"""Fixed pack ranges and revisioned reading state; catalogue reads never open media."""

import hashlib
import json
import random
import time

from sqlalchemy import func, select

from .catalog_selection import membership
from .errors import LibraryError
from .management_history import reject_historical
from .models import (
    ImagePack,
    PackPage,
    PackPreferences,
    PackProgress,
    PackSession,
    PackSessionEntry,
    RecentEntry,
    RequestRecord,
    Setting,
)
from .requests import once

DEFAULTS = {"mode": "horizontal", "direction": "ltr", "gap": False, "fit": "contain"}


class Reading:
    def __init__(self, db, packs):
        self.db, self.packs = db, packs

    @staticmethod
    def get(session, identity):
        value = session.get(PackSession, identity)
        if not value:
            raise LibraryError("pack_session_not_found", "阅读范围不存在，请从来源重新进入", 404)
        return value

    def eligible(self, session, value):
        # Only current availability can remove fixed members, never entry filters.
        available = self.packs.statement(session).with_only_columns(ImagePack.id)
        return select(PackSessionEntry).where(
            PackSessionEntry.session_id == value.id,
            PackSessionEntry.pack_id.in_(available),
        )

    def current(self, session, value):
        entries = self.eligible(session, value)
        return session.scalar(
            entries.where(PackSessionEntry.ordinal >= value.cursor)
            .order_by(PackSessionEntry.ordinal)
            .limit(1)
        ) or session.scalar(
            entries.where(PackSessionEntry.ordinal < value.cursor)
            .order_by(PackSessionEntry.ordinal.desc())
            .limit(1)
        )

    @staticmethod
    def defaults_in(session):
        row = session.get(Setting, "reader_defaults")
        return json.loads(row.value) if row else {**DEFAULTS, "revision": 0}

    def preferences_in(self, session, pack_id):
        row = session.get(PackPreferences, pack_id)
        return (
            {
                **{key: getattr(row, key) for key in DEFAULTS},
                "revision": row.revision,
                "overridden": True,
            }
            if row
            else {
                **{
                    key: value
                    for key, value in self.defaults_in(session).items()
                    if key in DEFAULTS
                },
                "revision": 0,
                "overridden": False,
            }
        )

    def state(self, session, pack):
        saved = session.get(PackProgress, pack.id)
        statement = self.packs.page_statement(session, pack.id)
        readable = statement.where(PackPage.error.is_(None))
        selected = (
            session.scalar(readable.where(PackPage.id == saved.page_id))
            if saved and saved.page_id
            else None
        )
        reason = saved.recovery_reason if saved else None
        if selected is None:
            prior = session.get(PackPage, saved.page_id) if saved and saved.page_id else None
            selected = (
                session.scalar(
                    readable.order_by(
                        func.abs(PackPage.ordinal - prior.ordinal),
                        (PackPage.ordinal < prior.ordinal),
                        PackPage.id,
                    ).limit(1)
                )
                if prior
                else session.scalar(readable.order_by(PackPage.ordinal, PackPage.id).limit(1))
            )
            if saved and not reason:
                reason = "page_unreadable" if prior else "page_removed"
        # row ordinal is the scanner's contiguous manifest index; root policy may
        # partition that manifest, so derive the visible index from the same query.
        index = (
            session.scalar(
                select(func.count()).select_from(
                    statement.where(
                        (PackPage.ordinal < selected.ordinal)
                        | ((PackPage.ordinal == selected.ordinal) & (PackPage.id < selected.id))
                    ).subquery()
                )
            )
            if selected
            else None
        )
        same = saved and selected and saved.page_id == selected.id
        return {
            "page": self.packs.page_json(selected, pack.content_version) if selected else None,
            "page_index": index,
            "offset_ratio": saved.offset_ratio if same else 0,
            "completed": bool(saved and saved.completed and same),
            "revision": saved.revision if saved else 0,
            "content_version": pack.content_version,
            "recovery_reason": reason,
            "preferences": self.preferences_in(session, pack.id),
        }

    def summary(self, session, value):
        row = self.current(session, value)
        entries = self.eligible(session, value)

        def neighbor(direction):
            if not row:
                return None
            criteria = (
                PackSessionEntry.ordinal < row.ordinal
                if direction < 0
                else PackSessionEntry.ordinal > row.ordinal
            )
            order = PackSessionEntry.ordinal.desc() if direction < 0 else PackSessionEntry.ordinal
            item = session.scalar(entries.where(criteria).order_by(order).limit(1))
            return {"pack_id": item.pack_id, "ordinal": item.ordinal} if item else None

        pack = session.get(ImagePack, row.pack_id) if row else None
        return {
            "id": value.id,
            "revision": value.revision,
            "scope": value.scope,
            "source": value.source,
            "order": value.order,
            "candidate_count": value.candidate_count,
            "available_count": session.scalar(select(func.count()).select_from(entries.subquery())),
            "cursor": row.ordinal if row else None,
            "finished": value.finished or row is None,
            "current": self.packs.summary(session, pack) if pack else None,
            "resume": self.state(session, pack) if pack else None,
            "previous": neighbor(-1),
            "next": neighbor(1),
        }

    def create(self, *, scope, source, sort, order, anchor_pack_id, request_id):
        scope = {**scope, "tag_ids": sorted(set(scope.get("tag_ids", [])))}
        payload = {
            "scope": scope,
            "source": source,
            "sort": sort,
            "order": order,
            "anchor": anchor_pack_id,
        }
        fingerprint = hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()
        with self.db.write() as session:
            prior = session.scalar(select(PackSession).where(PackSession.request_id == request_id))
            if prior:
                reject_historical(session, "pack_sessions", request_id)
                if prior.request_hash != fingerprint:
                    raise LibraryError("idempotency_conflict", "请求标识已用于不同的阅读范围")
                return self.summary(session, prior)
            reject_historical(session, "pack_sessions", request_id)
            ids = membership(
                session,
                self.packs.statement(session, source=source, sort=sort, **scope),
                ImagePack.id,
                "pack",
            )["ids"]
            if anchor_pack_id and anchor_pack_id not in ids:
                raise LibraryError("pack_outside_scope", "该图包不在当前阅读范围内", 422)
            if order == "random":
                random.SystemRandom().shuffle(ids)
            value = PackSession(
                request_id=request_id,
                request_hash=fingerprint,
                scope=scope,
                source={"kind": source, "sort": sort},
                order=order,
                cursor=ids.index(anchor_pack_id) if anchor_pack_id else 0,
                candidate_count=len(ids),
                finished=not ids,
            )
            session.add(value)
            session.flush()
            session.add_all(
                PackSessionEntry(session_id=value.id, ordinal=i, pack_id=identity)
                for i, identity in enumerate(ids)
            )
            pointer = session.get(Setting, "active_pack_session")
            if pointer:
                pointer.value = value.id
            else:
                session.add(Setting(key="active_pack_session", value=value.id))
            session.flush()
            return self.summary(session, value)

    def read(self, identity):
        with self.db.read() as session:
            session.connection().exec_driver_sql("BEGIN")
            return self.summary(session, self.get(session, identity))

    def entries(self, identity, offset, limit):
        with self.db.read() as session:
            session.connection().exec_driver_sql("BEGIN")
            value = self.get(session, identity)
            rows = list(
                session.scalars(
                    select(PackSessionEntry)
                    .where(PackSessionEntry.session_id == identity)
                    .order_by(PackSessionEntry.ordinal)
                    .offset(offset)
                    .limit(limit)
                )
            )
            page_ids = [row.pack_id for row in rows]
            available = set(
                session.scalars(
                    self.eligible(session, value)
                    .where(PackSessionEntry.pack_id.in_(page_ids))
                    .with_only_columns(PackSessionEntry.pack_id)
                )
            )
            return {
                "items": [
                    {
                        "ordinal": row.ordinal,
                        "pack": self.packs.summary(session, session.get(ImagePack, row.pack_id)),
                        "available": row.pack_id in available,
                    }
                    for row in rows
                ],
                "total": value.candidate_count,
                "offset": offset,
                "limit": limit,
                "revision": value.revision,
            }

    def active(self, session, identity, revision, pack_id=None):
        value = self.get(session, identity)
        pointer = session.get(Setting, "active_pack_session")
        if not pointer or pointer.value != identity:
            raise LibraryError("pack_session_replaced", "阅读范围已切换，请重新进入当前图包")
        if revision != value.revision:
            raise LibraryError("pack_session_changed", "阅读范围位置已更新，请重新读取")
        if pack_id:
            current = self.current(session, value)
            if value.finished or not current or current.pack_id != pack_id:
                raise LibraryError("pack_position_changed", "当前图包已切换，未保存旧图包状态")
        return value

    def position(self, identity, *, expected_revision, pack_id, finish, request_id):
        payload = {
            "id": identity,
            "revision": expected_revision,
            "pack_id": pack_id,
            "finish": finish,
        }
        with self.db.write() as session:

            def action():
                value = self.active(session, identity, expected_revision)
                if not finish:
                    row = session.scalar(
                        self.eligible(session, value).where(PackSessionEntry.pack_id == pack_id)
                    )
                    if not row:
                        raise LibraryError("pack_outside_scope", "该图包不在当前可读范围内", 422)
                    value.cursor = row.ordinal
                value.finished, value.revision = finish, value.revision + 1
                session.flush()
                return self.summary(session, value)

            return once(session, "pack_session.position", request_id, payload, action)

    def write_state(self, identity, pack_id, *, opened=False, **body):
        payload = {"session_id": identity, "pack_id": pack_id, **body}
        with self.db.write() as session:

            def action():
                value = self.active(session, identity, body["expected_session_revision"], pack_id)
                pack = session.get(ImagePack, pack_id)
                if pack.content_version != body["content_version"]:
                    raise LibraryError("pack_changed", "图包页清单已变化，请重新读取")
                page = session.scalar(
                    self.packs.page_statement(session, pack_id).where(
                        PackPage.id == body["page_id"], PackPage.error.is_(None)
                    )
                )
                if not page:
                    raise LibraryError("page_unavailable", "该图片已不可读，未修改阅读位置", 422)
                progress = session.get(PackProgress, pack_id)
                if (progress.revision if progress else 0) != body["expected_revision"]:
                    raise LibraryError("pack_progress_changed", "阅读进度已更新，未覆盖较新位置")
                if opened:
                    current = self.current(session, value)
                    if value.cursor != current.ordinal:
                        value.cursor = current.ordinal
                        value.revision += 1
                lease = session.get(Setting, "active_pack_opened")
                owner = {
                    "session_id": identity,
                    "pack_id": pack_id,
                    "revision": value.revision,
                }
                if not opened and (not lease or json.loads(lease.value) != owner):
                    raise LibraryError("pack_not_opened", "尚未实际打开当前图包，不能保存进度", 422)
                if not opened and not progress:
                    raise LibraryError("pack_not_opened", "尚未实际打开图包，不能保存进度", 422)
                if not progress:
                    progress = PackProgress(
                        pack_id=pack_id,
                        page_id=page.id,
                        revision=0,
                        completed=False,
                        offset_ratio=0,
                    )
                    session.add(progress)
                if not opened:
                    progress.offset_ratio, progress.completed = (
                        body["offset_ratio"],
                        body["completed"],
                    )
                elif progress.page_id != page.id:
                    progress.offset_ratio, progress.completed = 0, False
                progress.page_id, progress.content_version = page.id, pack.content_version
                progress.recovery_reason = None
                progress.revision += 1
                progress.updated_at = time.time()
                if opened:
                    if lease:
                        lease.value = json.dumps(owner)
                    else:
                        session.add(Setting(key="active_pack_opened", value=json.dumps(owner)))
                    recent = session.scalar(
                        select(RecentEntry).where(RecentEntry.pack_id == pack_id)
                    )
                    if recent:
                        recent.opened_at = time.time()
                    else:
                        session.add(RecentEntry(kind="pack", pack_id=pack_id))
                    if not session.get(PackPreferences, pack_id):
                        session.add(
                            PackPreferences(
                                pack_id=pack_id,
                                **{
                                    key: val
                                    for key, val in self.defaults_in(session).items()
                                    if key in DEFAULTS
                                },
                            )
                        )
                session.flush()
                return {**self.state(session, pack), "session_revision": value.revision}

            return once(
                session,
                "pack.opened" if opened else "pack.progress",
                body["request_id"],
                payload,
                action,
            )

    def preferences(
        self,
        pack_id,
        *,
        session_id,
        expected_session_revision,
        expected_revision,
        values,
        request_id,
    ):
        payload = {
            "pack_id": pack_id,
            "session_id": session_id,
            "session_revision": expected_session_revision,
            "revision": expected_revision,
            "values": values,
        }
        with self.db.write() as session:

            def action():
                self.active(session, session_id, expected_session_revision, pack_id)
                row = session.get(PackPreferences, pack_id)
                if (row.revision if row else 0) != expected_revision:
                    raise LibraryError("pack_preferences_changed", "本包阅读设置已更新，请重新读取")
                if not row:
                    row = PackPreferences(pack_id=pack_id, revision=0)
                    session.add(row)
                for key, val in values.items():
                    setattr(row, key, val)
                row.revision += 1
                session.flush()
                return self.preferences_in(session, pack_id)

            return once(session, "pack.preferences", request_id, payload, action)

    def defaults(self, *, values=None, expected_revision=None, request_id=None):
        if values is None:
            with self.db.read() as session:
                return self.defaults_in(session)
        with self.db.write() as session:

            def action():
                current = self.defaults_in(session)
                if current["revision"] != expected_revision:
                    raise LibraryError("reader_defaults_changed", "默认阅读设置已更新，请重新读取")
                result = {**values, "revision": expected_revision + 1}
                row = session.get(Setting, "reader_defaults")
                if row:
                    row.value = json.dumps(result)
                else:
                    session.add(Setting(key="reader_defaults", value=json.dumps(result)))
                return result

            return once(
                session,
                "reader.defaults",
                request_id,
                {"revision": expected_revision, "values": values},
                action,
            )

    def receipt(self, kind, request_id):
        with self.db.read() as session:
            session.connection().exec_driver_sql("BEGIN")
            if kind == "session":
                value = session.scalar(
                    select(PackSession).where(PackSession.request_id == request_id)
                )
                result = self.summary(session, value) if value else None
            else:
                namespace = {
                    "position": "pack_session.position",
                    "opened": "pack.opened",
                    "progress": "pack.progress",
                    "preferences": "pack.preferences",
                    "defaults": "reader.defaults",
                }[kind]
                record = session.get(RequestRecord, namespace + ":" + request_id)
                result = record.result if record else None
            if result is None:
                raise LibraryError(
                    "reading_request_not_found", "尚无该阅读操作回执，请确认状态后重试原请求", 404
                )
            return {"status": "completed", "result": result}

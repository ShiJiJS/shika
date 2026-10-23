import hashlib
import json
import random
import time

from sqlalchemy import delete, select

from .errors import LibraryError
from .library_state import prepared
from .models import PlaybackRound, RecentEntry, RoundEntry, Setting, Video, uid
from .requests import once


class Playback:
    def __init__(self, db, catalog, streams):
        self.db, self.catalog, self.streams = db, catalog, streams

    def eligible(self, session, round):
        # Fixed sessions only drop currently unavailable members. Entry filters
        # were evaluated once at creation; editing tags cannot change membership.
        scope = {} if round.membership == "fixed" else round.scope
        try:
            candidates = (
                self.catalog.video_statement(session, **scope)
                .with_only_columns(Video.id)
                .subquery()
            )
        except LibraryError as error:
            if error.code == "directory_not_found":
                return []
            raise
        return list(
            session.execute(
                select(RoundEntry.ordinal, RoundEntry.video_id)
                .where(
                    RoundEntry.round_id == round.id,
                    RoundEntry.video_id.in_(select(candidates.c.id)),
                )
                .order_by(RoundEntry.ordinal)
            )
        )

    def create(self, order, scope, anchor_video_id=None, request_id=None, **context):
        with self.db.write() as session:
            return self.create_in_session(
                session, order, scope, anchor_video_id, request_id, **context
            )

    def create_in_session(
        self,
        session,
        order,
        scope,
        anchor_video_id=None,
        request_id=None,
        *,
        allow_missing_scope=False,
        membership="legacy",
        source="library",
        sort="path",
    ):
        payload = {"order": order, "scope": scope, "anchor": anchor_video_id}
        if membership == "fixed":
            payload.update(membership=membership, source=source, sort=sort)
        request_hash = hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()
        request_id = request_id or uid()
        previous = session.scalar(
            select(PlaybackRound).where(PlaybackRound.request_id == request_id)
        )
        if previous:
            if previous.request_hash != request_hash:
                raise LibraryError("idempotency_conflict", "请求标识已用于不同的轮次操作")
            return self.summary(session, previous)
        try:
            candidates = list(
                session.scalars(
                    self.catalog.ordered_videos(
                        session, source=source, sort=sort, **scope
                    ).with_only_columns(Video.id)
                )
            )
        except LibraryError as error:
            if not allow_missing_scope or error.code != "directory_not_found":
                raise
            candidates = []
        if not prepared(session):
            if membership == "fixed":
                raise LibraryError("library_preparing", "视频首扫尚未完成，请稍后进入预览", 409)
            candidates = []
        if anchor_video_id and anchor_video_id not in candidates:
            raise LibraryError("video_outside_scope", "该视频不在当前可播放范围内", 422)
        source_ordinals = {video_id: i for i, video_id in enumerate(candidates)}
        if order == "random":
            random.SystemRandom().shuffle(candidates)
        round = PlaybackRound(
            request_id=request_id,
            request_hash=request_hash,
            order=order,
            scope=scope,
            membership=membership,
            source=source,
            sort=sort,
            cursor=candidates.index(anchor_video_id) if anchor_video_id else 0,
            candidate_count=len(candidates),
            finished=not candidates,
        )
        session.add(round)
        session.flush()
        session.add_all(
            RoundEntry(
                round_id=round.id,
                ordinal=i,
                video_id=video_id,
                source_ordinal=source_ordinals[video_id] if membership == "fixed" else None,
            )
            for i, video_id in enumerate(candidates)
        )
        pointer = session.get(Setting, "active_round")
        if pointer:
            pointer.value = round.id
        else:
            session.add(Setting(key="active_round", value=round.id))
        session.flush()
        refresh = session.get(Setting, "library_round_refresh")
        if refresh and prepared(session):
            session.delete(refresh)
        return self.summary(session, round)

    def current(self, *, create=True):
        with self.db.write_lock:
            with self.db.read() as session:
                pointer = session.get(Setting, "active_round")
                active = pointer.value if pointer else None
            if not active:
                if not create:
                    raise LibraryError("round_not_started", "请从媒体库选择范围开始预览", 404)
                return self.create("random", {})
            with self.db.write() as session:
                round = self.get(session, active)
                refresh = session.get(Setting, "library_round_refresh")
                if refresh and round.membership == "fixed":
                    session.delete(refresh)
                elif refresh and refresh.value and prepared(session):
                    session.delete(refresh)
                    try:
                        expected = set(
                            session.scalars(
                                self.catalog.video_statement(
                                    session, **round.scope
                                ).with_only_columns(Video.id)
                            )
                        )
                    except LibraryError as error:
                        if error.code != "directory_not_found":
                            raise
                        expected = set()
                    actual = {video_id for _ordinal, video_id in self.eligible(session, round)}
                    if actual != expected:
                        return self.create_in_session(
                            session, round.order, round.scope, allow_missing_scope=True
                        )
                return self.summary(session, round)

    @staticmethod
    def get(session, round_id):
        round = session.get(PlaybackRound, round_id)
        if not round:
            raise LibraryError("round_not_found", "播放轮次不存在", 404)
        return round

    def playable(self, session, entries):
        # Validate the selected/adjacent files against the current filesystem.
        return [
            (ordinal, video_id)
            for ordinal, video_id in entries
            if self.streams.can_play(session, session.get(Video, video_id))
        ]

    def summary(self, session, round):
        ready = prepared(session)
        entries = self.eligible(session, round) if ready else []
        cursor = next((i for i, row in enumerate(entries) if row[0] >= round.cursor), len(entries))
        selected = None
        for i in range(cursor, len(entries)):
            if self.streams.can_play(session, session.get(Video, entries[i][1])):
                selected = i
                break
        if selected is None and entries:
            # At exhaustion keep the last remaining video looping, as the client
            # already does; starting another round is an explicit operation.
            for i in range(min(cursor, len(entries) - 1), -1, -1):
                if self.streams.can_play(session, session.get(Video, entries[i][1])):
                    selected = i
                    break
            round.finished = True
        if selected is not None and entries[selected][0] != round.cursor:
            round.cursor = entries[selected][0]
            round.revision += 1
        window = []
        if selected is not None:
            neighbors = [selected]
            for direction in (-1, 1):
                i = selected + direction
                while 0 <= i < len(entries):
                    if self.streams.can_play(session, session.get(Video, entries[i][1])):
                        neighbors.append(i)
                        break
                    i += direction
            for i in sorted(neighbors):
                window.append(
                    {
                        "position": i,
                        "video": self.catalog.video_json(session.get(Video, entries[i][1])),
                    }
                )
        pointer = session.get(Setting, "active_round")
        return {
            "id": round.id,
            "library_locked": not ready,
            "active": bool(pointer and pointer.value == round.id),
            "order": round.order,
            "scope": round.scope,
            "membership": round.membership,
            "source": round.source,
            "sort": round.sort,
            "sequence_revision": round.sequence_revision,
            "position": selected or 0,
            "total": len(entries),
            "candidate_count": round.candidate_count,
            "revision": round.revision,
            "finished": round.finished or selected is None,
            "current": self.catalog.video_json(session.get(Video, entries[selected][1]))
            if selected is not None
            else None,
            "window": window,
        }

    def move(self, round_id, expected_revision, video_id=None, finish=False):
        with self.db.write() as session:
            round = self.get(session, round_id)
            pointer = session.get(Setting, "active_round")
            if not pointer or pointer.value != round.id:
                raise LibraryError("round_replaced", "播放范围已变化，请刷新当前轮次")
            entries = self.eligible(session, round)
            target = (
                next((row for row in entries if row[1] == video_id), None) if video_id else None
            )
            if video_id and (
                not target or not self.streams.can_play(session, session.get(Video, video_id))
            ):
                raise LibraryError("video_unavailable", "该视频已不在当前可播放范围内")
            already_applied = (target and target[0] == round.cursor and not round.finished) or (
                finish and round.finished
            )
            if expected_revision != round.revision and not already_applied:
                raise LibraryError("round_conflict", "轮次位置已变化，请刷新后重试")
            if finish:
                remaining = self.playable(session, entries)
                if remaining and round.cursor != remaining[-1][0]:
                    raise LibraryError("round_not_exhausted", "本轮还有未播放的视频")
                if not round.finished:
                    round.finished, round.revision = True, round.revision + 1
            elif target:
                if round.cursor != target[0] or round.finished:
                    round.cursor, round.finished, round.revision = (
                        target[0],
                        False,
                        round.revision + 1,
                    )
            return self.summary(session, round)

    def entries(self, round_id, offset, limit):
        with self.db.read() as session:
            session.connection().exec_driver_sql("BEGIN")
            round = self.get(session, round_id)
            entries = self.eligible(session, round)
            return {
                "items": [
                    {"position": i, "video": self.catalog.video_json(session.get(Video, video_id))}
                    for i, (_ordinal, video_id) in enumerate(
                        entries[offset : offset + limit], start=offset
                    )
                ],
                "offset": offset,
                "limit": limit,
                "total": len(entries),
            }

    def active_fixed(self, session, round_id, expected_revision):
        round = self.get(session, round_id)
        pointer = session.get(Setting, "active_round")
        if not pointer or pointer.value != round.id:
            raise LibraryError("round_replaced", "播放范围已变化，请返回当前预览")
        if round.membership != "fixed":
            raise LibraryError("fixed_session_required", "此操作需要从媒体库重新进入预览", 422)
        if round.revision != expected_revision:
            raise LibraryError("round_conflict", "预览位置已变化，请刷新后重试")
        return round

    def reorder(self, round_id, order, expected_revision, request_id, *, restart=False):
        """Reorder the stored members; never rerun the original filters."""
        with self.db.write() as session:

            def action():
                round = self.active_fixed(session, round_id, expected_revision)
                entries = list(
                    session.scalars(
                        select(RoundEntry)
                        .where(RoundEntry.round_id == round.id)
                        .order_by(RoundEntry.ordinal)
                    )
                )
                selected = next(
                    (entry.video_id for entry in entries if entry.ordinal == round.cursor), None
                )
                members = [(entry.video_id, entry.source_ordinal) for entry in entries]
                if order == "random":
                    random.SystemRandom().shuffle(members)
                else:
                    members.sort(key=lambda item: item[1])
                session.execute(
                    delete(RoundEntry)
                    .where(RoundEntry.round_id == round.id)
                    .execution_options(synchronize_session=False)
                )
                # Clear deleted identities before reusing composite ordinal keys.
                for entry in entries:
                    session.expunge(entry)
                session.add_all(
                    RoundEntry(
                        round_id=round.id, ordinal=i, video_id=video_id, source_ordinal=baseline
                    )
                    for i, (video_id, baseline) in enumerate(members)
                )
                round.cursor = (
                    0
                    if restart
                    else next(
                        (i for i, (video_id, _) in enumerate(members) if video_id == selected), 0
                    )
                )
                round.order, round.revision = order, round.revision + 1
                round.sequence_revision += 1
                round.finished = not members
                session.flush()
                return self.summary(session, round)

            return once(
                session,
                "preview.order",
                request_id,
                {"id": round_id, "order": order, "revision": expected_revision, "restart": restart},
                action,
            )

    def opened(self, round_id, video_id, expected_revision, request_id):
        """Only a visible selection acknowledges an open; prefetch/GET never do."""
        with self.db.write() as session:

            def action():
                round = self.active_fixed(session, round_id, expected_revision)
                entry = session.scalar(
                    select(RoundEntry).where(
                        RoundEntry.round_id == round.id,
                        RoundEntry.ordinal == round.cursor,
                        RoundEntry.video_id == video_id,
                    )
                )
                if not entry or not self.streams.can_play(session, session.get(Video, video_id)):
                    raise LibraryError("video_unavailable", "该视频已不是当前可观看内容")
                recent = session.scalar(select(RecentEntry).where(RecentEntry.video_id == video_id))
                if not recent:
                    recent = RecentEntry(kind="video", video_id=video_id)
                    session.add(recent)
                recent.opened_at = time.time()
                session.flush()
                return {"video_id": video_id, "opened_at": recent.opened_at}

            return once(
                session,
                "preview.opened",
                request_id,
                {"id": round_id, "video_id": video_id, "revision": expected_revision},
                action,
            )

"""Durable whole-pack logical operations; media bytes never move in this module."""

import hashlib
import json
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from sqlalchemy import func, or_, select

from .catalog_selection import membership
from .errors import LibraryError
from .models import (
    ImagePack,
    PackFileOperation,
    PackFileStep,
    PackPage,
    PackPreferences,
    PackProgress,
    PackSession,
    PackSessionEntry,
    PackTrashItem,
    RequestRecord,
    Root,
    Setting,
    Task,
)
from .pack_scanner import reserved_packs
from .requests import once


class PackOperations:
    undo_seconds = 8

    def __init__(self, db, packs, reading, *, clock=time.time, fault_hook=None):
        self.db, self.packs, self.reading = db, packs, reading
        self.clock, self.fault_hook = clock, fault_hook
        self.stop = threading.Event()
        self.lock = threading.RLock()
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="pack-operations")
        self.futures = {}
        self.purge = None

    def start(self):
        with self.db.write() as session:
            ids = list(
                session.scalars(
                    select(PackFileOperation.id)
                    .join(Task)
                    .where(
                        PackFileOperation.historical.is_(False),
                        or_(
                            Task.status.in_(("queued", "running", "interrupted")),
                            Task.error == "operation_recovery_required",
                        ),
                    )
                    .order_by(Task.created_at, Task.id)
                )
            )
            # Publish recovery before accepting HTTP reads. A client must not mistake
            # the previous process's interrupted status for this process's final result.
            for identity in ids:
                task = session.get(Task, identity)
                task.status, task.error = "queued", None
        for identity in ids:
            self.enqueue(identity)

    def enqueue(self, identity):
        with self.lock:
            future = self.futures.get(identity)
            if not future or future.done():
                self.futures[identity] = self.executor.submit(self.run, identity)

    @staticmethod
    def pointer(session, key):
        row = session.get(Setting, key)
        return row.value if row else None

    @staticmethod
    def set_pointer(session, key, value):
        row = session.get(Setting, key)
        if row:
            row.value = value
        else:
            session.add(Setting(key=key, value=value))

    def reading_snapshot(self, session, scene):
        if not scene:
            return None
        value = self.reading.active(
            session, scene["session_id"], scene["expected_session_revision"], scene["pack_id"]
        )
        pack = session.get(ImagePack, scene["pack_id"])
        saved = session.get(PackProgress, pack.id)
        lease = session.get(Setting, "active_pack_opened")
        owner = {"session_id": value.id, "pack_id": pack.id, "revision": value.revision}
        if not lease or json.loads(lease.value) != owner or not saved:
            raise LibraryError("pack_not_opened", "请实际打开并保存当前图包后再整理", 422)
        if (
            pack.content_version != scene["content_version"]
            or saved.revision != scene["expected_progress_revision"]
        ):
            raise LibraryError("pack_changed", "图包或阅读位置已变化，请先保存并重新读取")
        prefs = session.get(PackPreferences, pack.id)
        return {
            **scene,
            "cursor": value.cursor,
            "finished": value.finished,
            "page_id": saved.page_id,
            "offset_ratio": saved.offset_ratio,
            "preferences_revision": prefs.revision if prefs else 0,
        }

    def submit(self, kind, ids, request_id, *, scene=None, undo_of=None):
        if kind not in ("trash", "restore", "undo"):
            raise LibraryError("unsupported_pack_operation", "该图包操作尚不支持", 422)
        ids = sorted(set(ids))
        if kind != "undo" and not 1 <= len(ids) <= 1000:
            raise LibraryError("invalid_pack_operation", "每次请选择1至1000项", 422)
        payload = {"kind": kind, "ids": ids, "reading": scene, "undo_of": undo_of}
        digest = hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()
        key = "pack_files:" + request_id
        # A known command remains readable during maintenance, without enqueueing.
        with self.db.read() as session:
            prior = session.scalar(
                select(PackFileOperation).where(PackFileOperation.request_key == key)
            )
            if prior:
                if prior.request_hash != digest:
                    raise LibraryError("idempotency_conflict", "请求标识已用于不同的图包操作")
                return prior.id
        if self.stop.is_set():
            raise LibraryError("service_stopping", "服务正在停止", 503)
        with self.db.write() as session:
            prior = session.scalar(
                select(PackFileOperation).where(PackFileOperation.request_key == key)
            )
            if prior:
                if prior.request_hash != digest:
                    raise LibraryError("idempotency_conflict", "请求标识已用于不同的图包操作")
                return prior.id
            if scene and (kind != "trash" or ids != [scene["pack_id"]]):
                raise LibraryError("invalid_pack_cleanup", "阅读整理一次只能操作当前整包", 422)
            if kind == "undo":
                original = session.get(PackFileOperation, undo_of)
                if (
                    not original
                    or original.historical
                    or original.kind != "trash"
                    or self.pointer(session, "last_pack_delete_operation") != undo_of
                ):
                    raise LibraryError("stale_delete", "这次图包撤销已失效，请在回收站查看")
                committed = original.session_snapshot.get("committed_at")
                if committed is None or self.clock() > committed + self.undo_seconds:
                    raise LibraryError("undo_expired", "撤销时间已过，请在回收站恢复")
                ids = list(
                    session.scalars(
                        select(PackTrashItem.id).where(
                            PackTrashItem.operation_id == undo_of, PackTrashItem.status == "active"
                        )
                    )
                )
                if not ids:
                    raise LibraryError("stale_delete", "这次回收已恢复或不存在")
            snapshot = {"reading": self.reading_snapshot(session, scene), "prepared": {}}
            task = Task(kind="pack_" + kind, status="queued", phase="queued", result={})
            session.add(task)
            session.flush()
            operation = PackFileOperation(
                id=task.id,
                kind=kind,
                request_key=key,
                request_hash=digest,
                undo_of=undo_of,
                session_snapshot={},
                historical=False,
            )
            session.add(operation)
            session.flush()
            for requested in ids:
                item = session.get(PackTrashItem, requested) if kind != "trash" else None
                pack = session.get(ImagePack, item.pack_id if item else requested)
                root = session.get(Root, pack.root_id) if pack else None
                if (
                    not pack
                    or not root
                    or root.kind != "pack"
                    or (kind != "trash" and item is None)
                ):
                    raise LibraryError("pack_operation_item_not_found", "图包或回收记录不存在", 404)
                step = PackFileStep(
                    operation_id=task.id,
                    pack_id=pack.id,
                    requested_id=requested,
                    root_path=root.path,
                    original_path=pack.path,
                )
                if session.scalar(reserved_packs().where(PackFileStep.pack_id == pack.id).limit(1)):
                    step.outcome, step.error = "failed", "operation_busy"
                elif (kind == "trash" and pack.status not in ("available", "missing")) or (
                    kind != "trash" and (item.status != "active" or pack.status != "trash")
                ):
                    step.outcome, step.error = "failed", "stale_pack_state"
                session.add(step)
                session.flush()
                snapshot["prepared"][step.id] = {
                    "status": pack.status,
                    "generation": pack.generation,
                    "version": pack.content_version,
                    "root_id": root.id,
                }
            operation.session_snapshot = snapshot
            if kind == "trash":
                # Acceptance, not worker completion, establishes causality.
                self.set_pointer(session, "last_pack_delete_operation", operation.id)
            identity = operation.id
        self.enqueue(identity)
        return identity

    def checkpoint(self, phase, identity):
        if self.fault_hook:
            self.fault_hook(phase, identity)

    def run(self, identity):
        with self.db.read() as session:
            operation = session.get(PackFileOperation, identity)
            if operation and operation.kind == "permanent":
                if self.purge is not None:
                    self.purge.run(identity)
                else:
                    self.failed(identity, "failed", "unsupported_pack_operation")
                return
        try:
            if self.stop.is_set():
                raise InterruptedError()
            with self.db.write() as session:
                operation = session.get(PackFileOperation, identity)
                if not operation or operation.historical:
                    return
                task = session.get(Task, identity)
                task.status, task.phase, task.error = "running", "logical_marks", None
            self.checkpoint("before_logical_commit", identity)
            with self.db.write() as session:
                if self.stop.is_set():
                    raise InterruptedError()
                operation = session.get(PackFileOperation, identity)
                snapshot = dict(operation.session_snapshot)
                steps = list(
                    session.scalars(
                        select(PackFileStep)
                        .where(PackFileStep.operation_id == identity)
                        .order_by(PackFileStep.id)
                    )
                )
                pending = [step for step in steps if step.outcome == "pending"]
                scene_error = None
                try:
                    if snapshot.get("reading"):
                        self.reading_snapshot(session, snapshot["reading"])
                    if (
                        operation.kind == "undo"
                        and self.pointer(session, "last_pack_delete_operation") != operation.undo_of
                    ):
                        raise LibraryError("stale_delete", "已有新的图包回收操作")
                except LibraryError as error:
                    scene_error = error.code
                successes = []
                for step in pending:
                    pack = session.get(ImagePack, step.pack_id)
                    prepared = snapshot["prepared"][step.id]
                    code = scene_error
                    if not pack or (
                        pack.path != step.original_path
                        or pack.root_id != prepared["root_id"]
                        or pack.status != prepared["status"]
                        or pack.generation != prepared["generation"]
                        or pack.content_version != prepared["version"]
                    ):
                        code = "stale_pack_state"
                    if code:
                        step.outcome, step.error = "failed", code
                        continue
                    if operation.kind == "trash":
                        pages = list(
                            session.scalars(
                                select(PackPage)
                                .where(PackPage.pack_id == pack.id)
                                .order_by(PackPage.ordinal, PackPage.id)
                            )
                        )
                        session.add(
                            PackTrashItem(
                                id=step.id,
                                pack_id=pack.id,
                                operation_id=identity,
                                root_path=step.root_path,
                                original_path=pack.path,
                                deleted_at=self.clock(),
                                status="active",
                                manifest={
                                    "schema": 1,
                                    "status": pack.status,
                                    "error": pack.error,
                                    "content_version": pack.content_version,
                                    "page_count": pack.page_count,
                                    "pages": [
                                        {
                                            "id": p.id,
                                            "path": p.path,
                                            "name": p.relative_path,
                                            "signature": p.signature,
                                            "sha256": p.sha256,
                                            "size": p.size,
                                        }
                                        for p in pages
                                    ],
                                },
                            )
                        )
                        pack.status = "trash"
                    else:
                        item = session.get(PackTrashItem, step.requested_id)
                        if not item or item.status != "active":
                            step.outcome, step.error = "failed", "stale_pack_state"
                            continue
                        pack.status, pack.error = item.manifest["status"], item.manifest["error"]
                        if item.purged_pages and pack.page_count == 0 and pack.status == "available":
                            pack.error = "no_readable_images"
                        item.status = "restored"
                    pack.generation += 1
                    step.phase, step.outcome, step.error = "committed", "succeeded", None
                    successes.append(pack.id)
                if successes:
                    session.flush()
                    snapshot.setdefault("committed_at", self.clock())
                    if operation.kind == "trash":
                        self.clear_lease(session, successes)
                        if snapshot.get("reading"):
                            if snapshot["reading"].get("advance", True):
                                snapshot["transition"] = self.advance(session, snapshot["reading"])
                            else:
                                value = session.get(PackSession, snapshot["reading"]["session_id"])
                                value.revision += 1
                                snapshot["return_state"] = {
                                    "revision": value.revision,
                                    "cursor": value.cursor,
                                    "finished": value.finished,
                                }
                    elif operation.kind == "undo":
                        snapshot["reading_restored"] = self.restore_reading(
                            session, operation, successes
                        )
                operation.session_snapshot = snapshot
            self.checkpoint("logical_committed", identity)
            self.finish(identity)
        except InterruptedError:
            self.failed(identity, "interrupted", "service_stopped")
        except Exception:
            self.failed(identity, "failed", "operation_recovery_required")

    @staticmethod
    def clear_lease(session, pack_ids=None):
        row = session.get(Setting, "active_pack_opened")
        if row and (pack_ids is None or json.loads(row.value).get("pack_id") in pack_ids):
            session.delete(row)

    def advance(self, session, scene):
        value = session.get(PackSession, scene["session_id"])
        following = session.scalar(
            self.reading.eligible(session, value)
            .where(PackSessionEntry.ordinal > scene["cursor"])
            .order_by(PackSessionEntry.ordinal)
            .limit(1)
        )
        value.cursor = following.ordinal if following else scene["cursor"]
        value.finished, value.revision = following is None, value.revision + 1
        return {
            "session_id": value.id,
            "revision": value.revision,
            "cursor": value.cursor,
            "pack_id": following.pack_id if following else None,
            "finished": value.finished,
        }

    def restore_reading(self, session, operation, restored):
        original = session.get(PackFileOperation, operation.undo_of)
        snapshot = original.session_snapshot
        scene = snapshot.get("reading")
        transition = snapshot.get("transition") or snapshot.get("return_state")
        if not scene or not transition or scene["pack_id"] not in restored:
            return False
        value = session.get(PackSession, scene["session_id"])
        saved = session.get(PackProgress, scene["pack_id"])
        prefs = session.get(PackPreferences, scene["pack_id"])
        pack = session.get(ImagePack, scene["pack_id"])
        if (
            not value
            or self.pointer(session, "active_pack_session") != value.id
            or value.revision != transition["revision"]
            or value.cursor != transition["cursor"]
            or value.finished != transition["finished"]
            or not saved
            or saved.revision != scene["expected_progress_revision"]
            or (prefs.revision if prefs else 0) != scene["preferences_revision"]
            or pack.content_version != scene["content_version"]
        ):
            return False
        available = session.scalar(
            self.reading.eligible(session, value).where(
                PackSessionEntry.pack_id == scene["pack_id"]
            )
        )
        if not available:
            return False
        value.cursor, value.finished = scene["cursor"], scene["finished"]
        value.revision += 1
        self.clear_lease(session)
        return True

    def finish(self, identity):
        with self.db.write() as session:
            operation = session.get(PackFileOperation, identity)
            steps = list(
                session.scalars(select(PackFileStep).where(PackFileStep.operation_id == identity))
            )
            successes = sum(step.outcome == "succeeded" for step in steps)
            snapshot = operation.session_snapshot
            task = session.get(Task, identity)
            task.status, task.phase = ("completed" if successes else "failed"), "completed"
            task.finished_at = snapshot.get("committed_at", self.clock())
            task.error = (
                None
                if successes
                else next((s.error for s in steps if s.error), "no_operations_completed")
            )
            task.result = {
                "operation_id": identity,
                "total": len(steps),
                "processed": len(steps),
                "succeeded": successes,
                "failed": len(steps) - successes,
                "partial": 0 < successes < len(steps),
                "items": [
                    {
                        "requested_id": s.requested_id,
                        "pack_id": s.pack_id,
                        "trash_id": s.id if operation.kind == "trash" else s.requested_id,
                        "outcome": s.outcome,
                        "phase": s.phase,
                        "error": s.error,
                    }
                    for s in steps
                ],
                "reading_transition": snapshot.get("transition"),
                "reading_restored": snapshot.get("reading_restored", False),
                "undo_expires_at": snapshot.get("committed_at", 0) + self.undo_seconds
                if operation.kind == "trash" and successes
                else None,
            }

    def failed(self, identity, status, error):
        with self.db.write() as session:
            task = session.get(Task, identity)
            task.status, task.error = status, error

    def task(self, identity=None, *, request_id=None):
        with self.db.read() as session:
            operation = (
                session.scalar(
                    select(PackFileOperation).where(
                        PackFileOperation.request_key == "pack_files:" + request_id
                    )
                )
                if request_id
                else session.get(PackFileOperation, identity)
            )
            if not operation:
                raise LibraryError("pack_operation_not_found", "未找到已受理的图包操作", 404)
            task = session.get(Task, operation.id)
            return {
                "server_time": self.clock(),
                **{
                    key: getattr(task, key)
                    for key in (
                        "id",
                        "kind",
                        "status",
                        "phase",
                        "created_at",
                        "finished_at",
                        "result",
                        "error",
                    )
                },
            }

    def retry(self, identity, request_id):
        with self.db.write() as session:
            operation = session.get(PackFileOperation, identity)
            if not operation or operation.historical:
                raise LibraryError("pack_operation_not_found", "图包操作不存在", 404)

            def action():
                task = session.get(Task, identity)
                if task.status not in ("queued", "running"):
                    for step in session.scalars(
                        select(PackFileStep).where(
                            PackFileStep.operation_id == identity,
                            PackFileStep.outcome != "succeeded",
                        )
                    ):
                        if session.scalar(
                            reserved_packs()
                            .where(
                                PackFileStep.pack_id == step.pack_id,
                                PackFileStep.operation_id != identity,
                            )
                            .limit(1)
                        ):
                            raise LibraryError("operation_busy", "该图包已有进行中的操作")
                        step.outcome, step.error = "pending", None
                    task.status, task.error, task.finished_at = "queued", None, None
                return {"operation_id": identity}

            result = once(session, "pack_files.retry", request_id, {"id": identity}, action)
            enqueue = session.get(Task, identity).status == "queued"
        if enqueue:
            self.enqueue(identity)
        return result["operation_id"]

    def retry_receipt(self, request_id):
        with self.db.read() as session:
            record = session.get(RequestRecord, "pack_files.retry:" + request_id)
            if not record:
                raise LibraryError("pack_operation_not_found", "未找到已受理的图包重试", 404)
            identity = record.result["operation_id"]
        return self.task(identity)

    @staticmethod
    def trash_statement(search):
        statement = select(PackTrashItem).join(ImagePack).where(PackTrashItem.status == "active")
        if search:
            statement = statement.where(
                ImagePack.name.contains(search, autoescape=True)
                | PackTrashItem.original_path.contains(search, autoescape=True)
            )
        return statement.order_by(PackTrashItem.deleted_at.desc(), PackTrashItem.id)

    def trash(self, offset, limit, search=""):
        with self.db.read() as session:
            statement = self.trash_statement(search)
            rows = session.scalars(statement.offset(offset).limit(limit))
            return {
                "items": [
                    {
                        "id": item.id,
                        "operation_id": item.operation_id,
                        "original_path": item.original_path,
                        "deleted_at": item.deleted_at,
                        "page_count": session.get(ImagePack, item.pack_id).page_count if item.purged_pages else item.manifest["page_count"],
                        "purged_pages": item.purged_pages,
                        "permanent_operation_id": session.scalar(
                            select(PackFileOperation.id)
                            .join(PackFileStep, PackFileStep.operation_id == PackFileOperation.id)
                            .join(Task, Task.id == PackFileOperation.id)
                            .where(
                                PackFileStep.pack_id == item.pack_id,
                                PackFileStep.requested_id == item.id,
                                PackFileOperation.kind == "permanent",
                                PackFileOperation.historical.is_(False),
                            )
                            .order_by(Task.created_at.desc(), Task.id.desc())
                            .limit(1)
                        ),
                        "pack": self.packs.summary(session, session.get(ImagePack, item.pack_id)),
                    }
                    for item in rows
                ],
                "total": session.scalar(select(func.count()).select_from(statement.subquery())),
                "offset": offset,
                "limit": limit,
            }

    def selection(self, search=""):
        with self.db.read() as session:
            return membership(session, self.trash_statement(search), PackTrashItem.id, "pack-trash")

    def close(self):
        self.stop.set()
        self.executor.shutdown(wait=True, cancel_futures=True)

"""Logical trash and durable physical purge/legacy recovery operations."""

import errno
import hashlib
import json
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from sqlalchemy import delete, func, or_, select

from .errors import LibraryError
from .file_state import (
    reserved_steps,
    set_video_signature,
    touch_active_scan,
    video_signature,
)
from .file_transfer import FileTransfer
from .models import (
    FileOperation,
    FileStep,
    PlaybackRound,
    Root,
    RoundEntry,
    Setting,
    Tag,
    Task,
    TrashItem,
    Video,
    VideoTag,
    uid,
)
from .paths import beneath, validate_path
from .requests import once


class FileOperations:
    def __init__(self, db, settings, catalog, playback, fault_hook=None):
        self.db, self.settings, self.catalog, self.playback = db, settings, catalog, playback
        self.fault_hook = fault_hook
        self.stop = threading.Event()
        self.queue_lock = threading.RLock()
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="file-operations")
        self.futures = {}
        self.transfer = FileTransfer(self.stop, self.checkpoint, self.validate_step)

    def start(self):
        with self.db.read() as session:
            recovering = list(
                session.scalars(
                    select(FileOperation.id)
                    .join(Task)
                    .where(
                        FileOperation.historical.is_(False),
                        or_(
                            Task.status.in_(["queued", "running", "interrupted"]),
                            Task.error == "operation_recovery_required",
                        ),
                    )
                    .order_by(Task.created_at)
                )
            )
        for operation_id in recovering:
            self.enqueue(operation_id)

    def enqueue(self, operation_id):
        with self.queue_lock:
            future = self.futures.get(operation_id)
            if not future or future.done():
                self.futures[operation_id] = self.executor.submit(self.run, operation_id)

    def snapshot_round(self, session):
        active = session.get(Setting, "active_round")
        round = session.get(PlaybackRound, active.value) if active else None
        if not round:
            return {}
        snapshot = {"id": round.id, "cursor": round.cursor, "finished": round.finished}
        if round.membership == "fixed":
            snapshot["video_id"] = session.scalar(
                select(RoundEntry.video_id).where(
                    RoundEntry.round_id == round.id, RoundEntry.ordinal == round.cursor
                )
            )
        return snapshot

    def submit(self, kind, ids, request_id, undo_of=None):
        if self.stop.is_set():
            raise LibraryError("service_stopping", "服务正在停止", 503)
        ids = sorted(set(ids))
        payload = {"kind": kind, "ids": ids, "undo_of": undo_of}
        digest = hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()
        key = "files:" + request_id
        with self.db.write() as session:
            previous = session.scalar(select(FileOperation).where(FileOperation.request_key == key))
            if previous:
                if previous.request_hash != digest:
                    raise LibraryError("idempotency_conflict", "请求标识已用于不同的文件操作")
                return previous.id
            if kind == "undo":
                original = session.get(FileOperation, undo_of)
                latest = session.get(Setting, "last_delete_operation")
                if (
                    not original
                    or original.kind != "trash"
                    or not latest
                    or latest.value != undo_of
                ):
                    raise LibraryError("stale_delete", "这次删除已失效，请在回收站查看")
                ids = list(
                    session.scalars(
                        select(TrashItem.id).where(
                            TrashItem.operation_id == undo_of, TrashItem.status == "active"
                        )
                    )
                )
                if not ids:
                    raise LibraryError("stale_delete", "该次删除已恢复或不存在")
            task = Task(kind=kind, status="queued", phase="queued", result={})
            session.add(task)
            session.flush()
            operation = FileOperation(
                id=task.id,
                request_key=key,
                request_hash=digest,
                kind=kind,
                undo_of=undo_of,
                round_snapshot=self.snapshot_round(session),
                historical=False,
            )
            session.add(operation)
            session.flush()
            for requested_id in ids:
                self.prepare_step(session, operation, requested_id)
            operation_id = operation.id
        self.enqueue(operation_id)
        return operation_id

    def prepare_step(self, session, operation, requested_id):
        item = None if operation.kind == "trash" else session.get(TrashItem, requested_id)
        video = (
            session.get(Video, requested_id if operation.kind == "trash" else item.video_id)
            if operation.kind == "trash" or item
            else None
        )
        step = FileStep(
            id=uid(),
            operation_id=operation.id,
            requested_id=requested_id,
            video_id=video.id if video else None,
        )
        session.add(step)
        if not video or (operation.kind != "trash" and (not item or item.status != "active")):
            step.outcome, step.error = "failed", "item_not_found"
            return
        if session.scalar(
            reserved_steps().where(FileStep.video_id == video.id, FileStep.id != step.id).limit(1)
        ):
            step.outcome, step.error = "conflict", "operation_busy"
            return
        if operation.kind == "trash" and video.status != "available":
            step.outcome, step.error = "failed", "video_unavailable"
            return
        root = session.get(Root, video.root_id)
        step.original_status, step.root_path, step.original_path = (
            video.status,
            item.root_path if item else root.path,
            item.original_path if item else video.path,
        )
        step.expected_hash, step.expected_size, step.source_signature = (
            video.sha256,
            video.size,
            video_signature(video),
        )
        if operation.kind == "trash":
            step.trash_id = uid()
            step.source = video.path
            # Equal paths encode a logical trash receipt in the existing schema.
            # Old durable intents retain different paths and their recovery logic.
            step.destination = step.source
        else:
            step.trash_id, step.source = item.id, item.trash_path
            step.destination = "" if operation.kind == "permanent" else item.original_path
        step.staging = str(Path(step.source).parent / ".video-viewer-tmp" / step.id)
        step.copy_path = (
            str(Path(step.destination).parent / ".video-viewer-tmp" / (step.id + ".part"))
            if step.destination
            else ""
        )
        video.generation += 1
        video.error = "file_operation_pending"
        touch_active_scan(session, video)

    def validate_step(self, step, kind):
        with self.db.read() as session:
            video = session.get(Video, step.video_id)
            item = session.get(TrashItem, step.trash_id) if kind != "trash" else None
            if (
                not video
                or video.status != step.original_status
                or (kind != "trash" and (not item or item.status != "active"))
            ):
                raise LibraryError("stale_operation", "文件状态已变化，请刷新后重新操作")
        root_path = Path(step.root_path)
        validate_path(str(root_path), self.settings.mounts)
        if kind == "trash":
            validate_path(step.source, self.settings.mounts)
            if not beneath(Path(step.source), root_path):
                raise LibraryError("path_outside_scope", "源文件不在媒体目录内")
        else:
            allowed_trash = self.settings.trash_dir or root_path / ".video-viewer-trash"
            logical = item.trash_path == item.original_path
            if logical:
                validate_path(step.source, self.settings.mounts)
                if step.source != item.original_path or not beneath(Path(step.source), root_path):
                    raise LibraryError("path_outside_scope", "文件不在原媒体目录内")
            elif not beneath(Path(step.source), allowed_trash):
                raise LibraryError("path_outside_scope", "回收站文件不在受控范围内")
        if step.staging != str(Path(step.source).parent / ".video-viewer-tmp" / step.id):
            raise LibraryError("invalid_intent", "文件操作记录不合法")
        if kind != "permanent":
            if kind == "trash":
                expected = (
                    (self.settings.trash_dir or root_path / ".video-viewer-trash")
                    / step.trash_id
                    / Path(step.source).name
                )
                if Path(step.destination) != expected:
                    raise LibraryError("invalid_intent", "回收路径不合法")
            else:
                validate_path(step.destination, self.settings.mounts)
                with self.db.read() as session:
                    roots = list(session.scalars(select(Root)))
                if not any(beneath(Path(step.destination), Path(root.path)) for root in roots):
                    raise LibraryError(
                        "restore_outside_library", "原目录已调整，请先重新接入后恢复"
                    )
            if step.copy_path != str(
                Path(step.destination).parent / ".video-viewer-tmp" / (step.id + ".part")
            ):
                raise LibraryError("invalid_intent", "复制临时路径不合法")
        # Resolve/open checks apply at each filesystem primitive too.
        for value in (step.source, step.staging, step.destination, step.copy_path):
            if value and (
                not Path(value).is_absolute() or ".." in Path(value).parts or "\x00" in value
            ):
                raise LibraryError("invalid_intent", "文件操作路径不合法")

    def checkpoint(self, step_id, phase, **values):
        with self.db.write() as session:
            step = session.get(FileStep, step_id)
            step.phase = phase
            for key, value in values.items():
                setattr(step, key, value)
            session.get(Task, step.operation_id).phase = phase
        if self.fault_hook:
            self.fault_hook(phase, step_id)

    def run(self, operation_id):
        try:
            with self.db.write() as session:
                operation = session.get(FileOperation, operation_id)
                if operation.historical:
                    return
                task = session.get(Task, operation_id)
                task.status, task.phase, task.error = "running", "processing_files", None
                steps = list(
                    session.scalars(
                        select(FileStep)
                        .where(FileStep.operation_id == operation_id)
                        .order_by(FileStep.id)
                    )
                )
                kind = operation.kind
                if kind == "undo":
                    latest = session.get(Setting, "last_delete_operation")
                    if not latest or latest.value != operation.undo_of:
                        for step in steps:
                            if step.outcome == "pending":
                                step.outcome, step.error = "failed", "stale_delete"
                                video = session.get(Video, step.video_id)
                                if video:
                                    video.error = None
                        steps = []
            self.progress(operation_id)
            pending = [step for step in steps if step.outcome == "pending"]
            logical = [step for step in pending if step.source == step.destination]
            if logical:
                self.logical_batch(logical, kind)
            for step in pending:
                if step.source != step.destination:
                    self.run_step(step, kind)
            self.finish(operation_id)
        except InterruptedError:
            with self.db.write() as session:
                task = session.get(Task, operation_id)
                task.status, task.error = "interrupted", "service_stopped"
        except Exception:
            with self.db.write() as session:
                task = session.get(Task, operation_id)
                task.status, task.error = "failed", "operation_recovery_required"
                task.finished_at = time.time()

    def logical_batch(self, steps, kind):
        # A batch of marks/restores is one SQLite transaction, with no media
        # reads, hashing, directory creation, renames or deletes.
        with self.db.write() as session:
            for source in steps:
                step = session.get(FileStep, source.id)
                video = session.get(Video, step.video_id)
                item = session.get(TrashItem, step.trash_id) if kind != "trash" else None
                code = None
                if not video or video.status != step.original_status:
                    code = "stale_operation"
                elif kind != "trash" and (not item or item.status != "active"):
                    code = "item_not_found"
                elif kind != "trash" and session.scalar(
                    select(Video.id).where(
                        Video.location_key == step.destination, Video.id != video.id
                    )
                ):
                    code = "destination_conflict"
                if code:
                    step.phase, step.outcome, step.error = "prepared", "failed", code
                    if video and video.error == "file_operation_pending":
                        video.error = None
                    continue
                self.apply_step(session, step, kind, None)
        self.progress(steps[0].operation_id)
        if self.fault_hook:
            self.fault_hook("logical_committed", steps[0].id)

    def run_step(self, step, kind):
        if self.stop.is_set():
            raise InterruptedError("service_stopping")
        try:
            final_signature = self.transfer.execute(step, kind)
            self.commit_step(step.id, kind, final_signature)
        except (LibraryError, OSError) as error:
            self.fail_step(step, error, kind)
        self.progress(step.operation_id)

    def progress(self, operation_id):
        with self.db.write() as session:
            outcomes = list(
                session.scalars(
                    select(FileStep.outcome).where(FileStep.operation_id == operation_id)
                )
            )
            session.get(Task, operation_id).result = {
                "total": len(outcomes),
                "processed": sum(outcome != "pending" for outcome in outcomes),
                "succeeded": outcomes.count("succeeded"),
                "failed": sum(outcome not in ("pending", "succeeded") for outcome in outcomes),
            }

    def commit_step(self, step_id, kind, final_signature):
        with self.db.write() as session:
            step = session.get(FileStep, step_id)
            self.apply_step(session, step, kind, final_signature)

    def apply_step(self, session, step, kind, final_signature):
        video = session.get(Video, step.video_id)
        if kind == "trash":
            session.add(
                TrashItem(
                    id=step.trash_id,
                    video_id=video.id,
                    operation_id=step.operation_id,
                    root_path=step.root_path,
                    original_path=step.original_path,
                    trash_path=step.destination,
                    sha256=step.expected_hash,
                    size=step.expected_size,
                    status="active",
                )
            )
            video.status, video.location_key = (
                "trash",
                step.source if step.source == step.destination else None,
            )
        elif kind == "permanent":
            session.get(TrashItem, step.trash_id).status = "purged"
            video.status, video.location_key = "deleted", None
            session.execute(delete(VideoTag).where(VideoTag.video_id == video.id))
        else:
            conflicting = session.scalar(
                select(Video).where(Video.location_key == step.destination, Video.id != video.id)
            )
            if conflicting:
                conflicting.status, conflicting.location_key = "missing", None
                conflicting.generation += 1
                touch_active_scan(session, conflicting)
                session.flush()
            roots = list(session.scalars(select(Root)))
            root = min(
                (root for root in roots if beneath(Path(step.destination), Path(root.path))),
                key=lambda root: len(root.path),
            )
            video.status, video.location_key, video.path, video.root_id = (
                "available",
                step.destination,
                step.destination,
                root.id,
            )
            session.get(TrashItem, step.trash_id).status = "restored"
        if final_signature:
            set_video_signature(video, final_signature)
        video.error = None
        video.generation += 1
        touch_active_scan(session, video)
        step.phase, step.outcome, step.error = "committed", "succeeded", None

    @staticmethod
    def error_code(error):
        if isinstance(error, LibraryError):
            return error.code
        return {
            errno.EACCES: "permission_denied",
            errno.EPERM: "permission_denied",
            errno.EROFS: "read_only_media",
            errno.ENOSPC: "insufficient_space",
            errno.EDQUOT: "insufficient_space",
            errno.EEXIST: "destination_conflict",
            errno.ENOENT: "source_missing",
            errno.ELOOP: "path_unsafe",
            errno.ENOTDIR: "path_unsafe",
        }.get(error.errno, "file_io_failed")

    def fail_step(self, step, error, kind):
        try:
            state, restored_signature = self.transfer.rollback(step, kind)
        except (OSError, LibraryError):
            state, restored_signature = "conflict", None
        code = self.error_code(error)
        with self.db.write() as session:
            stored = session.get(FileStep, step.id)
            stored.error = code
            stored.outcome = (
                "conflict"
                if code in ("destination_conflict", "source_replaced", "path_unsafe")
                or state == "conflict"
                else "failed"
            )
            video = session.get(Video, stored.video_id)
            if video and code != "stale_operation":
                if state == "restored":
                    set_video_signature(video, restored_signature)
                    video.error = None
                elif state == "changed":
                    video.error = "file_changed"
                elif state == "missing":
                    video.status, video.location_key, video.error = (
                        "missing",
                        None,
                        "source_missing",
                    )
                else:
                    video.error = "file_operation_pending"
                video.generation += 1
                touch_active_scan(session, video)

    def finish(self, operation_id):
        with self.db.write() as session:
            operation = session.get(FileOperation, operation_id)
            steps = list(
                session.scalars(
                    select(FileStep)
                    .where(FileStep.operation_id == operation_id)
                    .order_by(FileStep.id)
                )
            )
            items = [
                {
                    "requested_id": step.requested_id,
                    "video_id": step.video_id,
                    "trash_id": step.trash_id,
                    "outcome": step.outcome,
                    "phase": step.phase,
                    "error": step.error,
                }
                for step in steps
            ]
            successes = sum(step.outcome == "succeeded" for step in steps)
            playback_restored = False
            if operation.kind == "trash" and successes:
                latest = session.get(Setting, "last_delete_operation")
                if latest:
                    latest.value = operation_id
                else:
                    session.add(Setting(key="last_delete_operation", value=operation_id))
            if operation.kind == "undo" and successes:
                original = session.get(FileOperation, operation.undo_of)
                snapshot = original.round_snapshot
                round = session.get(PlaybackRound, snapshot.get("id")) if snapshot else None
                tag_ids = round.scope.get("tag_ids", []) if round else []
                tags_exist = (
                    (round and round.membership == "fixed")
                    or not tag_ids
                    or session.scalar(
                        select(func.count()).select_from(Tag).where(Tag.id.in_(tag_ids))
                    )
                    == len(set(tag_ids))
                )
                target = (
                    next(
                        (
                            row
                            for row in self.playback.eligible(session, round)
                            if (
                                row[1] == snapshot["video_id"]
                                if "video_id" in snapshot
                                else row[0] == snapshot["cursor"]
                            )
                        ),
                        None,
                    )
                    if round and tags_exist
                    else None
                )
                if target and self.playback.streams.can_play(
                    session, session.get(Video, target[1])
                ):
                    round.cursor, round.finished = target[0], snapshot["finished"]
                    round.revision += 1
                    pointer = session.get(Setting, "active_round")
                    if pointer:
                        pointer.value = round.id
                    else:
                        session.add(Setting(key="active_round", value=round.id))
                    playback_restored = True
                if successes == len(steps):
                    session.get(Setting, "last_delete_operation").value = ""
            task = session.get(Task, operation_id)
            task.status = "completed" if successes else "failed"
            task.phase, task.finished_at = "completed", time.time()
            task.error = (
                None
                if successes
                else next((step.error for step in steps if step.error), "no_operations_completed")
            )
            task.result = {
                "operation_id": operation_id,
                "items": items,
                "succeeded": successes,
                "failed": len(steps) - successes,
                "partial": 0 < successes < len(steps),
                "playback_restored": playback_restored,
            }

    def retry(self, operation_id, request_id):
        with self.db.write() as session:
            operation = session.get(FileOperation, operation_id)
            if not operation or operation.historical:
                raise LibraryError("operation_not_found", "文件操作不存在", 404)

            def action():
                task = session.get(Task, operation_id)
                unfinished = list(
                    session.scalars(
                        select(FileStep).where(
                            FileStep.operation_id == operation_id,
                            FileStep.outcome != "succeeded",
                            FileStep.source != "",
                        )
                    )
                )
                if unfinished and task.status not in ("queued", "running"):
                    for step in unfinished:
                        if session.scalar(
                            reserved_steps()
                            .where(
                                FileStep.video_id == step.video_id,
                                FileStep.operation_id != operation_id,
                            )
                            .limit(1)
                        ):
                            raise LibraryError("operation_busy", "该视频已有进行中的文件操作")
                        step.outcome, step.error = "pending", None
                    task.status, task.error, task.finished_at = "queued", None, None
                return {"operation_id": operation_id}

            result = once(session, "files.retry", request_id, {"id": operation_id}, action)
            should_enqueue = session.get(Task, operation_id).status == "queued"
        if should_enqueue:
            self.enqueue(operation_id)
        return result["operation_id"]

    def trash(self, offset, limit):
        with self.db.read() as session:
            total = session.scalar(
                select(func.count()).select_from(TrashItem).where(TrashItem.status == "active")
            )
            items = session.scalars(
                select(TrashItem)
                .where(TrashItem.status == "active")
                .order_by(TrashItem.deleted_at.desc(), TrashItem.id)
                .offset(offset)
                .limit(limit)
            )
            return {
                "items": [
                    {
                        "id": item.id,
                        "operation_id": item.operation_id,
                        "original_path": item.original_path,
                        "deleted_at": item.deleted_at,
                        "video": self.catalog.video_json(session.get(Video, item.video_id)),
                    }
                    for item in items
                ],
                "total": total,
                "offset": offset,
                "limit": limit,
            }

    def close(self):
        self.stop.set()
        self.executor.shutdown(wait=True, cancel_futures=True)

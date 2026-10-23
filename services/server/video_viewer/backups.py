"""Asynchronous immutable exports, inspected imports and atomic logical restore."""

import hashlib
import json
import os
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor

from sqlalchemy import delete, select

from .backup_format import (
    SETTING_KEYS,
    TABLES,
    canonical,
    decode,
    require_legacy_backup,
    snapshot,
    validate_relations,
)
from .backup_reconcile import mappings_for, recommended_mapping, reconcile
from .errors import LibraryError
from .file_state import reserved_steps
from .file_transfer import rename_new, unlink_owned
from .models import FileOperation, Observation, RequestRecord, Setting, Task, uid
from .paths import make_directory, open_regular, signature
from .requests import once


class Backups:
    def __init__(self, db, settings, scanner, files, fault_hook=None):
        self.db, self.settings, self.scanner, self.files = db, settings, scanner, files
        self.fault_hook = fault_hook
        self.store = settings.data_dir / "backups"
        self.stop = threading.Event()
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="management-backups")
        self.lock = threading.RLock()
        self.futures = {}
        self.start_regular = None
        self.regular_started = False
        self.deferred = []

    def start(self, start_regular):
        self.start_regular = start_regular
        with self.db.read() as session:
            pending = list(
                session.scalars(
                    select(Task)
                    .where(
                        Task.kind.in_(["backup_export", "backup_inspect", "backup_restore"]),
                        Task.status.in_(["queued", "running", "interrupted"]),
                    )
                    .order_by(Task.created_at)
                )
            )
        restoring = next((task for task in pending if task.kind == "backup_restore"), None)
        if restoring:
            self.deferred = [task.id for task in pending if task.id != restoring.id]
            with self.db.write_lock:
                self.db.maintenance_task = restoring.id
            self.enqueue(restoring.id)
            return
        else:
            self.start_normal()
        for task in pending:
            if task.kind != "backup_restore":
                with self.db.write() as session:
                    session.get(Task, task.id).status = "queued"
                self.enqueue(task.id)

    def start_normal(self):
        if not self.regular_started:
            self.regular_started = True
            self.start_regular()
            for task_id in self.deferred:
                with self.db.write() as session:
                    session.get(Task, task_id).status = "queued"
                self.enqueue(task_id)
            self.deferred = []

    def path(self, task_id):
        try:
            if str(uuid.UUID(task_id)) != task_id:
                raise ValueError()
        except (ValueError, TypeError, AttributeError):
            raise LibraryError("backup_not_found", "备份不存在", 404) from None
        return self.store / (task_id + ".json")

    def read(self, task_id):
        with open_regular(self.path(task_id)) as fd:
            if os.fstat(fd).st_size > self.settings.backup_max_bytes:
                raise LibraryError("backup_too_large", "备份超过当前大小限制", 413)
            chunks, total = [], 0
            while chunk := os.read(fd, 1024 * 1024):
                total += len(chunk)
                if total > self.settings.backup_max_bytes:
                    raise LibraryError("backup_too_large", "备份超过当前大小限制", 413)
                chunks.append(chunk)
        return b"".join(chunks)

    def write(self, task_id, raw):
        if len(raw) > self.settings.backup_max_bytes:
            raise LibraryError("backup_too_large", "备份超过当前大小限制", 413)
        target = self.path(task_id)
        if target.exists():
            if self.read(task_id) != raw:
                raise LibraryError("backup_artifact_conflict", "备份文件与任务记录不一致")
            return
        # All paths are server-generated UUIDs under private management storage.
        temporary = target.with_suffix("." + uid() + ".tmp")
        with make_directory(self.store) as parent:
            fd = os.open(
                temporary.name,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                0o600,
                dir_fd=parent,
            )
            try:
                pending = memoryview(raw)
                while pending:
                    written = os.write(fd, pending)
                    if written <= 0:
                        raise OSError("short backup write")
                    pending = pending[written:]
                os.fsync(fd)
                owned = signature(os.fstat(fd))
            finally:
                os.close(fd)
            os.fsync(parent)
        try:
            rename_new(str(temporary), str(target))
        except FileExistsError:
            if self.read(task_id) != raw:
                raise LibraryError("backup_artifact_conflict", "备份文件与任务记录不一致") from None
            unlink_owned(temporary, owned)

    def enqueue(self, task_id):
        with self.lock:
            if self.stop.is_set():
                raise LibraryError("service_stopping", "服务正在停止", 503)
            future = self.futures.get(task_id)
            if not future or future.done():
                self.futures[task_id] = self.executor.submit(self.run, task_id)

    def submit(self, kind, request_id, raw=None):
        fingerprint = hashlib.sha256(raw).hexdigest() if raw is not None else None
        with self.db.write() as session:

            def action():
                if kind == "backup_export":
                    require_legacy_backup(session)
                task = Task(kind=kind, status="queued", result={"raw_sha256": fingerprint})
                session.add(task)
                session.flush()
                return {"id": task.id}

            result = once(
                session, "backup." + kind, request_id, {"raw_sha256": fingerprint}, action
            )
            task_id = result["id"]
            task = session.get(Task, task_id)
            if (
                raw is not None
                and task.status == "failed"
                and task.error == "backup_source_unavailable"
            ):
                task.status, task.error = "queued", None
            pending = task.status in ("queued", "running", "interrupted")
        if raw is not None:
            self.write(task_id, raw)
        if pending:
            self.enqueue(task_id)
        return task_id

    def inspect_result(self, document, raw):
        payload = document["payload"]
        suggestions = recommended_mapping(payload, self.settings)
        return {
            "format": document["format"],
            **self.details(document, raw),
            "counts": {name: len(rows) for name, rows in payload["tables"].items()},
            "roots": [
                {
                    "id": root["id"],
                    "name": root["name"],
                    "original_path": root["path"],
                    "suggested_path": suggestions[root["id"]],
                }
                for root in payload["tables"]["roots"]
            ],
        }

    def artifact(self, task_id, kinds=("backup_export", "backup_snapshot")):
        with self.db.read() as session:
            task = session.get(Task, task_id)
            if not task or task.kind not in kinds or task.status != "completed":
                raise LibraryError("backup_not_found", "备份尚未完成或不存在", 404)
        path = self.path(task_id)
        if not path.is_file():
            raise LibraryError("backup_not_found", "备份文件已不可用", 404)
        try:
            raw = self.read(task_id)
        except OSError:
            raise LibraryError("backup_not_found", "备份文件已不可用", 404) from None
        if hashlib.sha256(raw).hexdigest() != task.result.get("file_sha256"):
            raise LibraryError("backup_artifact_changed", "备份文件在校验后已变化，请重新导入", 409)
        return path

    def exports(self, limit):
        with self.db.read() as session:
            ids = list(
                session.scalars(
                    select(Task.id)
                    .where(
                        Task.kind.in_(["backup_export", "backup_snapshot"]),
                        Task.status == "completed",
                    )
                    .order_by(Task.created_at.desc())
                    .limit(limit)
                )
            )
        return [self.scanner.task(task_id) for task_id in ids]

    def submit_restore(self, preview_id, mapping, request_id):
        request = {"preview_id": preview_id, "root_mapping": mapping}
        key = "backup.restore:" + request_id
        fingerprint = hashlib.sha256(
            json.dumps(request, sort_keys=True, ensure_ascii=False).encode()
        ).hexdigest()
        # Replaying an accepted request must work while normal writes are paused.
        with self.db.read() as session:
            previous = session.get(RequestRecord, key)
            if previous:
                if previous.fingerprint != fingerprint:
                    raise LibraryError("idempotency_conflict", "请求标识已用于不同的恢复")
                return previous.result["id"]
        self.artifact(preview_id, ("backup_inspect",))
        document = decode(self.read(preview_id))
        mappings_for(document["payload"], mapping, self.settings)
        try:
            with self.db.write() as session:
                require_legacy_backup(session)
                busy = session.scalar(
                    select(Task.id)
                    .where(
                        Task.kind == "scan",
                        Task.status.in_(["queued", "running"]),
                    )
                    .limit(1)
                )
                active_files = session.scalar(
                    select(Task.id)
                    .join(FileOperation)
                    .where(
                        FileOperation.historical.is_(False),
                        Task.status.in_(["queued", "running"]),
                    )
                    .limit(1)
                )
                other_backups = session.scalar(
                    select(Task.id)
                    .where(
                        Task.kind.in_(["backup_export", "backup_inspect"]),
                        Task.status.in_(["queued", "running"]),
                    )
                    .limit(1)
                )
                if (
                    busy
                    or active_files
                    or other_backups
                    or session.scalar(reserved_steps().limit(1))
                ):
                    raise LibraryError("library_busy", "请等待扫描和文件操作完成后恢复")
                task = Task(
                    kind="backup_restore",
                    status="queued",
                    result={**request, "pre_snapshot_id": uid()},
                )
                session.add(task)
                session.flush()
                session.add(RequestRecord(id=key, fingerprint=fingerprint, result={"id": task.id}))
                pointer = session.get(Setting, "maintenance_restore")
                if pointer:
                    pointer.value = task.id
                else:
                    session.add(Setting(key="maintenance_restore", value=task.id))
                task_id = task.id
                self.db.maintenance_task = task_id
        except Exception:
            with self.db.write_lock:
                # Never release another restore's reservation after a conflict.
                if "task_id" in locals() and self.db.maintenance_task == task_id:
                    self.db.maintenance_task = None
            raise
        self.enqueue(task_id)
        return task_id

    def phase(self, task_id, phase):
        with self.db.write() as session:
            task = session.get(Task, task_id)
            task.phase = phase
        if self.fault_hook:
            self.fault_hook(phase, task_id)

    @staticmethod
    def details(document, raw):
        return {
            "checksum": document["sha256"],
            "file_sha256": hashlib.sha256(raw).hexdigest(),
            "bytes": len(raw),
            "version": document["version"],
        }

    def export(self, task_id):
        if self.path(task_id).exists():
            raw = self.read(task_id)
            document = decode(raw)
        else:
            document = snapshot(self.db, self.settings)
            raw = canonical(document)
            self.write(task_id, raw)
        return self.details(document, raw)

    def restore(self, task_id):
        with self.db.read() as session:
            inputs = dict(session.get(Task, task_id).result)
        self.artifact(inputs["preview_id"], ("backup_inspect",))
        document = decode(self.read(inputs["preview_id"]))
        mapping = mappings_for(document["payload"], inputs["root_mapping"], self.settings)
        snapshot_id = inputs["pre_snapshot_id"]
        with self.db.write() as session:
            if not session.get(Task, snapshot_id):
                session.add(
                    Task(
                        id=snapshot_id,
                        kind="backup_snapshot",
                        status="running",
                        phase="pre_restore",
                        result={},
                    )
                )
        details = self.export(snapshot_id)
        with self.db.write() as session:
            task = session.get(Task, snapshot_id)
            task.status, task.phase, task.result, task.finished_at = (
                "completed",
                "completed",
                details,
                time.time(),
            )
        self.phase(task_id, "snapshot_written")
        current = snapshot(self.db, self.settings)["payload"]
        self.phase(task_id, "reconciling_files")
        tables = reconcile(document["payload"], current, mapping, self.settings, self.stop)
        validate_relations(tables)
        if self.stop.is_set():
            raise InterruptedError("service_stopping")
        self.phase(task_id, "replacing_management")
        result = {
            **inputs,
            "restored": True,
            "counts": {name: len(rows) for name, rows in tables.items()},
            "available": sum(video["status"] == "available" for video in tables["videos"]),
            "missing": sum(video["status"] == "missing" for video in tables["videos"]),
            "trash": sum(video["status"] == "trash" for video in tables["videos"]),
            "historical_operations_replayed": 0,
            "unmapped_roots": [root_id for root_id, value in mapping.items() if value is None],
        }
        with self.db.write() as session:
            for table in reversed(TABLES):
                statement = table.delete()
                if table.name == "tasks":
                    statement = statement.where(~table.c.kind.startswith("backup_"))
                if table.name == "request_records":
                    statement = statement.where(~table.c.id.startswith("backup."))
                session.execute(statement)
            session.execute(delete(Observation))
            for table in TABLES:
                if tables[table.name]:
                    session.execute(table.insert(), tables[table.name])
            values = {
                **document["payload"]["settings"],
                "last_delete_operation": "",
                "root_configuration_restored": "1",
                "maintenance_restore": "",
            }
            for setting in SETTING_KEYS:
                if setting not in values:
                    values[setting] = ""
            for key, value in values.items():
                item = session.get(Setting, key)
                if item:
                    item.value = value
                else:
                    session.add(Setting(key=key, value=value))
            if self.fault_hook:
                self.fault_hook("after_replace_before_commit", task_id)
            task = session.get(Task, task_id)
            task.status, task.phase, task.error = "completed", "completed", None
            task.finished_at, task.result = time.time(), result
        return result

    def run(self, task_id):
        is_restore = False
        try:
            with self.db.read() as session:
                task = session.get(Task, task_id)
                kind = task.kind
                if task.status == "completed":
                    return
            is_restore = kind == "backup_restore"
            if is_restore:
                with self.db.write_lock:
                    self.db.maintenance_task, self.db.maintenance_owner = (
                        task_id,
                        threading.get_ident(),
                    )
            with self.db.write() as session:
                task = session.get(Task, task_id)
                task.status, task.phase, task.error = "running", "processing_backup", None
            if is_restore:
                self.restore(task_id)
            else:
                raw = self.read(task_id) if kind == "backup_inspect" else None
                if raw is not None and hashlib.sha256(raw).hexdigest() != task.result.get(
                    "raw_sha256"
                ):
                    raise LibraryError("backup_artifact_changed", "上传文件与请求不一致")
                result = (
                    self.inspect_result(decode(raw), raw)
                    if raw is not None
                    else self.export(task_id)
                )
                with self.db.write() as session:
                    task = session.get(Task, task_id)
                    task.status, task.phase, task.error = "completed", "completed", None
                    task.finished_at, task.result = time.time(), result
        except InterruptedError:
            self.fail(task_id, "service_stopped", "interrupted", is_restore)
        except Exception as error:
            code = (
                error.code
                if isinstance(error, LibraryError)
                else (
                    "backup_source_unavailable"
                    if isinstance(error, FileNotFoundError)
                    else "backup_operation_failed"
                )
            )
            self.fail(task_id, code, "failed", is_restore)
        finally:
            if is_restore:
                with self.db.write_lock:
                    self.db.maintenance_task, self.db.maintenance_owner = None, None
                if self.start_regular and not self.regular_started and not self.stop.is_set():
                    self.start_normal()

    def fail(self, task_id, error, status, is_restore):
        with self.db.write() as session:
            task = session.get(Task, task_id)
            task.status, task.error, task.phase, task.finished_at = (
                status,
                error,
                status,
                time.time(),
            )
            if is_restore and status != "interrupted":
                session.get(Setting, "maintenance_restore").value = ""

    def close(self):
        self.stop.set()
        self.executor.shutdown(wait=True, cancel_futures=True)

"""Durable v2 backup jobs and one-transaction management replacement.

The existing backup executor owns scheduling. Uploaded content is a logical
archive, never a database or SQL. Media are opened read-only by reconciliation.
"""

import hashlib
import json
import os
import shutil
import time
import uuid
from contextlib import contextmanager
from pathlib import Path

from sqlalchemy import delete, func, or_, select

from .authority import Authority
from .backup_archive import (
    StagedArchive,
    _readonly,
    file_hash,
    freeze_graph,
    inspect_backup,
    write_v2,
)
from .backup_format import FORMAT
from .backup_history import HistoryArchive
from .backup_reconcile import mappings_for, recommended_mapping
from .backup_restore_graph import prepare_graph
from .backup_v2_schema import SETTING_KEYS, TABLES, mounts_from
from .errors import LibraryError
from .file_state import reserved_steps
from .file_transfer import rename_new
from .management_history import EPOCHS_KEY, HISTORY_KEY
from .models import Observation, RequestRecord, Setting, Task, uid
from .pack_scanner import reserved_packs
from .requests import once

KINDS = ("backup_export_v2", "backup_inspect_v2", "backup_restore_v2")


def identity(value):
    try:
        if str(uuid.UUID(value)) != value:
            raise ValueError()
    except (ValueError, TypeError, AttributeError):
        raise LibraryError("backup_not_found", "管理备份不存在", 404) from None
    return value


def setting(session, key, value):
    row = session.get(Setting, key)
    if row is None:
        session.add(Setting(key=key, value=value))
    else:
        row.value = value


class ManagementArchives:
    def __init__(self, owner):
        self.owner, self.db, self.settings = owner, owner.db, owner.settings
        self.store = self.settings.data_dir / "management-archives"
        self.history_store = self.settings.data_dir / "management-history"
        for path in (self.store, self.history_store):
            path.mkdir(mode=0o700, exist_ok=True)
        # A post-commit process death can leave only its private work tree.
        # Local backup controls are retained across replacements, so completion
        # is still authoritative here; published history is never reaped here.
        for path in self.store.glob("restore-*"):
            if path.is_symlink() or not path.is_dir():
                continue
            try:
                task_id = identity(path.name.removeprefix("restore-"))
            except LibraryError:
                continue
            with self.db.read() as session:
                task = session.get(Task, task_id)
                completed = (
                    task is not None
                    and task.kind == "backup_restore_v2"
                    and task.status in ("completed", "failed")
                )
            if completed:
                shutil.rmtree(path)

    def check(self):
        if self.owner.stop.is_set():
            raise InterruptedError("service_stopping")

    def path(self, task_id):
        return self.store / (identity(task_id) + ".vvbackup")

    def history(self, session=None):
        if session is None:
            with self.db.read() as session:
                return self.history(session)
        ref = session.get(Setting, HISTORY_KEY)
        return (
            HistoryArchive(self.history_store / identity(ref.value) / "bundle")
            if ref and ref.value
            else None
        )

    def submit(self, kind, request_id, source=None):
        if kind not in KINDS[:2]:
            raise ValueError("Invalid archive job")
        digest = None
        if source is not None:
            if Path(source).stat().st_size > self.settings.backup_max_bytes:
                raise LibraryError("backup_too_large", "管理备份超过大小限制", 413)
            digest = file_hash(source)
        with self.db.write() as session:

            def action():
                task = Task(
                    kind=kind, status="queued", result={"archive_version": 2, "raw_sha256": digest}
                )
                session.add(task)
                session.flush()
                return {"id": task.id}

            result = once(session, "management." + kind, request_id, {"raw_sha256": digest}, action)
            task_id = result["id"]
            task = session.get(Task, task_id)
            if task.error == "restored_history":
                raise LibraryError("historical_request", "原管理任务为只读历史，请查询原结果", 409)
        if source is not None:
            destination = self.path(task_id)
            if destination.exists():
                if file_hash(destination) != digest:
                    raise LibraryError("backup_artifact_changed", "原导入文件不一致", 409)
            else:
                temporary = self.store / (".upload-" + uid())
                try:
                    with temporary.open("xb") as output, Path(source).open("rb") as incoming:
                        os.chmod(temporary, 0o600)
                        shutil.copyfileobj(incoming, output, 1024 * 1024)
                        output.flush()
                        os.fsync(output.fileno())
                    if file_hash(temporary) != digest:
                        raise LibraryError("backup_artifact_changed", "导入文件在受理时变化", 409)
                    rename_new(temporary, destination)
                    from .backup_archive import _sync_directory

                    _sync_directory(self.store)
                finally:
                    temporary.unlink(missing_ok=True)
        if (
            task.status in ("queued", "running", "interrupted")
            or task.error == "backup_source_unavailable"
        ):
            self.owner.enqueue(task_id)
        return task_id

    def artifact(self, task_id, *, inspect=False, original=None):
        with self.db.read() as session:
            task = session.get(Task, task_id)
            metadata = {c.name: getattr(task, c.name) for c in Task.__table__.c} if task else None
            if not inspect and (
                original is not None
                or metadata is None
                or metadata.get("error") == "restored_history"
            ):
                from .management_history import historical_task

                metadata = original or historical_task(session, task_id)
            expected = (
                ("backup_inspect_v2",) if inspect else ("backup_export_v2", "backup_snapshot_v2")
            )
            if (
                metadata is None
                or metadata["kind"] not in expected
                or metadata["status"] != "completed"
                or inspect
                and metadata.get("error") == "restored_history"
            ):
                raise LibraryError(
                    "backup_not_found", "管理备份尚未完成或不存在，请重新校验历史文件", 404
                )
            digest = metadata["result"].get("file_sha256")
        path = self.path(task_id)
        if not path.is_file() or file_hash(path) != digest:
            raise LibraryError(
                "backup_artifact_changed", "原管理备份文件在本服务不可用或已变化", 409
            )
        return path

    @contextmanager
    def staged(self, task_id, folder):
        yield inspect_backup(
            self.artifact(task_id, inspect=True),
            folder,
            maximum_bytes=self.settings.backup_max_bytes,
            check=self.check,
        )

    def export(self, task_id):
        path = self.path(task_id)
        work = self.store / ("write-" + identity(task_id))
        if work.exists():
            shutil.rmtree(work)
        work.mkdir(mode=0o700)
        try:
            if path.exists():
                return inspect_backup(
                    path,
                    work / "stage",
                    maximum_bytes=self.settings.backup_max_bytes,
                    check=self.check,
                ).details
            with freeze_graph(
                self.db, mounts_from(self.settings), work, check=self.check
            ) as current:
                details = write_v2(
                    work / "complete.vvbackup",
                    self._graphs(current, self.history()),
                    maximum_bytes=self.settings.backup_max_bytes,
                    check=self.check,
                )
                rename_new(work / "complete.vvbackup", path)
                from .backup_archive import _sync_directory

                _sync_directory(self.store)
                return details
        finally:
            shutil.rmtree(work, ignore_errors=True)

    def inspection(self, task_id):
        return self.store / ("inspect-" + identity(task_id)) / "stage"

    @staticmethod
    def _graphs(current, history):
        yield current
        if history:
            yield from history.graphs()

    def inspect(self, task_id):
        path = self.path(task_id)
        with self.db.read() as session:
            expected = session.get(Task, task_id).result["raw_sha256"]
        if file_hash(path) != expected:
            raise LibraryError("backup_artifact_changed", "上传文件与原请求不一致", 409)
        stage = self.inspection(task_id)
        if stage.parent.exists():
            shutil.rmtree(stage.parent)
        stage.parent.mkdir(mode=0o700)
        value = inspect_backup(
            path, stage, maximum_bytes=self.settings.backup_max_bytes, check=self.check
        )
        return {
            **value.details,
            "archive_version": 2,
            "format": FORMAT,
            "counts": value.counts(),
            "roots_count": value.roots(limit=1)["total"],
        }

    def preview_roots(self, task_id, *, offset=0, limit=24):
        with self.db.read() as session:
            task = session.get(Task, task_id)
            if not task or task.kind != "backup_inspect_v2" or task.status != "completed":
                raise LibraryError("backup_not_found", "请先完成管理备份校验", 404)
        stage = StagedArchive(self.inspection(task_id))
        page = stage.roots(offset=offset, limit=limit)
        graph = next(stage.graphs(verify=False))
        suggestions = recommended_mapping(
            {"tables": {"roots": page["items"]}, "mounts": graph.mounts}, self.settings
        )
        return {
            **page,
            "limit": limit,
            "items": [
                {**root, "original_path": root["path"], "suggested_path": suggestions[root["id"]]}
                for root in page["items"]
            ],
        }

    @staticmethod
    def prior_restore(session, key, fingerprint):
        prior = session.get(RequestRecord, key)
        if prior is None:
            return None
        if prior.fingerprint != fingerprint:
            raise LibraryError("idempotency_conflict", "原恢复请求的内容不同", 409)
        task = session.get(Task, prior.result["id"])
        if task is None or task.error == "restored_history":
            raise LibraryError("historical_request", "原管理恢复为只读历史，未重新执行", 409)
        return task.id

    def submit_restore(self, preview_id, mapping, request_id):
        payload = {"preview_id": preview_id, "root_mapping": mapping}
        fingerprint = hashlib.sha256(
            json.dumps(payload, sort_keys=True, ensure_ascii=False).encode()
        ).hexdigest()
        key = "management.restore:" + request_id
        with self.db.read() as session:
            prior = self.prior_restore(session, key, fingerprint)
            if prior:
                return prior
        self.artifact(preview_id, inspect=True)
        stage = StagedArchive(self.inspection(preview_id))
        roots = []
        for offset in range(0, 300, 100):
            page = stage.roots(offset=offset, limit=100)
            roots.extend(page["items"])
            if len(roots) >= page["total"]:
                break
        if len(roots) > 256:
            raise LibraryError("invalid_mapping", "媒体目录数量超出映射限制", 422)
        mappings_for({"tables": {"roots": roots}}, mapping, self.settings)
        task_id = None
        try:
            with self.db.write() as session:
                prior = self.prior_restore(session, key, fingerprint)
                if prior:
                    return prior
                busy = session.scalar(
                    select(Task.id)
                    .where(
                        Task.error.is_distinct_from("restored_history"),
                        or_(
                            Task.status.in_(("queued", "running")),
                            Task.kind.in_(
                                (*KINDS, "backup_export", "backup_inspect", "backup_restore")
                            )
                            & (Task.status == "interrupted"),
                            Task.error == "operation_recovery_required",
                        ),
                    )
                    .limit(1)
                )
                if (
                    busy
                    or session.scalar(reserved_steps().limit(1))
                    or session.scalar(reserved_packs().limit(1))
                ):
                    raise LibraryError("library_busy", "请等待同步和文件任务完成后恢复", 409)
                from .management_history import reject_historical

                reject_historical(session, "request_records", key)
                task = Task(
                    kind="backup_restore_v2",
                    status="queued",
                    result={**payload, "archive_version": 2, "pre_snapshot_id": uid()},
                )
                session.add(task)
                session.flush()
                task_id = task.id
                session.add(RequestRecord(id=key, fingerprint=fingerprint, result={"id": task_id}))
                setting(session, "maintenance_restore", task_id)
                self.db.maintenance_task = task_id
        except BaseException:
            if task_id and self.db.maintenance_task == task_id:
                self.db.maintenance_task = None
            raise
        self.owner.enqueue(task_id)
        return task_id

    def restore(self, task_id):
        with self.db.read() as session:
            inputs = dict(session.get(Task, task_id).result)
        workspace = self.store / ("restore-" + identity(task_id))
        history_folder = self.history_store / identity(task_id)
        if workspace.exists():
            shutil.rmtree(workspace)
        workspace.mkdir(mode=0o700)
        try:
            with self.staged(inputs["preview_id"], workspace / "import") as imported:
                snapshot_id = inputs["pre_snapshot_id"]
                with self.db.write() as session:
                    if session.get(Task, snapshot_id) is None:
                        session.add(
                            Task(
                                id=snapshot_id,
                                kind="backup_snapshot_v2",
                                status="running",
                                result={},
                            )
                        )
                details = self.export(snapshot_id)
                with self.db.write() as session:
                    row = session.get(Task, snapshot_id)
                    row.status, row.phase, row.finished_at, row.result = (
                        "completed",
                        "completed",
                        time.time(),
                        details,
                    )
                self.owner.phase(task_id, "snapshot_written")
                current = inspect_backup(
                    self.path(snapshot_id),
                    workspace / "current",
                    maximum_bytes=self.settings.backup_max_bytes,
                    check=self.check,
                )
                # A not-yet-referenced bundle belongs only to this durable job.
                # Rebuilding it after a crash also removes orphan preparations.
                with self.db.read() as session:
                    previous = session.get(Setting, HISTORY_KEY)
                    if previous and previous.value == task_id:
                        raise RuntimeError("A committed restore must never be replayed")
                if history_folder.exists():
                    shutil.rmtree(history_folder)
                history_folder.mkdir(mode=0o700)
                history = HistoryArchive.prepare(
                    [imported, current], history_folder / "bundle", check=self.check
                )
                self.owner.phase(task_id, "history_prepared")
                self.owner.phase(task_id, "reconciling_files")
                graph, counts = prepare_graph(
                    next(imported.graphs()),
                    next(current.graphs()),
                    workspace / "replacement.sqlite3",
                    inputs["root_mapping"],
                    self.settings,
                    check=self.check,
                )
                self.check()
                for _verified in history.graphs():
                    self.check()
                self.owner.phase(task_id, "replacing_management")
                self.commit(task_id, inputs, graph, history, counts)
        finally:
            shutil.rmtree(workspace, ignore_errors=True)
            with self.db.read() as session:
                active = session.get(Setting, HISTORY_KEY)
                committed = active and active.value == task_id
            if not committed:
                shutil.rmtree(history_folder, ignore_errors=True)
                with self.db.write() as session:
                    snapshot = session.get(Task, inputs["pre_snapshot_id"])
                    if snapshot is not None and snapshot.status in ("queued", "running"):
                        snapshot.status, snapshot.error, snapshot.phase = (
                            "failed",
                            "backup_snapshot_incomplete",
                            "failed",
                        )
                        snapshot.finished_at = time.time()

    def commit(self, task_id, inputs, graph, history, counts):
        controls = {task_id, inputs["preview_id"], inputs["pre_snapshot_id"]}
        engine = _readonly(graph.database)
        try:
            with engine.connect() as source, self.db.write() as session:
                if (
                    session.scalar(
                        select(func.count()).select_from(Task).where(Task.id.in_(controls))
                    )
                    != 3
                ):
                    raise LibraryError(
                        "backup_control_conflict", "本次恢复控制记录不完整，未替换管理数据", 409
                    )
                local_controls = select(Task.id).where(
                    Task.kind.startswith("backup_", autoescape=True),
                    Task.error.is_distinct_from("restored_history"),
                )
                control_namespaces = or_(
                    *[
                        RequestRecord.id.startswith(prefix, autoescape=True)
                        for prefix in (
                            "backup.backup_export:",
                            "backup.backup_inspect:",
                            "backup.restore:",
                            "management.backup_export_v2:",
                            "management.backup_inspect_v2:",
                            "management.restore:",
                        )
                    ]
                )
                epochs_row = session.get(Setting, EPOCHS_KEY)
                epochs = json.loads(epochs_row.value) if epochs_row else {}
                with history._index() as index:
                    current_graph = index.execute(
                        "SELECT identity FROM history_graphs WHERE source_order=1 AND was_library=1"
                    ).fetchone()[0]
                    graphs = {
                        row[0] for row in index.execute("SELECT identity FROM history_graphs")
                    }
                from .authority import valid_epoch

                if not isinstance(epochs, dict) or any(
                    not valid_epoch(epoch)
                    or not isinstance(graph_id, str)
                    or graph_id not in graphs
                    for epoch, graph_id in epochs.items()
                ):
                    raise LibraryError(
                        "history_unavailable", "原管理代次与历史图不一致，未替换管理数据", 409
                    )
                epochs[Authority.current(session)] = current_graph
                for table in reversed(TABLES):
                    statement = table.delete()
                    if table.name == "tasks":
                        statement = statement.where(
                            ~(
                                Task.kind.startswith("backup_", autoescape=True)
                                & Task.error.is_distinct_from("restored_history")
                            )
                        )
                    elif table.name == "request_records":
                        statement = statement.where(
                            ~func.coalesce(
                                control_namespaces
                                & RequestRecord.result["id"].as_string().in_(local_controls),
                                False,
                            )
                        )
                    session.execute(statement)
                session.execute(delete(Observation))
                for table in TABLES:
                    result = source.execute(select(table)).mappings()
                    while chunk := result.fetchmany(100):
                        if table.name == "tasks":
                            retained = set(
                                session.scalars(
                                    select(Task.id).where(Task.id.in_([row["id"] for row in chunk]))
                                )
                            )
                            if any(
                                row["id"] in retained and not row["kind"].startswith("backup_")
                                for row in chunk
                            ):
                                raise LibraryError(
                                    "backup_control_conflict",
                                    "备份媒体任务与本机控制任务身份冲突",
                                    409,
                                )
                            chunk = [row for row in chunk if row["id"] not in retained]
                        elif table.name == "request_records":
                            retained = set(
                                session.scalars(
                                    select(RequestRecord.id).where(
                                        RequestRecord.id.in_([row["id"] for row in chunk])
                                    )
                                )
                            )
                            chunk = [row for row in chunk if row["id"] not in retained]
                        elif table.name in (
                            "file_operations",
                            "pack_file_operations",
                            "pack_restore_plans",
                            "pack_purge_plans",
                            "pack_missing_cleanups",
                        ):
                            if session.scalar(
                                local_controls.where(
                                    Task.id.in_([row["id"] for row in chunk])
                                ).limit(1)
                            ):
                                raise LibraryError(
                                    "backup_control_conflict",
                                    "备份操作不能占用本机控制任务身份",
                                    409,
                                )
                        if chunk:
                            session.execute(table.insert(), [dict(row) for row in chunk])
                session.execute(delete(Setting).where(Setting.key.in_(SETTING_KEYS)))
                values = source.execute(
                    select(Setting.__table__).where(Setting.key.in_(SETTING_KEYS))
                ).mappings()
                for value in values:
                    session.add(Setting(**value))
                # Scan evidence and undo pointers cannot authorize this new graph.
                session.execute(
                    delete(Setting).where(
                        Setting.key.startswith("pack_root_scan_v1:", autoescape=True)
                    )
                )
                setting(session, "last_pack_delete_operation", "")
                setting(session, "root_configuration_restored", "1")
                setting(session, HISTORY_KEY, task_id)
                setting(session, EPOCHS_KEY, json.dumps(epochs, sort_keys=True))
                setting(session, "maintenance_restore", "")
                Authority.rotate(session)
                session.flush()
                if self.owner.fault_hook:
                    self.owner.fault_hook("after_replace_before_commit", task_id)
                # The old ORM identity map must not publish an imported task
                # over the explicitly preserved current control records.
                session.expire_all()
                task = session.get(Task, task_id)
                task.status, task.phase, task.error = "completed", "completed", None
                task.finished_at = time.time()
                task.result = {
                    **inputs,
                    "restored": True,
                    "counts": {
                        t.name: session.scalar(select(func.count()).select_from(t)) for t in TABLES
                    },
                    "imported_counts": counts,
                    "history_ref": task_id,
                    "historical_operations_replayed": 0,
                }
            if self.owner.fault_hook:
                self.owner.fault_hook("restore_committed", task_id)
        finally:
            engine.dispose()

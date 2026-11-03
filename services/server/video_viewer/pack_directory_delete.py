"""Accept directory IDs quickly; remove claimed folders in the existing worker.

No image inventory, image bytes or fingerprints are read. Each durable step
owns one directory inode; retry/restart can only resume that same directory.
"""

import os
import shutil
import stat
from pathlib import Path

from sqlalchemy import select, update

from .errors import LibraryError
from .file_operations import FileOperations
from .file_transfer import file_stat, rename_new
from .management_history import reject_historical
from .models import ImagePack, PackFileOperation, PackFileStep, PackPage, PackTrashItem, Root, Task
from .pack_purge_manifest import digest_json
from .pack_scanner import reserved_packs
from .paths import beneath, excluded, open_directory, signature, validate_path


class PackDirectoryDelete:
    def __init__(self, operations, settings, *, fault_hook=None):
        self.ops, self.db, self.settings = operations, operations.db, settings
        self.fault_hook = fault_hook

    def checkpoint(self, phase, identity):
        if self.fault_hook:
            self.fault_hook(phase, identity)
        if self.ops.stop.is_set():
            raise InterruptedError("service_stopping")

    def submit(self, ids, request_id):
        ids = sorted(set(ids))
        digest = digest_json({"kind": "directory_delete", "trash_ids": ids})
        key = "pack_files:" + request_id
        with self.db.write() as db:
            prior = db.execute(
                select(
                    PackFileOperation.id,
                    PackFileOperation.request_hash,
                    PackFileOperation.historical,
                ).where(PackFileOperation.request_key == key)
            ).first()
            if prior:
                if prior.historical:
                    reject_historical(db, "pack_file_operations", key)
                if prior.request_hash != digest:
                    raise LibraryError("idempotency_conflict", "原请求已用于其他图包")
                return prior.id
            reject_historical(db, "pack_file_operations", key)
            roots = list(db.scalars(select(Root)))
            rows = list(
                db.execute(
                    select(
                        PackTrashItem.id.label("trash_id"),
                        PackTrashItem.status.label("trash_status"),
                        PackTrashItem.original_path,
                        PackTrashItem.root_path,
                        ImagePack.id.label("pack_id"),
                        ImagePack.path,
                        ImagePack.root_id,
                        ImagePack.status,
                        ImagePack.device,
                        ImagePack.inode,
                    )
                    .join(ImagePack)
                    .where(PackTrashItem.id.in_(ids))
                )
            )
            if not ids or len(ids) > 1000 or len(rows) != len(ids):
                raise LibraryError("pack_operation_item_not_found", "所选回收记录不存在", 404)
            busy = set(db.scalars(reserved_packs()))
            by_root = {r.id: r for r in roots}
            for row in rows:
                root = by_root.get(row.root_id)
                if row.pack_id in busy:
                    raise LibraryError("operation_busy", "所选图包已有后台任务，请查询原任务")
                if row.trash_status != "active" or row.status != "trash":
                    raise LibraryError("stale_pack_state", "所选图包已恢复或回收状态已变化")
                self.scope(row, root, roots)
            task = Task(
                kind="pack_directory_delete",
                status="queued",
                phase="queued",
                result={"total": len(rows), "processed": 0, "succeeded": 0, "failed": 0},
            )
            db.add(task)
            db.flush()
            operation = PackFileOperation(
                id=task.id,
                kind="permanent",
                request_key=key,
                request_hash=digest,
                historical=False,
                session_snapshot={"directory_delete": True},
            )
            db.add(operation)
            db.flush()
            db.add_all(
                [
                    PackFileStep(
                        operation_id=task.id,
                        pack_id=r.pack_id,
                        requested_id=r.trash_id,
                        root_path=r.root_path,
                        original_path=r.path,
                        source_signature=[r.device, r.inode],
                    )
                    for r in rows
                ]
            )
            self.ops.set_pointer(db, "last_pack_delete_operation", "")
            identity = task.id
        self.ops.enqueue(identity)
        return identity

    def scope(self, row, root, roots):
        path, base = Path(row.path), Path(row.root_path)
        if (
            not root
            or root.kind != "pack"
            or not root.enabled
            or not root.available
            or not root.mount_id
            or root.path != row.root_path
            or row.original_path != row.path
            or not path.is_absolute()
            or ".." in path.parts
            or path == base
            or not beneath(path, base)
            or not any(beneath(path, m.path) for m in self.settings.mounts)
            or excluded(path, self.settings.data_dir)
            or (self.settings.trash_dir and beneath(path, self.settings.trash_dir))
            or any(r.id != root.id and beneath(Path(r.path), path) for r in roots)
        ):
            raise LibraryError("directory_delete_scope_changed", "图包目录或授权范围已变化，未删除")

    def current(self, db, step):
        row = db.execute(
            select(
                ImagePack.path,
                ImagePack.root_id,
                ImagePack.status,
                PackTrashItem.original_path,
                PackTrashItem.root_path,
                PackTrashItem.status.label("trash_status"),
            )
            .join(PackTrashItem, PackTrashItem.pack_id == ImagePack.id)
            .where(ImagePack.id == step.pack_id, PackTrashItem.id == step.requested_id)
        ).first()
        if (
            not row
            or row.status != "trash"
            or row.trash_status != "active"
            or row.path != step.original_path
        ):
            raise LibraryError("stale_pack_state", "图包回收状态已变化，未删除")
        roots = list(db.scalars(select(Root)))
        self.scope(row, next((r for r in roots if r.id == row.root_id), None), roots)

    def mark(self, step, phase):
        with self.db.write() as db:
            self.current(db, step)
            saved = db.get(PackFileStep, step.id)
            saved.phase = phase
            saved.source_signature = [*step.source_signature[:2], phase]
            step.source_signature = saved.source_signature
        step.phase = phase
        self.checkpoint(phase, step.id)

    def remove(self, step):
        path = Path(step.original_path)
        staged = path.parent / ".video-viewer-tmp" / ("directory-delete-" + step.id)
        with self.db.read() as db:
            self.current(db, step)
        validate_path(str(path), self.settings.mounts)
        observed = file_stat(staged)
        removing = step.phase == "removing" or step.source_signature[2:] == ["removing"]
        if observed is None and not removing:
            observed = file_stat(path)
            if (
                observed is None
                or not stat.S_ISDIR(observed.st_mode)
                or signature(observed)[:2] != step.source_signature[:2]
            ):
                raise LibraryError(
                    "directory_replaced", "图包文件夹不存在或已被替换，未删除其他文件夹"
                )
            self.mark(step, "claiming")
            rename_new(path, staged)
            self.mark(step, "claimed")
            observed = file_stat(staged)
        if observed is not None:
            if (
                not stat.S_ISDIR(observed.st_mode)
                or signature(observed)[:2] != step.source_signature[:2]
            ):
                raise LibraryError("directory_replaced", "后台目录身份已变化，未继续删除")
            self.mark(step, "removing")
            if not shutil.rmtree.avoids_symlink_attacks:
                raise LibraryError("filesystem_unsupported", "当前系统不支持目录安全删除")
            with open_directory(staged.parent) as parent:
                shutil.rmtree(staged.name, dir_fd=parent)
                os.fsync(parent)
            self.checkpoint("removed_before_commit", step.id)
        with self.db.write() as db:
            self.current(db, step)
            # Metadata updates only; do not inspect or hash any media content.
            db.execute(
                update(PackPage)
                .where(PackPage.pack_id == step.pack_id)
                .values(error="permanently_deleted")
            )
            pack = db.get(ImagePack, step.pack_id)
            db.execute(
                update(PackTrashItem)
                .where(PackTrashItem.id == step.requested_id)
                .values(purged_pages=PackTrashItem.purged_pages + pack.page_count, status="purged")
            )
            pack.status, pack.location_key, pack.error, pack.page_count = "deleted", None, None, 0
            pack.generation += 1
            pack.content_version += 1
            saved = db.get(PackFileStep, step.id)
            saved.phase, saved.outcome, saved.error = "committed", "succeeded", None

    def progress(self, identity, *, final=False):
        with self.db.write() as db:
            rows = list(
                db.scalars(select(PackFileStep).where(PackFileStep.operation_id == identity))
            )
            done = [r for r in rows if r.outcome in ("succeeded", "failed")]
            success = sum(r.outcome == "succeeded" for r in rows)
            failed = sum(r.outcome == "failed" for r in rows)
            task = db.get(Task, identity)
            task.result = {
                "operation_id": identity,
                "total": len(rows),
                "processed": len(done),
                "succeeded": success,
                "failed": failed,
                "partial": bool(success and failed),
                "needs_attention": any(r.phase == "needs_attention" for r in rows),
                "items": [
                    {
                        "requested_id": r.requested_id,
                        "trash_id": r.requested_id,
                        "pack_id": r.pack_id,
                        "phase": r.phase,
                        "outcome": r.outcome,
                        "error": r.error,
                    }
                    for r in rows
                ]
                if final
                else [],
                "reading_transition": None,
                "reading_restored": False,
                "undo_expires_at": None,
            }
            if final:
                task.status = "completed" if success else "failed"
                task.phase, task.finished_at = "completed", self.ops.clock()
                task.error = "directory_delete_failed" if failed else None

    def run(self, identity):
        try:
            with self.db.write() as db:
                operation = db.get(PackFileOperation, identity)
                if not operation or operation.historical:
                    return
                task = db.get(Task, identity)
                task.status, task.phase, task.error = "running", "deleting_directories", None
                steps = list(
                    db.scalars(select(PackFileStep).where(PackFileStep.operation_id == identity))
                )
            for step in steps:
                if step.outcome == "succeeded":
                    continue
                self.checkpoint("before_directory", step.id)
                try:
                    self.remove(step)
                except InterruptedError:
                    raise
                except (LibraryError, OSError) as error:
                    with self.db.write() as db:
                        saved = db.get(PackFileStep, step.id)
                        saved.outcome, saved.error = "failed", FileOperations.error_code(error)
                        if step.phase in ("claiming", "claimed", "removing"):
                            saved.phase = "needs_attention"
                self.progress(identity)
            self.progress(identity, final=True)
        except InterruptedError:
            self.ops.failed(identity, "interrupted", "directory_delete_interrupted")
        except Exception:
            self.ops.failed(identity, "interrupted", "directory_delete_interrupted")

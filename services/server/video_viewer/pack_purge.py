"""Durable execution of a confirmed image manifest; never recursive deletion."""

import copy
from pathlib import Path

from sqlalchemy import Integer, func, select, update

from .errors import LibraryError
from .file_operations import FileOperations
from .file_transfer import file_stat
from .management_history import reject_historical
from .models import (
    ImagePack,
    PackFileOperation,
    PackFileStep,
    PackPage,
    PackPurgeEntry,
    PackPurgeExecution,
    PackPurgePlan,
    PackPurgeStep,
    PackTrashItem,
    Root,
    Task,
)
from .pack_purge_io import ImagePurgeTransfer, PurgeTree
from .pack_purge_manifest import digest_json


class PackPurge:
    def __init__(self, operations, plans, settings, *, fault_hook=None):
        self.ops, self.plans, self.settings = operations, plans, settings
        self.db, self.stop = operations.db, operations.stop
        self.fault_hook = fault_hook
        self.rolling_back = False
        self.tree = None
        self.rows = {}

    def check_stop(self):
        if self.stop.is_set():
            raise InterruptedError("service_stopping")

    def checkpoint(self, phase, identity):
        if self.fault_hook:
            self.fault_hook(phase, identity)
        self.check_stop()

    def submit(self, plan_id, plan_digest, request_id):
        payload = {
            "kind": "permanent",
            "plan_id": plan_id,
            "digest": plan_digest,
            "confirmed": True,
        }
        fingerprint = digest_json(payload)
        key = "pack_files:" + request_id
        with self.db.read() as session:
            prior = session.scalar(
                select(PackFileOperation).where(PackFileOperation.request_key == key)
            )
            if prior:
                if prior.historical:
                    reject_historical(session, "pack_file_operations", key)
                if prior.request_hash != fingerprint:
                    raise LibraryError("idempotency_conflict", "请求标识已用于不同的图包操作")
                return prior.id
        if self.stop.is_set():
            raise LibraryError("service_stopping", "服务正在停止", 503)
        with self.db.write() as session:
            prior = session.scalar(
                select(PackFileOperation).where(PackFileOperation.request_key == key)
            )
            if prior:
                if prior.historical:
                    reject_historical(session, "pack_file_operations", key)
                if prior.request_hash != fingerprint:
                    raise LibraryError("idempotency_conflict", "请求标识已用于不同的图包操作")
                return prior.id
            reject_historical(session, "pack_file_operations", key)
            plan = session.get(PackPurgePlan, plan_id)
            task = session.get(Task, plan_id) if plan else None
            if not plan or not task:
                raise LibraryError("pack_purge_plan_not_found", "确认清单不存在", 404)
            if session.scalar(
                select(PackPurgeExecution.id).where(PackPurgeExecution.plan_id == plan_id)
            ):
                raise LibraryError("purge_plan_consumed", "清单已绑定原操作，请查询原回执")
            if plan.historical or task.status != "completed" or not plan.digest:
                raise LibraryError("purge_plan_not_ready", "图片清单不可用于确认")
            if self.ops.clock() > plan.expires_at:
                raise LibraryError("purge_plan_expired", "确认清单已过期，请重新核对")
            if plan.digest != plan_digest:
                raise LibraryError("purge_plan_changed", "确认摘要与准备清单不一致")
            entries = list(
                session.execute(
                    select(
                        PackPurgeEntry.id,
                        PackPurgeEntry.trash_id,
                        PackPurgeEntry.digest,
                    )
                    .where(PackPurgeEntry.plan_id == plan_id)
                    .order_by(PackPurgeEntry.trash_id)
                )
            )
            if (
                not entries
                or len(entries) > 1000
                or digest_json(
                    [{"trash_id": row.trash_id, "digest": row.digest} for row in entries]
                )
                != plan_digest
            ):
                raise LibraryError("purge_plan_changed", "确认清单不完整")
            task = Task(kind="pack_permanent", status="queued", phase="queued", result={})
            session.add(task)
            session.flush()
            operation = PackFileOperation(
                id=task.id,
                kind="permanent",
                request_key=key,
                request_hash=fingerprint,
                session_snapshot={"plan_id": plan_id, "digest": plan_digest},
                historical=False,
            )
            session.add(operation)
            session.flush()
            session.add(PackPurgeExecution(id=task.id, plan_id=plan_id))
            last_undo = self.ops.pointer(session, "last_pack_delete_operation")
            invalidate_undo = False
            for selected in entries:
                entry = session.get(PackPurgeEntry, selected.id)
                if not entry.manifest or entry.error or digest_json(entry.manifest) != entry.digest:
                    raise LibraryError("purge_plan_changed", "图片清单已变化")
                if session.get(PackTrashItem, entry.trash_id).operation_id == last_undo:
                    invalidate_undo = True
                if self.plans.source(session, entry.trash_id) != entry.source:
                    raise LibraryError("pack_changed", "图包在准备后变化，请重新核对")
                step = PackFileStep(
                    operation_id=task.id,
                    pack_id=entry.pack_id,
                    requested_id=entry.trash_id,
                    root_path=entry.source["root_path"],
                    original_path=entry.path,
                    expected_hash=entry.digest,
                    expected_size=entry.image_bytes,
                    source_signature=entry.manifest["directory_stamp"],
                )
                session.add(step)
                session.flush()
                for index, page in enumerate(entry.manifest["files"]):
                    session.add(
                        PackPurgeStep(
                            parent_id=step.id,
                            kind="image",
                            page_id=page["id"],
                            relative_path=page["relative_path"],
                            source_signature=page["signature"],
                            expected_hash=page["sha256"],
                            expected_size=page["size"],
                        )
                    )
                    if index % 256 == 255:
                        session.flush()
                for index, (name, item) in enumerate(entry.manifest["tree"].items()):
                    if item["kind"] == "directory":
                        session.add(
                            PackPurgeStep(
                                parent_id=step.id,
                                kind="directory",
                                relative_path=name,
                                source_signature=item["signature"],
                            )
                        )
                    if index % 256 == 255:
                        session.flush()
                session.flush()
                session.expunge(entry)
            if invalidate_undo:
                self.ops.set_pointer(session, "last_pack_delete_operation", "")
            identity = task.id
        self.ops.enqueue(identity)
        return identity

    def check_database(self, parent, manifest, rows, *, full=False, session=None):
        if session is None:
            with self.db.read() as opened:
                return self.check_database(parent, manifest, rows, full=full, session=opened)
        operation = session.get(PackFileOperation, parent.operation_id)
        execution = session.get(PackPurgeExecution, parent.operation_id)
        accepted_plan = session.get(PackPurgePlan, execution.plan_id) if execution else None
        if not operation or operation.historical or not accepted_plan or accepted_plan.historical:
            raise LibraryError("historical_operation", "历史删除只可查看")
        source = manifest["source"]
        pack, root = session.get(ImagePack, parent.pack_id), session.get(Root, source["root_id"])
        item = session.get(PackTrashItem, parent.requested_id)
        deleted = sum(row.kind == "image" and row.outcome == "succeeded" for row in rows)
        if (
            not pack
            or not item
            or item.status != "active"
            or (
                pack.status != "trash"
                or pack.path != source["path"]
                or pack.root_id != source["root_id"]
                or pack.generation != source["generation"] + deleted
                or pack.content_version != source["content_version"] + deleted
                or pack.page_count != len(source["pages"]) - deleted
            )
        ):
            raise LibraryError("stale_pack_state", "图包状态已变化，未继续删除")
        if not root or not root.enabled or not root.available or root.path != source["root_path"]:
            raise LibraryError("root_unavailable", "图包目录未启用或暂不可用")
        policy = sorted(
            [[r.id, r.path, r.kind, r.enabled, r.mount_id] for r in session.scalars(select(Root))]
        )
        if policy != source["root_policy"]:
            raise LibraryError("root_changed", "图包目录授权已变化")
        if full:
            expected = copy.deepcopy(source)
            expected["generation"] += deleted
            expected["content_version"] += deleted
            images = {row.page_id: row for row in rows if row.kind == "image"}
            expected["pages"] = [
                {
                    **page,
                    "signature": images[page["id"]].state.get(
                        "source_signature", page["signature"]
                    ),
                }
                for page in source["pages"]
                if images[page["id"]].outcome != "succeeded"
            ]
            current = self.plans.source(
                session, item.id, exclude_operation=operation.id, allow_empty=True
            )
            if current != expected:
                raise LibraryError("pack_changed", "图包索引已变化，请重新核对")

    def mark(self, identity, phase, **values):
        row = self.rows[identity]
        with self.db.write() as session:
            self.check_database(
                self.tree.parent, self.tree.manifest, self.tree.rows, session=session
            )
            state = {**row.state, **values}
            session.execute(
                update(PackPurgeStep)
                .where(PackPurgeStep.id == identity)
                .values(
                    phase=phase,
                    state=state,
                )
            )
            if phase == "rolled_back" and row.kind == "image" and values.get("source_signature"):
                if values["source_signature"][:2] == row.source_signature[:2]:
                    page = session.get(PackPage, row.page_id)
                    if page and page.pack_id == self.tree.parent.pack_id:
                        page.signature = values["source_signature"]
        row.phase, row.state = phase, state
        self.checkpoint("purge_" + phase, identity)
        if phase == "purging" and not self.rolling_back:
            self.tree.check()

    def commit_image(self, row):
        if row.outcome == "succeeded":
            return
        self.checkpoint("purge_unlinked_before_commit", row.id)
        with self.db.write() as session:
            self.check_database(
                self.tree.parent, self.tree.manifest, self.tree.rows, session=session
            )
            stored = session.get(PackPurgeStep, row.id)
            if stored.outcome == "succeeded":
                return
            pack = session.get(ImagePack, self.tree.parent.pack_id)
            page = session.get(PackPage, row.page_id)
            if not page or page.pack_id != pack.id:
                raise LibraryError("pack_changed", "图片元数据已变化，需核对已删除结果")
            page.error = "permanently_deleted"
            pack.page_count -= 1
            pack.generation += 1
            pack.content_version += 1
            session.get(PackTrashItem, self.tree.parent.requested_id).purged_pages += 1
            stored.phase, stored.outcome, stored.error = "committed", "succeeded", None
        row.phase, row.outcome, row.error = "committed", "succeeded", None
        self.checkpoint("purge_image_committed", row.id)

    def commit_directory(self, row, outcome):
        phase = "committed" if outcome == "succeeded" else "retained"
        with self.db.write() as session:
            self.check_database(
                self.tree.parent, self.tree.manifest, self.tree.rows, session=session
            )
            session.execute(
                update(PackPurgeStep)
                .where(PackPurgeStep.id == row.id)
                .values(
                    phase=phase,
                    outcome=outcome,
                    error=None,
                )
            )
        row.phase, row.outcome, row.error = phase, outcome, None

    def run_parent(self, parent, manifest, rows):
        images = {row.page_id: row for row in rows if row.kind == "image"}
        planned = {page["id"]: page for page in manifest["files"]}
        directories = {row.relative_path: row for row in rows if row.kind == "directory"}
        planned_dirs = {
            name: data["signature"]
            for name, data in manifest["tree"].items()
            if data["kind"] == "directory"
        }
        if (
            len(images) != len(planned)
            or set(images) != set(planned)
            or set(directories) != set(planned_dirs)
        ):
            raise LibraryError("invalid_purge_journal", "执行日志与确认清单不一致")
        for page_id, row in images.items():
            page = planned[page_id]
            if (row.relative_path, row.source_signature, row.expected_hash, row.expected_size) != (
                page["relative_path"],
                page["signature"],
                page["sha256"],
                page["size"],
            ):
                raise LibraryError("invalid_purge_journal", "图片执行日志身份不一致")
        if any(row.source_signature != planned_dirs[name] for name, row in directories.items()):
            raise LibraryError("invalid_purge_journal", "目录执行日志身份不一致")
        self.rows = {row.id: row for row in rows}
        self.tree = PurgeTree(self, parent, manifest, rows)
        transfer = ImagePurgeTransfer(self.stop, self.mark, self.tree.validate_transfer)
        self.check_database(parent, manifest, rows, full=True)
        # Finish/return owned directory claims before walking their original
        # paths; the original pack path may itself be temporarily claimed.
        for row in rows:
            if (
                row.kind == "directory"
                and row.outcome not in ("succeeded", "retained")
                and (file_stat(self.tree.staging(row)) or row.phase == "removing")
            ):
                self.tree.directory(row)
        self.tree.check(full=True)
        for row in rows:
            if row.kind != "image" or row.outcome == "succeeded":
                continue
            try:
                self.check_stop()
                self.tree.check()
                transfer.execute(self.tree.transfer_step(row), "permanent")
                self.commit_image(row)
            except InterruptedError:
                raise
            except (LibraryError, OSError) as failure:
                if row.outcome == "succeeded":
                    raise
                self.rolling_back = True
                try:
                    transfer.rollback(self.tree.transfer_step(row), "permanent")
                except (LibraryError, OSError):
                    pass
                finally:
                    self.rolling_back = False
                self.fail_page(row, failure)
                raise
        self.tree.check(full=True)
        directories = sorted(
            (r for r in rows if r.kind == "directory"),
            key=lambda r: (len(Path(r.relative_path).parts), r.relative_path),
            reverse=True,
        )
        for row in directories:
            if row.outcome in ("succeeded", "retained"):
                continue
            try:
                self.tree.directory(row)
            except InterruptedError:
                raise
            except (LibraryError, OSError) as failure:
                try:
                    self.tree.restore_directory(row)
                except (LibraryError, OSError):
                    pass  # Keep the owned claim and its reservation visible.
                self.fail_page(row, failure)
                raise
        self.tree.check(full=True)
        with self.db.write() as session:
            self.check_database(parent, manifest, rows, session=session)
            pack = session.get(ImagePack, parent.pack_id)
            pack.status, pack.location_key, pack.error = "deleted", None, None
            pack.generation += 1
            session.get(PackTrashItem, parent.requested_id).status = "purged"
            stored = session.get(PackFileStep, parent.id)
            stored.phase, stored.outcome, stored.error = "committed", "succeeded", None

    def fail_page(self, row, failure):
        code = FileOperations.error_code(failure)
        with self.db.write() as session:
            committed = session.get(PackPurgeStep, row.id)
            if committed.outcome == "succeeded":
                row.phase, row.outcome, row.error = (
                    committed.phase,
                    committed.outcome,
                    committed.error,
                )
                return
            session.execute(
                update(PackPurgeStep)
                .where(PackPurgeStep.id == row.id)
                .values(outcome="failed", error=code)
            )
        row.outcome, row.error = "failed", code

    def run(self, identity):
        try:
            self.check_stop()
            with self.db.write() as session:
                operation = session.get(PackFileOperation, identity)
                if not operation or operation.historical:
                    return
                session.get(Task, identity).status = "running"
                session.get(Task, identity).phase = "purging_images"
                parent_ids = list(
                    session.scalars(
                        select(PackFileStep.id)
                        .where(
                            PackFileStep.operation_id == identity,
                            PackFileStep.outcome == "pending",
                        )
                        .order_by(PackFileStep.id)
                    )
                )
            for parent_id in parent_ids:
                self.check_stop()
                with self.db.read() as session:
                    parent = session.get(PackFileStep, parent_id)
                    execution = session.get(PackPurgeExecution, identity)
                    entry = session.scalar(
                        select(PackPurgeEntry).where(
                            PackPurgeEntry.plan_id == execution.plan_id,
                            PackPurgeEntry.trash_id == parent.requested_id,
                        )
                    )
                    rows = list(
                        session.scalars(
                            select(PackPurgeStep)
                            .where(PackPurgeStep.parent_id == parent_id)
                            .order_by(PackPurgeStep.relative_path, PackPurgeStep.id)
                        )
                    )
                    manifest = entry.manifest if entry else None
                try:
                    if not manifest or digest_json(manifest) != parent.expected_hash:
                        raise LibraryError("purge_plan_changed", "执行清单身份已变化")
                    self.tree = None
                    self.run_parent(parent, manifest, rows)
                except InterruptedError:
                    raise
                except (LibraryError, OSError) as failure:
                    try:
                        owned = any(
                            row.phase not in ("prepared", "rolled_back", "retained", "committed")
                            and (
                                file_stat(
                                    Path(parent.root_path)
                                    / ".video-viewer-tmp"
                                    / "pack-purge"
                                    / identity
                                    / parent.id
                                    / row.kind
                                    / row.id
                                )
                                or (
                                    row.phase in ("purging", "removing")
                                    and not file_stat(
                                        Path(parent.original_path) / row.relative_path
                                    )
                                )
                            )
                            for row in rows
                        )
                    except OSError:
                        owned = True
                    with self.db.write() as session:
                        stored = session.get(PackFileStep, parent_id)
                        if stored.outcome != "succeeded":
                            stored.outcome, stored.error = (
                                "failed",
                                FileOperations.error_code(failure),
                            )
                            stored.phase = "needs_attention" if owned else "prepared"
                self.finish(identity, final=False)
            self.finish(identity, final=True)
        except InterruptedError:
            self.ops.failed(identity, "interrupted", "operation_recovery_required")
        except Exception:
            self.ops.failed(identity, "interrupted", "operation_recovery_required")
        finally:
            self.tree, self.rows = None, {}

    def finish(self, identity, *, final):
        with self.db.write() as session:
            parents = list(
                session.scalars(select(PackFileStep).where(PackFileStep.operation_id == identity))
            )
            succeeded = sum(p.outcome == "succeeded" for p in parents)
            page_stats = {
                row.parent_id: row
                for row in session.execute(
                    select(
                        PackPurgeStep.parent_id,
                        func.count().label("total"),
                        func.sum((PackPurgeStep.outcome == "succeeded").cast(Integer)).label(
                            "deleted"
                        ),
                    )
                    .join(PackFileStep)
                    .where(PackFileStep.operation_id == identity, PackPurgeStep.kind == "image")
                    .group_by(PackPurgeStep.parent_id)
                )
            }
            deleted = sum(row.deleted for row in page_stats.values())
            uncertain = session.scalar(
                select(func.count())
                .select_from(PackPurgeStep)
                .join(PackFileStep)
                .where(
                    PackFileStep.operation_id == identity,
                    PackPurgeStep.kind == "image",
                    PackPurgeStep.phase == "purging",
                    PackPurgeStep.outcome != "succeeded",
                )
            )
            task = session.get(Task, identity)
            task.result = {
                "operation_id": identity,
                "total": len(parents),
                "processed": sum(p.outcome != "pending" for p in parents),
                "succeeded": succeeded,
                "failed": sum(p.outcome == "failed" for p in parents),
                "partial": deleted > 0 and succeeded != len(parents),
                "needs_attention": any(p.phase == "needs_attention" for p in parents),
                "pages_pending_reconciliation": uncertain,
                "pages_deleted": deleted,
                "pages_total": sum(row.total for row in page_stats.values()),
                "items": [
                    {
                        "requested_id": p.requested_id,
                        "trash_id": p.requested_id,
                        "pack_id": p.pack_id,
                        "outcome": p.outcome,
                        "phase": p.phase,
                        "error": p.error,
                        "pages_deleted": page_stats[p.id].deleted,
                        "pages_total": page_stats[p.id].total,
                    }
                    for p in parents
                ],
                "reading_transition": None,
                "reading_restored": False,
                "undo_expires_at": None,
            }
            if final:
                task.status = "completed" if succeeded else "failed"
                task.phase = (
                    "needs_attention"
                    if any(p.phase == "needs_attention" for p in parents)
                    else "completed"
                )
                task.finished_at = self.ops.clock()
                task.error = next((p.error for p in parents if p.error), None)

    def pages(self, identity, offset=0, limit=100, *, kind="all", outcome="all"):
        with self.db.read() as session:
            statement = (
                select(PackPurgeStep, ImagePack.id, ImagePack.name)
                .select_from(PackPurgeStep)
                .join(PackFileStep)
                .join(ImagePack, PackFileStep.pack_id == ImagePack.id)
                .where(PackFileStep.operation_id == identity)
            )
            if kind != "all":
                statement = statement.where(PackPurgeStep.kind == kind)
            if outcome == "unfinished":
                statement = statement.where(PackPurgeStep.outcome.not_in(("succeeded", "retained")))
            if not session.get(PackPurgeExecution, identity):
                raise LibraryError("pack_operation_not_found", "图包永久删除操作不存在", 404)
            rows = session.execute(
                statement.order_by(
                    PackFileStep.id, PackPurgeStep.kind.desc(), PackPurgeStep.relative_path
                )
                .offset(offset)
                .limit(limit)
            )
            return {
                "items": [
                    {
                        **{
                            key: getattr(row, key)
                            for key in (
                                "id",
                                "parent_id",
                                "kind",
                                "page_id",
                                "relative_path",
                                "phase",
                                "outcome",
                                "error",
                            )
                        },
                        "pack_id": pack_id,
                        "pack_name": pack_name,
                    }
                    for row, pack_id, pack_name in rows
                ],
                "total": session.scalar(select(func.count()).select_from(statement.subquery())),
                "offset": offset,
                "limit": limit,
            }

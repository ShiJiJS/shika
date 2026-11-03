"""Durable background preparation of exact image-only deletion confirmations.

This stage never authorizes or performs deletion. A later execution command must
bind the ready digest and revalidate both management and filesystem evidence.
"""

import threading
import time
from concurrent.futures import ThreadPoolExecutor

from sqlalchemy import select, update

from .errors import LibraryError
from .management_history import reject_historical
from .models import (
    ImagePack,
    PackPage,
    PackPurgeEntry,
    PackPurgeExecution,
    PackPurgePlan,
    PackTrashItem,
    Root,
    Task,
)
from .pack_purge_manifest import PurgeManifest, digest_json
from .pack_scanner import reserved_packs


class PackPurgePlans:
    lifetime = 15 * 60

    def __init__(self, db, settings, *, clock=time.time, fault_hook=None):
        self.db, self.settings, self.clock = db, settings, clock
        self.fault_hook = fault_hook
        self.stop = threading.Event()
        self.lock = threading.RLock()
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="pack-purge-preview")
        self.futures = {}
        self.inspector = PurgeManifest(settings, self.check_stop, self.checkpoint)

    def checkpoint(self, phase, identity):
        if self.fault_hook:
            self.fault_hook(phase, identity)
        self.check_stop()

    def check_stop(self):
        if self.stop.is_set():
            raise InterruptedError("service_stopping")

    @staticmethod
    def source(session, trash_id, *, exclude_operation=None, allow_empty=False):
        item = session.get(PackTrashItem, trash_id)
        pack = session.get(ImagePack, item.pack_id) if item else None
        root = session.get(Root, pack.root_id) if pack else None
        if not item or not pack or not root or root.kind != "pack":
            raise LibraryError("pack_operation_item_not_found", "图包回收记录不存在", 404)
        if item.status != "active" or pack.status != "trash":
            raise LibraryError("stale_pack_state", "图包已恢复或回收状态已变化")
        if not root.enabled or not root.available or not root.mount_id:
            raise LibraryError("root_unavailable", "图包目录未启用、未映射或暂不可用")
        if item.original_path != pack.path or item.root_path != root.path:
            raise LibraryError("pack_changed", "图包接入位置与回收记录不同")
        reservation = reserved_packs(pack_id=pack.id, exclude_operation=exclude_operation)
        if session.scalar(reservation.limit(1)):
            raise LibraryError("operation_busy", "图包已有待执行操作，请稍后核对")
        pages = list(
            session.scalars(
                select(PackPage)
                .where(
                    PackPage.pack_id == pack.id,
                    PackPage.error.is_distinct_from("permanently_deleted"),
                )
                .order_by(PackPage.ordinal, PackPage.id)
            )
        )
        if (not pages and not allow_empty) or len(pages) != pack.page_count:
            raise LibraryError("invalid_page_manifest", "图包图片清单不完整")
        return {
            "pack_id": pack.id,
            "trash_id": item.id,
            "name": pack.name,
            "path": pack.path,
            "root_id": root.id,
            "root_path": root.path,
            "mount_id": root.mount_id,
            "root_policy": sorted(
                [
                    [r.id, r.path, r.kind, r.enabled, r.mount_id]
                    for r in session.scalars(select(Root))
                ]
            ),
            "generation": pack.generation,
            "content_version": pack.content_version,
            "directory_identity": [pack.device, pack.inode],
            "directory_signature": pack.directory_signature,
            "pages": [
                {
                    key: getattr(page, key)
                    for key in ("id", "path", "relative_path", "signature", "sha256", "size")
                }
                for page in pages
            ],
        }

    @staticmethod
    def prior(session, request_id, digest):
        plan = session.scalar(
            select(PackPurgePlan).where(
                PackPurgePlan.request_key == "pack_purge_preview:" + request_id
            )
        )
        if plan and plan.historical:
            reject_historical(session, "pack_purge_plans", "pack_purge_preview:" + request_id)
        if plan and plan.request_hash != digest:
            raise LibraryError("idempotency_conflict", "请求标识已用于不同的图片清单")
        return plan.id if plan else None

    def submit(self, trash_ids, request_id):
        if not self.settings.legacy_purge_previews:
            raise LibraryError("preview_superseded", "请更新App后直接提交图包文件夹后台删除", 410)
        ids = sorted(set(trash_ids))
        if not 1 <= len(ids) <= 1000:
            raise LibraryError("invalid_pack_operation", "每次请选择1至1000个图包", 422)
        digest = digest_json({"kind": "pack_purge_preview", "trash_ids": ids})
        with self.db.read() as session:
            prior = self.prior(session, request_id, digest)
            if prior:
                return prior
        if self.stop.is_set():
            raise LibraryError("service_stopping", "服务正在停止", 503)
        with self.db.write() as session:
            prior = self.prior(session, request_id, digest)
            if prior:
                return prior
            reject_historical(session, "pack_purge_plans", "pack_purge_preview:" + request_id)
            task = Task(kind="pack_purge_preview", status="queued", phase="queued", result={})
            session.add(task)
            session.flush()
            plan = PackPurgePlan(
                id=task.id,
                request_key="pack_purge_preview:" + request_id,
                request_hash=digest,
                expires_at=self.clock() + self.lifetime,
            )
            session.add(plan)
            session.flush()
            for trash_id in ids:
                source = self.source(session, trash_id)
                entry = PackPurgeEntry(
                    plan_id=plan.id,
                    pack_id=source["pack_id"],
                    trash_id=source["trash_id"],
                    source=source,
                    name=source["name"],
                    path=source["path"],
                )
                session.add(entry)
                session.flush()
                session.expunge(entry)
            identity = plan.id
        self.enqueue(identity)
        return identity

    def enqueue(self, identity):
        with self.lock:
            future = self.futures.get(identity)
            if not future or future.done():
                self.futures[identity] = self.executor.submit(self.run, identity)

    def start(self):
        if not self.settings.legacy_purge_previews:
            with self.db.write() as session:
                session.execute(
                    update(Task)
                    .where(
                        Task.kind == "pack_purge_preview",
                        Task.id.in_(select(PackPurgePlan.id).where(PackPurgePlan.historical.is_(False))),
                        Task.status.in_(("queued", "running", "interrupted")),
                    )
                    .values(
                        status="interrupted",
                        phase="interrupted",
                        error="preview_superseded",
                        finished_at=self.clock(),
                    )
                )
            return
        with self.db.write() as session:
            ids = list(
                session.scalars(
                    select(PackPurgePlan.id)
                    .join(Task)
                    .where(
                        PackPurgePlan.historical.is_(False),
                        Task.status.in_(("queued", "running", "interrupted")),
                    )
                    .order_by(Task.created_at, Task.id)
                )
            )
            for identity in ids:
                task = session.get(Task, identity)
                task.status, task.phase, task.error = "queued", "queued", None
                # Never combine a prior process's fingerprints with fresh ones.
                session.execute(
                    update(PackPurgeEntry)
                    .where(PackPurgeEntry.plan_id == identity)
                    .values(
                        manifest=None,
                        digest=None,
                        error=None,
                        image_count=0,
                        image_bytes=0,
                        retained_entries=0,
                    )
                )
        for identity in ids:
            self.enqueue(identity)

    def run(self, identity):
        try:
            self.check_stop()
            with self.db.write() as session:
                task = session.get(Task, identity)
                task.status, task.phase, task.error = "running", "fingerprinting", None
                entries = list(
                    session.scalars(
                        select(PackPurgeEntry.id)
                        .where(PackPurgeEntry.plan_id == identity)
                        .order_by(PackPurgeEntry.trash_id)
                    )
                )
            self.checkpoint("purge_preview_started", identity)
            for entry_id in entries:
                with self.db.read() as session:
                    entry = session.get(PackPurgeEntry, entry_id)
                self.check_stop()
                error, manifest = None, None
                try:
                    with self.db.read() as session:
                        if self.source(session, entry.trash_id) != entry.source:
                            raise LibraryError("pack_changed", "图包管理数据在准备期间变化")
                        roots = list(session.scalars(select(Root)))
                    manifest = self.inspector.build(entry.source, roots)
                    self.checkpoint("purge_before_manifest_commit", entry.id)
                    with self.db.read() as session:
                        current_roots = list(session.scalars(select(Root)))
                        before = [(r.id, r.path, r.kind, r.enabled, r.mount_id) for r in roots]
                        after = [
                            (r.id, r.path, r.kind, r.enabled, r.mount_id) for r in current_roots
                        ]
                        if self.source(session, entry.trash_id) != entry.source or sorted(
                            before
                        ) != sorted(after):
                            raise LibraryError("pack_changed", "图包或目录授权在准备期间变化")
                except LibraryError as failure:
                    error = failure.code
                except OSError:
                    error = "image_unavailable"
                with self.db.write() as session:
                    # Recheck within the same short transaction that publishes
                    # the fingerprint; all hashing remains outside this lock.
                    if not error:
                        try:
                            if self.source(session, entry.trash_id) != entry.source:
                                error = "pack_changed"
                        except LibraryError as failure:
                            error = failure.code
                    session.execute(
                        update(PackPurgeEntry)
                        .where(PackPurgeEntry.id == entry.id)
                        .values(
                            manifest=manifest if not error else None,
                            digest=digest_json(manifest) if not error else None,
                            error=error,
                            **{
                                key: manifest[key] if not error else 0
                                for key in (
                                    "image_count",
                                    "image_bytes",
                                    "retained_entries",
                                )
                            },
                        )
                    )
                self.progress(identity)
            with self.db.write() as session:
                plan = session.get(PackPurgePlan, identity)
                digests = []
                for row in session.execute(
                    select(
                        PackPurgeEntry.id,
                        PackPurgeEntry.trash_id,
                        PackPurgeEntry.source,
                        PackPurgeEntry.error,
                        PackPurgeEntry.digest,
                    )
                    .where(PackPurgeEntry.plan_id == identity)
                    .order_by(PackPurgeEntry.trash_id)
                ).yield_per(1):
                    if row.error or not row.digest:
                        continue
                    try:
                        if self.source(session, row.trash_id) != row.source:
                            raise LibraryError("pack_changed", "图包管理数据在准备期间变化")
                    except LibraryError as failure:
                        session.execute(
                            update(PackPurgeEntry)
                            .where(PackPurgeEntry.id == row.id)
                            .values(
                                error=failure.code,
                                manifest=None,
                                digest=None,
                                image_count=0,
                                image_bytes=0,
                                retained_entries=0,
                            )
                        )
                    else:
                        digests.append({"trash_id": row.trash_id, "digest": row.digest})
                rows = self.summaries(session, identity)
                task = session.get(Task, identity)
                task.result = self.result(rows)
                failed = not rows or any(row.error or not row.digest for row in rows)
                plan.digest = None if failed else digest_json(digests)
                plan.expires_at = self.clock() + self.lifetime
                task.status, task.phase = ("failed", "failed") if failed else ("completed", "ready")
                task.error = "purge_preview_failed" if failed else None
                task.finished_at = self.clock()
            self.checkpoint("purge_preview_ready", identity)
        except InterruptedError:
            self.fail(identity, "interrupted", "preview_interrupted")
        except Exception:
            self.fail(identity, "failed", "purge_preview_internal_error")

    @staticmethod
    def result(rows):
        successes = sum(row.digest is not None for row in rows)
        failures = sum(row.error is not None for row in rows)
        return {
            "total": len(rows),
            "processed": successes + failures,
            "succeeded": successes,
            "failed": failures,
            "image_count": sum(row.image_count for row in rows),
            "image_bytes": sum(row.image_bytes for row in rows),
        }

    @staticmethod
    def summaries(session, identity):
        # These columns deliberately exclude source/manifest JSON. A task list
        # must not deserialize every selected pack's full image inventory.
        return list(
            session.execute(
                select(
                    PackPurgeEntry.id,
                    PackPurgeEntry.trash_id,
                    PackPurgeEntry.pack_id,
                    PackPurgeEntry.name,
                    PackPurgeEntry.path,
                    PackPurgeEntry.digest,
                    PackPurgeEntry.error,
                    PackPurgeEntry.image_count,
                    PackPurgeEntry.image_bytes,
                    PackPurgeEntry.retained_entries,
                )
                .where(PackPurgeEntry.plan_id == identity)
                .order_by(PackPurgeEntry.trash_id)
            )
        )

    def progress(self, identity):
        with self.db.write() as session:
            session.get(Task, identity).result = self.result(self.summaries(session, identity))

    def fail(self, identity, status, error):
        with self.db.write() as session:
            task = session.get(Task, identity)
            task.status, task.phase, task.error, task.finished_at = (
                status,
                status,
                error,
                self.clock(),
            )

    def view(self, identity=None, *, request_id=None):
        with self.db.read() as session:
            criterion = (
                PackPurgePlan.request_key == "pack_purge_preview:" + request_id
                if request_id
                else PackPurgePlan.id == identity
            )
            # SQLite's legacy SELECT mode does not hold a transaction snapshot
            # across independent ORM gets. Fetch state and digest in one row so
            # a concurrent completion cannot produce completed + old digest.
            pair = session.execute(
                select(PackPurgePlan, Task)
                .join(
                    Task,
                    PackPurgePlan.id == Task.id,
                )
                .where(criterion)
            ).first()
            if not pair:
                raise LibraryError("pack_purge_plan_not_found", "未找到已受理的图片清单", 404)
            plan, task = pair
            now = self.clock()
            rows = self.summaries(session, plan.id)
            consumed = session.scalar(
                select(PackPurgeExecution.id).where(PackPurgeExecution.plan_id == plan.id)
            )
            return {
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
                "server_time": now,
                "expires_at": plan.expires_at,
                "digest": plan.digest,
                "historical": plan.historical,
                "operation_id": consumed,
                "ready": not consumed
                and not plan.historical
                and task.status == "completed"
                and bool(plan.digest)
                and now <= plan.expires_at,
                "items": [
                    {
                        "trash_id": row.trash_id,
                        "pack_id": row.pack_id,
                        "name": row.name,
                        "path": row.path,
                        "digest": row.digest,
                        "error": row.error,
                        **{
                            key: getattr(row, key)
                            for key in ("image_count", "image_bytes", "retained_entries")
                        },
                    }
                    for row in rows
                ],
            }

    def files(self, identity, trash_id, offset=0, limit=100):
        with self.db.read() as session:
            entry = session.scalar(
                select(PackPurgeEntry).where(
                    PackPurgeEntry.plan_id == identity,
                    PackPurgeEntry.trash_id == trash_id,
                )
            )
            if not entry:
                raise LibraryError("pack_purge_plan_not_found", "清单或其中的图包不存在", 404)
            if not entry.manifest:
                raise LibraryError("pack_purge_plan_not_ready", "该图包清单尚未核对完成")
            files = entry.manifest["files"]
            return {
                "items": files[offset : offset + limit],
                "total": len(files),
                "offset": offset,
                "limit": limit,
            }

    def close(self):
        self.stop.set()
        self.executor.shutdown(wait=True, cancel_futures=True)

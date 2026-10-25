"""Fixed-scope, restartable metadata cleanup; never modifies source bytes."""

import os
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from sqlalchemy import delete, func, insert, literal, select

from .errors import LibraryError
from .media_roots import owner_for_path
from .models import (
    ImagePack,
    PackMissingCleanup,
    PackMissingMember,
    PackPreferences,
    PackProgress,
    PackTagLink,
    PackTrashItem,
    RecentEntry,
    Root,
    Task,
)
from .pack_scanner import reserved_packs
from .paths import open_directory
from .requests import once


class PackMissing:
    def __init__(self, db, *, batch_size=100, fault_hook=None):
        if not 1 <= batch_size <= 100:
            raise ValueError("Invalid cleanup batch size")
        self.db, self.batch_size, self.fault_hook = db, batch_size, fault_hook
        self.stop = threading.Event()
        self.lock = threading.Lock()
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="pack-missing")
        self.futures = {}

    def checkpoint(self, phase, identity):
        if self.fault_hook:
            self.fault_hook(phase, identity)

    def submit(self, request_id):
        if self.stop.is_set():
            raise LibraryError("service_stopping", "服务正在停止", 503)
        with self.db.write() as session:

            def action():
                if session.scalar(
                    select(Task.id)
                    .where(
                        Task.kind.in_(("scan", "pack_forget_missing")),
                        Task.status.in_(("queued", "running")),
                    )
                    .limit(1)
                ):
                    raise LibraryError("cleanup_busy", "请等待同步或原清理任务完成后再清理")
                task = Task(kind="pack_forget_missing", status="queued", phase="queued", result={})
                session.add(task)
                session.flush()
                session.add(PackMissingCleanup(id=task.id, request_id=request_id))
                session.flush()
                # The database fixes all members without loading the library or
                # a giant ID list into either HTTP admission or task JSON.
                session.execute(
                    insert(PackMissingMember).from_select(
                        [
                            "cleanup_id",
                            "pack_id",
                            "root_id",
                            "generation",
                            "name",
                            "path",
                            "outcome",
                        ],
                        select(
                            literal(task.id),
                            ImagePack.id,
                            ImagePack.root_id,
                            ImagePack.generation,
                            ImagePack.name,
                            ImagePack.path,
                            literal("pending"),
                        ).where(ImagePack.status == "missing"),
                    )
                )
                total = session.scalar(
                    select(func.count())
                    .select_from(PackMissingMember)
                    .where(PackMissingMember.cleanup_id == task.id)
                )
                task.result = {
                    "total": total,
                    "processed": 0,
                    "succeeded": 0,
                    "failed": 0,
                    "skipped": 0,
                    "partial": False,
                }
                return {"id": task.id}

            result = once(session, "packs.forget_missing", request_id, {"confirmed": True}, action)
        self.schedule(result["id"])
        return result["id"]

    def receipt(self, request_id):
        with self.db.read() as session:
            identity = session.scalar(
                select(PackMissingCleanup.id).where(PackMissingCleanup.request_id == request_id)
            )
            if not identity:
                raise LibraryError("cleanup_request_not_found", "未找到原清理请求；未重新提交", 404)
            return identity

    @staticmethod
    def reason(session, member):
        pack = session.get(ImagePack, member.pack_id)
        if (
            not pack
            or pack.status != "missing"
            or pack.generation != member.generation
            or pack.path != member.path
            or pack.root_id != member.root_id
        ):
            return "图包状态已变化，记录保留"
        if session.scalar(reserved_packs(pack_id=pack.id).limit(1)) or session.scalar(
            select(PackTrashItem.id)
            .where(PackTrashItem.pack_id == pack.id, PackTrashItem.status == "active")
            .limit(1)
        ):
            return "已有文件操作或回收记录，记录保留"
        if session.scalar(
            select(Task.id)
            .where(Task.kind == "scan", Task.status.in_(("queued", "running")))
            .limit(1)
        ):
            return "目录正在同步，记录保留"
        roots = list(session.scalars(select(Root)))
        root = session.get(Root, member.root_id)
        owner = owner_for_path(member.path, roots, kind="pack")
        if (
            not root
            or not root.enabled
            or not root.available
            or not root.mount_id
            or root.kind != "pack"
            or root.last_scan is None
            or not owner
            or owner.id != root.id
        ):
            return "目录未启用、暂不可用或归属已变化，记录保留"
        try:
            with open_directory(Path(root.path)) as root_fd:
                identity = os.fstat(root_fd)
                try:
                    with open_directory(Path(member.path).parent) as parent_fd:
                        os.stat(Path(member.path).name, dir_fd=parent_fd, follow_symlinks=False)
                    return "内容已重新出现，请同步后核对"
                except FileNotFoundError:
                    pass
                # A vanished/replaced root must preserve this member, even if
                # looking up the pack above happened to report ENOENT.
                with open_directory(Path(root.path)) as current_fd:
                    current = os.fstat(current_fd)
                    if (identity.st_dev, identity.st_ino) != (current.st_dev, current.st_ino):
                        return "目录已变化，记录保留"
        except OSError:
            return "目录无法可靠核对，记录保留"
        return None

    def step(self, identity, pack_id):
        with self.db.write() as session:
            plan = session.get(PackMissingCleanup, identity)
            task = session.get(Task, identity)
            if not plan or plan.historical or task.status not in ("queued", "running"):
                return False
            member = session.get(PackMissingMember, (identity, pack_id))
            if not member or member.outcome != "pending":
                return True
            reason = self.reason(session, member)
            if reason:
                member.outcome, member.error = "skipped", reason
            else:
                pack = session.get(ImagePack, pack_id)
                pack.status, pack.location_key, pack.error = "deleted", None, None
                pack.generation += 1
                pack.content_version += 1
                for model in (PackTagLink, PackProgress, PackPreferences, RecentEntry):
                    session.execute(delete(model).where(model.pack_id == pack_id))
                # Pack/page tombstones remain for fixed sessions and original
                # file receipts. The scanner never reuses deleted identities.
                member.outcome = "succeeded"
            result = dict(task.result)
            result["processed"] += 1
            result["skipped" if reason else "succeeded"] += 1
            result["partial"] = result["skipped"] > 0
            task.result, task.status, task.phase = result, "running", "checking_missing"
            self.checkpoint("before_member_commit", identity)
        self.checkpoint("after_member_commit", identity)
        return True

    def run(self, identity):
        try:
            self.checkpoint("before_cleanup", identity)
            while not self.stop.is_set():
                with self.db.read() as session:
                    plan = session.get(PackMissingCleanup, identity)
                    task = session.get(Task, identity)
                    if not plan or plan.historical or task.status not in ("queued", "running"):
                        return
                    ids = list(
                        session.scalars(
                            select(PackMissingMember.pack_id)
                            .where(
                                PackMissingMember.cleanup_id == identity,
                                PackMissingMember.outcome == "pending",
                            )
                            .order_by(PackMissingMember.pack_id)
                            .limit(self.batch_size)
                        )
                    )
                if not ids:
                    with self.db.write() as session:
                        plan = session.get(PackMissingCleanup, identity)
                        task = session.get(Task, identity)
                        if plan.historical or task.status not in ("queued", "running"):
                            return
                        task.status, task.phase, task.finished_at = (
                            "completed",
                            "completed",
                            time.time(),
                        )
                    return
                for pack_id in ids:
                    if self.stop.is_set() or not self.step(identity, pack_id):
                        return
        except Exception:
            if not self.stop.is_set():
                with self.db.write() as session:
                    task = session.get(Task, identity)
                    task.status, task.phase = "failed", "failed"
                    task.error, task.finished_at = "清理未完成，尚未处理的记录保留", time.time()

    def schedule(self, identity):
        with self.lock:
            active = self.futures.get(identity)
            if active is None or active.done():
                self.futures[identity] = self.executor.submit(self.run, identity)

    def start(self):
        with self.db.read() as session:
            ids = list(
                session.scalars(
                    select(PackMissingCleanup.id)
                    .join(Task)
                    .where(
                        PackMissingCleanup.historical.is_(False),
                        Task.status.in_(("queued", "running")),
                    )
                )
            )
        for identity in ids:
            self.schedule(identity)

    def close(self):
        self.stop.set()
        self.executor.shutdown(wait=True)

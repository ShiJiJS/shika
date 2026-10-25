"""Durable whole-selection logical restore; only the server owns child batches."""

import hashlib
import json
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from sqlalchemy import func, insert, or_, select, update

from .errors import LibraryError
from .models import (
    ImagePack,
    PackFileOperation,
    PackFileStep,
    PackRestoreBatch,
    PackRestoreMember,
    PackRestorePlan,
    PackTrashItem,
    Root,
    Task,
)
from .pack_scanner import reserved_packs
from .requests import once


class PackRestorePlans:
    def __init__(self, operations, *, batch_size=1000, fault_hook=None):
        if not 1 <= batch_size <= 1000:
            raise ValueError("Invalid restore batch size")
        self.operations, self.db = operations, operations.db
        self.batch_size, self.fault_hook = batch_size, fault_hook
        self.stop = threading.Event()
        self.lock = threading.RLock()
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="pack-restore-plans")
        self.futures = {}

    def checkpoint(self, phase, identity):
        if self.fault_hook:
            self.fault_hook(phase, identity)

    @staticmethod
    def prior(session, request_id, digest):
        row = session.scalar(
            select(PackRestorePlan).where(
                PackRestorePlan.request_key == "pack_restore_plan:" + request_id
            )
        )
        if row and row.request_hash != digest:
            raise LibraryError("idempotency_conflict", "请求标识已用于不同的整份恢复计划")
        return row.id if row else None

    def submit(self, ids, request_id):
        ids = sorted(set(ids))
        if not 1 <= len(ids) <= 50000:
            raise LibraryError("invalid_restore_plan", "每份计划请选择1至50000个图包", 422)
        digest = hashlib.sha256(json.dumps(ids).encode()).hexdigest()
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
            task = Task(kind="pack_restore_plan", status="queued", phase="queued", result={})
            session.add(task)
            session.flush()
            plan = PackRestorePlan(
                id=task.id,
                request_key="pack_restore_plan:" + request_id,
                request_hash=digest,
                batch_size=self.batch_size,
            )
            session.add(plan)
            session.flush()
            # Do not load trash manifests or page lists into an admission request.
            for at in range(0, len(ids), 500):
                chunk = ids[at : at + 500]
                rows = (
                    session.execute(
                        select(
                            PackTrashItem.id.label("trash_id"),
                            PackTrashItem.status.label("trash_status"),
                            ImagePack.id.label("pack_id"),
                            ImagePack.name,
                            ImagePack.path,
                            ImagePack.status,
                            ImagePack.generation,
                            ImagePack.content_version,
                            Root.id.label("root_id"),
                            Root.kind,
                            Root.path.label("root_path"),
                        )
                        .join(ImagePack, ImagePack.id == PackTrashItem.pack_id)
                        .join(Root, Root.id == ImagePack.root_id)
                        .where(PackTrashItem.id.in_(chunk))
                    )
                    .mappings()
                    .all()
                )
                by_id = {r["trash_id"]: r for r in rows}
                if len(by_id) != len(chunk) or any(r["kind"] != "pack" for r in rows):
                    raise LibraryError("pack_operation_item_not_found", "图包或回收记录不存在", 404)
                reservations = reserved_packs().subquery()
                busy = set(
                    session.scalars(
                        select(reservations.c.pack_id).where(
                            reservations.c.pack_id.in_([r["pack_id"] for r in rows])
                        )
                    )
                )
                members = []
                for ordinal, identity in enumerate(chunk, at):
                    r = by_id[identity]
                    error = (
                        "operation_busy"
                        if r["pack_id"] in busy
                        else (
                            "stale_pack_state"
                            if r["status"] != "trash" or r["trash_status"] != "active"
                            else None
                        )
                    )
                    members.append(
                        dict(
                            plan_id=plan.id,
                            ordinal=ordinal,
                            pack_id=r["pack_id"],
                            trash_id=identity,
                            name=r["name"],
                            path=r["path"],
                            source={
                                "status": r["status"],
                                "generation": r["generation"],
                                "version": r["content_version"],
                                "root_id": r["root_id"],
                                "root_path": r["root_path"],
                            },
                            outcome="failed" if error else "pending",
                            phase="rejected" if error else "waiting",
                            error=error,
                        )
                    )
                session.execute(insert(PackRestoreMember), members)
            self.publish(session, plan.id)
            identity = plan.id
        self.enqueue(identity)
        return identity

    def enqueue(self, identity):
        with self.lock:
            previous = self.futures.get(identity)
            if not previous or previous.done():
                self.futures[identity] = self.executor.submit(self.run, identity)

    def start(self):
        with self.db.write() as session:
            identities = list(
                session.scalars(
                    select(PackRestorePlan.id)
                    .join(Task)
                    .where(
                        PackRestorePlan.historical.is_(False),
                        or_(
                            Task.status.in_(("queued", "running", "interrupted")),
                            Task.error == "operation_recovery_required",
                        ),
                    )
                    .order_by(Task.created_at, Task.id)
                )
            )
            for identity in identities:
                task = session.get(Task, identity)
                task.status, task.error = "queued", None
        for identity in identities:
            self.enqueue(identity)

    def publish(self, session, identity):
        counts = dict(
            session.execute(
                select(PackRestoreMember.outcome, func.count())
                .where(PackRestoreMember.plan_id == identity)
                .group_by(PackRestoreMember.outcome)
            ).all()
        )
        succeeded, failed = counts.get("succeeded", 0), counts.get("failed", 0)
        stopped, pending = counts.get("stopped", 0), counts.get("pending", 0)
        task = session.get(Task, identity)
        task.result = {
            "operation_id": identity,
            "total": sum(counts.values()),
            "processed": succeeded + failed,
            "succeeded": succeeded,
            "failed": failed,
            "stopped": stopped,
            "remaining": pending,
            "partial": bool(stopped or (failed and succeeded)),
            "batches": session.scalar(
                select(func.count())
                .select_from(PackRestoreBatch)
                .where(PackRestoreBatch.plan_id == identity)
            ),
        }
        return pending

    def prepare_batch(self, session, plan, ordinal, members):
        task = Task(kind="pack_restore", status="queued", phase="queued", result={})
        session.add(task)
        session.flush()
        operation = PackFileOperation(
            id=task.id,
            kind="restore",
            request_key=f"pack_restore_child:{plan.id}:{ordinal}",
            request_hash=plan.request_hash,
            session_snapshot={"prepared": {}},
            historical=False,
        )
        session.add(operation)
        session.flush()
        prepared = {}
        for member in members:
            step = PackFileStep(
                operation_id=task.id,
                pack_id=member.pack_id,
                requested_id=member.trash_id,
                root_path=member.source["root_path"],
                original_path=member.path,
            )
            session.add(step)
            session.flush()
            prepared[step.id] = member.source
            member.phase = "prepared"
        operation.session_snapshot = {"reading": None, "prepared": prepared}
        session.add(PackRestoreBatch(plan_id=plan.id, ordinal=ordinal, operation_id=task.id))
        return task.id

    def next_batch(self, identity):
        with self.db.write() as session:
            plan = session.get(PackRestorePlan, identity)
            if not plan or plan.historical:
                return None
            task = session.get(Task, identity)
            if (
                task.status in ("completed", "failed")
                and task.error != "operation_recovery_required"
            ):
                return None
            # Recover and account for an already accepted child before considering
            # stop or creating another child. Link + child + steps commit together.
            for batch in session.scalars(
                select(PackRestoreBatch)
                .where(PackRestoreBatch.plan_id == identity)
                .order_by(PackRestoreBatch.ordinal.desc())
                .limit(1)
            ):
                child = session.get(Task, batch.operation_id)
                if (
                    child.status in ("queued", "running", "interrupted")
                    or child.error == "operation_recovery_required"
                ):
                    return batch.operation_id
                self.account(session, plan, batch)
            if plan.stop_requested:
                session.execute(
                    update(PackRestoreMember)
                    .where(
                        PackRestoreMember.plan_id == identity,
                        PackRestoreMember.outcome == "pending",
                    )
                    .values(outcome="stopped", phase="stopped", error="plan_stopped")
                )
            pending = self.publish(session, identity)
            if not pending:
                stopped = task.result["stopped"] > 0
                task.status = "completed" if task.result["succeeded"] or stopped else "failed"
                task.phase = "stopped" if stopped else "completed"
                task.error = (
                    "plan_stopped"
                    if stopped
                    else (None if task.result["succeeded"] else "no_operations_completed")
                )
                task.finished_at = time.time()
                return None
            if self.stop.is_set():
                task.status, task.error = "interrupted", "service_stopped"
                return None
            first = session.scalar(
                select(PackRestoreMember.ordinal)
                .where(
                    PackRestoreMember.plan_id == identity, PackRestoreMember.outcome == "pending"
                )
                .order_by(PackRestoreMember.ordinal)
                .limit(1)
            )
            ordinal = first // plan.batch_size
            members = list(
                session.scalars(
                    select(PackRestoreMember)
                    .where(
                        PackRestoreMember.plan_id == identity,
                        PackRestoreMember.ordinal >= ordinal * plan.batch_size,
                        PackRestoreMember.ordinal < (ordinal + 1) * plan.batch_size,
                        PackRestoreMember.outcome == "pending",
                    )
                    .order_by(PackRestoreMember.ordinal)
                )
            )
            task.status, task.phase, task.error = "running", "restoring_batches", None
            return self.prepare_batch(session, plan, ordinal, members)

    @staticmethod
    def account(session, plan, batch):
        steps = {
            s.requested_id: s
            for s in session.scalars(
                select(PackFileStep).where(PackFileStep.operation_id == batch.operation_id)
            )
        }
        members = session.scalars(
            select(PackRestoreMember).where(
                PackRestoreMember.plan_id == plan.id,
                PackRestoreMember.ordinal >= batch.ordinal * plan.batch_size,
                PackRestoreMember.ordinal < (batch.ordinal + 1) * plan.batch_size,
                PackRestoreMember.outcome == "pending",
            )
        )
        for member in members:
            step = steps.get(member.trash_id)
            if not step or step.outcome not in ("succeeded", "failed"):
                raise RuntimeError("Restore child has no authoritative terminal result")
            member.outcome, member.phase, member.error = step.outcome, step.phase, step.error
        session.flush()

    def run(self, identity):
        try:
            while True:
                child = self.next_batch(identity)
                if child is None:
                    return
                self.checkpoint("restore_child_accepted", identity)
                self.operations.run(child)
                self.checkpoint("restore_child_finished", identity)
                with self.db.read() as session:
                    task = session.get(Task, child)
                    if (
                        task.status in ("queued", "running", "interrupted")
                        or task.error == "operation_recovery_required"
                    ):
                        raise RuntimeError("Restore child needs recovery")
        except Exception:
            with self.db.write() as session:
                task = session.get(Task, identity)
                plan = session.get(PackRestorePlan, identity)
                if plan and not plan.historical:
                    task.status, task.error = "failed", "operation_recovery_required"

    def view(self, identity=None, *, request_id=None):
        with self.db.read() as session:
            plan = (
                session.scalar(
                    select(PackRestorePlan).where(
                        PackRestorePlan.request_key == "pack_restore_plan:" + request_id
                    )
                )
                if request_id
                else session.get(PackRestorePlan, identity)
            )
            if not plan:
                raise LibraryError("restore_plan_not_found", "原恢复计划不存在；未重新提交", 404)
            task = session.get(Task, plan.id)
            return {
                **{
                    k: getattr(task, k)
                    for k in (
                        "id",
                        "kind",
                        "status",
                        "phase",
                        "created_at",
                        "finished_at",
                        "error",
                        "result",
                    )
                },
                "historical": plan.historical,
                "stop_requested": plan.stop_requested,
                "batch_size": plan.batch_size,
            }

    def request_stop(self, identity, request_id):
        changed = False
        with self.db.write() as session:
            plan = session.get(PackRestorePlan, identity)
            if not plan or plan.historical:
                raise LibraryError("restore_plan_not_found", "恢复计划不存在或已归档", 404)

            def action():
                nonlocal changed
                task = session.get(Task, identity)
                if (
                    task.status in ("queued", "running", "interrupted")
                    or task.error == "operation_recovery_required"
                ):
                    plan.stop_requested = True
                    changed = True
                return {"plan_id": identity}

            once(session, "pack_restore_plan.stop", request_id, {"id": identity}, action)
        if changed:
            self.enqueue(identity)
        return self.view(identity)

    def close(self):
        self.stop.set()
        self.executor.shutdown(wait=True, cancel_futures=True)

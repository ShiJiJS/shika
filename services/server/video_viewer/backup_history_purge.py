"""Exact, paged purge evidence in one immutable graph; never opens source media."""

import json

from sqlalchemy import func, select, true

from .errors import LibraryError
from .models import (
    ImagePack,
    PackFileOperation,
    PackFileStep,
    PackPurgeEntry,
    PackPurgeExecution,
    PackPurgePlan,
    PackPurgeStep,
    Task,
)


def missing():
    raise LibraryError("history_not_found", "原历史清单或所属任务不存在；未查询当前数据", 404)


class PurgeHistory:
    """Binds the original parent before any plan/member/file/result lookup."""

    def __init__(self, connection, identity, kind, graph_id):
        self.connection = connection
        if (
            kind not in {"pack_permanent", "pack_purge_preview"}
            or connection.scalar(select(Task.kind).where(Task.id == identity)) != kind
        ):
            missing()
        self.kind = kind
        if kind == "pack_permanent":
            plan_id = connection.scalar(
                select(PackPurgeExecution.plan_id)
                .join(PackFileOperation, PackFileOperation.id == PackPurgeExecution.id)
                .where(PackPurgeExecution.id == identity, PackFileOperation.kind == "permanent")
            )
            if plan_id is None:
                missing()
        else:
            plan_id = identity
        self.plan = (
            connection.execute(
                select(
                    PackPurgePlan.id, PackPurgePlan.digest, PackPurgePlan.expires_at, Task.status
                )
                .join(Task, Task.id == PackPurgePlan.id)
                .where(PackPurgePlan.id == plan_id, Task.kind == "pack_purge_preview")
            )
            .mappings()
            .first()
        )
        if self.plan is None:
            missing()
        self.binding = {
            "historical": True,
            "graph_id": graph_id,
            "task_id": identity,
            "task_kind": kind,
            "plan_id": plan_id,
        }

    def members(self):
        return select(
            PackPurgeEntry.trash_id,
            PackPurgeEntry.pack_id,
            PackPurgeEntry.name,
            PackPurgeEntry.path,
            PackPurgeEntry.digest,
            PackPurgeEntry.error,
            PackPurgeEntry.image_count,
            PackPurgeEntry.image_bytes,
            PackPurgeEntry.retained_entries,
        ).where(PackPurgeEntry.plan_id == self.plan["id"])

    def review(self, offset, limit):
        totals = (
            self.connection.execute(
                select(
                    func.count().label("total"),
                    func.coalesce(func.sum(PackPurgeEntry.image_count), 0).label("image_count"),
                    func.coalesce(func.sum(PackPurgeEntry.image_bytes), 0).label("image_bytes"),
                    func.coalesce(func.sum(PackPurgeEntry.retained_entries), 0).label(
                        "retained_entries"
                    ),
                ).where(PackPurgeEntry.plan_id == self.plan["id"])
            )
            .mappings()
            .one()
        )
        rows = self.connection.execute(
            self.members().order_by(PackPurgeEntry.id).offset(offset).limit(limit)
        ).mappings()
        operation = self.connection.scalar(
            select(PackPurgeExecution.id).where(PackPurgeExecution.plan_id == self.plan["id"])
        )
        return {
            **self.binding,
            **dict(totals),
            "status": self.plan["status"],
            "digest": self.plan["digest"],
            "expires_at": self.plan["expires_at"],
            "ready": False,
            "operation_id": operation,
            "items": [dict(row) for row in rows],
            "offset": offset,
            "limit": limit,
        }

    def files(self, trash_id, offset, limit):
        entry = (
            self.connection.execute(
                select(
                    PackPurgeEntry.id,
                    PackPurgeEntry.pack_id,
                    PackPurgeEntry.image_count,
                    func.json_type(PackPurgeEntry.manifest, "$.files").label("type"),
                    func.json_array_length(PackPurgeEntry.manifest, "$.files").label("total"),
                ).where(
                    PackPurgeEntry.plan_id == self.plan["id"], PackPurgeEntry.trash_id == trash_id
                )
            )
            .mappings()
            .first()
        )
        if entry is None:
            missing()
        if entry["type"] is None:
            raise LibraryError("pack_purge_plan_not_ready", "该历史图包没有已完成的精确清单", 409)
        if entry["type"] != "array" or entry["total"] != entry["image_count"]:
            raise LibraryError("invalid_history_manifest", "原历史图片数量与清单不一致", 409)
        files = func.json_each(PackPurgeEntry.manifest, "$.files").table_valued("key", "value")
        rows = self.connection.execute(
            select(files.c.value)
            .select_from(PackPurgeEntry)
            .join(files, true())
            .where(PackPurgeEntry.id == entry["id"])
            .order_by(files.c.key)
            .offset(offset)
            .limit(limit)
        )
        return {
            **self.binding,
            "trash_id": trash_id,
            "pack_id": entry["pack_id"],
            "items": [json.loads(row[0]) for row in rows],
            "total": entry["total"],
            "offset": offset,
            "limit": limit,
        }

    def pages(self, offset, limit, kind, outcome):
        if self.kind != "pack_permanent":
            missing()
        statement = (
            select(
                PackPurgeStep.id,
                PackPurgeStep.parent_id,
                PackPurgeStep.kind,
                PackPurgeStep.page_id,
                PackPurgeStep.relative_path,
                PackPurgeStep.phase,
                PackPurgeStep.outcome,
                PackPurgeStep.error,
                PackFileStep.pack_id,
                ImagePack.name.label("pack_name"),
            )
            .select_from(PackPurgeStep)
            .join(PackFileStep)
            .join(ImagePack, PackFileStep.pack_id == ImagePack.id)
            .where(PackFileStep.operation_id == self.binding["task_id"])
        )
        if kind != "all":
            statement = statement.where(PackPurgeStep.kind == kind)
        if outcome == "unfinished":
            statement = statement.where(PackPurgeStep.outcome.not_in(("succeeded", "retained")))
        total = self.connection.scalar(select(func.count()).select_from(statement.subquery()))
        rows = self.connection.execute(
            statement.order_by(
                PackFileStep.id,
                PackPurgeStep.kind.desc(),
                PackPurgeStep.relative_path,
                PackPurgeStep.id,
            )
            .offset(offset)
            .limit(limit)
        ).mappings()
        return {
            **self.binding,
            "items": [dict(row) for row in rows],
            "total": total,
            "offset": offset,
            "limit": limit,
        }

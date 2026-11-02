"""Read-only, bounded task summaries and operation members for settings.

The list projects scalar JSON counters in SQLite. It never loads a Task ORM
object (and its potentially large result/backup manifest) for each row.
"""

from pathlib import PurePosixPath
from typing import Annotated, Literal

from fastapi import APIRouter, Query, Request
from sqlalchemy import and_, case, func, literal, or_, select

from .errors import LibraryError
from .models import (
    FileOperation,
    FileStep,
    ImagePack,
    PackFileOperation,
    PackFileStep,
    PackMissingCleanup,
    PackMissingMember,
    PackPurgePlan,
    PackRestoreBatch,
    PackRestoreMember,
    PackRestorePlan,
    Task,
    Video,
)


class MaintenanceTasks:
    def __init__(self, db):
        self.db = db

    @staticmethod
    def summaries():
        result = Task.result

        def counter(key):
            return case((func.json_type(result, "$." + key) == "integer", result[key].as_integer()))

        historical = func.coalesce(
            or_(
                FileOperation.historical.is_(True),
                PackFileOperation.historical.is_(True),
                PackPurgePlan.historical.is_(True),
                PackRestorePlan.historical.is_(True),
                PackMissingCleanup.historical.is_(True),
                Task.error == "restored_history",
            ),
            False,
        )
        needs_attention = func.coalesce(
            or_(
                result["needs_attention"].as_boolean(), Task.error == "operation_recovery_required"
            ),
            False,
        )
        partial = func.coalesce(result["partial"].as_boolean(), False)
        failed = counter("failed")
        roots = func.json_each(result["roots"]).table_valued("key", "value", "type")
        root_status = case((roots.c.type == "object", func.json_extract(roots.c.value, "$.status")))
        root_issues = (
            select(func.count())
            .select_from(roots)
            .where(root_status.in_(("unavailable", "failed")))
            .scalar_subquery()
        )
        total, processed, succeeded = (counter(key) for key in ("total", "processed", "succeeded"))

        # Older video final receipts omitted total/processed, including receipts
        # written before this reader existed. Recover only that recognizable
        # terminal format, using the durable per-file rows; never rewrite the
        # original result or trust missing/malformed counters on other tasks.
        def step_count(*conditions):
            return (
                select(func.count())
                .select_from(FileStep)
                .where(FileStep.operation_id == Task.id, *conditions)
                .correlate(Task)
                .scalar_subquery()
            )

        legacy_total = step_count()
        legacy_succeeded = step_count(FileStep.outcome == "succeeded")
        legacy_failed = step_count(FileStep.outcome.in_(("failed", "conflict")))
        legacy_complete = func.coalesce(
            and_(
                FileOperation.id.is_not(None),
                Task.status.in_(("completed", "failed")),
                Task.phase == "completed",
                func.json_type(result, "$.total").is_(None),
                func.json_type(result, "$.processed").is_(None),
                func.json_type(result, "$.operation_id") == "text",
                result["operation_id"].as_string() == Task.id,
                func.json_type(result, "$.items") == "array",
                func.json_array_length(result, "$.items") == legacy_total,
                legacy_total > 0,
                succeeded >= 0,
                failed >= 0,
                succeeded == legacy_succeeded,
                failed == legacy_failed,
                legacy_succeeded + legacy_failed == legacy_total,
            ),
            False,
        )
        total = case((legacy_complete, legacy_total), else_=total)
        processed = case((legacy_complete, legacy_total), else_=processed)
        file_task = or_(
            FileOperation.id.is_not(None),
            Task.kind.in_(
                (
                    "pack_trash",
                    "pack_restore",
                    "pack_undo",
                    "pack_permanent",
                    "pack_restore_plan",
                    "pack_forget_missing",
                )
            ),
        )
        valid_result = func.coalesce(
            and_(
                total >= 0,
                processed == total,
                succeeded >= 0,
                failed >= 0,
                succeeded + failed == total,
            ),
            False,
        )
        valid_result = case(
            (
                Task.kind == "pack_forget_missing",
                func.coalesce(
                    and_(
                        total >= 0,
                        processed == total,
                        succeeded >= 0,
                        counter("skipped") >= 0,
                        failed == 0,
                        succeeded + counter("skipped") == total,
                    ),
                    False,
                ),
            ),
            (
                Task.kind == "pack_restore_plan",
                func.coalesce(
                    and_(
                        total >= 1,
                        succeeded >= 0,
                        failed >= 0,
                        counter("stopped") >= 0,
                        processed == succeeded + failed,
                        processed + counter("stopped") == total,
                    ),
                    False,
                ),
            ),
            else_=valid_result,
        )
        state = case(
            (historical, "historical"),
            (needs_attention, "attention"),
            (Task.status.in_(("queued", "running")), "processing"),
            (Task.status == "interrupted", "interrupted"),
            (file_task & ~valid_result, "attention"),
            (
                or_(partial, (Task.status == "completed") & or_(failed > 0, root_issues > 0)),
                "partial",
            ),
            (Task.status == "completed", "completed"),
            (Task.status == "failed", "failed"),
            else_="attention",
        )
        family = case(
            (Task.kind == "scan", "scan"),
            (Task.kind.startswith("pack_", autoescape=True), "pack"),
            (Task.kind.startswith("backup_", autoescape=True), "backup"),
            (FileOperation.id.is_not(None), "video"),
            else_="other",
        )
        return (
            select(
                Task.id,
                Task.kind,
                Task.status,
                Task.phase,
                Task.created_at,
                Task.finished_at,
                Task.error,
                family.label("family"),
                state.label("state"),
                historical.label("historical"),
                needs_attention.label("needs_attention"),
                case(
                    (Task.kind == "scan", result["progress"]["discovered"].as_integer()),
                    else_=total,
                ).label("total"),
                case(
                    (Task.kind == "scan", result["progress"]["processed"].as_integer()),
                    else_=processed,
                ).label("processed"),
                succeeded.label("succeeded"),
                failed.label("failed"),
                counter("stopped").label("stopped"),
                counter("remaining").label("remaining"),
                counter("skipped").label("skipped"),
                root_issues.label("root_issues"),
                counter("pages_total").label("pages_total"),
                counter("pages_deleted").label("pages_deleted"),
                counter("pages_pending_reconciliation").label("pages_pending"),
                result["packs"]["progress"]["packs_discovered"].as_integer().label("pack_total"),
                result["packs"]["progress"]["packs_processed"].as_integer().label("pack_processed"),
            )
            .select_from(Task)
            .outerjoin(FileOperation, FileOperation.id == Task.id)
            .outerjoin(PackFileOperation, PackFileOperation.id == Task.id)
            .outerjoin(PackPurgePlan, PackPurgePlan.id == Task.id)
            .outerjoin(PackRestorePlan, PackRestorePlan.id == Task.id)
            .outerjoin(PackMissingCleanup, PackMissingCleanup.id == Task.id)
        )

    def page(self, offset, limit, family="all", state="all"):
        projection = self.summaries().subquery()
        # The parent is the user-authorized operation; bounded implementation
        # batches stay available by ID without flooding the task list.
        statement = select(projection).where(
            projection.c.id.not_in(select(PackRestoreBatch.operation_id))
        )
        if family != "all":
            statement = statement.where(projection.c.family == family)
        if state == "attention":
            statement = statement.where(
                projection.c.state.in_(("attention", "interrupted", "failed", "partial"))
            )
        elif state != "all":
            statement = statement.where(projection.c.state == state)
        # One short serialized metadata read keeps total and page coherent while
        # workers publish results; legacy SQLite SELECTs alone tear the pair.
        with self.db.write_lock, self.db.read() as session:
            total = session.scalar(select(func.count()).select_from(statement.subquery()))
            rows = session.execute(
                statement.order_by(projection.c.created_at.desc(), projection.c.id.desc())
                .offset(offset)
                .limit(limit)
            ).mappings()
            return {
                "items": [dict(row) for row in rows],
                "total": total,
                "offset": offset,
                "limit": limit,
            }

    def task(self, identity):
        with self.db.read() as session:
            row = session.execute(self.summaries().where(Task.id == identity)).mappings().first()
            if not row or row["error"] == "restored_history":
                from .management_history import current_history

                history = current_history(session)
                if history is not None:
                    try:
                        return history.task(identity)
                    except LibraryError as error:
                        if error.code != "history_not_found":
                            raise
            if not row:
                raise LibraryError(
                    "task_not_found", "原任务不存在，请核对当前内容；未重新提交", 404
                )
            return dict(row)

    def items(self, identity, offset, limit, unfinished):
        summary = self.task(identity)
        if summary.get("graph_id"):
            from .management_history import current_history

            with self.db.read() as session:
                return current_history(session).members(
                    identity,
                    offset=offset,
                    limit=limit,
                    unfinished=unfinished,
                    graph_id=summary["graph_id"],
                )
        if summary["kind"] == "pack_forget_missing":
            step = PackMissingMember
            statement = select(
                step.pack_id.label("id"),
                step.pack_id.label("requested_id"),
                step.pack_id.label("media_id"),
                step.name,
                step.path,
                case((step.outcome == "pending", "checking_missing"), else_="completed").label(
                    "phase"
                ),
                step.outcome,
                step.error,
            )
        elif summary["kind"] == "pack_restore_plan":
            step = PackRestoreMember
            statement = select(
                step.trash_id.label("id"),
                step.trash_id.label("requested_id"),
                step.pack_id.label("media_id"),
                step.name,
                step.path,
                step.phase,
                step.outcome,
                step.error,
            )
        elif summary["family"] == "pack" and summary["kind"] != "pack_purge_preview":
            step = PackFileStep
            statement = select(
                step.id,
                step.requested_id,
                step.pack_id.label("media_id"),
                ImagePack.name,
                step.original_path.label("path"),
                step.phase,
                step.outcome,
                step.error,
            ).outerjoin(ImagePack, ImagePack.id == step.pack_id)
        elif summary["family"] == "video":
            step = FileStep
            statement = select(
                step.id,
                step.requested_id,
                step.video_id.label("media_id"),
                Video.name,
                step.original_path.label("path"),
                step.phase,
                step.outcome,
                step.error,
            ).outerjoin(Video, Video.id == step.video_id)
        else:
            step = None
            statement = select(literal(1)).where(literal(False))
        if step is not None:
            statement = statement.where(
                (
                    step.plan_id
                    if step is PackRestoreMember
                    else step.cleanup_id
                    if step is PackMissingMember
                    else step.operation_id
                )
                == identity
            )
            if unfinished:
                statement = statement.where(step.outcome != "succeeded")
        with self.db.write_lock, self.db.read() as session:
            total = session.scalar(select(func.count()).select_from(statement.subquery()))
            records = (
                []
                if step is None
                else session.execute(
                    statement.order_by(
                        step.ordinal
                        if step is PackRestoreMember
                        else step.pack_id
                        if step is PackMissingMember
                        else step.id
                    )
                    .offset(offset)
                    .limit(limit)
                ).mappings()
            )
            return {
                "operation_id": identity,
                "historical": summary["historical"],
                "items": [
                    {
                        **row,
                        "name": row["name"] or PurePosixPath(row["path"]).name or "已移除的内容",
                    }
                    for row in records
                ],
                "total": total,
                "offset": offset,
                "limit": limit,
            }


def router(auth_required):
    api = APIRouter(prefix="/api/v1/maintenance-tasks", dependencies=auth_required)

    @api.get("")
    def tasks(
        request: Request,
        offset: Annotated[int, Query(ge=0)] = 0,
        limit: Annotated[int, Query(ge=1, le=100)] = 24,
        family: Literal["all", "scan", "video", "pack", "backup", "other"] = "all",
        state: Literal["all", "processing", "attention", "completed", "historical"] = "all",
    ):
        return MaintenanceTasks(request.app.state.db).page(offset, limit, family, state)

    @api.get("/{identity}")
    def task(identity: str, request: Request):
        return MaintenanceTasks(request.app.state.db).task(identity)

    @api.get("/{identity}/items")
    def items(
        identity: str,
        request: Request,
        offset: Annotated[int, Query(ge=0)] = 0,
        limit: Annotated[int, Query(ge=1, le=100)] = 24,
        unfinished: bool = False,
    ):
        return MaintenanceTasks(request.app.state.db).items(identity, offset, limit, unfinished)

    return api

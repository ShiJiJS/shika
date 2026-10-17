"""Durable readiness and scan progress, independent of a connected client."""

from sqlalchemy import func, select

from .models import Root, Task, Video


def prepared(session):
    roots = [root for root in session.scalars(select(Root)) if root.mount_id]
    return bool(roots) and all(root.last_scan is not None for root in roots)


def library_state(db):
    with db.read() as session:
        roots = list(session.scalars(select(Root).order_by(Root.name, Root.id)))
        task = session.scalar(
            select(Task).where(Task.kind == "scan").order_by(Task.created_at.desc()).limit(1)
        )
        result = task.result if task else {}
        progress = result.get("progress", {})
        running = bool(task and task.status in ("queued", "running"))
        root_progress = {item["id"]: item for item in result.get("roots", [])}
        return {
            "ready": prepared(session),
            "scanning": running,
            "task_id": task.id if task else None,
            "status": task.status if task else "idle",
            "phase": task.phase if task else "idle",
            "updated_at": progress.get("updated_at"),
            "progress": progress,
            "counts": {
                key: result.get(key, 0)
                for key in ("imported", "unchanged", "deferred", "failed", "thumbnail_failed")
            },
            "failure_reasons": result.get("failure_reasons", {}),
            "warning_reasons": result.get("warning_reasons", {}),
            "indexed": session.scalar(
                select(func.count()).select_from(Video).where(Video.status == "available")
            ),
            "roots": [
                {
                    "id": root.id,
                    "ready": root.last_scan is not None and bool(root.mount_id),
                    "available": root.available,
                    "last_scan": root.last_scan,
                    "error": root.error,
                    "scan": root_progress.get(root.id),
                }
                for root in roots
            ],
        }

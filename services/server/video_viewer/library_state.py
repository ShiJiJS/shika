"""Durable readiness and scan progress, independent of a connected client."""

from sqlalchemy import func, select

from .media_roots import enabled_path, owner_for_path
from .models import Root, Task, Video
from .packs import Packs
from .root_scan_progress import ACTIVE, latest


def prepared(session, kind="video"):
    configured = list(session.scalars(select(Root)))
    roots = [root for root in configured if root.mount_id and root.enabled and root.kind == kind]
    if kind == "video":
        roots = list(
            {
                owner.id: owner
                for root in roots
                if (owner := owner_for_path(root.path, configured))
            }.values()
        )
    return bool(roots) and all(root.last_scan is not None for root in roots)


def library_state(db):
    # Streaming imports prepared(); defer the full catalog dependency until
    # application modules have finished initializing.
    from .catalog import Catalog

    with db.read() as session:
        # Both type totals describe one snapshot, using the same eligibility
        # rules as the actual unfiltered catalogs, without fetching any media.
        session.connection().exec_driver_sql("BEGIN")
        roots = list(session.scalars(select(Root).order_by(Root.name, Root.id)))
        pending = list(
            session.scalars(
                select(Task)
                .where(Task.kind == "scan", Task.status.in_(("queued", "running")))
                .order_by(Task.created_at)
            )
        )
        task = next((t for t in pending if t.status == "running"), None) or session.scalar(
            select(Task).where(Task.kind == "scan").order_by(Task.created_at.desc()).limit(1)
        )
        result = task.result if task else {}
        progress = result.get("progress", {})
        running = bool(task and task.status in ("queued", "running"))
        root_progress = {item["id"]: item for item in result.get("roots", [])}
        legacy_progress = {
            key: value for key, value in root_progress.items() if "configuration" not in value
        }
        scans = {root.id: latest(session, root) or legacy_progress.get(root.id) for root in roots}
        queued = {
            root.id: [
                t.id
                for t in pending
                if t.status == "queued" and root.id in t.result.get("scope", {}).get("root_ids", [])
            ]
            for root in roots
        }

        def kind_scanning(kind):
            return any(
                root.kind == kind
                and scans[root.id]
                and scans[root.id]["status"] in ACTIVE
                and any(
                    t.id == scans[root.id].get("task_id") and t.status == "running" for t in pending
                )
                for root in roots
            ) or bool(
                running
                and not result.get("scope")
                and (task.phase.startswith("pack_") == (kind == "pack"))
            )

        return {
            "ready": prepared(session),
            "media": {
                "video": {
                    "ready": prepared(session),
                    "scanning": kind_scanning("video"),
                    "indexed": session.scalar(
                        select(func.count()).select_from(
                            Catalog.video_statement(session).order_by(None).subquery()
                        )
                    ),
                },
                "pack": {
                    "ready": prepared(session, "pack"),
                    "scanning": kind_scanning("pack"),
                    "counts": result.get("packs", {}),
                    "indexed": session.scalar(
                        select(func.count()).select_from(
                            Packs(db).statement(session).order_by(None).subquery()
                        )
                    ),
                },
            },
            "scanning": bool(pending),
            "scan_queue": [
                {"task_id": t.id, "scope": t.result.get("scope"), "created_at": t.created_at}
                for t in pending
                if t.status == "queued"
            ],
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
                select(func.count())
                .select_from(Video)
                .where(Video.status == "available", enabled_path(session, Video.path))
            ),
            "roots": [
                {
                    "id": root.id,
                    "ready": root.last_scan is not None and bool(root.mount_id),
                    "kind": root.kind,
                    "enabled": root.enabled,
                    "available": root.available,
                    "last_scan": root.last_scan,
                    "error": root.error,
                    "scan": scans[root.id],
                    "queued_task_ids": queued[root.id],
                }
                for root in roots
            ],
        }

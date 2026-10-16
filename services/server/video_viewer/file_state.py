from sqlalchemy import and_, or_, select

from .models import FileOperation, FileStep, Task

RESOLVED_PHASES = ("prepared", "rolled_back", "committed")


def reserved_steps():
    return (
        select(FileStep)
        .join(FileOperation)
        .where(
            FileOperation.historical.is_(False),
            or_(
                FileStep.outcome == "pending",
                and_(
                    FileStep.outcome.in_(["failed", "conflict"]),
                    FileStep.phase.not_in(RESOLVED_PHASES),
                ),
            ),
        )
    )


def reserved_video_ids():
    return (
        reserved_steps().with_only_columns(FileStep.video_id).where(FileStep.video_id.is_not(None))
    )


def path_reserved(session, path):
    return session.scalar(
        reserved_steps()
        .where(
            or_(
                FileStep.source == str(path),
                FileStep.destination == str(path),
                FileStep.staging == str(path),
                FileStep.copy_path == str(path),
            )
        )
        .limit(1)
    )


def touch_active_scan(session, video):
    active = session.scalar(
        select(Task.id)
        .where(Task.kind == "scan", Task.status == "running")
        .order_by(Task.created_at.desc())
        .limit(1)
    )
    if active:
        video.seen_scan = active


def video_signature(video):
    return [video.device, video.inode, video.size, video.mtime_ns, video.ctime_ns]


def set_video_signature(video, value):
    video.device, video.inode, video.size, video.mtime_ns, video.ctime_ns = value

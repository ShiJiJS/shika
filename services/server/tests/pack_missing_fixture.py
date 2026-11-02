"""Read-only metadata snapshots for generated native missing-pack tests."""

import hashlib

from sqlalchemy import func, select

from video_viewer.models import (
    ImagePack,
    PackMissingCleanup,
    PackMissingMember,
    PackPreferences,
    PackProgress,
    PackSessionEntry,
    PackTagLink,
    RecentEntry,
    Task,
)


def missing_snapshot(db):
    with db.read() as session:
        records = []
        for plan in session.scalars(
            select(PackMissingCleanup).join(Task).order_by(Task.created_at)
        ):
            task = session.get(Task, plan.id)
            records.append(
                {
                    "id": plan.id,
                    "status": task.status,
                    "result": task.result,
                    "request_hash": hashlib.sha256(plan.request_id.encode()).hexdigest(),
                    "members": dict(
                        session.execute(
                            select(PackMissingMember.outcome, func.count())
                            .where(PackMissingMember.cleanup_id == plan.id)
                            .group_by(PackMissingMember.outcome)
                        ).all()
                    ),
                }
            )
        first = session.scalar(
            select(ImagePack)
            .where(ImagePack.name == "图包01")
            .order_by(ImagePack.created_at)
            .limit(1)
        )
        summary = (
            None
            if first is None
            else {
                "id": first.id,
                "status": first.status,
                "progress": session.get(PackProgress, first.id) is not None,
                "preferences": session.get(PackPreferences, first.id) is not None,
                "tag_links": session.scalar(
                    select(func.count())
                    .select_from(PackTagLink)
                    .where(PackTagLink.pack_id == first.id)
                ),
                "recent": session.scalar(
                    select(func.count())
                    .select_from(RecentEntry)
                    .where(RecentEntry.pack_id == first.id)
                ),
                "session_members": session.scalar(
                    select(func.count())
                    .select_from(PackSessionEntry)
                    .where(PackSessionEntry.pack_id == first.id)
                ),
            }
        )
        return {
            "cleanups": records,
            "first_pack": summary,
            "pack_statuses": dict(
                session.execute(
                    select(ImagePack.status, func.count()).group_by(ImagePack.status)
                ).all()
            ),
        }

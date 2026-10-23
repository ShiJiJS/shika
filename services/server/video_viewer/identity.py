"""Reconcile complete discoveries with bounded candidates and short writes."""

import os
from pathlib import Path

from sqlalchemy import func, select

from .errors import LibraryError
from .file_state import reserved_video_ids, set_video_signature, video_signature
from .media_roots import enabled_path
from .models import Root, TrashItem, Video
from .paths import open_video, signature


def content_key(video):
    # A quick fingerprint narrows candidates; full SHA-256 remains mandatory.
    return video.size, video.quick_hash, video.sha256


def inode_key(video):
    return video.device, video.inode, *content_key(video)


def publish_discoveries(db, settings, task_id, completed_roots, result, check_stop):
    content_columns = (Video.size, Video.quick_hash, Video.sha256)
    inode_columns = (Video.device, Video.inode, *content_columns)
    new_scope = (
        Video.status == "discovered",
        Video.seen_scan == task_id,
        Video.root_id.in_(completed_roots),
        Video.id.not_in(reserved_video_ids()),
    )
    with db.read() as session:
        ids = list(
            session.scalars(select(Video.id).where(*new_scope).order_by(Video.path, Video.id))
        )
        new_hashes = select(Video.sha256).where(*new_scope)
        # SQL aggregates retain compact evidence, not ORM objects/tags for the
        # entire collection. Counts are a fixed snapshot: publishing an earlier
        # hardlink must not make a later ambiguous hardlink appear unique.
        live_counts = {
            tuple(row[:-1]): row[-1]
            for row in session.execute(
                select(*content_columns, func.count())
                .where(
                    Video.status.in_(["available", "discovered"]),
                    Video.sha256.in_(new_hashes),
                )
                .group_by(*content_columns)
            )
        }
        inode_counts = {
            tuple(row[:-1]): row[-1]
            for row in session.execute(
                select(*inode_columns, func.count())
                .where(
                    Video.status == "discovered",
                    Video.sha256.in_(new_hashes),
                )
                .group_by(*inode_columns)
            )
        }
    for video_id in ids:
        check_stop()
        # Filesystem operations cannot target discoveries before publication.
        # Each publication is independent and leaves no long database write lock.
        with db.write() as session:
            fresh = session.get(Video, video_id)
            if fresh.status != "discovered" or fresh.seen_scan != task_id:
                continue
            try:
                with open_video(Path(fresh.path), settings.mounts) as fd:
                    if signature(os.fstat(fd)) != video_signature(fresh):
                        raise LibraryError("file_changing", "文件在扫描后已变化")
            except (OSError, LibraryError):
                fresh.error = "file_changing"
                result["deferred"] += 1
                continue
            query = (
                select(Video)
                .join(Root)
                .where(
                    Video.status == "missing",
                    Root.available.is_(True),
                    Root.enabled.is_(True),
                    enabled_path(session, Video.path),
                    Video.size == fresh.size,
                    Video.quick_hash == fresh.quick_hash,
                    Video.sha256 == fresh.sha256,
                    Video.id.not_in(reserved_video_ids()),
                    Video.id.not_in(select(TrashItem.video_id).where(TrashItem.status == "active")),
                )
            )
            # At most two candidate objects are needed to establish uniqueness.
            content_candidates = list(session.scalars(query.limit(2)))
            candidates = list(
                session.scalars(
                    query.where(
                        Video.device == fresh.device,
                        Video.inode == fresh.inode,
                    ).limit(2)
                )
            )
            if len(candidates) != 1 or inode_counts.get(inode_key(fresh)) != 1:
                candidates = content_candidates
                if len(candidates) != 1 or live_counts.get(content_key(fresh)) != 1:
                    candidates = []
            old = candidates[0] if candidates else None
            if old and not fresh.tags:
                fresh.status, fresh.location_key = "superseded", None
                session.flush()  # Release the unique location before reassignment.
                for field in (
                    "root_id",
                    "path",
                    "name",
                    "size",
                    "sha256",
                    "quick_hash",
                    "duration",
                    "width",
                    "height",
                    "rotation",
                    "type",
                    "video_codec",
                    "audio_codec",
                    "container",
                    "thumbnail",
                    "seen_scan",
                ):
                    setattr(old, field, getattr(fresh, field))
                set_video_signature(old, video_signature(fresh))
                old.status, old.location_key, old.error = "available", fresh.path, None
                old.generation += 1
                result["identity_matched"] += 1
            else:
                fresh.status, fresh.error = "available", None
                if content_candidates:
                    result["identity_ambiguous"] += 1
                    if len(result["issues"]) < 100:
                        result["issues"].append(
                            {
                                "root_id": fresh.root_id,
                                "name": fresh.name,
                                "code": "identity_ambiguous",
                            }
                        )

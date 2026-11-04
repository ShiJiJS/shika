"""Forget confirmed missing metadata without unlinking or moving any media."""

import os
from pathlib import Path

from sqlalchemy import delete, select

from .errors import LibraryError
from .file_state import reserved_video_ids
from .media_roots import owner_for_path
from .models import Root, Task, TrashItem, Video, VideoTag
from .paths import beneath, open_directory
from .requests import once


def forget_missing(db, request_id):
    with db.write() as session:

        def action():
            if session.scalar(
                select(Task.id)
                .where(Task.kind == "scan", Task.status.in_(("queued", "running")))
                .limit(1)
            ):
                raise LibraryError("scan_in_progress", "请等待目录同步完成后再清理", 409)
            roots = {root.id: root for root in session.scalars(select(Root))}
            identities = {}
            for root in roots.values():
                if (
                    not root.available
                    or not root.enabled
                    or root.kind != "video"
                    or not root.mount_id
                    or root.last_scan is None
                ):
                    continue
                try:
                    with open_directory(Path(root.path)) as fd:
                        info = os.fstat(fd)
                        identities[root.id] = (info.st_dev, info.st_ino)
                except OSError:
                    continue
            removed = skipped = 0
            for video in session.scalars(
                select(Video).where(
                    Video.status == "missing",
                    Video.id.not_in(reserved_video_ids()),
                    Video.id.not_in(select(TrashItem.video_id).where(TrashItem.status == "active")),
                )
            ):
                if (
                    owner_for_path(video.path, roots.values()) is None
                    or video.root_id not in identities
                    or not beneath(Path(video.path), Path(roots[video.root_id].path))
                ):
                    skipped += 1
                    continue
                try:
                    with open_directory(Path(video.path).parent) as fd:
                        os.stat(Path(video.path).name, dir_fd=fd, follow_symlinks=False)
                    skipped += 1  # It has returned; scan it instead of forgetting it.
                    continue
                except FileNotFoundError:
                    pass
                except OSError:
                    skipped += 1
                    continue
                video.status, video.location_key, video.error = "deleted", None, None
                video.generation += 1
                session.execute(delete(VideoTag).where(VideoTag.video_id == video.id))
                removed += 1
            # A disappearing mount must roll back the cleanup, not erase its history.
            for root_id, identity in identities.items():
                try:
                    with open_directory(Path(roots[root_id].path)) as fd:
                        info = os.fstat(fd)
                        if (info.st_dev, info.st_ino) != identity:
                            raise OSError("root_changed")
                except OSError as error:
                    raise LibraryError(
                        "root_unavailable", "目录已离线，未清除失效记录", 409
                    ) from error
            # Keep tombstones for old round/file receipts; they are not listed,
            # playable, or eligible for identity/tag recovery after confirmation.
            return {"removed": removed, "skipped": skipped}

        return once(session, "videos.forget_missing", request_id, {"confirmed": True}, action)

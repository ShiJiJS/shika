import os
import threading
from pathlib import Path

from sqlalchemy import select
from starlette.responses import FileResponse

from .errors import LibraryError
from .library_state import prepared
from .media_roots import owner_for_path
from .models import Root, Video
from .paths import open_directory, open_video, signature

MIME_TYPES = {
    "MP4": "video/mp4",
    "M4V": "video/mp4",
    "MOV": "video/quicktime",
    "MKV": "video/x-matroska",
    "WEBM": "video/webm",
    "AVI": "video/x-msvideo",
    "MPG": "video/mpeg",
    "MPEG": "video/mpeg",
    "TS": "video/mp2t",
    "MTS": "video/mp2t",
    "M2TS": "video/mp2t",
    "3GP": "video/3gpp",
}


class DescriptorResponse(FileResponse):
    """Starlette Range handling over an already verified, stable open file."""

    def __init__(self, fd, release, video):
        self.fd, self.release = fd, release
        super().__init__(
            f"/proc/self/fd/{fd}",
            stat_result=os.fstat(fd),
            media_type=MIME_TYPES.get(video.type, "application/octet-stream"),
            filename=video.name,
            content_disposition_type="inline",
            headers={"ETag": f'"{video.sha256}"', "Cache-Control": "private, no-cache"},
        )

    async def __call__(self, scope, receive, send):
        # Keep descriptor ownership here rather than relying on background tasks,
        # which might not run on cancellation or an invalid Range response.
        scope = {
            **scope,
            "extensions": {
                k: v
                for k, v in scope.get("extensions", {}).items()
                if k != "http.response.pathsend"
            },
        }
        try:
            await super().__call__(scope, receive, send)
        finally:
            os.close(self.fd)
            self.release()


class MediaStreams:
    def __init__(self, db, settings):
        self.db, self.settings = db, settings
        self.slots = threading.BoundedSemaphore(settings.media_streams)

    def verified_fd(self, session, video):
        if not video or video.status != "available" or video.error:
            raise LibraryError("video_unavailable", "视频当前不可播放", 404)
        root = session.get(Root, video.root_id)
        if (
            not root.available
            or not root.enabled
            or owner_for_path(video.path, list(session.scalars(select(Root)))) is None
        ):
            raise LibraryError("root_unavailable", "媒体目录暂不可用")
        try:
            with open_directory(Path(root.path)) as root_fd:
                os.listdir(root_fd)
        except OSError as error:
            raise LibraryError("root_unavailable", "媒体目录暂不可用") from error
        try:
            with open_video(Path(video.path), self.settings.mounts) as fd:
                if signature(os.fstat(fd)) != [
                    video.device,
                    video.inode,
                    video.size,
                    video.mtime_ns,
                    video.ctime_ns,
                ]:
                    raise LibraryError("media_changed", "视频文件已变化，请刷新媒体目录")
                return os.dup(fd)
        except FileNotFoundError as error:
            raise LibraryError("media_missing", "视频文件已缺失，请刷新媒体目录", 404) from error
        except PermissionError as error:
            raise LibraryError("media_inaccessible", "没有读取该视频的权限") from error
        except OSError as error:
            raise LibraryError("media_inaccessible", "视频暂时无法读取") from error

    def can_play(self, session, video):
        try:
            fd = self.verified_fd(session, video)
            os.close(fd)
            return True
        except LibraryError:
            return False

    def response(self, video_id):
        if not self.slots.acquire(blocking=False):
            raise LibraryError("media_busy", "播放连接较多，请稍后重试", 503)
        fd = None
        try:
            with self.db.read() as session:
                if not prepared(session):
                    raise LibraryError("library_preparing", "视频库正在准备，完成后即可播放", 409)
                video = session.get(Video, video_id)
                fd = self.verified_fd(session, video)
            return DescriptorResponse(fd, self.slots.release, video)
        except BaseException:
            if fd is not None:
                os.close(fd)
            self.slots.release()
            raise

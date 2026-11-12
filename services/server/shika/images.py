"""Bounded inspection and descriptor-owned image reads under pack/root policy."""

import json
import os
import subprocess
import sys
import threading
import time
from pathlib import Path
from types import SimpleNamespace

from sqlalchemy import select

from .directory_identity import directory_stamp
from .errors import LibraryError
from .media_roots import owner_for_path
from .models import ImagePack, PackPage, Root, uid
from .paths import beneath, open_directory, open_regular, signature, validate_path
from .rollback_images import ReturnedImageReads
from .streaming import DescriptorResponse

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}
IMAGE_MIME = {"JPEG": "image/jpeg", "PNG": "image/png", "WEBP": "image/webp"}


def inspect_image(fd, cache, timeout, stop):
    if stop.is_set():
        raise InterruptedError("scan_stopped")
    keep_thumbnail = False
    filename = uid() + ".jpg"
    target = cache / filename
    try:
        try:
            cache.mkdir(parents=True, exist_ok=True, mode=0o700)
        except OSError:
            pass  # Metadata/original remain usable even without a writable cache.
        process = subprocess.Popen(
            [sys.executable, "-m", "shika.image_probe", str(fd), str(target)],
            pass_fds=(fd,),
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        deadline = time.monotonic() + timeout
        try:
            warning = "thumbnail_resource_limit"
            while process.poll() is None:
                if stop.wait(0.02):
                    raise InterruptedError("scan_stopped")
                if time.monotonic() >= deadline:
                    process.kill()
                    warning = "thumbnail_timeout"
                    break
            raw, _ = process.communicate(timeout=2)
            if len(raw) > 4096:
                return {"error": "image_probe_failed"}
            receipts = []
            for line in raw.splitlines():
                try:
                    receipts.append(json.loads(line))
                except ValueError:
                    if process.returncode == 0:
                        raise
                    # A killed worker can leave its final JSON line incomplete.
            if process.returncode != 0:
                # A valid header was published before preview work. A timeout or
                # killed worker must not turn that original into an unreadable page.
                metadata = next((r["metadata"] for r in receipts if "metadata" in r), None)
                if metadata:
                    return {**metadata, "thumbnail": None, "thumbnail_warning": warning}
                return {
                    "error": "image_probe_timeout"
                    if warning == "thumbnail_timeout"
                    else "image_probe_failed"
                }
            if not receipts or "metadata" in receipts[-1]:
                return {"error": "image_probe_failed"}
            result = receipts[-1]
            if result.get("thumbnail") and target.is_file():
                result["thumbnail"] = filename
                keep_thumbnail = True
            else:
                result["thumbnail"] = None
            return result
        finally:
            if process.poll() is None:
                process.kill()
            process.communicate()
    except InterruptedError:
        raise
    except (OSError, ValueError):
        return {"error": "image_probe_unavailable"}
    finally:
        if not keep_thumbnail:
            try:
                target.unlink(missing_ok=True)
            except OSError:
                pass


class ImageStreams:
    def __init__(self, db, settings):
        self.db, self.settings = db, settings
        self.slots = threading.BoundedSemaphore(settings.media_streams)
        self.returned = ReturnedImageReads()

    def verified_fd(self, session, page, version):
        if not page:
            raise LibraryError("page_not_found", "图片页不存在", 404)
        pack = session.get(ImagePack, page.pack_id)
        if not pack or pack.status != "available":
            raise LibraryError("pack_unavailable", "图包当前不可读取", 404)
        if version is not None and pack.content_version != version:
            raise LibraryError("pack_changed", "图包页清单已变化，请重新读取", 409)
        root = session.get(Root, pack.root_id)
        owner = owner_for_path(page.path, list(session.scalars(select(Root))), "pack")
        if not root.available or not root.enabled or not owner or owner.id != root.id:
            raise LibraryError("root_unavailable", "图包目录暂不可用", 409)
        if page.error:
            raise LibraryError(page.error, "这张图片暂不可读取", 422)
        if not beneath(Path(pack.path), Path(root.path)) or (
            Path(pack.path) / page.relative_path != Path(page.path)
            or not beneath(Path(page.path), Path(pack.path))
        ):
            raise LibraryError("image_outside_pack", "图片不在图包范围内", 409)
        validate_path(page.path, self.settings.mounts)
        try:
            with open_directory(Path(root.path)) as root_fd:
                os.listdir(root_fd)
            with open_directory(Path(pack.path)) as folder:
                observed = directory_stamp(folder)
                birth_changed = bool(
                    pack.directory_signature
                    and pack.directory_signature[-1] is not None
                    and observed[-1] != pack.directory_signature[-1]
                )
                if tuple(observed[:2]) != (pack.device, pack.inode) or birth_changed:
                    raise LibraryError("pack_changed", "图包目录身份已变化，请同步目录", 409)
            with open_regular(Path(page.path)) as fd:
                observed = signature(os.fstat(fd))
                if observed != page.signature and not self.returned.matches(
                    session, page, pack, root, fd, observed
                ):
                    raise LibraryError("image_changed", "图片已变化，请同步图包", 409)
                return os.dup(fd), pack
        except OSError as error:
            raise LibraryError("image_unavailable", "图片暂不可读取，请同步目录", 409) from error

    def response(self, page_id, *, thumbnail=False, version=None):
        if not self.slots.acquire(blocking=False):
            raise LibraryError("image_busy", "图片读取较多，请稍后重试", 503)
        fd = None
        try:
            with self.db.read() as session:
                page = session.get(PackPage, page_id)
                fd, pack = self.verified_fd(session, page, version)
                digest = page.sha256
                media_type = IMAGE_MIME[page.format]
                name = Path(page.path).name
                if thumbnail:
                    os.close(fd)
                    fd = None
                    if not page.thumbnail or Path(page.thumbnail).name != page.thumbnail:
                        raise LibraryError("thumbnail_unavailable", "缩略图尚未生成", 404)
                    try:
                        with open_regular(
                            self.settings.data_dir / "image-thumbnails" / page.thumbnail
                        ) as cached:
                            fd = os.dup(cached)
                    except OSError as error:
                        raise LibraryError(
                            "thumbnail_unavailable", "缩略图暂不可用", 404
                        ) from error
                    media_type, name, digest = "image/jpeg", page.thumbnail, digest + "-thumb-v1"
                asset = SimpleNamespace(name=name, type=page.format, sha256=digest)
            return DescriptorResponse(
                fd,
                self.slots.release,
                asset,
                media_type=media_type,
                extra_headers={
                    "X-Content-Version": str(pack.content_version),
                    "X-Content-Type-Options": "nosniff",
                },
            )
        except BaseException:
            if fd is not None:
                os.close(fd)
            self.slots.release()
            raise

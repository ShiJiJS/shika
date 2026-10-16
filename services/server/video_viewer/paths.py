import os
import stat
from contextlib import contextmanager
from pathlib import Path

from .errors import LibraryError

EXCLUDED_NAMES = {".video-viewer-trash", ".video-viewer-tmp", "#recycle", "@eaDir", "@Recycle"}
VIDEO_EXTENSIONS = {
    ".mp4",
    ".mov",
    ".m4v",
    ".mkv",
    ".webm",
    ".avi",
    ".mpg",
    ".mpeg",
    ".ts",
    ".mts",
    ".m2ts",
    ".3gp",
}


def beneath(path: Path, parent: Path):
    return path == parent or parent in path.parents


def validate_path(path: str, mounts):
    candidate = Path(path)
    if not candidate.is_absolute() or ".." in candidate.parts:
        raise LibraryError("path_outside_mounts", "只能选择已挂载媒体目录内的位置", 422)
    mount = next((m for m in mounts if beneath(candidate, m.path)), None)
    if not mount:
        raise LibraryError("path_outside_mounts", "只能选择已挂载媒体目录内的位置", 422)
    # Lexical containment alone is insufficient for links in any component.
    if candidate.resolve(strict=False) != candidate:
        raise LibraryError("symlink_not_allowed", "不接入符号链接或越界目录", 422)
    return candidate, mount


@contextmanager
def open_directory(path: Path):
    """Open every component without following links, including intermediate ones."""
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for component in path.parts[1:]:
            next_fd = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = next_fd
        yield fd
    finally:
        os.close(fd)


@contextmanager
def open_video(path: Path, mounts):
    validate_path(str(path), mounts)
    with open_directory(path.parent) as parent_fd:
        fd = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent_fd)
        try:
            if not stat.S_ISREG(os.fstat(fd).st_mode):
                raise LibraryError("not_regular_file", "该位置不是普通视频文件")
            yield fd
        finally:
            os.close(fd)


def signature(info):
    return [
        str(info.st_dev),
        str(info.st_ino),
        info.st_size,
        str(info.st_mtime_ns),
        str(info.st_ctime_ns),
    ]


def excluded(path: Path, data_dir: Path):
    return any(p in EXCLUDED_NAMES for p in path.parts) or beneath(path, data_dir)

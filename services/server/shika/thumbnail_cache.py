"""Retire derived previews, never originals or management records.

Run on the scanner's single executor, after inspection/publication has finished.
Age alone cannot protect a preview from an hours-long, unpublished scan. Each
unlink also holds the database writer reservation so restore and publication
cannot add a reference between the last check and deletion.
"""

import os
import re
import stat
import time
from pathlib import Path

from sqlalchemy import select

from .authority import Authority
from .models import ImagePack, PackPage, Video
from .paths import open_directory

GRACE_SECONDS = 3600
BATCH_SIZE = 64
CACHE_NAME = re.compile(
    r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg(?:\.tmp\.jpg)?"
)


def stamp(info):
    return (
        info.st_dev,
        info.st_ino,
        info.st_size,
        info.st_mtime_ns,
        info.st_ctime_ns,
        info.st_nlink,
    )


def collect_thumbnails(db, data_dir, stop):
    result = {"files": 0, "bytes": 0, "errors": 0}
    cutoff = time.time() - GRACE_SECONDS
    epoch = None
    sources = (
        (
            "image-thumbnails",
            select(PackPage.thumbnail)
            .join(ImagePack)
            .where(ImagePack.status != "deleted", PackPage.thumbnail.is_not(None)),
            PackPage.thumbnail,
        ),
        (
            "thumbnails",
            select(Video.thumbnail).where(Video.status != "deleted", Video.thumbnail.is_not(None)),
            Video.thumbnail,
        ),
    )
    for folder, references, column in sources:
        if stop.is_set():
            break
        with db.write() as session:
            current = Authority.current(session)
            if epoch is not None and current != epoch:
                return result
            epoch = current
            # Preserve all non-deleted statuses, including staging, trash,
            # missing and disabled roots. Basenames also protect legacy paths.
            protected = {Path(name).name for name in session.scalars(references)}

        def discard(directory, candidates, *, references=references, column=column, epoch=epoch):
            with db.write() as session:
                if Authority.current(session) != epoch:
                    return False
                names = [name for name, _ in candidates]
                live = set(session.scalars(references.where(column.in_(names))))
                for name, observed in candidates:
                    if stop.is_set():
                        return False
                    if name in live:
                        continue
                    try:
                        current = os.stat(name, dir_fd=directory, follow_symlinks=False)
                        if stamp(current) != stamp(observed):
                            continue
                        os.unlink(name, dir_fd=directory)
                        result["files"] += 1
                        result["bytes"] += current.st_size
                    except FileNotFoundError:
                        pass
                    except OSError:
                        result["errors"] += 1
            return True

        try:
            with open_directory(data_dir / folder) as directory, os.scandir(directory) as entries:
                candidates = []
                for entry in entries:
                    if stop.is_set():
                        return result
                    if entry.name in protected or not CACHE_NAME.fullmatch(entry.name):
                        continue
                    try:
                        observed = entry.stat(follow_symlinks=False)
                    except FileNotFoundError:
                        continue
                    except OSError:
                        result["errors"] += 1
                        continue
                    if (
                        not stat.S_ISREG(observed.st_mode)
                        or observed.st_nlink != 1
                        or max(observed.st_mtime, observed.st_ctime) >= cutoff
                    ):
                        continue
                    candidates.append((entry.name, observed))
                    if len(candidates) == BATCH_SIZE:
                        if not discard(directory, candidates):
                            return result
                        candidates.clear()
                if candidates and not discard(directory, candidates):
                    return result
        except FileNotFoundError:
            pass
        except OSError:
            result["errors"] += 1
    return result

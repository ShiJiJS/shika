"""Recover a restored identity only from a current verified rollback witness."""

from pathlib import Path

from sqlalchemy import select

from .models import ImagePack, PackPage
from .rollback_images import ReturnedImageReads


def returned_continuity(session, pack, observations, stamp, root_path):
    old = pack.directory_signature
    if not old or old[:2] != stamp[:2]:
        return False
    if old[-1] is not None and stamp[-1] is not None and old[-1] != stamp[-1]:
        return False
    current = {row["relative_path"]: row for row in observations}
    for page in session.scalars(select(PackPage).where(PackPage.pack_id == pack.id)):
        row = current.get(page.relative_path)
        if (
            row
            and row["path"] == str(Path(pack.path) / page.relative_path)
            and page.sha256
            and row["sha256"] == page.sha256
            and row["signature"][:4] == page.signature[:4]
            and next(ReturnedImageReads.evidence(session, page, pack, root_path), None)
        ):
            return True
    return False


def unmanaged_duplicate(session, duplicate):
    """Never remove a duplicate carrying any management or operation reference.

    Inspect foreign keys rather than maintaining an incomplete list of user
    tables. Future pack references automatically prevent automatic repair.
    """
    for table in ImagePack.metadata.tables.values():
        if table is PackPage.__table__:
            continue
        for foreign_key in table.foreign_keys:
            if foreign_key.column is ImagePack.__table__.c.id:
                if session.scalar(
                    select(foreign_key.parent).where(foreign_key.parent == duplicate.id).limit(1)
                ):
                    return False
    return True

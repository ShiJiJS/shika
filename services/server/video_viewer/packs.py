"""Authoritative pack queries and versioned page manifests, independent of viewing."""

from pathlib import Path

from sqlalchemy import exists, func, select

from .errors import LibraryError
from .media_roots import owned_path
from .models import Directory, ImagePack, PackPage, PackProgress, PackTagLink, RecentEntry, Root


class Packs:
    def __init__(self, db):
        self.db = db

    @staticmethod
    def page_statement(session, pack_id):
        return (
            select(PackPage)
            .join(ImagePack)
            .where(
                PackPage.pack_id == pack_id, owned_path(session, PackPage.path, ImagePack.root_id)
            )
        )

    def statement(
        self,
        session,
        *,
        directory_id=None,
        search="",
        tag_ids=(),
        read_state="all",
        sort="name",
        status="available",
        source="library",
    ):
        statement = select(ImagePack).join(Root).outerjoin(PackProgress)
        if source == "recent":
            statement = statement.join(
                RecentEntry, RecentEntry.pack_id == ImagePack.id
            ).where(RecentEntry.kind == "pack")
        if sort == "recent" and source != "recent":
            raise LibraryError("invalid_pack_sort", "最近排序只用于最近图包", 422)
        if status in ("available", "unreadable"):
            statement = statement.where(
                ImagePack.status == "available",
                Root.available.is_(True),
                Root.enabled.is_(True),
                Root.kind == "pack",
                owned_path(session, ImagePack.path, ImagePack.root_id),
            )
            if status == "available":
                readable = exists(
                    select(PackPage.id).where(
                        PackPage.pack_id == ImagePack.id,
                        PackPage.error.is_(None),
                        owned_path(session, PackPage.path, ImagePack.root_id),
                    )
                )
                statement = statement.where(ImagePack.error.is_(None), readable)
            else:
                statement = statement.where(ImagePack.error.is_not(None))
        else:
            statement = statement.where(ImagePack.status == status)
        if directory_id:
            directory = session.get(Directory, directory_id)
            if not directory:
                raise LibraryError("directory_not_found", "目录不存在，请重新选择", 404)
            statement = statement.where(
                (ImagePack.path == directory.path)
                | ImagePack.path.startswith(directory.path + "/", autoescape=True)
            )
        if search:
            statement = statement.where(
                ImagePack.name.contains(search, autoescape=True)
                | func.substr(ImagePack.path, func.length(Root.path) + 1).contains(
                    search, autoescape=True
                )
            )
        for tag_id in set(tag_ids):
            statement = statement.where(
                exists(
                    select(PackTagLink.pack_id).where(
                        PackTagLink.pack_id == ImagePack.id, PackTagLink.tag_id == tag_id
                    )
                )
            )
        if read_state == "unread":
            statement = statement.where(PackProgress.pack_id.is_(None))
        elif read_state == "reading":
            statement = statement.where(PackProgress.completed.is_(False))
        elif read_state == "completed":
            statement = statement.where(PackProgress.completed.is_(True))
        return statement.order_by(*self.ordering(sort))

    @staticmethod
    def ordering(sort):
        if sort == "recent":
            return (RecentEntry.opened_at.desc(), ImagePack.id)
        return (
            ImagePack.created_at.desc() if sort == "newest" else func.lower(ImagePack.name),
            ImagePack.id,
        )

    def summary(self, session, pack):
        pages = self.page_statement(session, pack.id)
        count = session.scalar(select(func.count()).select_from(pages.subquery()))
        readable = pages.where(PackPage.error.is_(None))
        readable_count = session.scalar(select(func.count()).select_from(readable.subquery()))
        cover = session.scalar(readable.order_by(PackPage.ordinal, PackPage.id).limit(1))
        progress = session.get(PackProgress, pack.id)
        return {
            "id": pack.id,
            "root_id": pack.root_id,
            "path": pack.path,
            "name": pack.name,
            "status": pack.status,
            "error": pack.error,
            "page_count": count,
            "readable_count": readable_count,
            "content_version": pack.content_version,
            "tag_ids": sorted(tag.id for tag in pack.tags),
            "tag_names": {tag.id: tag.name for tag in sorted(pack.tags, key=lambda tag: tag.id)},
            "created_at": pack.created_at,
            "cover_url": f"/api/v1/packs/{pack.id}/cover?v={pack.content_version}"
            if cover and cover.thumbnail
            else None,
            "progress": None
            if not progress
            else {
                "page_id": progress.page_id,
                "offset_ratio": progress.offset_ratio,
                "completed": progress.completed,
                "revision": progress.revision,
                "updated_at": progress.updated_at,
            },
        }

    def list(self, *, offset=0, limit=24, anchor_ids=(), **query):
        with self.db.read() as session:
            session.connection().exec_driver_sql("BEGIN")
            statement = self.statement(session, **query)
            total = session.scalar(
                select(func.count()).select_from(statement.order_by(None).subquery())
            )
            anchor_index = None
            if anchor_ids:
                ranked = statement.order_by(None).with_only_columns(
                    ImagePack.id.label("pack_id"),
                    (func.row_number().over(order_by=self.ordering(query.get("sort", "name"))) - 1).label("position"),
                ).subquery()
                positions = dict(session.execute(
                    select(ranked.c.pack_id, ranked.c.position).where(ranked.c.pack_id.in_(anchor_ids))
                ).all())
                anchor_index = next(
                    (positions[identity] for identity in anchor_ids if identity in positions),
                    min(offset, max(0, total - 1)),
                )
                offset = anchor_index // limit * limit
            return {
                "items": [
                    self.summary(session, pack)
                    for pack in session.scalars(statement.offset(offset).limit(limit))
                ],
                "total": total,
                "offset": offset,
                "limit": limit,
                "anchor_index": anchor_index,
            }

    def selection(self, **query):
        from .catalog_selection import membership

        with self.db.read() as session:
            session.connection().exec_driver_sql("BEGIN")
            return membership(session, self.statement(session, **query), ImagePack.id, "pack")

    def get(self, pack_id):
        with self.db.read() as session:
            session.connection().exec_driver_sql("BEGIN")
            pack = session.get(ImagePack, pack_id)
            if not pack or pack.status == "discovered":
                raise LibraryError("pack_not_found", "图包不存在", 404)
            return self.summary(session, pack)

    @staticmethod
    def page_json(page, version):
        suffix = f"?v={version}"
        return {
            "id": page.id,
            "pack_id": page.pack_id,
            "name": Path(page.path).name,
            "relative_path": page.relative_path,
            "ordinal": page.ordinal,
            "width": page.width,
            "height": page.height,
            "size": page.size,
            "format": page.format,
            "sha256": page.sha256,
            "error": page.error,
            "content_version": version,
            "image_url": f"/api/v1/pages/{page.id}/image{suffix}" if not page.error else None,
            "thumbnail_url": f"/api/v1/pages/{page.id}/thumbnail{suffix}"
            if page.thumbnail and not page.error
            else None,
        }

    def pages(self, pack_id, *, offset=0, limit=100, version=None):
        with self.db.read() as session:
            session.connection().exec_driver_sql("BEGIN")
            pack = session.scalar(self.statement(session).where(ImagePack.id == pack_id))
            if not pack:
                raise LibraryError("pack_unavailable", "图包当前不可读取", 404)
            if version is not None and pack.content_version != version:
                raise LibraryError("pack_changed", "图包页清单已变化，请重新读取", 409)
            statement = self.page_statement(session, pack.id)
            total = session.scalar(select(func.count()).select_from(statement.subquery()))
            return {
                "items": [
                    self.page_json(page, pack.content_version)
                    for page in session.scalars(
                        statement.order_by(PackPage.ordinal, PackPage.id)
                        .offset(offset)
                        .limit(limit)
                    )
                ],
                "total": total,
                "offset": offset,
                "limit": limit,
                "content_version": pack.content_version,
            }

    def cover(self, pack_id, version=None):
        with self.db.read() as session:
            session.connection().exec_driver_sql("BEGIN")
            pack = session.scalar(self.statement(session).where(ImagePack.id == pack_id))
            if not pack:
                raise LibraryError("pack_unavailable", "图包当前不可读取", 404)
            if version is not None and pack.content_version != version:
                raise LibraryError("pack_changed", "图包页清单已变化，请重新读取", 409)
            page = session.scalar(
                self.page_statement(session, pack.id)
                .where(PackPage.error.is_(None))
                .order_by(PackPage.ordinal, PackPage.id)
                .limit(1)
            )
            return page.id

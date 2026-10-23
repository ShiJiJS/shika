"""Independent pack labels: IDs, counts, idempotent writes, never image labels."""

from sqlalchemy import and_, case, delete, exists, func, select

from .errors import LibraryError
from .media_roots import owned_path
from .models import ImagePack, PackPage, PackTag, PackTagLink, Root
from .requests import once


class PackTags:
    def __init__(self, db):
        self.db = db

    @staticmethod
    def json(tag):
        return {"id": tag.id, "name": tag.name, "kind": "pack"}

    def list(self, search="", offset=0, limit=200):
        with self.db.read() as session:
            session.connection().exec_driver_sql("BEGIN")
            criteria = PackTag.name.contains(search, autoescape=True)
            count = func.count(
                case(
                    (
                        and_(
                            ImagePack.status == "available",
                            ImagePack.error.is_(None),
                            Root.available.is_(True),
                            Root.enabled.is_(True),
                            owned_path(session, ImagePack.path, ImagePack.root_id),
                            exists(
                                select(PackPage.id)
                                .where(
                                    PackPage.pack_id == ImagePack.id,
                                    PackPage.error.is_(None),
                                    owned_path(session, PackPage.path, ImagePack.root_id),
                                )
                                .correlate(ImagePack)
                            ),
                        ),
                        ImagePack.id,
                    )
                )
            )
            statement = (
                select(PackTag, count)
                .outerjoin(PackTagLink, PackTagLink.tag_id == PackTag.id)
                .outerjoin(ImagePack, ImagePack.id == PackTagLink.pack_id)
                .outerjoin(Root, Root.id == ImagePack.root_id)
                .where(criteria)
                .group_by(PackTag.id)
                .order_by(PackTag.name, PackTag.id)
                .offset(offset)
                .limit(limit)
            )
            return {
                "items": [
                    {**self.json(tag), "pack_count": total}
                    for tag, total in session.execute(statement)
                ],
                "total": session.scalar(select(func.count()).select_from(PackTag).where(criteria)),
                "offset": offset,
                "limit": limit,
            }

    def create(self, name, request_id):
        with self.db.write() as session:

            def action():
                self.name_available(session, name)
                tag = PackTag(name=name)
                session.add(tag)
                session.flush()
                return self.json(tag)

            return once(session, "pack_tag.create", request_id, {"name": name}, action)

    @staticmethod
    def name_available(session, name, except_id=None):
        if session.scalar(select(PackTag.id).where(PackTag.name == name, PackTag.id != except_id)):
            raise LibraryError("duplicate_tag", "已有同名图包标签", 409)

    def rename(self, tag_id, name, request_id):
        with self.db.write() as session:

            def action():
                tag = session.get(PackTag, tag_id)
                if not tag:
                    raise LibraryError("tag_not_found", "图包标签不存在", 404)
                self.name_available(session, name, tag_id)
                tag.name = name
                return self.json(tag)

            return once(
                session, "pack_tag.rename", request_id, {"id": tag_id, "name": name}, action
            )

    def delete(self, tag_id, request_id):
        with self.db.write() as session:

            def action():
                tag = session.get(PackTag, tag_id)
                if not tag:
                    raise LibraryError("tag_not_found", "图包标签不存在", 404)
                session.delete(tag)
                session.flush()
                return {"id": tag_id, "deleted": True}

            return once(session, "pack_tag.delete", request_id, {"id": tag_id}, action)

    def assign(self, pack_ids, tag_ids, mode, request_id):
        pack_ids, tag_ids = sorted(set(pack_ids)), sorted(set(tag_ids))
        with self.db.write() as session:

            def action():
                packs = set(
                    session.scalars(
                        select(ImagePack.id).where(
                            ImagePack.id.in_(pack_ids),
                            ImagePack.status.in_(["available", "missing", "trash"]),
                        )
                    )
                )
                tags = set(session.scalars(select(PackTag.id).where(PackTag.id.in_(tag_ids))))
                if packs != set(pack_ids):
                    raise LibraryError("pack_not_found", "部分图包已不可用，未修改标签", 404)
                if tags != set(tag_ids):
                    raise LibraryError("tag_not_found", "部分图包标签不存在，未修改关联", 404)
                current = {identity: set() for identity in pack_ids}
                for link in session.scalars(
                    select(PackTagLink).where(PackTagLink.pack_id.in_(pack_ids))
                ):
                    current[link.pack_id].add(link.tag_id)
                for identity, old in current.items():
                    chosen = set(tag_ids)
                    target = (
                        old | chosen
                        if mode == "add"
                        else old - chosen
                        if mode == "remove"
                        else chosen
                    )
                    session.execute(
                        delete(PackTagLink).where(
                            PackTagLink.pack_id == identity, PackTagLink.tag_id.in_(old - target)
                        )
                    )
                    for tag in target - old:
                        session.add(PackTagLink(pack_id=identity, tag_id=tag))
                return {"updated": len(pack_ids)}

            return once(
                session,
                "pack_tag.assign",
                request_id,
                {"pack_ids": pack_ids, "tag_ids": tag_ids, "mode": mode},
                action,
            )

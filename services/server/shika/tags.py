from sqlalchemy import and_, case, delete, func, select

from .errors import LibraryError
from .media_roots import enabled_path
from .models import PlaybackRound, Root, Setting, Tag, Video, VideoTag
from .requests import once


class Tags:
    def __init__(self, db, playback):
        self.db, self.playback = db, playback

    @staticmethod
    def json(tag):
        return {"id": tag.id, "name": tag.name}

    def list(self, search="", offset=0, limit=200):
        with self.db.read() as session:
            criteria = Tag.name.contains(search, autoescape=True)
            total = session.scalar(select(func.count()).select_from(Tag).where(criteria))
            count = func.count(
                case(
                    (
                        and_(
                            Video.status == "available",
                            Video.error.is_(None),
                            Root.available.is_(True),
                            Root.enabled.is_(True),
                            enabled_path(session, Video.path),
                        ),
                        Video.id,
                    )
                )
            )
            query = (
                select(Tag, count)
                .outerjoin(VideoTag, VideoTag.tag_id == Tag.id)
                .outerjoin(Video, Video.id == VideoTag.video_id)
                .outerjoin(Root, Root.id == Video.root_id)
                .where(criteria)
                .group_by(Tag.id)
                .order_by(Tag.name, Tag.id)
                .offset(offset)
                .limit(limit)
            )
            return {
                "items": [
                    {**self.json(tag), "video_count": count}
                    for tag, count in session.execute(query)
                ],
                "total": total,
                "offset": offset,
                "limit": limit,
            }

    @staticmethod
    def name_available(session, name, except_id=None):
        if session.scalar(select(Tag.id).where(Tag.name == name, Tag.id != except_id)):
            raise LibraryError("duplicate_tag", "已有同名标签", 409)

    def create(self, name, request_id):
        with self.db.write() as session:

            def action():
                self.name_available(session, name)
                tag = Tag(name=name)
                session.add(tag)
                session.flush()
                return self.json(tag)

            return once(session, "tag.create", request_id, {"name": name}, action)

    def rename(self, tag_id, name, request_id):
        with self.db.write() as session:

            def action():
                tag = session.get(Tag, tag_id)
                if not tag:
                    raise LibraryError("tag_not_found", "标签不存在", 404)
                self.name_available(session, name, tag_id)
                tag.name = name
                return self.json(tag)

            return once(session, "tag.rename", request_id, {"id": tag_id, "name": name}, action)

    def delete(self, tag_id, request_id):
        with self.db.write() as session:

            def action():
                tag = session.get(Tag, tag_id)
                if not tag:
                    raise LibraryError("tag_not_found", "标签不存在", 404)
                session.delete(tag)
                session.flush()
                pointer = session.get(Setting, "active_round")
                round = session.get(PlaybackRound, pointer.value) if pointer else None
                replacement = None
                if (
                    round
                    and round.membership != "fixed"
                    and tag_id in round.scope.get("tag_ids", [])
                ):
                    scope = {
                        **round.scope,
                        "tag_ids": [tag for tag in round.scope["tag_ids"] if tag != tag_id],
                    }
                    replacement = self.playback.create_in_session(
                        session,
                        round.order,
                        scope,
                        request_id="tag-delete:" + request_id,
                        allow_missing_scope=True,
                    )["id"]
                return {"id": tag_id, "deleted": True, "replacement_round_id": replacement}

            return once(session, "tag.delete", request_id, {"id": tag_id}, action)

    def assign(self, video_ids, tag_ids, mode, request_id):
        video_ids, tag_ids = sorted(set(video_ids)), sorted(set(tag_ids))
        with self.db.write() as session:

            def action():
                videos = set(
                    session.scalars(
                        select(Video.id).where(
                            Video.id.in_(video_ids),
                            Video.status.in_(["available", "missing", "trash"]),
                        )
                    )
                )
                if videos != set(video_ids):
                    raise LibraryError("video_not_found", "部分视频已不可用，未修改标签", 404)
                tags = set(session.scalars(select(Tag.id).where(Tag.id.in_(tag_ids))))
                if tags != set(tag_ids):
                    raise LibraryError("tag_not_found", "部分标签已不存在，未修改关联", 404)
                current = {video_id: set() for video_id in video_ids}
                for link in session.scalars(
                    select(VideoTag).where(VideoTag.video_id.in_(video_ids))
                ):
                    current[link.video_id].add(link.tag_id)
                added = removed = changed = 0
                for video_id, before in current.items():
                    after = (
                        tags
                        if mode == "replace"
                        else before | tags
                        if mode == "add"
                        else before - tags
                    )
                    additions, removals = after - before, before - after
                    if removals:
                        session.execute(
                            delete(VideoTag).where(
                                VideoTag.video_id == video_id, VideoTag.tag_id.in_(removals)
                            )
                        )
                    session.add_all(
                        VideoTag(video_id=video_id, tag_id=tag_id) for tag_id in additions
                    )
                    added, removed, changed = (
                        added + len(additions),
                        removed + len(removals),
                        changed + bool(additions or removals),
                    )
                session.flush()
                return {
                    "video_ids": video_ids,
                    "changed": changed,
                    "added": added,
                    "removed": removed,
                }

            return once(
                session,
                "tags.assign",
                request_id,
                {"video_ids": video_ids, "tag_ids": tag_ids, "mode": mode},
                action,
            )

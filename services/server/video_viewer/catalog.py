from pathlib import Path

from sqlalchemy import func, or_, select, update

from .errors import LibraryError
from .media_roots import enabled_path, owner_for_path
from .models import Directory, ImagePack, RecentEntry, Root, Setting, Video, VideoTag, uid
from .paths import beneath, excluded, validate_path


class Catalog:
    def __init__(self, db, settings):
        self.db, self.settings = db, settings
        with db.write() as session:
            restored = session.get(Setting, "root_configuration_restored")
            for mount in settings.mounts:
                root = session.get(Root, mount.id)
                if root is None:
                    if restored or session.scalar(
                        select(Root.id).where(Root.mount_id == mount.id).limit(1)
                    ):
                        continue
                    root = Root(
                        id=mount.id, mount_id=mount.id, name=mount.name, path=str(mount.path)
                    )
                    session.add(root)
                    session.flush()
                else:
                    # User-selected subdirectories persist across service starts.
                    if root.mount_id:
                        validate_path(root.path, settings.mounts)
                self.ensure_directory(session, Path(root.path), root.id)

    @staticmethod
    def ensure_directory(session, path, root_id, scan_id=None):
        directory = session.scalar(select(Directory).where(Directory.path == str(path)))
        if directory is None:
            directory = Directory(path=str(path), root_id=root_id, name=path.name)
            session.add(directory)
            session.flush()
        if scan_id:
            directory.seen_scan = scan_id
        return directory

    def roots(self):
        with self.db.read() as session:
            return [
                self.root_json(session, r)
                for r in session.scalars(select(Root).order_by(Root.path))
            ]

    @staticmethod
    def root_json(session, root):
        directory = session.scalar(select(Directory).where(Directory.path == root.path))
        return {
            "id": root.id,
            "name": root.name,
            "path": root.path,
            "directory_id": directory.id,
            "kind": root.kind,
            "enabled": root.enabled,
            "available": root.available,
            "error": root.error,
            "last_scan": root.last_scan,
        }

    def save_root(self, name, path, root_id=None, *, kind=None, enabled=None):
        candidate, mount = validate_path(path, self.settings.mounts)
        if excluded(candidate, self.settings.data_dir):
            raise LibraryError("reserved_directory", "该目录保留给回收站或管理数据", 422)
        with self.db.write() as session:
            root = (
                session.get(Root, root_id)
                if root_id
                else session.scalar(select(Root).where(Root.path == str(candidate)))
            )
            previous_path = root.path if root else None
            if root_id and not root:
                raise LibraryError("root_not_found", "媒体目录不存在", 404)
            occupied = session.scalar(select(Root).where(Root.path == str(candidate)))
            if occupied and root and occupied.id != root.id:
                raise LibraryError("root_conflict", "该媒体目录已接入")
            if root and kind is not None and root.kind != kind:
                if session.scalar(
                    select(Video.id).where(Video.root_id == root.id).limit(1)
                ) or session.scalar(
                    select(ImagePack.id).where(ImagePack.root_id == root.id).limit(1)
                ):
                    raise LibraryError(
                        "root_kind_conflict",
                        "已有内容的目录不能直接更改媒体类型，请新建接入目录",
                        409,
                    )
            if root and root.path != str(candidate):
                other_roots = list(
                    session.scalars(select(Root).where(Root.id != root.id, Root.kind == "video"))
                )
                for video in session.scalars(select(Video).where(Video.root_id == root.id)):
                    if not beneath(Path(video.path), candidate):
                        replacement = next(
                            (r for r in other_roots if beneath(Path(video.path), Path(r.path))),
                            None,
                        )
                        if replacement:
                            video.root_id = replacement.id
                        elif video.status == "available":
                            video.status, video.location_key = "missing", None
                for pack in session.scalars(select(ImagePack).where(ImagePack.root_id == root.id)):
                    if not beneath(Path(pack.path), candidate) and pack.status == "available":
                        pack.status, pack.location_key = "missing", None
                root.path, root.available, root.last_scan = str(candidate), False, None
            if not root:
                root = Root(name=name, path=str(candidate), mount_id=mount.id)
                # Root IDs are also stable for user-added subdirectories.
                root.id = uid()
                session.add(root)
                session.flush()
            policy_changed = (
                previous_path != str(candidate)
                or (kind is not None and root.kind != kind)
                or (enabled is not None and root.enabled != enabled)
            )
            if kind is not None and root.kind != kind:
                root.last_scan, root.available, root.error = None, False, None
            root.name, root.mount_id = name, mount.id
            root.kind = kind if kind is not None else root.kind
            root.enabled = enabled if enabled is not None else root.enabled
            if policy_changed:
                scopes = {candidate, Path(previous_path)} if previous_path else {candidate}
                affected = [
                    identity
                    for identity, pack_path in session.execute(select(ImagePack.id, ImagePack.path))
                    if any(
                        beneath(Path(pack_path), scope) or beneath(scope, Path(pack_path))
                        for scope in scopes
                    )
                ]
                if affected:
                    session.execute(
                        update(ImagePack)
                        .where(ImagePack.id.in_(affected))
                        .values(content_version=ImagePack.content_version + 1)
                    )
            self.ensure_directory(session, candidate, root.id)
            return self.root_json(session, root)

    def directories(self, parent_id=None, kind="video", *, offset=0, limit=None):
        with self.db.read() as session:
            all_roots = list(session.scalars(select(Root)))
            roots = [root for root in all_roots if root.kind == kind]
            if not parent_id:
                selected = roots[offset:] if limit is None else roots[offset : offset + limit]
                items = []
                for root in selected:
                    data = self.root_json(session, root)
                    items.append(
                        {
                            **data,
                            "id": data["directory_id"],
                            "root_id": root.id,
                            "available": root.available and root.enabled,
                        }
                    )
                return {"items": items, "total": len(roots), "offset": offset, "limit": limit}
            parent = session.get(Directory, parent_id)
            if not parent:
                raise LibraryError("directory_not_found", "目录不存在", 404)
            if not any(beneath(Path(parent.path), Path(root.path)) for root in roots):
                raise LibraryError("directory_not_found", "目录不在接入范围内", 404)
            owner = owner_for_path(parent.path, all_roots, kind)
            if not owner or not owner.available:
                raise LibraryError("root_unavailable", "媒体目录暂不可用")
            tail = func.substr(Directory.path, len(parent.path) + 2)
            statement = select(Directory).where(
                Directory.path.startswith(parent.path + "/", autoescape=True),
                func.instr(tail, "/") == 0,
            )
            total = session.scalar(select(func.count()).select_from(statement.subquery()))
            statement = statement.order_by(Directory.path).offset(offset)
            if limit is not None:
                statement = statement.limit(limit)
            items = []
            for directory in session.scalars(statement):
                owner = owner_for_path(directory.path, all_roots, kind)
                items.append(
                    {
                        "id": directory.id,
                        "root_id": owner.id if owner else directory.root_id,
                        "name": directory.name,
                        "path": directory.path,
                        "available": bool(owner and owner.available),
                    }
                )
            return {"items": items, "total": total, "offset": offset, "limit": limit}

    def directory(self, *, directory_id=None, path=None, kind="video"):
        with self.db.read() as session:
            if path is not None:
                validate_path(path, self.settings.mounts)
                directory = session.scalar(
                    select(Directory).where(Directory.path == str(Path(path)))
                )
            else:
                directory = session.get(Directory, directory_id)
            if not directory:
                raise LibraryError("directory_not_found", "目录不存在，请重新选择", 404)
            roots = [
                root
                for root in session.scalars(select(Root))
                if beneath(Path(directory.path), Path(root.path))
            ]
            if not roots:
                raise LibraryError("directory_not_found", "目录不在当前接入范围内", 404)
            owner = owner_for_path(directory.path, roots, kind)
            available = bool(owner and owner.available)
            return {
                "id": directory.id,
                "root_id": owner.id if owner else directory.root_id,
                "path": directory.path,
                "name": directory.name,
                "available": available,
                "error": None
                if available
                else next((root.error for root in roots if root.error), "root_unavailable"),
            }

    def video_statement(
        self,
        session,
        *,
        directory_id=None,
        status="available",
        search="",
        orientation=None,
        duration=None,
        file_type=None,
        tag_ids=(),
    ):
        statement = select(Video).join(Root).where(Video.status == status)
        if status == "available":
            statement = statement.where(
                Root.available.is_(True),
                Root.enabled.is_(True),
                Root.kind == "video",
                Video.error.is_(None),
                enabled_path(session, Video.path),
            )
        if directory_id:
            directory = session.get(Directory, directory_id)
            if not directory:
                raise LibraryError("directory_not_found", "目录不存在", 404)
            statement = statement.where(
                or_(
                    Video.path == directory.path,
                    Video.path.startswith(directory.path + "/", autoescape=True),
                )
            )
        if search:
            statement = statement.where(
                Video.name.contains(search, autoescape=True)
                | func.substr(Video.path, func.length(Root.path) + 1).contains(
                    search, autoescape=True
                )
            )
        if orientation:
            statement = statement.where(
                Video.height > Video.width
                if orientation == "portrait"
                else Video.height <= Video.width
            )
        if duration:
            statement = statement.where(
                Video.duration <= 10 if duration == "short" else Video.duration > 10
            )
        if file_type:
            statement = statement.where(Video.type == file_type.upper())
        chosen_tags = sorted(set(tag_ids))
        if chosen_tags:
            matching = (
                select(VideoTag.video_id)
                .where(VideoTag.tag_id.in_(chosen_tags))
                .group_by(VideoTag.video_id)
                .having(func.count(VideoTag.tag_id) == len(chosen_tags))
            )
            statement = statement.where(Video.id.in_(matching))
        return statement

    @staticmethod
    def video_ordering(source, sort):
        if sort == "recent":
            if source != "recent":
                raise LibraryError("invalid_sort", "最近排序仅适用于最近入口", 422)
            ordering = (RecentEntry.opened_at.desc(), Video.id)
        elif sort == "name":
            ordering = (func.lower(Video.name), Video.path, Video.id)
        elif sort == "newest":
            ordering = (Video.created_at.desc(), Video.id)
        else:
            ordering = (Video.path, Video.id)
        return ordering

    def ordered_videos(self, session, *, source="library", sort="path", **scope):
        statement = self.video_statement(session, **scope)
        if source == "recent":
            statement = statement.join(
                RecentEntry,
                (RecentEntry.video_id == Video.id) & (RecentEntry.kind == "video"),
            )
        return statement.order_by(*self.video_ordering(source, sort))

    def selection(self, **scope):
        from .catalog_selection import membership

        with self.db.read() as session:
            session.connection().exec_driver_sql("BEGIN")
            return membership(session, self.ordered_videos(session, **scope), Video.id, "video")

    def videos(self, *, offset=0, limit=50, source="library", sort="path", anchor_ids=(), **scope):
        with self.db.read() as session:
            session.connection().exec_driver_sql("BEGIN")
            query = self.ordered_videos(session, source=source, sort=sort, **scope)
            total = session.scalar(
                select(func.count()).select_from(query.order_by(None).subquery())
            )
            anchor_index = None
            if anchor_ids:
                ranked = (
                    query.order_by(None)
                    .with_only_columns(
                        Video.id.label("video_id"),
                        (
                            func.row_number().over(order_by=self.video_ordering(source, sort)) - 1
                        ).label("position"),
                    )
                    .subquery()
                )
                positions = dict(
                    session.execute(
                        select(ranked.c.video_id, ranked.c.position).where(
                            ranked.c.video_id.in_(anchor_ids)
                        )
                    ).all()
                )
                anchor_index = next(
                    (positions[identity] for identity in anchor_ids if identity in positions),
                    min(offset, max(0, total - 1)),
                )
                offset = anchor_index // limit * limit
            items = session.scalars(query.offset(offset).limit(limit))
            result = []
            for video in items:
                item = self.video_json(video)
                if source == "recent":
                    item["opened_at"] = session.scalar(
                        select(RecentEntry.opened_at).where(
                            RecentEntry.video_id == video.id, RecentEntry.kind == "video"
                        )
                    )
                result.append(item)
            return {
                "items": result,
                "total": total,
                "offset": offset,
                "limit": limit,
                **({"anchor_index": anchor_index} if anchor_ids else {}),
            }

    @staticmethod
    def video_json(video):
        return {
            "id": video.id,
            "root_id": video.root_id,
            "path": video.path,
            "name": video.name,
            "status": video.status,
            "error": video.error,
            "size": video.size,
            "created_at": video.created_at,
            "duration": video.duration,
            "width": video.width,
            "height": video.height,
            "rotation": video.rotation,
            "type": video.type,
            "video_codec": video.video_codec,
            "audio_codec": video.audio_codec,
            "container": video.container,
            "thumbnail_url": f"/api/v1/videos/{video.id}/thumbnail" if video.thumbnail else None,
            "media_url": f"/api/v1/videos/{video.id}/stream",
            "tag_ids": sorted(tag.id for tag in video.tags),
        }

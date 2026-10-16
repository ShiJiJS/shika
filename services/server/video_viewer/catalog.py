from pathlib import Path

from sqlalchemy import func, or_, select

from .errors import LibraryError
from .models import Directory, Root, Setting, Video, VideoTag, uid
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
            "available": root.available,
            "error": root.error,
            "last_scan": root.last_scan,
        }

    def save_root(self, name, path, root_id=None):
        candidate, mount = validate_path(path, self.settings.mounts)
        if excluded(candidate, self.settings.data_dir):
            raise LibraryError("reserved_directory", "该目录保留给回收站或管理数据", 422)
        with self.db.write() as session:
            root = (
                session.get(Root, root_id)
                if root_id
                else session.scalar(select(Root).where(Root.path == str(candidate)))
            )
            if root_id and not root:
                raise LibraryError("root_not_found", "媒体目录不存在", 404)
            occupied = session.scalar(select(Root).where(Root.path == str(candidate)))
            if occupied and root and occupied.id != root.id:
                raise LibraryError("root_conflict", "该媒体目录已接入")
            if root and root.path != str(candidate):
                other_roots = list(session.scalars(select(Root).where(Root.id != root.id)))
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
                root.path, root.available, root.last_scan = str(candidate), False, None
            if not root:
                root = Root(name=name, path=str(candidate), mount_id=mount.id)
                # Root IDs are also stable for user-added subdirectories.
                root.id = uid()
                session.add(root)
                session.flush()
            root.name, root.mount_id = name, mount.id
            self.ensure_directory(session, candidate, root.id)
            return self.root_json(session, root)

    def directories(self, parent_id=None):
        with self.db.read() as session:
            roots = list(session.scalars(select(Root)))
            if not parent_id:
                return [
                    {
                        **self.root_json(session, r),
                        "id": self.root_json(session, r)["directory_id"],
                        "root_id": r.id,
                    }
                    for r in roots
                ]
            parent = session.get(Directory, parent_id)
            if not parent:
                raise LibraryError("directory_not_found", "目录不存在", 404)
            allowed_roots = [r for r in roots if beneath(Path(parent.path), Path(r.path))]
            if not allowed_roots:
                raise LibraryError("directory_not_found", "目录不在接入范围内", 404)
            if not any(r.available for r in allowed_roots):
                raise LibraryError("root_unavailable", "媒体目录暂不可用")
            statement = (
                select(Directory)
                .where(Directory.path.startswith(parent.path + "/", autoescape=True))
                .order_by(Directory.path)
            )
            return [
                {
                    "id": d.id,
                    "root_id": d.root_id,
                    "name": d.name,
                    "path": d.path,
                    "available": True,
                }
                for d in session.scalars(statement)
                if Path(d.path).parent == Path(parent.path)
            ]

    def directory(self, *, directory_id=None, path=None):
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
            available = any(root.available for root in roots)
            return {
                "id": directory.id,
                "root_id": directory.root_id,
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
            statement = statement.where(Root.available.is_(True), Video.error.is_(None))
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
            statement = statement.where(Video.name.contains(search, autoescape=True))
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

    def videos(self, *, offset=0, limit=50, **scope):
        with self.db.read() as session:
            query = self.video_statement(session, **scope)
            total = session.scalar(select(func.count()).select_from(query.subquery()))
            items = session.scalars(
                query.order_by(Video.path, Video.id).offset(offset).limit(limit)
            )
            return {
                "items": [self.video_json(v) for v in items],
                "total": total,
                "offset": offset,
                "limit": limit,
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

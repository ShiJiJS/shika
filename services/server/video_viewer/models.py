import time
import uuid

from sqlalchemy import JSON, Boolean, Float, ForeignKey, Index, Integer, String, Text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


def uid():
    return str(uuid.uuid4())


class Base(DeclarativeBase):
    pass


class Setting(Base):
    __tablename__ = "settings"
    key: Mapped[str] = mapped_column(String, primary_key=True)
    value: Mapped[str] = mapped_column(Text)


class AccessToken(Base):
    __tablename__ = "access_tokens"
    digest: Mapped[str] = mapped_column(String, primary_key=True)
    expires_at: Mapped[float] = mapped_column(Float)


class Root(Base):
    __tablename__ = "roots"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    name: Mapped[str] = mapped_column(String)
    path: Mapped[str] = mapped_column(Text, unique=True)
    mount_id: Mapped[str] = mapped_column(String)
    available: Mapped[bool] = mapped_column(Boolean, default=False)
    error: Mapped[str | None] = mapped_column(String, nullable=True)
    last_scan: Mapped[float | None] = mapped_column(Float, nullable=True)


class Directory(Base):
    __tablename__ = "directories"
    id: Mapped[str] = mapped_column(String, primary_key=True, default=uid)
    root_id: Mapped[str] = mapped_column(ForeignKey("roots.id"), index=True)
    path: Mapped[str] = mapped_column(Text, unique=True)
    name: Mapped[str] = mapped_column(String)
    seen_scan: Mapped[str | None] = mapped_column(String, nullable=True)


class Video(Base):
    __tablename__ = "videos"
    id: Mapped[str] = mapped_column(String, primary_key=True, default=uid)
    root_id: Mapped[str] = mapped_column(ForeignKey("roots.id"), index=True)
    path: Mapped[str] = mapped_column(Text, index=True)
    location_key: Mapped[str | None] = mapped_column(Text, unique=True, nullable=True)
    name: Mapped[str] = mapped_column(String)
    status: Mapped[str] = mapped_column(String, default="available", index=True)
    error: Mapped[str | None] = mapped_column(String, nullable=True)
    generation: Mapped[int] = mapped_column(Integer, default=0)
    size: Mapped[int] = mapped_column(Integer)
    device: Mapped[str] = mapped_column(String)
    inode: Mapped[str] = mapped_column(String)
    mtime_ns: Mapped[str] = mapped_column(String)
    ctime_ns: Mapped[str] = mapped_column(String)
    sha256: Mapped[str] = mapped_column(String, index=True)
    quick_hash: Mapped[str] = mapped_column(String, index=True)
    duration: Mapped[float] = mapped_column(Float)
    width: Mapped[int] = mapped_column(Integer)
    height: Mapped[int] = mapped_column(Integer)
    rotation: Mapped[int] = mapped_column(Integer, default=0)
    type: Mapped[str] = mapped_column(String)
    video_codec: Mapped[str] = mapped_column(String)
    audio_codec: Mapped[str | None] = mapped_column(String, nullable=True)
    container: Mapped[str] = mapped_column(String)
    thumbnail: Mapped[str | None] = mapped_column(String, nullable=True)
    seen_scan: Mapped[str] = mapped_column(String)
    created_at: Mapped[float] = mapped_column(Float, default=time.time)
    tags: Mapped[list["Tag"]] = relationship(secondary="video_tags", lazy="selectin", viewonly=True)
    __table_args__ = (Index("videos_order", "path", "id"),)


class Observation(Base):
    __tablename__ = "observations"
    path: Mapped[str] = mapped_column(Text, primary_key=True)
    signature: Mapped[list] = mapped_column(JSON)
    stable_since: Mapped[float] = mapped_column(Float)


class Task(Base):
    __tablename__ = "tasks"
    id: Mapped[str] = mapped_column(String, primary_key=True, default=uid)
    kind: Mapped[str] = mapped_column(String)
    status: Mapped[str] = mapped_column(String, default="queued", index=True)
    phase: Mapped[str] = mapped_column(String, default="queued")
    created_at: Mapped[float] = mapped_column(Float, default=time.time)
    finished_at: Mapped[float | None] = mapped_column(Float, nullable=True)
    result: Mapped[dict] = mapped_column(JSON, default=dict)
    error: Mapped[str | None] = mapped_column(String, nullable=True)


class PlaybackRound(Base):
    __tablename__ = "playback_rounds"
    id: Mapped[str] = mapped_column(String, primary_key=True, default=uid)
    request_id: Mapped[str] = mapped_column(String, unique=True)
    request_hash: Mapped[str] = mapped_column(String)
    order: Mapped[str] = mapped_column(String)
    scope: Mapped[dict] = mapped_column(JSON)
    cursor: Mapped[int] = mapped_column(Integer, default=0)
    revision: Mapped[int] = mapped_column(Integer, default=0)
    finished: Mapped[bool] = mapped_column(Boolean, default=False)
    candidate_count: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[float] = mapped_column(Float, default=time.time)


class RoundEntry(Base):
    __tablename__ = "round_entries"
    round_id: Mapped[str] = mapped_column(
        ForeignKey("playback_rounds.id", ondelete="CASCADE"), primary_key=True
    )
    ordinal: Mapped[int] = mapped_column(Integer, primary_key=True)
    video_id: Mapped[str] = mapped_column(ForeignKey("videos.id"), index=True)


class Tag(Base):
    __tablename__ = "tags"
    id: Mapped[str] = mapped_column(String, primary_key=True, default=uid)
    name: Mapped[str] = mapped_column(String, unique=True)
    created_at: Mapped[float] = mapped_column(Float, default=time.time)


class VideoTag(Base):
    __tablename__ = "video_tags"
    video_id: Mapped[str] = mapped_column(
        ForeignKey("videos.id", ondelete="CASCADE"), primary_key=True
    )
    tag_id: Mapped[str] = mapped_column(ForeignKey("tags.id", ondelete="CASCADE"), primary_key=True)
    __table_args__ = (Index("video_tags_tag_video", "tag_id", "video_id"),)


class RequestRecord(Base):
    __tablename__ = "request_records"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    fingerprint: Mapped[str] = mapped_column(String)
    result: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[float] = mapped_column(Float, default=time.time)


class FileOperation(Base):
    __tablename__ = "file_operations"
    id: Mapped[str] = mapped_column(ForeignKey("tasks.id"), primary_key=True)
    request_key: Mapped[str] = mapped_column(String, unique=True)
    request_hash: Mapped[str] = mapped_column(String)
    kind: Mapped[str] = mapped_column(String)
    undo_of: Mapped[str | None] = mapped_column(String, nullable=True)
    round_snapshot: Mapped[dict] = mapped_column(JSON, default=dict)
    historical: Mapped[bool] = mapped_column(Boolean, default=False)


class FileStep(Base):
    __tablename__ = "file_steps"
    id: Mapped[str] = mapped_column(String, primary_key=True, default=uid)
    operation_id: Mapped[str] = mapped_column(ForeignKey("file_operations.id"), index=True)
    requested_id: Mapped[str] = mapped_column(String)
    video_id: Mapped[str | None] = mapped_column(ForeignKey("videos.id"), nullable=True, index=True)
    trash_id: Mapped[str | None] = mapped_column(String, nullable=True)
    original_status: Mapped[str] = mapped_column(String, default="available")
    root_path: Mapped[str] = mapped_column(Text, default="")
    original_path: Mapped[str] = mapped_column(Text, default="")
    source: Mapped[str] = mapped_column(Text, default="")
    destination: Mapped[str] = mapped_column(Text, default="")
    staging: Mapped[str] = mapped_column(Text, default="")
    copy_path: Mapped[str] = mapped_column(Text, default="")
    expected_hash: Mapped[str] = mapped_column(String, default="")
    expected_size: Mapped[int] = mapped_column(Integer, default=0)
    source_signature: Mapped[list] = mapped_column(JSON, default=list)
    claimed_identity: Mapped[list] = mapped_column(JSON, default=list)
    published_identity: Mapped[list] = mapped_column(JSON, default=list)
    copy_identity: Mapped[list] = mapped_column(JSON, default=list)
    phase: Mapped[str] = mapped_column(String, default="prepared", index=True)
    outcome: Mapped[str] = mapped_column(String, default="pending")
    error: Mapped[str | None] = mapped_column(String, nullable=True)


class TrashItem(Base):
    __tablename__ = "trash_items"
    id: Mapped[str] = mapped_column(String, primary_key=True, default=uid)
    video_id: Mapped[str] = mapped_column(ForeignKey("videos.id"), index=True)
    operation_id: Mapped[str] = mapped_column(ForeignKey("file_operations.id"))
    root_path: Mapped[str] = mapped_column(Text)
    original_path: Mapped[str] = mapped_column(Text)
    trash_path: Mapped[str] = mapped_column(Text)
    sha256: Mapped[str] = mapped_column(String)
    size: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String, default="active", index=True)
    deleted_at: Mapped[float] = mapped_column(Float, default=time.time)

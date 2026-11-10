import time
import uuid

from sqlalchemy import (
    JSON,
    Boolean,
    CheckConstraint,
    Float,
    ForeignKey,
    ForeignKeyConstraint,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    text,
)
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
    issued_epoch: Mapped[str] = mapped_column(String, default="", server_default="")


class Root(Base):
    __tablename__ = "roots"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    name: Mapped[str] = mapped_column(String)
    path: Mapped[str] = mapped_column(Text, unique=True)
    mount_id: Mapped[str] = mapped_column(String)
    kind: Mapped[str] = mapped_column(String, default="video", server_default="video")
    enabled: Mapped[bool] = mapped_column(Boolean, default=True, server_default="1")
    available: Mapped[bool] = mapped_column(Boolean, default=False)
    error: Mapped[str | None] = mapped_column(String, nullable=True)
    last_scan: Mapped[float | None] = mapped_column(Float, nullable=True)
    __table_args__ = (
        CheckConstraint("kind IN ('video','pack')"),
        CheckConstraint("enabled IN (0,1)"),
    )


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
    membership: Mapped[str] = mapped_column(String, default="legacy", server_default="legacy")
    source: Mapped[str] = mapped_column(String, default="library", server_default="library")
    sort: Mapped[str] = mapped_column(String, default="path", server_default="path")
    sequence_revision: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
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
    source_ordinal: Mapped[int | None] = mapped_column(Integer, nullable=True)
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


class ImagePack(Base):
    __tablename__ = "packs"
    id: Mapped[str] = mapped_column(String, primary_key=True, default=uid)
    root_id: Mapped[str] = mapped_column(ForeignKey("roots.id"), index=True)
    # Paths may be reused by a replacement while the old missing ID keeps its
    # tags/progress. Only location_key reserves the current physical location;
    # a matching path alone must never transfer the old pack's identity.
    path: Mapped[str] = mapped_column(Text, index=True)
    location_key: Mapped[str | None] = mapped_column(Text, unique=True, nullable=True)
    name: Mapped[str] = mapped_column(String)
    status: Mapped[str] = mapped_column(String, default="available", index=True)
    error: Mapped[str | None] = mapped_column(String, nullable=True)
    device: Mapped[str] = mapped_column(String, default="")
    inode: Mapped[str] = mapped_column(String, default="")
    directory_signature: Mapped[list] = mapped_column(JSON, default=list, server_default="[]")
    content_version: Mapped[int] = mapped_column(Integer, default=0)
    page_count: Mapped[int] = mapped_column(Integer, default=0)
    generation: Mapped[int] = mapped_column(Integer, default=0)
    seen_scan: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[float] = mapped_column(Float, default=time.time)
    tags: Mapped[list["PackTag"]] = relationship(
        secondary="pack_tag_links", lazy="selectin", viewonly=True
    )
    __table_args__ = (CheckConstraint("content_version >= 0 AND page_count >= 0"),)


class PackPage(Base):
    __tablename__ = "pack_pages"
    id: Mapped[str] = mapped_column(String, primary_key=True, default=uid)
    pack_id: Mapped[str] = mapped_column(ForeignKey("packs.id", ondelete="CASCADE"), index=True)
    path: Mapped[str] = mapped_column(Text, index=True)
    relative_path: Mapped[str] = mapped_column(Text)
    ordinal: Mapped[int] = mapped_column(Integer)
    width: Mapped[int] = mapped_column(Integer)
    height: Mapped[int] = mapped_column(Integer)
    size: Mapped[int] = mapped_column(Integer)
    format: Mapped[str] = mapped_column(String)
    signature: Mapped[list] = mapped_column(JSON, default=list)
    sha256: Mapped[str | None] = mapped_column(String, nullable=True)
    error: Mapped[str | None] = mapped_column(String, nullable=True)
    thumbnail: Mapped[str | None] = mapped_column(String, nullable=True)
    seen_scan: Mapped[str | None] = mapped_column(String, nullable=True)
    __table_args__ = (
        UniqueConstraint("pack_id", "id"),
        UniqueConstraint("pack_id", "relative_path"),
        Index("pack_pages_order", "pack_id", "ordinal", "id"),
        CheckConstraint("ordinal >= 0 AND width >= 0 AND height >= 0 AND size >= 0"),
    )


class PackTag(Base):
    __tablename__ = "pack_tag_definitions"
    id: Mapped[str] = mapped_column(String, primary_key=True, default=uid)
    name: Mapped[str] = mapped_column(String, unique=True)
    created_at: Mapped[float] = mapped_column(Float, default=time.time)


class PackTagLink(Base):
    __tablename__ = "pack_tag_links"
    pack_id: Mapped[str] = mapped_column(
        ForeignKey("packs.id", ondelete="CASCADE"), primary_key=True
    )
    tag_id: Mapped[str] = mapped_column(
        ForeignKey("pack_tag_definitions.id", ondelete="CASCADE"), primary_key=True
    )
    __table_args__ = (Index("pack_tags_tag_pack", "tag_id", "pack_id"),)


class PackProgress(Base):
    __tablename__ = "pack_progress"
    pack_id: Mapped[str] = mapped_column(
        ForeignKey("packs.id", ondelete="CASCADE"), primary_key=True
    )
    page_id: Mapped[str | None] = mapped_column(String, nullable=True)
    offset_ratio: Mapped[float] = mapped_column(Float, default=0)
    completed: Mapped[bool] = mapped_column(Boolean, default=False)
    revision: Mapped[int] = mapped_column(Integer, default=0)
    content_version: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    recovery_reason: Mapped[str | None] = mapped_column(String, nullable=True)
    updated_at: Mapped[float] = mapped_column(Float, default=time.time)
    __table_args__ = (
        ForeignKeyConstraint(["pack_id", "page_id"], ["pack_pages.pack_id", "pack_pages.id"]),
        CheckConstraint("offset_ratio >= 0 AND offset_ratio <= 1 AND revision >= 0"),
    )


class PackPreferences(Base):
    __tablename__ = "pack_preferences"
    pack_id: Mapped[str] = mapped_column(
        ForeignKey("packs.id", ondelete="CASCADE"), primary_key=True
    )
    revision: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    mode: Mapped[str] = mapped_column(String, default="vertical")
    direction: Mapped[str] = mapped_column(String, default="ltr")
    gap: Mapped[bool] = mapped_column(Boolean, default=False)
    fit: Mapped[str] = mapped_column(String, default="contain")
    __table_args__ = (
        CheckConstraint("mode IN ('horizontal','vertical')"),
        CheckConstraint("direction IN ('ltr','rtl')"),
        CheckConstraint("fit IN ('contain','width')"),
    )


class RecentEntry(Base):
    __tablename__ = "recent_entries"
    id: Mapped[str] = mapped_column(String, primary_key=True, default=uid)
    kind: Mapped[str] = mapped_column(String)
    video_id: Mapped[str | None] = mapped_column(
        ForeignKey("videos.id", ondelete="CASCADE"), unique=True, nullable=True
    )
    pack_id: Mapped[str | None] = mapped_column(
        ForeignKey("packs.id", ondelete="CASCADE"), unique=True, nullable=True
    )
    opened_at: Mapped[float] = mapped_column(Float, default=time.time, index=True)
    __table_args__ = (
        CheckConstraint(
            "(kind='video' AND video_id IS NOT NULL AND pack_id IS NULL) OR (kind='pack' AND pack_id IS NOT NULL AND video_id IS NULL)"
        ),
    )


class PackSession(Base):
    __tablename__ = "pack_sessions"
    id: Mapped[str] = mapped_column(String, primary_key=True, default=uid)
    request_id: Mapped[str] = mapped_column(String, unique=True)
    request_hash: Mapped[str] = mapped_column(String)
    scope: Mapped[dict] = mapped_column(JSON)
    source: Mapped[dict] = mapped_column(JSON, default=dict)
    order: Mapped[str] = mapped_column(String, default="sequential")
    cursor: Mapped[int] = mapped_column(Integer, default=0)
    revision: Mapped[int] = mapped_column(Integer, default=0)
    finished: Mapped[bool] = mapped_column(Boolean, default=False)
    candidate_count: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[float] = mapped_column(Float, default=time.time)
    __table_args__ = (
        CheckConstraint("cursor >= 0 AND revision >= 0 AND candidate_count >= 0"),
        CheckConstraint("\"order\" IN ('random','sequential')"),
    )


class PackSessionEntry(Base):
    __tablename__ = "pack_session_entries"
    session_id: Mapped[str] = mapped_column(
        ForeignKey("pack_sessions.id", ondelete="CASCADE"), primary_key=True
    )
    ordinal: Mapped[int] = mapped_column(Integer, primary_key=True)
    pack_id: Mapped[str] = mapped_column(ForeignKey("packs.id"), index=True)
    __table_args__ = (UniqueConstraint("session_id", "pack_id"),)


class PackFileOperation(Base):
    __tablename__ = "pack_file_operations"
    id: Mapped[str] = mapped_column(ForeignKey("tasks.id"), primary_key=True)
    request_key: Mapped[str] = mapped_column(String, unique=True)
    request_hash: Mapped[str] = mapped_column(String)
    kind: Mapped[str] = mapped_column(String)
    undo_of: Mapped[str | None] = mapped_column(
        ForeignKey("pack_file_operations.id"), nullable=True
    )
    session_snapshot: Mapped[dict] = mapped_column(JSON, default=dict)
    historical: Mapped[bool] = mapped_column(Boolean, default=False)
    __table_args__ = (CheckConstraint("kind IN ('trash','restore','permanent','undo')"),)


class PackFileStep(Base):
    __tablename__ = "pack_file_steps"
    id: Mapped[str] = mapped_column(String, primary_key=True, default=uid)
    operation_id: Mapped[str] = mapped_column(ForeignKey("pack_file_operations.id"), index=True)
    pack_id: Mapped[str] = mapped_column(ForeignKey("packs.id"), index=True)
    page_id: Mapped[str | None] = mapped_column(ForeignKey("pack_pages.id"), nullable=True)
    requested_id: Mapped[str] = mapped_column(String)
    root_path: Mapped[str] = mapped_column(Text)
    original_path: Mapped[str] = mapped_column(Text)
    source_signature: Mapped[list] = mapped_column(JSON, default=list)
    expected_hash: Mapped[str | None] = mapped_column(String, nullable=True)
    expected_size: Mapped[int] = mapped_column(Integer, default=0)
    phase: Mapped[str] = mapped_column(String, default="prepared", index=True)
    outcome: Mapped[str] = mapped_column(String, default="pending")
    error: Mapped[str | None] = mapped_column(String, nullable=True)


class PackTrashItem(Base):
    __tablename__ = "pack_trash_items"
    purged_pages: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    id: Mapped[str] = mapped_column(String, primary_key=True, default=uid)
    pack_id: Mapped[str] = mapped_column(ForeignKey("packs.id"), index=True)
    operation_id: Mapped[str] = mapped_column(ForeignKey("pack_file_operations.id"))
    root_path: Mapped[str] = mapped_column(Text)
    original_path: Mapped[str] = mapped_column(Text)
    manifest: Mapped[dict] = mapped_column(JSON, default=dict)
    status: Mapped[str] = mapped_column(String, default="active", index=True)
    deleted_at: Mapped[float] = mapped_column(Float, default=time.time)
    __table_args__ = (
        Index("pack_trash_active", "pack_id", unique=True, sqlite_where=text("status='active'")),
    )


class PackMissingCleanup(Base):
    __tablename__ = "pack_missing_cleanups"
    id: Mapped[str] = mapped_column(ForeignKey("tasks.id"), primary_key=True)
    request_id: Mapped[str] = mapped_column(String, unique=True)
    historical: Mapped[bool] = mapped_column(Boolean, default=False)


class PackMissingMember(Base):
    __tablename__ = "pack_missing_members"
    cleanup_id: Mapped[str] = mapped_column(
        ForeignKey("pack_missing_cleanups.id"), primary_key=True
    )
    pack_id: Mapped[str] = mapped_column(ForeignKey("packs.id"), primary_key=True)
    root_id: Mapped[str] = mapped_column(ForeignKey("roots.id"))
    generation: Mapped[int] = mapped_column(Integer)
    name: Mapped[str] = mapped_column(String)
    path: Mapped[str] = mapped_column(Text)
    outcome: Mapped[str] = mapped_column(String, default="pending")
    error: Mapped[str | None] = mapped_column(String, nullable=True)
    __table_args__ = (Index("ix_pack_missing_pending", "cleanup_id", "outcome", "pack_id"),)


class PackRestorePlan(Base):
    __tablename__ = "pack_restore_plans"
    id: Mapped[str] = mapped_column(ForeignKey("tasks.id"), primary_key=True)
    request_key: Mapped[str] = mapped_column(String, unique=True)
    request_hash: Mapped[str] = mapped_column(String)
    historical: Mapped[bool] = mapped_column(Boolean, default=False)
    stop_requested: Mapped[bool] = mapped_column(Boolean, default=False)
    batch_size: Mapped[int] = mapped_column(Integer)
    __table_args__ = (CheckConstraint("batch_size BETWEEN 1 AND 1000"),)


class PackRestoreMember(Base):
    __tablename__ = "pack_restore_members"
    plan_id: Mapped[str] = mapped_column(ForeignKey("pack_restore_plans.id"), primary_key=True)
    ordinal: Mapped[int] = mapped_column(Integer, primary_key=True)
    pack_id: Mapped[str] = mapped_column(ForeignKey("packs.id"), index=True)
    trash_id: Mapped[str] = mapped_column(ForeignKey("pack_trash_items.id"))
    name: Mapped[str] = mapped_column(String)
    path: Mapped[str] = mapped_column(Text)
    source: Mapped[dict] = mapped_column(JSON)
    phase: Mapped[str] = mapped_column(String, default="waiting")
    outcome: Mapped[str] = mapped_column(String, default="pending", index=True)
    error: Mapped[str | None] = mapped_column(String, nullable=True)
    __table_args__ = (UniqueConstraint("plan_id", "trash_id"),)


class PackRestoreBatch(Base):
    __tablename__ = "pack_restore_batches"
    plan_id: Mapped[str] = mapped_column(ForeignKey("pack_restore_plans.id"), primary_key=True)
    ordinal: Mapped[int] = mapped_column(Integer, primary_key=True)
    operation_id: Mapped[str] = mapped_column(ForeignKey("pack_file_operations.id"), unique=True)


class PackPurgePlan(Base):
    __tablename__ = "pack_purge_plans"
    historical: Mapped[bool] = mapped_column(Boolean, default=False, server_default="0")
    id: Mapped[str] = mapped_column(ForeignKey("tasks.id"), primary_key=True)
    request_key: Mapped[str] = mapped_column(String, unique=True)
    request_hash: Mapped[str] = mapped_column(String)
    expires_at: Mapped[float] = mapped_column(Float)
    digest: Mapped[str | None] = mapped_column(String, nullable=True)


class PackPurgeEntry(Base):
    __tablename__ = "pack_purge_entries"
    name: Mapped[str] = mapped_column(String)
    path: Mapped[str] = mapped_column(Text)
    image_count: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    image_bytes: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    retained_entries: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    id: Mapped[str] = mapped_column(String, primary_key=True, default=uid)
    plan_id: Mapped[str] = mapped_column(ForeignKey("pack_purge_plans.id"), index=True)
    pack_id: Mapped[str] = mapped_column(ForeignKey("packs.id"), index=True)
    trash_id: Mapped[str] = mapped_column(ForeignKey("pack_trash_items.id"))
    source: Mapped[dict] = mapped_column(JSON)
    manifest: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    digest: Mapped[str | None] = mapped_column(String, nullable=True)
    error: Mapped[str | None] = mapped_column(String, nullable=True)
    __table_args__ = (UniqueConstraint("plan_id", "trash_id"),)


class PackPurgeExecution(Base):
    __tablename__ = "pack_purge_executions"
    id: Mapped[str] = mapped_column(ForeignKey("pack_file_operations.id"), primary_key=True)
    plan_id: Mapped[str] = mapped_column(ForeignKey("pack_purge_plans.id"), unique=True)


class PackPurgeStep(Base):
    __tablename__ = "pack_purge_steps"
    id: Mapped[str] = mapped_column(String, primary_key=True, default=uid)
    parent_id: Mapped[str] = mapped_column(ForeignKey("pack_file_steps.id"), index=True)
    kind: Mapped[str] = mapped_column(String)
    # Historical identity must survive scanner removal of a deleted page row.
    page_id: Mapped[str | None] = mapped_column(String, nullable=True)
    relative_path: Mapped[str] = mapped_column(Text)
    source_signature: Mapped[list] = mapped_column(JSON)
    expected_hash: Mapped[str | None] = mapped_column(String, nullable=True)
    expected_size: Mapped[int] = mapped_column(Integer, default=0)
    state: Mapped[dict] = mapped_column(JSON, default=dict)
    phase: Mapped[str] = mapped_column(String, default="prepared")
    outcome: Mapped[str] = mapped_column(String, default="pending")
    error: Mapped[str | None] = mapped_column(String, nullable=True)
    __table_args__ = (
        UniqueConstraint("parent_id", "kind", "relative_path"),
        CheckConstraint("kind IN ('image','directory')"),
    )

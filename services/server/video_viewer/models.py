import time
import uuid

from sqlalchemy import JSON, Boolean, Float, ForeignKey, Index, Integer, String, Text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


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

"""Versioned logical snapshots: management data only, never executable imports."""

import hashlib
import json
import math
import time
import uuid
from pathlib import Path

from sqlalchemy import JSON, Boolean, Float, Integer, String, create_engine, select
from sqlalchemy.exc import IntegrityError, StatementError

from .errors import LibraryError
from .models import Base, PlaybackRound, Root, Setting

FORMAT = "video-viewer-management"
VERSION = 1
SCHEMA = "0004"
CONTROL_PREFIX = "backup_"
SETTING_KEYS = {"active_round", "last_delete_operation"}
# v1 remains the exact video-only logical schema until LF7 adds v2.
LEGACY_TABLES = {
    "roots",
    "directories",
    "videos",
    "tasks",
    "playback_rounds",
    "round_entries",
    "tags",
    "video_tags",
    "request_records",
    "file_operations",
    "file_steps",
    "trash_items",
}
TABLES = [table for table in Base.metadata.sorted_tables if table.name in LEGACY_TABLES]


def backup_columns(table):
    excluded = {
        "roots": {"kind", "enabled"},
        "playback_rounds": {"membership", "source", "sort"},
        "round_entries": {"source_ordinal"},
    }
    return [column for column in table.c if column.name not in excluded.get(table.name, set())]


def require_legacy_backup(session):
    """Never report a successful v1 export/restore that would omit new data."""
    typed_root = session.scalar(
        select(Root.id).where((Root.kind != "video") | Root.enabled.is_(False)).limit(1)
    )
    new_data = any(
        session.scalar(select(table.c[next(iter(table.c.keys()))]).limit(1)) is not None
        for table in Base.metadata.sorted_tables
        if table.name not in LEGACY_TABLES | {"settings", "access_tokens", "observations"}
    )
    fixed_round = session.scalar(
        select(PlaybackRound.id).where(PlaybackRound.membership == "fixed").limit(1)
    )
    if typed_root or new_data or fixed_round:
        raise LibraryError("backup_upgrade_required", "当前管理数据需要媒体库备份 v2 支持", 409)


TABLE_MAP = {table.name: table for table in TABLES}


def canonical(value):
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False
    ).encode("utf-8")


def package(payload):
    document = {"format": FORMAT, "version": VERSION, "created_at": time.time(), "payload": payload}
    return {**document, "sha256": hashlib.sha256(canonical(document)).hexdigest()}


def snapshot(db, settings):
    # Keep one short, serialized logical read across tables; disk serialization
    # happens afterwards. Do not materialize ORM relationships or media bytes.
    with db.write_lock, db.read() as session:
        require_legacy_backup(session)
        tables = {}
        for table in TABLES:
            statement = select(*backup_columns(table))
            if table.name == "tasks":
                statement = statement.where(~table.c.kind.startswith(CONTROL_PREFIX))
            if table.name == "request_records":
                statement = statement.where(~table.c.id.startswith("backup."))
            rows = [dict(row) for row in session.execute(statement).mappings()]
            if table.name == "videos":
                for row in rows:
                    row["thumbnail"] = None
            tables[table.name] = rows
        preferences = {
            row.key: row.value
            for row in session.scalars(select(Setting).where(Setting.key.in_(SETTING_KEYS)))
        }
    return package(
        {
            "schema": SCHEMA,
            "mounts": [
                {"id": mount.id, "name": mount.name, "path": str(mount.path)}
                for mount in settings.mounts
            ],
            "settings": preferences,
            "tables": tables,
        }
    )


def invalid(message="备份格式或管理数据不完整"):
    raise LibraryError("invalid_backup", message, 422)


def plain_path(value):
    if not isinstance(value, str) or not value or len(value) > 4096 or "\x00" in value:
        invalid()
    path = Path(value)
    if not path.is_absolute() or ".." in path.parts or str(path) != value:
        invalid("备份含有不合法的路径")
    return path


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            invalid("备份含有重复字段")
        result[key] = value
    return result


def decode(raw):
    try:
        document = json.loads(
            raw, object_pairs_hook=unique_pairs, parse_constant=lambda _value: invalid()
        )
        if not isinstance(document, dict) or set(document) != {
            "format",
            "version",
            "created_at",
            "payload",
            "sha256",
        }:
            invalid()
        if (
            document["format"] != FORMAT
            or type(document["version"]) is not int
            or document["version"] != VERSION
        ):
            raise LibraryError("backup_version_unsupported", "备份类型或版本不兼容", 422)
        if type(document["created_at"]) not in (int, float) or not math.isfinite(
            document["created_at"]
        ):
            invalid()
        signed = {key: value for key, value in document.items() if key != "sha256"}
        if document["sha256"] != hashlib.sha256(canonical(signed)).hexdigest():
            raise LibraryError("backup_checksum_mismatch", "备份完整性校验失败", 422)
        validate_payload(document["payload"])
        return document
    except (ValueError, TypeError, KeyError, RecursionError, UnicodeError):
        invalid()


def validate_payload(payload):
    if not isinstance(payload, dict) or set(payload) != {"schema", "mounts", "settings", "tables"}:
        invalid()
    if payload["schema"] != SCHEMA:
        raise LibraryError("backup_version_unsupported", "备份数据库版本不兼容", 422)
    if not isinstance(payload["settings"], dict) or set(payload["settings"]) - SETTING_KEYS:
        invalid()
    if any(
        not isinstance(value, str) or len(value) > 128 for value in payload["settings"].values()
    ):
        invalid()
    mounts = payload["mounts"]
    if not isinstance(mounts, list) or len(mounts) > 256:
        invalid()
    mount_ids = set()
    for mount in mounts:
        if not isinstance(mount, dict) or set(mount) != {"id", "name", "path"}:
            invalid()
        if (
            not isinstance(mount["id"], str)
            or not mount["id"]
            or mount["id"] in mount_ids
            or len(mount["id"]) > 128
        ):
            invalid()
        mount_ids.add(mount["id"])
        if not isinstance(mount["name"], str) or len(mount["name"]) > 100:
            invalid()
        plain_path(mount["path"])
    tables = payload["tables"]
    if not isinstance(tables, dict) or set(tables) != set(TABLE_MAP):
        invalid()
    for name, table in TABLE_MAP.items():
        rows = tables[name]
        if not isinstance(rows, list) or len(rows) > 250_000:
            invalid("备份记录数量超出支持范围")
        for row in rows:
            if not isinstance(row, dict) or set(row) != {
                column.name for column in backup_columns(table)
            }:
                invalid()
            if name not in {"roots", "request_records", "video_tags", "round_entries"}:
                try:
                    if str(uuid.UUID(row["id"])) != row["id"]:
                        invalid()
                except (ValueError, TypeError, AttributeError):
                    invalid()
            for column in backup_columns(table):
                value = row[column.name]
                if value is None:
                    if not column.nullable:
                        invalid()
                    continue
                if isinstance(column.type, Boolean):
                    valid = type(value) is bool
                elif isinstance(column.type, Integer):
                    valid = type(value) is int and -(2**63) <= value < 2**63
                elif isinstance(column.type, Float):
                    valid = type(value) in (float, int) and math.isfinite(value)
                elif isinstance(column.type, JSON):
                    valid = isinstance(
                        value,
                        list
                        if column.name.endswith("identity") or column.name == "source_signature"
                        else dict,
                    )
                elif isinstance(column.type, String):
                    valid = isinstance(value, str) and "\x00" not in value and len(value) <= 8192
                else:
                    valid = False
                if not valid:
                    invalid()
            if name == "tasks" and row["kind"].startswith(CONTROL_PREFIX):
                invalid()
            if name == "request_records" and row["id"].startswith("backup."):
                invalid()
    validate_relations(tables)


def validate_relations(tables):
    # Foreign keys, primary keys and uniqueness are checked before any live
    # table can be replaced. SQL values remain bound to the known schema.
    engine = create_engine("sqlite://")
    try:
        with engine.begin() as connection:
            connection.exec_driver_sql("PRAGMA foreign_keys=ON")
            Base.metadata.create_all(connection)
            for table in TABLES:
                if tables[table.name]:
                    connection.execute(table.insert(), tables[table.name])
    except (IntegrityError, StatementError, OverflowError):
        invalid("备份关联或唯一约束不完整")
    finally:
        engine.dispose()
    roots = {root["id"]: root for root in tables["roots"]}
    for name in ("roots", "directories", "videos"):
        for row in tables[name]:
            plain_path(row["path"])
            if name != "roots":
                # Missing records may precede a root-selection change; their
                # old paths remain evidence, never candidates for file writes.
                plain_path(roots[row["root_id"]]["path"])
            if name == "videos":
                if row["status"] not in {
                    "available",
                    "missing",
                    "trash",
                    "deleted",
                    "discovered",
                    "superseded",
                }:
                    invalid()
                if (
                    row["size"] < 0
                    or row["duration"] <= 0
                    or row["width"] <= 0
                    or row["height"] <= 0
                ):
                    invalid()
                if any(
                    len(row[key]) != 64 or any(char not in "0123456789abcdef" for char in row[key])
                    for key in ("sha256", "quick_hash")
                ):
                    invalid()
                if row["thumbnail"] is not None:
                    invalid("备份不能包含缩略图缓存引用")
                if row["location_key"] not in (None, row["path"]):
                    invalid()
    active = set()
    for row in tables["trash_items"]:
        for key in ("root_path", "original_path", "trash_path"):
            plain_path(row[key])
        if row["status"] not in {"active", "restored", "purged"}:
            invalid()
        if row["status"] == "active":
            if row["video_id"] in active:
                invalid()
            active.add(row["video_id"])
    for row in tables["playback_rounds"]:
        scope = row["scope"]
        if row["order"] not in {"random", "sequential"} or row["cursor"] < 0 or row["revision"] < 0:
            invalid()
        if set(scope) - {"directory_id", "orientation", "duration", "file_type", "tag_ids"}:
            invalid()
        if scope.get("orientation") not in (None, "portrait", "landscape") or scope.get(
            "duration"
        ) not in (None, "short", "long"):
            invalid()
        if scope.get("directory_id") is not None and not isinstance(scope["directory_id"], str):
            invalid()
        if scope.get("file_type") is not None and not isinstance(scope["file_type"], str):
            invalid()
        if not isinstance(scope.get("tag_ids", []), list) or any(
            not isinstance(tag, str) for tag in scope.get("tag_ids", [])
        ):
            invalid()
    for row in tables["file_operations"]:
        if row["kind"] not in {"trash", "restore", "permanent", "undo"}:
            invalid()
        if set(row["round_snapshot"]) - {"id", "cursor", "finished"}:
            invalid()

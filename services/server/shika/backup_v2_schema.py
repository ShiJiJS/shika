"""Approved logical graph and typed preferences; excludes device/runtime secrets."""

import json
import math
import uuid
from pathlib import PurePosixPath

from sqlalchemy import JSON, Boolean, Float, Integer, String, select

from .backup_format import invalid, plain_path
from .models import Base, PackSession, PackSessionEntry, PlaybackRound, Setting
from .reading import DEFAULTS

SCHEMA = "0013"
TABLE_NAMES = frozenset(
    {
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
        "packs",
        "pack_pages",
        "pack_tag_definitions",
        "pack_tag_links",
        "pack_progress",
        "pack_preferences",
        "recent_entries",
        "pack_sessions",
        "pack_session_entries",
        "pack_file_operations",
        "pack_file_steps",
        "pack_trash_items",
        "pack_missing_cleanups",
        "pack_missing_members",
        "pack_restore_plans",
        "pack_restore_members",
        "pack_restore_batches",
        "pack_purge_plans",
        "pack_purge_entries",
        "pack_purge_executions",
        "pack_purge_steps",
    }
)
TABLES = tuple(t for t in Base.metadata.sorted_tables if t.name in TABLE_NAMES)
TABLE_MAP = {t.name: t for t in TABLES}
LIST_FIELDS = frozenset(
    {
        "directory_signature",
        "signature",
        "source_signature",
        "claimed_identity",
        "published_identity",
        "copy_identity",
    }
)
SETTING_KEYS = frozenset(
    {
        "active_round",
        "last_delete_operation",
        "active_pack_session",
        "active_pack_opened",
        "reader_defaults",
        "playback_defaults",
    }
)
POINTERS = {
    "active_round": ("playback_rounds", "id"),
    "last_delete_operation": ("file_operations", "id"),
    "active_pack_session": ("pack_sessions", "id"),
}


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def json_value(value, depth=0):
    if depth > 64:
        invalid("备份记录嵌套过深")
    if value is None or type(value) in (bool, int):
        return
    if isinstance(value, float) and math.isfinite(value):
        return
    if isinstance(value, str) and "\0" not in value:
        try:
            value.encode("utf-8")
        except UnicodeError:
            invalid()
        return
    if isinstance(value, list):
        for item in value:
            json_value(item, depth + 1)
        return
    if isinstance(value, dict) and all(isinstance(key, str) and "\0" not in key for key in value):
        for key in value:
            json_value(key, depth + 1)
        for item in value.values():
            json_value(item, depth + 1)
        return
    invalid()


def sanitized(table, row):
    result = dict(row)
    if table in ("videos", "pack_pages"):
        result["thumbnail"] = None
    if table in ("videos", "packs"):
        result.update(device="", inode="")
    if table == "videos":
        result.update(mtime_ns="", ctime_ns="")
    if table == "packs":
        result["directory_signature"] = []
    if table == "pack_pages":
        result["signature"] = []
    if table == "roots":
        result.update(available=False, error=None, last_scan=None)
    if "seen_scan" in result:
        result["seen_scan"] = None if TABLE_MAP[table].c.seen_scan.nullable else ""
    return result


def validate_row(name, row):
    table = TABLE_MAP.get(name)
    if table is None or not isinstance(row, dict) or set(row) != set(table.c.keys()):
        invalid("备份包含未知表或不完整的记录字段")
    for column in table.c:
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
            valid = finite(value)
        elif isinstance(column.type, JSON):
            valid = isinstance(value, list if column.name in LIST_FIELDS else dict)
            json_value(value)
        elif isinstance(column.type, String):
            valid = isinstance(value, str) and "\0" not in value and len(value) <= 8192
        else:
            valid = False
        if not valid:
            invalid()
        if column.name in {"path", "root_path", "original_path", "trash_path"} and not (
            name == "file_steps" and value == ""
        ):
            plain_path(value)
        if column.name == "relative_path":
            path = PurePosixPath(value)
            if not value or path.is_absolute() or ".." in path.parts or str(path) != value:
                invalid("备份含有不合法的相对路径")
    if "id" in row and name not in ("roots", "request_records"):
        try:
            if str(uuid.UUID(row["id"])) != row["id"]:
                invalid()
        except (ValueError, AttributeError, TypeError):
            invalid()
    for key in (
        "generation",
        "content_version",
        "page_count",
        "revision",
        "cursor",
        "ordinal",
        "candidate_count",
        "expected_size",
        "image_count",
        "image_bytes",
        "retained_entries",
        "purged_pages",
    ):
        if key in row and row[key] < 0:
            invalid()
    if name in ("videos", "packs") and row["status"] not in (
        "available",
        "missing",
        "trash",
        "deleted",
        "superseded",
    ):
        invalid("备份不能包含未发布的扫描暂存内容")
    if name == "videos" and (
        row["size"] < 0 or row["duration"] <= 0 or row["width"] <= 0 or row["height"] <= 0
    ):
        invalid()
    if name == "pack_pages" and (
        row["size"] < 0
        or row["width"] < 0
        or row["height"] < 0
        or not row["error"]
        and (row["width"] == 0 or row["height"] == 0 or row["sha256"] is None)
    ):
        invalid()
    if name in ("videos", "pack_pages"):
        for key in ("sha256", "quick_hash"):
            value = row.get(key)
            if value is not None and (
                len(value) != 64 or any(c not in "0123456789abcdef" for c in value)
            ):
                invalid()
    if sanitized(name, row) != row:
        invalid("备份不能包含缩略图或扫描身份缓存")


def validate_settings(values):
    if not isinstance(values, dict) or set(values) != SETTING_KEYS:
        invalid("备份管理设置不完整")
    for key in POINTERS:
        if values[key] is not None and (
            not isinstance(values[key], str) or not 1 <= len(values[key]) <= 128
        ):
            invalid()
    for key, fields in [
        ("playback_defaults", {"order", "revision"}),
        ("reader_defaults", {"mode", "direction", "gap", "fit", "revision"}),
    ]:
        item = values[key]
        if not isinstance(item, dict) or set(item) != fields:
            invalid()
        if type(item["revision"]) is not int or not 0 <= item["revision"] < 2**63:
            invalid()
    if values["playback_defaults"]["order"] not in ("random", "sequential"):
        invalid()
    reader = values["reader_defaults"]
    if (
        reader["mode"] not in ("horizontal", "vertical")
        or reader["direction"] not in ("ltr", "rtl")
        or type(reader["gap"]) is not bool
        or reader["fit"] not in ("contain", "width")
    ):
        invalid()
    owner = values["active_pack_opened"]
    if owner is not None and (
        not isinstance(owner, dict)
        or set(owner) != {"session_id", "pack_id", "revision"}
        or not all(
            isinstance(owner[k], str) and 1 <= len(owner[k]) <= 128
            for k in ("session_id", "pack_id")
        )
        or type(owner["revision"]) is not int
        or not 0 <= owner["revision"] < 2**63
    ):
        invalid()


def settings_from(connection):
    saved = dict(
        connection.execute(
            select(Setting.key, Setting.value).where(Setting.key.in_(SETTING_KEYS))
        ).all()
    )
    result = {key: saved.get(key) or None for key in POINTERS}
    try:
        result["active_pack_opened"] = (
            json.loads(saved["active_pack_opened"]) if saved.get("active_pack_opened") else None
        )
        active = connection.scalar(
            select(PlaybackRound.order).where(PlaybackRound.id == result["active_round"])
        )
        result["playback_defaults"] = (
            json.loads(saved["playback_defaults"])
            if "playback_defaults" in saved
            else {"order": active or "random", "revision": 0}
        )
        result["reader_defaults"] = (
            json.loads(saved["reader_defaults"])
            if "reader_defaults" in saved
            else {**DEFAULTS, "revision": 0}
        )
    except (ValueError, TypeError):
        invalid("当前管理设置无法解析")
    validate_settings(result)
    return result


def validate_graph(connection, preferences):
    if connection.exec_driver_sql("PRAGMA foreign_key_check").fetchone() is not None:
        invalid("备份关联不完整")
    if connection.exec_driver_sql("PRAGMA quick_check").scalar() != "ok":
        invalid("备份暂存数据校验失败")
    for key, (name, column) in POINTERS.items():
        value = preferences[key]
        if (
            value is not None
            and connection.scalar(
                select(TABLE_MAP[name].c[column]).where(TABLE_MAP[name].c[column] == value)
            )
            is None
        ):
            invalid("备份活动范围或撤销指针没有对应记录")
    owner = preferences["active_pack_opened"]
    if owner:
        revision = connection.scalar(
            select(PackSession.revision).where(PackSession.id == owner["session_id"])
        )
        found = connection.scalar(
            select(PackSessionEntry.pack_id).where(
                PackSessionEntry.session_id == owner["session_id"],
                PackSessionEntry.pack_id == owner["pack_id"],
            )
        )
        if revision is None or found is None or owner["revision"] > revision:
            invalid("备份已读图包归属不完整")


def mounts_from(settings):
    return [
        {"id": mount.id, "name": mount.name, "path": str(mount.path)} for mount in settings.mounts
    ]


def validate_mounts(mounts):
    if not isinstance(mounts, list) or len(mounts) > 256:
        invalid()
    ids = set()
    for item in mounts:
        if (
            not isinstance(item, dict)
            or set(item) != {"id", "name", "path"}
            or not isinstance(item["id"], str)
            or not 1 <= len(item["id"]) <= 128
            or item["id"] in ids
            or not isinstance(item["name"], str)
            or len(item["name"]) > 100
        ):
            invalid()
        ids.add(item["id"])
        plain_path(item["path"])

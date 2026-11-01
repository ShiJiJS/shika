"""Map restored records to current physical truth, without moving any media."""

import copy
import os
from collections import defaultdict
from pathlib import Path
from types import SimpleNamespace

from .errors import LibraryError
from .file_transfer import FileTransfer
from .models import uid
from .paths import beneath, excluded, open_directory, validate_path


def mappings_for(payload, mapping, settings):
    roots = payload["tables"]["roots"]
    if set(mapping) != {root["id"] for root in roots}:
        raise LibraryError(
            "invalid_mapping", "请为备份中的每个媒体目录明确指定路径或保持未映射", 422
        )
    result = {}
    for root_id, value in mapping.items():
        if value is None:
            result[root_id] = None
            continue
        path, mount = validate_path(value, settings.mounts)
        if excluded(path, settings.data_dir) or (
            settings.trash_dir and beneath(path, settings.trash_dir)
        ):
            raise LibraryError("invalid_mapping", "媒体目录不能映射到管理数据或回收位置", 422)
        if any(item and item[0] == str(path) for item in result.values()):
            raise LibraryError("invalid_mapping", "多个媒体目录不能映射到同一路径", 422)
        result[root_id] = (str(path), mount.id)
    return result


def recommended_mapping(payload, settings):
    old_mounts = {mount["id"]: Path(mount["path"]) for mount in payload["mounts"]}
    suggestions = {}
    for root in payload["tables"]["roots"]:
        proposed = None
        try:
            path, _ = validate_path(root["path"], settings.mounts)
            proposed = str(path)
        except (LibraryError, OSError):
            old_parent = old_mounts.get(root["mount_id"])
            target = next(
                (mount for mount in settings.mounts if mount.id == root["mount_id"]), None
            )
            if old_parent and target and beneath(Path(root["path"]), old_parent):
                proposed = str(target.path / Path(root["path"]).relative_to(old_parent))
        suggestions[root["id"]] = proposed
    return suggestions


def mapped_path(value, old_base, new_base):
    if new_base is None or not beneath(Path(value), Path(old_base)):
        return None
    return str(Path(new_base) / Path(value).relative_to(old_base))


def reconcile(payload, current, mapping, settings, stop):
    tables = copy.deepcopy(payload["tables"])
    source_roots = {root["id"]: root for root in payload["tables"]["roots"]}
    roots = {root["id"]: root for root in tables["roots"]}
    current_videos = {video["id"]: video for video in current["tables"]["videos"]}
    current_trash = {
        item["video_id"]: item
        for item in current["tables"]["trash_items"]
        if item["status"] == "active"
    }
    trash = {item["id"]: item for item in tables["trash_items"]}
    trash_by_video = defaultdict(list)
    videos_by_id = {video["id"]: video for video in tables["videos"]}
    for item in trash.values():
        trash_by_video[item["video_id"]].append(item)
    validator = FileTransfer(stop, None, None)

    def check_stop():
        if stop.is_set():
            raise InterruptedError("service_stopping")

    def verified(path, video, *, is_trash=False, item=None):
        if not path:
            return None
        check_stop()
        try:
            if is_trash:
                base = settings.trash_dir or Path(item["root_path"]) / ".video-viewer-trash"
                logical = item["trash_path"] == item["original_path"]
                if logical:
                    validate_path(path, settings.mounts)
                    if not beneath(Path(path), Path(item["root_path"])):
                        return None
                elif Path(path) != base / item["id"] / Path(item["original_path"]).name:
                    return None
                validate_path(item["root_path"], settings.mounts)
            else:
                validate_path(path, settings.mounts)
            return validator.verified(
                path, SimpleNamespace(expected_hash=video["sha256"], expected_size=video["size"])
            )
        except (OSError, LibraryError):
            return None

    for root in roots.values():
        target = mapping[root["id"]]
        root["available"], root["last_scan"] = False, None
        if not target:
            root["mount_id"], root["error"] = "", "root_unmapped"
            continue
        root["path"], root["mount_id"] = target
        try:
            with open_directory(Path(root["path"])) as fd:
                os.listdir(fd)
            root["available"], root["error"] = True, None
        except OSError:
            root["error"] = "root_unavailable"
    directories = []
    for directory in tables["directories"]:
        root = roots[directory["root_id"]]
        target = mapped_path(
            directory["path"],
            source_roots[root["id"]]["path"],
            root["path"] if mapping[root["id"]] else None,
        )
        if target:
            directory["path"], directory["seen_scan"] = target, None
            if target != root["path"]:
                try:
                    with open_directory(Path(target)):
                        pass
                except OSError:
                    continue
        elif mapping[root["id"]]:
            continue
        directories.append(directory)
    for root in roots.values():
        if not any(directory["path"] == root["path"] for directory in directories):
            directories.append(
                {
                    "id": uid(),
                    "root_id": root["id"],
                    "path": root["path"],
                    "name": Path(root["path"]).name,
                    "seen_scan": None,
                }
            )
    tables["directories"] = directories
    for item in trash.values():
        video = videos_by_id[item["video_id"]]
        root, old_root = roots[video["root_id"]], source_roots[video["root_id"]]
        if mapping[root["id"]]:
            logical = item["trash_path"] == item["original_path"]
            original = mapped_path(item["original_path"], old_root["path"], root["path"])
            item["original_path"] = original or item["original_path"]
            item["root_path"] = root["path"]
            item["trash_path"] = (
                item["original_path"]
                if logical
                else str(
                    (settings.trash_dir or Path(root["path"]) / ".video-viewer-trash")
                    / item["id"]
                    / Path(item["original_path"]).name
                )
            )
    for video in tables["videos"]:
        check_stop()
        root, old_root = roots[video["root_id"]], source_roots[video["root_id"]]
        original = mapped_path(
            video["path"], old_root["path"], root["path"] if mapping[root["id"]] else None
        )
        video["path"] = original or video["path"]
        video["location_key"], video["thumbnail"] = None, None
        video["generation"] += 1
        if video["status"] in ("deleted", "superseded"):
            continue
        video["status"], video["error"] = "missing", "source_missing"
        if not mapping[root["id"]]:
            video["error"] = "root_unmapped"
            continue
        known = current_videos.get(video["id"])
        # Logical trash is still physically at the original path. Prefer an
        # active mark over that path's existence, otherwise restore would
        # silently resurrect every marked item as available.
        marked = current_trash.get(video["id"])
        if marked and not any(
            mapping[owner["id"]] and beneath(Path(marked["original_path"]), Path(owner["path"]))
            for owner in roots.values()
        ):
            marked = None
        if marked is None and (not known or known["status"] != "available"):
            marked = next(
                (item for item in trash_by_video[video["id"]] if item["status"] == "active"), None
            )
        if marked and marked["trash_path"] == marked["original_path"]:
            result = verified(marked["trash_path"], video, is_trash=True, item=marked)
            for previous in trash_by_video[video["id"]]:
                if previous["id"] != marked["id"] and previous["status"] == "active":
                    previous["status"] = "restored"
            trash[marked["id"]] = copy.deepcopy(marked)
            video["status"], video["path"], video["location_key"] = (
                "trash",
                marked["original_path"],
                marked["original_path"],
            )
            video["error"] = None if result else "trash_missing"
            if result:
                (
                    video["device"],
                    video["inode"],
                    video["size"],
                    video["mtime_ns"],
                    video["ctime_ns"],
                ) = result
            continue
        candidates = []
        if known and known["sha256"] == video["sha256"] and known["status"] == "available":
            owners = [
                item
                for item in roots.values()
                if mapping[item["id"]] and beneath(Path(known["path"]), Path(item["path"]))
            ]
            if owners:
                candidates.append(
                    (known["path"], min(owners, key=lambda item: len(item["path"]))["id"])
                )
        if original:
            candidates.append((original, root["id"]))
        result = None
        for path, owner in candidates:
            result = verified(path, video)
            if result:
                video["status"], video["path"], video["location_key"], video["root_id"] = (
                    "available",
                    path,
                    path,
                    owner,
                )
                video["name"] = Path(path).name
                for item in trash_by_video[video["id"]]:
                    if item["status"] == "active":
                        item["status"] = "restored"
                break
        if not result:
            existing = current_trash.get(video["id"])
            possible = []
            if (
                existing
                and existing["sha256"] == video["sha256"]
                and any(
                    mapping[item["id"]] and beneath(Path(existing["root_path"]), Path(item["path"]))
                    for item in roots.values()
                )
            ):
                possible.append((existing, True))
            possible.extend(
                (item, False) for item in trash_by_video[video["id"]] if item["status"] == "active"
            )
            for item, from_current in possible:
                result = verified(item["trash_path"], video, is_trash=True, item=item)
                if result:
                    for previous in trash_by_video[video["id"]]:
                        if previous["id"] != item["id"] and previous["status"] == "active":
                            previous["status"] = "restored"
                    if item["id"] not in trash:
                        trash[item["id"]] = copy.deepcopy(item)
                        trash_by_video[video["id"]].append(trash[item["id"]])
                    elif from_current:
                        trash[item["id"]].update(copy.deepcopy(item))
                    video["status"] = "trash"
                    break
        if result:
            video["device"], video["inode"], video["size"], video["mtime_ns"], video["ctime_ns"] = (
                result
            )
            video["error"] = None
        elif any(item["status"] == "active" for item in trash_by_video[video["id"]]):
            video["error"] = "trash_missing"
    tables["trash_items"] = list(trash.values())
    # Retain command receipts, including commands issued after the backup, so
    # delayed retries cannot execute an old delete again. Current labels and
    # unrelated videos are not merged into the restored collection.
    video_ids = {video["id"] for video in tables["videos"]}
    known_operations = {row["id"] for row in current["tables"]["file_operations"]}
    for name in ("tasks", "file_operations", "file_steps"):
        merged = {row["id"]: row for row in tables[name]}
        for row in current["tables"][name]:
            operation_id = row["operation_id"] if name == "file_steps" else row["id"]
            if operation_id in known_operations:
                retained = copy.deepcopy(row)
                if name == "file_steps" and retained["video_id"] not in video_ids:
                    retained["video_id"] = None
                merged[row["id"]] = retained
        tables[name] = list(merged.values())
    receipts = {row["id"]: row for row in tables["request_records"]}
    receipts.update({row["id"]: copy.deepcopy(row) for row in current["tables"]["request_records"]})
    tables["request_records"] = list(receipts.values())
    for operation in tables["file_operations"]:
        operation["historical"] = True
    for task in tables["tasks"]:
        if task["status"] in ("queued", "running"):
            task["status"], task["phase"], task["error"] = (
                "interrupted",
                "historical",
                "restored_history",
            )
    return tables

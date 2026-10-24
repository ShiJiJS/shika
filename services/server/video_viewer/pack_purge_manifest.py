"""Read-only, descriptor-bound evidence for a later confirmed image purge."""

import hashlib
import json
import os
import stat
from pathlib import Path

from .directory_identity import directory_stamp
from .errors import LibraryError
from .images import IMAGE_EXTENSIONS
from .media_roots import owner_for_path
from .paths import beneath, excluded, open_directory, signature, validate_path


def digest_json(value):
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()
    ).hexdigest()


class PurgeManifest:
    # Bound each pack's tree before allocating its sorted name inventory.
    max_entries = 200_000
    max_depth = 128

    def __init__(self, settings, check_stop, checkpoint):
        self.settings, self.check_stop, self.checkpoint = settings, check_stop, checkpoint

    def hash_file(self, parent, name, expected):
        descriptor = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
        try:
            before = signature(os.fstat(descriptor))
            if not stat.S_ISREG(os.fstat(descriptor).st_mode) or before != expected:
                raise LibraryError("image_changed", "图片身份或签名已变化，请重新核对")
            digest = hashlib.sha256()
            while chunk := os.read(descriptor, 1024 * 1024):
                self.check_stop()
                digest.update(chunk)
            if signature(os.fstat(descriptor)) != before:
                raise LibraryError("image_changed", "图片仍在变化，请重新核对")
            return digest.hexdigest()
        finally:
            os.close(descriptor)

    @staticmethod
    def pack_identity(source, observed):
        indexed = source["directory_signature"]
        return observed[:2] == source["directory_identity"] and (
            not indexed or indexed[-1] is None or observed[-1] == indexed[-1]
        )

    def inspect(self, source, roots, *, fingerprint):
        path, root_path = Path(source["path"]), Path(source["root_path"])
        validate_path(str(root_path), self.settings.mounts)
        validate_path(str(path), self.settings.mounts)
        if path == root_path or not beneath(path, root_path):
            raise LibraryError("pack_outside_root", "图包不在已确认目录内")
        indexed = {page["relative_path"]: page for page in source["pages"]}
        if len(indexed) != len(source["pages"]) or not indexed:
            raise LibraryError("invalid_page_manifest", "图包图片清单不完整")
        for relative, page in indexed.items():
            if (
                not relative
                or Path(relative).is_absolute()
                or ".." in Path(relative).parts
                or str(path / relative) != page["path"]
                or Path(relative).suffix.lower() not in IMAGE_EXTENSIONS
            ):
                raise LibraryError("image_outside_pack", "图片不在已确认图包范围内")
        tree, files = {}, {}

        def walk(fd, current, depth):
            self.check_stop()
            if depth > self.max_depth:
                raise LibraryError("manifest_too_large", "图包目录层级过深，请缩小范围")
            before = directory_stamp(fd)
            relative = str(current.relative_to(path))
            tree[relative] = {"kind": "directory", "signature": before}
            names = []
            with os.scandir(fd) as scan:
                for item in scan:
                    self.check_stop()
                    if len(tree) + len(names) >= self.max_entries:
                        raise LibraryError("manifest_too_large", "本次清单过大，请减少所选图包")
                    names.append(item.name)
            names.sort()
            for name in names:
                self.check_stop()
                if len(tree) >= self.max_entries:
                    raise LibraryError("manifest_too_large", "本次清单过大，请减少所选图包")
                full = current / name
                relative = str(full.relative_to(path))
                info = os.stat(name, dir_fd=fd, follow_symlinks=False)
                owner = owner_for_path(full, roots, "pack")
                protected = (
                    excluded(full, self.settings.data_dir)
                    or (self.settings.trash_dir and beneath(full, self.settings.trash_dir))
                    or not owner
                    or owner.id != source["root_id"]
                )
                if protected:
                    tree[relative] = {"kind": "preserve_scope", "signature": signature(info)}
                    continue
                if stat.S_ISDIR(info.st_mode):
                    child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                    try:
                        if signature(os.fstat(child)) != signature(info):
                            raise LibraryError("pack_changed", "图包目录在核对期间变化")
                        walk(child, full, depth + 1)
                    finally:
                        os.close(child)
                elif stat.S_ISREG(info.st_mode):
                    observed = signature(info)
                    tree[relative] = {"kind": "file", "signature": observed}
                    if full.suffix.lower() not in IMAGE_EXTENSIONS:
                        continue
                    page = indexed.get(relative)
                    if not page:
                        raise LibraryError(
                            "unindexed_image", "目录出现未确认图片，请先重新同步核对"
                        )
                    if observed != page["signature"] or info.st_size != page["size"]:
                        raise LibraryError("image_changed", "已索引图片发生变化，请重新同步核对")
                    digest = self.hash_file(fd, name, observed) if fingerprint else None
                    if fingerprint and page["sha256"] and digest != page["sha256"]:
                        raise LibraryError("image_changed", "图片内容与已索引版本不一致")
                    files[relative] = {**page, "sha256": digest}
                    if fingerprint:
                        self.checkpoint("purge_page_fingerprinted", page["id"])
                else:
                    raise LibraryError(
                        "ambiguous_pack_entry", "图包含链接或特殊文件，请先处理后重试"
                    )
            if directory_stamp(fd) != before:
                raise LibraryError("pack_changed", "图包目录在核对期间变化，请重试")

        with open_directory(root_path) as root_fd, open_directory(path) as pack_fd:
            root_identity = directory_stamp(root_fd)[:2]
            stamp = directory_stamp(pack_fd)
            if not self.pack_identity(source, stamp):
                raise LibraryError("pack_changed", "图包目录身份已变化，请重新同步核对")
            walk(pack_fd, path, 0)
        if set(files) != set(indexed):
            raise LibraryError("indexed_image_missing", "已索引图片缺失或不在当前授权范围内")
        # Opening the lexical paths again rejects a renamed/replaced root or pack.
        with open_directory(root_path) as root_fd, open_directory(path) as pack_fd:
            if directory_stamp(root_fd)[:2] != root_identity or directory_stamp(pack_fd) != stamp:
                raise LibraryError("pack_changed", "图包路径在核对期间变化")
        return {
            "root_identity": root_identity,
            "directory_stamp": stamp,
            "tree": tree,
            "files": [files[key] for key in sorted(files)],
        }

    def build(self, source, roots):
        result = self.inspect(source, roots, fingerprint=True)
        self.checkpoint("purge_pack_fingerprinted", source["pack_id"])
        after = self.inspect(source, roots, fingerprint=False)
        if any(result[key] != after[key] for key in ("root_identity", "directory_stamp", "tree")):
            raise LibraryError("pack_changed", "图包在图片核对后变化，请重试")
        image_names = {p["relative_path"] for p in result["files"]}
        retained = sum(
            value["kind"] in ("file", "preserve_scope")
            for name, value in result["tree"].items()
            if name not in image_names
        )
        return {
            "schema": 1,
            "source": source,
            **result,
            "image_count": len(result["files"]),
            "image_bytes": sum(p["size"] for p in result["files"]),
            "retained_entries": retained,
        }

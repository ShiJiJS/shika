"""Image claims and non-recursive empty-directory cleanup under a frozen tree."""

import os
from pathlib import Path
from types import SimpleNamespace

from .directory_identity import directory_stamp
from .errors import LibraryError
from .file_transfer import FileTransfer, file_stat, rename_new
from .paths import open_directory, signature, validate_path


class ImagePurgeTransfer(FileTransfer):
    def claim(self, step, **_):
        # Images are hashed again after claim, even when original stat fields
        # match. Do not inherit the large-video unchanged-purge optimization.
        return super().claim(step, unchanged_purge=False)


def same_directory(observed, expected):
    return observed[:2] == expected[:2] and (
        len(expected) < 6 or expected[-1] is None or observed[-1] == expected[-1]
    )


class PurgeTree:
    def __init__(self, owner, parent, manifest, rows):
        self.owner, self.parent, self.manifest, self.rows = owner, parent, manifest, rows
        self.path = Path(parent.original_path)
        self.stamps = {}
        self.by_id = {row.id: row for row in rows}
        self.by_relative = {row.relative_path: row for row in rows if row.kind == "image"}
        self.directories = {row.relative_path: row for row in rows if row.kind == "directory"}
        self.children = {}
        for relative in manifest["tree"]:
            if relative != ".":
                self.children.setdefault(str(Path(relative).parent), set()).add(Path(relative).name)

    def source(self, row):
        return self.path / row.relative_path

    def staging(self, row):
        for identity in (self.parent.operation_id, self.parent.id, row.id):
            if Path(identity).name != identity or identity in (".", ".."):
                raise LibraryError("invalid_purge_journal", "删除日志的路径身份不合法")
        return (
            Path(self.parent.root_path)
            / ".video-viewer-tmp"
            / "pack-purge"
            / self.parent.operation_id
            / self.parent.id
            / row.kind
            / row.id
        )

    def basic(self, *, pack=True):
        self.owner.check_database(self.parent, self.manifest, self.rows)
        validate_path(str(self.path), self.owner.settings.mounts)
        validate_path(self.parent.root_path, self.owner.settings.mounts)
        with open_directory(Path(self.parent.root_path)) as fd:
            if directory_stamp(fd)[:2] != self.manifest["root_identity"]:
                raise LibraryError("root_changed", "接入根目录身份已变化")
        if pack:
            with open_directory(self.path) as fd:
                if not same_directory(directory_stamp(fd), self.manifest["directory_stamp"]):
                    raise LibraryError("pack_changed", "图包目录身份已变化")

    def removed(self, row):
        if row.outcome == "succeeded":
            return True
        if row.phase in ("prepared", "rolled_back", "retained"):
            return False
        if file_stat(self.staging(row)):
            return True
        return row.phase in ("purging", "removing") and not file_stat(self.source(row))

    def revalidate_returned_image(self, row, path, expected, observed):
        # A journaled rollback can be followed by a ctime-only attribute update.
        # Permit that narrow case only after hashing the same returned inode;
        # mtime/size changes and replacements still invalidate the frozen tree.
        if (
            not row
            or row.phase != "rolled_back"
            or not row.state.get("source_signature")
            or observed is None
            or observed[:4] != expected[:4]
        ):
            return False
        transfer = ImagePurgeTransfer(self.owner.stop, self.owner.mark, self.validate_transfer)
        verified = transfer.verified(path, row, expected[:2])
        if verified[:4] != expected[:4]:
            raise LibraryError("manifest_changed", "文件在确认后变化，请重新核对")
        # Reuse the rollback checkpoint so the page and journal signatures stay
        # in sync. The following claim verifies identity and bytes again.
        self.owner.mark(row.id, "rolled_back", source_signature=verified)
        return True

    def check(self, *, full=False):
        self.basic(pack=False)
        removed = {row.relative_path for row in self.rows if self.removed(row)}
        if "." in removed:
            if file_stat(self.path):
                raise LibraryError("pack_changed", "原图包位置出现新目录，未删除新内容")
            return
        self.basic()
        own_changes = any(row.phase != "prepared" for row in self.rows)
        for relative, expected in self.manifest["tree"].items():
            self.owner.check_stop()
            if relative in removed:
                continue
            if any(str(parent) in removed for parent in Path(relative).parents):
                continue
            full_path = self.path / relative
            if expected["kind"] == "directory":
                with open_directory(full_path) as fd:
                    stamp = directory_stamp(fd)
                    if not same_directory(stamp, expected["signature"]):
                        raise LibraryError("pack_changed", "图包子目录被替换，已停止")
                    if full and not own_changes and stamp != expected["signature"]:
                        raise LibraryError("manifest_changed", "目录在确认后变化，请重新核对")
                    if full or self.stamps.get(relative) != stamp:
                        names = set(os.listdir(fd))
                        wanted = {
                            name
                            for name in self.children.get(relative, set())
                            if str(Path(relative) / name) not in removed
                        }
                        if names != wanted:
                            raise LibraryError(
                                "manifest_changed", "图包出现新增或缺失文件，请重新核对"
                            )
                        self.stamps[relative] = stamp
            else:
                row = self.by_relative.get(relative)
                if not full and row:
                    continue  # The current image is checked and hashed after claim.
                info = file_stat(full_path)
                current = signature(info) if info else None
                wanted = (
                    row.state.get("source_signature", row.source_signature)
                    if row
                    else expected["signature"]
                )
                if current != wanted and not self.revalidate_returned_image(
                    row, full_path, wanted, current
                ):
                    raise LibraryError("manifest_changed", "文件在确认后变化，请重新核对")

    def transfer_step(self, row):
        return SimpleNamespace(
            id=row.id,
            source=str(self.source(row)),
            staging=str(self.staging(row)),
            destination="",
            copy_path="",
            phase=row.phase,
            source_signature=row.state.get("source_signature", row.source_signature),
            expected_hash=row.expected_hash,
            expected_size=row.expected_size,
            claimed_identity=row.state.get("claimed_identity", []),
            published_identity=[],
            copy_identity=[],
        )

    def validate_transfer(self, step, _):
        self.basic()
        row = self.by_id[step.id]
        for parent in Path(row.relative_path).parents:
            expected = self.manifest["tree"].get(str(parent))
            if not expected or expected["kind"] != "directory":
                raise LibraryError("invalid_purge_journal", "图片父目录不在确认清单内")
            with open_directory(self.path / parent) as fd:
                if not same_directory(directory_stamp(fd), expected["signature"]):
                    raise LibraryError("pack_changed", "图片父目录被替换")
        if not self.owner.rolling_back and not file_stat(step.staging):
            info = file_stat(step.source)
            if row.phase not in ("purging",) and (
                not info or signature(info) != step.source_signature
            ):
                raise LibraryError("manifest_changed", "图片在确认后变化，请重新核对")

    def directory(self, row):
        """Claim an empty directory, then rmdir only the claimed identity."""
        self.basic(pack=False)
        source, stage = self.source(row), self.staging(row)
        if row.phase == "removing" and not file_stat(stage) and not file_stat(source):
            self.owner.commit_directory(row, "succeeded")
            return
        staged = file_stat(stage)
        if not staged:
            self.check()
            with open_directory(source) as fd:
                stamp = directory_stamp(fd)
                if not same_directory(stamp, row.source_signature):
                    raise LibraryError("pack_changed", "空目录身份已变化")
                if os.listdir(fd):
                    self.owner.commit_directory(row, "retained")
                    return
            self.owner.mark(row.id, "directory_claiming")
            rename_new(source, stage)
            with open_directory(stage) as fd:
                claimed_stamp = directory_stamp(fd)
            self.owner.mark(row.id, "directory_claimed", claimed_stamp=claimed_stamp)
        with open_directory(stage) as fd:
            stamp = directory_stamp(fd)
            if not same_directory(stamp, row.source_signature) or os.listdir(fd):
                self.restore_directory(row)
                raise LibraryError("manifest_changed", "目录在清理期间变化，内容已保留")
        self.owner.mark(row.id, "removing")
        # A nonempty replacement can never be recursively removed.
        with open_directory(stage.parent) as parent:
            before = os.stat(stage.name, dir_fd=parent, follow_symlinks=False)
            if [str(before.st_dev), str(before.st_ino)] != row.source_signature[:2]:
                raise LibraryError("pack_changed", "暂存目录身份已变化，未清除")
            os.rmdir(stage.name, dir_fd=parent)
            os.fsync(parent)
        self.owner.checkpoint("purge_directory_removed", row.id)
        self.owner.commit_directory(row, "succeeded")

    def restore_directory(self, row):
        source, stage = self.source(row), self.staging(row)
        if not file_stat(stage):
            return
        if file_stat(source):
            raise LibraryError("destination_conflict", "原目录位置已被占用，暂存内容保留")
        with open_directory(stage) as fd:
            expected = row.state.get("claimed_stamp", row.source_signature)
            if not same_directory(directory_stamp(fd), expected):
                raise LibraryError("pack_changed", "暂存目录身份不明，内容保留待核对")
        rename_new(stage, source)
        self.owner.mark(row.id, "rolled_back")

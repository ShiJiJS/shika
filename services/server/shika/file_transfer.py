"""Descriptor-based no-overwrite transfers with durable caller checkpoints."""

import ctypes
import errno
import hashlib
import os
from pathlib import Path

from .errors import LibraryError
from .paths import make_directory, open_directory, open_regular, signature

_libc = ctypes.CDLL(None, use_errno=True)
_rename = _libc.renameat2
_rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
_rename.restype = ctypes.c_int


def identity(value):
    return list(value[:2])


def file_stat(path):
    try:
        with open_directory(Path(path).parent) as parent:
            return os.stat(Path(path).name, dir_fd=parent, follow_symlinks=False)
    except FileNotFoundError:
        return None


def rename_new(source, destination):
    source, destination = Path(source), Path(destination)
    with open_directory(source.parent) as origin, make_directory(destination.parent) as target:
        if _rename(origin, os.fsencode(source.name), target, os.fsencode(destination.name), 1):
            code = ctypes.get_errno()
            if code in (errno.ENOSYS, errno.EINVAL, errno.EOPNOTSUPP):
                raise LibraryError("filesystem_unsupported", "该文件系统不支持安全的不覆盖移动")
            raise OSError(code, os.strerror(code))
        os.fsync(origin)
        os.fsync(target)


def unlink_owned(path, expected):
    path = Path(path)
    with open_directory(path.parent) as parent:
        current = signature(os.stat(path.name, dir_fd=parent, follow_symlinks=False))
        if current != list(expected):
            raise LibraryError("source_changed", "操作中的文件已变化，未清除该文件")
        os.unlink(path.name, dir_fd=parent)
        os.fsync(parent)


class FileTransfer:
    def __init__(self, stop, checkpoint, validate):
        self.stop, self.checkpoint, self.validate = stop, checkpoint, validate

    def digest(self, fd):
        before = signature(os.fstat(fd))
        os.lseek(fd, 0, os.SEEK_SET)
        digest = hashlib.sha256()
        while chunk := os.read(fd, 1024 * 1024):
            if self.stop.is_set():
                raise InterruptedError("service_stopping")
            digest.update(chunk)
        if signature(os.fstat(fd)) != before:
            raise LibraryError("source_changed", "文件仍在变化，操作已停止")
        return digest.hexdigest(), before

    def verified(self, path, step, expected_identity=None):
        with open_regular(Path(path)) as fd:
            current = signature(os.fstat(fd))
            if current[2] != step.expected_size or (
                expected_identity and identity(current) != list(expected_identity)
            ):
                raise LibraryError("source_replaced", "文件身份已变化，未执行清除")
            digest, current = self.digest(fd)
            if digest != step.expected_hash:
                raise LibraryError("source_changed", "文件内容已变化，未执行清除")
            return current

    def mark(self, step, phase, **values):
        self.checkpoint(step.id, phase, **values)
        step.phase = phase
        for key, value in values.items():
            setattr(step, key, value)
        if self.stop.is_set():
            raise InterruptedError("service_stopping")

    def destination_owned(self, step):
        if not step.destination or not step.published_identity or not file_stat(step.destination):
            return False
        try:
            self.verified(step.destination, step, step.published_identity)
            return True
        except (OSError, LibraryError):
            return False

    def claim(self, step, *, unchanged_purge=False):
        if file_stat(step.staging):
            expected = step.claimed_identity or identity(step.source_signature)
            current = self.verified(step.staging, step, expected)
            self.mark(step, "verified", claimed_identity=identity(current))
            return current
        current = file_stat(step.source)
        if not current:
            raise LibraryError("source_missing", "源文件已缺失，操作未执行")
        current = signature(current)
        unchanged = current == step.source_signature
        expected = step.claimed_identity or identity(step.source_signature)
        if identity(current) != expected:
            raise LibraryError("source_replaced", "源文件已被替换，操作未执行")
        if current != step.source_signature:
            self.verified(step.source, step, expected)
            self.mark(step, "prepared", source_signature=current)
        self.mark(step, "claiming")
        with open_regular(Path(step.source)) as original:
            before = signature(os.fstat(original))
            if before != step.source_signature:
                raise LibraryError("source_changed", "源文件已变化，操作未执行")
            rename_new(step.source, step.staging)
            with open_regular(Path(step.staging)) as staged:
                after = signature(os.fstat(staged))
            # Record what was actually claimed before content validation so a
            # changed source can be put back without deleting somebody else's file.
            self.mark(step, "claimed", claimed_identity=identity(after))
            if identity(after) != identity(before):
                raise LibraryError("source_replaced", "源文件在移动时被替换")
        # An unchanged original has already been fingerprinted. A permanent
        # purge needs identity/attribute checks, not another full disk read.
        # Rename changes ctime; inode, size and mtime must remain identical.
        # Changed sources and crash recovery retain full content verification.
        if unchanged_purge and unchanged and after[:4] == before[:4]:
            current = after
        else:
            current = self.verified(step.staging, step, step.claimed_identity)
        self.mark(step, "verified")
        return current

    def copy_to_destination(self, step):
        copy_path = Path(step.copy_path)
        if file_stat(copy_path):
            if step.copy_identity:
                try:
                    complete = self.verified(copy_path, step, step.copy_identity)
                    self.mark(step, "publish_ready", published_identity=identity(complete))
                    rename_new(copy_path, step.destination)
                    self.mark(step, "published")
                    return
                except LibraryError:
                    # Only remove an incomplete copy whose inode belongs to this
                    # journal entry while the verified source is still retained.
                    self.verified(step.staging, step, step.claimed_identity)
                    info = file_stat(copy_path)
                    if info and identity(signature(info)) == step.copy_identity:
                        unlink_owned(copy_path, signature(info))
                    else:
                        raise LibraryError("copy_conflict", "复制临时位置已被占用") from None
            else:
                raise LibraryError("copy_conflict", "复制临时位置已存在，原文件仍保留")
        self.mark(step, "copying")
        with make_directory(copy_path.parent) as parent:
            output = os.open(
                copy_path.name,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                0o600,
                dir_fd=parent,
            )
            try:
                self.mark(step, "copying", copy_identity=identity(signature(os.fstat(output))))
                with open_regular(Path(step.staging)) as source:
                    before = signature(os.fstat(source))
                    digest = hashlib.sha256()
                    while chunk := os.read(source, 1024 * 1024):
                        if self.stop.is_set():
                            raise InterruptedError("service_stopping")
                        digest.update(chunk)
                        pending = memoryview(chunk)
                        while pending:
                            written = os.write(output, pending)
                            if written <= 0:
                                raise OSError(errno.EIO, "short_write")
                            pending = pending[written:]
                    if (
                        signature(os.fstat(source)) != before
                        or digest.hexdigest() != step.expected_hash
                    ):
                        raise LibraryError("source_changed", "复制期间源文件已变化")
                    source_info = os.fstat(source)
                    os.fchmod(output, source_info.st_mode & 0o777)
                    os.utime(output, ns=(source_info.st_atime_ns, source_info.st_mtime_ns))
                os.fsync(output)
                os.fsync(parent)
            finally:
                os.close(output)
        current = self.verified(copy_path, step, step.copy_identity)
        self.mark(step, "publish_ready", published_identity=identity(current))
        rename_new(copy_path, step.destination)
        self.mark(step, "published")

    def execute(self, step, kind):
        self.validate(step, kind)
        if (
            kind == "permanent"
            and step.phase == "purging"
            and not file_stat(step.staging)
            and not file_stat(step.source)
        ):
            with open_directory(Path(step.staging).parent) as parent:
                os.fsync(parent)
            return None
        if self.destination_owned(step):
            if file_stat(step.staging):
                current = self.verified(step.staging, step, step.claimed_identity)
                unlink_owned(step.staging, current)
            self.mark(step, "source_removed")
            return signature(file_stat(step.destination))
        if step.destination and file_stat(step.destination):
            raise LibraryError("destination_conflict", "原位置已有同名文件，未覆盖")
        current = self.claim(step, unchanged_purge=kind == "permanent")
        if kind == "permanent":
            self.mark(step, "purging")
            # Recheck the opened inode and attributes immediately after the
            # durable checkpoint; no unlink is based only on a path or hash.
            unlink_owned(step.staging, current)
            return None
        self.mark(step, "publish_ready", published_identity=identity(current))
        try:
            rename_new(step.staging, step.destination)
            self.mark(step, "published")
        except OSError as error:
            if error.errno != errno.EXDEV:
                raise
            self.copy_to_destination(step)
            destination_signature = self.verified(step.destination, step, step.published_identity)
            current = self.verified(step.staging, step, step.claimed_identity)
            if signature(file_stat(step.destination)) != destination_signature:
                raise LibraryError(
                    "destination_changed", "目标文件在校验后已变化，来源仍保留"
                ) from None
            unlink_owned(step.staging, current)
        self.mark(step, "source_removed")
        with open_regular(Path(step.destination)) as published:
            result = signature(os.fstat(published))
            if identity(result) != step.published_identity:
                raise LibraryError("destination_changed", "目标文件在操作期间已变化")
        return result

    def rollback(self, step, kind):
        """Return a claimed file without overwriting; keep any uncertain copy."""
        self.validate(step, kind)
        if self.destination_owned(step):
            return "pending", None
        if step.phase == "purging" and not file_stat(step.staging) and not file_stat(step.source):
            return "pending", None
        try:
            if file_stat(step.staging):
                with open_regular(Path(step.staging)) as staged:
                    current = signature(os.fstat(staged))
                expected = step.claimed_identity or identity(step.source_signature)
                if identity(current) != expected:
                    return "conflict", None
                if file_stat(step.source):
                    return "conflict", None
                rename_new(step.staging, step.source)
            if not file_stat(step.source):
                return "missing", None
            try:
                current = self.verified(
                    step.source, step, step.claimed_identity or identity(step.source_signature)
                )
            except LibraryError:
                with open_regular(Path(step.source)) as source:
                    current = signature(os.fstat(source))
                if identity(current) != (step.claimed_identity or identity(step.source_signature)):
                    return "conflict", None
                self.mark(step, "rolled_back", claimed_identity=[])
                return "changed", current
            if step.copy_path and step.copy_identity:
                partial = file_stat(step.copy_path)
                if partial and identity(signature(partial)) == step.copy_identity:
                    unlink_owned(step.copy_path, signature(partial))
            self.mark(step, "rolled_back", source_signature=current, claimed_identity=[])
            return "restored", current
        except (OSError, LibraryError):
            return "conflict", None

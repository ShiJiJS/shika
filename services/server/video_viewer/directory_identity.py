"""Read-only directory evidence, including optional Linux statx creation time."""

import ctypes
import os
import struct

from .paths import signature

# Linux statx ABI: fixed 256-byte structure; btime is the timestamp at 0x50.
# https://github.com/torvalds/linux/blob/master/include/uapi/linux/stat.h
_libc = ctypes.CDLL(None, use_errno=True)
_statx = getattr(_libc, "statx", None)
if _statx:
    _statx.argtypes = (ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_uint, ctypes.c_void_p)
    _statx.restype = ctypes.c_int


def directory_stamp(fd):
    info = os.fstat(fd)
    birth = getattr(info, "st_birthtime_ns", None)
    if birth is None and _statx:
        result = ctypes.create_string_buffer(256)
        # AT_EMPTY_PATH and STATX_BTIME inspect the already verified descriptor.
        if _statx(fd, b"", 0x1000, 0x800, result) == 0:
            raw = result.raw
            if struct.unpack_from("=I", raw)[0] & 0x800:
                seconds, nanoseconds = struct.unpack_from("=qI", raw, 0x50)
                if seconds > 0:
                    birth = seconds * 1_000_000_000 + nanoseconds
    return [*signature(info), str(birth) if birth is not None else None]

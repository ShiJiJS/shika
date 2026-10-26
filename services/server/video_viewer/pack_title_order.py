"""Bounded, process-local Chinese title keys using the runtime's pinned ICU.

Keys are ephemeral, not persisted in SQLite: ICU upgrades must not leave stale
on-disk keys. Each thread owns its collator; SQL applies the same key before
LIMIT, membership snapshots and anchor ranking.
"""

import ctypes as c
import ctypes.util
import re
import sys
import threading
import weakref
from functools import lru_cache

from .pack_presentation import presentation


class _ChineseCollator:
    def __init__(self):
        location = ctypes.util.find_library("icui18n")
        if not location:
            raise RuntimeError("Chinese pack ordering requires ICU (Debian libicu72)")
        self.library = c.CDLL(location)
        version = re.search(r"(?:\.so\.|\.)(\d+)(?:\.dylib)?$", location)
        suffix = "_" + version[1] if version else ""

        def function(name, args, result):
            value = getattr(self.library, name + suffix)
            value.argtypes, value.restype = args, result
            return value

        open_collator = function("ucol_open", [c.c_char_p, c.POINTER(c.c_int32)], c.c_void_p)
        close = function("ucol_close", [c.c_void_p], None)
        self.key = function(
            "ucol_getSortKey", [c.c_void_p, c.c_void_p, c.c_int32, c.c_void_p, c.c_int32], c.c_int32
        )
        error = c.c_int32(0)
        self.handle = open_collator(b"zh_CN", c.byref(error))
        if error.value > 0 or not self.handle:
            if self.handle:
                close(self.handle)
            raise RuntimeError(f"Cannot initialize Chinese pack ordering: ICU {error.value}")
        self.cleanup = weakref.finalize(self, close, self.handle)

    def sort_key(self, text):
        source = text.encode("utf-16-le" if sys.byteorder == "little" else "utf-16-be")
        size = self.key(self.handle, source, len(source) // 2, None, 0)
        target = c.create_string_buffer(size)
        actual = self.key(self.handle, source, len(source) // 2, target, size)
        if actual != size or size < 1:
            raise RuntimeError("ICU returned an invalid pack title key")
        return target.raw


_thread = threading.local()


@lru_cache(maxsize=1)
def title_order_available():
    """Bare development hosts may lack ICU; do not advertise a false promise."""
    try:
        probe = _ChineseCollator()
        try:
            probe.sort_key("")
        finally:
            probe.cleanup()
        return True
    except (OSError, AttributeError, RuntimeError):
        return False


@lru_cache(maxsize=4096)
def title_sort_key(name):
    if not hasattr(_thread, "collator"):
        _thread.collator = _ChineseCollator()
    return _thread.collator.sort_key(presentation(name).title)

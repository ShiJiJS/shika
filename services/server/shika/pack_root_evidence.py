"""Rebuildable, local proof of the directory used by a completed pack scan."""

import json

from .directory_identity import directory_stamp
from .models import Setting


def identity(fd):
    stamp = directory_stamp(fd)
    # Directory contents change normally. Only device, inode and (when
    # available) creation time identify the directory itself.
    return [stamp[0], stamp[1], stamp[-1]]


def key(root_id):
    return "pack_root_scan_v1:" + root_id


def remember(session, root, observed):
    value = json.dumps({"path": root.path, "last_scan": root.last_scan, "identity": observed})
    stored = session.get(Setting, key(root.id))
    if stored:
        stored.value = value
    else:
        session.add(Setting(key=key(root.id), value=value))


def matches(session, root, observed):
    stored = session.get(Setting, key(root.id))
    if not stored:
        return False
    try:
        value = json.loads(stored.value)
    except (ValueError, TypeError):
        return False
    return value == {"path": root.path, "last_scan": root.last_scan, "identity": observed}

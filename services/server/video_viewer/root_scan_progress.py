"""Durable per-root scan facts, indexed locally without exporting runtime state."""

import json
import time

from .authority import Authority
from .models import Setting

PREFIX = "root_scan_progress_v1:"
ACTIVE = {"queued", "discovering", "waiting_for_stable_files", "processing_media", "reconciling"}


def configuration(root):
    return [root.path, root.kind, root.mount_id, root.enabled]


def entry(root, task_id):
    return {
        "id": root.id,
        "kind": root.kind,
        "task_id": task_id,
        "configuration": configuration(root),
        "status": "queued" if root.enabled else "disabled",
        "phase": "queued" if root.enabled else "disabled",
        "discovered": 0,
        "processed": 0,
        "progress": {
            "discovered": 0,
            "processed": 0,
            "discovery_complete": False,
            **({"packs_discovered": 0, "packs_processed": 0} if root.kind == "pack" else {}),
        },
        "counts": {},
    }


def publish(session, task):
    """Task.result is authoritative; this index preserves other roots across scoped scans."""
    epoch = Authority.current(session)
    for item in task.result.get("roots", []):
        if "configuration" not in item:
            continue  # Legacy tasks have no reliable per-root/configuration facts.
        value = json.dumps({"epoch": epoch, "scan": item}, sort_keys=True)
        key = PREFIX + item["id"]
        stored = session.get(Setting, key)
        if stored:
            if stored.value != value:
                stored.value = value
        else:
            session.add(Setting(key=key, value=value))


def latest(session, root):
    stored = session.get(Setting, PREFIX + root.id)
    if not stored:
        return None
    try:
        value = json.loads(stored.value)
        item = value["scan"]
        if value["epoch"] == Authority.current(session) and item["configuration"] == configuration(
            root
        ):
            return {k: v for k, v in item.items() if k != "configuration"}
    except (ValueError, TypeError, KeyError):
        pass
    return None


def stage(item, status, *, error=None):
    item.update(status=status, phase=status, updated_at=time.time())
    if error:
        item["error"] = error
    if status not in ACTIVE:
        item["finished_at"] = time.time()


def terminate(result, status, error):
    for item in result.get("roots", []):
        if item["status"] in ACTIVE:
            stage(item, status, error=error)

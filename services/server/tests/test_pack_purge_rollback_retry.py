"""Retry only verified returned images after a rollback changes file metadata."""

import errno
import os
import stat
from pathlib import Path

import pytest

from .test_pack_operations import command, tree, wait
from .test_pack_purge_execution import execute, plan
from .test_pack_purge_plans import fixture


def partial(client, media):
    root, _, rows = fixture(client, media)
    purge = client.app.state.pack_purge

    def fail(phase, identity):
        row = purge.rows.get(identity)
        if phase == "purge_purging" and row and row.relative_path == "nested/2.jpg":
            raise PermissionError(errno.EACCES, "controlled rollback")

    purge.fault_hook = fail
    value = execute(client, plan(client, [rows[0]["id"]]))
    assert value["status"] == "failed" and value["result"]["pages_deleted"] == 1
    remaining = Path(root["path"]) / "pack-0" / "nested/2.jpg"
    assert remaining.is_file()
    purge.fault_hook = None
    return value, remaining


def test_retry_revalidates_returned_image_when_only_ctime_has_changed(library):
    client, media = library
    task, remaining = partial(client, media)
    before = tree(media)
    old_stat = remaining.stat()
    os.chmod(remaining, stat.S_IMODE(old_stat.st_mode))
    current = remaining.stat()
    assert current.st_ino == old_stat.st_ino
    assert current.st_mtime_ns == old_stat.st_mtime_ns
    assert current.st_ctime_ns != old_stat.st_ctime_ns
    result = wait(
        client,
        command(client, f"pack-operations/{task['id']}/retry", {"request_id": "retry-original"})[
            "id"
        ],
    )
    assert result["id"] == task["id"] and result["status"] == "completed", result
    assert result["result"]["pages_deleted"] == result["result"]["pages_total"] == 2
    assert tree(media) == {name: sha for name, sha in before.items() if name.endswith("notes.txt")}


@pytest.mark.parametrize("change", ["content", "replacement", "mtime", "new-image", "missing"])
def test_retry_does_not_accept_changed_or_replaced_returned_images(library, change):
    client, media = library
    task, remaining = partial(client, media)
    old_stat = remaining.stat()
    if change == "content":
        data = bytearray(remaining.read_bytes())
        data[len(data) // 2] ^= 1
        remaining.write_bytes(data)
        os.utime(remaining, ns=(old_stat.st_atime_ns, old_stat.st_mtime_ns))
    elif change == "replacement":
        new = remaining.with_name("replacement")
        new.write_bytes(remaining.read_bytes())
        os.utime(new, ns=(old_stat.st_atime_ns, old_stat.st_mtime_ns))
        os.replace(new, remaining)
    elif change == "mtime":
        os.utime(remaining, ns=(old_stat.st_atime_ns, old_stat.st_mtime_ns + 1_000_000))
    elif change == "missing":
        remaining.unlink()
    else:
        remaining.with_name("new.jpg").write_bytes(remaining.read_bytes())
    before = tree(media)
    result = wait(
        client,
        command(client, f"pack-operations/{task['id']}/retry", {"request_id": "retry-original"})[
            "id"
        ],
    )
    assert result["id"] == task["id"] and result["status"] == "failed", result
    assert result["result"]["pages_deleted"] == 1
    assert tree(media) == before

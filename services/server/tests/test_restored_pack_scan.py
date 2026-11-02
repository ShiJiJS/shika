"""Restored identities survive scans without absorbing replacements or user data."""

import os
import shutil
from pathlib import Path
from unittest.mock import patch

import pytest
from sqlalchemy import select

from video_viewer.models import (
    ImagePack,
    PackFileOperation,
    PackPage,
    PackPreferences,
    PackProgress,
    PackPurgeStep,
    PackSessionEntry,
    PackTagLink,
    RecentEntry,
)
from video_viewer.pack_scanner import PackScanner

from .test_media_types import pack_tag
from .test_pack_operations import command, tree, wait
from .test_packs import packs, sync
from .test_reading import create, opened, progress_body
from .test_rolled_back_image_reads import restored


def no_birth(monkeypatch):
    from video_viewer.pack_scanner import directory_stamp

    monkeypatch.setattr(
        "video_viewer.pack_scanner.directory_stamp", lambda fd: [*directory_stamp(fd)[:5], None]
    )


def managed(client, pack):
    tag = pack_tag(client, name="keep original", key="original-tag")
    response = client.patch(
        "/api/v1/pack-tag-links",
        json={"pack_ids": [pack["id"]], "tag_ids": [tag["id"]], "request_id": "tag-original"},
    )
    assert response.status_code == 200
    reading = create(client, anchor_pack_id=pack["id"])
    state = opened(client, reading)
    response = client.patch(
        f"/api/v1/packs/{pack['id']}/progress",
        json=progress_body(reading, state, offset_ratio=0.45),
    )
    assert response.status_code == 200
    return tag, reading


def metadata(client, pack_id):
    with client.app.state.db.read() as session:
        return {
            table.__tablename__: [
                {column.name: getattr(row, column.name) for column in table.__table__.columns}
                for row in session.scalars(select(table).where(table.pack_id == pack_id))
            ]
            for table in (PackTagLink, PackProgress, PackPreferences, RecentEntry, PackSessionEntry)
        }


def test_scan_restored_returned_image_preserves_original_identity_and_resume(library, monkeypatch):
    client, media = library
    no_birth(monkeypatch)
    task, original, page, remaining = restored(client, media)
    tag, reading = managed(client, original)
    before, files = metadata(client, original["id"]), tree(media)
    sync(client)
    current = next(p for p in packs(client)["items"] if p["path"] == original["path"])
    assert current["id"] == original["id"], (current, original)
    assert current["tag_ids"] == [tag["id"]]
    assert current["page_count"] == 1
    assert current["progress"]["page_id"] == page["id"]
    assert current["progress"]["offset_ratio"] == 0.45
    assert metadata(client, original["id"]) == before
    listing = client.get(f"/api/v1/packs/{original['id']}/pages").json()
    assert [p["id"] for p in listing["items"]] == [page["id"]]
    assert client.get(listing["items"][0]["image_url"]).content == remaining.read_bytes()
    resumed = client.get(f"/api/v1/pack-sessions/{reading['id']}").json()
    assert resumed["resume"]["page"]["id"] == page["id"]
    assert resumed["resume"]["offset_ratio"] == 0.45
    assert client.get("/api/v1/recent", params={"kind": "pack"}).json()["total"] == 1
    result = wait(
        client,
        command(client, f"pack-operations/{task['id']}/retry", {"request_id": "old-after-scan"})[
            "id"
        ],
    )
    assert result["error"] == "stale_pack_state"
    assert tree(media) == files
    version = current["content_version"]
    sync(client)
    assert client.get(f"/api/v1/packs/{original['id']}").json()["content_version"] == version
    assert metadata(client, original["id"]) == before and tree(media) == files


def legacy_duplicate(client, original):
    # Reproduce the old scanner decision: no continuity, and content fallback
    # counts the permanently deleted tombstone as if it were still on disk.
    with patch.object(PackScanner, "continuity", return_value=False):
        sync(client)
    current = next(p for p in packs(client)["items"] if p["path"] == original["path"])
    assert current["id"] != original["id"]
    return current


def test_scan_repairs_existing_unmanaged_duplicate_to_original_identity(library, monkeypatch):
    client, media = library
    no_birth(monkeypatch)
    _, original, page, remaining = restored(client, media)
    managed(client, original)
    before, files = metadata(client, original["id"]), tree(media)
    duplicate = legacy_duplicate(client, original)
    sync(client)
    current = next(p for p in packs(client)["items"] if p["path"] == original["path"])
    assert current["id"] == original["id"], (current, duplicate)
    assert metadata(client, original["id"]) == before
    with client.app.state.db.read() as session:
        assert session.get(ImagePack, duplicate["id"]) is None
    assert (
        client.get(f"/api/v1/packs/{original['id']}/pages").json()["items"][0]["id"] == page["id"]
    )
    assert remaining.is_file() and tree(media) == files


@pytest.mark.parametrize("relation", ["tag", "progress", "preferences", "recent", "session"])
def test_existing_duplicate_with_management_rows_is_not_silently_discarded(
    library, monkeypatch, relation
):
    client, media = library
    no_birth(monkeypatch)
    _, original, _, _ = restored(client, media)
    managed(client, original)
    duplicate = legacy_duplicate(client, original)
    with client.app.state.db.write() as session:
        page = session.scalar(select(PackPage).where(PackPage.pack_id == duplicate["id"]))
        if relation == "tag":
            tag = session.scalar(select(PackTagLink).where(PackTagLink.pack_id == original["id"]))
            session.add(PackTagLink(pack_id=duplicate["id"], tag_id=tag.tag_id))
        elif relation == "progress":
            session.add(PackProgress(pack_id=duplicate["id"], page_id=page.id, offset_ratio=0.73))
        elif relation == "preferences":
            session.add(PackPreferences(pack_id=duplicate["id"], mode="horizontal"))
        elif relation == "recent":
            session.add(RecentEntry(kind="pack", pack_id=duplicate["id"]))
        else:
            entry = session.scalar(
                select(PackSessionEntry).where(PackSessionEntry.pack_id == original["id"])
            )
            session.add(
                PackSessionEntry(session_id=entry.session_id, pack_id=duplicate["id"], ordinal=100)
            )
    before = {p["id"]: metadata(client, p["id"]) for p in (original, duplicate)}
    files = tree(media)
    job = sync(client)
    for identity, values in before.items():
        assert metadata(client, identity) == values
        with client.app.state.db.read() as session:
            assert session.get(ImagePack, identity)
    assert tree(media) == files
    assert job["result"]["packs"]["identity_ambiguous"] >= 1


@pytest.mark.parametrize(
    "change", ["content", "inode", "mtime", "directory", "birth", "journal", "historical"]
)
def test_returned_scan_witness_does_not_absorb_external_replacements(library, monkeypatch, change):
    client, media = library
    no_birth(monkeypatch)
    task, original, _, remaining = restored(client, media)
    managed(client, original)
    if change == "content":
        info = remaining.stat()
        from .test_packs import image

        image(remaining, color="green", format="JPEG")
        os.utime(remaining, ns=(info.st_atime_ns, info.st_mtime_ns))
    elif change == "inode":
        info = remaining.stat()
        other = remaining.with_name("replacement")
        other.write_bytes(remaining.read_bytes())
        os.utime(other, ns=(info.st_atime_ns, info.st_mtime_ns))
        os.replace(other, remaining)
    elif change == "mtime":
        info = remaining.stat()
        os.utime(remaining, ns=(info.st_atime_ns, info.st_mtime_ns + 1000000))
    elif change == "directory":
        folder = Path(original["path"])
        moved = media / "detached"
        folder.rename(moved)
        shutil.copytree(moved, folder)
    elif change == "birth":
        from video_viewer.pack_scanner import directory_stamp

        with client.app.state.db.write() as session:
            pack = session.get(ImagePack, original["id"])
            pack.directory_signature = [*pack.directory_signature[:5], "1"]
        monkeypatch.setattr(
            "video_viewer.pack_scanner.directory_stamp", lambda fd: [*directory_stamp(fd)[:5], "2"]
        )
    else:
        with client.app.state.db.write() as session:
            if change == "historical":
                session.get(PackFileOperation, task["id"]).historical = True
            else:
                row = session.scalar(
                    select(PackPurgeStep).where(PackPurgeStep.phase == "rolled_back")
                )
                row.state = {}
    before, files = metadata(client, original["id"]), tree(media)
    sync(client)
    current = next(p for p in packs(client)["items"] if p["path"] == original["path"])
    assert current["id"] != original["id"]
    assert current["tag_ids"] == [] and current["progress"] is None
    assert metadata(client, original["id"]) == before and tree(media) == files


def test_management_added_during_inspection_prevents_duplicate_retirement(library, monkeypatch):
    client, media = library
    no_birth(monkeypatch)
    _, original, _, _ = restored(client, media)
    tag, _ = managed(client, original)
    duplicate = legacy_duplicate(client, original)
    before, files = metadata(client, original["id"]), tree(media)
    read_pack = PackScanner.read_pack
    added = []

    def inspect_then_tag(scanner, path, *args):
        result = read_pack(scanner, path, *args)
        if str(path) == original["path"] and not added:
            with client.app.state.db.write() as session:
                session.add(PackTagLink(pack_id=duplicate["id"], tag_id=tag["id"]))
            added.append(True)
        return result

    monkeypatch.setattr(PackScanner, "read_pack", inspect_then_tag)
    job = sync(client)
    assert added and job["result"]["packs"]["identity_ambiguous"] >= 1
    assert metadata(client, original["id"]) == before and tree(media) == files
    assert metadata(client, duplicate["id"])["pack_tag_links"] == [
        {"pack_id": duplicate["id"], "tag_id": tag["id"]}
    ]

import hashlib
import os
import shutil
import tempfile
from dataclasses import replace
from pathlib import Path

from shika.config import Mount

from .conftest import connect, put, scan
from .test_file_operations import operation, trash
from .test_playback import create_round
from .test_tags import assign, tag


def marked_video(client):
    video = client.get("/api/v1/videos").json()["items"][0]
    marked = tag(client, "稳定标签")["id"]
    assign(client, [video["id"]], [marked])
    return video, marked


def test_external_rename_and_directory_move_keep_identity_and_round(library, samples):
    client, media = library
    original = media / "before" / "one.mov"
    digest = put(samples / "h264.mov", original)
    scan(client)
    old, marked = marked_video(client)
    active, _ = create_round(client, "sequential")
    moved = media / "after" / "新名称.mov"
    moved.parent.mkdir()
    original.rename(moved)
    original.parent.rmdir()
    job = scan(client)
    assert job["result"]["identity_matched"] == 1, job
    fresh = client.get("/api/v1/videos").json()["items"][0]
    assert fresh["id"] == old["id"] and fresh["tag_ids"] == [marked]
    assert fresh["name"] == moved.name and fresh["path"] == str(moved)
    assert client.get("/api/v1/playback").json()["id"] == active["id"]
    assert client.get("/api/v1/playback").json()["current"]["id"] == old["id"]
    root = client.get("/api/v1/roots").json()["items"][0]
    children = client.get("/api/v1/directories", params={"parent_id": root["directory_id"]}).json()[
        "items"
    ]
    assert [d["name"] for d in children] == ["after"]
    assert client.get(fresh["media_url"]).content == moved.read_bytes()
    assert hashlib.sha256(moved.read_bytes()).hexdigest() == digest and not original.exists()
    assert scan(client)["result"]["unchanged"] == 1
    assert client.get("/api/v1/videos").json()["items"][0]["id"] == old["id"]


def test_move_across_roots_matches_after_all_roots_regardless_of_order(environment, samples):
    settings, media = environment
    first, last = media / "a-first", media / "z-last"
    first.mkdir()
    original = last / "one.mov"
    put(samples / "h264.mov", original)
    settings = replace(settings, mounts=(Mount("a", "first", first), Mount("z", "last", last)))
    client, _ = connect(settings)
    try:
        scan(client)
        old, marked = marked_video(client)
        original.rename(first / "moved.mov")
        result = scan(client)
        fresh = client.get("/api/v1/videos").json()["items"][0]
        assert result["result"]["identity_matched"] == 1, result
        assert fresh["root_id"] == "a" and fresh["id"] == old["id"]
        assert fresh["tag_ids"] == [marked]
        assert client.get("/api/v1/videos?status=missing").json()["total"] == 0
    finally:
        client.__exit__(None, None, None)


def test_cross_device_unique_full_content_match_preserves_id(environment, samples):
    settings, media = environment
    original = media / "one.mov"
    digest = put(samples / "h264.mov", original)
    with tempfile.TemporaryDirectory(prefix="video-viewer-external-", dir="/dev/shm") as target:
        destination = Path(target) / "other.mov"
        assert destination.parent.stat().st_dev != original.stat().st_dev
        settings = replace(
            settings, mounts=(*settings.mounts, Mount("other", "other", Path(target)))
        )
        client, _ = connect(settings)
        try:
            scan(client)
            old, marked = marked_video(client)
            shutil.copyfile(original, destination)
            original.unlink()
            result = scan(client)
            assert result["result"]["identity_matched"] == 1, result
            fresh = client.get("/api/v1/videos").json()["items"][0]
            assert fresh["id"] == old["id"] and fresh["tag_ids"] == [marked]
            assert fresh["root_id"] == "other"
            assert hashlib.sha256(destination.read_bytes()).hexdigest() == digest
        finally:
            client.__exit__(None, None, None)


def test_copy_and_hardlink_stay_distinct_and_do_not_inherit_tags(library, samples):
    client, media = library
    source = media / "one.mov"
    put(samples / "h264.mov", source)
    scan(client)
    old, marked = marked_video(client)
    shutil.copyfile(source, media / "copy.mov")
    os.link(source, media / "hardlink.mov")
    scan(client)
    videos = client.get("/api/v1/videos").json()["items"]
    assert len(videos) == 3 and len({v["id"] for v in videos}) == 3
    assert next(v for v in videos if v["id"] == old["id"])["tag_ids"] == [marked]
    assert all(v["tag_ids"] == [] for v in videos if v["id"] != old["id"])


def test_ambiguous_identical_new_copies_are_not_guessed(library, samples):
    client, media = library
    source = media / "one.mov"
    put(samples / "h264.mov", source)
    scan(client)
    old, marked = marked_video(client)
    # Copies have different inodes; remove the origin only after making both.
    shutil.copyfile(source, media / "a.mov")
    shutil.copyfile(source, media / "b.mov")
    source.unlink()
    result = scan(client)
    assert result["result"]["identity_matched"] == 0, result
    assert result["result"]["identity_ambiguous"] == 2
    fresh = client.get("/api/v1/videos").json()["items"]
    assert len(fresh) == 2 and all(v["id"] != old["id"] and not v["tag_ids"] for v in fresh)
    missing = client.get("/api/v1/videos?status=missing").json()["items"]
    assert len(missing) == 1 and missing[0]["id"] == old["id"] and missing[0]["tag_ids"] == [marked]
    assert scan(client)["result"]["identity_matched"] == 0


def test_missing_outside_scope_then_return_and_path_replacement(library, samples, tmp_path):
    client, media = library
    source, away = media / "one.mov", tmp_path / "away.mov"
    put(samples / "h264.mov", source)
    scan(client)
    old, marked = marked_video(client)
    source.rename(away)
    scan(client)
    assert client.get("/api/v1/videos").json()["total"] == 0
    assert client.get("/api/v1/videos?status=missing").json()["items"][0]["tag_ids"] == [marked]
    # A different file now occupies the original name, while the original returns elsewhere.
    put(samples / "portrait.mp4", source)
    away.rename(media / "returned.mov")
    scan(client)
    videos = client.get("/api/v1/videos").json()["items"]
    recovered = next(v for v in videos if v["name"] == "returned.mov")
    replacement = next(v for v in videos if v["name"] == "one.mov")
    assert recovered["id"] == old["id"] and recovered["tag_ids"] == [marked]
    assert replacement["id"] != old["id"] and replacement["tag_ids"] == []


def test_real_trash_is_not_external_identity_candidate(library, samples):
    client, media = library
    source = media / "one.mov"
    put(samples / "h264.mov", source)
    scan(client)
    old, marked = marked_video(client)
    shutil.copyfile(source, media / "copy.mov")
    assert trash(client, [old["id"]])[0]["status"] == "completed"
    scan(client)
    fresh = client.get("/api/v1/videos").json()["items"]
    assert len(fresh) == 1 and fresh[0]["id"] != old["id"] and fresh[0]["tag_ids"] == []
    item = client.get("/api/v1/trash").json()["items"][0]
    assert item["video"]["id"] == old["id"] and item["video"]["tag_ids"] == [marked]
    restored, _ = operation(client, "/api/v1/trash/restore", {"trash_ids": [item["id"]]})
    assert restored["status"] == "completed", restored
    scan(client)
    assert client.get("/api/v1/videos").json()["total"] == 2


def test_removed_selected_directory_keeps_empty_round_scope(library, samples):
    client, media = library
    source = media / "before" / "one.mov"
    put(samples / "h264.mov", source)
    scan(client)
    root = client.get("/api/v1/roots").json()["items"][0]
    directory = client.get(
        "/api/v1/directories", params={"parent_id": root["directory_id"]}
    ).json()["items"][0]
    video, marked = marked_video(client)
    old, _ = create_round(
        client, "sequential", {"directory_id": directory["id"], "tag_ids": [marked]}
    )
    source.parent.rename(media / "after")
    scan(client)
    active = client.get("/api/v1/playback")
    assert active.status_code == 200, active.text
    assert active.json()["id"] == old["id"] and active.json()["total"] == 0
    assert active.json()["scope"]["directory_id"] == directory["id"]
    assert active.json()["current"] is None
    deleted = client.request(
        "DELETE", f"/api/v1/tags/{marked}", json={"request_id": "remove-in-stale-scope"}
    )
    assert deleted.status_code == 200, deleted.text
    current = client.get("/api/v1/playback").json()
    assert current["id"] != old["id"] and current["total"] == 0
    assert current["scope"]["directory_id"] == directory["id"] and current["scope"]["tag_ids"] == []


def test_same_quick_fingerprint_different_middle_content_never_inherits_tags(library, samples):
    client, media = library
    source = media / "one.mp4"
    put(samples / "portrait.mp4", source)
    with source.open("ab") as output:
        output.truncate(256 * 1024)
    scan(client)
    old, marked = marked_video(client)
    replacement = media / "different.mp4"
    shutil.copyfile(source, replacement)
    with replacement.open("r+b") as output:
        output.seek(128 * 1024)
        output.write(b"different-middle")
    before, after = source.read_bytes(), replacement.read_bytes()
    assert (
        len(before) == len(after)
        and before[:65536] == after[:65536]
        and before[-65536:] == after[-65536:]
    )
    assert hashlib.sha256(before).digest() != hashlib.sha256(after).digest()
    source.unlink()
    result = scan(client)
    assert result["result"]["identity_matched"] == 0, result
    fresh = client.get("/api/v1/videos").json()["items"][0]
    assert fresh["id"] != old["id"] and fresh["tag_ids"] == []
    assert client.get("/api/v1/videos?status=missing").json()["items"][0]["tag_ids"] == [marked]


def test_multiple_missing_identical_origins_do_not_merge_into_one_new_copy(library, samples):
    client, media = library
    put(samples / "h264.mov", media / "one.mov")
    put(samples / "h264.mov", media / "two.mov")
    scan(client)
    old = client.get("/api/v1/videos").json()["items"]
    marked = tag(client, "原副本标签")["id"]
    assign(client, [old[0]["id"]], [marked])
    shutil.copyfile(media / "one.mov", media / "new.mov")
    (media / "one.mov").unlink()
    (media / "two.mov").unlink()
    result = scan(client)
    assert result["result"]["identity_matched"] == 0, result
    fresh = client.get("/api/v1/videos").json()["items"][0]
    assert fresh["id"] not in [v["id"] for v in old] and fresh["tag_ids"] == []
    assert client.get("/api/v1/videos?status=missing").json()["total"] == 2

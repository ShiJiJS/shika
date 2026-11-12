"""Whole-pack scan/query/read contracts over disposable generated images."""

import hashlib
import os
import shutil
import time
from pathlib import Path

import pytest
from PIL import Image
from sqlalchemy import select

from shika.models import ImagePack, Observation, PackPage, PackProgress

from .conftest import scan
from .test_media_types import pack_root, pack_tag


def image(path, *, color="red", size=(40, 60), format=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", size, color).save(path, format=format)
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sync(client, timeout=60):
    time.sleep(0.04)
    job = scan(client, timeout)
    # A changed known signature first enters the explicit stability wait.
    for _ in range(3):
        if not any(root["status"] == "deferred" for root in job["result"]["roots"]):
            return job
        time.sleep(0.04)
        job = scan(client, timeout)
    return job


def packs(client, **params):
    response = client.get("/api/v1/packs", params=params)
    assert response.status_code == 200, response.text
    return response.json()


def pages(client, identity, **params):
    response = client.get(f"/api/v1/packs/{identity}/pages", params=params)
    assert response.status_code == 200, response.text
    return response.json()


def label(client, pack_id):
    tag = pack_tag(client)
    response = client.patch(
        "/api/v1/pack-tag-links",
        json={"pack_ids": [pack_id], "tag_ids": [tag["id"]], "request_id": "assign"},
    )
    assert response.status_code == 200, response.text
    return tag


def test_pack_natural_manifest_pagination_image_formats_auth_and_versions(library):
    client, media = library
    root = pack_root(client, media)
    base = Path(root["path"])
    hashes = {}
    for name in ("10.png", "2.png", "1.jpg", "chapter10/1.webp", "chapter2/3.png"):
        hashes[name] = image(base / "natural" / name)
    image(base / "other" / "1.png", color="blue")
    job = sync(client)
    assert job["result"]["packs"]["progress"]["processed"] == 6, job
    catalog = packs(client, limit=1)
    assert catalog["total"] == 2 and len(catalog["items"]) == 1
    pack = next(p for p in packs(client)["items"] if p["name"] == "natural")
    assert pack["page_count"] == pack["readable_count"] == 5
    listing = pages(client, pack["id"])
    assert [p["relative_path"] for p in listing["items"]] == [
        "1.jpg",
        "2.png",
        "10.png",
        "chapter2/3.png",
        "chapter10/1.webp",
    ]
    assert len(pages(client, pack["id"], limit=2, offset=4)["items"]) == 1
    for page in listing["items"]:
        response = client.get(page["image_url"])
        assert response.status_code == 200, response.text
        assert hashlib.sha256(response.content).hexdigest() == hashes[page["relative_path"]]
        assert response.headers["content-type"].startswith("image/")
        assert response.headers["x-content-version"] == str(pack["content_version"])
        assert client.head(page["image_url"]).content == b""
        ranged = client.get(page["image_url"], headers={"Range": "bytes=0-9"})
        assert ranged.status_code == 206 and len(ranged.content) == 10
        assert client.get(page["image_url"], headers={"Authorization": ""}).status_code == 401
        assert client.get(page["thumbnail_url"]).headers["content-type"] == "image/jpeg"
    assert client.get(pack["cover_url"]).status_code == 200
    assert client.get("/api/v1/packs", headers={"Authorization": ""}).status_code == 401
    assert client.get("/api/v1/packs", params={"limit": 201}).status_code == 422
    assert (
        client.get(
            f"/api/v1/packs/{pack['id']}/pages", params={"v": pack["content_version"] + 1}
        ).status_code
        == 409
    )
    assert client.get("/api/v1/pages/not-a-page/image").status_code == 404
    assert packs(client, search="%")["total"] == 0
    assert packs(client, search="natural")["total"] == 1
    assert client.get("/api/v1/library-state").json()["media"]["pack"]["ready"] is True


def test_rename_pack_and_pages_preserves_ids_tags_progress_and_avoids_reprobe(library, monkeypatch):
    client, media = library
    root = pack_root(client, media)
    base = Path(root["path"])
    image(base / "before" / "1.png")
    image(base / "before" / "2.png", color="blue")
    sync(client)
    before = packs(client)["items"][0]
    first = pages(client, before["id"])["items"][0]
    tag = label(client, before["id"])
    with client.app.state.db.write() as session:
        session.add(PackProgress(pack_id=before["id"], page_id=first["id"], offset_ratio=0.4))
    (base / "before").rename(base / "renamed")
    sync(client)
    renamed = packs(client)["items"][0]
    assert renamed["id"] == before["id"] and renamed["tag_ids"] == [tag["id"]]
    assert renamed["progress"]["page_id"] == first["id"]
    assert pages(client, renamed["id"])["items"][0]["id"] == first["id"]
    assert renamed["content_version"] == before["content_version"]
    (base / "renamed" / "1.png").rename(base / "renamed" / "3.png")
    sync(client)
    changed = packs(client)["items"][0]
    assert changed["content_version"] > renamed["content_version"]
    assert changed["progress"]["page_id"] == first["id"]

    def unexpected(*args, **kwargs):
        raise AssertionError("unchanged image must not decode or hash again")

    monkeypatch.setattr("shika.pack_scanner.inspect_image", unexpected)
    job = sync(client)
    assert job["result"]["packs"]["unchanged"] == 1, job


def test_same_path_replacement_does_not_inherit_old_labels_or_progress(library):
    client, media = library
    root = pack_root(client, media)
    base = Path(root["path"])
    image(base / "same" / "1.png")
    sync(client)
    old = packs(client)["items"][0]
    label(client, old["id"])
    old_page = pages(client, old["id"])["items"][0]
    with client.app.state.db.write() as session:
        session.add(PackProgress(pack_id=old["id"], page_id=old_page["id"]))
    (base / "same").rename(media / "detached")
    image(base / "same" / "1.png", color="green")
    sync(client)
    new = packs(client)["items"][0]
    assert new["id"] != old["id"] and new["tag_ids"] == [] and new["progress"] is None
    missing = packs(client, status="missing")["items"][0]
    assert missing["id"] == old["id"] and missing["tag_ids"] and missing["progress"]
    assert client.get(old_page["image_url"]).status_code == 404


def test_unique_content_move_recovers_but_duplicate_copies_remain_ambiguous(library):
    client, media = library
    root = pack_root(client, media)
    base = Path(root["path"])
    image(base / "original" / "1.png")
    image(base / "original" / "2.png")
    sync(client)
    old = packs(client)["items"][0]
    label(client, old["id"])
    old_page = pages(client, old["id"])["items"][0]
    shutil.copytree(base / "original", base / "copied")
    shutil.rmtree(base / "original")
    sync(client)
    copied = packs(client)["items"][0]
    assert copied["id"] == old["id"] and copied["tag_ids"]
    assert pages(client, copied["id"])["items"][0]["id"] == old_page["id"]
    shutil.copytree(base / "copied", base / "duplicate-a")
    shutil.copytree(base / "copied", base / "duplicate-b")
    shutil.rmtree(base / "copied")
    job = sync(client)
    current = packs(client)
    assert current["total"] == 2
    assert all(p["id"] != old["id"] and p["tag_ids"] == [] for p in current["items"])
    assert packs(client, status="missing")["items"][0]["id"] == old["id"]
    assert job["result"]["packs"]["identity_ambiguous"] == 2


def test_disabled_nested_scope_and_offline_keep_manifest_and_progress(library):
    client, media = library
    root = pack_root(client, media)
    base = Path(root["path"])
    image(base / "pack" / "1.png")
    image(base / "pack" / "nested" / "2.png", color="blue")
    sync(client)
    pack = packs(client)["items"][0]
    nested_page = pages(client, pack["id"])["items"][1]
    label(client, pack["id"])
    with client.app.state.db.write() as session:
        session.add(PackProgress(pack_id=pack["id"], page_id=nested_page["id"], offset_ratio=0.7))
    nested = client.post(
        "/api/v1/roots",
        json={
            "name": "停用子目录",
            "path": str(base / "pack" / "nested"),
            "kind": "pack",
            "enabled": False,
        },
    ).json()
    assert packs(client)["items"][0]["page_count"] == 1
    assert client.get(nested_page["image_url"]).status_code == 409
    sync(client)
    with client.app.state.db.read() as session:
        assert session.get(PackPage, nested_page["id"])
        assert session.get(PackProgress, pack["id"]).page_id == nested_page["id"]
    client.put(
        f"/api/v1/roots/{nested['id']}",
        json={"name": nested["name"], "path": nested["path"], "enabled": True},
    )
    # The explicitly nested root now owns its direct files, not the outer pack.
    assert client.get(nested_page["image_url"]).status_code == 409
    moved = base.with_name("offline-packs")
    base.rename(moved)
    try:
        sync(client)
        assert packs(client)["total"] == 0
        assert packs(client, status="missing")["total"] == 0
        with client.app.state.db.read() as session:
            assert session.get(ImagePack, pack["id"]).status == "available"
            assert session.get(PackProgress, pack["id"]).page_id == nested_page["id"]
    finally:
        moved.rename(base)


def test_bad_empty_unsupported_animated_and_optional_thumbnail_failure(library, monkeypatch):
    client, media = library
    root = pack_root(client, media)
    base = Path(root["path"])
    image(base / "mixed" / "1.png")
    (base / "mixed" / "2.jpg").write_bytes(b"invalid")
    (base / "mixed" / "notes.txt").write_text("keep me")
    (base / "empty").mkdir()
    (base / "unsupported").mkdir()
    (base / "unsupported" / "a.gif").write_bytes(b"not indexed")
    frames = [Image.new("RGB", (10, 10), color) for color in ("red", "blue")]
    frames[0].save(base / "mixed" / "3.webp", save_all=True, append_images=frames[1:], duration=50)
    job = sync(client)
    pack = packs(client)["items"][0]
    assert pack["page_count"] == 3 and pack["readable_count"] == 1
    assert packs(client, status="unreadable")["total"] == 2
    listed = pages(client, pack["id"])["items"]
    assert {p["error"] for p in listed} == {None, "invalid_image", "animated_image_unsupported"}
    assert job["result"]["packs"]["unsupported_files"] == 2
    assert (base / "mixed" / "notes.txt").read_text() == "keep me"
    # A cache directory made unwritable must not disable valid source images.
    for child in (client.app.state.settings.data_dir / "image-thumbnails").iterdir():
        child.unlink()
    cache = client.app.state.settings.data_dir / "image-thumbnails"
    cache.chmod(0o500)
    try:
        sync(client)
        pack = packs(client)["items"][0]
        assert pack["readable_count"] == 1 and pack["cover_url"] is None
        assert client.get(pages(client, pack["id"])["items"][0]["image_url"]).status_code == 200
    finally:
        cache.chmod(0o700)


def test_page_changes_relocate_removed_progress_and_invalidate_old_versions(library):
    client, media = library
    root = pack_root(client, media)
    base = Path(root["path"]) / "pack"
    for index, color in enumerate(("red", "blue", "green"), 1):
        image(base / f"{index}.png", color=color)
    sync(client)
    pack = packs(client)["items"][0]
    before = pages(client, pack["id"])["items"]
    with client.app.state.db.write() as session:
        session.add(PackProgress(pack_id=pack["id"], page_id=before[1]["id"], offset_ratio=0.6))
    (base / "2.png").unlink()
    image(base / "4.png", color="yellow")
    sync(client)
    changed = packs(client)["items"][0]
    after = pages(client, pack["id"])["items"]
    assert [page["relative_path"] for page in after] == ["1.png", "3.png", "4.png"]
    assert after[0]["id"] == before[0]["id"] and after[1]["id"] == before[2]["id"]
    assert changed["progress"]["page_id"] == after[1]["id"]
    assert changed["progress"]["revision"] == 1 and changed["progress"]["offset_ratio"] == 0
    assert changed["content_version"] > pack["content_version"]
    assert client.get(before[0]["image_url"]).status_code == 409
    image(base / "1.png", color="black")
    assert client.get(after[0]["image_url"]).status_code == 409
    sync(client)
    current = pages(client, pack["id"])["items"][0]
    assert current["sha256"] != after[0]["sha256"]
    assert client.get(current["image_url"]).status_code == 200


def test_disabled_root_reenable_preserves_ids_and_page_permissions(library):
    client, media = library
    root = pack_root(client, media)
    image(Path(root["path"]) / "pack" / "1.png")
    sync(client)
    pack = packs(client)["items"][0]
    page = pages(client, pack["id"])["items"][0]
    label(client, pack["id"])
    body = {"path": root["path"], "name": root["name"], "enabled": False}
    client.put(f"/api/v1/roots/{root['id']}", json=body)
    assert packs(client)["total"] == 0
    assert client.get(page["image_url"]).status_code == 409
    sync(client)
    assert packs(client, status="missing")["total"] == 0
    assert client.get("/api/v1/pack-tags").json()["items"][0]["pack_count"] == 0
    client.put(f"/api/v1/roots/{root['id']}", json={**body, "enabled": True})
    sync(client)
    current = packs(client)["items"][0]
    assert current["id"] == pack["id"] and current["tag_ids"]
    assert pages(client, pack["id"])["items"][0]["id"] == page["id"]
    assert client.get("/api/v1/pack-tags").json()["items"][0]["pack_count"] == 1


def test_symlinks_and_replaced_directory_cannot_serve_cached_images(library, tmp_path):
    client, media = library
    root = pack_root(client, media)
    base = Path(root["path"])
    outside = tmp_path / "outside"
    image(outside / "secret.png", color="blue")
    image(base / "safe" / "1.png")
    (base / "safe" / "linked.png").symlink_to(outside / "secret.png")
    (base / "linked-pack").symlink_to(outside, target_is_directory=True)
    (base / "safe" / "linked-dir").symlink_to(outside, target_is_directory=True)
    job = sync(client)
    assert job["result"]["packs"]["symlinks_skipped"] == 3
    pack = packs(client)["items"][0]
    page = pages(client, pack["id"])["items"][0]
    assert pack["page_count"] == 1
    original = base / "safe" / "1.png"
    original.unlink()
    original.symlink_to(outside / "secret.png")
    assert client.get(page["image_url"]).status_code in (409, 422)
    assert client.get(page["thumbnail_url"]).status_code in (409, 422)
    assert hashlib.sha256((outside / "secret.png").read_bytes()).hexdigest() != page["sha256"]


def test_partial_permission_failure_keeps_old_pack_and_page_records(library):
    client, media = library
    root = pack_root(client, media)
    base = Path(root["path"])
    image(base / "pack" / "1.png")
    image(base / "pack" / "restricted" / "2.png")
    image(base / "good" / "1.png", color="blue")
    sync(client)
    pack = next(pack for pack in packs(client)["items"] if pack["name"] == "pack")
    with client.app.state.db.read() as session:
        before = {page.id for page in session.scalars(select(PackPage))}
    (base / "pack" / "1.png").unlink()
    (base / "pack" / "restricted").chmod(0)
    try:
        sync(client)
        assert [pack["name"] for pack in packs(client)["items"]] == ["good"]
        assert packs(client, status="unreadable")["items"][0]["id"] == pack["id"]
        assert packs(client, status="missing")["total"] == 0
        with client.app.state.db.read() as session:
            assert session.get(ImagePack, pack["id"]).status == "available"
            assert {page.id for page in session.scalars(select(PackPage))} == before
    finally:
        (base / "pack" / "restricted").chmod(0o700)
    sync(client)
    assert packs(client)["total"] == 2
    assert (
        next(pack for pack in packs(client)["items"] if pack["name"] == "pack")["page_count"] == 1
    )


def test_tag_intersection_read_states_and_typed_directory_filters(library):
    client, media = library
    root = pack_root(client, media)
    base = Path(root["path"])
    for index, color in enumerate(("red", "blue", "green")):
        image(base / f"{index}-pack" / "1.png", color=color)
    sync(client)
    listing = packs(client)["items"]
    a = pack_tag(client, "A", "a")
    b = pack_tag(client, "B", "b")
    for ids, tags, key in (
        ([p["id"] for p in listing], [a["id"]], "all"),
        ([listing[1]["id"]], [b["id"]], "one"),
    ):
        client.patch(
            "/api/v1/pack-tag-links", json={"pack_ids": ids, "tag_ids": tags, "request_id": key}
        )
    assert packs(client, tag_ids=[a["id"], b["id"]])["total"] == 1
    with client.app.state.db.write() as session:
        for pack, completed in ((listing[0], False), (listing[1], True)):
            page = session.scalar(select(PackPage).where(PackPage.pack_id == pack["id"]))
            session.add(PackProgress(pack_id=pack["id"], page_id=page.id, completed=completed))
    assert packs(client, read_state="unread")["items"][0]["id"] == listing[2]["id"]
    assert packs(client, read_state="reading")["items"][0]["id"] == listing[0]["id"]
    assert packs(client, read_state="completed")["items"][0]["id"] == listing[1]["id"]
    children = client.get(
        "/api/v1/directories", params={"kind": "pack", "parent_id": root["directory_id"]}
    ).json()["items"]
    assert len(children) == 3
    assert packs(client, directory_id=children[0]["id"])["total"] == 1
    assert client.get("/api/v1/pack-tags").json()["items"][1]["pack_count"] == 1


def test_jpeg_exif_dimensions_and_unchanged_source_bytes(library):
    client, media = library
    root = pack_root(client, media)
    path = Path(root["path"]) / "rotated" / "1.jpg"
    path.parent.mkdir()
    exif = Image.Exif()
    exif[274] = 6
    Image.new("RGB", (40, 60), "red").save(path, exif=exif)
    original = path.read_bytes()
    sync(client)
    pack = packs(client)["items"][0]
    page = pages(client, pack["id"])["items"][0]
    assert (page["width"], page["height"]) == (60, 40)
    assert client.get(page["image_url"]).content == original
    assert path.read_bytes() == original


def test_pack_first_scan_keeps_ready_video_playable(library, samples, monkeypatch):
    import threading

    from shika.pack_scanner import inspect_image as original

    from .conftest import put
    from .test_backups import wait_task

    client, media = library
    put(samples / "portrait.mp4", media / "video.mp4")
    sync(client)
    video = client.get("/api/v1/videos").json()["items"][0]
    root = pack_root(client, media)
    image(Path(root["path"]) / "pack" / "1.png")
    entered, release = threading.Event(), threading.Event()

    def held(*args):
        entered.set()
        assert release.wait(10)
        return original(*args)

    monkeypatch.setattr("shika.pack_scanner.inspect_image", held)
    time.sleep(0.04)
    task = client.post("/api/v1/scans").json()
    try:
        assert entered.wait(10)
        state = client.get("/api/v1/library-state").json()
        assert state["ready"] and state["media"]["video"]["ready"]
        assert not state["media"]["pack"]["ready"] and state["media"]["pack"]["scanning"]
        assert client.get(video["media_url"], headers={"Range": "bytes=0-19"}).status_code == 206
    finally:
        release.set()
    assert wait_task(client, task["id"])["status"] == "completed"
    assert client.get("/api/v1/library-state").json()["media"]["pack"]["ready"]


def test_500_pages_4k_8k_pagination_and_cached_rescan(library, monkeypatch):
    import json

    client, media = library
    root = pack_root(client, media)
    base = Path(root["path"])
    for index in range(1, 501):
        image(base / "long" / f"{index}.png", size=(24, 36))
    image(base / "large" / "1-4k.png", size=(4000, 6000))
    image(base / "large" / "2-8k.png", size=(8000, 8000))
    started = time.monotonic()
    job = sync(client, timeout=180)
    elapsed = time.monotonic() - started
    catalog = packs(client)
    assert catalog["total"] == 2
    long = next(pack for pack in catalog["items"] if pack["name"] == "long")
    found = [
        page
        for offset in range(0, 500, 100)
        for page in pages(client, long["id"], offset=offset, limit=100)["items"]
    ]
    assert len({page["id"] for page in found}) == 500
    assert [page["name"] for page in found] == [f"{index}.png" for index in range(1, 501)]
    large = next(pack for pack in catalog["items"] if pack["name"] == "large")
    big_pages = pages(client, large["id"])["items"]
    assert [(p["width"], p["height"]) for p in big_pages] == [(4000, 6000), (8000, 8000)]
    for page in (found[0], found[-1], *big_pages):
        assert client.get(page["image_url"]).status_code == 200
        assert client.get(page["thumbnail_url"]).status_code == 200

    def unexpected(*args):
        raise AssertionError("cached 502-page corpus must not decode again")

    monkeypatch.setattr("shika.pack_scanner.inspect_image", unexpected)
    cached_started = time.monotonic()
    cached = sync(client, timeout=30)
    assert cached["result"]["packs"]["unchanged"] == 2
    print(
        json.dumps(
            {
                "fixture": "502 generated PNGs, including 4K/8K",
                "first_scan_seconds": round(elapsed, 3),
                "cached_scan_seconds": round(time.monotonic() - cached_started, 3),
                "peak_decoder_kib": job["result"]["packs"]["progress"]["peak_decoder_kib"],
                "page_count": 502,
                "private_media": False,
            }
        )
    )


def test_directory_mutation_defers_publication_until_a_complete_manifest(library, monkeypatch):
    from shika.pack_scanner import inspect_image as original

    client, media = library
    root = pack_root(client, media)
    base = Path(root["path"]) / "pack"
    image(base / "1.png")
    sync(client)
    pack = packs(client)["items"][0]
    image(base / "2.png", color="blue")
    injected = False

    def mutate(*args):
        nonlocal injected
        if not injected:
            image(base / "3.png", color="green")
            injected = True
        return original(*args)

    monkeypatch.setattr("shika.pack_scanner.inspect_image", mutate)
    time.sleep(0.04)
    job = scan(client)
    assert job["result"]["packs"]["deferred"] == 1
    current = packs(client)["items"][0]
    assert current["page_count"] == 1 and current["content_version"] == pack["content_version"]
    sync(client)
    assert packs(client)["items"][0]["page_count"] == 3


def test_changed_pages_stabilize_together_instead_of_one_page_per_scan(library):
    client, media = library
    root = pack_root(client, media)
    base = Path(root["path"]) / "changed"
    for index in range(4):
        image(base / f"{index}.png")
    sync(client)
    for index in range(4):
        image(base / f"{index}.png", color="blue")

    assert scan(client)["result"]["packs"]["deferred"] == 1
    time.sleep(0.04)
    completed = scan(client)
    assert completed["result"]["packs"]["deferred"] == 0
    assert completed["result"]["packs"]["updated"] == 1
    assert all(
        page["sha256"] == hashlib.sha256((base / page["relative_path"]).read_bytes()).hexdigest()
        for page in pages(client, packs(client)["items"][0]["id"])["items"]
    )


def test_metadata_only_changes_reuse_verified_image_thumbnails(library, monkeypatch):
    client, media = library
    root = pack_root(client, media)
    path = Path(root["path"]) / "same-content" / "1.png"
    image(path)
    sync(client)
    pack = packs(client)["items"][0]
    cached = set((client.app.state.settings.data_dir / "image-thumbnails").iterdir())
    os.utime(path, ns=(path.stat().st_atime_ns, path.stat().st_mtime_ns + 1_000_000))

    def unexpected(*args, **kwargs):
        raise AssertionError("identical verified bytes must reuse their thumbnail")

    monkeypatch.setattr("shika.pack_scanner.inspect_image", unexpected)
    sync(client)
    assert pages(client, pack["id"])["total"] == 1
    assert set((client.app.state.settings.data_dir / "image-thumbnails").iterdir()) == cached
    assert client.get(packs(client)["items"][0]["cover_url"]).status_code == 200


def test_remounted_device_converges_without_redecoding_or_losing_pack_metadata(
    library, monkeypatch
):
    client, media = library
    root = pack_root(client, media)
    for index in range(4):
        image(Path(root["path"]) / "remounted" / f"{index}.png")
    sync(client)
    before = packs(client)["items"][0]
    first = pages(client, before["id"])["items"][0]
    tag = label(client, before["id"])
    with client.app.state.db.write() as session:
        pack = session.get(ImagePack, before["id"])
        pack.device = "previous-device"
        pack.directory_signature = ["previous-device", *pack.directory_signature[1:]]
        session.add(PackProgress(pack_id=pack.id, page_id=first["id"], offset_ratio=0.4))
        for page in session.scalars(select(PackPage).where(PackPage.pack_id == pack.id)):
            page.signature = ["previous-device", *page.signature[1:]]
            observation = session.get(Observation, page.path)
            observation.signature = ["previous-device", *observation.signature[1:]]
    cache = client.app.state.settings.data_dir / "image-thumbnails"
    previous_files = set(cache.iterdir())

    def unexpected(*args, **kwargs):
        raise AssertionError("a remount must not regenerate identical pixels")

    monkeypatch.setattr("shika.pack_scanner.inspect_image", unexpected)
    assert scan(client)["result"]["packs"]["deferred"] == 1
    time.sleep(0.04)
    completed = scan(client)
    assert completed["result"]["packs"]["deferred"] == 0
    current = packs(client)["items"][0]
    assert current["id"] == before["id"] and current["tag_ids"] == [tag["id"]]
    assert current["progress"]["page_id"] == first["id"]
    assert current["progress"]["offset_ratio"] == 0.4
    assert set(cache.iterdir()) == previous_files
    assert sync(client)["result"]["packs"]["unchanged"] == 1


def test_interrupted_staging_is_not_visible_and_recovers_after_restart(environment, monkeypatch):
    from .conftest import connect
    from .test_backups import wait_task

    settings, media = environment
    client, _ = connect(settings)
    try:
        root = pack_root(client, media)
        image(Path(root["path"]) / "old" / "1.png")
        sync(client)
        previous = packs(client)["items"][0]
        label(client, previous["id"])
        image(Path(root["path"]) / "new" / "1.png", color="blue")

        def interrupted(*args):
            raise InterruptedError("injected stop before reconciliation")

        with monkeypatch.context() as patch:
            patch.setattr("shika.pack_scanner.PackScanner.reconcile", interrupted)
            time.sleep(0.04)
            task = client.post("/api/v1/scans").json()
            assert wait_task(client, task["id"])["status"] == "interrupted"
        visible = packs(client)
        assert visible["total"] == 1 and visible["items"][0]["id"] == previous["id"]
        with client.app.state.db.read() as session:
            assert (
                len(
                    list(session.scalars(select(ImagePack).where(ImagePack.status == "discovered")))
                )
                == 1
            )
    finally:
        client.__exit__(None, None, None)
    client, _ = connect(settings)
    try:
        sync(client)
        current = packs(client)
        assert current["total"] == 2
        assert next(pack for pack in current["items"] if pack["id"] == previous["id"])["tag_ids"]
        with client.app.state.db.read() as session:
            assert not list(
                session.scalars(select(ImagePack).where(ImagePack.status == "discovered"))
            )
    finally:
        client.__exit__(None, None, None)


def test_cold_catalog_exposes_completed_pack_while_later_pack_is_inspecting(library, monkeypatch):
    import threading

    from shika.pack_scanner import inspect_image as original

    from .test_backups import wait_task

    client, media = library
    root = pack_root(client, media)
    base = Path(root["path"])
    image(base / "1-ready" / "1.png")
    image(base / "2-held" / "1.png", color="blue")
    calls = 0
    entered, release = threading.Event(), threading.Event()

    def held(*args):
        nonlocal calls
        calls += 1
        if calls == 2:
            entered.set()
            assert release.wait(10)
        return original(*args)

    monkeypatch.setattr("shika.pack_scanner.inspect_image", held)
    time.sleep(0.04)
    task = client.post("/api/v1/scans").json()
    try:
        assert entered.wait(10)
        current = packs(client)
        assert current["total"] == 1 and current["items"][0]["name"] == "1-ready"
        first = current["items"][0]
        page = pages(client, first["id"])["items"][0]
        assert client.get(page["image_url"]).status_code == 200
        label(client, first["id"])
        assert not client.get("/api/v1/library-state").json()["media"]["pack"]["ready"]
    finally:
        release.set()
    assert wait_task(client, task["id"])["status"] == "completed"
    assert packs(client)["total"] == 2
    assert packs(client)["items"][0]["id"] == first["id"]
    assert packs(client)["items"][0]["tag_ids"]


def test_directory_pagination_and_retyping_keeps_legacy_directory_ids(library):
    client, media = library
    base = media / "packs"
    base.mkdir()
    image(base / "pack" / "chapter" / "1.png")
    # The legacy video scan has already indexed these directory identities.
    sync(client)
    legacy = client.get("/api/v1/directories/resolve", params={"path": str(base)}).json()
    root = pack_root(client, media)
    assert root["directory_id"] == legacy["id"]
    sync(client)
    resolved = client.get(
        "/api/v1/directories/resolve", params={"path": str(base), "kind": "pack"}
    ).json()
    assert resolved["id"] == legacy["id"] and resolved["root_id"] == root["id"]
    for index in range(120):
        (base / f"empty-{index}").mkdir()
    sync(client)
    found = []
    for offset in range(0, 121, 25):
        response = client.get(
            "/api/v1/directories",
            params={
                "parent_id": root["directory_id"],
                "kind": "pack",
                "limit": 25,
                "offset": offset,
            },
        )
        assert response.status_code == 200, response.text
        result = response.json()
        assert result["total"] == 121 and len(result["items"]) <= 25
        found.extend(result["items"])
    assert len({directory["id"] for directory in found}) == 121
    assert {directory["root_id"] for directory in found} == {root["id"]}
    assert client.get("/api/v1/directories", params={"limit": 201}).status_code == 422
    schema = client.get("/openapi.json").json()
    operation_ids = [
        operation["operationId"]
        for path in schema["paths"].values()
        for operation in path.values()
        if "operationId" in operation
    ]
    assert len(operation_ids) == len(set(operation_ids))
    assert (
        "image/png"
        in schema["paths"]["/api/v1/pages/{page_id}/image"]["get"]["responses"]["200"]["content"]
    )


@pytest.mark.parametrize("birth_supported", [True, False])
def test_recycled_directory_inode_does_not_adopt_unrelated_pack(
    library, monkeypatch, birth_supported
):
    from shika.directory_identity import directory_stamp
    from shika.paths import open_directory

    if not birth_supported:
        monkeypatch.setattr("shika.directory_identity._statx", None)
    client, media = library
    root = pack_root(client, media)
    base = Path(root["path"])
    image(base / "same" / "1.png")
    sync(client)
    previous = packs(client)["items"][0]
    label(client, previous["id"])
    old_page = pages(client, previous["id"])["items"][0]
    (base / "same").rename(media / "detached-old")
    image(base / "same" / "1.png", color="green")
    with open_directory(base / "same") as fd:
        current = directory_stamp(fd)
    # Deterministically simulate a NAS reusing the old inode for a new directory.
    with client.app.state.db.write() as session:
        old = session.get(ImagePack, previous["id"])
        old.device, old.inode = current[:2]
        stored = list(old.directory_signature)
        stored[:2] = current[:2]
        old.directory_signature = stored
    assert client.get(old_page["image_url"]).status_code == 409
    sync(client)
    new = packs(client)["items"][0]
    assert new["id"] != previous["id"] and not new["tag_ids"]
    assert packs(client, status="missing")["items"][0]["id"] == previous["id"]


def test_empty_pack_identity_is_stable_and_inplace_replacement_keeps_live_directory(library):
    client, media = library
    root = pack_root(client, media)
    base = Path(root["path"])
    (base / "empty").mkdir()
    image(base / "live" / "1.png")
    sync(client)
    empty = packs(client, status="unreadable")["items"][0]
    live = packs(client)["items"][0]
    label(client, live["id"])
    sync(client)
    assert packs(client, status="unreadable")["items"][0]["id"] == empty["id"]
    image(base / "live" / "1.png", color="blue")
    sync(client)
    assert packs(client)["items"][0]["id"] == live["id"]
    assert packs(client)["items"][0]["tag_ids"]


def test_pack_summary_version_and_counts_share_one_read_snapshot(library):
    from sqlalchemy import event

    client, media = library
    root = pack_root(client, media)
    image(Path(root["path"]) / "pack" / "1.png")
    sync(client)
    pack = packs(client)["items"][0]
    db = client.app.state.db
    fired = False

    def mutate(connection, cursor, statement, parameters, context, many):
        nonlocal fired
        if fired or "FROM packs" not in statement or "WHERE packs.id" not in statement:
            return
        fired = True
        with db.write() as session:
            source = session.scalar(select(PackPage).where(PackPage.pack_id == pack["id"]))
            session.add(
                PackPage(
                    pack_id=pack["id"],
                    path=source.path + ".new",
                    relative_path="2.png",
                    ordinal=1,
                    width=source.width,
                    height=source.height,
                    size=source.size,
                    format=source.format,
                    signature=source.signature,
                    sha256=source.sha256,
                )
            )
            session.get(ImagePack, pack["id"]).content_version += 1

    event.listen(db.engine, "after_cursor_execute", mutate)
    try:
        before = client.get(f"/api/v1/packs/{pack['id']}").json()
        assert fired
        assert before["content_version"] == pack["content_version"] and before["page_count"] == 1
    finally:
        event.remove(db.engine, "after_cursor_execute", mutate)
    after = client.get(f"/api/v1/packs/{pack['id']}").json()
    assert after["content_version"] == pack["content_version"] + 1 and after["page_count"] == 2


def test_protected_cached_pages_are_not_evidence_for_a_replacement(library, monkeypatch):
    from shika.directory_identity import directory_stamp
    from shika.paths import open_directory

    monkeypatch.setattr("shika.directory_identity._statx", None)
    client, media = library
    root = pack_root(client, media)
    base = Path(root["path"])
    image(base / "same" / "1.png")
    image(base / "same" / "hidden" / "2.png", color="blue")
    sync(client)
    previous = packs(client)["items"][0]
    hidden_page = pages(client, previous["id"])["items"][1]
    label(client, previous["id"])
    with client.app.state.db.write() as session:
        session.add(PackProgress(pack_id=previous["id"], page_id=hidden_page["id"]))
    response = client.post(
        "/api/v1/roots",
        json={
            "path": str(base / "same" / "hidden"),
            "name": "protected",
            "kind": "pack",
            "enabled": False,
        },
    )
    assert response.status_code == 201
    sync(client)
    (base / "same").rename(media / "detached-old")
    image(base / "same" / "1.png", color="green")
    image(base / "same" / "hidden" / "2.png", color="black")
    with open_directory(base / "same") as fd:
        current = directory_stamp(fd)
    with client.app.state.db.write() as session:
        old = session.get(ImagePack, previous["id"])
        old.device, old.inode = current[:2]
        recorded = list(old.directory_signature)
        recorded[:2] = current[:2]
        old.directory_signature = recorded
    sync(client)
    new = packs(client)["items"][0]
    assert new["id"] != previous["id"] and new["tag_ids"] == []
    with client.app.state.db.read() as session:
        assert list(
            session.scalars(select(PackPage.relative_path).where(PackPage.pack_id == new["id"]))
        ) == ["1.png"]
        assert session.get(PackProgress, previous["id"]).page_id == hidden_page["id"]
        assert session.get(PackPage, hidden_page["id"])


def test_disabled_duplicate_is_ambiguity_evidence_not_a_tag_donor(library):
    client, media = library
    root = pack_root(client, media)
    other = media / "other-packs"
    other.mkdir()
    second = client.post(
        "/api/v1/roots", json={"name": "other", "path": str(other), "kind": "pack"}
    ).json()
    first_path = Path(root["path"]) / "a"
    image(first_path / "1.png")
    image(other / "b" / "1.png")
    sync(client)
    old = next(pack for pack in packs(client)["items"] if pack["name"] == "a")
    label(client, old["id"])
    client.put(
        f"/api/v1/roots/{second['id']}",
        json={"name": second["name"], "path": second["path"], "enabled": False},
    )
    shutil.copytree(other / "b", Path(root["path"]) / "c")
    shutil.rmtree(first_path)
    sync(client)
    current = packs(client)["items"][0]
    assert current["name"] == "c" and current["id"] != old["id"] and not current["tag_ids"]
    assert packs(client, status="missing")["items"][0]["id"] == old["id"]
    with client.app.state.db.read() as session:
        disabled = session.scalar(select(ImagePack).where(ImagePack.name == "b"))
        assert disabled.status == "available"


@pytest.mark.parametrize("unmapped", [False, True])
def test_inaccessible_pack_root_does_not_poison_parent_video_root(library, samples, unmapped):
    from shika.models import Root

    from .conftest import put

    client, media = library
    put(samples / "portrait.mp4", media / "video.mp4")
    sync(client)
    video = client.get("/api/v1/videos").json()["items"][0]
    root = pack_root(client, media)
    image(Path(root["path"]) / "pack" / "1.png")
    if unmapped:
        with client.app.state.db.write() as session:
            stored = session.get(Root, root["id"])
            stored.mount_id, stored.available, stored.error = "", False, "root_unmapped"
    Path(root["path"]).chmod(0)
    try:
        job = sync(client)
        main = next(item for item in job["result"]["roots"] if item["id"] == "main")
        assert main["status"] == "completed"
        assert client.get("/api/v1/library-state").json()["media"]["video"]["ready"]
        assert client.get("/api/v1/videos").json()["total"] == 1
        assert client.get(video["media_url"], headers={"Range": "bytes=0-9"}).status_code == 206
        assert packs(client)["total"] == 0
    finally:
        Path(root["path"]).chmod(0o700)

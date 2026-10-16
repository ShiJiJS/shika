import os
import sqlite3
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace

from .conftest import connect, put, scan


def create_round(client, order="random", scope=None, **extra):
    body = {"request_id": str(uuid.uuid4()), "order": order, "scope": scope or {}, **extra}
    response = client.post("/api/v1/rounds", json=body)
    assert response.status_code == 201, response.text
    return response.json(), body


def move(client, round, video_id=None, finish=False):
    body = {
        "expected_revision": round["revision"],
        **({"video_id": video_id} if video_id else {"finish": finish}),
    }
    response = client.patch(f"/api/v1/rounds/{round['id']}/position", json=body)
    assert response.status_code == 200, response.text
    return response.json()


def test_original_streams_range_mime_and_authorization(library, samples):
    client, media = library
    for sample in samples.iterdir():
        put(sample, media / sample.name)
    scan(client)
    videos = client.get("/api/v1/videos").json()["items"]
    mime = {
        "MP4": "video/mp4",
        "MOV": "video/quicktime",
        "MKV": "video/x-matroska",
        "WEBM": "video/webm",
        "AVI": "video/x-msvideo",
    }
    for video in videos:
        source = (media / video["name"]).read_bytes()
        route = video["media_url"]
        response = client.get(route)
        assert response.status_code == 200 and response.content == source
        assert response.headers["content-type"] == mime[video["type"]]
        assert response.headers["accept-ranges"] == "bytes"
        assert response.headers["content-length"] == str(len(source))
        assert "passphrase" not in route and "token" not in route
        partial = client.get(route, headers={"Range": "bytes=10-99"})
        assert partial.status_code == 206 and partial.content == source[10:100]
        assert partial.headers["content-range"] == f"bytes 10-99/{len(source)}"
        tail = client.get(route, headers={"Range": "bytes=-37"})
        assert tail.status_code == 206 and tail.content == source[-37:]
        head = client.head(route)
        assert head.status_code == 200 and not head.content
        assert head.headers["content-length"] == str(len(source))
        bad = client.get(route, headers={"Range": f"bytes={len(source)}-"})
        assert bad.status_code == 416 and bad.headers["content-range"] == f"bytes */{len(source)}"
        assert client.get(route, headers={"Authorization": ""}).status_code == 401
    route = videos[0]["media_url"]
    multiple = client.get(route, headers={"Range": "bytes=0-9,100-109"})
    assert (
        multiple.status_code == 206 and "multipart/byteranges" in multiple.headers["content-type"]
    )
    assert client.get(route, headers={"Range": "invalid"}).status_code == 400
    assert client.get("/api/v1/videos/not-a-video/stream").status_code == 404
    with ThreadPoolExecutor(max_workers=4) as pool:
        ranges = list(
            pool.map(
                lambda start: client.get(route, headers={"Range": f"bytes={start}-{start + 9}"}),
                range(0, 80, 10),
            )
        )
    assert all(response.status_code == 206 and len(response.content) == 10 for response in ranges)


def test_range_errors_release_descriptors_and_slots(environment, samples):
    settings, media = environment
    settings = replace(settings, media_streams=1)
    put(samples / "h264.mov", media / "one.mov")
    client, _ = connect(settings)
    try:
        scan(client)
        route = client.get("/api/v1/videos").json()["items"][0]["media_url"]
        assert client.get(route, headers={"Range": "bytes=0-4"}).status_code == 206
        before = len(os.listdir("/proc/self/fd"))
        for _ in range(25):
            assert client.get(route, headers={"Range": "bytes=999999999-"}).status_code == 416
            assert client.get(route, headers={"Range": "bytes=0-4"}).status_code == 206
        assert len(os.listdir("/proc/self/fd")) <= before + 2
    finally:
        client.__exit__(None, None, None)


def test_stream_rechecks_changed_missing_and_linked_files(library, samples, tmp_path):
    client, media = library
    path = media / "one.mov"
    put(samples / "h264.mov", path)
    scan(client)
    route = client.get("/api/v1/videos").json()["items"][0]["media_url"]
    with path.open("ab") as output:
        output.write(b"changed")
    response = client.get(route)
    assert response.status_code == 409 and response.json()["error"]["code"] == "media_changed"
    path.unlink()
    assert client.get(route).status_code == 404
    outside = tmp_path / "outside.mov"
    put(samples / "portrait.mp4", outside)
    path.symlink_to(outside)
    assert client.get(route).status_code == 422


def test_random_round_stability_backtracking_and_explicit_exhaustion(library, samples):
    client, media = library
    for i in range(5):
        put(samples / "h264.mov", media / f"{i}.mov")
    scan(client)
    round, body = create_round(client)
    entries = client.get(f"/api/v1/rounds/{round['id']}/entries").json()["items"]
    ids = [e["video"]["id"] for e in entries]
    assert len(ids) == len(set(ids)) == round["candidate_count"] == 5
    assert len(round["window"]) <= 3 and round["current"]["id"] == ids[0]
    assert [
        e["video"]["id"]
        for e in client.get(f"/api/v1/rounds/{round['id']}/entries").json()["items"]
    ] == ids
    assert client.post("/api/v1/rounds", json=body).json()["id"] == round["id"]
    assert (
        client.patch(
            f"/api/v1/rounds/{round['id']}/position",
            json={"expected_revision": round["revision"], "finish": True},
        ).status_code
        == 409
    )
    stale = round
    for index in range(1, len(ids)):
        round = move(client, round, ids[index])
        assert round["position"] == index and round["current"]["id"] == ids[index]
    assert (
        client.patch(
            f"/api/v1/rounds/{round['id']}/position",
            json={"expected_revision": stale["revision"], "video_id": ids[1]},
        ).status_code
        == 409
    )
    round = move(client, round, ids[-2])
    round = move(client, round, ids[-1])
    revision = round["revision"]
    round = move(client, round, finish=True)
    assert round["finished"] and round["current"]["id"] == ids[-1]
    assert (
        client.patch(
            f"/api/v1/rounds/{round['id']}/position",
            json={"expected_revision": revision, "finish": True},
        ).status_code
        == 200
    )
    assert client.get("/api/v1/playback").json()["id"] == round["id"]
    assert client.get("/api/v1/playback").json()["finished"] is True
    assert client.get(round["current"]["media_url"]).status_code == 200
    round = move(client, round, ids[-2])
    assert not round["finished"]


def test_sequential_round_scope_new_files_and_restart(environment, samples):
    settings, media = environment
    for name in ("c.mov", "a.mov", "b.mov"):
        put(samples / "h264.mov", media / "selected" / name)
    put(samples / "portrait.mp4", media / "outside.mp4")
    client, token = connect(settings)
    scan(client)
    root = client.get("/api/v1/roots").json()["items"][0]
    directory = client.get(
        "/api/v1/directories", params={"parent_id": root["directory_id"]}
    ).json()["items"][0]
    scope = {"directory_id": directory["id"], "file_type": "MOV", "orientation": "landscape"}
    round, request = create_round(client, "sequential", scope)
    entries = client.get(f"/api/v1/rounds/{round['id']}/entries").json()["items"]
    assert [e["video"]["name"] for e in entries] == ["a.mov", "b.mov", "c.mov"]
    round = move(client, round, entries[1]["video"]["id"])
    put(samples / "h264.mov", media / "selected" / "d.mov")
    scan(client)
    assert client.get("/api/v1/playback").json()["total"] == 3
    client.__exit__(None, None, None)
    client, _ = connect(settings, token=token)
    restored = client.get("/api/v1/playback").json()
    assert restored["id"] == round["id"] and restored["current"]["id"] == round["current"]["id"]
    assert restored["position"] == 1 and restored["scope"] == round["scope"]
    new_round, _ = create_round(client, "sequential", scope)
    assert new_round["id"] != round["id"] and new_round["total"] == 4
    retry = client.post("/api/v1/rounds", json=request).json()
    assert retry["id"] == round["id"] and retry["active"] is False
    assert client.get("/api/v1/playback").json()["id"] == new_round["id"]
    request["order"] = "random"
    assert client.post("/api/v1/rounds", json=request).status_code == 409
    assert (
        client.patch(
            f"/api/v1/rounds/{round['id']}/position",
            json={"expected_revision": 0, "video_id": entries[0]["video"]["id"]},
        ).status_code
        == 409
    )
    client.__exit__(None, None, None)


def test_unavailable_candidates_and_empty_scope_never_fall_back(library, samples):
    client, media = library
    for name in ("a.mov", "b.mov", "c.mov"):
        put(samples / "h264.mov", media / name)
    scan(client)
    empty, _ = create_round(client, scope={"orientation": "portrait"})
    assert empty["total"] == 0 and empty["current"] is None and empty["finished"]
    round, _ = create_round(client, "sequential")
    first = round["current"]["id"]
    (media / "a.mov").unlink()
    resumed = client.get("/api/v1/playback").json()
    assert resumed["id"] == round["id"] and resumed["current"]["id"] != first
    assert resumed["current"]["name"] == "b.mov"
    scan(client)
    after_scan = client.get("/api/v1/playback").json()
    assert after_scan["total"] == 2 and after_scan["position"] == 0
    for name in ("b.mov", "c.mov"):
        (media / name).unlink()
    scan(client)
    empty = client.get("/api/v1/playback").json()
    assert empty["total"] == 0 and empty["current"] is None and empty["finished"]


def test_expired_media_session_and_scope_validation(environment, samples):
    settings, media = environment
    settings = replace(settings, token_seconds=0.1)
    put(samples / "h264.mov", media / "one.mov")
    client, _ = connect(settings)
    time.sleep(0.12)
    assert client.get("/api/v1/playback").status_code == 401
    client.__exit__(None, None, None)
    settings = replace(settings, token_seconds=100)
    client, _ = connect(settings)
    scan(client)
    video = client.get("/api/v1/videos").json()["items"][0]
    assert (
        client.post(
            "/api/v1/rounds", json={"request_id": "bad", "scope": {"directory_id": "unknown"}}
        ).status_code
        == 404
    )
    assert (
        client.post(
            "/api/v1/rounds", json={"request_id": "bad", "scope": {"directory_id": ""}}
        ).status_code
        == 422
    )
    assert (
        client.post(
            "/api/v1/rounds",
            json={
                "request_id": "bad",
                "scope": {"orientation": "portrait"},
                "anchor_video_id": video["id"],
            },
        ).status_code
        == 422
    )
    assert client.delete("/api/v1/auth/session").status_code == 204
    assert client.get(video["media_url"], headers={"Range": "bytes=0-4"}).status_code == 401
    client.__exit__(None, None, None)


def test_round_filters_persisted_trash_state_before_file_operation_service(environment, samples):
    settings, media = environment
    for name in ("a.mov", "b.mov"):
        put(samples / "h264.mov", media / name)
    client, _ = connect(settings)
    try:
        scan(client)
        round, _ = create_round(client, "sequential")
        recycled = round["current"]
        # S4 owns the physical move. Seed its persisted catalog state here to
        # verify the S2 consumer contract before that producer exists.
        with sqlite3.connect(settings.data_dir / "library.sqlite3") as database:
            database.execute(
                "update videos set status='trash', location_key=NULL where id=?", (recycled["id"],)
            )
        current = client.get("/api/v1/playback").json()
        assert current["total"] == 1 and current["current"]["name"] == "b.mov"
        assert client.get(recycled["media_url"]).status_code == 404
    finally:
        client.__exit__(None, None, None)

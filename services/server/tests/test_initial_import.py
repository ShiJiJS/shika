import threading
import time

from video_viewer import scanner

from .conftest import connect, put, scan


def terminal(client, task_id):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        task = client.get(f"/api/v1/tasks/{task_id}").json()
        if task["status"] in {"completed", "interrupted", "failed"}:
            return task
        time.sleep(0.02)
    raise AssertionError("Scan did not finish")


def gated_probe(monkeypatch, *, interrupt=False):
    original = scanner.inspect_media
    blocked, release = threading.Event(), threading.Event()
    calls = 0

    def probe(*args):
        nonlocal calls
        calls += 1
        if calls == 2:
            blocked.set()
            assert release.wait(15), "Test did not release the media probe"
            if interrupt:
                raise InterruptedError("simulated worker interruption")
        return original(*args)

    monkeypatch.setattr(scanner, "inspect_media", probe)
    return blocked, release, original


def test_first_import_is_browsable_before_completion_and_survives_interruption(
    environment, samples, monkeypatch
):
    settings, media = environment
    put(samples / "portrait.mp4", media / "first.mp4")
    put(samples / "portrait.mp4", media / "second.mp4")
    client, _ = connect(settings)
    blocked, release, original = gated_probe(monkeypatch, interrupt=True)
    try:
        job = client.post("/api/v1/scans").json()
        assert blocked.wait(10)
        assert client.get(f"/api/v1/tasks/{job['id']}").json()["status"] == "running"
        videos = client.get("/api/v1/videos").json()
        assert videos["total"] == 1
        first = videos["items"][0]
        assert client.get(first["thumbnail_url"]).status_code == 200
        stream = client.get(first["media_url"], headers={"Range": "bytes=0-31"})
        assert stream.status_code == 206 and len(stream.content) == 32
        tag = client.post(
            "/api/v1/tags", json={"request_id": "initial-tag", "name": "初次标记"}
        ).json()
        response = client.patch(
            "/api/v1/video-tags",
            json={
                "request_id": "initial-link",
                "video_ids": [first["id"]],
                "tag_ids": [tag["id"]],
                "mode": "add",
            },
        )
        assert response.status_code == 200
        release.set()
        assert terminal(client, job["id"])["status"] == "interrupted"
    finally:
        release.set()
        client.__exit__(None, None, None)
    monkeypatch.setattr(scanner, "inspect_media", original)
    reopened, _ = connect(settings)
    try:
        scan(reopened)
        videos = reopened.get("/api/v1/videos").json()
        assert videos["total"] == 2
        saved = next(v for v in videos["items"] if v["id"] == first["id"])
        assert saved["tag_ids"] == [tag["id"]]
        other = next(v for v in videos["items"] if v["id"] != first["id"])
        assert other["tag_ids"] == []
    finally:
        reopened.__exit__(None, None, None)


def test_existing_library_waits_for_complete_identity_evidence(library, samples, monkeypatch):
    client, media = library
    put(samples / "portrait.mp4", media / "old.mp4")
    scan(client)
    old = client.get("/api/v1/videos").json()["items"][0]
    (media / "old.mp4").rename(media / "renamed.mp4")
    put(samples / "portrait.mp4", media / "duplicate.mp4")
    blocked, release, _ = gated_probe(monkeypatch)
    try:
        job = client.post("/api/v1/scans").json()
        assert blocked.wait(10)
        current = client.get("/api/v1/videos").json()["items"]
        assert len(current) == 1 and current[0]["id"] == old["id"]
        assert current[0]["name"] == "old.mp4"
        release.set()
        assert terminal(client, job["id"])["status"] == "completed"
        current = client.get("/api/v1/videos").json()["items"]
        assert len(current) == 2
        renamed = next(v for v in current if v["name"] == "renamed.mp4")
        duplicate = next(v for v in current if v["name"] == "duplicate.mp4")
        assert renamed["id"] == old["id"]
        assert duplicate["id"] != old["id"]
    finally:
        release.set()

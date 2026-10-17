import threading
import time

from video_viewer import scanner

from .conftest import connect, put, scan
from .test_file_operations import trash
from .test_playback import create_round
from .test_tags import assign, tag


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


def test_first_import_locks_playback_but_keeps_progress_and_survives_interruption(
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
        assert stream.status_code == 409
        state = client.get('/api/v1/library-state').json()
        assert not state['ready'] and state['scanning']
        assert state['progress']['discovered'] == 2
        assert state['progress']['processed'] == 1
        assert state['progress']['bytes_processed'] > 0
        assert state['counts']['imported'] == 1
        assert state['roots'][0]['last_scan'] is None
        partial_round = client.get('/api/v1/playback').json()
        assert partial_round['library_locked'] and partial_round['current'] is None
        assert partial_round['total'] == 0
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
        assert not reopened.get('/api/v1/library-state').json()['ready']
        scan(reopened)
        assert reopened.get('/api/v1/library-state').json()['ready']
        full_round = reopened.get('/api/v1/playback').json()
        assert full_round['total'] == 2 and full_round['id'] != partial_round['id']
        videos = reopened.get("/api/v1/videos").json()
        assert videos["total"] == 2
        saved = next(v for v in videos["items"] if v["id"] == first["id"])
        assert saved["tag_ids"] == [tag["id"]]
        other = next(v for v in videos["items"] if v["id"] != first["id"])
        assert other["tag_ids"] == []
        assert reopened.get(saved['media_url'], headers={'Range': 'bytes=0-31'}).status_code == 206
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
        assert client.get('/api/v1/library-state').json()['ready']
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


def test_ready_index_tags_and_server_trash_survive_replacement(environment, samples):
    settings, media = environment
    put(samples / 'portrait.mp4', media / 'keep.mp4')
    put(samples / 'h264.mov', media / 'discard.mov')
    client, token = connect(settings)
    try:
        scan(client)
        videos = client.get('/api/v1/videos').json()['items']
        marked = tag(client, '保留的标记')['id']
        assign(client, [video['id'] for video in videos], [marked])
        trash(client, [videos[0]['id']])
        before = client.get('/api/v1/trash').json()['items']
        remaining = client.get('/api/v1/videos').json()['items']
        roots = client.get('/api/v1/roots').json()
    finally:
        client.__exit__(None, None, None)
    reopened, _ = connect(settings, token=token)
    try:
        assert reopened.get('/api/v1/library-state').json()['ready']
        assert reopened.get('/api/v1/roots').json() == roots
        assert reopened.get('/api/v1/videos').json()['items'] == remaining
        assert reopened.get('/api/v1/trash').json()['items'] == before
        assert remaining[0]['tag_ids'] == [marked]
    finally:
        reopened.__exit__(None, None, None)


def test_preparation_after_restore_keeps_round_with_historical_trash(library, samples):
    from .test_backups import export, restore

    client, media = library
    for number in range(3):
        put(samples / 'portrait.mp4', media / f'{number}.mp4')
    scan(client)
    active, _ = create_round(client, 'sequential')
    trash(client, [active['current']['id']])
    active = client.get('/api/v1/playback').json()
    raw, _ = export(client)
    restored, _ = restore(client, raw, {'main': str(media)})
    assert restored['status'] == 'completed'
    assert not client.get('/api/v1/library-state').json()['ready']
    scan(client)
    current = client.get('/api/v1/playback').json()
    assert current['id'] == active['id']
    assert current['position'] == active['position']
    assert current['current']['id'] == active['current']['id']

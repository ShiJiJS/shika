import hashlib
import uuid
from concurrent.futures import ThreadPoolExecutor

from .conftest import connect, put, scan
from .test_playback import create_round


def tag(client, name, request_id=None):
    body = {"name": name, "request_id": request_id or str(uuid.uuid4())}
    response = client.post("/api/v1/tags", json=body)
    assert response.status_code == 201, response.text
    return response.json()


def assign(client, videos, tags, mode="add", request_id=None):
    body = {
        "request_id": request_id or str(uuid.uuid4()),
        "video_ids": videos,
        "tag_ids": tags,
        "mode": mode,
    }
    response = client.patch("/api/v1/video-tags", json=body)
    assert response.status_code == 200, response.text
    return response.json(), body


def test_flat_tag_crud_search_names_and_no_automatic_folder_tags(library, samples):
    client, media = library
    digest = put(samples / "h264.mov", media / "不会自动变标签" / "one.mov")
    scan(client)
    assert client.get("/api/v1/tags").json()["total"] == 0
    first = tag(client, "  自然  ")
    assert first["name"] == "自然"
    assert (
        client.post("/api/v1/tags", json={"request_id": "blank", "name": "   "}).status_code == 422
    )
    assert (
        client.post("/api/v1/tags", json={"request_id": "duplicate", "name": "自然"}).status_code
        == 409
    )
    second = tag(client, "风景")
    assert (
        client.get("/api/v1/tags", params={"search": "自"}).json()["items"][0]["id"] == first["id"]
    )
    assert client.get("/api/v1/tags", params={"search": "%"}).json()["total"] == 0
    video = client.get("/api/v1/videos").json()["items"][0]
    assign(client, [video["id"]], [first["id"], second["id"]])
    renamed = client.patch(
        f"/api/v1/tags/{first['id']}", json={"request_id": "rename", "name": "自然美景"}
    )
    assert renamed.status_code == 200 and renamed.json()["id"] == first["id"]
    assert (
        client.patch(
            f"/api/v1/tags/{first['id']}", json={"request_id": "conflict", "name": second["name"]}
        ).status_code
        == 409
    )
    response = client.request(
        "DELETE", f"/api/v1/tags/{first['id']}", json={"request_id": "delete"}
    )
    assert response.status_code == 200
    assert (
        client.request(
            "DELETE", f"/api/v1/tags/{first['id']}", json={"request_id": "delete"}
        ).status_code
        == 200
    )
    assert client.get("/api/v1/videos").json()["items"][0]["tag_ids"] == [second["id"]]
    assert hashlib.sha256((media / "不会自动变标签" / "one.mov").read_bytes()).hexdigest() == digest


def test_batch_set_semantics_retries_and_atomic_validation(library, samples):
    client, media = library
    for name in ("a.mov", "b.mov"):
        put(samples / "h264.mov", media / name)
    scan(client)
    ids = [v["id"] for v in client.get("/api/v1/videos").json()["items"]]
    a, b, c = (tag(client, name)["id"] for name in ("A", "B", "C"))
    result, body = assign(client, ids, [a, a])
    assert result["added"] == 2
    assert client.patch("/api/v1/video-tags", json=body).json() == result
    assert client.patch("/api/v1/video-tags", json={**body, "tag_ids": [b]}).status_code == 409
    assign(client, [ids[0]], [b])
    assign(client, ids, [c])
    assign(client, ids, [a], "remove")
    videos = {v["id"]: set(v["tag_ids"]) for v in client.get("/api/v1/videos").json()["items"]}
    assert videos == {ids[0]: {b, c}, ids[1]: {c}}
    bad = {
        "request_id": "invalid-batch",
        "video_ids": [ids[0], "missing-video"],
        "tag_ids": [a],
        "mode": "replace",
    }
    assert client.patch("/api/v1/video-tags", json=bad).status_code == 404
    bad["video_ids"], bad["tag_ids"] = ids, ["missing-tag"]
    assert client.patch("/api/v1/video-tags", json=bad).status_code == 404
    assert {
        v["id"]: set(v["tag_ids"]) for v in client.get("/api/v1/videos").json()["items"]
    } == videos
    assign(client, [ids[0]], [a], "replace")
    assign(client, [ids[1]], [], "replace")
    videos = {v["id"]: set(v["tag_ids"]) for v in client.get("/api/v1/videos").json()["items"]}
    assert videos == {ids[0]: {a}, ids[1]: set()}


def test_and_filters_share_directory_attributes_pagination_and_rounds(library, samples):
    client, media = library
    put(samples / "h264.mov", media / "selected" / "a.mov")
    put(samples / "h264.mov", media / "selected" / "b.mov")
    put(samples / "portrait.mp4", media / "selected" / "c.mp4")
    put(samples / "h264.mov", media / "outside" / "d.mov")
    scan(client)
    videos = {v["name"]: v for v in client.get("/api/v1/videos").json()["items"]}
    a, b, unused = (tag(client, name)["id"] for name in ("自然", "花卉", "未使用"))
    assign(client, [v["id"] for v in videos.values()], [a])
    assign(client, [videos[n]["id"] for n in ("a.mov", "c.mp4", "d.mov")], [b])
    both = client.get("/api/v1/videos", params=[("tag_ids", a), ("tag_ids", b)])
    assert both.status_code == 200 and both.json()["total"] == 3
    assert client.get(
        "/api/v1/videos", params=[("tag_ids", a), ("tag_ids", b), ("limit", 1)]
    ).json()["items"]
    root = client.get("/api/v1/roots").json()["items"][0]
    children = client.get("/api/v1/directories", params={"parent_id": root["directory_id"]}).json()[
        "items"
    ]
    directory = next(d for d in children if d["name"] == "selected")
    filters = [
        ("tag_ids", a),
        ("tag_ids", b),
        ("directory_id", directory["id"]),
        ("file_type", "MOV"),
        ("orientation", "landscape"),
        ("duration", "short"),
    ]
    listing = client.get("/api/v1/videos", params=filters).json()
    assert listing["total"] == 1 and listing["items"][0]["name"] == "a.mov"
    scope = {
        "tag_ids": [a, b],
        "directory_id": directory["id"],
        "file_type": "MOV",
        "orientation": "landscape",
        "duration": "short",
    }
    round, _ = create_round(client, "sequential", scope)
    assert round["total"] == 1 and round["current"]["id"] == listing["items"][0]["id"]
    empty, _ = create_round(client, scope={"tag_ids": [a, unused]})
    assert empty["total"] == 0 and empty["current"] is None
    assert client.get("/api/v1/videos", params={"tag_ids": "unknown-tag"}).json()["total"] == 0


def test_active_tag_deletion_rebuilds_scope_atomically_and_does_not_move_files(library, samples):
    client, media = library
    original = {media / f"{i}.mov": put(samples / "h264.mov", media / f"{i}.mov") for i in range(3)}
    scan(client)
    ids = [v["id"] for v in client.get("/api/v1/videos").json()["items"]]
    a, b = tag(client, "A")["id"], tag(client, "B")["id"]
    assign(client, ids, [a])
    assign(client, ids[:1], [b])
    round, _ = create_round(client, scope={"tag_ids": [a, b]})
    assert round["total"] == 1
    renamed = client.patch(
        f"/api/v1/tags/{b}", json={"request_id": "rename-active", "name": "renamed"}
    )
    assert renamed.status_code == 200
    assert client.get("/api/v1/playback").json()["id"] == round["id"]
    deleted = client.request("DELETE", f"/api/v1/tags/{b}", json={"request_id": "remove-active"})
    assert deleted.status_code == 200, deleted.text
    current = client.get("/api/v1/playback").json()
    assert (
        current["id"] != round["id"]
        and current["scope"]["tag_ids"] == [a]
        and current["total"] == 3
    )
    later, _ = create_round(client, "sequential", {"tag_ids": [a]})
    assert (
        client.request(
            "DELETE", f"/api/v1/tags/{b}", json={"request_id": "remove-active"}
        ).status_code
        == 200
    )
    assert client.get("/api/v1/playback").json()["id"] == later["id"]
    assert all(
        hashlib.sha256(path.read_bytes()).hexdigest() == digest for path, digest in original.items()
    )


def test_tag_commands_persist_across_restart_and_do_not_resurrect_deleted_tags(
    environment, samples
):
    settings, media = environment
    put(samples / "h264.mov", media / "one.mov")
    client, token = connect(settings)
    scan(client)
    video = client.get("/api/v1/videos").json()["items"][0]
    created = tag(client, "记忆", "create-once")
    result, body = assign(client, [video["id"]], [created["id"]], request_id="assign-once")
    client.__exit__(None, None, None)
    client, _ = connect(settings, token=token)
    try:
        assert client.get("/api/v1/videos").json()["items"][0]["tag_ids"] == [created["id"]]
        assert client.patch("/api/v1/video-tags", json=body).json() == result
        assert client.get("/api/v1/tags").json()["items"][0]["video_count"] == 1
        assert (
            client.request(
                "DELETE", f"/api/v1/tags/{created['id']}", json={"request_id": "delete-once"}
            ).status_code
            == 200
        )
        assert tag(client, "记忆", "create-once")["id"] == created["id"]
        assert client.get("/api/v1/tags").json()["total"] == 0
        assert client.get("/api/v1/videos").json()["items"][0]["tag_ids"] == []
    finally:
        client.__exit__(None, None, None)


def test_concurrent_name_creation_and_association_are_consistent(library, samples):
    client, media = library
    put(samples / "h264.mov", media / "one.mov")
    scan(client)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(
            pool.map(
                lambda i: client.post(
                    "/api/v1/tags", json={"name": "相同名称", "request_id": f"concurrent-{i}"}
                ),
                (1, 2),
            )
        )
    assert sorted(r.status_code for r in results) == [201, 409]
    created = next(r.json() for r in results if r.status_code == 201)
    video_id = client.get("/api/v1/videos").json()["items"][0]["id"]
    body = {
        "request_id": "concurrent-association",
        "video_ids": [video_id],
        "tag_ids": [created["id"]],
        "mode": "add",
    }
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: client.patch("/api/v1/video-tags", json=body), (1, 2)))
    assert all(r.status_code == 200 and r.json()["added"] == 1 for r in results)
    assert client.get("/api/v1/videos").json()["items"][0]["tag_ids"] == [created["id"]]

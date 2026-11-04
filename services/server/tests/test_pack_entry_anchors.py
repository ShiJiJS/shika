"""Pack catalogue return uses the same complete filtered order as its list."""

from shika.models import ImagePack, PackProgress, Root

from .test_media_types import pack_root, pack_tag, seed_pack


def locate(client, anchors, *, fallback=58, **scope):
    response = client.get(
        "/api/v1/packs",
        params={
            "anchor_ids": anchors,
            "offset": fallback,
            "limit": 24,
            **scope,
        },
    )
    assert response.status_code == 200, response.text
    return response.json()


def test_pack_return_neighbor_after_filter_removal_insert_and_clamped_empty(library):
    client, media = library
    root = pack_root(client, media)
    ids = [seed_pack(client, root, f"包{i:03d}") for i in range(73)]
    a, b = pack_tag(client, "交集一", "anchor-a"), pack_tag(client, "交集二", "anchor-b")
    assert (
        client.patch(
            "/api/v1/pack-tag-links",
            json={
                "pack_ids": ids,
                "tag_ids": [a["id"], b["id"]],
                "request_id": "anchor-assign",
            },
        ).status_code
        == 200
    )
    with client.app.state.db.write() as session:
        session.add(PackProgress(pack_id=ids[-1], completed=True))
    scope = {
        "directory_id": root["directory_id"],
        "search": "包",
        "read_state": "unread",
        "tag_ids": [a["id"], b["id"]],
        "sort": "name",
    }
    first = locate(client, [ids[58], ids[59], ids[57]], **scope)
    assert first["total"] == 72 and first["offset"] == 48 and first["anchor_index"] == 58
    assert first["items"][10]["id"] == ids[58] and len(first["items"]) == 24
    assert (
        client.patch(
            "/api/v1/pack-tag-links",
            json={
                "pack_ids": [ids[58]],
                "tag_ids": [b["id"]],
                "mode": "remove",
                "request_id": "anchor-remove",
            },
        ).status_code
        == 200
    )
    neighbor = locate(client, [ids[58], ids[59], ids[57]], **scope)
    assert neighbor["total"] == 71 and neighbor["anchor_index"] == 58
    assert neighbor["items"][10]["id"] == ids[59]
    assert ids[58] not in {p["id"] for p in neighbor["items"]}
    new = seed_pack(client, root, "包-early")
    assert (
        client.patch(
            "/api/v1/pack-tag-links",
            json={
                "pack_ids": [new],
                "tag_ids": [a["id"], b["id"]],
                "request_id": "anchor-new",
            },
        ).status_code
        == 200
    )
    inserted = locate(client, [ids[59]], **scope)
    assert inserted["anchor_index"] == 59 and inserted["offset"] == 48
    assert inserted["items"][11]["id"] == ids[59]
    last = locate(client, ["no-longer-present"], fallback=1000, **scope)
    assert last["anchor_index"] == 71 and last["offset"] == 48
    empty = locate(client, [ids[59]], fallback=58, **{**scope, "search": "不存在%"})
    assert empty["items"] == [] and empty["total"] == 0
    assert empty["anchor_index"] == empty["offset"] == 0
    with client.app.state.db.read() as session:
        assert (
            session.connection().exec_driver_sql("SELECT count(*) FROM pack_sessions").scalar() == 0
        )
        assert (
            session.connection().exec_driver_sql("SELECT count(*) FROM recent_entries").scalar()
            == 0
        )
    with client.app.state.db.write() as session:
        session.get(Root, root["id"]).enabled = False
    assert locate(client, [ids[59]], **scope)["total"] == 0


def test_pack_anchor_sort_contract_auth_and_invalid_directory(library):
    client, media = library
    root = pack_root(client, media)
    ids = [seed_pack(client, root, f"包{i}") for i in range(3)]
    with client.app.state.db.write() as session:
        for i, identity in enumerate(ids):
            session.get(ImagePack, identity).created_at = 100 + i
    result = locate(client, [ids[2]], sort="newest")
    assert result["anchor_index"] == 0 and result["items"][0]["id"] == ids[2]
    assert locate(client, [ids[2]], sort="name")["anchor_index"] == 2
    with client.app.state.db.write() as session:
        session.get(ImagePack, ids[1]).status = "missing"
        session.get(ImagePack, ids[2]).status = "missing"
    previous = locate(client, [ids[1], ids[2], ids[0]], fallback=1)
    assert previous["anchor_index"] == 0 and previous["items"][0]["id"] == ids[0]
    assert (
        client.get(
            "/api/v1/packs", params={"anchor_ids": ids}, headers={"Authorization": ""}
        ).status_code
        == 401
    )
    assert (
        client.get("/api/v1/packs", params={"anchor_ids": ids, "directory_id": "gone"}).status_code
        == 404
    )
    assert (
        client.get("/api/v1/packs", params={"anchor_ids": [str(i) for i in range(17)]}).status_code
        == 422
    )

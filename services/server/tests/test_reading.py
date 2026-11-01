"""Reader interface contracts over real SQLite/auth, never private NAS media."""

from pathlib import Path

from sqlalchemy import func, select

from video_viewer.models import (
    ImagePack,
    PackPage,
    PackPreferences,
    PackProgress,
    Root,
)

from .test_media_types import pack_root, pack_tag, seed_pack
from .test_packs import image, packs, pages, sync


def create(client, **changes):
    response = client.post("/api/v1/pack-sessions", json={"request_id": "session", **changes})
    assert response.status_code == 201, response.text
    return response.json()


def setup(client, media, count=2, page_count=3):
    root = pack_root(client, media)
    ids = [seed_pack(client, root, f"包{i:03d}") for i in range(count)]
    with client.app.state.db.write() as db:
        for identity in ids:
            pack = db.get(ImagePack, identity)
            pack.content_version = 1
            for i in range(1, page_count):
                db.add(
                    PackPage(
                        pack_id=identity,
                        path=f"{pack.path}/{i}.png",
                        relative_path=f"{i}.png",
                        ordinal=i,
                        width=4000,
                        height=8000,
                        size=100,
                        format="PNG",
                    )
                )
    return root, ids


def open_body(value, **changes):
    return {
        "request_id": "open",
        "pack_id": value["current"]["id"],
        "page_id": value["resume"]["page"]["id"],
        "expected_session_revision": value["revision"],
        "expected_revision": value["resume"]["revision"],
        "content_version": value["current"]["content_version"],
        **changes,
    }


def opened(client, value, **changes):
    response = client.post(
        f"/api/v1/pack-sessions/{value['id']}/opened", json=open_body(value, **changes)
    )
    assert response.status_code == 200, response.text
    return response.json()


def progress_body(value, state, **changes):
    return {
        "request_id": "progress",
        "session_id": value["id"],
        "page_id": state["page"]["id"],
        "expected_session_revision": value["revision"],
        "expected_revision": state["revision"],
        "content_version": state["content_version"],
        "offset_ratio": 0.37,
        "completed": False,
        **changes,
    }


def test_complete_fixed_range_survives_filter_edits_new_packs_and_unavailable_members(library):
    client, media = library
    root, ids = setup(client, media, count=27)
    a, b = pack_tag(client, "一", "a"), pack_tag(client, "二", "b")
    client.patch(
        "/api/v1/pack-tag-links",
        json={"pack_ids": ids, "tag_ids": [a["id"], b["id"]], "request_id": "assign"},
    )
    other_path = media / "other-packs"
    other_path.mkdir()
    other = client.post(
        "/api/v1/roots", json={"name": "其他图包", "path": str(other_path), "kind": "pack"}
    ).json()
    outside = seed_pack(client, other, "包outside")
    wrong_name = seed_pack(client, root, "other-name")
    one_tag = seed_pack(client, root, "包one-tag")
    completed = seed_pack(client, root, "包completed")
    assert (
        client.patch(
            "/api/v1/pack-tag-links",
            json={
                "pack_ids": [outside, wrong_name, completed],
                "tag_ids": [a["id"], b["id"]],
                "request_id": "decoys",
            },
        ).status_code
        == 200
    )
    assert (
        client.patch(
            "/api/v1/pack-tag-links",
            json={"pack_ids": [one_tag], "tag_ids": [a["id"]], "request_id": "one-tag"},
        ).status_code
        == 200
    )
    with client.app.state.db.write() as db:
        db.add(PackProgress(pack_id=completed, completed=True))
    query = {
        "directory_id": root["directory_id"],
        "tag_ids": [a["id"], b["id"]],
        "search": "包",
        "read_state": "unread",
    }
    value = create(client, source="tags", scope=query, anchor_pack_id=ids[-1])
    assert value["candidate_count"] == value["available_count"] == 27
    assert value["cursor"] == 26 and value["current"]["id"] == ids[-1]
    assert create(client, source="tags", scope=query, anchor_pack_id=ids[-1])["id"] == value["id"]
    assert (
        client.post(
            "/api/v1/pack-sessions", json={"request_id": "session", "scope": {}}
        ).status_code
        == 409
    )
    client.patch(
        "/api/v1/pack-tag-links",
        json={"pack_ids": ids, "tag_ids": [a["id"]], "mode": "remove", "request_id": "remove"},
    )
    new = seed_pack(client, root, "包new")
    with client.app.state.db.write() as db:
        db.get(ImagePack, ids[-1]).status = "missing"
    entries = client.get(
        f"/api/v1/pack-sessions/{value['id']}/entries", params={"offset": 24, "limit": 3}
    ).json()
    assert entries["total"] == 27 and [row["pack"]["id"] for row in entries["items"]] == ids[24:]
    assert entries["items"][-1]["available"] is False
    latest = client.get(f"/api/v1/pack-sessions/{value['id']}").json()
    assert latest["candidate_count"] == 27 and latest["available_count"] == 26
    assert latest["current"]["id"] == ids[-2] and latest["next"] is None
    assert latest["scope"] == {**query, "tag_ids": sorted(query["tag_ids"])} and latest[
        "source"
    ] == {"kind": "tags", "sort": "name"}
    assert (
        client.patch(
            f"/api/v1/pack-sessions/{value['id']}/position",
            json={"request_id": "outside", "expected_revision": 0, "pack_id": new},
        ).status_code
        == 422
    )
    assert client.get("/api/v1/recent", params={"kind": "pack"}).json()["total"] == 0
    with client.app.state.db.read() as db:
        assert db.scalar(select(func.count()).select_from(PackProgress)) == 1
        assert db.scalar(select(func.count()).select_from(PackPreferences)) == 0
    random_range = create(client, request_id="random", source="tags", scope=query, order="random")
    random_page = client.get(
        f"/api/v1/pack-sessions/{random_range['id']}/entries", params={"limit": 100}
    ).json()
    # Tags were removed above; only the newly inserted pack has no tags either.
    assert random_page["total"] == 0
    unfiltered = create(client, request_id="random-all", order="random")
    first_order = client.get(
        f"/api/v1/pack-sessions/{unfiltered['id']}/entries", params={"limit": 100}
    ).json()
    repeated = create(client, request_id="random-all", order="random")
    assert (
        client.get(f"/api/v1/pack-sessions/{repeated['id']}/entries", params={"limit": 100}).json()
        == first_order
    )
    assert len({row["pack"]["id"] for row in first_order["items"]}) == first_order["total"]


def test_progress_receipts_revisions_current_owner_and_no_preload_history(library):
    client, media = library
    _, ids = setup(client, media)
    value = create(client)
    raw = progress_body(value, value["resume"])
    assert client.patch(f"/api/v1/packs/{ids[0]}/progress", json=raw).status_code == 422
    state = opened(client, value)
    assert opened(client, value) == state and state["revision"] == 1
    assert client.get("/api/v1/recent", params={"kind": "pack"}).json()["total"] == 1
    request = progress_body(value, state)
    path = f"/api/v1/packs/{ids[0]}/progress"
    saved = client.patch(path, json=request)
    assert saved.status_code == 200, saved.text
    assert client.patch(path, json=request).json() == saved.json()
    assert saved.json()["offset_ratio"] == 0.37 and saved.json()["revision"] == 2
    assert client.patch(path, json={**request, "request_id": "late"}).status_code == 409
    assert client.patch(path, json={**request, "offset_ratio": 0.5}).status_code == 409
    other_page = pages(client, ids[1])["items"][0]["id"]
    assert (
        client.patch(
            path,
            json={
                **request,
                "request_id": "foreign",
                "expected_revision": 2,
                "page_id": other_page,
            },
        ).status_code
        == 422
    )
    assert (
        client.patch(
            path,
            json={
                **request,
                "request_id": "version",
                "expected_revision": 2,
                "content_version": 999,
            },
        ).status_code
        == 409
    )
    moved = client.patch(
        f"/api/v1/pack-sessions/{value['id']}/position",
        json={"request_id": "move", "expected_revision": 0, "pack_id": ids[1]},
    ).json()
    assert moved["revision"] == 1 and moved["current"]["id"] == ids[1]
    assert (
        client.patch(
            path, json={**request, "request_id": "old-position", "expected_revision": 2}
        ).status_code
        == 409
    )
    assert client.get("/api/v1/recent", params={"kind": "pack"}).json()["total"] == 1
    opened(client, moved, request_id="open-second")
    assert client.get("/api/v1/recent", params={"kind": "pack"}).json()["total"] == 2
    newer = create(client, request_id="new-session", anchor_pack_id=ids[0])
    assert (
        client.patch(
            path, json={**request, "request_id": "old-session", "expected_revision": 2}
        ).status_code
        == 409
    )
    assert newer["resume"]["offset_ratio"] == 0.37
    assert (
        client.get("/api/v1/pack-reading-requests/progress/progress").json()["result"]
        == saved.json()
    )
    assert (
        client.get("/api/v1/pack-reading-requests/session/session").json()["result"]["id"]
        == value["id"]
    )
    assert (
        client.patch(
            path, json={**request, "request_id": "after-receipt", "expected_revision": 2}
        ).status_code
        == 409
    )
    assert client.get("/api/v1/pack-reading-requests/opened/unknown").status_code == 404
    assert client.get("/api/v1/recent").json()["total"] == 0
    recent = client.get("/api/v1/recent", params={"kind": "pack"}).json()
    assert [p["id"] for p in recent["items"]] == ids[::-1]
    recent_scope = create(client, request_id="recent", source="recent", sort="recent")
    assert recent_scope["current"]["id"] == ids[1] and recent_scope["candidate_count"] == 2
    matching = client.get(
        "/api/v1/packs/selection", params={"source": "recent", "sort": "recent"}
    ).json()
    assert matching["ids"] == ids[::-1]


def test_preferences_and_defaults_are_independent_and_frozen_only_on_actual_open(library):
    client, media = library
    _, ids = setup(client, media)
    value = create(client)
    assert value["resume"]["preferences"]["overridden"] is False
    defaults = {"mode": "vertical", "direction": "rtl", "gap": True, "fit": "width"}
    body = {"values": defaults, "expected_revision": 0, "request_id": "defaults"}
    assert client.patch("/api/v1/reading-defaults", json=body).status_code == 200
    state = opened(client, value)
    assert state["preferences"] == {**defaults, "revision": 0, "overridden": True}
    assert client.patch("/api/v1/reading-defaults", json=body).json()["revision"] == 1
    second = {
        "values": {**defaults, "mode": "horizontal"},
        "expected_revision": 1,
        "request_id": "defaults2",
    }
    assert client.patch("/api/v1/reading-defaults", json=second).status_code == 200
    latest = client.get(f"/api/v1/pack-sessions/{value['id']}").json()
    assert latest["resume"]["preferences"]["mode"] == "vertical"
    prefs = {
        "session_id": value["id"],
        "expected_session_revision": 0,
        "expected_revision": 0,
        "values": {**defaults, "gap": False},
        "request_id": "prefs",
    }
    path = f"/api/v1/packs/{ids[0]}/preferences"
    saved = client.patch(path, json=prefs)
    assert saved.status_code == 200 and saved.json()["revision"] == 1
    assert client.patch(path, json=prefs).json() == saved.json()
    assert client.patch(path, json={**prefs, "request_id": "stale"}).status_code == 409
    moved = client.patch(
        f"/api/v1/pack-sessions/{value['id']}/position",
        json={"request_id": "next", "expected_revision": 0, "pack_id": ids[1]},
    ).json()
    assert (
        moved["resume"]["preferences"]["mode"] == "horizontal"
        and moved["resume"]["preferences"]["overridden"] is False
    )
    assert moved["resume"]["revision"] == 0
    assert client.get("/api/v1/recent", params={"kind": "pack"}).json()["total"] == 1


def test_scan_deleted_resume_page_reports_recovery_then_actual_open_acknowledges(library):
    client, media = library
    root = pack_root(client, media)
    folder = Path(root["path"]) / "scan"
    for i, color in enumerate(["red", "blue", "green"]):
        image(folder / f"{i}.png", color=color)
    sync(client)
    pack = packs(client)["items"][0]
    manifest = pages(client, pack["id"])
    value = create(client)
    state = opened(client, value)
    request = progress_body(value, state, page_id=manifest["items"][1]["id"])
    assert client.patch(f"/api/v1/packs/{pack['id']}/progress", json=request).status_code == 200
    (folder / "1.png").unlink()
    sync(client)
    latest = client.get(f"/api/v1/pack-sessions/{value['id']}").json()
    assert latest["resume"]["recovery_reason"] == "page_removed"
    assert latest["resume"]["page"]["id"] == manifest["items"][2]["id"]
    assert latest["resume"]["offset_ratio"] == 0 and latest["resume"]["revision"] > 2
    assert latest["current"]["content_version"] > pack["content_version"]
    assert opened(client, latest, request_id="reopen")["recovery_reason"] is None
    assert client.get("/api/v1/recent", params={"kind": "pack"}).json()["total"] == 1


def test_bounded_manifest_resume_at_page_500_and_failed_page_fallback(library):
    client, media = library
    _, ids = setup(client, media, count=1, page_count=500)
    value = create(client)
    last = pages(client, ids[0], offset=499, limit=1)["items"][0]
    state = opened(client, value, page_id=last["id"])
    assert state["page_index"] == 499 and state["page"]["width"] == 4000
    with client.app.state.db.write() as db:
        db.get(PackPage, last["id"]).error = "image_corrupt"
    latest = client.get(f"/api/v1/pack-sessions/{value['id']}").json()
    assert (
        latest["resume"]["page_index"] == 498
        and latest["resume"]["recovery_reason"] == "page_unreadable"
    )
    assert pages(client, ids[0], offset=490, limit=10)["total"] == 500
    assert (
        client.get(
            f"/api/v1/pack-sessions/{value['id']}/entries",
            params={"limit": 201},
        ).status_code
        == 422
    )


def test_finished_empty_disabled_auth_and_invalid_input_do_not_expand_range(library):
    client, media = library
    root, ids = setup(client, media)
    value = create(client, anchor_pack_id=ids[-1])
    finish = {"expected_revision": 0, "request_id": "finish", "finish": True}
    result = client.patch(f"/api/v1/pack-sessions/{value['id']}/position", json=finish)
    assert result.status_code == 200 and result.json()["finished"] is True
    assert (
        client.post(
            f"/api/v1/pack-sessions/{value['id']}/opened", json=open_body(value)
        ).status_code
        == 409
    )
    with client.app.state.db.write() as db:
        db.get(Root, root["id"]).enabled = False
    unavailable = client.get(f"/api/v1/pack-sessions/{value['id']}").json()
    assert (
        unavailable["current"] is None
        and unavailable["available_count"] == 0
        and unavailable["candidate_count"] == 2
    )
    empty = create(client, request_id="empty", scope={"search": "nothing"})
    assert empty["candidate_count"] == 0 and empty["finished"]
    for path in [
        "/api/v1/reading-defaults",
        f"/api/v1/pack-sessions/{value['id']}",
        f"/api/v1/pack-sessions/{value['id']}/entries",
    ]:
        assert client.get(path, headers={"Authorization": ""}).status_code == 401
    assert (
        client.post(
            "/api/v1/pack-sessions", json={"request_id": "outside", "anchor_pack_id": ids[0]}
        ).status_code
        == 422
    )
    assert (
        client.post(
            "/api/v1/pack-sessions", json={"request_id": "dir", "scope": {"directory_id": "gone"}}
        ).status_code
        == 404
    )
    assert (
        client.post(
            "/api/v1/pack-sessions", json={"request_id": "bad", "sort": "recent"}
        ).status_code
        == 422
    )
    assert (
        client.patch(
            "/api/v1/reading-defaults",
            json={"request_id": "badprefs", "expected_revision": 0, "values": {"mode": "diagonal"}},
        ).status_code
        == 422
    )
    assert client.get("/api/v1/recent", params={"kind": "pack"}).json()["total"] == 0


def test_restore_write_gate_keeps_reader_state_and_receipts_unchanged(library):
    client, media = library
    _, ids = setup(client, media)
    value = create(client)
    client.app.state.db.maintenance_task = "isolated-restore"
    try:
        assert (
            client.post(
                f"/api/v1/pack-sessions/{value['id']}/opened", json=open_body(value)
            ).status_code
            == 503
        )
        assert (
            client.patch(
                "/api/v1/reading-defaults",
                json={"request_id": "blocked", "expected_revision": 0, "values": {}},
            ).status_code
            == 503
        )
        assert client.get("/api/v1/recent", params={"kind": "pack"}).json()["total"] == 0
    finally:
        client.app.state.db.maintenance_task = None
    state = opened(client, value)
    assert state["revision"] == 1
    assert client.get("/api/v1/packs", params={"read_state": "reading"}).json()["total"] == 1
    body = progress_body(value, state, completed=True, offset_ratio=1)
    result = client.patch(f"/api/v1/packs/{ids[0]}/progress", json=body)
    assert result.status_code == 200 and result.json()["completed"] is True
    assert client.get("/api/v1/packs", params={"read_state": "completed"}).json()["total"] == 1
    assert client.get("/api/v1/packs", params={"read_state": "unread"}).json()["total"] == 1


def test_opening_unavailable_cursor_fallback_commits_position_before_member_reappears(library):
    client, media = library
    _, ids = setup(client, media)
    value = create(client)
    with client.app.state.db.write() as db:
        db.get(ImagePack, ids[0]).status = "missing"
    fallback = client.get(f"/api/v1/pack-sessions/{value['id']}").json()
    assert fallback["current"]["id"] == ids[1] and fallback["revision"] == 0
    state = opened(client, fallback)
    assert state["session_revision"] == 1
    with client.app.state.db.write() as db:
        db.get(ImagePack, ids[0]).status = "available"
    latest = client.get(f"/api/v1/pack-sessions/{value['id']}").json()
    assert latest["current"]["id"] == ids[1] and latest["revision"] == 1
    assert (
        client.patch(
            f"/api/v1/packs/{ids[1]}/progress", json=progress_body(latest, state)
        ).status_code
        == 200
    )


def test_catalog_recent_page_index_uses_manifest_position_and_does_not_write(library):
    client, media = library
    _, ids = setup(client, media, count=1)
    with client.app.state.db.write() as db:
        ordered = db.scalars(
            select(PackPage).where(PackPage.pack_id == ids[0]).order_by(PackPage.ordinal)
        ).all()
        for i, page in enumerate(ordered):
            page.ordinal = (i + 1) * 10
    value = create(client)
    assert value["current"]["progress"] is None
    state = opened(client, value)
    first = client.get(f"/api/v1/packs/{ids[0]}").json()
    assert first["progress"]["page_index"] == 0
    manifest = pages(client, ids[0])
    last_id = manifest["items"][2]["id"]
    saved = client.patch(
        f"/api/v1/packs/{ids[0]}/progress", json=progress_body(value, state, page_id=last_id)
    )
    assert saved.status_code == 200, saved.text
    for path, params in [
        (f"/api/v1/packs/{ids[0]}", {}),
        ("/api/v1/packs", {"source": "recent", "sort": "recent"}),
        ("/api/v1/recent", {"kind": "pack"}),
    ]:
        result = client.get(path, params=params).json()
        row = result["items"][0] if "items" in result else result
        assert row["progress"]["page_index"] == 2
        assert row["progress"]["revision"] == saved.json()["revision"]
    with client.app.state.db.write() as db:
        db.get(PackPage, last_id).path = "/outside-fixture/last.png"
    latest = client.get(f"/api/v1/packs/{ids[0]}").json()
    assert latest["page_count"] == 2
    assert latest["progress"]["page_index"] is None
    assert latest["progress"]["page_id"] == last_id
    assert latest["progress"]["revision"] == saved.json()["revision"]


def test_vertical_default_preserves_existing_global_and_pack_choices(library):
    import json

    from video_viewer.models import Setting

    client, media = library
    _, ids = setup(client, media, count=3)
    defaults = client.get("/api/v1/reading-defaults").json()
    assert defaults == {
        "mode": "vertical",
        "direction": "ltr",
        "gap": False,
        "fit": "contain",
        "revision": 0,
    }
    with client.app.state.db.write() as db:
        db.add(PackPreferences(pack_id=ids[0], mode="horizontal"))
        page = db.scalar(
            select(PackPage).where(PackPage.pack_id == ids[1]).order_by(PackPage.ordinal)
        )
        db.add(PackProgress(pack_id=ids[1], page_id=page.id, offset_ratio=0.37, content_version=1))
    custom = create(client, request_id="custom-mode", anchor_pack_id=ids[0])
    assert custom["resume"]["preferences"]["mode"] == "horizontal"
    assert custom["resume"]["preferences"]["overridden"] is True
    inherited = create(client, request_id="inherited-mode", anchor_pack_id=ids[1])
    assert inherited["resume"]["preferences"]["mode"] == "vertical"
    assert inherited["resume"]["preferences"]["overridden"] is False
    assert inherited["resume"]["offset_ratio"] == 0.37
    with client.app.state.db.write() as db:
        db.add(
            Setting(
                key="reader_defaults",
                value=json.dumps({**defaults, "mode": "horizontal", "revision": 3}),
            )
        )
    assert client.get("/api/v1/reading-defaults").json()["mode"] == "horizontal"
    stored = create(client, request_id="stored-default", anchor_pack_id=ids[2])
    assert stored["resume"]["preferences"]["mode"] == "horizontal"
    with client.app.state.db.read() as db:
        assert db.get(PackProgress, ids[1]).offset_ratio == 0.37
        assert db.get(PackPreferences, ids[1]) is None


def test_reading_preferences_request_omitting_mode_uses_vertical(library):
    client, _ = library
    response = client.patch(
        "/api/v1/reading-defaults",
        json={"values": {"gap": True}, "expected_revision": 0, "request_id": "omitted-mode"},
    )
    assert response.status_code == 200
    assert response.json() == {
        "mode": "vertical",
        "direction": "ltr",
        "gap": True,
        "fit": "contain",
        "revision": 1,
    }

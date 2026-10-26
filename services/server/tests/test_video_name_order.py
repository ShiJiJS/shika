"""Chinese name order is shared by SQL pages, selection and fixed playback."""

from concurrent.futures import ThreadPoolExecutor

from sqlalchemy import select

from video_viewer.models import RecentEntry, Root, Video
from video_viewer.pack_title_order import name_sort_key, title_order_available
from video_viewer.paths import signature

from .conftest import put
from .test_catalog_counts import video
from .test_fixed_preview import begin, entries, reorder


def seed(client, media, names, sample):
    ids = [video(client, media, name) for name in names]
    with client.app.state.db.write() as db:
        db.get(Root, "main").last_scan = 1000
        for identity in ids:
            item = db.get(Video, identity)
            path = media / f"{item.name}.mp4"
            item.sha256 = put(sample, path)
            item.device, item.inode, item.size, item.mtime_ns, item.ctime_ns = signature(path.stat())
    return ids


def listing(client, **params):
    response = client.get("/api/v1/videos", params={"sort": "name", "name_locale": "zh-CN", **params})
    assert response.status_code == 200, response.text
    return response.json()


def test_literal_names_use_chinese_collation_without_pack_presentation():
    assert sorted(["水边的花.mp4", "风里的花园.mp4"], key=name_sort_key) == ["风里的花园.mp4", "水边的花.mp4"]
    assert name_sort_key("作者 NO.001 - 夏日祭.mp4") != name_sort_key("夏日祭.mp4")
    assert name_sort_key("é.mp4") == name_sort_key("e\u0301.mp4")
    values = [f"🌷 风 {i}.mp4" for i in range(24)]
    with ThreadPoolExecutor(max_workers=4) as pool:
        keys = list(pool.map(name_sort_key, values))
    name_sort_key.cache_clear()
    assert keys == [name_sort_key(value) for value in values]
    assert name_sort_key.cache_info().maxsize == 4096


def test_full_pages_anchor_selection_and_fixed_round_keep_one_order(library, samples):
    client, media = library
    names = [f"水边 {i:02d}" for i in range(12, -1, -1)] + [f"风里 {i:02d}" for i in range(13, -1, -1)]
    ids = seed(client, media, names, samples / "portrait.mp4")
    expected = ids[13:][::-1] + ids[:13][::-1]
    all_ids = []
    for offset in (0, 7, 14, 21):
        page = listing(client, offset=offset, limit=7)
        assert page["total"] == 27
        all_ids.extend(v["id"] for v in page["items"])
    assert all_ids == expected and len(set(all_ids)) == 27
    anchor = listing(client, anchor_ids=["removed", expected[25]], limit=7)
    assert anchor["anchor_index"] == 25 and anchor["offset"] == 21
    assert anchor["items"][4]["id"] == expected[25]
    selected = client.get("/api/v1/videos/selection", params={"sort": "name", "name_locale": "zh-CN"}).json()
    assert selected == {"kind": "video", "ids": expected, "total": 27}
    assert client.get("/api/v1/playback", params={"create": "false"}).status_code == 404
    assert client.get("/api/v1/recent").json()["total"] == 0
    value, request = begin(client, sort="name", name_locale="zh-CN", anchor_video_id=expected[25])
    assert value["sort"] == "name" and value["name_locale"] == "zh-CN" and value["candidate_count"] == 27 and value["position"] == 25
    assert client.post("/api/v1/rounds", json=request).json()["id"] == value["id"]
    changed = client.post("/api/v1/rounds", json={k: v for k, v in request.items() if k != "name_locale"})
    assert changed.status_code == 409
    with client.app.state.db.write() as db:
        db.get(Video, expected[0]).name = "最后改名"
    seed(client, media, ["啊新增"], samples / "portrait.mp4")
    assert [r["video"]["id"] for r in entries(client, value)] == expected
    randomized, _ = reorder(client, value, "random")
    restored, _ = reorder(client, randomized, "sequential")
    assert [r["video"]["id"] for r in entries(client, restored)] == expected
    assert restored["current"]["id"] == expected[25]
    assert listing(client)["total"] == 28
    assert client.get("/api/v1/recent").json()["total"] == 0


def test_legacy_defaults_ties_newest_and_recent_keep_their_contracts(library, samples):
    client, media = library
    ids = seed(client, media, ["水边", "风里", "é", "e\u0301"], samples / "portrait.mp4")
    # Canonically equal names resolve by the original path, then stable ID.
    actual = listing(client)["items"]
    assert [v["id"] for v in actual if v["id"] in ids[2:]] == [ids[3], ids[2]]
    with client.app.state.db.write() as db:
        for i, identity in enumerate(ids):
            db.get(Video, identity).created_at = i + 10
        db.add_all([RecentEntry(kind="video", video_id=ids[0], opened_at=200),
                    RecentEntry(kind="video", video_id=ids[1], opened_at=100)])
    def listed(**params):
        return [v["id"] for v in client.get("/api/v1/videos", params=params).json()["items"]]
    assert listed(sort="name") == [ids[3], ids[2], ids[0], ids[1]]
    assert listed() == [ids[3], ids[2], ids[0], ids[1]]
    assert listed(sort="newest") == ids[::-1]
    assert listed(source="recent", sort="recent") == ids[:2]
    assert listed(source="recent", sort="name", name_locale="zh-CN") == [ids[1], ids[0]]
    assert listing(client, source="tags", search="风")["items"][0]["id"] == ids[1]
    assert client.get("/api/v1/videos", params={"sort": "recent"}).status_code == 422
    legacy, _ = begin(client, sort="name")
    assert legacy["sort"] == "name" and [r["video"]["id"] for r in entries(client, legacy)] == [ids[3], ids[2], ids[0], ids[1]]


def test_missing_icu_does_not_advertise_or_accept_new_order(library, monkeypatch, samples):
    client, media = library
    seed(client, media, ["水边", "风里"], samples / "portrait.mp4")
    with monkeypatch.context() as missing:
        missing.setattr("video_viewer.pack_title_order.ctypes.util.find_library", lambda _: None)
        title_order_available.cache_clear()
        try:
            assert "video_name_order" not in client.get("/api/v1/info").json()["capabilities"]
            assert client.get("/api/v1/videos").json()["total"] == 2
            assert client.get("/api/v1/videos", params={"sort": "name"}).status_code == 200
            for route in ["videos", "videos/selection"]:
                response = client.get(f"/api/v1/{route}", params={"sort": "name", "name_locale": "zh-CN"})
                assert response.status_code == 503 and response.json()["error"]["code"] == "video_name_order_unavailable"
            response = client.post("/api/v1/rounds", json={"request_id": "missing-icu", "membership": "fixed", "sort": "name", "name_locale": "zh-CN"})
            assert response.status_code == 503
            with client.app.state.db.read() as db:
                assert not list(db.scalars(select(RecentEntry)))
            assert client.get("/api/v1/playback", params={"create": "false"}).status_code == 404
        finally:
            title_order_available.cache_clear()


def test_locale_is_optional_without_expanding_the_public_sort_enum(library):
    client, _ = library
    assert "video_name_order" in client.get("/api/v1/info").json()["capabilities"]
    for route in ["videos", "videos/selection"]:
        for params in [{"sort": "name_zh"}, {"sort": "name", "name_locale": "not-supported"},
                       {"sort": "newest", "name_locale": "zh-CN"}]:
            assert client.get(f"/api/v1/{route}", params=params).status_code == 422
    for body in [{"sort": "name_zh"}, {"sort": "newest", "name_locale": "zh-CN"},
                 {"sort": "name", "name_locale": "zh-CN", "membership": "legacy"}]:
        assert client.post("/api/v1/rounds", json={"request_id": "invalid", "membership": "fixed", **body}).status_code == 422

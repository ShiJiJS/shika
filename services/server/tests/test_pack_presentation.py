"""Display labels and full-range Chinese ordering over disposable metadata."""

from concurrent.futures import ThreadPoolExecutor

import pytest

from shika.models import ImagePack
from shika.pack_presentation import presentation
from shika.pack_title_order import title_order_available, title_sort_key

from .test_media_types import pack_root, seed_pack
from .test_reading import create


@pytest.mark.parametrize(
    "name,title,author,number",
    [
        ("示例作者 NO.034 - 夏日祭", "夏日祭", "示例作者", "034"),
        ("[作者 A] no.001 – 晚风 - 外景", "晚风 - 外景", "作者 A", "001"),
        ("【作者】 NO．09 — 🌷 春日", "🌷 春日", "作者", "09"),
        ("作者　NO.10 - 中文空格", "中文空格", "作者", "10"),
        ("普通目录 - 海边", "普通目录 - 海边", None, None),
        ("[4K] 风景", "[4K] 风景", None, None),
        ("2026-01-01 写真", "2026-01-01 写真", None, None),
        ("作者 NO.1 - ", "作者 NO.1 - ", None, None),
        ("NO.01 - 无作者", "NO.01 - 无作者", None, None),
        ("作者 NO.123456789 - 超长编号", "作者 NO.123456789 - 超长编号", None, None),
        ("作者 NO.1 - 第一行\n第二行", "作者 NO.1 - 第一行\n第二行", None, None),
        ("[] NO.1 - 空作者", "[] NO.1 - 空作者", None, None),
    ],
)
def test_conservative_presentation(name, title, author, number):
    value = presentation(name)
    assert (value.title, value.author, value.number) == (title, author, number)


def test_chinese_order_keys_unicode_case_accents_and_threads():
    # Frozen reference uses localeCompare('zh-CN'), not Unicode code points.
    expected = ["加藤惠 - 和服", "夏日祭", "新年快乐", "原野上的浪漫"]
    assert sorted(reversed(expected), key=title_sort_key) == expected
    assert title_sort_key("示例作者 NO.034 - 夏日祭") == title_sort_key("夏日祭")
    assert title_sort_key("é") == title_sort_key("e\u0301")
    # Each newly used worker creates its own collator, including non-BMP text.
    values = [f"{i} 🌷 夏日祭" for i in range(32)]
    with ThreadPoolExecutor(max_workers=4) as pool:
        first = list(pool.map(title_sort_key, values))
    title_sort_key.cache_clear()
    assert first == [title_sort_key(value) for value in values]
    assert title_sort_key.cache_info().maxsize == presentation.cache_info().maxsize == 4096


def test_missing_runtime_is_not_advertised_and_legacy_catalog_stays_available(library, monkeypatch):
    client, media = library
    root = pack_root(client, media)
    seed_pack(client, root, "作者 NO.1 - 夏日祭")
    with monkeypatch.context() as missing:
        missing.setattr("shika.pack_title_order.ctypes.util.find_library", lambda _: None)
        title_order_available.cache_clear()
        try:
            assert "pack_presentation" not in client.get("/api/v1/info").json()["capabilities"]
            assert client.get("/api/v1/packs").json()["total"] == 1
            assert client.get("/api/v1/packs", params={"sort": "title"}).status_code == 503
        finally:
            title_order_available.cache_clear()


def listing(client, **params):
    r = client.get("/api/v1/packs", params={"sort": "title", **params})
    assert r.status_code == 200, r.text
    return r.json()


def test_summary_title_search_detail_and_reading_preserve_raw_identity(library):
    client, media = library
    root = pack_root(client, media)
    name = "作者甲 NO.034 - 夏日祭"
    identity = seed_pack(client, root, name)
    unknown = seed_pack(client, root, "[4K] 未知来源")
    value = listing(client, search="作者甲")["items"][0]
    assert value["id"] == identity and value["name"] == name
    assert value["path"] == f"{root['path']}/{name}"
    assert (value["title"], value["author"], value["number"]) == ("夏日祭", "作者甲", "034")
    assert listing(client, search="夏日祭")["items"][0] == value
    assert client.get(f"/api/v1/packs/{identity}").json() == value
    fallback = client.get(f"/api/v1/packs/{unknown}").json()
    assert fallback["title"] == fallback["name"] and fallback["author"] is None
    assert fallback["number"] is None
    reading = create(client, sort="title", anchor_pack_id=identity)
    assert reading["current"] == value
    assert reading["source"]["sort"] == "title"
    assert client.get("/api/v1/recent", params={"kind": "pack"}).json()["total"] == 0


def test_title_order_across_pages_anchor_selection_and_fixed_reading(library):
    client, media = library
    root = pack_root(client, media)
    # Raw author/volume order is deliberately opposite to display order.
    names = [f"作者 {28 - i:02d} NO.{28 - i:03d} - 晚风 {i:02d}" for i in range(28)]
    ids = [seed_pack(client, root, name) for name in names]
    title_ids = []
    for offset in (0, 7, 14, 21):
        page = listing(client, offset=offset, limit=7)
        assert page["total"] == 28
        title_ids += [item["id"] for item in page["items"]]
    assert title_ids == ids and len(set(title_ids)) == 28
    # Legacy/default name requests retain the original folder-name ordering.
    assert [p["id"] for p in listing(client, sort="name", limit=100)["items"]] == ids[::-1]
    assert [
        p["id"] for p in client.get("/api/v1/packs", params={"limit": 100}).json()["items"]
    ] == ids[::-1]
    anchor = listing(client, anchor_ids=[ids[25]], limit=7)
    assert anchor["anchor_index"] == 25 and anchor["offset"] == 21
    assert anchor["items"][4]["id"] == ids[25]
    selected = client.get("/api/v1/packs/selection", params={"sort": "title"}).json()
    assert selected == {"kind": "pack", "ids": ids, "total": 28}
    value = create(client, sort="title", anchor_pack_id=ids[25])
    assert value["cursor"] == 25 and value["candidate_count"] == 28
    with client.app.state.db.write() as db:
        db.get(ImagePack, ids[0]).name = "作者 NO.999 - 最后"
    seed_pack(client, root, "作者 NO.000 - 最先")
    entries = client.get(
        f"/api/v1/pack-sessions/{value['id']}/entries", params={"limit": 100}
    ).json()
    assert [e["pack"]["id"] for e in entries["items"]] == ids
    assert entries["total"] == 28
    assert listing(client)["total"] == 29


def test_chinese_ties_and_newest_recent_remain_independent(library):
    client, media = library
    root = pack_root(client, media)
    names = [
        "作者 NO.004 - 原野上的浪漫",
        "作者 NO.003 - 新年快乐",
        "作者 NO.002 - 夏日祭",
        "作者 NO.001 - 加藤惠 - 和服",
    ]
    ids = [seed_pack(client, root, name) for name in names]
    other = seed_pack(client, root, "另一作者 NO.010 - 夏日祭")
    order = [p["id"] for p in listing(client)["items"]]
    assert order == [ids[3], *sorted([ids[2], other]), ids[1], ids[0]]
    with client.app.state.db.write() as db:
        db.get(ImagePack, other).created_at = 0
        for i, identity in enumerate(ids):
            db.get(ImagePack, identity).created_at = i + 10
    assert listing(client, sort="newest")["items"][0]["id"] == ids[3]
    assert client.get("/api/v1/packs", params={"sort": "recent"}).status_code == 422
    assert listing(client, sort="recent", source="recent")["total"] == 0

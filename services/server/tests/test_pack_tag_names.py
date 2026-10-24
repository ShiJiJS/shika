"""Pack cards and selected labels resolve names independently of label pages."""

from .test_media_types import pack_root, pack_tag, seed_pack
from .test_tags import tag


def test_pack_label_names_beyond_first_page_rename_delete_and_namespace(library):
    client, media = library
    root = pack_root(client, media)
    identity = seed_pack(client, root)
    labels = [pack_tag(client, f"标签{i:02d}", f"pack-name-{i}") for i in range(61)]
    video_label = tag(client, "标签60", "video-name")
    first = client.get("/api/v1/pack-tags", params={"limit": 50}).json()
    assert labels[-1]["id"] not in {row["id"] for row in first["items"]}
    body = {"pack_ids": [identity], "tag_ids": [labels[5]["id"], labels[-1]["id"]], "request_id": "names-assign"}
    assert client.patch("/api/v1/pack-tag-links", json=body).status_code == 200
    params = {"tag_ids": [labels[-1]["id"], video_label["id"], "gone"]}
    response = client.get("/api/v1/pack-tags/resolve", params=params)
    assert response.status_code == 200, response.text
    result = response.json()
    assert result["kind"] == "pack"
    assert result["items"] == [labels[-1]]
    assert set(result["missing_ids"]) == {video_label["id"], "gone"}
    expected = {labels[5]["id"]: "标签05", labels[-1]["id"]: "标签60"}
    assert client.get(f"/api/v1/packs/{identity}").json()["tag_names"] == expected
    assert client.get("/api/v1/packs").json()["items"][0]["tag_names"] == expected
    assert client.patch(f"/api/v1/pack-tags/{labels[-1]['id']}", json={"name": "新名称", "request_id": "names-rename"}).status_code == 200
    renamed = client.get("/api/v1/pack-tags/resolve", params=params).json()
    assert renamed["items"][0]["name"] == "新名称"
    assert client.get(f"/api/v1/packs/{identity}").json()["tag_names"][labels[-1]["id"]] == "新名称"
    assert client.request("DELETE", f"/api/v1/pack-tags/{labels[-1]['id']}", json={"request_id": "names-delete"}).status_code == 200
    assert labels[-1]["id"] in client.get("/api/v1/pack-tags/resolve", params=params).json()["missing_ids"]
    assert client.get(f"/api/v1/packs/{identity}").json()["tag_names"] == {labels[5]["id"]: "标签05"}
    assert client.get("/api/v1/tags").json()["items"][0]["name"] == "标签60"


def test_pack_name_resolution_requires_auth_bounded_input_and_reports_missing(library):
    client, _ = library
    assert client.get("/api/v1/pack-tags/resolve", headers={"Authorization": ""}, params={"tag_ids": ["a"]}).status_code == 401
    assert client.get("/api/v1/pack-tags/resolve").status_code == 422
    assert client.get("/api/v1/pack-tags/resolve", params={"tag_ids": [str(i) for i in range(257)]}).status_code == 422
    response = client.get("/api/v1/pack-tags/resolve", params={"tag_ids": ["a", "a", "b"]})
    assert response.status_code == 200
    assert response.json() == {"kind": "pack", "items": [], "missing_ids": ["a", "b"]}

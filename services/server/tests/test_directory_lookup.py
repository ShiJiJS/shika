from .conftest import put, scan


def test_stable_directory_lookup_scoped_resolution_and_availability(library, samples):
    client, media = library
    put(samples / "h264.mov", media / "inner" / "deep" / "one.mov")
    scan(client)
    route = "/api/v1/directories/resolve"
    found = client.get(route, params={"path": str(media / "inner" / "deep")})
    assert found.status_code == 200, found.text
    directory = found.json()
    assert directory["available"] and directory["path"] == str(media / "inner" / "deep")
    assert client.get(f"/api/v1/directories/{directory['id']}").json() == directory
    assert client.get(route, params={"path": "/etc"}).status_code == 422
    assert client.get(route, params={"path": str(media / "absent")}).status_code == 404
    assert (
        client.get(
            f"/api/v1/directories/{directory['id']}", headers={"Authorization": ""}
        ).status_code
        == 401
    )
    disconnected = media.with_name("detached")
    media.rename(disconnected)
    try:
        scan(client)
        unavailable = client.get(f"/api/v1/directories/{directory['id']}").json()
        assert unavailable["available"] is False and unavailable["error"] == "root_unavailable"
    finally:
        disconnected.rename(media)
    (media / "inner").rename(media / "renamed")
    scan(client)
    assert client.get(f"/api/v1/directories/{directory['id']}").status_code == 404
    assert client.get(route, params={"path": str(media / "renamed" / "deep")}).json()["available"]

from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace

from fastapi.testclient import TestClient
from sqlalchemy import select

from shika.app import create_app
from shika.models import AccessToken, Setting

from .conftest import connect

OLD = "old-isolated-passphrase"
NEW = "new-isolated-passphrase"


def authorize(client, receipt):
    client.headers["Authorization"] = "Bearer " + receipt["access_token"]


def test_first_connection_claims_once_and_persists_without_a_secret_file(environment):
    settings, _ = environment
    settings = replace(settings, passphrase="")
    with TestClient(create_app(settings)) as client:
        assert client.get("/api/v1/auth/status").json() == {"initialized": False}
        assert client.get("/api/v1/info").status_code == 401
        assert (
            client.post("/api/v1/auth/login", json={"passphrase": NEW}).json()["error"]["code"]
            == "setup_required"
        )
        invalid = client.post("/api/v1/auth/setup", json={"passphrase": "short"})
        assert invalid.status_code == 422 and "short" not in invalid.text
        result = client.post("/api/v1/auth/setup", json={"passphrase": NEW})
        assert result.status_code == 201, result.text
        receipt = result.json()
        authorize(client, receipt)
        server_id = client.get("/api/v1/info").json()["server_id"]
        assert client.get("/api/v1/auth/status").json() == {"initialized": True}
        assert client.post("/api/v1/auth/setup", json={"passphrase": OLD}).status_code == 409
        with client.app.state.db.read() as session:
            assert NEW not in session.get(Setting, "passphrase_hash").value
    with TestClient(create_app(settings)) as client:
        authorize(client, receipt)
        assert client.get("/api/v1/info").json()["server_id"] == server_id
        assert client.post("/api/v1/auth/login", json={"passphrase": NEW}).status_code == 200


def test_rotation_rejects_wrong_current_preserves_self_and_revokes_every_old_session(environment):
    settings, _ = environment
    settings = replace(settings, passphrase=OLD)
    client, token = connect(settings)
    try:
        other = client.post("/api/v1/auth/login", json={"passphrase": OLD}).json()["access_token"]
        bad = client.post(
            "/api/v1/auth/passphrase", json={"current_passphrase": "wrong", "new_passphrase": NEW}
        )
        assert bad.status_code == 422
        assert client.get("/api/v1/info").status_code == 200
        assert (
            client.post(
                "/api/v1/auth/passphrase",
                json={"current_passphrase": OLD, "new_passphrase": "short"},
            ).status_code
            == 422
        )
        response = client.post(
            "/api/v1/auth/passphrase", json={"current_passphrase": OLD, "new_passphrase": NEW}
        )
        assert response.status_code == 200, response.text
        receipt = response.json()
        for old in (token, other):
            assert (
                client.get("/api/v1/info", headers={"Authorization": "Bearer " + old}).status_code
                == 401
            )
        authorize(client, receipt)
        assert client.get("/api/v1/info").status_code == 200
        assert client.post("/api/v1/auth/login", json={"passphrase": OLD}).status_code == 401
        assert client.post("/api/v1/auth/login", json={"passphrase": NEW}).status_code == 200
    finally:
        client.__exit__(None, None, None)
    # Leaving an old read-only seed mounted must not reset the user's new secret.
    with TestClient(create_app(settings)) as client:
        authorize(client, receipt)
        assert client.get("/api/v1/info").status_code == 200
        assert client.post("/api/v1/auth/login", json={"passphrase": NEW}).status_code == 200
    # Deliberately changing that seed still provides an operator recovery path.
    with TestClient(create_app(replace(settings, passphrase="operator-recovery-secret"))) as client:
        authorize(client, receipt)
        assert client.get("/api/v1/info").status_code == 401
        assert (
            client.post(
                "/api/v1/auth/login", json={"passphrase": "operator-recovery-secret"}
            ).status_code
            == 200
        )


def test_legacy_hash_migration_keeps_existing_tokens(environment):
    settings, _ = environment
    client, token = connect(settings)
    with client.app.state.db.write() as session:
        session.delete(session.get(Setting, "configured_passphrase_hash"))
    client.__exit__(None, None, None)
    client, _ = connect(settings, token=token)
    try:
        assert client.get("/api/v1/info").status_code == 200
        assert client.post("/api/v1/auth/setup", json={"passphrase": NEW}).status_code == 409
    finally:
        client.__exit__(None, None, None)


def test_simultaneous_first_setup_cannot_replace_the_winner(environment):
    settings, _ = environment
    with TestClient(create_app(replace(settings, passphrase=""))) as client:
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(
                pool.map(
                    lambda value: client.post("/api/v1/auth/setup", json={"passphrase": value}),
                    (OLD, NEW),
                )
            )
        assert sum(r.status_code == 201 for r in results) == 1
        assert all(r.status_code in (201, 409, 429) for r in results)
        winner = OLD if results[0].status_code == 201 else NEW
        assert client.post("/api/v1/auth/login", json={"passphrase": winner}).status_code == 200


def test_login_verified_before_a_rotation_cannot_mint_an_old_secret_session(library, monkeypatch):
    client, _ = library
    auth, db = client.app.state.auth, client.app.state.db
    original = auth.matches

    def rotated(encoded, supplied):
        result = original(encoded, supplied)
        with db.write() as session:
            session.get(Setting, "passphrase_hash").value = auth.hasher.hash(NEW)
            for token in session.scalars(select(AccessToken)):
                session.delete(token)
        return result

    monkeypatch.setattr(auth, "matches", rotated)
    response = client.post(
        "/api/v1/auth/login", json={"passphrase": client.app.state.settings.passphrase}
    )
    assert response.status_code == 401
    with db.read() as session:
        assert list(session.scalars(select(AccessToken))) == []

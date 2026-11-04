import json

import pytest

from shika.models import Setting

from .conftest import connect
from .test_backups import export, restore
from .test_playback import create_round


def change(client, request_id="default-1", revision=0, order="sequential"):
    return client.patch(
        "/api/v1/playback-defaults",
        json={
            "request_id": request_id,
            "expected_revision": revision,
            "order": order,
        },
    )


def test_defaults_do_not_change_current_round_and_only_receipt_is_replayed(library):
    client, _ = library
    active, _ = create_round(client, "random")
    before = client.get("/api/v1/playback").json()
    assert client.get("/api/v1/playback-defaults").json() == {"order": "random", "revision": 0}
    saved = change(client)
    assert saved.status_code == 200 and saved.json() == {"order": "sequential", "revision": 1}
    assert change(client).json() == saved.json()
    assert change(client, order="random").json()["error"]["code"] == "idempotency_conflict"
    assert change(client, "other").json()["error"]["code"] == "playback_defaults_changed"
    receipt = client.get("/api/v1/playback-default-requests/default-1").json()
    assert receipt == {"status": "completed", "result": saved.json()}
    assert client.get("/api/v1/playback-default-requests/missing").status_code == 404
    assert client.get("/api/v1/playback").json() == before
    assert before["id"] == active["id"]


def test_old_round_adopted_once_and_survives_restart(environment):
    settings, _ = environment
    client, token = connect(settings)
    create_round(client, "sequential")
    # An old installation has no dedicated default; preserve its legacy order
    # at service upgrade, before a client can create a different round.
    with client.app.state.db.write() as session:
        session.delete(session.get(Setting, "playback_defaults"))
    client.__exit__(None, None, None)
    client, _ = connect(settings, token=token)
    try:
        assert client.get("/api/v1/playback-defaults").json() == {
            "order": "sequential",
            "revision": 0,
        }
        create_round(client, "random")
        assert client.get("/api/v1/playback-defaults").json()["order"] == "sequential"
        assert change(client, "chosen", order="random").status_code == 200
    finally:
        client.__exit__(None, None, None)
    client, _ = connect(settings, token=token)
    try:
        assert client.get("/api/v1/playback-defaults").json() == {"order": "random", "revision": 1}
    finally:
        client.__exit__(None, None, None)


@pytest.mark.parametrize(
    "field,value", [("order", "other"), ("expected_revision", -1), ("unknown", True)]
)
def test_defaults_validation_and_auth(library, field, value):
    client, _ = library
    body = {"request_id": "bad", "expected_revision": 0, "order": "random", field: value}
    assert client.patch("/api/v1/playback-defaults", json=body).status_code == 422
    client.headers.pop("Authorization")
    assert client.get("/api/v1/playback-defaults").status_code == 401
    assert client.patch("/api/v1/playback-defaults", json=body).status_code == 401


@pytest.mark.parametrize("key", ["reader_defaults", "playback_defaults"])
def test_legacy_backup_cannot_silently_omit_explicit_defaults(library, key):
    client, _ = library
    with client.app.state.db.write() as session:
        row = session.get(Setting, key)
        if row:
            row.value = json.dumps({"order": "random", "revision": 1}, separators=(",", ":"))
        else:
            session.add(Setting(key=key, value='{"revision":1}'))
    response = client.post("/api/v1/backups", json={"request_id": "unsafe"})
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "backup_upgrade_required"


def test_v1_restore_reseeds_implicit_default_from_imported_round(library):
    client, _ = library
    create_round(client, "sequential")
    raw, _ = export(client)
    create_round(client, "random")
    roots = client.get("/api/v1/roots").json()["items"]
    restored, _ = restore(client, raw, {root["id"]: root["path"] for root in roots})
    assert restored["status"] == "completed", restored
    assert client.get("/api/v1/playback-defaults").json() == {"order": "sequential", "revision": 0}

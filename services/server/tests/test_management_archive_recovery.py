"""Kill actual HTTP workers before and after the v2 replacement transaction."""

import hashlib
import json
import os
import socket
import subprocess
import sys
import time

import httpx
import pytest

from .conftest import put, scan
from .test_backups import wait_task
from .test_management_archives import PREFIX, export, inspect
from .test_tags import tag


@pytest.mark.parametrize(
    "phase", ["snapshot_written", "after_replace_before_commit", "restore_committed"]
)
def test_sigkill_v2_restore_preserves_one_commit_and_original_control_ledger(
    environment, samples, phase
):
    settings, media = environment
    digest = put(samples / "h264.mov", media / "one.mov")
    parent = settings.data_dir.parent
    config, secret, marker = parent / "mounts.json", parent / "passphrase", parent / "checkpoint"
    config.write_text(json.dumps([{"id": "main", "name": "isolated", "path": str(media)}]))
    secret.write_text(settings.passphrase)
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    env = {
        **os.environ,
        "VV_DATA_DIR": str(settings.data_dir),
        "VV_MOUNTS_FILE": str(config),
        "VV_PASSPHRASE_FILE": str(secret),
        "VV_SCAN_INTERVAL": "0",
        "VV_STABILITY_SECONDS": "0.02",
        "TEST_BACKUP_PHASE": phase,
        "TEST_BACKUP_MARKER": str(marker),
    }

    def start(factory):
        server = subprocess.Popen(
            [
                sys.executable,
                "-m",
                "uvicorn",
                factory,
                "--factory",
                "--host",
                "127.0.0.1",
                "--port",
                str(port),
                "--no-access-log",
            ],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            assert server.poll() is None, "isolated v2 server stopped"
            try:
                if httpx.get(f"http://127.0.0.1:{port}/health", timeout=1).status_code == 200:
                    return server
            except httpx.TransportError:
                pass
            time.sleep(0.02)
        server.kill()
        server.communicate(timeout=5)
        raise AssertionError("isolated v2 startup timed out")

    server = start("tests.fault_server:create_backup_fault_app")
    try:
        with httpx.Client(base_url=f"http://127.0.0.1:{port}", timeout=10) as client:
            token = client.post(
                "/api/v1/auth/login", json={"passphrase": settings.passphrase}
            ).json()["access_token"]
            client.headers["Authorization"] = "Bearer " + token
            scan(client)
            original = tag(client, "恢复目标")
            raw, exported = export(client)
            preview = inspect(client, raw)
            later = tag(client, "仅在原历史", request_id="before-replacement")
            epoch = client.get("/api/v1/info").json()["management_epoch"]
            body = {
                "request_id": "lost-v2-restore-response",
                "preview_id": preview["id"],
                "root_mapping": {"main": str(media)},
                "confirmed": True,
            }
            response = client.post(PREFIX + "/restores", json=body)
            assert response.status_code == 202, response.text
            identity = response.json()["id"]
            deadline = time.monotonic() + 30
            while not marker.exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            assert marker.read_text() == phase
            current_tags = {row["id"] for row in client.get("/api/v1/tags").json()["items"]}
            observed_epoch = client.get("/api/v1/info").json()["management_epoch"]
            if phase == "restore_committed":
                assert current_tags == {original["id"]} and observed_epoch != epoch
                committed = client.get("/api/v1/tasks/" + identity).json()
                assert committed["status"] == "completed"
                finished_at = committed["finished_at"]
            else:
                assert current_tags == {original["id"], later["id"]} and observed_epoch == epoch
                finished_at = None
            server.kill()
            server.communicate(timeout=5)
            server = start("shika.app:create_app")
            recovered = wait_task(client, identity)
            assert recovered["status"] == "completed", recovered
            if finished_at is not None:
                assert recovered["finished_at"] == finished_at
                assert client.get("/api/v1/info").json()["management_epoch"] == observed_epoch
            assert not (
                settings.data_dir / "management-archives" / ("restore-" + identity)
            ).exists()
            assert (settings.data_dir / "management-history" / identity / "bundle").is_dir()
            stale = client.post(PREFIX + "/restores", json=body)
            assert (
                stale.status_code == 409 and stale.json()["error"]["code"] == "management_changed"
            )
            receipt = client.get(PREFIX + "/requests/restore/" + body["request_id"])
            assert (
                receipt.status_code == 200
                and receipt.json()["finished_at"] == recovered["finished_at"]
            )
            client.headers["X-Management-Epoch"] = client.get("/api/v1/info").json()[
                "management_epoch"
            ]
            assert client.post(PREFIX + "/restores", json=body).json()["id"] == identity
            assert (
                client.post(
                    "/api/v1/tags", json={"request_id": "before-replacement", "name": "仅在原历史"}
                ).status_code
                == 409
            )
            assert client.get("/api/v1/management-history/epochs/" + epoch).status_code == 200
            assert client.get(PREFIX + "/" + exported["id"] + "/download").content == raw
            snapshot = client.get(
                PREFIX + "/" + recovered["result"]["pre_snapshot_id"] + "/download"
            )
            assert snapshot.status_code == 200 and later["id"].encode() in snapshot.content
            assert hashlib.sha256((media / "one.mov").read_bytes()).hexdigest() == digest
            assert client.get("/api/v1/trash").json()["total"] == 0
            assert recovered["result"]["historical_operations_replayed"] == 0
            print(
                json.dumps(
                    {
                        "phase": phase,
                        "fault": "SIGKILL",
                        "recovered_once": True,
                        "snapshot_download": True,
                        "source_hash_preserved": True,
                        "retired_post_blocked": True,
                    }
                )
            )
    finally:
        server.kill()
        server.communicate(timeout=5)

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
from .test_backups import export, inspect, wait_task
from .test_tags import tag


@pytest.mark.parametrize("phase", ["snapshot_written", "after_replace_before_commit"])
def test_sigkill_restore_rolls_back_then_recovers_without_file_commands(
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
            assert server.poll() is None, "isolated backup server stopped"
            try:
                if httpx.get(f"http://127.0.0.1:{port}/health", timeout=1).status_code == 200:
                    return server
            except httpx.TransportError:
                pass
            time.sleep(0.02)
        server.kill()
        server.communicate(timeout=5)
        raise AssertionError("server startup timed out")

    server = start("tests.fault_server:create_backup_fault_app")
    try:
        with httpx.Client(base_url=f"http://127.0.0.1:{port}", timeout=5) as client:
            token = client.post(
                "/api/v1/auth/login", json={"passphrase": settings.passphrase}
            ).json()["access_token"]
            client.headers["Authorization"] = "Bearer " + token
            epoch_before = client.get("/api/v1/info").json()["management_epoch"]
            scan(client)
            old = tag(client, "恢复目标")
            raw, _ = export(client)
            extra = tag(client, "恢复前状态")
            preview = inspect(client, raw)
            body = {
                "request_id": "restore-response-lost",
                "preview_id": preview["id"],
                "root_mapping": {"main": str(media)},
                "confirmed": True,
            }
            response = client.post("/api/v1/backup-restores", json=body)
            assert response.status_code == 202, response.text
            task_id = response.json()["id"]
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline and not marker.exists():
                time.sleep(0.02)
            assert marker.read_text() == phase
            # Reads still observe the committed pre-restore state even while a
            # transaction has replaced every management table but not committed.
            assert {item["id"] for item in client.get("/api/v1/tags").json()["items"]} == {
                old["id"],
                extra["id"],
            }
            assert client.get("/api/v1/info").json()["management_epoch"] == epoch_before
            server.kill()
            server.communicate(timeout=5)
            server = start("shika.app:create_app")
            result = wait_task(client, task_id)
            assert result["status"] == "completed", result
            epoch_after = client.get("/api/v1/info").json()["management_epoch"]
            assert epoch_after != epoch_before
            # Old tokens remain valid for original read-only reconciliation.
            stale = client.post("/api/v1/backup-restores", json=body)
            assert (
                stale.status_code == 409 and stale.json()["error"]["code"] == "management_changed"
            )
            found = client.get("/api/v1/backup-requests/restore/" + body["request_id"])
            assert found.status_code == 200 and found.json()["id"] == task_id
            client.headers["X-Management-Epoch"] = epoch_after
            assert client.post("/api/v1/backup-restores", json=body).json()["id"] == task_id
            assert [item["id"] for item in client.get("/api/v1/tags").json()["items"]] == [
                old["id"]
            ]
            assert hashlib.sha256((media / "one.mov").read_bytes()).hexdigest() == digest
            assert client.get("/api/v1/trash").json()["total"] == 0
            before = client.get(f"/api/v1/backups/{result['result']['pre_snapshot_id']}/download")
            assert before.status_code == 200
            assert len(before.json()["payload"]["tables"]["tags"]) == 2
            print(
                json.dumps(
                    {
                        "fault": "SIGKILL",
                        "phase": phase,
                        "restore_recovered": True,
                        "old_data_visible_before_commit": True,
                        "media_hash_preserved": True,
                        "authority_unchanged_before_commit": True,
                        "authority_changed_after_commit": True,
                        "stale_post_rejected": True,
                        "original_receipt_readable": True,
                        "historical_operations_replayed": result["result"][
                            "historical_operations_replayed"
                        ],
                    }
                )
            )
    finally:
        server.kill()
        server.communicate(timeout=5)

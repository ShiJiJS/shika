"""Actual loopback HTTP + SIGKILL, not a cooperative shutdown simulation."""

import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

import httpx
import pytest

from .test_pack_operations import wait
from .test_pack_purge_execution import plan
from .test_pack_purge_plans import fixture


@pytest.mark.parametrize("attempt", [1, 2, 3])
@pytest.mark.parametrize(
    "phase,root_only", [("purge_unlinked_before_commit", False), ("purge_directory_removed", True)]
)
def test_sigkill_recovers_exact_confirmed_purge_without_replaying_deleted_pages(
    environment, phase, root_only, attempt
):
    settings, media = environment
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
        "TEST_PACK_PURGE_PHASE": phase,
        "TEST_PACK_PURGE_MARKER": str(marker),
        "TEST_PACK_PURGE_ROOT_ONLY": "1" if root_only else "0",
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
            if server.poll() is not None:
                raise AssertionError(server.communicate(timeout=5)[0].decode())
            try:
                if httpx.get(f"http://127.0.0.1:{port}/health", timeout=1).status_code == 200:
                    return server
            except httpx.TransportError:
                pass
            time.sleep(0.02)
        server.kill()
        server.communicate(timeout=5)
        raise AssertionError("isolated purge server startup timed out")

    server = start("tests.pack_purge_fault_server:create_fault_app")
    try:
        with httpx.Client(base_url=f"http://127.0.0.1:{port}", timeout=5) as client:
            token = client.post(
                "/api/v1/auth/login", json={"passphrase": settings.passphrase}
            ).json()["access_token"]
            client.headers["Authorization"] = "Bearer " + token
            root, _, rows = fixture(client, media)
            base = Path(root["path"]) / "pack-0"
            if root_only:
                (base / "notes.txt").unlink()
            value = plan(client, [rows[0]["id"]])
            body = {
                "request_id": "kill-result-unknown",
                "plan_id": value["id"],
                "digest": value["digest"],
                "confirmed": True,
            }
            accepted = client.post("/api/v1/pack-trash/permanent", json=body)
            assert accepted.status_code == 202, accepted.text
            identity = accepted.json()["id"]
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline and not marker.exists():
                time.sleep(0.02)
            assert marker.read_text() == phase
            assert not (base / "1.png").exists()
            server.kill()
            server.communicate(timeout=5)
            assert server.returncode == -9
            server = start("shika.app:create_app")
            receipt = client.get("/api/v1/pack-file-requests/kill-result-unknown")
            assert receipt.status_code == 200 and receipt.json()["id"] == identity
            result = wait(client, identity)
            assert result["status"] == "completed", result
            assert result["result"]["pages_deleted"] == result["result"]["pages_total"] == 2
            assert client.post("/api/v1/pack-trash/permanent", json=body).json()["id"] == identity
            assert client.get("/api/v1/pack-trash").json()["total"] == 0
            if root_only:
                assert not base.exists()
            else:
                assert (base / "notes.txt").read_text() == "retain attachment"
                assert not (base / "nested").exists()
            print(
                json.dumps(
                    {
                        "fault": "SIGKILL",
                        "attempt": attempt,
                        "phase": phase,
                        "root_directory": root_only,
                        "request_receipt": "same operation",
                        "pages_deleted": 2,
                        "pages_total": 2,
                    }
                )
            )
    finally:
        server.kill()
        server.communicate(timeout=5)

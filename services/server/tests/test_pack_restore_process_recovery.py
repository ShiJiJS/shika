"""Real HTTP and SIGKILL at acceptance, child commit and parent accounting."""

import json
import os
import socket
import subprocess
import sys
import time

import httpx
import pytest

from .test_pack_operations import tree
from .test_pack_purge_plans import fixture
from .test_pack_restore_plans import wait


@pytest.mark.parametrize("attempt", [1, 2, 3])
@pytest.mark.parametrize(
    "phase", ["restore_child_accepted", "logical_committed", "restore_child_finished"]
)
def test_sigkill_resumes_original_plan_without_replaying_a_committed_child(
    environment, phase, attempt
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
        "TEST_RESTORE_PHASE": phase,
        "TEST_RESTORE_MARKER": str(marker),
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
        raise AssertionError("restore process startup timed out")

    server = start("tests.pack_restore_fault_server:create_fault_app")
    try:
        with httpx.Client(base_url=f"http://127.0.0.1:{port}", timeout=10) as client:
            token = client.post(
                "/api/v1/auth/login", json={"passphrase": settings.passphrase}
            ).json()["access_token"]
            client.headers["Authorization"] = "Bearer " + token
            _, packs, rows = fixture(client, media, 7)
            originals = tree(media)
            response = client.post(
                "/api/v1/pack-restore-plans",
                json={"trash_ids": [r["id"] for r in rows], "request_id": "process-unknown"},
            )
            assert response.status_code == 202, response.text
            identity = response.json()["id"]
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline and not marker.exists():
                time.sleep(0.02)
            assert marker.read_text() == phase
            server.kill()
            server.communicate(timeout=5)
            assert server.returncode == -9
            server = start("video_viewer.app:create_app")
            # Reopen is GET-only; the complete seven-member selection survived.
            original = client.get("/api/v1/pack-restore-requests/process-unknown")
            assert original.status_code == 200 and original.json()["id"] == identity
            result = wait(client, identity)
            assert result["result"]["succeeded"] == 7 and result["result"]["batches"] == 4
            assert result["batch_size"] == 2
            assert client.get("/api/v1/pack-trash").json()["total"] == 0
            assert tree(media) == originals
            # Generation is exposed only by SQLite: one trash and one restore.
            import sqlite3

            with sqlite3.connect(settings.data_dir / "library.sqlite3") as connection:
                assert connection.execute("SELECT DISTINCT generation FROM packs").fetchall() == [
                    (3,)
                ]
                assert connection.execute(
                    "SELECT COUNT(*),COUNT(DISTINCT operation_id) FROM pack_restore_batches"
                ).fetchone() == (4, 4)
                assert connection.execute(
                    "SELECT COUNT(*) FROM pack_restore_members"
                ).fetchone() == (7,)
                assert connection.execute("PRAGMA foreign_key_check").fetchall() == []
            print(
                json.dumps(
                    {
                        "phase": phase,
                        "attempt": attempt,
                        "fault": "SIGKILL",
                        "members": len(packs),
                        "batches": 4,
                        "same_request": True,
                        "media_unchanged": True,
                    }
                )
            )
    finally:
        server.kill()
        server.communicate(timeout=5)

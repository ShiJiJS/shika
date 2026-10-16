import hashlib
import json
import os
import socket
import subprocess
import sys
import time

import httpx
import pytest

from .conftest import put
from .test_file_operations import operation, trash, wait_operation


@pytest.mark.parametrize("kind,phase", [("trash", "published"), ("permanent", "purging")])
def test_sigkill_real_http_file_operation_recovers_exact_request(environment, samples, kind, phase):
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
        "TEST_FILE_PHASE": phase,
        "TEST_FILE_MARKER": str(marker),
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
            assert server.poll() is None, "isolated file-operation server stopped"
            try:
                if httpx.get(f"http://127.0.0.1:{port}/health", timeout=1).status_code == 200:
                    return server
            except httpx.TransportError:
                pass
            time.sleep(0.02)
        server.kill()
        server.communicate(timeout=5)
        raise AssertionError("server startup timed out")

    server = start("tests.fault_server:create_fault_app")
    try:
        with httpx.Client(base_url=f"http://127.0.0.1:{port}", timeout=5) as client:
            token = client.post(
                "/api/v1/auth/login", json={"passphrase": settings.passphrase}
            ).json()["access_token"]
            client.headers["Authorization"] = "Bearer " + token
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                videos = client.get("/api/v1/videos").json()
                if videos["total"]:
                    break
                time.sleep(0.02)
            video = videos["items"][0]
            route = "/api/v1/videos/trash"
            request = {"request_id": "response-lost", "video_ids": [video["id"]]}
            if kind == "permanent":
                assert trash(client, [video["id"]])[0]["status"] == "completed"
                item = client.get("/api/v1/trash").json()["items"][0]
                route = "/api/v1/trash/permanent"
                request = {
                    "request_id": "purge-response-lost",
                    "trash_ids": [item["id"]],
                    "confirmed": True,
                }
            submitted = client.post(route, json=request)
            assert submitted.status_code == 202, submitted.text
            operation_id = submitted.json()["id"]
            while time.monotonic() < deadline and not marker.exists():
                time.sleep(0.02)
            assert marker.read_text() == phase
            server.kill()
            server.communicate(timeout=5)
            server = start("video_viewer.app:create_app")
            recovered = wait_operation(client, operation_id)
            assert recovered["status"] == "completed", recovered
            assert client.post(route, json=request).json()["id"] == operation_id
            assert client.get("/api/v1/videos").json()["total"] == 0
            assert not (media / "one.mov").exists()
            if kind == "trash":
                assert client.get("/api/v1/trash").json()["total"] == 1
                assert [
                    hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in (media / ".video-viewer-trash").rglob("*.mov")
                ] == [digest]
                undone, _ = operation(client, f"/api/v1/operations/{operation_id}/undo", {})
                assert undone["status"] == "completed", undone
                assert hashlib.sha256((media / "one.mov").read_bytes()).hexdigest() == digest
            else:
                assert client.get("/api/v1/trash").json()["total"] == 0
                assert not list((media / ".video-viewer-trash").rglob("*.mov"))
            print(
                json.dumps(
                    {
                        "fault": "SIGKILL",
                        "phase": phase,
                        "operation": kind,
                        "recovered": "completed",
                        "request_replay": "same operation",
                    }
                )
            )
    finally:
        server.kill()
        server.communicate(timeout=5)

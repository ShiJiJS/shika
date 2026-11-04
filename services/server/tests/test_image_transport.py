"""Real sockets: image backpressure, cancellation, Range, and bounded server RSS."""

import json
import os
import socket
import subprocess
import sys
import time

import httpx
from PIL import Image

from .http_streams import available_stream, process_kib


def test_real_image_cancellation_and_backpressure_do_not_buffer_original(environment):
    settings, media = environment
    folder = media / "pack"
    folder.mkdir()
    source = folder / "large.png"
    with Image.new("RGB", (4096, 4096), "blue") as image:
        image.save(source, compress_level=0)
    config = media.parent / "mounts.json"
    config.write_text(json.dumps([{"id": "main", "name": "isolated", "path": str(media)}]))
    secret = media.parent / "passphrase"
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
        "VV_STABILITY_SECONDS": "0",
        "VV_MEDIA_STREAMS": "1",
    }
    server = subprocess.Popen(
        [
            sys.executable,
            "-m",
            "uvicorn",
            "shika.app:create_app",
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
    try:
        with httpx.Client(base_url=f"http://127.0.0.1:{port}", timeout=5) as client:
            deadline = time.monotonic() + 45
            while time.monotonic() < deadline:
                assert server.poll() is None
                try:
                    if client.get("/health").status_code == 200:
                        break
                except httpx.TransportError:
                    pass
                time.sleep(0.03)
            login = client.post("/api/v1/auth/login", json={"passphrase": settings.passphrase})
            client.headers["Authorization"] = "Bearer " + login.json()["access_token"]
            while not client.get("/api/v1/library-state").json()["ready"]:
                assert time.monotonic() < deadline
                time.sleep(0.03)
            changed = client.put(
                "/api/v1/roots/main", json={"path": str(media), "name": "图片", "kind": "pack"}
            )
            assert changed.status_code == 200, changed.text
            assert client.get("/api/v1/library-state").json()["media"]["pack"]["ready"] is False
            task_id = client.post("/api/v1/scans").json()["id"]
            while time.monotonic() < deadline:
                task = client.get(f"/api/v1/tasks/{task_id}").json()
                if task["status"] == "completed":
                    break
                assert task["status"] != "failed", task
                time.sleep(0.03)
            assert task["status"] == "completed", task
            pack = client.get("/api/v1/packs").json()["items"][0]
            page = client.get(f"/api/v1/packs/{pack['id']}/pages").json()["items"][0]
            route = page["image_url"]
            baseline = process_kib(server.pid)
            peak, fds_before = baseline, len(os.listdir(f"/proc/{server.pid}/fd"))
            for _ in range(3):
                with available_stream(client, route) as response:
                    assert response.headers["content-length"] == str(source.stat().st_size)
                    chunks = response.iter_raw(chunk_size=1024)
                    assert len(next(chunks)) == 1024
                    assert client.get(route, headers={"Range": "bytes=0-9"}).status_code == 503
                    assert client.get("/health").status_code == 200
                    peak = max(peak, process_kib(server.pid))
                deadline_release = time.monotonic() + 5
                while time.monotonic() < deadline_release:
                    reopened = client.get(route, headers={"Range": "bytes=0-9"})
                    if reopened.status_code == 206:
                        break
                    assert reopened.status_code == 503
                    time.sleep(0.02)
                assert reopened.status_code == 206 and len(reopened.content) == 10
            fds_after = len(os.listdir(f"/proc/{server.pid}/fd"))
            assert peak - baseline < 32 * 1024
            assert fds_after <= fds_before + 4
            print(
                json.dumps(
                    {
                        "transport": "real authenticated HTTP image",
                        "file_bytes": source.stat().st_size,
                        "cancellations": 3,
                        "stream_slots": 1,
                        "rss_before_kib": baseline,
                        "rss_peak_kib": peak,
                        "fds_before": fds_before,
                        "fds_after": fds_after,
                        "range_after_cancel": 206,
                    }
                )
            )
    finally:
        server.terminate()
        try:
            server.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            server.kill()
            server.communicate(timeout=5)

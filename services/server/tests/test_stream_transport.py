import json
import os
import socket
import subprocess
import sys
import time

import httpx

from .conftest import put
from .http_streams import available_stream, process_kib


def test_real_http_backpressure_cancellation_and_bounded_memory(environment, samples):
    settings, media = environment
    source = media / "large.mp4"
    put(samples / "portrait.mp4", source)
    with source.open("ab") as output:
        output.truncate(128 * 1024 * 1024)
    config = settings.data_dir.parent / "mounts.json"
    config.write_text(json.dumps([{"id": "main", "name": "isolated", "path": str(media)}]))
    secret = settings.data_dir.parent / "passphrase"
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
        "VV_MEDIA_STREAMS": "1",
    }
    server = subprocess.Popen(
        [
            sys.executable,
            "-m",
            "uvicorn",
            "video_viewer.app:create_app",
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
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                assert server.poll() is None, "isolated HTTP server stopped"
                try:
                    if client.get("/health").status_code == 200:
                        break
                except httpx.TransportError:
                    pass
                time.sleep(0.03)
            login = client.post("/api/v1/auth/login", json={"passphrase": settings.passphrase})
            assert login.status_code == 200
            client.headers["Authorization"] = "Bearer " + login.json()["access_token"]
            while time.monotonic() < deadline:
                listing = client.get("/api/v1/videos").json()
                if listing["total"] == 1 and client.get("/api/v1/library-state").json()["ready"]:
                    break
                time.sleep(0.03)
            assert listing["total"] == 1
            route = listing["items"][0]["media_url"]
            baseline_memory = process_kib(server.pid)
            baseline_fds = len(os.listdir(f"/proc/{server.pid}/fd"))
            peak_memory = baseline_memory
            for _ in range(3):
                with available_stream(client, route) as response:
                    assert response.status_code == 200
                    assert response.headers["content-length"] == str(source.stat().st_size)
                    chunks = response.iter_raw(chunk_size=1024)
                    assert len(next(chunks)) == 1024
                    # Keep the first response unread: actual socket backpressure
                    # must hold its slot without buffering the entire media file.
                    blocked = client.get(route, headers={"Range": "bytes=0-127"})
                    assert blocked.status_code == 503
                    assert client.get("/api/v1/info").status_code == 200
                    peak_memory = max(peak_memory, process_kib(server.pid))
                    assert peak_memory - baseline_memory < 32 * 1024
                release_deadline = time.monotonic() + 5
                while time.monotonic() < release_deadline:
                    reopened = client.get(route, headers={"Range": "bytes=0-127"})
                    if reopened.status_code == 206:
                        break
                    assert reopened.status_code == 503
                    time.sleep(0.02)
                assert reopened.status_code == 206 and len(reopened.content) == 128
            final_fds = len(os.listdir(f"/proc/{server.pid}/fd"))
            assert final_fds <= baseline_fds + 4
            print(
                json.dumps(
                    {
                        "transport": "real HTTP over loopback, non-root Docker",
                        "file_bytes": source.stat().st_size,
                        "cancellations": 3,
                        "stream_slots": 1,
                        "rss_before_kib": baseline_memory,
                        "rss_peak_kib": peak_memory,
                        "fds_before": baseline_fds,
                        "fds_after": final_fds,
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

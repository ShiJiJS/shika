#!/usr/bin/env python3
"""Validate the canonical LF0 image corpus over public HTTP in disposable storage.

Run inside the server test image with this directory mounted read-only. Always
creates synthetic media in TemporaryDirectory; never accepts an existing source.
"""

import hashlib
import json
import os
import runpy
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import httpx


def main():
    generate = runpy.run_path(str(Path(__file__).with_name("generate-lf0-packs.py")))["generate"]
    with tempfile.TemporaryDirectory(prefix="lf2-canonical-") as temporary:
        base = Path(temporary)
        media = base / "media"
        manifest = generate(media)
        originals = {
            str(path.relative_to(media)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in media.rglob("*")
            if path.is_file()
        }
        config, secret = base / "mounts.json", base / "passphrase"
        config.write_text(json.dumps([{"id": "main", "name": "LF 合成夹具", "path": str(media)}]))
        secret.write_text("lf2-isolated-generated-fixture-only")
        secret.chmod(0o600)
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        environment = {
            **os.environ,
            "VV_DATA_DIR": str(base / "data"),
            "VV_MOUNTS_FILE": str(config),
            "VV_PASSPHRASE_FILE": str(secret),
            "VV_SCAN_INTERVAL": "0",
            "VV_STABILITY_SECONDS": "0",
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
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        try:
            with httpx.Client(base_url=f"http://127.0.0.1:{port}", timeout=20) as client:
                startup = time.monotonic() + 30
                while time.monotonic() < startup:
                    assert server.poll() is None, "Isolated server stopped"
                    try:
                        if client.get("/health").status_code == 200:
                            break
                    except httpx.TransportError:
                        pass
                    time.sleep(0.05)
                response = client.post(
                    "/api/v1/auth/login", json={"passphrase": secret.read_text()}
                )
                assert response.status_code == 200
                client.headers["Authorization"] = "Bearer " + response.json()["access_token"]
                while time.monotonic() < startup:
                    state = client.get("/api/v1/library-state").json()
                    if state["ready"] and not state["scanning"]:
                        break
                    time.sleep(0.03)
                changed = client.put(
                    "/api/v1/roots/main", json={"path": str(media), "name": "图包", "kind": "pack"}
                )
                assert changed.status_code == 200, changed.text
                started = time.monotonic()
                task = client.post("/api/v1/scans").json()["id"]
                deadline = time.monotonic() + 240
                while time.monotonic() < deadline:
                    job = client.get(f"/api/v1/tasks/{task}").json()
                    if job["status"] == "completed":
                        break
                    assert job["status"] != "failed", job
                    time.sleep(0.1)
                assert job["status"] == "completed", job
                cold = time.monotonic() - started
                listed = client.get("/api/v1/packs").json()
                assert listed["total"] == manifest["pack_count"] == 4
                expected = {page["path"]: page for page in manifest["pages"]}
                valid, invalid, all_ids = 0, 0, set()
                for pack in listed["items"]:
                    pages = []
                    for offset in range(0, pack["page_count"], 100):
                        response = client.get(
                            f"/api/v1/packs/{pack['id']}/pages",
                            params={"offset": offset, "limit": 100, "v": pack["content_version"]},
                        )
                        assert response.status_code == 200, response.text
                        batch = response.json()
                        assert batch["total"] == pack["page_count"]
                        pages.extend(batch["items"])
                    if pack["name"] == "01-natural":
                        assert [page["relative_path"] for page in pages] == manifest[
                            "natural_order"
                        ]
                    if pack["name"] == "04-long":
                        assert [page["name"] for page in pages] == [
                            f"{index}.png" for index in range(1, 501)
                        ]
                    for page in pages:
                        assert page["id"] not in all_ids
                        all_ids.add(page["id"])
                        if page["error"]:
                            assert page["image_url"] is None
                            assert (
                                client.get(f"/api/v1/pages/{page['id']}/image").status_code == 422
                            )
                            invalid += 1
                            continue
                        relative = f"{pack['name']}/{page['relative_path']}"
                        spec = expected[relative]
                        assert (page["width"], page["height"]) == (spec["width"], spec["height"])
                        response = client.get(page["image_url"])
                        assert response.status_code == 200
                        assert hashlib.sha256(response.content).hexdigest() == spec["sha256"]
                        assert client.get(page["thumbnail_url"]).status_code == 200
                        valid += 1
                assert valid == manifest["valid_image_count"] == 508 and invalid == 1
                cached_started = time.monotonic()
                cached_id = client.post("/api/v1/scans").json()["id"]
                while time.monotonic() < deadline:
                    cached = client.get(f"/api/v1/tasks/{cached_id}").json()
                    if cached["status"] == "completed":
                        break
                    assert cached["status"] != "failed", cached
                    time.sleep(0.05)
                assert cached["status"] == "completed"
                cached_time = time.monotonic() - cached_started
                assert cached["result"]["packs"]["unchanged"] == 4
                after = {
                    str(path.relative_to(media)): hashlib.sha256(path.read_bytes()).hexdigest()
                    for path in media.rglob("*")
                    if path.is_file()
                }
                assert after == originals, "Scanner changed source media/attachments"
                print(
                    json.dumps(
                        {
                            "generator": manifest["generator"],
                            "source_revision": os.environ.get("VV_EVIDENCE_REVISION"),
                            "image_id": os.environ.get("VV_EVIDENCE_IMAGE"),
                            "transport": "public HTTP",
                            "packs": 4,
                            "valid_originals_checked": valid,
                            "thumbnails_checked": valid,
                            "invalid_pages": invalid,
                            "long_pack_pages": 500,
                            "source_files_unchanged": True,
                            "private_media": False,
                            "first_scan_seconds": round(cold, 3),
                            "cached_scan_seconds": round(cached_time, 3),
                            "peak_decoder_kib": job["result"]["packs"]["progress"][
                                "peak_decoder_kib"
                            ],
                        },
                        ensure_ascii=False,
                    )
                )
        finally:
            server.terminate()
            try:
                server.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
                server.communicate(timeout=5)


if __name__ == "__main__":
    main()

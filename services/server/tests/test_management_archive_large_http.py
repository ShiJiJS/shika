"""Actual network streaming and measured server Python allocation working set."""

import hashlib
import json
import os
import socket
import sqlite3
import subprocess
import sys
import time
import uuid
from dataclasses import replace

import httpx

from video_viewer.models import Task

from .conftest import connect, put, scan
from .test_management_archives import PREFIX, export


def test_over_32mib_http_import_download_restore_has_bounded_server_python_peak(
    environment, samples
):
    settings, media = environment
    settings = replace(settings, backup_max_bytes=64 * 1024 * 1024)
    digest = put(samples / "h264.mov", media / "source.mov")
    client, token = connect(settings)
    try:
        scan(client)
        with client.app.state.db.write() as session:
            for start in range(0, 18000, 100):
                session.execute(
                    Task.__table__.insert(),
                    [
                        {
                            "id": str(uuid.uuid4()),
                            "kind": "scan",
                            "status": "completed",
                            "phase": "completed",
                            "result": {"note": "x" * 2048},
                        }
                        for _ in range(start, start + 100)
                    ],
                )
        raw, exported = export(client, "large-seed")
        source = settings.data_dir.parent / "large.vvbackup"
        source.write_bytes(raw)
        expected_hash = hashlib.sha256(raw).hexdigest()
        del raw
    finally:
        client.__exit__(None, None, None)
    assert source.stat().st_size > 32 * 1024 * 1024
    parent = settings.data_dir.parent
    config, secret = parent / "mounts.json", parent / "passphrase"
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
        "VV_BACKUP_MAX_BYTES": str(settings.backup_max_bytes),
    }
    process = subprocess.Popen(
        [
            sys.executable,
            "-m",
            "uvicorn",
            "tests.fault_server:create_archive_memory_app",
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
        with httpx.Client(base_url=f"http://127.0.0.1:{port}", timeout=20) as client:
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                assert process.poll() is None, "isolated memory server stopped"
                try:
                    if client.get("/health").status_code == 200:
                        break
                except httpx.TransportError:
                    pass
                time.sleep(0.02)
            else:
                raise AssertionError("isolated memory server timeout")
            client.headers["Authorization"] = "Bearer " + token
            # Wait for its ordinary startup scan before measuring file work.
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                if not client.get("/api/v1/library-state").json()["scanning"]:
                    break
                time.sleep(0.05)
            client.post("/test-allocation/reset").raise_for_status()

            def chunks():
                with source.open("rb") as incoming:
                    while chunk := incoming.read(64 * 1024):
                        yield chunk

            response = client.post(
                PREFIX + "/imports", content=chunks(), headers={"Idempotency-Key": "large-import"}
            )
            assert response.status_code == 202, response.text

            def completed(identity):
                deadline = time.monotonic() + 180
                while time.monotonic() < deadline:
                    response = client.get("/api/v1/tasks/" + identity)
                    assert response.status_code == 200, response.text
                    job = response.json()
                    if job["status"] not in ("queued", "running"):
                        assert job["status"] == "completed", job
                        return job
                    time.sleep(0.05)
                raise AssertionError(job)

            preview = completed(response.json()["id"])
            assert preview["result"]["file_sha256"] == expected_hash
            actual_hash, downloaded = hashlib.sha256(), 0
            with client.stream("GET", PREFIX + "/" + exported["id"] + "/download") as download:
                assert download.status_code == 200
                for chunk in download.iter_bytes(64 * 1024):
                    actual_hash.update(chunk)
                    downloaded += len(chunk)
            assert actual_hash.hexdigest() == expected_hash and downloaded == source.stat().st_size
            response = client.post(
                PREFIX + "/restores",
                json={
                    "request_id": "large-restore",
                    "preview_id": preview["id"],
                    "root_mapping": {"main": str(media)},
                    "confirmed": True,
                },
            )
            assert response.status_code == 202, response.text
            restored = completed(response.json()["id"])
            peak = client.get("/test-allocation/peak").json()["peak_bytes"]
            assert peak < 32 * 1024 * 1024, {"bytes": downloaded, "python_peak": peak}
            with sqlite3.connect(settings.data_dir / "library.sqlite3") as database:
                count, minimum, maximum = database.execute(
                    "SELECT count(*),min(length(json_extract(result,'$.note'))),max(length(json_extract(result,'$.note'))) FROM tasks WHERE json_type(result,'$.note')='text'"
                ).fetchone()
            assert count == 18000 and minimum == maximum == 2048
            assert restored["result"]["historical_operations_replayed"] == 0
            assert hashlib.sha256((media / "source.mov").read_bytes()).hexdigest() == digest
            print(
                "VV_MANAGEMENT_HTTP_MEMORY",
                json.dumps(
                    {
                        "archive_bytes": downloaded,
                        "server_python_peak_bytes": peak,
                        "restored_note_tasks": count,
                        "source_hash_preserved": True,
                        "limit_bytes": settings.backup_max_bytes,
                    }
                ),
            )
    finally:
        process.kill()
        process.communicate(timeout=5)

import hashlib
import shutil
import time

import pytest
from fastapi.testclient import TestClient

from video_viewer.app import create_app
from video_viewer.config import Mount, Settings

from .generate_media import generate

PASSPHRASE = "isolated-test-secret-7412"


@pytest.fixture(scope="session")
def samples(tmp_path_factory):
    return generate(tmp_path_factory.mktemp("formats"))


@pytest.fixture
def environment(tmp_path):
    media = tmp_path / "media"
    media.mkdir()
    settings = Settings(
        data_dir=tmp_path / "data",
        mounts=(Mount("main", "测试媒体", media),),
        passphrase=PASSPHRASE,
        stability_seconds=0.03,
        scan_interval=0,
        startup_scan=False,
    )
    return settings, media


def connect(settings, *, token=None, file_fault_hook=None, backup_fault_hook=None):
    client = TestClient(create_app(settings, file_fault_hook, backup_fault_hook))
    client.__enter__()
    if not token:
        response = client.post("/api/v1/auth/login", json={"passphrase": settings.passphrase})
        assert response.status_code == 200, response.text
        token = response.json()["access_token"]
    client.headers["Authorization"] = f"Bearer {token}"
    return client, token


@pytest.fixture
def library(environment):
    settings, media = environment
    client, _ = connect(settings)
    try:
        yield client, media
    finally:
        client.__exit__(None, None, None)


def scan(client, timeout=30):
    response = client.post("/api/v1/scans")
    assert response.status_code == 202, response.text
    task_id = response.json()["id"]
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        task = client.get(f"/api/v1/tasks/{task_id}").json()
        if task["status"] in {"completed", "failed", "interrupted"}:
            assert task["status"] == "completed", task
            return task
        time.sleep(0.02)
    raise AssertionError(f"scan timeout: {task}")


def wait_phase(client, task_id, phase):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        result = client.get(f"/api/v1/tasks/{task_id}").json()
        if result["phase"] == phase:
            return result
        assert result["status"] not in {"completed", "failed", "interrupted"}, result
        time.sleep(0.01)
    raise AssertionError(f"phase timeout: {result}")


def put(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    return hashlib.sha256(destination.read_bytes()).hexdigest()


__all__ = ["connect", "scan", "put", "wait_phase"]

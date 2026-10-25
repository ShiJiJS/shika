"""Public-HTTP v1 restore actor for the disposable Android authority scenario.

Installed only by e2e_server after its explicit environment/mount guards.
Never returns tokens or modifies anything outside the generated fixture.
"""

import hashlib
import time
from contextlib import contextmanager

import httpx
from fastapi import Header, HTTPException


def install(app, base, key, passphrase):
    prepared = {}
    completed = {}

    def guard(value):
        if value != key:
            raise HTTPException(status_code=403)

    @contextmanager
    def actor():
        with httpx.Client(
            base_url="http://127.0.0.1:8760",
            headers={"X-Fixture-Actor": "authority-host"},
            timeout=15,
        ) as client:
            login = client.post("/api/v1/auth/login", json={"passphrase": passphrase})
            assert login.status_code == 200
            client.headers["Authorization"] = "Bearer " + login.json()["access_token"]
            client.headers["X-Management-Epoch"] = login.json()["management_epoch"]
            yield client

    def checked(response, status=200):
        assert response.status_code == status, (response.request.url.path, response.status_code)
        return response.json()

    def wait(client, task):
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            value = checked(client.get(f"/api/v1/tasks/{task['id']}"))
            if value["status"] in {"completed", "failed", "interrupted"}:
                assert value["status"] == "completed", value
                return value
            time.sleep(0.05)
        raise AssertionError("Authority fixture task timed out")

    def files():
        return {
            str(path.relative_to(base)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(base.rglob("*"))
            if path.is_file()
        }

    @app.post("/__fixture/authority/prepare")
    def prepare(x_fixture_key: str | None = Header(default=None)):
        guard(x_fixture_key)
        if prepared:
            return prepared
        with actor() as client:
            info = checked(client.get("/api/v1/info"))
            tag = checked(
                client.post(
                    "/api/v1/tags",
                    json={
                        "request_id": "authority-fixture-tag",
                        "name": "恢复目标",
                    },
                ),
                201,
            )
            exported = wait(
                client,
                checked(
                    client.post(
                        "/api/v1/backups",
                        json={
                            "request_id": "authority-fixture-export",
                        },
                    ),
                    202,
                ),
            )
            response = client.get(f"/api/v1/backups/{exported['id']}/download")
            assert response.status_code == 200
            raw = response.content
            preview = wait(
                client,
                checked(
                    client.post(
                        "/api/v1/backup-imports",
                        content=raw,
                        headers={
                            "Content-Type": "application/json",
                            "Idempotency-Key": "authority-fixture-inspect",
                        },
                    ),
                    202,
                ),
            )
            roots = checked(client.get("/api/v1/roots"))["items"]
            checked(
                client.patch(
                    f"/api/v1/tags/{tag['id']}",
                    json={
                        "request_id": "authority-fixture-modified",
                        "name": "恢复前修改",
                    },
                )
            )
            prepared.update(
                old_epoch=info["management_epoch"],
                server_id=info["server_id"],
                tag_id=tag["id"],
                preview_id=preview["id"],
                root_mapping={root["id"]: root["path"] for root in roots},
                files=files(),
                file_sha256=hashlib.sha256(raw).hexdigest(),
            )
        assert len(prepared["files"]) == 27
        return prepared

    @app.post("/__fixture/authority/restore")
    def restore(x_fixture_key: str | None = Header(default=None)):
        guard(x_fixture_key)
        assert prepared
        if completed:
            return completed
        with actor() as client:
            task = wait(
                client,
                checked(
                    client.post(
                        "/api/v1/backup-restores",
                        json={
                            "request_id": "authority-fixture-restore",
                            "preview_id": prepared["preview_id"],
                            "root_mapping": prepared["root_mapping"],
                            "confirmed": True,
                        },
                    ),
                    202,
                ),
            )
            info = checked(client.get("/api/v1/info"))
            tags = checked(client.get("/api/v1/tags"))["items"]
            assert info["management_epoch"] != prepared["old_epoch"]
            assert any(t["id"] == prepared["tag_id"] and t["name"] == "恢复目标" for t in tags)
            assert files() == prepared["files"]
            completed.update(new_epoch=info["management_epoch"], task_id=task["id"], files=files())
        return completed

    @app.get("/__fixture/authority/stats")
    def stats(x_fixture_key: str | None = Header(default=None)):
        guard(x_fixture_key)
        return {"prepared": prepared, "completed": completed, "files": files()}

#!/usr/bin/env python3
"""Bootstrap only the running owned 8763 synthetic fixture using real HTTP."""

import hashlib
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path
from urllib.error import HTTPError

ROOT = Path(__file__).resolve().parents[1]
BASE = "http://127.0.0.1:8763"
DEST = ROOT / ".dev/history-purge-app"
CONTROL = {"X-Fixture-Key": "history-purge-isolated-control"}


def request(method, path, body=None, headers=None):
    raw = (
        json.dumps(body, ensure_ascii=False).encode()
        if isinstance(body, dict)
        else body
    )
    req = urllib.request.Request(
        BASE + path,
        data=raw,
        headers={
            **(headers or {}),
            **({"Content-Type": "application/json"} if isinstance(body, dict) else {}),
        },
        method=method,
    )
    with urllib.request.urlopen(req, timeout=30) as response:
        return response.read()


def control(path):
    return json.loads(request("GET", "/__history_fixture" + path, headers=CONTROL))


assert control("/status")["fixture"] == "purge-history-owned-8763"
DEST.mkdir(parents=True, exist_ok=True)
setup = DEST / "data/app-setup.json"
if setup.exists():
    existing = json.loads(setup.read_text())
    assert control("/setup") == existing
    print(json.dumps({"already_prepared": True, "restore_id": existing["restore_id"]}))
    raise SystemExit(0)

auth = json.loads(
    request("POST", "/api/v1/auth/login", {"passphrase": "history-purge-isolated-only"})
)
headers = {"Authorization": "Bearer " + auth["access_token"]}


def call(method, path, body=None):
    raw = request(method, path, body, headers)
    return json.loads(raw)


def wait(identity, route="/api/v1/tasks/"):
    deadline = time.monotonic() + 120
    while True:
        task = call("GET", route + identity)
        if task["status"] not in ("queued", "running"):
            return task
        if time.monotonic() > deadline:
            raise TimeoutError(identity)
        time.sleep(0.1)


try:
    prior = call("GET", "/api/v1/pack-file-requests/history-permanent")
except HTTPError as error:
    if error.code != 404:
        raise
    prior = None
if prior is None:
    roots = call("GET", "/api/v1/roots")["items"]
    pack_root = next(v for v in roots if v["path"] == "/media/packs")
    if pack_root["kind"] != "pack":
        call(
            "PUT",
            "/api/v1/roots/" + pack_root["id"],
            {
                "name": "历史图包目录",
                "path": "/media/packs",
                "kind": "pack",
                "enabled": True,
            },
        )
    assert wait(call("POST", "/api/v1/scans")["id"])["status"] == "completed"
    packs = call("GET", "/api/v1/packs?limit=100")["items"]
    assert len(packs) == 27
    exported = wait(
        call("POST", "/api/v1/management-backups", {"request_id": "history-export"})[
            "id"
        ]
    )
    assert exported["status"] == "completed"
    archive = request(
        "GET",
        "/api/v1/management-backups/" + exported["id"] + "/download",
        headers=headers,
    )
    (DEST / "export.vvbackup").write_bytes(archive)
    preview = json.loads(
        request(
            "POST",
            "/api/v1/management-backups/imports",
            archive,
            {
                **headers,
                "Idempotency-Key": "history-import",
                "Content-Type": "application/x-ndjson",
            },
        )
    )
    preview = wait(preview["id"])
    assert preview["status"] == "completed"
    trashed = wait(
        call(
            "POST",
            "/api/v1/packs/trash",
            {"request_id": "history-trash", "pack_ids": [v["id"] for v in packs]},
        )["id"]
    )
    assert trashed["result"]["succeeded"] == 27
    trash = call("GET", "/api/v1/pack-trash?limit=100")["items"]
    plan = wait(
        call(
            "POST",
            "/api/v1/pack-purge-plans",
            {"request_id": "history-plan", "trash_ids": [v["id"] for v in trash]},
        )["id"],
        "/api/v1/pack-purge-plans/",
    )
    assert plan["ready"] and len(plan["items"]) == 27
    purged = wait(
        call(
            "POST",
            "/api/v1/pack-trash/permanent",
            {
                "request_id": "history-permanent",
                "plan_id": plan["id"],
                "digest": plan["digest"],
                "confirmed": True,
            },
        )["id"]
    )
else:
    roots = call("GET", "/api/v1/roots")["items"]
    plan = call("GET", "/api/v1/pack-purge-requests/history-plan")
    exported = call("GET", "/api/v1/management-backups/requests/export/history-export")
    preview = call("GET", "/api/v1/management-backups/requests/inspect/history-import")
    archive = request(
        "GET",
        "/api/v1/management-backups/" + exported["id"] + "/download",
        headers=headers,
    )
    purged = wait(prior["id"])
assert (
    purged["result"]["pages_total"] == 153 and purged["result"]["pages_deleted"] == 126
)
checkpoint = DEST / "restore-checkpoint.json"
old_epoch = (
    json.loads(checkpoint.read_text())["old_epoch"]
    if checkpoint.exists()
    else call("GET", "/api/v1/info")["management_epoch"]
)
checkpoint.write_text(json.dumps({"old_epoch": old_epoch}))
restored = wait(
    call(
        "POST",
        "/api/v1/management-backups/restores",
        {
            "request_id": "history-restore",
            "preview_id": preview["id"],
            "root_mapping": {v["id"]: v["path"] for v in roots},
            "confirmed": True,
        },
    )["id"]
)
assert restored["status"] == "completed"
new_epoch = call("GET", "/api/v1/info")["management_epoch"]
assert new_epoch != old_epoch
headers["X-Management-Epoch"] = new_epoch
graph = call("GET", "/api/v1/management-history/epochs/" + old_epoch)["graph_id"]
base = "/api/v1/management-history/tasks/" + purged["id"]
review = call(
    "GET",
    base + "/purge-review?" + urllib.parse.urlencode({"graph_id": graph, "limit": 100}),
)
assert review["total"] == 27 and len(review["items"]) == 27
large = next((i, v) for i, v in enumerate(review["items"]) if v["image_count"] == 127)
results = call(
    "GET",
    base
    + "/purge-pages?"
    + urllib.parse.urlencode({"graph_id": graph, "outcome": "unfinished"}),
)
assert results["total"] > 0 and any(
    v["error"] == "permission_denied" for v in results["items"]
)
metadata = {
    "plan_id": plan["id"],
    "purge_id": purged["id"],
    "restore_id": restored["id"],
    "old_epoch": old_epoch,
    "current_epoch": new_epoch,
    "graph_id": graph,
    "large_member": large[1],
    "large_member_offset": large[0] // 24 * 24,
    "review": review,
    "unfinished": results,
    "source_files_expected": 54,
    "deleted_images": 126,
    "archive_bytes": len(archive),
    "archive_sha256": hashlib.sha256(archive).hexdigest(),
}
setup.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
print(
    json.dumps(
        {
            "prepared": True,
            "packs": 27,
            "images": 153,
            "deleted_images": 126,
            "graph_id": graph,
            "purge_id": purged["id"],
        },
        ensure_ascii=False,
    )
)

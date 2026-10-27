"""Read-only evidence replay. Injected reply loss is distinct from issue #89."""

import gzip
import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SOURCE = "848a1b8a0f80dccc3fd49ea1fa7676e5405114ba"
REGRESSION = "ed09749186b2f9f375fdd0c22b38d4a9fefb768b"
BASE = "6ae5ad6ad057f5403d3bd64404bcb3afc0de14c8"


def read(name):
    return json.loads((HERE / name).read_text())


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def verify():
    manifest = read("manifest.json")
    assert manifest["producer"] == SOURCE
    for name, expected in manifest["files"].items():
        assert hashlib.sha256((HERE / name).read_bytes()).hexdigest() == expected, name
    assert not git(
        "diff",
        REGRESSION,
        SOURCE,
        "--",
        "apps/mobile/lib",
        "apps/mobile/test",
        "apps/mobile/android",
    )
    assert git("rev-parse", f"{BASE}:services/server/video_viewer") == git(
        "rev-parse", f"{SOURCE}:services/server/video_viewer"
    )
    assert git(
        "diff", "--name-only", BASE, SOURCE, "--", "apps/mobile/lib"
    ).decode().splitlines() == ["apps/mobile/lib/library/server_api.dart"]
    assert not git(
        "diff",
        BASE,
        SOURCE,
        "--",
        "apps/mobile/android",
        "apps/mobile/assets",
        "design/reference/library-first",
    )
    checks = read("checks.json")
    assert checks["regression_source"] == REGRESSION and checks["producer"] == SOURCE
    assert not checks["service_full_rerun"] and not checks["original_issue_reproduced"]
    assert "+672: All tests passed!" in (HERE / "client-full.log").read_text()
    related = (HERE / "recovery-tests-final.log").read_text()
    assert "+28: All tests passed!" in related
    marker = "ARCHIVE_REFUSED_UPLOAD_VERIFIED:"
    (record,) = [
        json.loads(line.split(marker)[1])
        for line in related.splitlines()
        if marker in line
    ]
    assert record["phase"] == "opening" and record["cause"] == "SocketException"
    assert record["original_reads"] == 2 and record["posts_after_reopening"] == 0
    assert record["journal_unchanged"] and record["local_file_removed"]
    assert "No issues found!" in (HERE / "analyze-restart.log").read_text()
    assert "All checks passed!" in (HERE / "ruff.log").read_text()
    cases = {
        "controlled-reply-restart": (8, 4, 13),
        "normal-after-control": (10, 4, 15),
    }
    for case, (app, system, pngs) in cases.items():
        source = read(case + "/source.json")
        assert source["commit"] == SOURCE
        assert source["prototype_tree"] == "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
        for name, digest in source["files"].items():
            assert (
                hashlib.sha256(git("show", f"{SOURCE}:{name}")).hexdigest() == digest
            ), name
        assert read(case + "/host-exit.json")["code"] == 0
        assert not (HERE / case / "restore-error.json").exists()
        result = read(case + "/result.json")
        assert (
            result["passed"]
            and result["native_points"] == app
            and result["system_points"] == system
        )
        assert len(list((HERE / case).glob("*.png"))) == pngs
        saved = read(case + "/saved-document.json")
        raw = gzip.decompress(
            (HERE / case / "exported-document.vvbackup.gz").read_bytes()
        )
        assert (
            len(raw) == saved["bytes"]
            and hashlib.sha256(raw).hexdigest() == saved["sha256"]
        )
        assert read(case + "/media-before.json") == read(case + "/media-after.json")
        view = read(case + "/restored-viewport.json")
        assert view["before"] == view["after"]
        assert not read(case + "/app-cleanup.json")["app_pid"]
    normal = "normal-after-control/"
    assert read(normal + "exit.json")["code"] == 0
    assert not read(normal + "fixture-final.json")["upload_truncated"]
    assert read(normal + "result.json")["restore_posts"] == 1
    normal_requests = read(normal + "requests.json")
    for path in (
        "/api/v1/management-backups",
        "/api/v1/management-backups/imports",
        "/api/v1/management-backups/restores",
    ):
        assert (
            sum(r["method"] == "POST" and r["path"] == path for r in normal_requests)
            == 1
        )
    controlled = "controlled-reply-restart/"
    assert (
        read(controlled + "exit.json")["code"] != 0
        and read(controlled + "resume-exit.json")["code"] == 0
    )
    failure = read(controlled + "transport-failure.json")
    assert (
        failure["phase"] == "readingResponse"
        and failure["cause_type"] == "HttpException"
    )
    assert failure["message"] == "Connection closed while receiving data"
    book = read(controlled + "failure-journal.json")
    (scope,) = book["scopes"].values()
    command = scope["inspect"]
    assert command.get("task") is None
    original = read(controlled + "resume-verified.json")
    assert (
        command["key"] == original["original_key"]
        and command["digest"] == original["sha256"]
    )
    killed = read(controlled + "failure-force-stop.json")
    resumed = read(controlled + "resumed-app-pid.json")
    assert (
        killed["old_pid"]
        and not killed["after_pid"]
        and resumed["pid"] != killed["old_pid"]
    )
    removed = read(controlled + "removed-owned-input.json")
    assert removed["removed"] and removed["id"] == command["file"]["id"]
    assert re.fullmatch(
        r"files/management-archives/[a-f0-9]{64}/[a-f0-9]{32}\.vvbackup",
        removed["path"],
    )
    first = read(controlled + "first-requests.json")
    imports = [
        r
        for r in first
        if r["method"] == "POST" and r["path"] == "/api/v1/management-backups/imports"
    ]
    assert len(imports) == 1 and imports[0]["idempotency_key"] == command["key"]
    assert not any(
        r["method"] == "POST" and r["path"].endswith("/restores") for r in first
    )
    later = read(controlled + "resumed-requests.json")
    assert later and all(r["method"] == "GET" for r in later)
    assert (
        sum(
            r["path"] == "/api/v1/management-backups/requests/inspect/" + command["key"]
            for r in later
        )
        == 1
    )
    actual = read(controlled + "accepted-import-sql.json")
    assert actual["task"]["id"] == original["task"] == actual["receipt"]["result"]["id"]
    assert (
        actual["task"]["status"] == "completed"
        and actual["task"]["kind"] == "backup_inspect_v2"
    )
    assert actual["receipt"]["id"] == "management.backup_inspect_v2:" + command["key"]
    assert actual["epoch"] == original["epoch"] and original["confirmation_off"]
    assert actual["counts"] == {
        "roots": 27,
        "tags": 2,
        "pack_tag_definitions": 2,
        "packs": 1,
        "pack_pages": 1,
    }
    assert read(controlled + "result.json")["original_issue_reproduced"] is False
    assert read("cleanup.json")["owned_avd_absent"] and all(
        c["absent"] for c in read("cleanup.json")["containers"]
    )
    bad = read(
        "intermediate-before-display-fix/controlled-reply-restart/restore-error.json"
    )
    assert bad["error"] == "KeyError('size')"
    assert (
        read("intermediate-before-display-fix/controlled-reply-restart/source.json")[
            "commit"
        ]
        == "d22d6fcaf7396fb1cf90f83cb4246a715de39216"
    )
    recovery = read("display-recovery.json")
    assert recovery["before"] != recovery["expected"]
    assert (
        recovery["after"]
        == recovery["expected"]
        == read("cleanup.json")["restored_display"]
    )
    assert (HERE / "preserved-services-before.txt").read_bytes() == (
        HERE / "preserved-services-after.txt"
    ).read_bytes()
    return {
        "evidence_verified": True,
        "producer": SOURCE,
        "inputs": len(manifest["files"]),
        "client_tests": 672,
        "related_tests": 28,
        "native_points": 26,
        "pngs": 28,
        "controlled_restart_reads": len(later),
        "controlled_restart_posts": 0,
        "original_issue_reproduced": False,
        "published": False,
    }


if __name__ == "__main__":
    print(json.dumps(verify(), ensure_ascii=False, indent=2))

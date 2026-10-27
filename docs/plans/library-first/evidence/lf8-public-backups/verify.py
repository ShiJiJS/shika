"""Read-only replay of public-capability evidence; no server or Android mutations."""

import gzip
import hashlib
import json
import re
import subprocess
from pathlib import Path

EVIDENCE = Path(__file__).resolve().parent
ROOT = EVIDENCE.parents[4]
SOURCE = "6287cc4747da4160ca20e6e51559183f8e1ed61c"
REGRESSION = "2f62dd02b2c7e6b37d1f3da0f82a9e479f30566e"
BASE = "3a72b1eb"


def read(name):
    return json.loads((EVIDENCE / name).read_text())


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def verify():
    manifest = read("manifest.json")
    assert manifest["producer"] == SOURCE
    for name, digest in manifest["files"].items():
        assert hashlib.sha256((EVIDENCE / name).read_bytes()).hexdigest() == digest, (
            name
        )
    source = read("native/source.json")
    assert source["commit"] == SOURCE
    for name, digest in source["files"].items():
        assert hashlib.sha256(git("show", f"{SOURCE}:{name}")).hexdigest() == digest, (
            name
        )
    assert source["prototype_tree"] == "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
    assert not git(
        "diff",
        BASE,
        SOURCE,
        "--",
        "apps/mobile/lib",
        "apps/mobile/android",
        "apps/mobile/assets",
    )
    old_app = git("show", f"{BASE}:services/server/video_viewer/app.py")
    new_app = git("show", f"{SOURCE}:services/server/video_viewer/app.py")
    assert new_app == old_app.replace(
        b'                "management_purge_history",\n',
        b'                "management_purge_history",\n                "backup_v2",\n',
        1,
    )
    fixture = git("show", f"{SOURCE}:services/server/tests/archive_app_fixture.py")
    assert b'append("backup_v2")' not in fixture
    checks = read("check-results.json")
    assert checks["source"] == REGRESSION
    assert not git("diff", REGRESSION, SOURCE, "--", "apps/mobile", "services/server")
    assert checks["client_tests"] == 670 and checks["client_exit"] == 0
    client = (EVIDENCE / "client-full.log").read_text()
    assert "+670: All tests passed!" in client and "[E]" not in client
    assert "No issues found!" in (EVIDENCE / "analyze.log").read_text()
    server = (EVIDENCE / "server-full.log").read_text()
    match = re.search(r"(\d+) passed", server)
    assert match and " FAILED " not in server and " failed," not in server
    assert checks["server_tests"] == int(match[1])
    assert checks["server_script_exit"] == 1  # inherited repository format gate
    comparison = read("format-comparison.json")
    assert comparison["same_preexisting_files"] and comparison["count"] == 27
    assert comparison["files"]["baseline"] == comparison["files"]["current"]
    assert "27 files would be reformatted" in server
    assert checks["format_gate"] == "preexisting_27_files"
    result = read("native/result.json")
    assert result["passed"] and result["cancel_inputs"] and not result["large_document"]
    assert result["native_points"] == 10 and result["system_points"] == 4
    assert read("native/exit.json")["code"] == 0
    info, after = (
        read("native/public-info-before.json"),
        read("native/public-info-after.json"),
    )
    for item in (info, after):
        assert "backup_v2" in item["capabilities"]
        assert {"management_authority", "management_history"} <= set(
            item["capabilities"]
        )
        assert item["management_backups"] == {
            "versions": [1, 2],
            "max_bytes": 67108864,
            "max_roots": 256,
        }
    assert info["management_history_available"] is False
    assert after["management_history_available"] is True
    assert info["management_epoch"] != after["management_epoch"]
    saved = read("native/saved-document.json")
    raw = gzip.decompress(
        (EVIDENCE / "native/exported-document.vvbackup.gz").read_bytes()
    )
    assert len(raw) == saved["bytes"] < 32 * 1024 * 1024
    assert hashlib.sha256(raw).hexdigest() == saved["sha256"]
    journals = read("native/journals.json")
    assert (
        len(journals) == 6
        and journals[0]["state"] == journals[1]["state"] == journals[2]["state"]
    )
    requests = read("native/requests.json")
    for path in (
        "/api/v1/management-backups",
        "/api/v1/management-backups/imports",
        "/api/v1/management-backups/restores",
        "/api/v1/auth/login",
    ):
        assert (
            sum(r["method"] == "POST" and r["path"] == path for r in requests) == 1
        ), path
    for scene in ("save-cancelled", "pick-cancelled"):
        rows = read(f"native/archive-ui-{scene}-requests.json")
        assert not any(
            r["method"] == "POST"
            and r["path"]
            in {
                "/api/v1/management-backups/imports",
                "/api/v1/management-backups/restores",
            }
            for r in rows
        )
    assert read("native/media-before.json") == read("native/media-after.json")
    restored = read("native/restored-viewport.json")
    assert restored["before"] == restored["after"]
    assert not read("native/app-cleanup.json")["app_pid"]
    assert (EVIDENCE / "preserved-services-before.txt").read_bytes() == (
        EVIDENCE / "preserved-services-after.txt"
    ).read_bytes()
    assert read("avd-cleanup.json")["owned_pid_absent"]
    diagnostic = read("diagnostic-launcher-anr/host-events.json")
    assert diagnostic["events"] == [] and "nexuslauncher" in str(diagnostic["errors"])
    assert read("diagnostic-launcher-anr/exit.json")["code"] != 0
    assert "nexuslauncher" in read("launcher-recovery.json")["focus_after"]
    assert read("diagnostic-upload-network/exit.json")["code"] == 1
    upload_error = (EVIDENCE / "diagnostic-upload-network/android-test.log").read_text()
    assert "暂时无法连接服务" in upload_error
    failed_requests = read("diagnostic-upload-network/requests-final.json")
    assert not any(
        r["method"] == "POST" and r["path"] == "/api/v1/management-backups/imports"
        for r in failed_requests
    )
    assert read("diagnostic-transport-logging/exit.json")["code"] == 0
    assert (
        read("diagnostic-transport-logging/source.json")["files"][
            "apps/mobile/lib/library/server_api.dart"
        ]
        != source["files"]["apps/mobile/lib/library/server_api.dart"]
    )
    assert not read("native/initial-scan.json")["scanning"]
    preparation_error = (EVIDENCE / "native-runner-final.log").read_text()
    assert "HTTP Error 409" in preparation_error
    assert (
        "ValueError: not enough values"
        in (EVIDENCE / "native-runner-final-ready.log").read_text()
    )
    return {
        "evidence_verified": True,
        "source": SOURCE,
        "inputs": len(manifest["files"]),
        "client_tests": 670,
        "server_tests": checks["server_tests"],
        "format_gate": "preexisting_27_files",
        "native_points": 14,
        "production_backup_v2": True,
        "published": False,
    }


if __name__ == "__main__":
    print(json.dumps(verify(), ensure_ascii=False, indent=2))

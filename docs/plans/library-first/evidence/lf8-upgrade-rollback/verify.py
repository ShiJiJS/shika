#!/usr/bin/env python3
"""Verify stored observations without starting services or replaying commands."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SERVER = "b79da7b9c4d2ab099c055b8eb855904e32abb0a5"
APP = "cf9920257f7bc88af534ea6fb3177cef69c0a161"
NEW = "sha256:886b79b72ecb9116087d892f230471943121f24ccef093113cc3197b4607fef4"
OLD = "sha256:980c9a01bca1f826521da2f0f5660be863dc28fc7592c888bc800efe4d02d67e"
PROTOTYPE = "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"


def read(name):
    return json.loads((HERE / name).read_text())


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for value in iter(lambda: stream.read(1048576), b""):
            result.update(value)
    return result.hexdigest()


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def ui(name):
    return "\n".join(
        n.get("text", "") + "\n" + n.get("content-desc", "")
        for n in ET.parse(HERE / "screens" / (name + ".xml")).iter("node")
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifacts", type=Path)
    args = parser.parse_args()
    manifest = read("manifest.json")
    for name, expected in manifest["files"].items():
        assert digest(HERE / name) == expected, name
    producer = read("frozen-producer.json")
    assert producer["server_source"] == SERVER and producer["app_source"] == APP
    assert producer["server_image"] == NEW and producer["app_version_code"] == 6
    assert not git("diff", APP, SERVER, "--", "apps/mobile/lib", "apps/mobile/android", "apps/mobile/pubspec.yaml")
    assert git("rev-parse", SERVER + ":design/reference/library-first").decode().strip() == PROTOTYPE
    source = read("runtime-source.json")
    assert source["source"] == SERVER and source["image"] == NEW and not source["tests_present"]
    assert len(source["files"]) == 73
    for name, expected in source["files"].items():
        assert hashlib.sha256(git("show", SERVER + ":services/server/" + name)).hexdigest() == expected
    assert hashlib.sha256(git("show", SERVER + ":services/server/tests/test_maintenance_tasks.py")).hexdigest() == producer["red_tests_sha256"]
    assert "5 failed, 10 passed, 6 deselected" in (HERE / "diagnostics/task-summary-final-tests-red.log").read_text()
    assert "21 passed" in (HERE / "task-summary-green.log").read_text()
    assert "462 passed" in (HERE / "server-full.log").read_text()
    assert "All checks passed!" in (HERE / "ruff.log").read_text()
    assert "140 files already formatted" in (HERE / "format.log").read_text()
    checks = read("checks.json")
    assert checks["source"] == SERVER and checks["server_test_exit"] == 0
    assert checks["client_full_suite_rerun"] is False
    for name, expected in checks["logs"].items():
        assert digest(HERE / name) == expected

    baseline = read("baseline-projection.json")
    assert baseline["alembic_version"]["rows"] == [{"version_num": "0004"}]
    assert baseline["videos"]["count"] == 2 and baseline["video_tags"]["count"] == 2
    assert baseline["trash_items"]["count"] == baseline["tags"]["count"] == baseline["access_tokens"]["count"] == 1
    assert baseline["request_records"]["count"] == 3
    assert baseline["playback_rounds"]["count"] == 1 and baseline["round_entries"]["count"] == 2
    stable = ["tags", "video_tags", "playback_rounds", "round_entries", "request_records", "file_operations", "file_steps", "trash_items"]
    seed = read("seeded.json")
    pids, qemu = [], set()
    for number in range(1, 4):
        result = read(f"accepted-{number}-result.json")
        assert result["complete"] and result["same_sample"]
        assert result["server_source"] == SERVER and result["new_image"] == NEW and result["old_image"] == OLD
        assert result["media_sha_unchanged"] and result["same_qemu_through_cycle"]
        qemu.add(result["owned_qemu_pid"])
        restore = read(f"accepted-{number}-restore.json")
        assert restore["restored_all_data_files_equal"] and restore["schema"] == "0004"
        assert restore["data_directory_inode_preserved"] and restore["sqlite_file_inode_preserved"]
        assert restore["app_stopped"] and restore["upgraded_container_removed"] and restore["config_equal"]
        assert restore["files"] == {k[len("data/"):]: v for k, v in read("baseline-files.json").items() if k.startswith("data/")}
        for version, image in [("new", NEW), ("old", OLD)]:
            phase = f"accepted-{number}-{version}"
            runtime = read(phase + "/runtime.json")
            assert runtime["Image"] == image and "video_viewer.app:create_app" in runtime["Args"]
            assert not any(m["Destination"] == "/app" for m in runtime["Mounts"])
            preflight = read(phase + "/container-preflight.json")
            assert preflight["image"] == OLD and preflight["schema"] == "0004"
            assert preflight["before_sha256"] == preflight["after_sha256"] == preflight["host_sha256"] == restore["files"]["library.sqlite3"]
            assert preflight["integrity"] == "ok"
            assert read(phase + "/stopped.json")["removed"]
            start = read(phase + "-app-start.json")
            assert start["cold_start"] and start["new_pid"]
            pids.append(start["new_pid"])
            requests = read(phase + "/app-requests.json")
            trace = [json.loads(s) for s in (HERE / "trace" / phase / "requests.jsonl").read_text().splitlines()]
            offset = start["trace_start_offset"]
            assert trace[offset:offset + len(requests)] == requests
            assert all(v["status"] in (200, 201, 206) for v in requests)
            assert not any(v["path"] == "/api/v1/auth/login" for v in requests)
            writes = [v for v in requests if v["method"] != "GET"]
            observation = read(phase + "/ui-proof.json")
            assert observation["no_login"] and observation["available_video_count"] == observation["trash_count"] == 1
            assert observation["actual_switches"]["暗黑模式"] == "true"
            assert observation["actual_switches"]["准备相邻视频，前后各一条；关闭可减少网络与解码占用"] == "false"
            inspection = read(phase + "/host-http-inspection.json")
            assert inspection["app_already_stopped"] and inspection["temporary_inspection_token_revoked"]
            assert inspection["original_token_table_unchanged"] and inspection["receipt"] == seed["receipt"]
            control = trace[inspection["trace_start_offset"]:inspection["trace_end_offset"]]
            assert [(r["method"], r["path"]) for r in control if r["method"] != "GET"] == [("POST", "/api/v1/auth/login"), ("DELETE", "/api/v1/auth/session")]
            assert inspection["info"]["server_id"] == seed["info"]["server_id"]
            if version == "new":
                assert len(writes) == 1 and writes[0]["method"] == "POST" and writes[0]["path"] == "/api/v1/tags"
                assert read(phase + "/automatic-snapshot-projection.json") == baseline
                projection = read(phase + "/after-startup-original-columns.json")
                assert projection["alembic_version"]["rows"] == [{"version_num": "0014"}]
                assert projection["access_tokens"] == baseline["access_tokens"]
                for name in stable:
                    assert projection[name] == baseline[name], (phase, name)
                startup = read(phase + "/startup-requests.json")
                assert all(r["method"] == "GET" for r in startup)
                assert not any("/stream" in r["path"] or "/opened" in r["path"] for r in startup)
                assert observation["old_task_state"] == "completed" and observation["old_task_id"] == seed["task"]["id"]
                assert "视频移入回收站\n已完成" in ui(phase + "-tasks")
                assert "没有符合条件的图包" in ui(phase + "-packs-empty")
                assert f"AFTER_UPGRADE_FINAL_{number}" in ui(phase + "-marker-created")
                assert inspection["summary"]["state"] == "completed" and inspection["summary"]["total"] == inspection["summary"]["processed"] == 1
            else:
                assert writes == [] and observation["post_upgrade_marker_absent"]
                assert "AFTER_UPGRADE" not in ui(phase + "-tags") and "LEGACY_ONLY" in ui(phase + "-tags")
                assert "capabilities" not in inspection["info"]
                projection = read(phase + "/after-ui-projection.json")
                for name in stable + ["access_tokens"]:
                    assert projection[name] == baseline[name], (phase, name)
    assert len(set(pids)) == 6 and len(qemu) == 1
    cleanup = read("cleanup.json")
    assert cleanup["complete"] and cleanup["owned_qemu_absent"] and cleanup["original_services_unchanged"]
    assert cleanup["donor_data_unchanged"] and cleanup["media_unchanged"]
    assert all(row["absent"] for row in cleanup["owned_containers"])
    assert (HERE / "original-services-before.txt").read_bytes() == (HERE / "original-services-after.txt").read_bytes()
    assert read("diagnostics/final-1-qemu-exit/observed-exit.json")["native_round_complete"] is False
    mismatch = read("diagnostics/verified-1-old-start/diagnosis.json")
    assert mismatch["acceptance_cycle_complete"] is False and mismatch["exit_code"] == 3
    assert mismatch["cause_unconfirmed"] is True
    final_package = (HERE / "final-package.txt").read_text()
    assert "versionCode=6 " in final_package and "DEBUGGABLE" not in final_package
    if args.artifacts:
        archive = read("runtime-archive.json")
        path = args.artifacts / Path(archive["path"]).name
        assert path.stat().st_size == archive["bytes"] and digest(path) == archive["sha256"]
    print(json.dumps({"verified": True, "source": SERVER, "evidence_files": len(manifest["files"]), "native_cycles": 3, "normal_app_processes": len(pids), "same_public_sample": True, "server_tests": 462, "archive_hash_rechecked": bool(args.artifacts)}))


if __name__ == "__main__":
    main()

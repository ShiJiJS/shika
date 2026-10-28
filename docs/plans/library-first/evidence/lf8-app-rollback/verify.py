#!/usr/bin/env python3
"""Read-only verification of the paired APK and native replacement evidence."""

import argparse
import hashlib
import json
import re
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

E = Path(__file__).resolve().parent
ROOT = E.parents[4]
CERT = "f5abd3bd11d94b3aaee66ab65e6a666a228a4d64edf4b86de9327ae9b8a59161"
SOURCE = "a3c7659a738619842f9923078363135299210826"
CF = "cf9920257f7bc88af534ea6fb3177cef69c0a161"
IMAGE = "sha256:886b79b72ecb9116087d892f230471943121f24ccef093113cc3197b4607fef4"


def read(name):
    return json.loads((E / name).read_text())


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def screen(name):
    nodes = ET.fromstring((E / "screens" / (name + ".xml")).read_bytes()).iter("node")
    return "\n".join(n.get("text", "") + "\n" + n.get("content-desc", "") for n in nodes)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts", type=Path)
    args = parser.parse_args()
    manifest = read("manifest.json")
    assert set(manifest) == {
        str(p.relative_to(E))
        for p in E.rglob("*")
        if p.is_file() and p.name not in {"manifest.json", "README.md", "verify.py"}
    }
    for name, expected in manifest.items():
        assert digest(E / name) == expected, name
    built = read("build/result.json")
    assert built["complete"] and built["source"] == SOURCE
    assert built["legacy_source"] == "f5fe32c9e8136fa0b54a272609d8b7f2ac1d83ba"
    assert len(built["steps"]) == 13
    for step in built["steps"]:
        assert step["exit_code"] == 0
        assert digest(E / "build" / (step["name"] + ".log")) == step["log_sha256"]
    for kind, count in [("rollback", 85), ("forward", 14)]:
        a = built[kind]
        assert a["version_code"] == 8 and a["certificate_sha256"] == CERT
        assert a["normal_entrypoint"] and not a["integration_test_plugin"]
        assert a["flutter_engine_abis"] == ["arm64-v8a"]
        assert re.search(
            r"\+" + str(count) + r": All tests passed!",
            (E / "build" / (kind + "-tests.log")).read_text(),
        )
        badging = (E / "build" / (kind + "-badging.log")).read_text()
        assert "versionCode='8'" in badging and "versionName='" + a["version"] + "'" in badging
        assert "application-debuggable" not in badging
        if args.artifacts:
            path = args.artifacts / Path(a["path"]).name
            assert path.stat().st_size == a["bytes"] and digest(path) == a["sha256"]
    subprocess.run(
        [
            "git",
            "diff",
            "--exit-code",
            CF,
            SOURCE,
            "--",
            "apps/mobile/lib",
            "apps/mobile/android",
            "design/reference/library-first",
        ],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    )
    subprocess.run(
        [
            "git",
            "diff",
            "--exit-code",
            "b79da7b9c4d2ab099c055b8eb855904e32abb0a5",
            SOURCE,
            "--",
            "services/server",
        ],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    )
    for overlay in built["rollback_overlays"].values():
        if overlay.get("change"):
            continue  # Explicit old-main/repository patches, hashed by the export builder.
        blob = subprocess.check_output(["git", "show", overlay["from"]], cwd=ROOT)
        assert hashlib.sha256(blob).hexdigest() == overlay["sha256"]
    sequence = [
        "forward8-first",
        "rollback8-first",
        "forward8-return",
        "rollback8-repeat",
        "forward8-repeat",
    ]
    prior = None
    for name in sequence:
        i = read("records/" + name + "-install.json")
        assert i["command"][:5] == ["adb", "-s", "emulator-5556", "install", "-r"]
        assert i["no_uninstall_or_clear"] and "Success" in i["output"]
        b, a = i["before"], i["after"]
        for field in ["firstInstallTime", "dataDir", "appId"]:
            assert b[field] == a[field]
        if prior:
            assert b == prior
        else:
            assert b["versionCode"].startswith("6 ")
        assert a["versionCode"].startswith("8 ")
        kind = "rollback" if name.startswith("rollback") else "forward"
        assert a["versionName"] == built[kind]["version"] and i["sha256"] == built[kind]["sha256"]
        prior = a
    windows = read("startup-windows.json")
    assert len(windows) == 6 and len({w["pid"] for w in windows.values()}) == 6
    for name, w in windows.items():
        assert w["requests"] and not any(r["path"] == "/api/v1/auth/login" for r in w["requests"])
        if w["kind"] == "new":
            assert all(
                r["method"] == "GET" and "/stream" not in r["path"] and "/opened" not in r["path"]
                for r in w["requests"]
            ), name
    before = read("records/before-rollback-preferences.json")
    assert before["videoOrder"] == "sequential" and len(before["defaultMigrations"]) == 2
    changed = {**before, "dark": False, "preloadAdjacent": True}
    for name in [
        "rollback8-settings-saved",
        "rollback8-before-forward",
        "forward8-return",
        "forward8-preserved",
        "rollback8-repeat",
        "forward8-repeat",
        "final",
    ]:
        assert read("records/" + name + "-preferences.json") == changed, name
    assert read("records/appearance-fixture-proof.json")["explicit_test_fixture"]
    b = read("records/before-rollback-projection.json")
    old = read("records/rollback8-after-confirmed-undo.json")
    final = read("records/stopped-final-projection.json")
    for d in [b, old, final]:
        assert d["integrity"] == "ok" and not d["foreign_key_errors"]
        assert d["access_tokens"] == b["access_tokens"] and d["access_tokens"]["count"] == 1
        for name in ["tags", "video_tags", "pack_tag_definitions", "pack_tag_links"]:
            assert d[name] == b[name]
    for name in [k for k in old if "pack" in k]:
        assert old[name] == b[name], name
    for name in ["pack_preferences", "pack_pages", "packs"]:
        assert final[name] == b[name], name
    stable_progress = [
        "pack_id",
        "page_id",
        "offset_ratio",
        "completed",
        "content_version",
        "recovery_reason",
    ]
    for key in stable_progress:
        assert final["pack_progress"]["rows"][0][key] == b["pack_progress"]["rows"][0][key]
    previous_ops = {r["id"] for r in b["file_operations"]["rows"]}
    ops = [r for r in old["file_operations"]["rows"] if r["id"] not in previous_ops]
    assert sorted(r["kind"] for r in ops) == ["trash", "undo"]
    trash = next(r for r in ops if r["kind"] == "trash")
    undo = next(r for r in ops if r["kind"] == "undo")
    assert undo["undo_of"] == trash["id"]
    for op in ops:
        task = next(t for t in final["tasks"]["rows"] if t["id"] == op["id"])
        result = json.loads(task["result"])
        assert (
            task["status"] == "completed"
            and result["total"] == result["processed"] == result["succeeded"] == 1
        )
    assert undo["id"] in screen("forward8-old-undo-detail")
    assert "2 个视频" in screen("rollback8-library-after-undo")
    assert "纵向拼接" in screen("final-reader") and "2 / 3" in screen("final-reader")
    assert "LEGACY_ONLY" in screen("final-tags") and "PACK_ONLY" not in screen("final-tags")
    assert "PACK_ONLY" in screen("final-pack-tags-after") and "LEGACY_ONLY" not in screen(
        "final-pack-tags-after"
    )
    runtime = read("records/runtime.json")
    assert (
        runtime["Image"] == IMAGE
        and runtime["Config"]["Labels"]["video-viewer.lab"] == "lf8-app-rollback"
    )
    for m in runtime["Mounts"]:
        if m["Destination"] in ["/media/videos", "/media/packs"]:
            assert not m["RW"]
    cleanup = read("records/cleanup.json")
    for key in [
        "removed",
        "emulator_closed",
        "original_four_services_unchanged",
        "donor_unchanged",
        "videos_unchanged",
        "packs_unchanged",
        "phone_nas_untouched",
    ]:
        assert cleanup[key], key
    assert (E / "records/services-before.txt").read_bytes() == (
        E / "records/services-after.txt"
    ).read_bytes()
    print(
        json.dumps(
            {
                "verified_inputs": len(manifest),
                "cover_installs": 5,
                "roundtrips": 2,
                "tests_this_stage": 99,
                "artifacts_checked": bool(args.artifacts),
            }
        )
    )


if __name__ == "__main__":
    main()

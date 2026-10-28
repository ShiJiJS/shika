#!/usr/bin/env python3
"""Read-only verification of the frozen preview evidence; no device mutations."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SOURCE = "cf9920257f7bc88af534ea6fb3177cef69c0a161"
BASE = "38dc07dfe964517175418578310f231c4b92809c"
PROTOTYPE = "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
CERT = "f5abd3bd11d94b3aaee66ab65e6a666a228a4d64edf4b86de9327ae9b8a59161"


def read(name):
    return json.loads((HERE / name).read_text())


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for part in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(part)
    return value.hexdigest()


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def ui(name):
    nodes = ET.parse(HERE / "screens" / (name + ".xml")).iter("node")
    return "\n".join(
        n.get("text", "") + "\n" + n.get("content-desc", "") for n in nodes
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifacts", type=Path)
    parser.add_argument("--recompute-ast", action="store_true")
    args = parser.parse_args()
    manifest = read("manifest.json")
    assert manifest["source"] == SOURCE
    for name, expected in manifest["files"].items():
        assert digest(HERE / name) == expected, name

    assert git("rev-parse", SOURCE + ":design/reference/library-first").decode().strip() == PROTOTYPE
    assert git("rev-parse", "HEAD:design/reference/library-first").decode().strip() == PROTOTYPE
    result = read("reference-free/result.json")
    assert result["source_commit"] == SOURCE and result["complete"] is True
    assert hashlib.sha256(git("show", SOURCE + ":scripts/check-reference-isolation.py")).hexdigest() == result["script_sha256"]
    expected_steps = {
        "flutter-version", "flutter-pub-get", "flutter-analyze", "flutter-test",
        "android-debug", "android-release", "server-image", "server-ruff",
        "server-format", "server-pytest",
    }
    assert {s["name"] for s in result["steps"]} == expected_steps
    for step in result["steps"]:
        assert step["status"] == "passed" and step["required"] is True
        assert step["exit_code"] == 0
        assert digest(HERE / "reference-free/checks" / (step["name"] + ".log")) == step["log_sha256"]
    assert "+672: All tests passed!" in (HERE / "reference-free/checks/flutter-test.log").read_text()
    assert "447 passed, 1 warning" in (HERE / "reference-free/checks/server-pytest.log").read_text()
    assert result["original_reference_unchanged"] and result["reference_absent_in_export"]
    assert result["mutated_tracked_files"] == []
    assert result["app_package_root_is_export"]
    assert result["removed_reference_files"] == 72
    inputs = read("reference-free/export-files.json")
    tracked = git("ls-tree", "-r", "--name-only", SOURCE).decode().splitlines()
    retained = {p for p in tracked if not p.startswith("design/reference/")}
    assert set(inputs) == retained and len(retained) == result["retained_tracked_files"] == 15792
    # Recheck actual application/server/build inputs against immutable Git, not HEAD.
    checked_source_files = 0
    for name, expected in inputs.items():
        if name.startswith(("apps/mobile/lib/", "apps/mobile/android/", "services/server/", "scripts/")) or name in {"apps/mobile/pubspec.yaml", "apps/mobile/pubspec.lock"}:
            assert hashlib.sha256(git("show", SOURCE + ":" + name)).hexdigest() == expected, name
            checked_source_files += 1
    references = read("reference-free/original-reference-files.json")
    tracked_references = {p[len("design/reference/"):] for p in tracked if p.startswith("design/reference/")}
    assert len(tracked_references) == 72 and tracked_references <= set(references)
    for name in tracked_references:
        assert hashlib.sha256(git("show", SOURCE + ":design/reference/" + name)).hexdigest() == references[name]
    # The helper also protects three ignored, local prototype validation reports.
    local_reference_reports = set(references) - tracked_references
    assert local_reference_reports == {"library-first/validation-pack-cleanup.json", "library-first/validation-settings.json", "library-first/validation.json"}
    for name in local_reference_reports:
        local = ROOT / "design/reference" / name
        if local.exists():
            assert digest(local) == references[name]

    ast = read("ast-equivalence.json")
    assert ast["base"] == BASE and ast["all_ast_equal"]
    assert ast["changed_count"] == 27
    ast_inputs = []
    for name, record in ast["files"].items():
        before = git("show", BASE + ":services/server/" + name)
        after = git("show", SOURCE + ":services/server/" + name)
        assert hashlib.sha256(before).hexdigest() == record["before_sha256"]
        assert hashlib.sha256(after).hexdigest() == record["after_sha256"]
        assert record["ast_equal"] and record["changed"] == (before != after)
        if args.recompute_ast:
            ast_inputs.append([name, before.decode(), after.decode()])
    image = read("runtime-image.json")
    if args.recompute_ast:
        code = (
            "import ast,json,sys; rows=json.load(sys.stdin); "
            "assert all(ast.dump(ast.parse(a))==ast.dump(ast.parse(b)) for n,a,b in rows); "
            "print(json.dumps({'all_ast_equal':True,'files':len(rows),'python':sys.version}))"
        )
        process = subprocess.run(
            ["docker", "run", "--rm", "-i", "--read-only", image["Id"], "python", "-c", code],
            input=json.dumps(ast_inputs), text=True, capture_output=True, check=True,
        )
        print(process.stdout.strip())

    apk = read("preview-apk.json")
    archive = read("runtime-archive.json")
    assert apk["source"] == archive["source"] == SOURCE
    assert apk["version_code"] == 6 and apk["version"] == "0.2.0-preview.1"
    assert apk["normal_entrypoint"] and not apk["integration_test_plugin"] and not apk["checks_pending"]
    assert apk["sha256"] == result["apks"]["release"]["sha256"]
    assert result["apks"]["release"]["flutter_engine_abis"] == ["arm64-v8a"]
    assert not result["apks"]["release"]["integration_test_plugin_dex_path"]
    assert result["apks"]["release"]["design_paths"] == []
    assert apk["certificate_sha256"] == read("old-apk.json")["certificate_sha256"] == CERT
    for file in ["old-signature.txt", "preview-signature.txt"]:
        assert "Signer #1 certificate SHA-256 digest: " + CERT in (HERE / file).read_text()
    for name, code in [("old-package.txt", "5"), ("new-package.txt", "6")]:
        package = (HERE / name).read_text()
        assert "versionCode=" + code + " " in package and "DEBUGGABLE" not in package
    def package_fields(name):
        return dict(line.split("=", 1) for line in (HERE / name).read_text().splitlines() if "=" in line)
    old, new = package_fields("old-package.txt"), package_fields("new-package.txt")
    for key in ["dataDir", "firstInstallTime"]:
        assert old[key] == new[key]
    assert old["lastUpdateTime"] != new["lastUpdateTime"]
    assert "Success" in (HERE / "new-apk-upgrade-install.log").read_text()
    assert read("upgrade-before-sql.json") == read("upgrade-after-startup-sql.json")
    assert len(read("upgrade-before-sql.json")) == 8  # seven projections + token-table summary
    startup = read("upgrade-startup-requests.json")
    assert len(startup) == 26 and all(x["method"] == "GET" for x in startup)
    assert not any("/stream" in x["path"] or "/opened" in x["path"] or "/auth/login" in x["path"] for x in startup)
    process = read("upgrade-process.json")
    assert process["old_absent_after_upgrade"] and process["old_pid"] != process["new_pid"]
    preferences = read("upgrade-preserved-preferences.json")
    assert preferences["dark"] is True and preferences["preload_adjacent"] is False
    assert preferences["endpoint"] == "http://10.0.2.2:8771"
    smoke = read("release-smoke.json")
    assert smoke["video_tags_separate"] and smoke["pack_tags_separate"] and smoke["password_not_retained"]
    assert smoke["reader_horizontal_page"] == smoke["reader_vertical_page"] == 2
    assert smoke["reader_returned_to_pack_library"]
    for text in ["媒体库", "图包", "UPGRADE_KEEP"]:
        assert text in ui("new-first-library")
    assert "PACK_ONLY" in ui("new-pack-tags") and "UPGRADE_KEEP" not in ui("new-pack-tags")
    assert "纵向拼接" in ui("new-reader-vertical") and "2 / 3" in ui("new-reader-vertical")
    legacy = read("legacy-compatibility.json")
    assert legacy["schema"] == "0004" and legacy["legacy_ui_fallback"]
    assert legacy["unsupported_pack_requests"] == 0
    assert all(r["status"] == 200 for r in legacy["requests"])
    assert not any("/packs" in r["path"] or "/pack-tags" in r["path"] for r in legacy["requests"])
    assert "LEGACY_ONLY" in ui("legacy-tags") and "UPGRADE_KEEP" not in ui("legacy-tags")
    assert "2 个视频" in ui("legacy-video-library")
    cleanup = read("cleanup.json")
    assert cleanup["cleanup_complete"] and cleanup["owned_emulator_absent"]
    assert cleanup["original_four_services_unchanged"]
    assert len(cleanup["owned_containers"]) == 2 and all(c["removed"] for c in cleanup["owned_containers"])
    assert (HERE / "preserved-services-before.txt").read_bytes() == (HERE / "preserved-services-after.txt").read_bytes()
    assert image["Config"]["Labels"]["org.opencontainers.image.revision"] == SOURCE
    assert image["Architecture"] == "arm64" and image["Os"] == "linux"
    assert "video_viewer.app:create_app" in image["Config"]["Cmd"]
    for name in ["upgrade", "legacy-upgrade"]:
        runtime = read(name + "/runtime.json")
        assert "video_viewer.app:create_app" in runtime["Args"]
        assert not any(m["Destination"] == "/app" for m in runtime["mounts"])
    if args.artifacts:
        for record in [apk, archive]:
            artifact = args.artifacts / Path(record["path"]).name
            assert artifact.stat().st_size == record["bytes"]
            assert digest(artifact) == record["sha256"]
    print(json.dumps({"verified": True, "evidence_files": len(manifest["files"]), "source": SOURCE, "source_files_rechecked": checked_source_files, "binary_hashes_rechecked": bool(args.artifacts), "ast_recomputed": args.recompute_ast}))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Verify public build receipts; optionally rehash the private export and APKs."""

import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path
from zipfile import ZipFile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SOURCE = "7c70e5983f8ed8cc3e71077910bc362434d266cb"
PROTOTYPE = "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
REQUIRED = {
    "flutter-version",
    "flutter-pub-get",
    "flutter-analyze",
    "flutter-test",
    "android-debug",
    "android-release",
    "server-image",
    "server-ruff",
    "server-pytest",
}


def digest(path):
    with path.open("rb") as stream:
        value = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
        return value.hexdigest()


def read(path):
    return json.loads(path.read_text())


def source_hashes():
    entries = subprocess.check_output(["git", "ls-tree", "-rz", SOURCE], cwd=ROOT).split(b"\0")
    paths = {}
    for entry in filter(None, entries):
        info, name = entry.split(b"\t", 1)
        mode, kind, oid = info.decode().split()
        assert kind == "blob" and mode in {"100644", "100755"}
        paths[name.decode()] = oid
    hashes = {}
    with tempfile.TemporaryFile() as requests:
        requests.write(("\n".join(sorted(set(paths.values()))) + "\n").encode())
        requests.seek(0)
        proc = subprocess.Popen(
            ["git", "cat-file", "--batch"],
            cwd=ROOT,
            stdin=requests,
            stdout=subprocess.PIPE,
        )
        try:
            for oid in sorted(set(paths.values())):
                header = proc.stdout.readline().decode().split()
                assert header[0] == oid and header[1] == "blob"
                remaining = int(header[2])
                value = hashlib.sha256()
                while remaining:
                    chunk = proc.stdout.read(min(remaining, 1024 * 1024))
                    assert chunk
                    value.update(chunk)
                    remaining -= len(chunk)
                assert proc.stdout.read(1) == b"\n"
                hashes[oid] = value.hexdigest()
            assert proc.wait() == 0
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()
    return {name: hashes[oid] for name, oid in paths.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", type=Path)
    args = parser.parse_args()
    manifest = read(HERE / "manifest.json")
    actual = {
        str(p.relative_to(HERE))
        for p in HERE.rglob("*")
        if p.is_file()
        and p.name not in {"manifest.json", "verification.json"}
        and "__pycache__" not in p.parts
    }
    assert actual == set(manifest), "Evidence manifest coverage differs"
    for name, expected in manifest.items():
        assert digest(HERE / name) == expected, name
    result = read(HERE / "run/result.json")
    assert result["source_commit"] == SOURCE and result["prototype_tree"] == PROTOTYPE
    assert result["complete"] and result["app_package_root_is_export"]
    assert result["original_reference_unchanged"] and result["reference_absent_in_export"]
    assert result["mutated_tracked_files"] == []
    steps = {step["name"]: step for step in result["steps"]}
    assert {name for name, step in steps.items() if step["required"]} == REQUIRED
    for name, step in steps.items():
        assert step["status"] == ("failed" if name == "server-format" else "passed")
        assert step["exit_code"] == (1 if name == "server-format" else 0)
        assert digest(HERE / f"run/checks/{name}.log") == step["log_sha256"]
    assert "+643: All tests passed!" in (HERE / "run/checks/flutter-test.log").read_text()
    assert "447 passed" in (HERE / "run/checks/server-pytest.log").read_text()
    assert "27 files would be reformatted" in (HERE / "run/checks/server-format.log").read_text()
    exported = read(HERE / "run/export-files.json")
    original = read(HERE / "run/original-reference-files.json")
    source = source_hashes()
    assert exported == {
        name: value for name, value in source.items() if not name.startswith("design/reference/")
    }, "Export does not match full retained Git source"
    assert len(exported) == result["retained_tracked_files"]
    tracked_reference = {
        name.removeprefix("design/reference/"): value
        for name, value in source.items()
        if name.startswith("design/reference/")
    }
    assert set(original) - set(tracked_reference) == {
        "library-first/validation.json",
        "library-first/validation-settings.json",
        "library-first/validation-pack-cleanup.json",
    }
    assert {name: original[name] for name in tracked_reference} == tracked_reference
    assert len(tracked_reference) == result["removed_reference_files"] == 72
    for name, value in tracked_reference.items():
        assert digest(ROOT / "design/reference" / name) == value
    assert result["script_sha256"] == source["scripts/check-reference-isolation.py"]
    assert digest(ROOT / "scripts/check-reference-isolation.py") == result["script_sha256"]
    # Later evidence/docs commits are allowed; runtime/build inputs stay identical.
    for name, value in exported.items():
        if name.startswith(("apps/mobile/", "services/server/")) or name in {
            "scripts/dev.sh",
            "scripts/dev-env.sh",
        }:
            assert digest(ROOT / name) == value, name
    packages = read(HERE / "run/package-config.json")["packages"]
    assert not any("design/reference" in p["rootUri"] for p in packages)
    package = next(p for p in packages if p["name"] == "video_viewer")
    assert package["rootUri"] == "../"
    for mode, info in result["apks"].items():
        assert mode in {"debug", "release"} and info["bytes"] > 0
        assert info["flutter_engine_abis"] == ["arm64-v8a"]
        assert info["design_paths"] == []
        assets = read(HERE / f"run/{mode}-apk-assets.json")
        assert len(assets) == info["flutter_assets"]
        assert not any(
            "design/reference" in name or "library-first/app.html" in name for name in assets
        )
        if mode == "release":
            assert not info["integration_test_plugin_dex_path"]
    assert set(result["apks"]) == {"debug", "release"}
    safety = read(HERE / "checks/unsafe-output-checks.json")
    assert {item["case"] for item in safety} == {"checkout", "dev-root", "existing-run"}
    assert all(item["exit_code"] == 2 and item["expected_refusal"] for item in safety)
    diagnostic = read(HERE / "diagnostics/run-1/result.json")
    assert diagnostic["source_commit"] == "36db1f461a7994f3cb55f1c297703204fd88012d"
    assert not diagnostic["complete"]
    old_steps = {step["name"]: step for step in diagnostic["steps"]}
    assert old_steps["android-release"]["status"] == "failed"
    assert old_steps["flutter-test"]["status"] == "passed"
    assert old_steps["server-pytest"]["status"] == "passed"
    for name, step in old_steps.items():
        assert digest(HERE / f"diagnostics/run-1/checks/{name}.log") == step["log_sha256"]
    assert (
        "Built build/app/outputs/flutter-apk/app-release.apk"
        in (HERE / "diagnostics/run-1/checks/android-release-standard-command.log").read_text()
    )
    if args.run_dir:
        folder = args.run_dir.resolve()
        assert read(folder / "result.json") == result
        for name, value in original.items():
            assert digest(ROOT / "design/reference" / name) == value
        for name, value in exported.items():
            assert digest(folder / "workspace" / name) == value, name
        assert not (folder / "workspace/design/reference").exists()
        for mode, info in result["apks"].items():
            apk = folder / f"workspace/apps/mobile/build/app/outputs/flutter-apk/app-{mode}.apk"
            assert digest(apk) == info["sha256"] and apk.stat().st_size == info["bytes"]
            with ZipFile(apk) as bundle:
                names = bundle.namelist()
                assert not any(
                    "design/reference/" in name or "library-first/app.html" in name
                    for name in names
                )
                assets = {
                    name: hashlib.sha256(bundle.read(name)).hexdigest()
                    for name in bundle.namelist()
                    if name.startswith("assets/flutter_assets/")
                }
                assert assets == read(HERE / f"run/{mode}-apk-assets.json")
                abis = sorted(
                    {
                        name.split("/")[1]
                        for name in names
                        if name.startswith("lib/") and name.endswith("/libflutter.so")
                    }
                )
                assert abis == info["flutter_engine_abis"]
                has_test_plugin = any(
                    b"dev/flutter/plugins/integration_test" in bundle.read(name)
                    for name in names
                    if name.startswith("classes") and name.endswith(".dex")
                )
                assert has_test_plugin == info["integration_test_plugin_dex_path"]
    print(
        json.dumps(
            {
                "verified": True,
                "source_commit": SOURCE,
                "manifest_inputs": len(manifest),
                "retained_source_files": len(exported),
                "client_tests": 643,
                "server_tests": 447,
                "known_server_format_files": 27,
                "private_export_and_apks_rehashed": bool(args.run_dir),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()

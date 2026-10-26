#!/usr/bin/env python3
"""Build and test a clean tracked export after removing its design reference.

Only the new export is changed. SDKs and package caches are shared through the
existing local development environment; APKs remain under the ignored output.
"""
# ruff: noqa: UP017  # macOS development scripts also run with Python 3.9.

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import unquote, urljoin, urlparse
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = "design/reference"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_hashes(folder):
    return {
        str(p.relative_to(folder)): sha(p)
        for p in sorted(folder.rglob("*"))
        if p.is_file()
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", default="HEAD")
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="New directory inside this checkout's ignored .dev directory",
    )
    args = parser.parse_args()
    output = args.output.resolve()
    private = (ROOT / ".dev").resolve()
    if output == private or not output.is_relative_to(private) or output.exists():
        parser.error("--output must be a new child directory of .dev")
    commit = subprocess.check_output(
        ["git", "rev-parse", args.ref + "^{commit}"], cwd=ROOT, text=True
    ).strip()
    changed = subprocess.check_output(
        [
            "git",
            "diff",
            "--name-only",
            commit,
            "--",
            "apps/mobile",
            "services/server",
            "scripts/dev.sh",
            "scripts/dev-env.sh",
        ],
        cwd=ROOT,
        text=True,
    )
    if changed.strip():
        parser.error(
            "Commit the app/server/development script changes before exporting them"
        )
    original = ROOT / REFERENCE
    original_hashes = tree_hashes(original)
    if original.exists() and not (original / "REFERENCE_ONLY.json").exists():
        parser.error(
            "The original reference marker must exist for this removal exercise"
        )
    output.mkdir(parents=True)
    workspace = output / "workspace"
    workspace.mkdir()
    logs = output / "checks"
    logs.mkdir()
    (output / "original-reference-files.json").write_text(
        json.dumps(original_hashes, ensure_ascii=False, indent=2) + "\n"
    )
    env = os.environ.copy()
    env["VV_DEV_HOME"] = str(Path(env.get("VV_DEV_HOME", private)).resolve())
    # The export lives below the real checkout; prevent accidental parent Git
    # discovery while still allowing Flutter's own SDK Git repository.
    env["GIT_CEILING_DIRECTORIES"] = str(output)
    env.pop("LF8_ASSIGNMENT_SHOTS", None)
    env.pop("LF8_TAG_SHOTS", None)
    prototype_entry = subprocess.check_output(
        ["git", "ls-tree", commit, REFERENCE + "/library-first"], cwd=ROOT, text=True
    ).split()
    result = {
        "source_commit": commit,
        "script_sha256": sha(Path(__file__)),
        "started_at": datetime.now(timezone.utc).isoformat(),
        "prototype_tree": prototype_entry[2] if prototype_entry else None,
        "steps": [],
        "complete": False,
    }

    def save():
        (output / "result.json").write_text(
            json.dumps(result, ensure_ascii=False, indent=2) + "\n"
        )

    def run(name, command, cwd=workspace, *, required=True):
        log = logs / (name + ".log")
        entry = {
            "name": name,
            "command": command,
            "cwd": str(cwd.relative_to(output)),
            "required": required,
            "status": "running",
        }
        result["steps"].append(entry)
        save()
        print(json.dumps({"step": name, "status": "running"}), flush=True)
        with log.open("wb") as stream:
            proc = subprocess.Popen(
                command, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT
            )
            entry["pid"] = proc.pid
            save()
            code = proc.wait()
        entry.update(
            status="passed" if code == 0 else "failed",
            exit_code=code,
            log_sha256=sha(log),
        )
        save()
        print(json.dumps({"step": name, "exit_code": code}), flush=True)
        return code == 0

    save()
    try:
        # A complete Git export preserves all tracked inputs. No untracked keys,
        # local.properties, generated build files or package configs are copied.
        with (output / "archive-export.log").open("wb") as log:
            archive = subprocess.Popen(
                ["git", "archive", "--format=tar", commit],
                cwd=ROOT,
                stdout=subprocess.PIPE,
                stderr=log,
            )
            extracted = subprocess.run(
                ["tar", "-xf", "-", "-C", str(workspace)],
                stdin=archive.stdout,
                stderr=log,
                check=False,
            )
            archive.stdout.close()
            if archive.wait() or extracted.returncode:
                raise RuntimeError("Clean source export failed")
        copied_reference = workspace / REFERENCE
        result["removed_reference_files"] = len(tree_hashes(copied_reference))
        if copied_reference.exists():
            marker = json.loads((copied_reference / "REFERENCE_ONLY.json").read_text())
            if marker.get("production_dependency") is not False:
                raise RuntimeError(
                    "Exported reference is not marked independently removable"
                )
            shutil.rmtree(copied_reference)
        assert not copied_reference.exists()
        assert (
            subprocess.run(
                ["git", "rev-parse", "--is-inside-work-tree"],
                cwd=workspace,
                env=env,
                capture_output=True,
                check=False,
            ).returncode
            != 0
        )
        tracked = subprocess.check_output(
            ["git", "ls-tree", "-r", "--name-only", commit], cwd=ROOT, text=True
        ).splitlines()
        retained = [name for name in tracked if not name.startswith(REFERENCE + "/")]
        manifest = {
            name: sha(workspace / name)
            for name in retained
            if (workspace / name).is_file()
        }
        (output / "export-files.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
        )
        result["retained_tracked_files"] = len(manifest)
        mobile = workspace / "apps/mobile"
        dev = ["bash", str(workspace / "scripts/dev.sh")]
        run("flutter-version", [*dev, "flutter", "--version", "--machine"], mobile)
        ready = run(
            "flutter-pub-get",
            [*dev, "flutter", "pub", "get", "--offline", "--enforce-lockfile"],
            mobile,
        )
        if ready:
            config = mobile / ".dart_tool/package_config.json"
            packages = json.loads(config.read_text())["packages"]
            package = next(p for p in packages if p["name"] == "video_viewer")
            package_root = Path(
                unquote(urlparse(urljoin(config.as_uri(), package["rootUri"])).path)
            ).resolve()
            assert package_root == mobile.resolve(), package_root
            shutil.copy2(config, output / "package-config.json")
            result["app_package_root_is_export"] = True
            run("flutter-analyze", [*dev, "flutter", "analyze", "--no-pub"], mobile)
            run("flutter-test", [*dev, "flutter", "test", "--no-pub", "test"], mobile)
            result["apks"] = {}
            for mode in ["debug", "release"]:
                built = run(
                    "android-" + mode,
                    [
                        *dev,
                        "flutter",
                        "build",
                        "apk",
                        "--" + mode,
                        # Flutter must regenerate the mode-specific plugin
                        # registrant when switching from debug to release.
                        "--target-platform",
                        "android-arm64",
                    ],
                    mobile,
                )
                if not built:
                    continue
                apk = mobile / ("build/app/outputs/flutter-apk/app-" + mode + ".apk")
                with ZipFile(apk) as bundle:
                    names = bundle.namelist()
                    assert not any(
                        REFERENCE + "/" in n or "library-first/app.html" in n
                        for n in names
                    )
                    assets = {
                        n: hashlib.sha256(bundle.read(n)).hexdigest()
                        for n in names
                        if n.startswith("assets/flutter_assets/")
                    }
                    native_abis = sorted(
                        {
                            n.split("/")[1]
                            for n in names
                            if n.startswith("lib/") and n.endswith(".so")
                        }
                    )
                    flutter_abis = sorted(
                        {
                            n.split("/")[1]
                            for n in names
                            if n.startswith("lib/") and n.endswith("/libflutter.so")
                        }
                    )
                    test_plugin = any(
                        b"dev/flutter/plugins/integration_test" in bundle.read(n)
                        for n in names
                        if n.startswith("classes") and n.endswith(".dex")
                    )
                    assert flutter_abis == ["arm64-v8a"]
                    if mode == "release":
                        assert not test_plugin
                (output / (mode + "-apk-assets.json")).write_text(
                    json.dumps(assets, indent=2) + "\n"
                )
                result["apks"][mode] = {
                    "sha256": sha(apk),
                    "bytes": apk.stat().st_size,
                    "flutter_assets": len(assets),
                    "design_paths": [],
                    "native_abis": native_abis,
                    "flutter_engine_abis": flutter_abis,
                    "integration_test_plugin_dex_path": test_plugin,
                }
        image = "video-viewer-reference-check:" + commit[:12]
        if run(
            "server-image",
            [
                "docker",
                "build",
                "--target",
                "test",
                "-t",
                image,
                str(workspace / "services/server"),
            ],
        ):
            docker = [
                "docker",
                "run",
                "--rm",
                "--read-only",
                "--shm-size=64m",
                "--tmpfs",
                "/tmp:mode=1777",
                image,
            ]
            run("server-ruff", [*docker, "ruff", "check", "."])
            run(
                "server-format",
                [*docker, "ruff", "format", "--check", "."],
                required=False,
            )
            run("server-pytest", docker)
        mutated = [
            name for name, digest in manifest.items() if sha(workspace / name) != digest
        ]
        result["mutated_tracked_files"] = mutated
        result["original_reference_unchanged"] = (
            tree_hashes(original) == original_hashes
        )
        result["reference_absent_in_export"] = not copied_reference.exists()
        assert (
            not mutated
            and result["original_reference_unchanged"]
            and result["reference_absent_in_export"]
        )
        names = {step["name"] for step in result["steps"] if step["status"] == "passed"}
        expected = {
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
        result["complete"] = expected.issubset(names) and all(
            step["status"] == "passed" for step in result["steps"] if step["required"]
        )
        result["finished_at"] = datetime.now(timezone.utc).isoformat()
        save()
        return 0 if result["complete"] else 1
    except Exception as error:
        result["error"] = str(error)
        result["original_reference_unchanged"] = (
            tree_hashes(original) == original_hashes
        )
        save()
        raise


if __name__ == "__main__":
    sys.exit(main())

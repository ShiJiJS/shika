#!/usr/bin/env python3
"""Build signed old-UI rollback and forward APKs in isolated tracked exports.

Run through scripts/dev.sh. No APK is installed and no keystore is copied.
"""

import argparse
import hashlib
import io
import json
import os
import shutil
import subprocess
import tarfile
from pathlib import Path
from urllib.parse import unquote, urljoin, urlparse
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
LEGACY = "f5fe32c9e8136fa0b54a272609d8b7f2ac1d83ba"
CERT = "f5abd3bd11d94b3aaee66ab65e6a666a228a4d64edf4b86de9327ae9b8a59161"


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def patch_once(path, old, new):
    text = path.read_text()
    assert text.count(old) == 1, str(path)
    path.write_text(text.replace(old, new))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", default="HEAD")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    private = (ROOT / ".dev").resolve()
    if output == private or not output.is_relative_to(private) or output.exists():
        parser.error("Use a new output directory below this project's .dev")
    source = git("rev-parse", args.ref + "^{commit}").decode().strip()
    changed = git(
        "diff",
        "--name-only",
        source,
        "--",
        "apps/mobile",
        "scripts/dev.sh",
        "scripts/dev-env.sh",
        "scripts/build-app-rollback.py",
        "tools/rollback-client",
    )
    if changed.strip():
        parser.error("Commit app/build/rollback template changes before exporting")
    assert b"version: 0.2.0-preview.2+8" in git("show", source + ":apps/mobile/pubspec.yaml")
    output.mkdir(parents=True)
    exports = output / "exports"
    exports.mkdir()
    env = os.environ.copy()
    env["GIT_CEILING_DIRECTORIES"] = str(exports)
    sdk = Path(env["ANDROID_HOME"])
    build_tools = sdk / "build-tools/36.0.0"
    dev = ["bash", str(ROOT / "scripts/dev.sh")]
    result = {"source": source, "legacy_source": LEGACY, "steps": [], "complete": False}

    def save():
        (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")

    def run(name, command, cwd):
        log = output / (name + ".log")
        with log.open("wb") as stream:
            completed = subprocess.run(
                command, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT
            )
        record = {
            "name": name,
            "command": command,
            "cwd": str(cwd),
            "exit_code": completed.returncode,
            "log_sha256": sha(log),
        }
        result["steps"].append(record)
        save()
        print(json.dumps({"step": name, "exit_code": completed.returncode}), flush=True)
        if completed.returncode:
            raise RuntimeError(name + " failed; see " + str(log))
        return log.read_text(errors="replace")

    def export(name, ref):
        folder = exports / name
        folder.mkdir()
        raw = git("archive", "--format=tar", ref, "apps/mobile")
        with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
            for member in archive:
                relative = Path(member.name)
                assert not relative.is_absolute() and ".." not in relative.parts
                destination = folder / relative
                if member.isdir():
                    destination.mkdir(parents=True, exist_ok=True)
                else:
                    assert member.isfile(), member.name
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_bytes(archive.extractfile(member).read())
                    destination.chmod(member.mode & 0o777)
        hashes = {
            str(p.relative_to(folder)): sha(p) for p in sorted(folder.rglob("*")) if p.is_file()
        }
        (output / (name + "-source-files.json")).write_text(json.dumps(hashes, indent=2) + "\n")
        return folder / "apps/mobile", hashes

    artifacts = ROOT / "tmp/releases"
    artifacts.mkdir(parents=True, exist_ok=True)
    targets = {
        "rollback": artifacts / "video-viewer-0.1.4-rollback.1-arm64.apk",
        "forward": artifacts / "video-viewer-0.2.0-preview.2-arm64.apk",
    }
    assert all(not path.exists() for path in targets.values()), "Preview target already exists"
    save()
    run("flutter-version", [*dev, "flutter", "--version", "--machine"], ROOT)
    old, old_hashes = export("rollback", LEGACY)
    current, current_hashes = export("forward", source)
    assert (old / "pubspec.lock").read_bytes() == (current / "pubspec.lock").read_bytes()
    overlays = {}
    for name in [
        "lib/ui/preferences.dart",
        "lib/library/credentials.dart",
        "lib/library/scoped_journal.dart",
    ]:
        data = git("show", source + ":apps/mobile/" + name)
        (old / name).write_bytes(data)
        overlays[name] = {"from": source + ":apps/mobile/" + name, "sha256": sha(old / name)}
    for template, destination in [
        ("rollback_storage.dart.template", "lib/library/rollback_storage.dart"),
        ("rollback_storage_test.dart.template", "test/rollback_storage_test.dart"),
    ]:
        data = git("show", source + ":tools/rollback-client/" + template)
        (old / destination).write_bytes(data)
        overlays[destination] = {
            "from": source + ":tools/rollback-client/" + template,
            "sha256": sha(old / destination),
        }
    for name in ["preferences_test.dart", "scoped_journal_test.dart"]:
        destination = "test/rollback_compat_" + name
        (old / destination).write_bytes(git("show", source + ":apps/mobile/test/" + name))
        overlays[destination] = {
            "from": source + ":apps/mobile/test/" + name,
            "sha256": sha(old / destination),
        }
    patch_once(
        old / "lib/main.dart",
        "import 'library/credentials.dart';",
        "import 'library/credentials.dart';\nimport 'library/rollback_storage.dart';",
    )
    patch_once(
        old / "lib/main.dart",
        "  final LibraryRepository repository = demo",
        "  final credentials = SecureCredentialStore();\n  final LibraryRepository repository = demo",
    )
    patch_once(
        old / "lib/main.dart", "          SecureCredentialStore(),", "          credentials,"
    )
    patch_once(
        old / "lib/main.dart",
        "fileCommands: SecureFileCommandStore(),",
        "fileCommands: RollbackFileCommands(SecureFileCommandStore(), credentials),",
    )
    patch_once(
        old / "lib/main.dart",
        "backupWork: SecureBackupWorkStore(),",
        "backupWork: RollbackBackupWork(SecureBackupWorkStore(), credentials),",
    )
    patch_once(
        old / "lib/library/server_repository.dart",
        "        serverId: info['server_id'] as String,",
        "        serverId: info['server_id'] as String,\n        managementEpoch: info['management_epoch'] as String?,",
    )
    for name in ["lib/main.dart", "lib/library/server_repository.dart"]:
        overlays[name] = {
            "from": LEGACY + ":apps/mobile/" + name,
            "sha256": sha(old / name),
            "change": "storage adapter wiring / retain info epoch only",
        }
    result["rollback_overlays"] = overlays
    result["lockfile_sha256"] = sha(current / "pubspec.lock")
    save()

    built = {}
    for name, mobile, version, code in [
        ("rollback", old, "0.1.4-rollback.1", 7),
        ("forward", current, "0.2.0-preview.2", 8),
    ]:
        run(
            name + "-pub-get",
            [*dev, "flutter", "pub", "get", "--offline", "--enforce-lockfile"],
            mobile,
        )
        packages = json.loads((mobile / ".dart_tool/package_config.json").read_text())
        package = next(p for p in packages["packages"] if p["name"] == "video_viewer")
        package_uri = urljoin(
            (mobile / ".dart_tool/package_config.json").as_uri(), package["rootUri"]
        )
        assert Path(unquote(urlparse(package_uri).path)).resolve() == mobile
        run(name + "-analyze", [*dev, "flutter", "analyze", "--no-pub"], mobile)
        tests = (
            ["test"]
            if name == "rollback"
            else [
                "test/preferences_test.dart",
                "test/connection_widget_test.dart",
                "test/scoped_journal_test.dart",
                "test/preference_switch_test.dart",
            ]
        )
        run(name + "-tests", [*dev, "flutter", "test", "--no-pub", *tests], mobile)
        run(
            name + "-release",
            [
                *dev,
                "flutter",
                "build",
                "apk",
                "--release",
                "--target-platform",
                "android-arm64",
                "--dart-define=LIBRARY_MODE=server",
                "--build-name",
                version,
                "--build-number",
                str(code),
            ],
            mobile,
        )
        apk = mobile / "build/app/outputs/flutter-apk/app-release.apk"
        signature = run(
            name + "-signature",
            [str(build_tools / "apksigner"), "verify", "--print-certs", str(apk)],
            mobile,
        )
        assert "Signer #1 certificate SHA-256 digest: " + CERT in signature
        badging = run(
            name + "-badging", [str(build_tools / "aapt"), "dump", "badging", str(apk)], mobile
        )
        assert "name='io.github.shijijs.video_viewer'" in badging
        assert (
            "versionCode='" + str(code) + "'" in badging
            and "versionName='" + version + "'" in badging
        )
        assert "application-debuggable" not in badging
        with ZipFile(apk) as bundle:
            names = bundle.namelist()
            flutter_abis = sorted(
                {
                    p.split("/")[1]
                    for p in names
                    if p.startswith("lib/") and p.endswith("/libflutter.so")
                }
            )
            assert flutter_abis == ["arm64-v8a"]
            assert not any("design/reference/" in p or "library-first/app.html" in p for p in names)
            assert not any(
                b"dev/flutter/plugins/integration_test" in bundle.read(p)
                for p in names
                if p.startswith("classes") and p.endswith(".dex")
            )
        result[name] = {
            "path": str(targets[name]),
            "version": version,
            "version_code": code,
            "sha256": sha(apk),
            "bytes": apk.stat().st_size,
            "certificate_sha256": CERT,
            "flutter_engine_abis": flutter_abis,
            "normal_entrypoint": True,
            "integration_test_plugin": False,
        }
        built[name] = apk
        for relative, expected in (old_hashes if name == "rollback" else current_hashes).items():
            app_relative = str(Path(relative).relative_to("apps/mobile"))
            if name == "rollback" and app_relative in overlays:
                continue
            assert sha(mobile / app_relative) == expected, relative
        assert sha(mobile / "pubspec.lock") == result["lockfile_sha256"]
        save()
    for name, apk in built.items():
        with apk.open("rb") as source_file, targets[name].open("xb") as target:
            shutil.copyfileobj(source_file, target)
        assert sha(targets[name]) == result[name]["sha256"]
    result["complete"] = True
    save()
    print(
        json.dumps({"complete": True, "rollback_code": 7, "forward_code": 8, "output": str(output)})
    )


if __name__ == "__main__":
    main()

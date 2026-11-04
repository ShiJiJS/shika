#!/usr/bin/env python3
"""Supplement existing native evidence with actual large/short footer views.

Uses only the dedicated emulator and public 8761 fixture. Preparation resets and seeds
its public image folders; the UI part is read-only and cancels its confirmation.
The full 39-point run remains a separate, immutable evidence set.
"""

import argparse
import hashlib
import importlib.util
import json
import subprocess
import threading
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=["large", "landscape"], required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location(
        "connection_runner", ROOT / "scripts/run-client-connection-test.py"
    )
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    runner.EVIDENCE = args.output.resolve()
    runner.EVIDENCE.mkdir(parents=True, exist_ok=False)
    runner.PREFIX = "lf7-roots-missing"

    def device(*command):
        return subprocess.check_output(
            [runner.ADB, "-s", "emulator-5554", "shell", *command],
            text=True,
            timeout=10,
        ).strip()

    def viewport():
        return {
            "size": device("wm", "size"),
            "density": device("wm", "density"),
            "font_scale": device("settings", "get", "system", "font_scale"),
        }

    runner.prepare_emulator()
    original = viewport()
    width, height, scale = (
        (360, 740, "2.0") if args.profile == "large" else (844, 390, "1.0")
    )
    source_paths = subprocess.check_output(
        ["git", "ls-files", "apps/mobile/lib", "services/server/shika"],
        cwd=ROOT,
        text=True,
    ).splitlines() + [
        "apps/mobile/integration_test/server_missing_footer_test.dart",
        "scripts/capture-missing-footer.py",
        "scripts/run-client-connection-test.py",
        "services/server/tests/e2e_server.py",
    ]
    source = {
        "production_commit": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
        ).strip(),
        "profile": args.profile,
        "window": [width, height],
        "files": {
            name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
            for name in source_paths
        },
    }
    (runner.EVIDENCE / "source.json").write_text(json.dumps(source, indent=2) + "\n")
    watcher = None
    try:
        with (runner.EVIDENCE / "preparation.log").open("w") as setup_log:
            subprocess.run(
                ["bash", str(ROOT / "scripts/prepare-client-e2e.sh"), "--reset"],
                cwd=ROOT,
                stdout=setup_log,
                stderr=subprocess.STDOUT,
                check=True,
                timeout=180,
            )
        device("wm", "size", f"{width * 3}x{height * 3}")
        device("wm", "density", "480")
        device("settings", "put", "system", "font_scale", scale)
        request = urllib.request.Request(
            "http://127.0.0.1:8761/__fixture/checkpoint/ready",
            headers=runner.HEADERS,
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=10) as response:
            response.read()
        watcher = threading.Thread(target=runner.watch, daemon=True)
        watcher.start()
        with (runner.EVIDENCE / "android-test.log").open("w") as log:
            result = subprocess.run(
                [
                    "bash",
                    str(ROOT / "scripts/dev.sh"),
                    "flutter",
                    "test",
                    "integration_test/server_missing_footer_test.dart",
                    "-d",
                    "emulator-5554",
                    "--no-uninstall",
                    "--reporter",
                    "expanded",
                ],
                cwd=ROOT / "apps/mobile",
                stdout=log,
                stderr=subprocess.STDOUT,
                timeout=300,
                check=False,
            )
        assert result.returncode == 0, "See android-test.log"
    finally:
        runner.stop.set()
        if watcher is not None:
            watcher.join(timeout=30)
        for name in ["size", "density"]:
            override = next(
                (
                    line.split(":", 1)[1].strip()
                    for line in original[name].splitlines()
                    if line.startswith("Override")
                ),
                "reset",
            )
            device("wm", name, override)
        if original["font_scale"] == "null":
            device("settings", "delete", "system", "font_scale")
        else:
            device("settings", "put", "system", "font_scale", original["font_scale"])
        (runner.EVIDENCE / "restored-viewport.json").write_text(
            json.dumps({"before": original, "after": viewport()}, indent=2) + "\n"
        )
        (runner.EVIDENCE / "host-events.json").write_text(
            json.dumps({"events": runner.events, "errors": runner.errors}, indent=2)
            + "\n"
        )
    assert not runner.errors, runner.errors
    text = (runner.EVIDENCE / "android-test.log").read_text()
    assert "All tests passed!" in text and "MISSING_FOOTER_VERIFIED:" in text
    metrics = [
        json.loads(line.split("FOOTER_METRICS:", 1)[1])
        for line in text.splitlines()
        if "FOOTER_METRICS:" in line
    ]
    assert len(metrics) == 2
    for item in metrics:
        assert item["window"] == [width, height] and item["remaining_scroll"] <= 1
        for suffix in [
            ".png",
            "-window.txt",
            "-files.json",
            "-requests.json",
            "-stats.json",
        ]:
            assert (
                runner.EVIDENCE / f"lf7-roots-missing-{item['state']}{suffix}"
            ).is_file()
    (runner.EVIDENCE / "metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")
    print(
        json.dumps(
            {
                "profile": args.profile,
                "checks": 2,
                "source": source["production_commit"],
            }
        )
    )


if __name__ == "__main__":
    main()

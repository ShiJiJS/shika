#!/usr/bin/env python3
"""Create a fresh disposable database while preserving its exact media files.

The host runner must first stop only video-viewer-client-e2e-server-1.
The old management directory is retained as a recoverable test snapshot.
"""

import json
import os
import subprocess
import time
from pathlib import Path


def main():
    if os.name != "posix":
        raise SystemExit("Run this fixture helper inside WSL")
    running = subprocess.check_output(
        ["docker", "inspect", "--format", "{{.State.Running}}", "video-viewer-client-e2e-server-1"],
        text=True,
    ).strip()
    if running != "false":
        raise SystemExit("Stop only the isolated e2e container before replacing its management directory")
    base = Path.home() / ".local/share/video-viewer-e2e"
    if base.resolve() != base or base.is_symlink():
        raise SystemExit("Unexpected fixture base")
    data, media = base / "data", base / "media"
    for target in [data, media]:
        if target.resolve() != target or target.is_symlink() or not target.is_dir():
            raise SystemExit("Unexpected disposable fixture directory")
    mounts = json.loads((base / "config/mounts.json").read_text())
    if {(item["id"], item["path"]) for item in mounts} != {
        ("shorts", "/media/shorts"), ("camera", "/media/camera")
    } or (base / "config/passphrase").read_text().strip() != "video-viewer-emulator-fixture-only":
        raise SystemExit("Not the isolated emulator fixture")
    if not (data / "e2e-seeded").is_file():
        raise SystemExit("Missing disposable fixture marker")
    snapshots = base / "snapshots"
    if snapshots.is_symlink() or snapshots.resolve() != snapshots:
        raise SystemExit("Unexpected snapshot target")
    snapshots.mkdir(mode=0o700, exist_ok=True)
    saved = snapshots / f"before-fresh-instance-{time.time_ns()}"
    if saved.exists() or saved.parent.resolve() != snapshots:
        raise SystemExit("Unexpected snapshot destination")
    data.rename(saved)
    data.mkdir(mode=0o700)
    (data / "e2e-seeded").write_text("Preserve existing disposable media; do not seed it again")
    print(json.dumps({"fresh_instance_prepared": True, "preserved_snapshot": str(saved)}))


if __name__ == "__main__":
    main()

#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export VV_E2E_HOME="${VV_E2E_HOME:-$HOME/.local/share/video-viewer-e2e}"
export VV_E2E_ASSETS="$repo_dir/apps/mobile/assets/media"
compose=(docker compose -f "$repo_dir/deploy/tests/compose.yaml")
if [[ "${1:-}" == "--reset" ]]; then
  "${compose[@]}" down
  python3 - "$VV_E2E_HOME" "$repo_dir" <<'PY'
import os
import shutil
import sys
from pathlib import Path
base = Path(sys.argv[1])
allowed = {Path.home() / ".local/share/video-viewer-e2e", Path(sys.argv[2]) / ".dev/e2e"}
if base not in allowed or base.resolve() != base:
    raise SystemExit("Refusing reset outside the dedicated non-symlink fixture directory")
expected = base
for name in ("data", "media"):
    target = base / name
    if target.exists():
        if target.is_symlink() or target.resolve().parent != expected:
            raise SystemExit("Unsafe fixture reset target")
        for directory, _, _ in os.walk(target, followlinks=False):
            os.chmod(directory, 0o700)
        shutil.rmtree(target)
PY
fi
mkdir -p "$VV_E2E_HOME"/{data,media,config}
printf '%s' 'video-viewer-emulator-fixture-only' > "$VV_E2E_HOME/config/passphrase"
chmod 600 "$VV_E2E_HOME/config/passphrase"
cat > "$VV_E2E_HOME/config/mounts.json" <<'JSON'
[
  {"id":"shorts","name":"端到端短视频","path":"/media/shorts"},
  {"id":"camera","name":"端到端相机","path":"/media/camera"}
]
JSON
"${compose[@]}" up -d --build
python3 - <<'PY'
import json
import time
import urllib.request
base = "http://127.0.0.1:8761"
deadline = time.monotonic() + 60
token = None
while time.monotonic() < deadline:
    try:
        if token is None:
            request = urllib.request.Request(base + "/api/v1/auth/login", data=json.dumps({"passphrase":"video-viewer-emulator-fixture-only"}).encode(), headers={"Content-Type":"application/json"})
            with urllib.request.urlopen(request, timeout=3) as response:
                token = json.load(response)["access_token"]
        request = urllib.request.Request(base + "/api/v1/videos", headers={"Authorization":"Bearer " + token})
        with urllib.request.urlopen(request, timeout=3) as response:
            if json.load(response)["total"] >= 27:
                ready = urllib.request.Request(base + "/api/v1/library-state", headers={"Authorization":"Bearer " + token})
                with urllib.request.urlopen(ready, timeout=3) as state:
                    if not json.load(state)["ready"]:
                        time.sleep(0.2)
                        continue
                print("Isolated emulator fixture ready at port 8761; main service unchanged")
                break
    except OSError:
        pass
    time.sleep(0.2)
else:
    raise SystemExit("Fixture startup or scan did not complete")
PY

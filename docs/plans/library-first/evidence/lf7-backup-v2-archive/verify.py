"""Check archived results and source against the exact tested Git revision."""

import hashlib
import json
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[5]
folder = Path(__file__).resolve().parent
proof = json.loads((folder / "proof.json").read_text())
manifest = json.loads((folder / "source-sha256.json").read_text())
assert proof["source_commit"] == manifest["source_commit"]
for path, expected in manifest["files"].items():
    data = subprocess.check_output(["git", "show", f"{manifest['source_commit']}:{path}"], cwd=root)
    assert hashlib.sha256(data).hexdigest() == expected, path
archive = (folder / "archive-tests.log").read_text()
assert "29 passed, 1 warning in 29.02s" in archive
assert "19 passed, 1 warning" in (folder / "legacy-regression.log").read_text()
assert "All checks passed!" in (folder / "ruff.log").read_text()
metrics = json.loads(re.search(r"VV_ARCHIVE_MEMORY (\{[^\n]+\})", archive)[1])
assert metrics == proof["large_archive"]
assert metrics["bytes"] > 32 * 1024 * 1024
assert metrics["python_peak_bytes"] < 16 * 1024 * 1024
assert metrics["task_rows"] == 18000 and metrics["note_length"] == 2048
assert re.fullmatch(r"[a-f0-9]{64}", metrics["file_sha256"])
assert proof["managed_tables"] == 33
assert not any(proof[k] for k in ("public_v2_enabled", "full_restore_verified", "app_streaming_verified"))
for path, expected in json.loads((folder / "evidence-sha256.json").read_text()).items():
    assert hashlib.sha256((folder / path).read_bytes()).hexdigest() == expected, path
print("PASS: pinned source, 29 archive + 19 legacy results, disk metrics and evidence hashes; v2 remains private")

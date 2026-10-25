"""Verify fixed history-bundle results; not a full-v2 restore assertion."""

import hashlib
import json
import re
import subprocess
from pathlib import Path

folder = Path(__file__).resolve().parent
root = Path(__file__).resolve().parents[5]
proof = json.loads((folder / "proof.json").read_text())
source = json.loads((folder / "source-sha256.json").read_text())
assert source["source_commit"] == proof["source_commit"]
for path, expected in source["files"].items():
    data = subprocess.check_output(["git", "show", f"{source['source_commit']}:{path}"], cwd=root)
    assert hashlib.sha256(data).hexdigest() == expected, path
log = (folder / "combined-tests.log").read_text()
assert "66 passed, 1 warning in 76.83s" in log
assert sum(proof["modules"].values()) == proof["combined_tests"] == 66
assert "All checks passed!" in (folder / "ruff.log").read_text()
for name, marker in (("history", "VV_HISTORY_MEMORY"), ("archive", "VV_ARCHIVE_MEMORY")):
    value = json.loads(re.search(marker + r" (\{[^\n]+\})", log)[1])
    assert value == proof["metrics"][name]
    assert value.get("archive_bytes", value.get("bytes")) > 32 * 1024 * 1024
    assert value["python_peak_bytes"] < 16 * 1024 * 1024
assert proof["metrics"]["history"]["indexed_tasks"] == 18000
assert proof["metrics"]["history"]["page_count"] == 24
kills = [json.loads(value) for value in re.findall(r"VV_HISTORY_KILL (\{[^\n]+\})", log)]
assert kills == proof["history_process_kills"]
assert len(kills) == 2
assert kills[0] == dict(phase="before_publish", returncode=-9, published=False, source_unchanged=True)
assert kills[1] == dict(phase="after_publish", returncode=-9, published=True, source_unchanged=True)
assert not any(proof[k] for k in ("public_v2_enabled", "full_v2_restore_verified", "app_transfer_verified"))
for path, expected in json.loads((folder / "evidence-sha256.json").read_text()).items():
    assert hashlib.sha256((folder / path).read_bytes()).hexdigest() == expected, path
print("PASS: pinned source, 66 checks, two history publication SIGKILLs and bounded Python metrics; full v2 remains open")

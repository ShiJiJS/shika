"""Check exact-source authority tests and actual v1 restore commit boundaries."""

import hashlib
import json
import re
import subprocess
from pathlib import Path

folder = Path(__file__).resolve().parent
root = Path(__file__).resolve().parents[5]
proof = json.loads((folder / "proof.json").read_text())
source = json.loads((folder / "source-sha256.json").read_text())
assert proof["source_commit"] == source["source_commit"]
for path, expected in source["files"].items():
    value = subprocess.check_output(["git", "show", f"{source['source_commit']}:{path}"], cwd=root)
    assert hashlib.sha256(value).hexdigest() == expected, path
log = (folder / "server-full.log").read_text()
assert "375 passed, 1 warning in 626.43s" in log
assert proof["server_tests"] == 375 and proof["authority_tests"] == 17
assert proof["server_exit_code"] == 0
assert "17 tests collected" in (folder / "collection.log").read_text()
assert "All checks passed!" in (folder / "ruff.log").read_text()
races = [json.loads(value) for value in re.findall(r"VV_AUTHORITY_RACE (\{[^\n]+\})", log)]
assert races == proof["authority_races"] == [
    dict(explicit=False, old_request_rejected=True, new_root_rows=0),
    dict(explicit=True, old_request_rejected=True, new_root_rows=0),
]
restore = json.loads(re.search(r"VV_AUTHORITY_RESTORE (\{[^\n]+\})", log)[1])
assert restore == proof["actual_v1_restore"] == dict(changed=True, original_get=True, restore_tasks=1, media_unchanged=True)
kills = []
for value in re.findall(r"\{[^\n]+\}", log):
    try:
        record = json.loads(value)
    except ValueError:
        continue
    if record.get("fault") == "SIGKILL" and "authority_changed_after_commit" in record:
        kills.append(record)
assert kills == proof["v1_restore_process_kills"] and len(kills) == 2
assert {row["phase"] for row in kills} == {"snapshot_written", "after_replace_before_commit"}
for row in kills:
    assert row["historical_operations_replayed"] == 0
    assert all(row[key] is True for key in (
        "restore_recovered", "old_data_visible_before_commit", "media_hash_preserved",
        "authority_unchanged_before_commit", "authority_changed_after_commit",
        "stale_post_rejected", "original_receipt_readable",
    ))
assert proof["database_schema"] == "0014" and proof["logical_v2_graph_schema"] == "0013"
assert not any(proof[key] for key in ("public_backup_v2_enabled", "app_authority_integrated", "full_v2_restore_verified"))
for path, expected in json.loads((folder / "evidence-sha256.json").read_text()).items():
    assert hashlib.sha256((folder / path).read_bytes()).hexdigest() == expected, path
print("PASS: 375 exact-source server checks, 17 authority cases and two v1 restore SIGKILL boundaries; App/v2 remain open")

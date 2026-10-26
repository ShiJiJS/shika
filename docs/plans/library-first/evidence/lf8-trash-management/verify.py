"""Read-only checks of fixed-source native trash evidence; run at repository root."""

import hashlib
import json
import struct
import subprocess
from pathlib import Path

root = Path.cwd()
evidence = Path(__file__).resolve().parent


def read(path):
    return json.loads(path.read_text())


def sha(data):
    return hashlib.sha256(data).hexdigest()


states = [
    "reader", "video", "read-error", "packs", "empty", "keyboard", "paged",
    "selected", "dark", "confirm", "unknown", "receipt", "restored",
    "single-confirm", "single-restored",
]
source = read(evidence / "source.json")
proof = []
for profile, size, text13 in [
    ("normal", [390, 844], 13),
    ("large", [360, 740], 26),
    ("landscape", [844, 390], 13),
]:
    folder = evidence / profile
    assert read(folder / "source.json") == source
    events = read(folder / "lf8-trash-host-events.json")
    assert not events["errors"]
    assert [e["phase"] for e in events["events"] if e["phase"].startswith("trash-")] == [f"trash-{s}" for s in states]
    log = (folder / "lf8-trash-android-test.log").read_text()
    assert "All tests passed!" in log and "Some tests failed" not in log
    metrics = [json.loads(line.split("TRASH_METRICS:", 1)[1])
               for line in log.splitlines() if "TRASH_METRICS:" in line]
    assert len(metrics) == 15
    assert [m["state"] for m in metrics] == [f"trash-{s}" for s in states]
    assert all(m["window"] == size and m["dpr"] == 3 and m["text13"] == text13
               for m in metrics)
    assert all(m["dark"] == (m["state"] == "trash-dark") for m in metrics)
    assert metrics[5]["keyboard"] > 0
    traces, plans = {}, {}
    initial = None
    for state in states:
        base = folder / f"lf8-trash-trash-{state}"
        pixels = base.with_suffix(".png").read_bytes()
        assert pixels[:8] == b"\x89PNG\r\n\x1a\n"
        assert struct.unpack(">II", pixels[16:24]) == tuple(v * 3 for v in size)
        focus = Path(str(base) + "-window.txt").read_text()
        assert "Application Not Responding" not in focus
        assert any("mCurrentFocus=" in line and "io.github.shijijs.video_viewer" in line
                   for line in focus.splitlines())
        hashes = read(Path(str(base) + "-files.json"))["hashes"]
        if initial is None:
            initial = hashes
            assert len(initial) == 81
        assert hashes == initial
        traces[state] = read(Path(str(base) + "-requests.json"))["items"]
        plans[state] = read(Path(str(base) + "-plan.json"))
    for state in states[1:10]:
        assert all(e["method"] == "GET" for e in traces[state])
        assert plans[state]["plan"] is None
    trace = traces["single-restored"]
    assert all(e["authenticated"] for e in trace)
    writes = [e for e in trace if e["method"] != "GET"]
    assert [(e["path"], e["status"]) for e in writes] == [
        ("/api/v1/pack-restore-plans", 503),
        ("/api/v1/pack-restore-plans", 202),
    ]
    a, b = (set(e["restore_members"]) for e in writes)
    assert len(a) == 26 and len(b) == 1 and not a.intersection(b)
    receipts = [e for e in trace if e["path"].startswith("/api/v1/pack-restore-requests/")]
    assert len(receipts) == 1 and receipts[0]["method"] == "GET" and receipts[0]["status"] == 200
    assert sha(receipts[0]["path"].split("/")[-1].encode()) == writes[0]["command_hash"]
    assert not any("/pack-restore-requests/" in e["path"] for e in traces["unknown"])
    for state in ["unknown", "receipt", "restored", "single-confirm", "single-restored"]:
        stats = plans[state]
        plan = stats["plan"]
        count = 1 if state == "single-restored" else 26
        assert plan["status"] == plan["phase"] == "completed"
        assert plan["result"] == {
            "operation_id": plan["id"], "total": count, "processed": count,
            "succeeded": count, "failed": 0, "stopped": 0,
            "remaining": 0, "partial": False, "batches": 1,
        }
        assert stats["member_counts"] == {"succeeded": count} and len(stats["batches"]) == 1
        assert len(stats["packs"]) == 27
        assert sum(p["status"] == "available" for p in stats["packs"]) == (27 if count == 1 else 26)
        assert sum(p["status"] == "trash" for p in stats["packs"]) == (0 if count == 1 else 1)
        assert sha(plan["request_id"].encode()) == writes[1 if count == 1 else 0]["command_hash"]
    marker = next(json.loads(line.split("TRASH_MANAGEMENT_VERIFIED:", 1)[1])
                  for line in log.splitlines() if "TRASH_MANAGEMENT_VERIFIED:" in line)
    assert marker == {"packs": 27, "restored_bulk": 26, "restored_single": 1,
                      "images": 81, "original_posts": 2, "receipt_gets": 1,
                      "cancel_zero_writes": True, "reading_and_tags_preserved": True,
                      "video_unchanged": True}
    restored = read(folder / "restored-viewport.json")
    assert restored["before"] == restored["after"] == {
        "size": "Physical size: 1080x2400", "density": "Physical density: 420", "font_scale": "1.0",
    }
    proof.append({"profile": profile, "checkpoints": 15, **marker})

for metadata in [source, read(evidence / "checks/source.json")]:
    for path, digest in metadata["files"].items():
        assert sha((root / path).read_bytes()) == digest
        assert sha(subprocess.check_output(["git", "show", f"{metadata['commit']}:{path}"])) == digest
assert source["prototype_tree"] == "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
assert subprocess.check_output(["git", "rev-parse", "HEAD:design/reference/library-first"], text=True).strip() == source["prototype_tree"]
for item in read(evidence / "reference/source-sha256.json")["files"]:
    assert sha((root / "design/reference/library-first" / item["path"]).read_bytes()) == item["sha256"]
for index in [1, 2, 3]:
    assert "+47: All tests passed!" in (evidence / f"checks/targeted-{index}.log").read_text()
assert "No issues found!" in (evidence / "checks/analyze.log").read_text()
assert "All checks passed!" in (evidence / "checks/ruff.log").read_text()

# Separate same-production run: the unknown footer was below the landscape frame.
footer = evidence / "supplement/landscape"
pinned = read(footer / "source.json")
assert pinned["production_commit"] == source["commit"]
for path, digest in pinned["files"].items():
    assert sha((root / path).read_bytes()) == digest
    if path in source["files"]:
        assert digest == source["files"][path]
    elif path.endswith("capture-trash-footer.py"):
        assert sha((footer / "capture-source.py.txt").read_bytes()) == digest
    elif path.endswith("trash-footer-tail.dart.txt"):
        assert sha((footer / "tail-source.dart.txt").read_bytes()) == digest
    else:
        raise AssertionError(f"Unpinned supplemental source: {path}")
generated = (footer / "generated-test.dart.txt").read_bytes()
assert sha(generated) == pinned["generated_sha256"]
main_test = (root / "apps/mobile/integration_test/server_trash_management_test.dart").read_text()
assert generated.decode() == main_test.split("      await shot('unknown');", 1)[0] + (footer / "tail-source.dart.txt").read_text()
log = (footer / "android-test.log").read_text()
assert "All tests passed!" in log and "TRASH_FOOTER_VERIFIED:" in log
assert not read(footer / "host-events.json")["errors"]
metric = read(footer / "metrics.json")[-1]
assert metric["state"] == "trash-unknown" and metric["window"] == [844, 390]
assert metric["dpr"] == 3 and metric["text13"] == 13 and metric["keyboard"] == 0
base = footer / "lf8-trash-trash-unknown"
assert struct.unpack(">II", base.with_suffix(".png").read_bytes()[16:24]) == (2532, 1170)
focus = Path(str(base) + "-window.txt").read_text()
assert any("mCurrentFocus=" in line and "io.github.shijijs.video_viewer" in line for line in focus.splitlines())
hashes = read(Path(str(base) + "-files.json"))["hashes"]
assert len(hashes) == 81
assert hashes == read(footer / "lf8-trash-trash-reader-files.json")["hashes"]
trace = read(Path(str(base) + "-requests.json"))["items"]
writes = [e for e in trace if e["method"] != "GET"]
assert len(writes) == 1 and writes[0]["path"] == "/api/v1/pack-restore-plans"
assert writes[0]["status"] == 503 and len(set(writes[0]["restore_members"])) == 26
assert not any("/pack-restore-requests/" in e["path"] for e in trace)
stats = read(Path(str(base) + "-plan.json"))
assert stats["member_counts"] == {"succeeded": 26}
assert stats["plan"]["status"] == "completed" and stats["plan"]["result"]["succeeded"] == 26
assert sha(stats["plan"]["request_id"].encode()) == writes[0]["command_hash"]
restored = read(footer / "restored-viewport.json")
assert restored["before"] == restored["after"] == read(evidence / "normal/restored-viewport.json")["before"]

baseline = read(evidence / "baseline/source.json")
assert baseline["commit"].startswith("b520486")
for path, digest in baseline["files"].items():
    assert sha(subprocess.check_output(["git", "show", f"{baseline['commit']}:{path}"])) == digest
baseline_log = (evidence / "baseline/lf8-trash-android-test.log").read_text()
assert "TRASH_BASELINE_VERIFIED" in baseline_log and "Some tests failed" in baseline_log
assert len(list((evidence / "baseline").glob("*.png"))) == 9
manifest = read(evidence / "manifest.json")
actual = {str(p.relative_to(evidence)) for p in evidence.rglob("*")
          if p.is_file() and p.name not in {"manifest.json", "verification.json"}}
assert set(manifest) == actual
assert all(sha((evidence / p).read_bytes()) == digest for p, digest in manifest.items())
print(json.dumps({"verified": True, "source": source["commit"], "inputs": len(manifest), "native_checkpoints": 45, "supplemental_footer": 1, "baseline_partial_only": True, "profiles": proof}, ensure_ascii=False, indent=2))

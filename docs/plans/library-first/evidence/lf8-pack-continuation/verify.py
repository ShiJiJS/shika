"""Point-in-time, read-only evidence verification; requires Pillow."""

import hashlib
import json
import subprocess
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SOURCE = "c4aaf3b"
PROTO = "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
SCENES = [
    "continue-empty", "continue-read", "continue-library", "continue-reader",
    "continue-return", "continue-scope", "continue-multi", "continue-error",
    "continue-retry", "continue-recent",
]


def read(path):
    return json.loads(path.read_text())


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


manifest = read(HERE / "manifest.json")
for name, expected in manifest.items():
    assert digest(HERE / name) == expected, name
    git("ls-files", "--error-unmatch", str((HERE / name).relative_to(ROOT)))
assert git("rev-parse", "HEAD:design/reference/library-first") == PROTO
for tree in ["apps/mobile/lib", "services/server/video_viewer"]:
    assert git("rev-parse", f"HEAD:{tree}") == git("rev-parse", f"{SOURCE}:{tree}")
assert git("rev-parse", "HEAD:services/server/video_viewer") == git(
    "rev-parse", "4785a69:services/server/video_viewer"
)
sources, windows, first_media = [], [], None
for name in ["normal-1", "normal-2", "normal-3", "large", "landscape"]:
    run = HERE / name
    result, source, metrics = (read(run / f) for f in ["result.json", "source.json", "metrics.json"])
    assert result["passed"] and result["scenario"] == "continuation"
    assert result["screens"] == SCENES and len(metrics) == len(SCENES)
    assert source["commit"] == git("rev-parse", SOURCE)
    assert source["prototype_tree"] == PROTO
    for path, sha in source["files"].items():
        assert digest(ROOT / path) == sha, path
        assert hashlib.sha256(subprocess.check_output(["git", "show", f"{SOURCE}:{path}"], cwd=ROOT)).hexdigest() == sha
    sources.append(source["files"])
    media = read(run / "media-before.json")
    assert media == read(run / "media-after.json") and len(media) == 26
    if first_media is None:
        first_media = media
    assert media == first_media
    restored = read(run / "restored-viewport.json")
    assert restored["before"] == restored["after"]
    assert restored["font_before"] == restored["font_after"] and not restored["errors"]
    assert read(run / "prepared.json") == {"videos": 2, "packs": 4, "pages": 24}
    log = (run / "flutter.log").read_text()
    assert "All tests passed!" in log and "CONTINUATION_LAYOUT_ERROR" not in log
    proof = json.loads(next(l.split("PACK_CONTINUATION_VERIFIED:", 1)[1] for l in log.splitlines() if l.startswith("PACK_CONTINUATION_VERIFIED:")))
    assert proof["source"] == "library" and proof["candidate_count"] == 4
    assert proof["seed_progress"]["page_index"] == 2
    # The second snapshot is AFTER the explicit second reader-open, which
    # legitimately increments its revision. Each readonly interval is also
    # asserted inside the fixed native test; do not equate across real opens.
    assert proof["after_summary"] == proof["final_progress"]
    assert proof["after_summary"]["revision"] == proof["before_summary"]["revision"] + 1
    for key in ["page_id", "page_index", "offset_ratio", "completed"]:
        assert proof["before_summary"][key] == proof["after_summary"][key]
    assert proof["final_progress"]["page_index"] == 3
    requests = read(run / "requests.json")
    sessions = [r for r in requests if r["path"] == "/api/v1/pack-sessions" and r["method"] == "POST"]
    assert len(sessions) == 2
    for session in sessions:
        assert session["status"] == 201 and session["body"]["source"] == "library"
        assert session["body"]["anchor_pack_id"] == proof["pack"]
        assert session["body"]["scope"] == {"directory_id": None, "search": "", "tag_ids": [], "read_state": "all"}
    assert len([r for r in requests if r["path"].endswith("/opened") and r["method"] == "POST" and r["status"] == 200]) == 2
    # Native trace intentionally stores paths only. The controlled 503 applies
    # only to source=recent/limit=1; exact query arguments have HTTP unit tests.
    summary_reads = [r for r in requests if r["method"] == "GET" and r["path"] == "/api/v1/packs"]
    assert any(r["status"] == 503 for r in summary_reads)
    assert any(r["status"] == 200 and r["phase"] == "continue-error" for r in summary_reads)
    db = read(run / "database.json")
    assert db["counts"] == {"videos": 2, "packs": 4, "pack_pages": 24, "recent_entries": 1, "pack_progress": 1, "pack_sessions": 2}
    assert all(s["candidate_count"] == 4 and json.loads(s["source"])["kind"] == "library" for s in db["sessions"])
    assert db["progress"][0]["ordinal"] == 3 and not db["progress"][0]["completed"]
    assert db["progress"][0]["pack_id"] == db["recent"][0]["pack_id"] == proof["pack"]
    for m in metrics:
        image = Image.open(run / (m["state"] + ".png"))
        assert image.size == tuple(round(v * m["dpr"]) for v in m["size"])
        focus = (run / (m["state"] + "-window.txt")).read_text()
        assert any("mCurrentFocus=" in l and "io.github.shijijs.video_viewer" in l for l in focus.splitlines())
    by_state = {m["state"]: m for m in metrics}
    for state in ["continue-library", "continue-return", "continue-retry"]:
        assert "pack-continuation" in by_state[state]["keys"]
        assert any(t["text"] == "第 4 / 6 张" for t in by_state[state]["texts"])
    for state in ["continue-empty", "continue-scope", "continue-multi", "continue-recent"]:
        assert "pack-continuation" not in by_state[state]["keys"]
    if name.startswith("normal"):
        assert by_state["continue-library"]["keys"]["pack-continuation"] == [16, 196, 358, 86]
    windows.append({"run": name, "size": metrics[0]["size"], "padding": metrics[0]["viewPadding"], "scale": metrics[0]["textScale"]})
assert all(s == sources[0] for s in sources)
assert first_media == json.loads(git(
    "show",
    "4785a69:docs/plans/library-first/evidence/lf8-shared-geometry/normal-1/media-before.json",
))
assert "+471: All tests passed!" in (HERE / "checks/client.log").read_text()
assert "16 passed" in (HERE / "checks/server.log").read_text()
assert "No issues found!" in (HERE / "checks/analyze.log").read_text()
assert "All checks passed!" in (HERE / "checks/ruff.log").read_text()
assert read(HERE / "reference/metrics.json")["viewport"] == [390, 844, 1]
print(json.dumps({"verified": True, "source": git("rev-parse", SOURCE), "inputs": len(manifest), "native_screens": 50, "client_tests": 471, "server_tests": 16, "windows": windows, "scope": "pack continuation only; full LF8 remains open"}, ensure_ascii=False, indent=2))

"""Read-only point-in-time verification of counts evidence; requires Pillow."""

import hashlib
import json
import subprocess
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SOURCE = "910cfb271c9c83e0458b798c788651773d6d9a8e"
PROTO = "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
SCENES = ["counts-home", "counts-packs", "counts-filter", "counts-tags",
          "counts-recent", "counts-trash", "counts-restore", "counts-error", "counts-retry"]


def read(p):
    return json.loads(p.read_text())


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


manifest = read(HERE / "manifest.json")
for path, expected in manifest.items():
    assert sha(HERE / path) == expected, path
    git("ls-files", "--error-unmatch", str((HERE / path).relative_to(ROOT)))
assert git("rev-parse", "HEAD:design/reference/library-first") == PROTO
for tree in ["apps/mobile/lib", "services/server/video_viewer"]:
    assert git("rev-parse", f"HEAD:{tree}") == git("rev-parse", f"{SOURCE}:{tree}")
assert git("rev-parse", f"{SOURCE}:services/server/video_viewer") == git("rev-parse", "b74e95a:services/server/video_viewer")
for path, expected in read(HERE / "checks/source.json")["files"].items():
    assert sha(ROOT / path) == expected
    assert hashlib.sha256(subprocess.check_output(["git", "show", f"{SOURCE}:{path}"], cwd=ROOT)).hexdigest() == expected
first_media, sources = None, []
for name in ["normal-1", "normal-2", "normal-3", "large", "landscape", "continuation"]:
    run = HERE / name
    result, source, metrics = (read(run / p) for p in ["result.json", "source.json", "metrics.json"])
    assert result["passed"] and source["commit"] == SOURCE
    assert source["prototype_tree"] == PROTO
    for path, expected in source["files"].items():
        assert sha(ROOT / path) == expected, path
        assert hashlib.sha256(subprocess.check_output(["git", "show", f"{SOURCE}:{path}"], cwd=ROOT)).hexdigest() == expected
    sources.append(source["files"])
    media = read(run / "media-before.json")
    assert media == read(run / "media-after.json") and len(media) == 26
    if first_media is None:
        first_media = media
    assert media == first_media
    restored = read(run / "restored-viewport.json")
    assert restored["before"] == restored["after"] and not restored["errors"]
    assert restored["font_before"] == restored["font_after"]
    assert read(run / "prepared.json") == {"videos": 2, "packs": 4, "pages": 24}
    log = (run / "flutter.log").read_text()
    assert "All tests passed!" in log
    assert "CATALOG_COUNTS_ERROR:" not in log and "CONTINUATION_LAYOUT_ERROR:" not in log
    assert len(metrics) == (10 if name == "continuation" else 9)
    assert result["screens"] == [m["state"] for m in metrics]
    expected_size = [360, 809] if name == "large" else [844, 442] if name == "landscape" else [390, 905]
    assert all(m["size"] == expected_size and m["textScale"] == (2 if name == "large" else 1) for m in metrics)
    for m in metrics:
        assert Image.open(run / (m["state"] + ".png")).size == tuple(round(v * m["dpr"]) for v in m["size"])
        focus = (run / (m["state"] + "-window.txt")).read_text()
        assert any("mCurrentFocus=" in l and "io.github.shijijs.video_viewer" in l for l in focus.splitlines())
    db, requests = read(run / "database.json"), read(run / "requests.json")
    if name == "continuation":
        assert result["scenario"] == "continuation"
        proof = json.loads(next(l.split("PACK_CONTINUATION_VERIFIED:", 1)[1] for l in log.splitlines() if l.startswith("PACK_CONTINUATION_VERIFIED:")))
        assert proof["candidate_count"] == 4 and proof["source"] == "library"
        assert proof["after_summary"] == proof["final_progress"]
        assert proof["final_progress"]["page_index"] == 3
        assert db["counts"]["recent_entries"] == 1 and db["counts"]["pack_sessions"] == 2
        assert all(s["candidate_count"] == 4 for s in db["sessions"])
        continue
    assert result["scenario"] == "counts" and result["screens"] == SCENES
    proof = json.loads(next(l.split("CATALOG_COUNTS_VERIFIED:", 1)[1] for l in log.splitlines() if l.startswith("CATALOG_COUNTS_VERIFIED:")))
    assert proof["before_progress"] == proof["after_progress"]
    assert proof["transitions"] == [[2, 4], [2, 3], [2, 4]] and proof["recent"] == 0
    assert db["counts"] == {"videos": 2, "packs": 4, "pack_pages": 24, "recent_entries": 0,
        "pack_progress": 1, "pack_sessions": 0, "playback_rounds": 0, "pack_file_operations": 2, "pack_trash_items": 1}
    assert db["progress"][0]["ordinal"] == 2 and db["progress"][0]["revision"] == 1
    assert db["operations"] == [{"kind": "trash", "historical": 0}, {"kind": "restore", "historical": 0}]
    assert db["trash"][0]["status"] == "restored" and not db["trash"][0]["purged_pages"]
    assert [(r["method"], r["path"], r["status"]) for r in requests if r["method"] != "GET"] == [
        ("POST", "/api/v1/auth/login", 200),
        ("POST", "/api/v1/packs/trash", 202),
        ("POST", "/api/v1/pack-trash/restore", 202),
    ]
    assert not any(r["method"] == "POST" and (r["path"].endswith("/scans") or r["path"].endswith("/opened") or r["path"].endswith("/pack-sessions")) for r in requests)
    state_reads = [r for r in requests if r["path"] == "/api/v1/library-state"]
    assert all(r["method"] == "GET" for r in state_reads)
    assert any(r["status"] == 503 for r in state_reads)
    assert any(r["status"] == 200 and r["phase"] == "counts-error" for r in state_reads)
    for m in metrics:
        if m["state"] in ["counts-tags", "counts-recent"]:
            assert all("catalog-count-" not in key for key in m["keys"])
            continue
        expected = None if m["state"] == "counts-error" else {"video": 2, "pack": 3 if m["state"] == "counts-trash" else 4}
        assert m["counts"] == expected
        for kind in ["video", "pack"]:
            rect = m["keys"]["catalog-count-" + kind]
            label = "—" if expected is None else str(expected[kind])
            assert any(t["rect"] == rect and t["text"] == label and t["fontSize"] == 12 for t in m["texts"])
assert all(s == sources[0] for s in sources)
assert first_media == json.loads(git("show", "4785a69:docs/plans/library-first/evidence/lf8-shared-geometry/normal-1/media-before.json"))
for f in ["home.png", "packs.png", "metrics.json"]:
    frozen = subprocess.check_output(["git", "show", f"4785a69:docs/plans/library-first/evidence/lf8-shared-geometry/reference/{f}"], cwd=ROOT)
    assert hashlib.sha256(frozen).hexdigest() == sha(HERE / "reference" / f)
assert "+485: All tests passed!" in (HERE / "checks/client.log").read_text()
assert "75 passed" in (HERE / "checks/server.log").read_text()
assert "No issues found!" in (HERE / "checks/analyze.log").read_text()
assert "All checks passed!" in (HERE / "checks/ruff.log").read_text()
print(json.dumps({"verified": True, "source": SOURCE, "inputs": len(manifest),
    "counts_screens": 45, "continuation_regression_screens": 10,
    "client_tests": 485, "server_related_tests": 75,
    "scope": "catalog counts and tag resize only; LF8 remains open"}, indent=2))

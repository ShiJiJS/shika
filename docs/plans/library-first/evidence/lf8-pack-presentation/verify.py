"""Point-in-time public fixture evidence; requires Pillow; read-only."""

import hashlib
import json
import subprocess
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]


def read(p):
    return json.loads(p.read_text())


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def at_source(path):
    return hashlib.sha256(subprocess.check_output(["git", "show", f"{SOURCE}:{path}"], cwd=ROOT)).hexdigest()


def proof(log, marker):
    return json.loads(next(l.split(marker, 1)[1] for l in log.splitlines() if l.startswith(marker)))


contract = read(HERE / "source.json")
SOURCE, PROTO = contract["commit"], contract["prototype_tree"]
manifest = read(HERE / "manifest.json")
for path, expected in manifest.items():
    assert sha(HERE / path) == expected, path
    git("ls-files", "--error-unmatch", str((HERE / path).relative_to(ROOT)))
for path, expected in contract["files"].items():
    assert sha(ROOT / path) == at_source(path) == expected, path
assert git("rev-parse", "HEAD:design/reference/library-first") == PROTO == "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
for tree in ["apps/mobile/lib", "services/server/video_viewer"]:
    assert git("rev-parse", f"HEAD:{tree}") == git("rev-parse", f"{SOURCE}:{tree}")
reference = read(HERE / "reference/metrics.json")
assert reference["viewport"] == [390, 844, 1] and reference["history"] == []
assert reference["setup"]["progress"]["summer"] == 2
titles = [r["title"] for r in reference["order"]]
assert titles == ["加藤惠 · 和服", "灵梦 · 新年快乐", "夏日祭", "原野上的浪漫"]
for path, expected in read(HERE / "reference/served-source.json")["files"].items():
    assert sha(ROOT / "design/reference/library-first" / path) == expected
    assert at_source("design/reference/library-first/" + path) == expected
sources, first_media = [], None
dependency = read(HERE / "checks/runtime-dependency.json")
assert dependency["library"] == "libicui18n.so.72" and dependency["package"].endswith("72.1-3+deb12u1")
for name in ["normal-1", "normal-2", "normal-3", "large", "landscape", "counts", "continuation"]:
    run = HERE / name
    result, source, metrics = (read(run / p) for p in ["result.json", "source.json", "metrics.json"])
    assert result["passed"] and source["commit"] == SOURCE and source["prototype_tree"] == PROTO
    assert read(run / "runtime.json")[0]["Image"] == dependency["image"]
    for path, expected in source["files"].items():
        assert sha(ROOT / path) == at_source(path) == expected, path
    sources.append(source["files"])
    media = read(run / "media-before.json")
    assert media == read(run / "media-after.json") and len(media) == 26
    first_media = first_media or media
    assert media == first_media
    restore = read(run / "restored-viewport.json")
    assert restore["before"] == restore["after"] and not restore["errors"]
    assert restore["font_before"] == restore["font_after"]
    assert read(run / "prepared.json") == {"videos": 2, "packs": 4, "pages": 24}
    log = (run / "flutter.log").read_text()
    assert "All tests passed!" in log
    assert all(s not in log for s in ["PACK_PRESENTATION_ERROR:", "CATALOG_COUNTS_ERROR:", "CONTINUATION_LAYOUT_ERROR:"])
    assert len(metrics) == (9 if name == "counts" else 10)
    assert result["screens"] == [m["state"] for m in metrics]
    expected_size = [360, 809] if name == "large" else [844, 442] if name == "landscape" else [390, 905]
    for m in metrics:
        assert m["size"] == expected_size and m["textScale"] == (2 if name == "large" else 1)
        assert Image.open(run / (m["state"] + ".png")).size == tuple(round(v * m["dpr"]) for v in m["size"])
        focus = (run / (m["state"] + "-window.txt")).read_text()
        assert any("mCurrentFocus=" in l and "io.github.shijijs.video_viewer" in l for l in focus.splitlines())
    db, requests = read(run / "database.json"), read(run / "requests.json")
    assert db["counts"]["videos"] == 2 and db["counts"]["packs"] == 4 and db["counts"]["pack_pages"] == 24
    opened = [r for r in requests if r["method"] == "POST" and r["path"].endswith("/opened")]
    scans = [r for r in requests if r["method"] == "POST" and r["path"].endswith("/scans")]
    if name == "continuation":
        # The existing regression explicitly calls repo.refresh() to trigger
        # a catalog/summary reload after enabling its controlled fault.
        assert scans == [{"method": "POST", "path": "/api/v1/scans", "status": 202, "phase": "continue-multi"}]
    else:
        assert not scans
    if name == "counts":
        p = proof(log, "CATALOG_COUNTS_VERIFIED:")
        assert p["before_progress"] == p["after_progress"] and p["transitions"] == [[2, 4], [2, 3], [2, 4]]
        assert not opened and not db["counts"]["recent_entries"] and not db["counts"]["pack_sessions"]
        assert db["operations"] == [{"kind": "trash", "historical": 0}, {"kind": "restore", "historical": 0}]
        assert db["trash"] == [{"status": "restored", "purged_pages": 0}]
        by_state = {m["state"]: m for m in metrics}
        assert by_state["counts-error"]["counts"] is None
        assert by_state["counts-retry"]["counts"] == {"video": 2, "pack": 4}
        continue
    assert len(opened) == 2 and all(r["status"] == 200 for r in opened)
    assert db["counts"]["pack_sessions"] == 2 and not db["operations"] and not db["trash"]
    if name == "continuation":
        p = proof(log, "PACK_CONTINUATION_VERIFIED:")
        assert p["candidate_count"] == 4 and p["source"] == "library"
        assert p["after_summary"] == p["final_progress"] and p["final_progress"]["page_index"] == 3
        assert db["counts"]["recent_entries"] == 1 and db["counts"]["pack_progress"] == 1
        continue
    p = proof(log, "PACK_PRESENTATION_VERIFIED:")
    assert result["scenario"] == "presentation" and p["titles"] == titles
    assert p["authors"] == ["示例作者"] * 4 and p["queue_ids"] == p["newest_ids"]
    packs = {r["id"]: r for r in db["packs"]}
    assert [packs[i]["name"] for i in p["title_ids"]] == p["raw_names"]
    assert p["raw_names"] == [r["folder"] for r in read(HERE / "reference/order.json")["order"]]
    assert p["newest_ids"] == [r["id"] for r in sorted(db["packs"], key=lambda r: (-r["created_at"], r["id"]))]
    sessions = {r["id"]: r for r in db["sessions"]}
    for key, expected, sort, search in [("filtered_range", [p["title_ids"][2]], "title", "夏日祭"), ("newest_range", p["newest_ids"], "newest", "")]:
        s = sessions[p[key]]
        assert s["candidate_count"] == len(expected) and json.loads(s["source"]) == {"kind": "library", "sort": sort}
        assert json.loads(s["scope"])["search"] == search
        assert [r["pack_id"] for r in db["entries"] if r["session_id"] == s["id"]] == expected
    assert p["before_read"]["page_index"] == 2 and p["before_read"]["revision"] == 1
    assert p["recent_total"] == db["counts"]["recent_entries"] == len({p["title_ids"][2], p["newest_ids"][0]})
    by_state = {m["state"]: m for m in metrics}
    assert any(t["text"] == "示例作者 · 034" and t["fontSize"] == 12 for t in by_state["presentation-reader"]["texts"])
    assert any(t["text"] == "在读 · 3" and t["fontSize"] == 12 for t in by_state["presentation-title"]["texts"])
    if name.startswith("normal"):
        texts = by_state["presentation-library"]["texts"]
        assert all(any(t["text"] == title and t["fontSize"] == 16 for t in texts) for title in titles)
assert all(s == sources[0] for s in sources)
assert first_media == json.loads(git("show", "4785a69:docs/plans/library-first/evidence/lf8-shared-geometry/normal-1/media-before.json"))
assert "+494: All tests passed!" in (HERE / "checks/client.log").read_text()
assert "111 passed" in (HERE / "checks/server.log").read_text()
assert "No issues found!" in (HERE / "checks/analyze.log").read_text()
assert "All checks passed!" in (HERE / "checks/ruff.log").read_text()
print(json.dumps({"verified": True, "source": SOURCE, "inputs": len(manifest), "presentation_screens": 50,
    "regression_screens": 19, "client_tests": 494, "server_related_tests": 111,
    "scope": "pack presentation/order only; full LF8 remains open"}, indent=2))

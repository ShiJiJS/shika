"""Read-only, point-in-time verification of the public native card evidence."""

import hashlib
import json
import subprocess
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def at_source(path):
    return hashlib.sha256(subprocess.check_output(["git", "show", f"{SOURCE}:{path}"], cwd=ROOT)).hexdigest()


def proof(log, marker):
    return json.loads(next(row.split(marker, 1)[1] for row in log.splitlines() if row.startswith(marker)))


contract = read(HERE / "source.json")
SOURCE, PROTO = contract["commit"], contract["prototype_tree"]
manifest = read(HERE / "manifest.json")
for path, expected in manifest.items():
    assert sha(HERE / path) == expected, path
    git("ls-files", "--error-unmatch", str((HERE / path).relative_to(ROOT)))
for path, expected in contract["files"].items():
    assert sha(ROOT / path) == at_source(path) == expected, path
assert git("rev-parse", "HEAD:design/reference/library-first") == PROTO == "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
assert git("rev-parse", "HEAD:apps/mobile/lib") == git("rev-parse", f"{SOURCE}:apps/mobile/lib")
assert git("rev-parse", "HEAD:services/server/video_viewer") == git("rev-parse", f"{SOURCE}:services/server/video_viewer") == git("rev-parse", contract["server_unchanged_from"] + ":services/server/video_viewer")
reference = read(HERE / "reference/metrics.json")
assert reference["viewport"] == [390, 844, 1] and reference["history"] == []
assert reference["setup"]["progress"]["summer"] == 2
titles = [r["title"] for r in reference["order"]]
for path, expected in read(HERE / "reference/served-source.json")["files"].items():
    assert sha(ROOT / "design/reference/library-first" / path) == at_source("design/reference/library-first/" + path) == expected

sources, first_media, screenshots = [], None, 0
for name in ["normal-1", "normal-2", "normal-3", "large", "landscape", "shared", "presentation", "continuation", "counts"]:
    run = HERE / name
    result, source, metrics = (read(run / p) for p in ["result.json", "source.json", "metrics.json"])
    assert result["passed"] and source["commit"] == SOURCE and source["prototype_tree"] == PROTO
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
    assert "All tests passed!" in log and "PROTOTYPE_FIDELITY_VERIFIED" in log
    assert all(s not in log for s in ["CATALOG_CARDS_ERROR:", "PACK_PRESENTATION_ERROR:", "CATALOG_COUNTS_ERROR:", "CONTINUATION_LAYOUT_ERROR:"])
    expected_count = 8 if name == "shared" else 10 if name in ["presentation", "continuation"] else 9 if name == "counts" else 6
    assert len(metrics) == expected_count and result["screens"] == [m["state"] for m in metrics]
    expected_size = [360, 809] if name in ["large", "continuation"] else [844, 442] if name in ["landscape", "presentation"] else [390, 905]
    for m in metrics:
        assert m["size"] == expected_size and m["textScale"] == (2 if name in ["large", "continuation"] else 1)
        assert Image.open(run / (m["state"] + ".png")).size == tuple(round(v * m["dpr"]) for v in m["size"])
        focus = (run / (m["state"] + "-window.txt")).read_text()
        assert any("mCurrentFocus=" in line and "io.github.shijijs.video_viewer" in line for line in focus.splitlines())
    screenshots += len(metrics)
    db, requests = read(run / "database.json"), read(run / "requests.json")
    assert db["counts"]["videos"] == 2 and db["counts"]["packs"] == 4 and db["counts"]["pack_pages"] == 24
    opened = [r for r in requests if r["method"] == "POST" and r["path"].endswith("/opened")]
    scans = [r for r in requests if r["method"] == "POST" and r["path"].endswith("/scans")]
    if name == "continuation":
        assert scans == [{"method": "POST", "path": "/api/v1/scans", "status": 202, "phase": "continue-multi"}]
        p = proof(log, "PACK_CONTINUATION_VERIFIED:")
        assert p["candidate_count"] == 4 and p["source"] == "library"
        assert p["after_summary"] == p["final_progress"] and p["final_progress"]["page_index"] == 3
        assert abs(p["return_offset"] - p["expected_return_offset"]) <= 1
        assert p["return_offset"] > 0 and p["return_anchor"] in [r["id"] for r in db["packs"]]
        assert len(opened) == 2 and db["counts"]["pack_sessions"] == 2 and db["counts"]["recent_entries"] == 1
        continue
    assert not scans
    if name == "counts":
        p = proof(log, "CATALOG_COUNTS_VERIFIED:")
        assert p["before_progress"] == p["after_progress"] and p["transitions"] == [[2, 4], [2, 3], [2, 4]]
        assert not opened and not db["counts"]["recent_entries"] and not db["counts"]["pack_sessions"]
        assert db["operations"] == [{"kind": "trash", "historical": 0}, {"kind": "restore", "historical": 0}]
        assert db["trash"] == [{"status": "restored", "purged_pages": 0}]
        continue
    if name == "presentation":
        p = proof(log, "PACK_PRESENTATION_VERIFIED:")
        assert p["titles"] == titles and p["authors"] == ["示例作者"] * 4
        assert p["queue_ids"] == p["newest_ids"] and len(opened) == 2 and db["counts"]["pack_sessions"] == 2
        sessions = {r["id"]: r for r in db["sessions"]}
        for key, ids, sort in [("filtered_range", [p["title_ids"][2]], "title"), ("newest_range", p["newest_ids"], "newest")]:
            session = sessions[p[key]]
            assert session["candidate_count"] == len(ids) and json.loads(session["source"])["sort"] == sort
            assert [r["pack_id"] for r in db["entries"] if r["session_id"] == session["id"]] == ids
        continue
    assert not opened and not db["counts"]["recent_entries"] and not db["counts"]["pack_sessions"]
    assert not db["operations"] and not db["trash"] and not db["counts"]["playback_rounds"]
    assert len(db["progress"]) == 1 and db["progress"][0]["ordinal"] == 2 and db["progress"][0]["revision"] == 1
    assert all(r["method"] == "GET" or r["path"] == "/api/v1/auth/login" for r in requests)
    if name == "shared":
        continue
    p = proof(log, "CATALOG_CARDS_VERIFIED:")
    assert p["before_progress"] == p["after_progress"] and p["recent"] == 0
    assert len(p["pack_ids"]) == 4 and len(p["video_ids"]) == 2
    columns = 4 if name == "landscape" else 2
    assert p["expected_columns"] == columns
    for m in metrics:
        assert m["counts"] == {"video": 2, "pack": 4}
        assert all(g["columns"] == columns and g["stride"] == (340 if name == "large" else 313) for g in m["grids"].values())
    for scene, text in [("cards-video-meta", "横屏"), ("cards-pack-meta", "示例作者")]:
        m = next(m for m in metrics if m["state"] == scene)
        meta = next(t for t in m["texts"] if t["text"] == text)
        x, y, w, h = meta["rect"]
        pixels = Image.open(run / (scene + ".png")).convert("RGB").crop(tuple(round(v * m["dpr"]) for v in [x, y, x + w, y + h]))
        colors = pixels.getcolors(pixels.width * pixels.height)
        assert sum(count for count, color in colors if color == (98, 110, 89)) > 10
        tags = [t for t in m["texts"] if (t["text"] or "").startswith("# ")]
        assert tags and all(t["fontSize"] == 12 for t in tags)

assert screenshots == 67 and all(s == sources[0] for s in sources)
assert first_media == json.loads(git("show", "4785a69:docs/plans/library-first/evidence/lf8-shared-geometry/normal-1/media-before.json"))
assert "+501: All tests passed!" in (HERE / "checks/client.log").read_text()
assert "No issues found!" in (HERE / "checks/analyze.log").read_text()
assert "All checks passed!" in (HERE / "checks/ruff.log").read_text()
assert "Continuation timeout: real history appears" in (HERE / "diagnostics/lazy-return-flutter.log").read_text()
print(json.dumps({"verified": True, "source": SOURCE, "inputs": len(manifest), "native_screens": screenshots,
    "client_tests": 501, "server_production_unchanged": True, "server_tests_rerun": False,
    "scope": "Card layout and selected regressions; full LF8 remains open"}, indent=2))

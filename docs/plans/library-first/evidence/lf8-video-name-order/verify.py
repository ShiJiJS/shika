"""Point-in-time native evidence over public fixtures; read-only."""

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


def git_sha(commit, path):
    return hashlib.sha256(subprocess.check_output(["git", "show", f"{commit}:{path}"], cwd=ROOT)).hexdigest()


def proof(log, marker):
    return json.loads(next(line.split(marker, 1)[1] for line in log.splitlines() if line.startswith(marker)))


contract = read(HERE / "source.json")
SOURCE, TEST = contract["commit"], contract["test_commit"]
manifest = read(HERE / "manifest.json")
for path, expected in manifest.items():
    assert sha(HERE / path) == expected, path
    git("ls-files", "--error-unmatch", str((HERE / path).relative_to(ROOT)))
for path, expected in contract["files"].items():
    commit = TEST if path in contract["test_files"] else SOURCE
    assert sha(ROOT / path) == git_sha(commit, path) == expected, path
for tree in ["apps/mobile/lib", "services/server/video_viewer"]:
    assert git("rev-parse", "HEAD:" + tree) == git("rev-parse", SOURCE + ":" + tree) == git("rev-parse", TEST + ":" + tree)
assert git("rev-parse", "HEAD:apps/mobile/test") == contract["test_tree"]
assert git("rev-parse", "HEAD:services/server/tests") == contract["server_test_tree"]
assert git("rev-parse", "HEAD:design/reference/library-first") == contract["prototype_tree"] == "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
reference = read(HERE / "reference/metrics.json")
assert reference["viewport"] == [390, 844, 1] and reference["setup"]["history_after"] == []
assert [row["title"] for row in reference["order"]] == ["风里的花园", "水边的花"]
for path, expected in read(HERE / "reference/served-source.json")["files"].items():
    assert sha(ROOT / "design/reference/library-first" / path) == git_sha(SOURCE, "design/reference/library-first/" + path) == expected
sources, media, screenshots = [], None, 0
runtime = read(HERE / "checks/runtime-dependency.json")
assert runtime["architecture"] == "arm64" and runtime["icu_package"].endswith("72.1-3+deb12u1")
for name in ["normal-1", "normal-2", "normal-3", "large", "landscape", "cards", "shared", "presentation"]:
    run = HERE / name
    result, source, metrics = (read(run / p) for p in ["result.json", "source.json", "metrics.json"])
    assert result["passed"] and source["commit"] == SOURCE and source["prototype_tree"] == contract["prototype_tree"]
    assert read(run / "runtime.json")[0]["Image"] == runtime["image"]
    for path, expected in source["files"].items():
        assert sha(ROOT / path) == git_sha(SOURCE, path) == expected, path
    sources.append(source["files"])
    before = read(run / "media-before.json")
    assert before == read(run / "media-after.json") and len(before) == 26
    media = media or before
    assert media == before
    restore = read(run / "restored-viewport.json")
    assert restore["before"] == restore["after"] and restore["font_before"] == restore["font_after"] and not restore["errors"]
    assert read(run / "prepared.json") == {"videos": 2, "packs": 4, "pages": 24}
    assert len(metrics) == (6 if name == "cards" else 10 if name == "presentation" else 8)
    assert result["screens"] == [m["state"] for m in metrics]
    size = [360, 809] if name == "large" else [844, 442] if name in ["landscape", "cards"] else [390, 905]
    for m in metrics:
        assert m["size"] == size and m["textScale"] == (2 if name == "large" else 1)
        assert Image.open(run / (m["state"] + ".png")).size == tuple(round(v * m["dpr"]) for v in size)
        focus = (run / (m["state"] + "-window.txt")).read_text()
        assert any("mCurrentFocus=" in line and "io.github.shijijs.video_viewer" in line for line in focus.splitlines())
    screenshots += len(metrics)
    log = (run / "flutter.log").read_text()
    assert "All tests passed!" in log and "PROTOTYPE_FIDELITY_VERIFIED" in log
    assert all(s not in log for s in ["VIDEO_NAME_ORDER_ERROR:", "PACK_PRESENTATION_ERROR:", "CATALOG_CARDS_ERROR:"])
    db, requests = read(run / "database.json"), read(run / "requests.json")
    assert [db["counts"][t] for t in ["videos", "packs", "pack_pages"]] == [2, 4, 24]
    assert not db["operations"] and not db["trash"]
    assert not any(r["method"] == "POST" and r["path"] == "/api/v1/scans" for r in requests)
    if name == "presentation":
        p = proof(log, "PACK_PRESENTATION_VERIFIED:")
        assert p["queue_ids"] == p["newest_ids"] and p["authors"] == ["示例作者"] * 4
        assert db["counts"]["pack_sessions"] == 2 and not db["rounds"]
        continue
    assert len(db["progress"]) == 1 and db["progress"][0]["ordinal"] == 2 and db["progress"][0]["revision"] == 1
    assert not db["sessions"]
    if name in ["cards", "shared"]:
        assert not db["rounds"] and not db["recent"]
        if name == "cards":
            p = proof(log, "CATALOG_CARDS_VERIFIED:")
            assert p["before_progress"] == p["after_progress"] and p["expected_columns"] == 4
        continue
    p = proof(log, "VIDEO_NAME_ORDER_VERIFIED:")
    assert all(m["library_ready"] for m in metrics)
    assert p["names"] == [r["title"] + ".mp4" for r in reference["order"]]
    assert p["ids"] == p["queue_ids"] and p["recent"] == p["ids"][::-1]
    assert p["public_sort"] == "name" and p["name_locale"] == "zh-CN"
    assert [r["video_id"] for r in db["recent"]] == p["recent"]
    rounds = {r["id"]: r for r in db["rounds"]}
    assert len(rounds) == 2 and db["counts"]["recent_entries"] == 2
    for key, ids, search in [("filtered_round", p["ids"][:1], "风里的花园"), ("full_round", p["ids"], "")]:
        r = rounds[p[key]]
        assert r["sort"] == "name_zh" and r["membership"] == "fixed" and r["source"] == "library"
        assert json.loads(r["scope"]).get("search", "") == search and r["candidate_count"] == len(ids)
        entries = [e for e in db["round_entries"] if e["round_id"] == r["id"]]
        assert [e["video_id"] for e in entries] == ids
        assert [e["source_ordinal"] for e in entries] == list(range(len(ids)))
    creates = [r for r in requests if r["method"] == "POST" and r["path"] == "/api/v1/rounds"]
    assert len(creates) == 2 and all(r["body"]["sort"] == "name" and r["body"]["name_locale"] == "zh-CN" for r in creates)
    assert len([r for r in requests if r["method"] == "POST" and r["path"].endswith("/opened")]) == 3
    reads = [dict(r["query"]) for r in requests if r["method"] == "GET" and r["path"] in ["/api/v1/videos", "/api/v1/videos/selection"] and dict(r["query"]).get("sort") == "name"]
    assert len(reads) >= 4 and all(r.get("name_locale") == "zh-CN" for r in reads)
    assert all(not r["round"] for r in metrics[:2])
assert screenshots == 64 and all(s == sources[0] for s in sources)
assert media == json.loads(git("show", "4785a69:docs/plans/library-first/evidence/lf8-shared-geometry/normal-1/media-before.json"))
assert "+505: All tests passed!" in (HERE / "checks/client.log").read_text()
assert "88 passed" in (HERE / "checks/server.log").read_text()
assert "No issues found!" in (HERE / "checks/analyze.log").read_text()
assert "All checks passed!" in (HERE / "checks/ruff.log").read_text()
assert "No active player with ID" in (HERE / "diagnostics/native-exit-before-fix/flutter.log").read_text()
assert "+0 -2" in (HERE / "diagnostics/exit-old.log").read_text()
print(json.dumps({"verified": True, "source": SOURCE, "test_commit": TEST, "inputs": len(manifest),
    "native_screens": screenshots, "client_tests": 505, "server_related_tests": 88,
    "scope": "Video name order and preview exit only; full LF8 remains open"}, indent=2))

"""Read-only verification of native missing management, exact receipts and source bytes."""

import hashlib
import json
import struct
import subprocess
from pathlib import Path

root = Path.cwd()
evidence = root / "docs/plans/library-first/evidence/lf8-missing-management"
rounds = json.loads((evidence / "verification.json").read_text())
assert len(rounds) == 3 and all(r["exit_code"] == 0 for r in rounds)
phases = [
    "roots-created",
    "roots-disabled",
    "roots-conflict",
    "missing-paged",
    "missing-preserved",
    "missing-unknown",
    "missing-reopened",
    "missing-result",
    "missing-task-paged",
]
proof = []
for row in rounds:
    folder = evidence / f"round-{row['round']}"
    events = json.loads((folder / "lf7-roots-missing-host-events.json").read_text())
    assert not events["errors"]
    actual = [e["phase"] for e in events["events"]]
    assert all(p in actual for p in phases) and "error" not in actual
    files, traces, stats = {}, {}, {}
    for phase in phases:
        base = folder / f"lf7-roots-missing-{phase}"
        assert base.with_suffix(".png").is_file()
        focus = Path(str(base) + "-window.txt").read_text()
        assert "Application Not Responding" not in focus
        assert any(
            "mCurrentFocus=" in line and "io.github.shijijs.video_viewer" in line
            for line in focus.splitlines()
        )
        files[phase] = json.loads(Path(str(base) + "-files.json").read_text())["hashes"]
        traces[phase] = json.loads(Path(str(base) + "-requests.json").read_text())[
            "items"
        ]
        stats[phase] = json.loads(Path(str(base) + "-stats.json").read_text())
    initial = files["roots-created"]
    assert len(initial) == 81
    assert files["roots-disabled"] == files["roots-conflict"] == initial
    kept = {
        p: sha for p, sha in initial.items() if p.startswith(("图包26/", "图包27/"))
    }
    assert len(kept) == 6
    assert files["missing-paged"] == files["missing-preserved"] == kept
    returned = files["missing-unknown"]
    assert len(returned) == 7 and set(returned) - set(kept) == {"图包25/1.jpg"}
    assert all(returned[p] == sha for p, sha in kept.items())
    assert all(files[p] == returned for p in phases[6:])
    first = stats["roots-conflict"]["first_pack"]
    assert first["status"] == "available" and first["progress"] and first["preferences"]
    assert first["tag_links"] == first["recent"] == first["session_members"] == 1
    assert not stats["missing-paged"]["cleanups"]
    preserved = stats["missing-preserved"]
    assert len(preserved["cleanups"]) == 1
    job = preserved["cleanups"][0]
    assert job["status"] == "completed" and job["members"] == {"skipped": 25}
    assert job["result"] == {
        "total": 25,
        "processed": 25,
        "succeeded": 0,
        "failed": 0,
        "skipped": 25,
        "partial": True,
    }
    assert preserved["first_pack"] == {**first, "status": "missing"}
    final = stats["missing-task-paged"]
    assert len(final["cleanups"]) == 2 and final["cleanups"][0] == job
    removed = final["cleanups"][1]
    assert removed["status"] == "completed" and removed["members"] == {
        "skipped": 1,
        "succeeded": 24,
    }
    assert removed["result"] == {
        "total": 25,
        "processed": 25,
        "succeeded": 24,
        "failed": 0,
        "skipped": 1,
        "partial": True,
    }
    assert final["pack_statuses"] == {"available": 2, "deleted": 24, "missing": 1}
    assert final["first_pack"] == {
        "id": first["id"],
        "status": "deleted",
        "progress": False,
        "preferences": False,
        "tag_links": 0,
        "recent": 0,
        "session_members": 1,
    }
    trace = traces["missing-task-paged"]
    assert all(e["authenticated"] for e in trace)
    changes = [e for e in trace if e["method"] != "GET"]
    new_root = [e for e in changes if e["path"] == "/api/v1/roots"]
    assert len(new_root) == 1 and new_root[0]["status"] == 201
    assert (
        new_root[0]["root_input"]["kind"] == "pack"
        and new_root[0]["root_input"]["enabled"]
    )
    edits = [e for e in changes if e["path"].startswith("/api/v1/roots/")]
    assert [
        (e["root_input"]["kind"], e["root_input"]["enabled"], e["status"])
        for e in edits
    ] == [
        ("pack", False, 200),
        ("pack", True, 200),
        ("video", True, 409),
        ("pack", False, 200),
        ("pack", True, 200),
    ]
    clears = [e for e in changes if e["path"] == "/api/v1/packs/forget-missing"]
    assert len(clears) == 2 and [e["status"] for e in clears] == [202, 503]
    assert [e["command_hash"] for e in clears] == [
        job["request_hash"],
        removed["request_hash"],
    ]
    receipts = [
        e for e in trace if e["path"].startswith("/api/v1/pack-missing-requests/")
    ]
    assert (
        len(receipts) == 1
        and receipts[0]["method"] == "GET"
        and receipts[0]["status"] == 200
    )
    assert (
        hashlib.sha256(receipts[0]["path"].split("/")[-1].encode()).hexdigest()
        == removed["request_hash"]
    )
    for phase in ["missing-paged", "missing-unknown", "missing-reopened"]:
        assert not any("/pack-missing-requests/" in e["path"] for e in traces[phase])
    assert not any(
        e["path"] == "/api/v1/packs/forget-missing" for e in traces["missing-paged"]
    )
    assert len([e for e in changes if e["path"] == "/api/v1/scans"]) == 2
    allowed = {
        "/api/v1/roots",
        "/api/v1/scans",
        "/api/v1/pack-sessions",
        "/api/v1/pack-tags",
        "/api/v1/pack-tag-links",
        "/api/v1/packs/forget-missing",
    }
    assert all(
        e["path"] in allowed
        or e["path"].startswith("/api/v1/roots/")
        or e["path"].startswith("/api/v1/pack-sessions/")
        and e["path"].endswith("/opened")
        for e in changes
    )
    member_pages = [
        e
        for e in trace
        if e["path"] == f"/api/v1/maintenance-tasks/{removed['id']}/items"
    ]
    assert any(
        e["query"].get("offset") == "24" and e["query"].get("limit") == "24"
        for e in member_pages
    )
    log = (folder / "lf7-roots-missing-android-test.log").read_text()
    assert "All tests passed!" in log
    marker = next(
        line.split("VV_MISSING_PROOF ", 1)[1]
        for line in log.splitlines()
        if "VV_MISSING_PROOF " in line
    )
    check = json.loads(marker)
    assert check == {
        "preserved_disabled": 25,
        "removed": 24,
        "returned_preserved": 1,
        "old_id_retained": True,
        "current_video_unchanged": True,
    }
    extra = [
        "missing-empty-video",
        "missing-first",
        "missing-confirm-cancel",
        "missing-dark",
    ]
    for phase in extra:
        stem = folder / f"lf7-roots-missing-{phase}"
        assert stem.with_suffix(".png").is_file()
        focus = Path(str(stem) + "-window.txt").read_text()
        assert any(
            "mCurrentFocus=" in line and "io.github.shijijs.video_viewer" in line
            for line in focus.splitlines()
        )
        snapshot = json.loads(Path(str(stem) + "-files.json").read_text())["hashes"]
        assert snapshot == (returned if phase == "missing-dark" else kept)
        requests = json.loads(Path(str(stem) + "-requests.json").read_text())["items"]
        if phase == "missing-confirm-cancel":
            assert not any(
                e["path"] == "/api/v1/packs/forget-missing" for e in requests
            )
    metrics = [
        json.loads(line.split("MISSING_METRICS:", 1)[1])
        for line in log.splitlines()
        if "MISSING_METRICS:" in line
    ]
    for phase in phases + extra:
        raw = (folder / f"lf7-roots-missing-{phase}.png").read_bytes()
        assert raw[:8] == b"\x89PNG\r\n\x1a\n"
        assert struct.unpack(">II", raw[16:24]) == tuple(
            int(v * 3) for v in row["window"]
        )
    assert len(metrics) == 13 and {m["state"] for m in metrics} == set(phases + extra)
    assert all(m["window"] == row["window"] and m["dpr"] == 3 for m in metrics)
    for m in metrics:
        if "missing-header" in m["rects"]:
            assert (
                abs(
                    m["rects"]["missing-header"][2]
                    - (row["window"][0] - m["viewPadding"][0] - m["viewPadding"][2])
                )
                < 1
            )
            # Platform geometry can serialize 52dp as 51.99999999999999.
            assert m["rects"]["missing-header"][3] >= 51.99
        assert m["dark"] == (m["state"] == "missing-dark")
    restored = json.loads((folder / "restored-viewport.json").read_text())
    assert (
        restored["before"]
        == restored["after"]
        == {
            "size": "Physical size: 1080x2400",
            "density": "Physical density: 420",
            "font_scale": "1.0",
        }
    )
    current_source = json.loads((folder / "source.json").read_text())
    canonical = json.loads((evidence / "source.json").read_text())
    assert current_source == canonical
    assert current_source["commit"] == row["source_commit"]
    assert current_source["prototype_tree"] == canonical["prototype_tree"]
    for path, sha in current_source["files"].items():
        # Every final profile pins the same production and harness bytes.
        if path.startswith(("apps/mobile/lib/", "services/server/video_viewer/")):
            assert sha == canonical["files"][path]
        blob = subprocess.check_output(
            ["git", "show", f"{current_source['commit']}:{path}"], cwd=root
        )
        assert hashlib.sha256(blob).hexdigest() == sha
    proof.append(
        {
            "round": row["round"],
            "root_edits": 5,
            "disabled_preserved": 25,
            "metadata_removed": 24,
            "returned_preserved": 1,
            "cleanup_posts": 2,
            "original_receipt_gets": 1,
            "retained_source_images": 7,
            "app_assertions": check,
        }
    )
source = json.loads((evidence / "source.json").read_text())
assert all(row["source_commit"] == source["commit"] for row in rounds)
assert all(
    hashlib.sha256((root / p).read_bytes()).hexdigest() == sha
    for p, sha in source["files"].items()
)
unit_source = json.loads((evidence / "checks/source.json").read_text())
for path, sha in unit_source["files"].items():
    assert hashlib.sha256((root / path).read_bytes()).hexdigest() == sha
    blob = subprocess.check_output(
        ["git", "show", f"{unit_source['commit']}:{path}"], cwd=root
    )
    assert hashlib.sha256(blob).hexdigest() == sha
for index in (1, 2, 3):
    unit = (evidence / "checks" / f"targeted-{index}.log").read_text()
    assert "+21: All tests passed!" in unit and "Some tests failed" not in unit
assert "No issues found!" in (evidence / "checks/analyze.log").read_text()
assert "All checks passed!" in (evidence / "checks/ruff.log").read_text()
supplement = []
for profile, window, text13 in [
    ("large", [360, 740], 26),
    ("landscape", [844, 390], 13),
]:
    folder = evidence / "supplement" / profile
    pinned = json.loads((folder / "source.json").read_text())
    assert pinned["production_commit"] == source["commit"]
    for path, sha in pinned["files"].items():
        assert hashlib.sha256((root / path).read_bytes()).hexdigest() == sha
        if path in source["files"]:
            assert source["files"][path] == sha
        else:
            archived = evidence / "supplement/sources" / path
            assert hashlib.sha256(archived.read_bytes()).hexdigest() == sha
    metrics = json.loads((folder / "metrics.json").read_text())
    assert len(metrics) == 2
    retained = None
    stats = None
    for m in metrics:
        assert m["window"] == window and m["text13"] == text13 and m["dpr"] == 3
        assert m["remaining_scroll"] <= 1
        stem = folder / f"lf7-roots-missing-{m['state']}"
        raw = stem.with_suffix(".png").read_bytes()
        assert struct.unpack(">II", raw[16:24]) == tuple(v * 3 for v in window)
        focus = Path(str(stem) + "-window.txt").read_text()
        assert any(
            "mCurrentFocus=" in line and "io.github.shijijs.video_viewer" in line
            for line in focus.splitlines()
        )
        trace = json.loads(Path(str(stem) + "-requests.json").read_text())["items"]
        assert all(e["method"] == "GET" and e["authenticated"] for e in trace)
        snapshot = json.loads(Path(str(stem) + "-files.json").read_text())["hashes"]
        assert len(snapshot) == 6
        state = json.loads(Path(str(stem) + "-stats.json").read_text())
        assert not state["cleanups"]
        if retained is not None:
            assert retained == snapshot and stats == state
        retained, stats = snapshot, state
    assert metrics[1]["confirmation_tail_visible"]
    log = (folder / "android-test.log").read_text()
    assert "All tests passed!" in log
    marker = next(
        line.split("MISSING_FOOTER_VERIFIED:", 1)[1]
        for line in log.splitlines()
        if "MISSING_FOOTER_VERIFIED:" in line
    )
    assert json.loads(marker) == {
        "images": 6,
        "zero_writes_after_preparation": True,
        "current_video_unchanged": True,
        "cancelled": True,
    }
    restored = json.loads((folder / "restored-viewport.json").read_text())
    assert (
        restored["before"]
        == restored["after"]
        == {
            "size": "Physical size: 1080x2400",
            "density": "Physical density: 420",
            "font_scale": "1.0",
        }
    )
    assert not json.loads((folder / "host-events.json").read_text())["errors"]
    supplement.append(
        {"profile": profile, "footer_and_confirmation": 2, "cancel_zero_writes": True}
    )
manifest = json.loads((evidence / "manifest.json").read_text())
assert all(
    hashlib.sha256((evidence / name).read_bytes()).hexdigest() == sha
    for name, sha in manifest.items()
)
print(
    json.dumps(
        {
            "verified": True,
            "native_screens": 39,
            "supplemental_screens": 4,
            "supplement": supplement,
            "rounds": proof,
            "source": source["commit"],
            "manifest_inputs": len(manifest),
        },
        ensure_ascii=False,
    )
)

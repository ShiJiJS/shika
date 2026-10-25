"""Read-only evidence verification. Requires Pillow; uses no NAS or credentials."""

import hashlib
import json
import subprocess
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SOURCE = "a9da395"
PROTO = "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
SCENES = [
    "home",
    "packs",
    "video-tags",
    "pack-tags",
    "settings",
    "settings-bottom",
    "dark",
    "dark-bottom",
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
    "rev-parse", "7f195ff:services/server/video_viewer"
)
first_media = None
sources = []
windows = []
for name in ["normal-1", "normal-2", "normal-3", "large", "landscape"]:
    run = HERE / name
    result, source, metrics = (
        read(run / f) for f in ["result.json", "source.json", "metrics.json"]
    )
    assert result["passed"] and result["screens"] == SCENES
    assert git("rev-parse", source["commit"]) == git("rev-parse", SOURCE)
    assert source["prototype_tree"] == PROTO
    for path, sha in source["files"].items():
        assert digest(ROOT / path) == sha, path
    sources.append(source["files"])
    media = read(run / "media-before.json")
    assert media == read(run / "media-after.json") and len(media) == 26
    if first_media is None:
        first_media = media
    assert media == first_media
    restored = read(run / "restored-viewport.json")
    assert (
        restored["before"] == restored["after"]
        and restored["font_before"] == restored["font_after"]
    )
    assert not restored["errors"]
    assert len(metrics) == 8
    assert read(run / "prepared.json") == {"videos": 2, "packs": 4, "pages": 24}
    sql = read(run / "database-counts.json")
    assert sql["videos"] == 2 and sql["packs"] == 4 and sql["pack_pages"] == 24
    assert "All tests passed!" in (run / "flutter.log").read_text()
    for m in metrics:
        image = Image.open(run / (m["state"] + ".png")).convert("RGB")
        assert image.size == tuple(round(v * m["dpr"]) for v in m["size"])
        focus = (run / (m["state"] + "-window.txt")).read_text()
        assert any(
            "mCurrentFocus=" in line and "io.github.shijijs.video_viewer" in line
            for line in focus.splitlines()
        )
        # Actual rendered pixels, not merely the preference or switch state.
        pixel = (
            round((m["viewPadding"][0] + 5) * m["dpr"]),
            round((m["viewPadding"][1] + 100) * m["dpr"]),
        )
        expected = (20, 25, 20) if m["state"].startswith("dark") else (250, 248, 243)
        assert image.getpixel(pixel) == expected, (
            name,
            m["state"],
            image.getpixel(pixel),
        )
    windows.append(
        {
            "run": name,
            "window": metrics[0]["size"],
            "viewPadding": metrics[0]["viewPadding"],
            "scale": metrics[0]["textScale"],
        }
    )
    if name.startswith("normal"):
        m = {m["state"]: m for m in metrics}
        assert m["home"]["keys"]["video-search"] == [60, 146, 314, 42]
        assert m["home"]["keys"]["app-navigation"] == [0, 831, 390, 50]
        assert all(
            t["rect"][1] == 475
            for t in m["home"]["texts"]
            if (t["text"] or "").endswith(".mp4")
        )
        groups = {
            t["text"]: t["rect"][1] - 49
            for t in m["settings"]["texts"]
            if t["text"] in ["连接与文件", "数据维护", "偏好"]
        }
        assert groups == {"连接与文件": 68, "数据维护": 251, "偏好": 503}
        for state in ["settings-bottom", "dark-bottom"]:
            title = next(t for t in m[state]["texts"] if t["text"] == "阅读偏好")
            assert title["rect"][1] + title["rect"][3] < 831
assert all(source == sources[0] for source in sources)
exported = read(HERE / "inputs/media-export-sha256.json")
for pack in read(HERE / "inputs/packs.json"):
    for index, page in enumerate(pack["pages"]):
        raster = Path(page).with_suffix(".png").name
        expected = next(
            sha for path, sha in exported.items() if path.endswith("/raster/" + raster)
        )
        assert first_media[f"packs/{pack['folder']}/{index + 1:04d}.png"] == expected
for orientation, folder, title in [
    ("landscape", "横屏", "风里的花园"),
    ("portrait", "竖屏", "水边的花"),
]:
    expected = exported[f"apps/mobile/assets/media/flower-{orientation}.mp4"]
    assert first_media[f"videos/{folder}/{title}.mp4"] == expected
assert read(HERE / "before/media-before.json") == first_media
assert read(HERE / "before/media-after.json") == first_media
assert "All tests passed!" in (HERE / "checks/targeted.log").read_text()
assert "+16: All tests passed!" in (HERE / "checks/targeted.log").read_text()
assert "No issues found!" in (HERE / "checks/analyze.log").read_text()
assert "All checks passed!" in (HERE / "checks/ruff.log").read_text()
assert len(read(HERE / "comparison/normalization.json")) == 8
print(
    json.dumps(
        {
            "verified": True,
            "source": git("rev-parse", SOURCE),
            "prototype": PROTO,
            "inputs": len(manifest),
            "native_screens": 40,
            "targeted_checks": 16,
            "source_files": len(sources[0]),
            "windows": windows,
            "scope": "shared geometry only; full LF8 remains open",
        },
        ensure_ascii=False,
        indent=2,
    )
)

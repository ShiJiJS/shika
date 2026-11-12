"""The distributed tagging Skill works without adjacent personal Skills."""

import hashlib
import importlib.util
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SKILL = ROOT / "skills/video-tagging"


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


@pytest.fixture
def standalone(tmp_path):
    copied = tmp_path / "different agent" / "video-tagging"
    shutil.copytree(SKILL, copied, ignore=shutil.ignore_patterns("__pycache__"))
    cfg = tmp_path / "private config.json"
    cfg.write_text((copied / "assets/config.json").read_text())
    return copied, cfg


def test_moved_skill_uses_bundled_extractor_and_preserves_explicit_override(standalone):
    copied, cfg = standalone
    infer = module("standalone_tagging_infer", copied / "scripts/infer.py")
    assert Path(infer.load_config(cfg)["extractor"]) == copied / "scripts/extract_keyframes.py"
    assert not (copied.parent / "video-understanding").exists()
    override = cfg.parent / "custom extractor.py"
    override.write_text("# existing user adapter\n")
    cfg.write_text(json.dumps({"extractor": override.name}))
    assert Path(infer.load_config(cfg)["extractor"]) == override


@pytest.fixture
def video(tmp_path):
    if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        pytest.skip("Install FFmpeg to run actual frame extraction checks")
    path = tmp_path / "合成视频 with spaces.mp4"
    subprocess.run(
        [
            "ffmpeg",
            "-nostdin",
            "-v",
            "error",
            "-f",
            "lavfi",
            "-i",
            "testsrc2=size=128x72:rate=10:duration=2",
            "-c:v",
            "mpeg4",
            "-threads",
            "1",
            str(path),
        ],
        check=True,
        timeout=30,
        capture_output=True,
    )
    return path


def test_real_extraction_is_bounded_paged_read_only_and_refuses_overwrite(
    standalone,
    video,
    tmp_path,
):
    copied, _ = standalone
    tool = copied / "scripts/extract_keyframes.py"
    original = hashlib.sha256(video.read_bytes()).hexdigest()
    output = tmp_path / "outputs with spaces"
    command = [
        sys.executable,
        str(tool),
        str(video),
        "-o",
        str(output),
        "--interval",
        "0.2",
        "--max-frames",
        "5",
        "--cols",
        "1",
        "--sheet-max-cells",
        "2",
        "--sheet-width",
        "640",
        "-q",
        "--json",
    ]
    result = subprocess.run(
        command, cwd=tmp_path, capture_output=True, text=True, timeout=60, check=False
    )
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) == {"status": "ready", "frames": 5, "overviews": 3}
    assert video.name not in result.stdout + result.stderr
    meta = json.loads((output / "keyframes.json").read_text())
    assert meta["sampling"] == "uniform"
    assert [row["time"] for row in meta["frames"]] == sorted(row["time"] for row in meta["frames"])
    assert meta["frames"][-1]["time"] >= 1.5
    for path in [row["path"] for row in meta["frames"]] + meta["overviews"]:
        with Image.open(path) as image:
            image.verify()
    assert hashlib.sha256(video.read_bytes()).hexdigest() == original
    before = {p.name: p.read_bytes() for p in output.iterdir()}
    repeated = subprocess.run(command, capture_output=True, text=True, timeout=15, check=False)
    assert repeated.returncode == 1
    assert {p.name: p.read_bytes() for p in output.iterdir()} == before
    assert not list(output.parent.glob(".shika-keyframes-*"))


def test_real_preparation_from_moved_skill_uses_no_external_skill(standalone, video, tmp_path):
    copied, cfg = standalone
    infer = module("moved_tagging_infer", copied / "scripts/infer.py")
    config = infer.load_config(cfg)
    folder, task = infer.task_for(
        {"video_id": "V000001", "source_path": str(video)},
        config,
        "Fixture prompt",
        tmp_path / "private runs",
        "prepare",
    )
    assert Path(task["config"]["extractor"]).is_relative_to(copied)
    assert task["frames"] and task["overviews"]
    assert (folder / "task.json").is_file()
    second_folder, second_task = infer.task_for(
        {"video_id": "V000001", "source_path": str(video)},
        config,
        "Fixture prompt",
        tmp_path / "private runs",
        "prepare",
    )
    assert (second_folder, second_task) == (folder, task)


def test_invalid_video_does_not_publish_partial_output(standalone, tmp_path):
    copied, _ = standalone
    tool = module("invalid_tagging_extract", copied / "scripts/extract_keyframes.py")
    source = tmp_path / "broken.mp4"
    source.write_bytes(b"not a video")
    output = tmp_path / "failed frames"
    if not shutil.which("ffprobe") or not shutil.which("ffmpeg"):
        pytest.skip("FFmpeg required")
    with pytest.raises(subprocess.CalledProcessError):
        tool.extract(source, output)
    assert not output.exists()

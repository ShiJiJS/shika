"""Decoder limits are enforced by real subprocesses, independent of HTTP."""

import subprocess
import sys
import threading

from PIL import Image

from shika.images import inspect_image

from .test_packs import image, large_png


def test_probe_timeout_and_stop_reap_decoder_and_remove_partial_cache(tmp_path, monkeypatch):
    source = tmp_path / "source.png"
    image(source)
    spawned = []
    original = subprocess.Popen

    def tracked(*args, **kwargs):
        child = original(*args, **kwargs)
        spawned.append(child)
        return child

    monkeypatch.setattr("shika.images.subprocess.Popen", tracked)
    with source.open("rb") as source_file:
        result = inspect_image(source_file.fileno(), tmp_path / "cache", 0.001, threading.Event())
        assert result["error"] == "image_probe_timeout"
    assert spawned and all(child.poll() is not None for child in spawned)
    assert list((tmp_path / "cache").iterdir()) == []
    stopped = threading.Event()
    stopped.set()
    import pytest

    with source.open("rb") as source_file, pytest.raises(InterruptedError):
        inspect_image(source_file.fileno(), tmp_path / "cache", 20, stopped)
    assert all(child.poll() is not None for child in spawned)


def test_source_beyond_old_pixel_ceiling_is_kept_without_decoding_a_full_frame(tmp_path):
    source = tmp_path / "576-megapixels.png"
    large_png(source, (24000, 24000))
    with source.open("rb") as file:
        result = inspect_image(file.fileno(), tmp_path / "cache", 20, threading.Event())
    assert not result.get("error"), result
    assert (result["width"], result["height"]) == (24000, 24000)
    assert result["thumbnail_warning"] == "thumbnail_resource_limit"
    assert not list((tmp_path / "cache").iterdir())


def test_timeout_or_crash_after_header_keeps_original_and_removes_partial_preview(
    tmp_path, monkeypatch
):
    import json

    source = tmp_path / "source.png"
    image(source)
    original = subprocess.Popen
    for fail in ("timeout", "crash"):
        children = []

        def worker(args, fail=fail, children=children, **kwargs):
            code = (
                "import json,os,sys,time; from pathlib import Path; "
                "from PIL import Image; "
                "im=Image.open(os.fdopen(os.dup(int(sys.argv[1])), 'rb')); "
                "print(json.dumps({'metadata': {'width':im.width,'height':im.height,'format':im.format}}),flush=True); "
                "Path(sys.argv[2]).write_bytes(b'partial'); "
                + ("time.sleep(60)" if fail == "timeout" else "print('{',flush=True); os._exit(1)")
            )
            child = original([sys.executable, "-c", code, *args[-2:]], **kwargs)
            children.append(child)
            return child

        monkeypatch.setattr("shika.images.subprocess.Popen", worker)
        with source.open("rb") as file:
            result = inspect_image(file.fileno(), tmp_path / "cache", 1, threading.Event())
        assert not result.get("error"), json.dumps(result)
        assert (result["width"], result["height"]) == (40, 60)
        assert result["thumbnail_warning"] == (
            "thumbnail_timeout" if fail == "timeout" else "thumbnail_resource_limit"
        )
        assert all(child.poll() is not None for child in children)
        assert not list((tmp_path / "cache").iterdir())


def test_confirmed_decode_error_does_not_fall_back_to_a_valid_header(tmp_path):
    source = tmp_path / "truncated.jpg"
    image(source, size=(256, 256))
    source.write_bytes(source.read_bytes()[:-50])
    with source.open("rb") as file:
        result = inspect_image(file.fileno(), tmp_path / "cache", 20, threading.Event())
    assert result["error"] == "invalid_image"
    assert not list((tmp_path / "cache").iterdir())


def test_large_jpeg_uses_decoder_downsampling_and_keeps_original_dimensions(tmp_path):
    source = tmp_path / "101-megapixels.jpg"
    # Generate the source outside pytest: the decoder's inherited high-water
    # RSS must not include the test fixture's full-size image allocation.
    subprocess.run(
        [
            sys.executable,
            "-c",
            "from PIL import Image; import sys; "
            "Image.new('RGB', (11648, 8736), 'blue').save(sys.argv[1], 'JPEG', quality=70)",
            str(source),
        ],
        check=True,
        timeout=20,
    )
    with source.open("rb") as file:
        result = inspect_image(file.fileno(), tmp_path / "cache", 20, threading.Event())
    assert not result.get("error"), result
    assert (result["width"], result["height"]) == (11648, 8736)
    with Image.open(tmp_path / "cache" / result["thumbnail"]) as preview:
        assert preview.width <= 512 and preview.height <= 768

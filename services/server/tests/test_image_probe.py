"""Decoder limits are enforced by real subprocesses, independent of HTTP."""

import struct
import subprocess
import sys
import threading
import zlib

from PIL import Image

from shika.images import inspect_image

from .test_packs import image


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


def test_pixel_limit_rejects_header_before_allocating_full_image(tmp_path):
    def chunk(kind, value):
        return (
            struct.pack(">I", len(value))
            + kind
            + value
            + struct.pack(">I", zlib.crc32(kind + value))
        )

    source = tmp_path / "oversized.png"
    source.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", 10000, 10000, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(b"\0"))
        + chunk(b"IEND", b"")
    )
    with source.open("rb") as file:
        result = inspect_image(file.fileno(), tmp_path / "cache", 20, threading.Event())
    assert result["error"] == "image_too_large"
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

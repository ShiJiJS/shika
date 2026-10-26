"""Normalize system regions only; retain original columns and content."""

import json
from pathlib import Path

from PIL import Image, ImageChops

HERE = Path(__file__).resolve().parent
out = HERE / "comparison"
out.mkdir(exist_ok=True)
m = json.loads((HERE / "normal-1/metrics.json").read_text())[0]
assert m["state"] == "video-order-library" and m["library_ready"]
assert m["size"] == [390, 905] and m["viewPadding"] == [0, 49, 0, 24]
native = Image.open(HERE / "normal-1/video-order-library.png").convert("RGB")
native = native.crop((0, 147, 1170, 2643)).resize((390, 832), Image.Resampling.LANCZOS)
reference = Image.open(HERE / "reference/video.png").convert("RGB")
assert reference.size == (390, 844)
reference = reference.crop((0, 0, 390, 832))
pair = Image.new("RGB", (780, 832))
pair.paste(reference, (0, 0))
pair.paste(native, (390, 0))
pair.save(out / "paired.png")
Image.blend(reference, native, .5).save(out / "overlay.png")
ImageChops.difference(reference, native).save(out / "difference.png")
(out / "normalization.json").write_text(json.dumps({
    "content": [390, 832], "native_top_removed": 49, "native_bottom_removed": 24,
    "reference_bottom_removed": 12, "native_dpr": 3, "reference_dpr": 1,
    "state": "cold ready video library, no viewing round, name order, no saved history",
    "known_differences": "Native filenames retain .mp4 and actual ceil duration 00:06; reference titles omit extensions and use 0:05. Scrollbar width, icon shapes and some tag ordering differ. No whole-page equality claim.",
}, indent=2) + "\n")

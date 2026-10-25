"""Rebuild the same-state comparison without stretching or rearranging content."""

import json
from pathlib import Path

from PIL import Image, ImageChops

HERE = Path(__file__).resolve().parent
OUT = HERE / "comparison"
OUT.mkdir(exist_ok=True)
run = HERE / "normal-1"
m = next(
    m for m in json.loads((run / "metrics.json").read_text()) if m["state"] == "continue-library"
)
image = Image.open(run / "continue-library.png").convert("RGB")
dpr, (width, height) = m["dpr"], m["size"]
left, top, right, bottom = m["viewPadding"]
box = [left * dpr, top * dpr, (width - right) * dpr, (height - bottom) * dpr]
size = (round(width - left - right), round(height - top - bottom))
assert size == (390, 832)
native = image.crop(tuple(round(v) for v in box)).resize(size, Image.Resampling.LANCZOS)
reference = Image.open(HERE / "reference/continued.png").convert("RGB")
assert reference.size == (390, 844)
reference = reference.crop((0, 0, 390, 832))
native.save(OUT / "native-content.png")
reference.save(OUT / "reference-content.png")
pair = Image.new("RGB", (780, 832))
pair.paste(reference, (0, 0))
pair.paste(native, (390, 0))
pair.save(OUT / "paired.png")
Image.blend(reference, native, .5).save(OUT / "overlay.png")
ImageChops.difference(reference, native).save(OUT / "difference.png")
(OUT / "normalization.json").write_text(
    json.dumps({"native_box_px": box, "content": size, "reference_bottom_removed": 12}, indent=2)
    + "\n"
)

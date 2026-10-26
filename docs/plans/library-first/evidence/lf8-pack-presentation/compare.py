"""Same cold-library content comparison, without column shifts or stretching."""

import json
from pathlib import Path

from PIL import Image, ImageChops

HERE = Path(__file__).resolve().parent
out = HERE / "comparison"
out.mkdir(exist_ok=True)
m = json.loads((HERE / "normal-1/metrics.json").read_text())[0]
assert m["size"] == [390, 905] and m["viewPadding"] == [0, 49, 0, 24]
native = Image.open(HERE / "normal-1/presentation-library.png").convert("RGB")
native = native.crop((0, 49 * 3, 390 * 3, (905 - 24) * 3)).resize((390, 832), Image.Resampling.LANCZOS)
reference = Image.open(HERE / "reference/packs.png").convert("RGB")
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
    "known_differences": "desktop reference scrollbar narrows columns; tag text 11 vs 12dp/1.6 and 4dp top gap remain in RESULTS; no whole-page equality claim",
}, indent=2) + "\n")

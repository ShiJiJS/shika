"""Compare only the affected 147dp header; requires Pillow."""

import json
from pathlib import Path

from PIL import Image, ImageChops

HERE = Path(__file__).resolve().parent
out = HERE / "comparison"
out.mkdir(exist_ok=True)
metrics = json.loads((HERE / "normal-1/metrics.json").read_text())
for state, reference in [("counts-home", "home"), ("counts-packs", "packs")]:
    m = next(m for m in metrics if m["state"] == state)
    dpr = m["dpr"]
    assert m["size"] == [390, 905] and m["viewPadding"] == [0, 49, 0, 24]
    native = Image.open(HERE / "normal-1" / (state + ".png")).convert("RGB")
    native = native.crop((0, 49 * dpr, 390 * dpr, (49 + 147) * dpr))
    native = native.resize((390, 147), Image.Resampling.LANCZOS)
    ref = Image.open(HERE / "reference" / (reference + ".png")).convert("RGB")
    assert ref.size == (390, 844)
    ref = ref.crop((0, 0, 390, 147))
    pair = Image.new("RGB", (780, 147))
    pair.paste(ref, (0, 0))
    pair.paste(native, (390, 0))
    pair.save(out / (reference + "-paired.png"))
    Image.blend(ref, native, .5).save(out / (reference + "-overlay.png"))
    ImageChops.difference(ref, native).save(out / (reference + "-difference.png"))
(out / "normalization.json").write_text(json.dumps({
    "region": [0, 0, 390, 147], "native_top_removed_dp": 49,
    "native_dpr": 3, "reference_dpr": 1,
    "scope": "header only; body/history/order is not a same-state comparison",
}, indent=2) + "\n")

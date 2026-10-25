"""Normalize actual native pixels using recorded safe areas, then compare."""

import json
from pathlib import Path

from PIL import Image, ImageChops, ImageEnhance

HERE = Path(__file__).resolve().parent
out = HERE / "comparison"
out.mkdir(exist_ok=False)
metrics = json.loads((HERE / "normal-1/metrics.json").read_text())
report = []
for m in metrics:
    name = m["state"]
    dpr = m["dpr"]
    left, top, right, bottom = m["viewPadding"]
    width, height = m["size"]
    assert [width, height] == [390, 905] and dpr == 3
    native = Image.open(HERE / "normal-1" / (name + ".png")).convert("RGB")
    assert native.size == (1170, 2715)
    native = native.crop(
        (
            round(left * dpr),
            round(top * dpr),
            round((width - right) * dpr),
            round((height - bottom) * dpr),
        )
    )
    native = native.resize(
        (round(width - left - right), round(height - top - bottom)),
        Image.Resampling.LANCZOS,
    )
    reference = Image.open(HERE / "reference" / (name + ".png")).convert("RGB")
    assert reference.size == (390, 844) and native.size == (390, 832)
    reference = reference.crop((0, 0, 390, 832))
    native.save(out / (name + "-native.png"))
    reference.save(out / (name + "-reference.png"))
    sheet = Image.new("RGB", (780, 832), "white")
    sheet.paste(reference)
    sheet.paste(native, (390, 0))
    sheet.save(out / (name + "-compare.png"))
    Image.blend(reference, native, 0.5).save(out / (name + "-overlay.png"))
    ImageEnhance.Contrast(ImageChops.difference(reference, native)).enhance(3).save(
        out / (name + "-difference.png")
    )
    report.append(
        {
            "state": name,
            "native_source": [1170, 2715],
            "dpr": dpr,
            "native_safe_area": [left, top, right, bottom],
            "reference_bottom_removed": 12,
            "content": [390, 832],
            "stretch": False,
        }
    )
(out / "normalization.json").write_text(json.dumps(report, indent=2) + "\n")

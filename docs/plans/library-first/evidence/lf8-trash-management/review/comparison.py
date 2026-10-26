"""Produce DPR-normalized QA comparisons without moving individual elements."""

import json
from pathlib import Path

from PIL import Image, ImageDraw

evidence = Path(__file__).resolve().parents[1]
records = []
for profile in ["normal", "large", "landscape"]:
    folder = evidence / profile
    lines = (folder / "lf8-trash-android-test.log").read_text().splitlines()
    metrics = [json.loads(s.split("TRASH_METRICS:", 1)[1])
               for s in lines if "TRASH_METRICS:" in s]
    for state in ["video", "packs", "unknown", "single-confirm"]:
        m = next(m for m in metrics if m["state"] == f"trash-{state}")
        raw = Image.open(folder / f"lf8-trash-trash-{state}.png").convert("RGB")
        d = m["dpr"]
        top, bottom = m["viewPadding"][1], m["viewPadding"][3]
        native = raw.crop((0, round(top * d), raw.width, raw.height - round(bottom * d)))
        native = native.resize((round(native.width / d), round(native.height / d)), Image.Resampling.LANCZOS)
        native.save(evidence / "review" / f"{profile}-{state}-logical.png")
        records.append({"profile": profile, "state": state, "dpr": d,
                        "safe_top": top, "safe_bottom": bottom,
                        "size": list(native.size), "source": str(folder.relative_to(evidence))})
        if profile != "normal" or state not in ["video", "packs"]:
            continue
        ref = Image.open(evidence / "reference" / ("video-390.png" if state == "video" else "pack-390.png")).convert("RGB")
        sheet = Image.new("RGB", (ref.width + native.width + 16, max(ref.height, native.height) + 28), "#dddeda")
        draw = ImageDraw.Draw(sheet)
        sheet.paste(ref, (0, 28))
        sheet.paste(native, (ref.width + 16, 28))
        draw.text((8, 8), "Frozen browser reference", fill="black")
        draw.text((ref.width + 24, 8), "Native safe area; real catalog", fill="black")
        sheet.save(evidence / "review" / f"normal-{state}-comparison.png")
(evidence / "review/normalization.json").write_text(json.dumps({
    "method": "Crop actual native safe area; proportional DPR downsample; neutral padding. No element movement or stretching.",
    "records": records,
}, indent=2) + "\n")

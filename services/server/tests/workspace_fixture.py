"""Public flower samples for the isolated native library UI, never production."""

from PIL import Image, ImageDraw


def seed_workspace_packs(base, assets):
    destination = base / "shorts" / "图包"
    # Exactly the directory below the fixture's hard-coded /media mount.
    if str(destination) != "/media/shorts/图包":
        raise RuntimeError("Unexpected native workspace fixture path")
    with Image.open(assets / "flower-portrait.jpg") as source:
        cover = source.convert("RGB").resize((240, 360))
    for index in range(1, 28):
        folder = destination / f"图包{index:02d}"
        folder.mkdir(parents=True, exist_ok=True)
        for page in (1, 2, 10):
            target = folder / f"{page}.jpg"
            if target.exists():
                continue
            image = cover.copy()
            drawing = ImageDraw.Draw(image)
            drawing.rectangle((0, 0, 240, 26), fill=(32, 38, 31))
            drawing.text((8, 7), f"PACK {index:02d} / PAGE {page}", fill="white")
            image.save(target, quality=85)
    return {"path": str(destination), "pack_count": 27, "page_count": 81}

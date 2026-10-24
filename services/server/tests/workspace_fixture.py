"""Public flower samples for the isolated native library UI, never production."""

from PIL import Image, ImageDraw


def seed_workspace_packs(base, assets, count=27):
    destination = base / "shorts" / "图包"
    # Exactly the directory below the fixture's hard-coded /media mount.
    if str(destination) != "/media/shorts/图包":
        raise RuntimeError("Unexpected native workspace fixture path")
    with Image.open(assets / "flower-portrait.jpg") as source:
        cover = source.convert("RGB").resize((240, 360))
    if count not in (27, 73):
        raise RuntimeError("Unexpected native workspace pack count")
    for index in range(1, count + 1):
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
    return {"path": str(destination), "pack_count": count, "page_count": count * 3}


def prepend_workspace_pack(base, assets):
    destination = base / "shorts" / "图包" / "000新增图包"
    if str(destination) != "/media/shorts/图包/000新增图包":
        raise RuntimeError("Unexpected native prepend path")
    destination.mkdir(parents=True, exist_ok=True)
    with Image.open(assets / "flower-portrait.jpg") as source:
        source.convert("RGB").resize((240, 360)).save(destination / "1.jpg", quality=85)
    return {"path": str(destination)}

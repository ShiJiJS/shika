"""Public flower samples for the isolated native library UI, never production."""

from PIL import Image, ImageDraw
from sqlalchemy import func, select

from shika.models import ImagePack, PackPage, PackProgress, RecentEntry, Root


def seed_workspace_packs(base, assets, count=27):
    destination = base / "shorts" / "图包"
    # Exactly the directory below the fixture's hard-coded /media mount.
    if str(destination) != "/media/shorts/图包":
        raise RuntimeError("Unexpected native workspace fixture path")
    with Image.open(assets / "flower-portrait.jpg") as source:
        cover = source.convert("RGB").resize((240, 360))
    if count not in (27, 73, 1003):
        raise RuntimeError("Unexpected native workspace pack count")
    for index in range(1, count + 1):
        folder = destination / f"图包{index:02d}"
        folder.mkdir(parents=True, exist_ok=True)
        if count == 1003:
            (folder / "notes.txt").write_text(
                f"retain fixture attachment {index}", encoding="utf-8"
            )
        for page in (1,) if count == 1003 else (1, 2, 10):
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


def seed_recent_pack_history(db):
    """Past-reading fixture, distinct from frames opened by the current UI run."""
    with db.write() as session:
        root = session.scalar(
            select(Root).where(Root.kind == "pack", Root.path == "/media/shorts/图包")
        )
        if root is None or session.scalar(
            select(func.count()).select_from(RecentEntry).where(RecentEntry.kind == "pack")
        ):
            raise RuntimeError("Expected freshly scanned isolated pack root without history")
        packs = session.scalars(
            select(ImagePack).where(ImagePack.root_id == root.id).order_by(ImagePack.name)
        ).all()
        if len(packs) != 73:
            raise RuntimeError("Expected 73 disposable fixture packs")
        selected = packs[:27]
        for index, pack in enumerate(selected):
            pages = session.scalars(
                select(PackPage)
                .where(PackPage.pack_id == pack.id)
                .order_by(PackPage.ordinal, PackPage.id)
            ).all()
            if len(pages) != 3:
                raise RuntimeError("Expected three public sample pages")
            session.add(RecentEntry(kind="pack", pack_id=pack.id, opened_at=1000 + index))
            session.add(
                PackProgress(
                    pack_id=pack.id,
                    page_id=pages[1].id,
                    content_version=pack.content_version,
                    offset_ratio=0.25,
                    revision=1,
                    updated_at=1000 + index,
                )
            )
        return {"historical_ids": [pack.id for pack in selected], "total": 27}

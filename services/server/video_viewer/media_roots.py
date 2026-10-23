"""Configured root policies apply even before the next background scan."""

from pathlib import Path

from sqlalchemy import case, false, or_, select

from .models import Root
from .paths import beneath


def owner_for_path(path, roots, kind="video"):
    owners = []
    for root in sorted(roots, key=lambda r: len(r.path)):
        if not root.mount_id or not beneath(Path(path), Path(root.path)):
            continue
        if not root.enabled or root.kind != kind:
            owners = []
        else:
            owners.append(root)
    return owners[0] if owners else None


def enabled_path(session, column, kind="video"):
    roots = list(session.scalars(select(Root).order_by(Root.path)))
    clauses = [
        (
            or_(column == root.path, column.startswith(root.path + "/", autoescape=True)),
            bool(root.mount_id and root.enabled and root.kind == kind),
        )
        for root in sorted(roots, key=lambda r: len(r.path), reverse=True)
    ]
    return case(*clauses, else_=False) if clauses else false()

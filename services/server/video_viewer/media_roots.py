"""Configured root policies apply even before the next background scan."""

from pathlib import Path

from sqlalchemy import case, false, literal, or_, select

from .models import Root
from .paths import beneath


def owner_for_path(path, roots, kind="video"):
    owners = []
    for root in sorted(roots, key=lambda r: len(r.path)):
        if not beneath(Path(path), Path(root.path)):
            continue
        if not root.mount_id or not root.enabled or root.kind != kind:
            owners = []
        else:
            owners.append(root)
    return (owners[-1] if kind == "pack" else owners[0]) if owners else None


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


def path_owner(session, column, kind="pack"):
    """SQL counterpart of owner_for_path, including type/disabled barriers."""
    roots = list(session.scalars(select(Root)))
    clauses = []
    for root in sorted(roots, key=lambda root: len(root.path), reverse=True):
        owner = owner_for_path(root.path, roots, kind)
        clauses.append(
            (
                or_(column == root.path, column.startswith(root.path + "/", autoescape=True)),
                owner.id if owner else None,
            )
        )
    return case(*clauses, else_=None) if clauses else literal(None)


def owned_path(session, column, root_id, kind="pack"):
    """Pack uses its nearest root; video retains its outermost unblocked root."""
    return path_owner(session, column, kind) == root_id

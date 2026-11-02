"""Prepare a complete replacement graph against local, read-only media truth.

All changes are to a private copy. This module cannot commit the active library
or execute an imported task. Original graphs remain available for history.
"""

import hashlib
import os
import sqlite3
from contextlib import closing
from pathlib import Path

from sqlalchemy import create_engine, delete, func, select, update

from .backup_archive import ArchiveGraph, _check, _private_file, _readonly, file_hash
from .backup_reconcile import mapped_path, mappings_for
from .backup_v2_schema import TABLE_MAP, mounts_from, settings_from, validate_graph
from .directory_identity import directory_stamp
from .errors import LibraryError
from .media_roots import owner_for_path
from .models import Root, uid
from .paths import excluded, open_directory, open_regular, signature, validate_path


def _rows(connection, table, condition=None):
    statement = select(table).order_by(*table.primary_key.columns)
    if condition is not None:
        statement = statement.where(condition)
    result = connection.execute(statement).mappings()
    while batch := result.fetchmany(100):
        yield from batch


def _one(connection, name, identity):
    table = TABLE_MAP[name]
    return connection.execute(select(table).where(table.c.id == identity)).mappings().first()


def _parents(target, path, root):
    """Keep a locally renamed item's directory navigation reachable."""
    directory = Path(path).parent
    base = Path(root.path)
    if not directory.is_relative_to(base):
        return
    table = TABLE_MAP["directories"]
    while directory != base:
        if target.scalar(select(table.c.id).where(table.c.path == str(directory))) is None:
            target.execute(
                table.insert().values(
                    id=uid(),
                    root_id=root.id,
                    path=str(directory),
                    name=directory.name,
                    seen_scan=None,
                )
            )
        directory = directory.parent


def _verify(path, expected_hash, expected_size, settings, check, *, trash=None):
    if not expected_hash or trash is None and excluded(Path(path), settings.data_dir):
        return None
    try:
        if trash is None:
            validate_path(path, settings.mounts)
        else:
            validate_path(trash["root_path"], settings.mounts)
            expected = (
                (settings.trash_dir or Path(trash["root_path"]) / ".video-viewer-trash")
                / trash["id"]
                / Path(trash["original_path"]).name
            )
            if Path(path) != expected:
                return None
        with open_regular(Path(path)) as fd:
            before = signature(os.fstat(fd))
            if before[2] != expected_size:
                return None
            digest = hashlib.sha256()
            while chunk := os.read(fd, 1024 * 1024):
                _check(check)
                digest.update(chunk)
            if signature(os.fstat(fd)) != before or digest.hexdigest() != expected_hash:
                return None
        with open_regular(Path(path)) as fd:
            return before if signature(os.fstat(fd)) == before else None
    except OSError:
        return None
    except LibraryError as error:
        if error.code in {
            "invalid_path",
            "path_outside_mounts",
            "symlink_not_allowed",
            "not_regular_file",
        }:
            return None
        raise


def prepare_graph(imported, current, destination, mapping, settings, *, check=None):
    """Return a private reconciled library, plus scalar results.

    Staged graphs and local current snapshots have already been fully validated.
    The caller must keep its maintenance reservation through final replacement.
    Rows are processed in bounded windows; a single existing JSON record retains
    the archive codec's explicit record-size bound.
    """
    destination = Path(destination)
    if imported.digest and file_hash(imported.database) != imported.digest:
        raise LibraryError("backup_artifact_changed", "导入图在恢复前发生变化", 409)
    _private_file(destination)
    try:
        with closing(sqlite3.connect(imported.database.as_uri() + "?mode=ro", uri=True)) as source:
            with closing(sqlite3.connect(destination)) as target:
                source.backup(target, pages=256, progress=lambda *_: _check(check))
        source_engine, current_engine = _readonly(imported.database), _readonly(current.database)
        target_engine = create_engine(f"sqlite:///{destination}")
        try:
            with (
                source_engine.connect() as source,
                current_engine.connect() as local,
                target_engine.begin() as target,
            ):
                target.exec_driver_sql("PRAGMA foreign_keys=ON")
                if source.scalar(select(func.count()).select_from(TABLE_MAP["roots"])) > 256:
                    raise LibraryError("invalid_mapping", "媒体目录数量超出映射限制", 422)
                old_roots = {r["id"]: dict(r) for r in _rows(source, TABLE_MAP["roots"])}
                mappings = mappings_for(
                    {"tables": {"roots": list(old_roots.values())}}, mapping, settings
                )
                effective_paths = [
                    mappings[rid][0] if mappings[rid] else old["path"]
                    for rid, old in old_roots.items()
                ]
                if len(effective_paths) != len(set(effective_paths)):
                    raise LibraryError("invalid_mapping", "映射后目录相互冲突", 422)
                roots = {}
                target.execute(
                    update(TABLE_MAP["roots"]).values(
                        path="/.vv-restore-root/" + TABLE_MAP["roots"].c.id
                    )
                )
                for identity, old in old_roots.items():
                    _check(check)
                    root = dict(old)
                    root.update(available=False, last_scan=None, error="root_unmapped")
                    value = mappings[identity]
                    if value is None:
                        root.update(enabled=False, mount_id="")
                    else:
                        root.update(path=value[0], mount_id=value[1], error="root_unavailable")
                        try:
                            with open_directory(Path(root["path"])) as fd:
                                os.listdir(fd)
                            root.update(available=True, error=None)
                        except OSError:
                            pass
                    roots[identity] = Root(**root)
                    target.execute(
                        update(TABLE_MAP["roots"])
                        .where(TABLE_MAP["roots"].c.id == identity)
                        .values(**root)
                    )
                effective = [root.path for root in roots.values()]
                if len(effective) != len(set(effective)):
                    raise LibraryError("invalid_mapping", "映射后目录相互冲突", 422)
                directories = TABLE_MAP["directories"]
                target.execute(
                    update(directories).values(path="/.vv-restore-directory/" + directories.c.id)
                )
                for row in _rows(source, directories):
                    root = roots[row["root_id"]]
                    path = (
                        mapped_path(row["path"], old_roots[root.id]["path"], root.path)
                        if mappings[root.id]
                        else row["path"]
                    )
                    if path is None:
                        raise LibraryError("invalid_backup", "目录不在原根内", 422)
                    target.execute(
                        update(directories)
                        .where(directories.c.id == row["id"])
                        .values(path=path, seen_scan=None)
                    )
                for root in roots.values():
                    if (
                        target.scalar(
                            select(directories.c.id).where(directories.c.path == root.path)
                        )
                        is None
                    ):
                        target.execute(
                            directories.insert().values(
                                id=uid(),
                                root_id=root.id,
                                path=root.path,
                                name=Path(root.path).name,
                                seen_scan=None,
                            )
                        )
                # Never import machine-specific scan/authorization evidence.
                for name in ("videos", "packs"):
                    target.execute(update(TABLE_MAP[name]).values(location_key=None))
                _videos(source, local, target, old_roots, roots, mappings, settings, check)
                _packs(source, local, target, old_roots, roots, mappings, settings, check)
                for name in (
                    "file_operations",
                    "pack_file_operations",
                    "pack_restore_plans",
                    "pack_purge_plans",
                    "pack_missing_cleanups",
                ):
                    target.execute(update(TABLE_MAP[name]).values(historical=True))
                # Exact original status/error remains in the immutable source
                # history. The active projection is explicitly non-executable.
                target.execute(
                    update(TABLE_MAP["tasks"])
                    .where(TABLE_MAP["tasks"].c.status.in_(("queued", "running")))
                    .values(status="interrupted", phase="historical")
                )
                target.execute(update(TABLE_MAP["tasks"]).values(error="restored_history"))
                values = settings_from(target)
                values["last_delete_operation"] = None
                values["active_pack_opened"] = None
                from .models import Setting

                for key in ("last_delete_operation", "active_pack_opened"):
                    target.execute(delete(Setting).where(Setting.key == key))
                validate_graph(target, values)
                counts = {
                    name: target.scalar(select(func.count()).select_from(TABLE_MAP[name]))
                    for name in TABLE_MAP
                }
            with closing(sqlite3.connect(destination)) as connection:
                connection.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            return ArchiveGraph(
                "library", "library", destination, mounts_from(settings), file_hash(destination)
            ), counts
        finally:
            source_engine.dispose()
            current_engine.dispose()
            target_engine.dispose()
    except BaseException:
        destination.unlink(missing_ok=True)
        raise


def _anchor(local, target, name, identity, check, visiting=None):
    """Retain exact real provenance parents required by a current trash mark.

    Full original steps/members stay in the immutable current history graph;
    active anchors do not pull unrelated media into the restored collection.
    Their original task must be routed through that history by the coordinator.
    """
    if _one(target, name, identity):
        return
    visiting = set() if visiting is None else visiting
    if identity in visiting:
        raise LibraryError("invalid_backup", "操作父关联形成循环", 422)
    visiting.add(identity)
    _check(check)
    row = _one(local, name, identity)
    task = _one(local, "tasks", identity)
    if row is None or task is None:
        raise LibraryError("invalid_backup", "当前回收标记缺少操作父记录", 422)
    if row["undo_of"]:
        _anchor(local, target, name, row["undo_of"], check, visiting)
    if not _one(target, "tasks", identity):
        target.execute(TABLE_MAP["tasks"].insert().values(**dict(task)))
    target.execute(TABLE_MAP[name].insert().values(**{**dict(row), "historical": True}))
    visiting.remove(identity)


def _mark(source, local, target, name, identity, path, root, check, settings, known):
    table = TABLE_MAP[name]
    condition = (
        table.c.video_id == identity if name == "trash_items" else table.c.pack_id == identity
    )
    current = (
        local.execute(select(table).where(condition, table.c.status == "active")).mappings().first()
    )
    imported = (
        source.execute(select(table).where(condition, table.c.status == "active"))
        .mappings()
        .first()
    )
    # A locally completed restore is newer physical/management truth. Retire
    # an imported active mark instead of resurrecting it from an older backup.
    if current is None and known is not None and known["status"] == "available":
        target.execute(
            update(table).where(condition, table.c.status == "active").values(status="restored")
        )
        return False
    value = current if current is not None else imported
    if value is None:
        return False
    value = dict(value)
    # Legacy physically moved video trash is checked separately, never moved.
    logical = name != "trash_items" or value["trash_path"] == value["original_path"]
    value.update(root_path=root.path, original_path=path)
    if not logical:
        value["trash_path"] = str(
            (settings.trash_dir or Path(root.path) / ".video-viewer-trash")
            / value["id"]
            / Path(path).name
        )
    if name == "trash_items" and logical:
        value["trash_path"] = path
    target.execute(
        update(table).where(condition, table.c.status == "active").values(status="restored")
    )
    if current is not None:
        _anchor(
            local,
            target,
            "file_operations" if name == "trash_items" else "pack_file_operations",
            value["operation_id"],
            check,
        )
    existing = _one(target, name, value["id"])
    if existing:
        target.execute(update(table).where(table.c.id == value["id"]).values(**value))
    else:
        target.execute(table.insert().values(**value))
    return True if logical else value


def _videos(source, local, target, old_roots, roots, mappings, settings, check):
    table = TABLE_MAP["videos"]
    for row in _rows(source, table):
        _check(check)
        root, known = roots[row["root_id"]], _one(local, "videos", row["id"])
        path = (
            mapped_path(row["path"], old_roots[root.id]["path"], root.path)
            if mappings[root.id]
            else None
        )
        if (
            mappings[row["root_id"]]
            and root.enabled
            and known
            and known["status"] in ("available", "trash")
            and known["sha256"] == row["sha256"]
        ):
            actual_owner = owner_for_path(known["path"], roots.values(), "video")
            if actual_owner and actual_owner.available:
                root, path = actual_owner, known["path"]
        value = dict(row)
        value.update(
            path=path or row["path"],
            root_id=root.id,
            generation=max(row["generation"], known["generation"] if known else 0) + 1,
            device="",
            inode="",
            mtime_ns="",
            ctime_ns="",
            seen_scan="",
            thumbnail=None,
            location_key=None,
            status="missing",
            error="root_unmapped" if not path else "source_missing",
        )
        terminal = (
            row["status"] in ("deleted", "superseded")
            or known
            and known["status"] in ("deleted", "superseded")
        )
        if terminal:
            value.update(
                status=known["status"]
                if known and known["status"] in ("deleted", "superseded")
                else row["status"],
                error=None,
            )
        elif (
            path
            and root.enabled
            and root.available
            and owner_for_path(path, roots.values(), "video") is not None
        ):
            marked = _mark(
                source, local, target, "trash_items", row["id"], path, root, check, settings, known
            )
            actual = marked["trash_path"] if isinstance(marked, dict) else path
            observed = _verify(
                actual,
                row["sha256"],
                row["size"],
                settings,
                check,
                trash=marked if isinstance(marked, dict) else None,
            )
            if observed:
                value.update(
                    status="trash" if marked else "available",
                    error=None,
                    location_key=path,
                    device=observed[0],
                    inode=observed[1],
                    mtime_ns=observed[3],
                    ctime_ns=observed[4],
                )
            elif marked:
                value.update(status="trash", error="trash_missing", location_key=path)
        target.execute(update(table).where(table.c.id == row["id"]).values(**value))
        if value["location_key"]:
            _parents(target, value["path"], root)


def _packs(source, local, target, old_roots, roots, mappings, settings, check):
    packs, pages = TABLE_MAP["packs"], TABLE_MAP["pack_pages"]
    for row in _rows(source, packs):
        _check(check)
        root, known = roots[row["root_id"]], _one(local, "packs", row["id"])
        path = (
            mapped_path(row["path"], old_roots[root.id]["path"], root.path)
            if mappings[root.id]
            else None
        )
        if (
            mappings[row["root_id"]]
            and root.enabled
            and known
            and known["status"] in ("available", "trash")
        ):
            actual_owner = owner_for_path(known["path"], roots.values(), "pack")
            if actual_owner and actual_owner.available:
                root, path = actual_owner, known["path"]
        value = dict(row)
        value.update(
            path=path or row["path"],
            root_id=root.id,
            device="",
            inode="",
            directory_signature=[],
            seen_scan=None,
            content_version=max(row["content_version"], known["content_version"] if known else 0)
            + 1,
            generation=max(row["generation"], known["generation"] if known else 0) + 1,
            location_key=None,
            status="missing",
            error="root_unmapped" if not path else "source_missing",
        )
        terminal = (
            row["status"] in ("deleted", "superseded")
            or known
            and known["status"] in ("deleted", "superseded")
        )
        observed = None
        if terminal:
            value.update(
                status=known["status"]
                if known and known["status"] in ("deleted", "superseded")
                else row["status"],
                error=None,
            )
        elif path and root.available and root.enabled:
            owner = owner_for_path(path, roots.values(), "pack")
            if (
                owner is not None
                and owner.id == root.id
                and not excluded(Path(path), settings.data_dir)
            ):
                try:
                    with open_directory(Path(path)) as fd:
                        observed = directory_stamp(fd)
                except OSError:
                    pass
            if observed:
                marked = _mark(
                    source,
                    local,
                    target,
                    "pack_trash_items",
                    row["id"],
                    path,
                    root,
                    check,
                    settings,
                    known,
                )
                value.update(
                    device=observed[0],
                    inode=observed[1],
                    directory_signature=observed,
                    status="trash" if marked else "available",
                    location_key=path,
                    error=None,
                )
        for page in _rows(source, pages, pages.c.pack_id == row["id"]):
            _check(check)
            actual = str(Path(path) / page["relative_path"]) if path else page["path"]
            # A successful physical purge is a tombstone even if bytes later
            # reappear at the same path. Retire the old page ID, as scanning does.
            steps, parents = TABLE_MAP["pack_purge_steps"], TABLE_MAP["pack_file_steps"]
            purged = local.execute(
                select(steps.c.id)
                .join(parents, parents.c.id == steps.c.parent_id)
                .where(
                    parents.c.pack_id == row["id"],
                    steps.c.kind == "image",
                    steps.c.outcome == "succeeded",
                    steps.c.relative_path == page["relative_path"],
                    steps.c.expected_hash == page["sha256"],
                )
                .limit(1)
            ).first()
            if purged:
                target.execute(
                    update(parents).where(parents.c.page_id == page["id"]).values(page_id=None)
                )
                progress = TABLE_MAP["pack_progress"]
                target.execute(
                    update(progress)
                    .where(progress.c.page_id == page["id"])
                    .values(
                        page_id=None,
                        completed=False,
                        offset_ratio=0,
                        revision=progress.c.revision + 1,
                        recovery_reason="page_removed",
                    )
                )
                target.execute(delete(pages).where(pages.c.id == page["id"]))
                continue
            owner = owner_for_path(actual, roots.values(), "pack") if path else None
            fresh = (
                _verify(actual, page["sha256"], page["size"], settings, check)
                if observed and owner and owner.id == root.id
                else None
            )
            target.execute(
                update(pages)
                .where(pages.c.id == page["id"])
                .values(
                    path=actual,
                    signature=fresh or [],
                    thumbnail=None,
                    seen_scan=None,
                    error=None if fresh else "image_unavailable",
                )
            )
        if observed:
            try:
                with open_directory(Path(path)) as fd:
                    if directory_stamp(fd) != observed:
                        raise OSError("pack changed while hashing")
            except OSError:
                value.update(status="missing", location_key=None, error="pack_changed")
                target.execute(
                    update(pages)
                    .where(pages.c.pack_id == row["id"])
                    .values(signature=[], error="image_unavailable")
                )
        value["page_count"] = target.scalar(
            select(func.count()).select_from(pages).where(pages.c.pack_id == row["id"])
        )
        readable = target.scalar(
            select(func.count())
            .select_from(pages)
            .where(pages.c.pack_id == row["id"], pages.c.error.is_(None))
        )
        if observed and not readable:
            value["error"] = "no_readable_images"
            if value["status"] == "available":
                value.update(status="missing", location_key=None)
        target.execute(update(packs).where(packs.c.id == row["id"]).values(**value))

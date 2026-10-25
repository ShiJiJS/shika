"""Scan whole packs, stage discoveries, and reconcile only unique identity evidence."""

import hashlib
import os
import re
import time
from collections import Counter, defaultdict
from pathlib import Path
from types import SimpleNamespace

from sqlalchemy import and_, delete, literal, or_, select, update

from . import pack_root_evidence
from .directory_identity import directory_stamp
from .images import IMAGE_EXTENSIONS, inspect_image
from .media_roots import owned_path, owner_for_path
from .models import (
    ImagePack,
    Observation,
    PackFileOperation,
    PackFileStep,
    PackPage,
    PackProgress,
    PackRestoreMember,
    PackRestorePlan,
    Root,
)
from .paths import beneath, excluded, open_directory, open_regular, signature

PAGE_FIELDS = (
    "path",
    "relative_path",
    "ordinal",
    "width",
    "height",
    "size",
    "format",
    "signature",
    "sha256",
    "error",
    "thumbnail",
)


def natural_key(value):
    return tuple(
        tuple(
            (1, int(part), len(part))
            if part.isdecimal() and part.isascii()
            else (0, part.casefold(), part)
            for part in re.split(r"([0-9]+)", component)
        )
        for component in Path(value).parts
    )


def digest_pages(session, pack_id, *, require_owned=True):
    statement = (
        select(
            PackPage.sha256,
            owned_path(session, PackPage.path, ImagePack.root_id)
            if require_owned
            else literal(True),
        )
        .join(ImagePack)
        .where(PackPage.pack_id == pack_id)
        .order_by(PackPage.sha256)
    )
    digest, count = hashlib.sha256(), 0
    for value, owned in session.execute(statement):
        if not value or not owned:
            return None  # Hidden/unverified subtrees are never content evidence.
        digest.update(value.encode())
        count += 1
    return (count, digest.hexdigest()) if count else None


def reserved_packs(*, pack_id=None, exclude_operation=None, exclude_plan=None):
    steps = (
        select(PackFileStep.pack_id)
        .join(PackFileOperation)
        .where(PackFileOperation.historical.is_(False), or_(
            PackFileStep.outcome == "pending",
            and_(PackFileStep.phase == "needs_attention", PackFileStep.outcome != "succeeded"),
        ))
    )
    members = (
        select(PackRestoreMember.pack_id)
        .join(PackRestorePlan)
        .where(PackRestorePlan.historical.is_(False), PackRestoreMember.outcome == "pending")
    )
    if exclude_operation:
        steps = steps.where(PackFileStep.operation_id != exclude_operation)
    if exclude_plan:
        members = members.where(PackRestoreMember.plan_id != exclude_plan)
    reserved = steps.union(members).subquery()
    statement = select(reserved.c.pack_id)
    return statement.where(reserved.c.pack_id == pack_id) if pack_id else statement


class PackDeferred(Exception):
    pass


class PackScanner:
    def __init__(self, scanner):
        self.scanner = scanner
        self.db, self.settings = scanner.db, scanner.settings
        self.cache = self.settings.data_dir / "image-thumbnails"

    def tick(self, task_id, result, force=False):
        self.scanner.check_stop()
        result["packs"]["progress"]["updated_at"] = time.time()
        self.scanner.progress(task_id, result, force=force)

    def issue(self, result, code, *, pack_id=None, root_id=None, name=None):
        summary = result["packs"]
        summary["failure_reasons"][code] = summary["failure_reasons"].get(code, 0) + 1
        if len(summary["issues"]) < 100:
            summary["issues"].append(
                {"code": code, "pack_id": pack_id, "root_id": root_id, "name": name}
            )

    def run(self, task_id, roots, result):
        summary = result["packs"] = {
            "imported": 0,
            "updated": 0,
            "failed_pages": 0,
            "failed_packs": 0,
            "protected_packs": 0,
            "unchanged": 0,
            "deferred": 0,
            "failed": 0,
            "missing": 0,
            "identity_matched": 0,
            "identity_ambiguous": 0,
            "thumbnail_failed": 0,
            "unsupported_files": 0,
            "loose_images": 0,
            "symlinks_skipped": 0,
            "failure_reasons": {},
            "issues": [],
            "progress": {
                "discovered": 0,
                "processed": 0,
                "packs_discovered": 0,
                "packs_processed": 0,
                "peak_decoder_kib": 0,
            },
        }
        active = [root for root in roots if root.kind == "pack" and root.enabled]
        if not active:
            return
        self.scanner.change_task(task_id, phase="pack_discovering", result=result)
        with self.db.write() as session:
            # Unpublished staging records can have no user/session/file references.
            session.execute(delete(ImagePack).where(ImagePack.status == "discovered"))
            old = list(
                session.scalars(
                    select(ImagePack).where(
                        ImagePack.status.in_(("available", "missing")),
                        ImagePack.id.not_in(reserved_packs()),
                    )
                )
            )
        initial_catalog = not old
        initial_generations = {pack.id: pack.generation for pack in old}
        by_inode = defaultdict(list)
        for pack in old:
            if pack.device and pack.inode:
                by_inode[(pack.device, pack.inode)].append(pack)
        inventories, current = {}, []
        root_items = {}
        for root in active:
            item = {
                "id": root.id,
                "kind": "pack",
                "status": "discovering",
                "discovered": 0,
                "processed": 0,
            }
            root_items[root.id] = item
            result["roots"].append(item)
            if not root.mount_id:
                self.unavailable(root.id, item, "root_unmapped")
                continue
            try:
                with open_directory(Path(root.path)) as fd:
                    identity = pack_root_evidence.identity(fd)
                    folders = []
                    with os.scandir(fd) as entries:
                        for entry in entries:
                            path = Path(root.path) / entry.name
                            self.scanner.check_stop()
                            if excluded(path, self.settings.data_dir) or (
                                self.settings.trash_dir and beneath(path, self.settings.trash_dir)
                            ):
                                continue
                            if entry.is_symlink():
                                summary["symlinks_skipped"] += 1
                                continue
                            if entry.is_dir(follow_symlinks=False):
                                owner = owner_for_path(path, roots, "pack")
                                if owner and owner.id == root.id:
                                    info = entry.stat(follow_symlinks=False)
                                    folders.append((path, (str(info.st_dev), str(info.st_ino))))
                            elif path.suffix.lower() in IMAGE_EXTENSIONS:
                                summary["loose_images"] += 1
                            else:
                                summary["unsupported_files"] += 1
                    inventories[root.id] = (identity, folders)
                    if initial_catalog:
                        # With no old identity to recover, each completed pack can
                        # be browsed immediately while later packs are inspecting.
                        with self.db.write() as session:
                            session.get(Root, root.id).available = True
                    current.extend((root, path, identity) for path, identity in folders)
            except InterruptedError:
                raise
            except OSError:
                self.unavailable(root.id, item)
        paths = {str(path) for _, path, _ in current}
        inode_counts = Counter(identity for _, _, identity in current)
        summary["progress"]["packs_discovered"] = len(current)
        completed = set()
        for root in active:
            if root.id not in inventories:
                continue
            item = root_items[root.id]
            root_ok, deferred = True, False
            for path, identity in sorted(
                inventories[root.id][1], key=lambda row: natural_key(str(row[0]))
            ):
                self.tick(task_id, result)
                with self.db.read() as session:
                    located = session.scalar(
                        select(ImagePack).where(ImagePack.location_key == str(path))
                    )
                    if located and (
                        located.status in ("trash", "deleted")
                        or initial_generations.get(located.id) != located.generation
                        or session.scalar(
                            reserved_packs(pack_id=located.id).limit(1)
                        )
                    ):
                        summary["protected_packs"] += 1
                        summary["progress"]["packs_processed"] += 1
                        item["processed"] += 1
                        continue
                candidates = [
                    pack
                    for pack in by_inode[identity]
                    if pack.root_id in inventories
                    and (pack.path == str(path) or pack.path not in paths)
                ]
                previous = candidates[0] if len(candidates) == inode_counts[identity] == 1 else None
                try:
                    pages, stamp = self.read_pack(
                        path, identity, root, roots, previous or located, task_id, result
                    )
                    proven = [
                        candidate
                        for candidate in candidates
                        if self.continuity(candidate, pages, stamp)
                    ]
                    located_match = next(
                        (
                            candidate
                            for candidate in proven
                            if located and candidate.id == located.id
                        ),
                        None,
                    )
                    if located_match:
                        previous = located_match
                    else:
                        previous = proven[0] if len(proven) == inode_counts[identity] == 1 else None
                    with self.db.write() as session:
                        pack = session.get(ImagePack, previous.id) if previous else None
                        occupied = session.scalar(
                            select(ImagePack).where(ImagePack.location_key == str(path))
                        )
                        # Inspection runs outside the write transaction. A cleanup accepted
                        # meanwhile owns both the stable identity and the occupied location.
                        if any(
                            candidate
                            and (
                                candidate.status in ("trash", "deleted")
                                or initial_generations.get(candidate.id) != candidate.generation
                                or session.scalar(
                                    reserved_packs(pack_id=candidate.id)
                                    .limit(1)
                                )
                            )
                            for candidate in (pack, occupied)
                        ):
                            summary["protected_packs"] += 1
                            summary["progress"]["packs_processed"] += 1
                            item["processed"] += 1
                            continue
                        if not pack:
                            pack = ImagePack(
                                root_id=root.id,
                                path=str(path),
                                name=path.name,
                                status="available" if initial_catalog else "discovered",
                                location_key=str(path) if initial_catalog else None,
                                device=identity[0],
                                inode=identity[1],
                            )
                            session.add(pack)
                            session.flush()
                            summary["imported"] += 1
                        elif pack.path != str(path):
                            summary["identity_matched"] += 1
                        changed = self.publish_pages(
                            session, pack, pages, path, root.id, identity, task_id, stamp
                        )
                        if previous:
                            summary["updated" if changed else "unchanged"] += 1
                        if pack.error:
                            self.issue(result, pack.error, pack_id=pack.id)
                    summary["progress"]["packs_processed"] += 1
                    item["processed"] += 1
                except PackDeferred:
                    deferred = True
                    summary["deferred"] += 1
                except InterruptedError:
                    raise
                except OSError:
                    root_ok = False
                    summary["failed"] += 1
                    summary["failed_packs"] += 1
                    failed_id = previous.id if previous else located.id if located else None
                    self.issue(
                        result,
                        "pack_directory_unavailable",
                        pack_id=failed_id,
                        root_id=root.id,
                        name=path.name,
                    )
                    if failed_id:
                        with self.db.write() as session:
                            failed = session.get(ImagePack, failed_id)
                            if (
                                failed
                                and failed.status not in ("trash", "deleted")
                                and not session.scalar(
                                    reserved_packs(pack_id=failed.id)
                                    .limit(1)
                                )
                            ):
                                failed.error = "pack_directory_unavailable"
                self.tick(task_id, result)
            accessible = True
            try:
                with open_directory(Path(root.path)) as fd:
                    if pack_root_evidence.identity(fd) != inventories[root.id][0]:
                        accessible = False
            except OSError:
                accessible = False
            if not accessible:
                self.unavailable(root.id, item)
            elif not root_ok:
                item.update(status="partial", error="pack_scan_incomplete")
                with self.db.write() as session:
                    stored = session.get(Root, root.id)
                    stored.available, stored.error = True, "pack_scan_incomplete"
            elif deferred:
                item.update(status="deferred", error="files_changing")
                with self.db.write() as session:
                    stored = session.get(Root, root.id)
                    stored.available, stored.error = True, "files_changing"
            else:
                item["status"] = "completed"
                completed.add(root.id)
                with self.db.write() as session:
                    stored = session.get(Root, root.id)
                    stored.available, stored.error = True, None
            item["discovered"] = len(inventories[root.id][1])
        self.scanner.change_task(task_id, phase="pack_reconciling", result=result)
        self.reconcile(task_id, completed, result, initial_generations, inventories)
        self.tick(task_id, result, force=True)

    def unavailable(self, root_id, item, code="root_unavailable"):
        item.update(status="unavailable", error=code)
        with self.db.write() as session:
            root = session.get(Root, root_id)
            root.available, root.error = False, code

    def read_pack(self, path, identity, root, roots, previous, task_id, result):
        summary = result["packs"]
        inventory, directories = [], []

        def walk(fd, directory):
            self.scanner.check_stop()
            owner = owner_for_path(directory, roots, "pack")
            if not owner or owner.id != root.id:
                return
            directories.append((directory, signature(os.fstat(fd))))
            with self.db.write() as session:
                record = self.scanner.catalog.ensure_directory(session, directory, root.id, task_id)
                record.root_id = root.id
            with os.scandir(fd) as entries:
                for entry in entries:
                    full = directory / entry.name
                    if excluded(full, self.settings.data_dir) or (
                        self.settings.trash_dir and beneath(full, self.settings.trash_dir)
                    ):
                        continue
                    if entry.is_symlink():
                        summary["symlinks_skipped"] += 1
                        continue
                    if entry.is_dir(follow_symlinks=False):
                        owner = owner_for_path(full, roots, "pack")
                        if not owner or owner.id != root.id:
                            continue
                        child = os.open(
                            entry.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd
                        )
                        try:
                            walk(child, full)
                        finally:
                            os.close(child)
                    elif entry.is_file(follow_symlinks=False):
                        owner = owner_for_path(full, roots, "pack")
                        if not owner or owner.id != root.id:
                            continue
                        if full.suffix.lower() in IMAGE_EXTENSIONS:
                            inventory.append((full, signature(entry.stat(follow_symlinks=False))))
                        else:
                            summary["unsupported_files"] += 1

        with open_directory(path) as fd:
            stamp = directory_stamp(fd)
            if tuple(stamp[:2]) != identity:
                raise PackDeferred()
            walk(fd, path)
        summary["progress"]["discovered"] += len(inventory)
        with self.db.read() as session:
            cached = (
                {
                    page.relative_path: page
                    for page in session.scalars(
                        select(PackPage).where(PackPage.pack_id == previous.id)
                    )
                }
                if previous
                else {}
            )
        observations = []
        self.scanner.change_task(task_id, phase="pack_inspecting", result=result)
        for full, observed in sorted(
            inventory, key=lambda row: natural_key(str(row[0].relative_to(path)))
        ):
            self.tick(task_id, result)
            relative = str(full.relative_to(path))
            with self.db.write() as session:
                prior = session.get(Observation, str(full))
                if not prior:
                    prior = Observation(
                        path=str(full),
                        signature=observed,
                        stable_since=min(
                            time.time(), max(int(observed[3]), int(observed[4])) / 1e9
                        ),
                    )
                    session.add(prior)
                elif prior.signature != observed:
                    prior.signature, prior.stable_since = observed, time.time()
                stable_since = prior.stable_since
            if time.time() - stable_since < self.settings.stability_seconds:
                raise PackDeferred()
            with open_regular(full) as fd:
                if signature(os.fstat(fd)) != observed:
                    raise PackDeferred()
                old = cached.get(relative)
                if old and old.signature == observed:
                    metadata = {key: getattr(old, key) for key in PAGE_FIELDS}
                    if not old.error and (
                        not old.thumbnail or not (self.cache / old.thumbnail).is_file()
                    ):
                        inspected = inspect_image(
                            fd, self.cache, self.settings.probe_timeout, self.scanner.stop
                        )
                        if not inspected.get("error"):
                            metadata["thumbnail"] = inspected.get("thumbnail")
                            if inspected.get("thumbnail_warning"):
                                summary["thumbnail_failed"] += 1
                else:
                    digest = hashlib.sha256()
                    os.lseek(fd, 0, os.SEEK_SET)
                    while chunk := os.read(fd, 1024 * 1024):
                        self.scanner.check_stop()
                        digest.update(chunk)
                    os.lseek(fd, 0, os.SEEK_SET)
                    inspected = inspect_image(
                        fd, self.cache, self.settings.probe_timeout, self.scanner.stop
                    )
                    metadata = {
                        "width": inspected.get("width", 0),
                        "height": inspected.get("height", 0),
                        "format": inspected.get(
                            "format",
                            {".png": "PNG", ".webp": "WEBP"}.get(full.suffix.lower(), "JPEG"),
                        ),
                        "sha256": digest.hexdigest(),
                        "error": inspected.get("error"),
                        "thumbnail": inspected.get("thumbnail"),
                    }
                    if inspected.get("thumbnail_warning"):
                        summary["thumbnail_failed"] += 1
                    summary["progress"]["peak_decoder_kib"] = max(
                        summary["progress"]["peak_decoder_kib"], inspected.get("peak_rss_kib", 0)
                    )
                    if inspected.get("error"):
                        summary["failed_pages"] += 1
                        summary["failed"] += 1
                        self.issue(
                            result,
                            inspected["error"],
                            root_id=root.id,
                            name=f"{path.name}/{relative}",
                        )
                if signature(os.fstat(fd)) != observed:
                    raise PackDeferred()
            with open_regular(full) as fresh:
                if signature(os.fstat(fresh)) != observed:
                    raise PackDeferred()
            metadata.update(
                path=str(full), relative_path=relative, signature=observed, size=observed[2]
            )
            observations.append(metadata)
            summary["progress"]["processed"] += 1
        with open_directory(path) as fd:
            if tuple(signature(os.fstat(fd))[:2]) != identity:
                raise PackDeferred()
        for directory, observed in directories:
            with open_directory(directory) as fd:
                if signature(os.fstat(fd)) != observed:
                    raise PackDeferred()
        return sorted(observations, key=lambda row: natural_key(row["relative_path"])), stamp

    def continuity(self, previous, observations, stamp):
        old = previous.directory_signature
        if old:
            if old[:2] != stamp[:2]:
                return False
            if old[-1] is not None and stamp[-1] is not None:
                return old[-1] == stamp[-1]
            if old[:5] == stamp[:5]:
                return True
        # Filesystems without creation times need corroborating page evidence.
        current = {tuple(page["signature"]) for page in observations if page["signature"]}
        with self.db.read() as session:
            return any(
                tuple(signature) in current
                for signature in session.scalars(
                    select(PackPage.signature).where(PackPage.pack_id == previous.id)
                )
                if signature
            )

    def publish_pages(self, session, pack, observations, path, root_id, identity, task_id, stamp):
        old = list(session.scalars(select(PackPage).where(PackPage.pack_id == pack.id)))
        # Protected metadata belongs only to the identity actually selected.
        observations = list(observations)
        present = {page["relative_path"] for page in observations}
        roots = list(session.scalars(select(Root)))
        for page in old:
            candidate = path / page.relative_path
            owner = owner_for_path(candidate, roots, "pack")
            if page.relative_path not in present and (not owner or owner.id != root_id):
                retained = {field: getattr(page, field) for field in PAGE_FIELDS}
                retained["path"] = str(candidate)
                observations.append(retained)
        observations.sort(key=lambda page: natural_key(page["relative_path"]))
        before = sorted(
            (page.relative_path, page.signature, page.sha256, page.error) for page in old
        )
        by_path = {page.relative_path: page for page in old}
        matches, used = {}, set()
        for index, row in enumerate(observations):
            prior = by_path.get(row["relative_path"])
            if prior and (
                prior.signature == row["signature"]
                or (prior.sha256 and prior.sha256 == row["sha256"])
            ):
                matches[index], used = prior, used | {prior.id}
        for key in (lambda row: tuple(row.signature[:2]), lambda row: row.sha256):
            old_groups, new_groups = defaultdict(list), defaultdict(list)
            for page in old:
                if page.id not in used:
                    old_groups[key(page)].append(page)
            for index, row in enumerate(observations):
                if index not in matches:
                    new_groups[key(SimpleNamespace(**row))].append(index)
            for value, indexes in new_groups.items():
                if value and len(indexes) == len(old_groups[value]) == 1:
                    prior = old_groups[value][0]
                    matches[indexes[0]], used = prior, used | {prior.id}
        for page in old:
            page.relative_path = ".vv-retired-" + page.id
        session.flush()
        updated = []
        for index, row in enumerate(observations):
            page = matches.get(index)
            if not page:
                page = PackPage(pack_id=pack.id)
                session.add(page)
            for field in PAGE_FIELDS:
                if field != "ordinal":
                    setattr(page, field, row[field])
            page.ordinal, page.seen_scan = index, task_id
            updated.append(page)
        session.flush()
        removed = {page.id for page in old if page.id not in used}
        progress = session.get(PackProgress, pack.id)
        if progress and progress.page_id in removed:
            previous = next(page for page in old if page.id == progress.page_id)
            readable = [page for page in updated if not page.error]
            nearest = min(
                readable,
                key=lambda page: (
                    abs(page.ordinal - previous.ordinal),
                    page.ordinal < previous.ordinal,
                ),
                default=None,
            )
            progress.page_id = nearest.id if nearest else None
            progress.recovery_reason = "page_removed"
            progress.offset_ratio, progress.completed = 0, False
            progress.revision, progress.updated_at = progress.revision + 1, time.time()
            session.flush()
        if removed:
            session.execute(
                update(PackFileStep).where(PackFileStep.page_id.in_(removed)).values(page_id=None)
            )
            session.execute(delete(PackPage).where(PackPage.id.in_(removed)))
        after = sorted(
            (page.relative_path, page.signature, page.sha256, page.error) for page in updated
        )
        changed = before != after
        identity_changed = (
            pack.path != str(path) or pack.root_id != root_id or pack.status == "missing"
        )
        pack.content_version += int(changed or pack.content_version == 0)
        if progress and progress.recovery_reason:
            progress.content_version = pack.content_version
        pack.generation += int(changed or pack.path != str(path) or pack.status == "missing")
        pack.path, pack.name, pack.root_id = str(path), path.name, root_id
        pack.device, pack.inode = identity
        pack.directory_signature = stamp
        pack.page_count, pack.seen_scan = len(updated), task_id
        pack.error = (
            "pack_empty"
            if not updated
            else "no_readable_images"
            if all(page.error for page in updated)
            else None
        )
        if pack.status != "discovered":
            pack.status, pack.location_key = "available", str(path)
        return changed or identity_changed

    def reconcile(self, task_id, completed, result, initial_generations, inventories):
        summary = result["packs"]
        with self.db.write() as session:
            unseen = list(
                session.scalars(
                    select(ImagePack).where(
                        ImagePack.status == "available",
                        ImagePack.root_id.in_(completed),
                        ImagePack.seen_scan != task_id,
                        ImagePack.id.not_in(reserved_packs()),
                        owned_path(session, ImagePack.path, ImagePack.root_id),
                    )
                )
            )
            # A restore can release its reservation after this scan skipped the
            # directory. Only this scan's unchanged original candidates can be
            # declared missing; newly restored identities await the next scan.
            unseen = [pack for pack in unseen if initial_generations.get(pack.id) == pack.generation]
            unseen_ids = {pack.id for pack in unseen}
            for pack in unseen:
                pack.status, pack.location_key = "missing", None
                pack.generation += 1
                summary["missing"] += 1
            session.flush()
            current = list(
                session.scalars(
                    select(ImagePack).where(
                        ImagePack.status.in_(("available", "discovered")),
                        ImagePack.root_id.in_(completed),
                        ImagePack.seen_scan == task_id,
                    )
                )
            )
            counts = Counter(digest_pages(session, pack.id) for pack in current)
            known_counts = Counter()
            if any(pack.status == "discovered" for pack in current):
                for known in session.scalars(
                    select(ImagePack).where(ImagePack.status.in_(("available", "missing", "trash")))
                ):
                    known_counts[digest_pages(session, known.id, require_owned=False)] += 1
            missing = defaultdict(list)
            for pack in session.scalars(
                select(ImagePack).where(
                    ImagePack.status == "missing",
                    ImagePack.root_id.in_(completed),
                    ImagePack.id.not_in(reserved_packs()),
                    owned_path(session, ImagePack.path, ImagePack.root_id),
                )
            ):
                if pack.id in initial_generations and pack.generation == initial_generations[pack.id] + int(pack.id in unseen_ids):
                    missing[digest_pages(session, pack.id)].append(pack)
            for fresh in current:
                if fresh.status != "discovered":
                    continue
                digest = digest_pages(session, fresh.id)
                candidates = missing[digest] if digest else []
                if len(candidates) == counts[digest] == known_counts[digest] == 1:
                    previous = candidates[0]
                    pages = [
                        {field: getattr(page, field) for field in PAGE_FIELDS}
                        for page in session.scalars(
                            select(PackPage).where(PackPage.pack_id == fresh.id)
                        )
                    ]
                    self.publish_pages(
                        session,
                        previous,
                        sorted(pages, key=lambda p: natural_key(p["relative_path"])),
                        Path(fresh.path),
                        fresh.root_id,
                        (fresh.device, fresh.inode),
                        task_id,
                        fresh.directory_signature,
                    )
                    session.execute(delete(PackPage).where(PackPage.pack_id == fresh.id))
                    session.delete(fresh)
                    for issue in summary["issues"]:
                        if issue["pack_id"] == fresh.id:
                            issue["pack_id"] = previous.id
                    summary["identity_matched"] += 1
                    summary["imported"] -= 1
                    summary["updated"] += 1
                    summary["missing"] -= int(previous.id in unseen_ids)
                else:
                    fresh.status, fresh.location_key = "available", fresh.path
                    if candidates:
                        summary["identity_ambiguous"] += 1
            for root_id in completed:
                root = session.get(Root, root_id)
                root.last_scan = time.time()
                pack_root_evidence.remember(session, root, inventories[root_id][0])
            # No failed/partial root can publish staged data or classify old data missing.
            session.execute(delete(ImagePack).where(ImagePack.status == "discovered"))

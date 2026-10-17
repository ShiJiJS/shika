import os
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from sqlalchemy import delete, select, update

from .errors import LibraryError
from .file_state import path_reserved, reserved_video_ids
from .identity import publish_discoveries
from .media import MediaInspectionError, fingerprint, inspect_media, make_thumbnail
from .models import Directory, Observation, Root, Setting, Task, Video
from .paths import VIDEO_EXTENSIONS, beneath, excluded, open_directory, open_video, signature


class Scanner:
    """One durable scan at a time; only short per-file database transactions."""

    def __init__(self, db, settings, catalog):
        self.db, self.settings, self.catalog = db, settings, catalog
        self.stop = threading.Event()
        self.lock = threading.RLock()
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="media-scan")
        self.future = None
        self.active_id = None
        with db.write() as session:
            session.execute(
                update(Task)
                .where(Task.kind == "scan", Task.status.in_(["queued", "running"]))
                .values(
                    status="interrupted",
                    phase="interrupted",
                    error="service_restarted",
                    finished_at=time.time(),
                )
            )
        self.scheduler = threading.Thread(target=self.schedule, name="scan-scheduler", daemon=True)

    def start(self):
        if self.settings.startup_scan:
            self.submit()
        self.scheduler.start()

    def schedule(self):
        interval = self.settings.scan_interval
        if interval <= 0:
            return
        while not self.stop.wait(interval):
            try:
                self.submit()
            except LibraryError as error:
                if error.code != "restore_in_progress":
                    raise

    def submit(self):
        with self.lock:
            if self.stop.is_set():
                raise LibraryError("service_stopping", "服务正在停止，请稍后重试", 503)
            if self.future and not self.future.done():
                return self.task(self.active_id)
            with self.db.write() as session:
                task = Task(kind="scan", status="queued", phase="queued", result={})
                session.add(task)
                session.flush()
                self.active_id = task.id
            self.future = self.executor.submit(self.run, task.id)
            return self.task(task.id)

    def task(self, task_id):
        with self.db.read() as session:
            task = session.get(Task, task_id)
            if not task:
                raise LibraryError("task_not_found", "任务不存在", 404)
            return {
                "id": task.id,
                "kind": task.kind,
                "status": task.status,
                "phase": task.phase,
                "created_at": task.created_at,
                "finished_at": task.finished_at,
                "result": task.result,
                "error": task.error,
            }

    def tasks(self, limit):
        with self.db.read() as session:
            ids = list(
                session.scalars(select(Task.id).order_by(Task.created_at.desc()).limit(limit))
            )
        return [self.task(task_id) for task_id in ids]

    def change_task(self, task_id, **values):
        with self.db.write() as session:
            task = session.get(Task, task_id)
            for key, value in values.items():
                setattr(task, key, value)

    def run(self, task_id):
        result = {
            "imported": 0,
            "unchanged": 0,
            "deferred": 0,
            "failed": 0,
            "thumbnail_failed": 0,
            "failure_reasons": {},
            "warning_reasons": {},
            "warnings": [],
            "missing": 0,
            "identity_matched": 0,
            "identity_ambiguous": 0,
            "roots": [],
            "issues": [],
            "progress": {"discovered": 0, "processed": 0, "bytes_total": 0, "bytes_processed": 0},
        }
        self.last_progress = 0
        try:
            with self.db.read() as session:
                initial_import = session.scalar(select(Video.id).limit(1)) is None
            self.change_task(task_id, status="running", phase="discovering", result=result)
            with self.db.read() as session:
                roots = list(session.scalars(select(Root).order_by(Root.path)))
            for root in roots:
                self.check_stop()
                self.scan_root(
                    task_id,
                    root,
                    [item for item in roots if item.mount_id],
                    result,
                    initial_import=initial_import,
                )
            self.check_stop()
            self.change_task(task_id, phase="reconciling_identities")
            publish_discoveries(
                self.db,
                self.settings,
                task_id,
                [root["id"] for root in result["roots"] if root["status"] == "completed"],
                result,
                self.check_stop,
            )
            # Readiness is published only after identity reconciliation, never
            # after merely traversing a directory. Keep it durable across upgrades.
            with self.db.write() as session:
                became_ready = False
                for item in result["roots"]:
                    if item["status"] == "completed":
                        root = session.get(Root, item["id"])
                        became_ready |= root.last_scan is None
                        root.last_scan = time.time()
                if became_ready:
                    flag = session.get(Setting, "library_round_refresh")
                    if flag:
                        flag.value = "1"
                    else:
                        session.add(Setting(key="library_round_refresh", value="1"))
            self.progress(task_id, result, force=True)
            self.change_task(
                task_id,
                status="completed",
                phase="completed",
                result=result,
                finished_at=time.time(),
            )
        except InterruptedError:
            self.change_task(
                task_id,
                status="interrupted",
                phase="interrupted",
                error="scan_interrupted",
                result=result,
                finished_at=time.time(),
            )
        except Exception:
            # Do not serialize subprocess commands, host paths or request secrets.
            self.change_task(
                task_id,
                status="failed",
                phase="failed",
                error="scan_failed",
                result=result,
                finished_at=time.time(),
            )

    def check_stop(self):
        if self.stop.is_set():
            raise InterruptedError("scan_stopped")

    def progress(self, task_id, result, *, force=False):
        now = time.monotonic()
        if force or now - self.last_progress >= 1:
            result["progress"]["updated_at"] = time.time()
            self.change_task(task_id, result=result)
            self.last_progress = now

    def scan_root(self, task_id, root, roots, result, *, initial_import=False):
        base = Path(root.path)
        entries = []
        item = {
            "id": root.id,
            "status": "discovering",
            "discovered": 0,
            "processed": 0,
            "bytes_total": 0,
            "bytes_processed": 0,
        }
        result["roots"].append(item)
        self.change_task(task_id, phase="discovering", result=result)
        if not root.mount_id:
            item.update(status="unavailable", error="root_unmapped")
            return
        try:
            with open_directory(base) as fd:
                os.listdir(fd)
                root_identity = (os.fstat(fd).st_dev, os.fstat(fd).st_ino)
            with self.db.write() as session:
                stored = session.get(Root, root.id)
                stored.available, stored.error = True, None
            # Walk opened directory FDs, not path-based os.walk, so an external
            # link replacement cannot redirect enumeration outside this root.
            with open_directory(base) as fd:
                self.discover(fd, base, root, roots, task_id, entries, result, item)
        except (OSError, LibraryError):
            with self.db.write() as session:
                stored = session.get(Root, root.id)
                stored.available, stored.error = False, "root_unavailable"
            item.update(status="unavailable", error="root_unavailable")
            return
        item["status"] = "processing_media"
        self.change_task(task_id, phase="waiting_for_stable_files", result=result)
        remaining = max(
            (since + self.settings.stability_seconds - time.time() for _, _, since in entries),
            default=0,
        )
        if remaining > 0 and self.stop.wait(remaining):
            raise InterruptedError("scan_stopped")
        self.change_task(task_id, phase="processing_media")
        for path, first_signature, stable_since in entries:
            self.check_stop()
            owner = min(
                (r for r in roots if beneath(path, Path(r.path))), key=lambda r: len(r.path)
            )
            with self.db.read() as session:
                existing = session.scalar(select(Video).where(Video.location_key == str(path)))
            try:
                self.scan_file(
                    path,
                    first_signature,
                    owner,
                    task_id,
                    result,
                    existing,
                    stable_since,
                    initial_import=initial_import,
                )
            except InterruptedError:
                raise
            except (
                OSError,
                ValueError,
                KeyError,
                StopIteration,
                LibraryError,
                subprocess.SubprocessError,
            ) as error:
                result["failed"] += 1
                code = (
                    error.code
                    if isinstance(error, (MediaInspectionError, LibraryError))
                    else "file_missing"
                    if isinstance(error, FileNotFoundError)
                    else "permission_denied"
                    if isinstance(error, PermissionError)
                    else "invalid_metadata"
                    if isinstance(error, (ValueError, KeyError, StopIteration))
                    else "media_read_failed"
                )
                result["failure_reasons"][code] = result["failure_reasons"].get(code, 0) + 1
                if len(result["issues"]) < 100:
                    result["issues"].append({"root_id": root.id, "name": path.name, "code": code})
                with self.db.write() as session:
                    self.record_state(session, existing, path, task_id, code)
            item["processed"] += 1
            item["bytes_processed"] += first_signature[2]
            result["progress"]["processed"] += 1
            result["progress"]["bytes_processed"] += first_signature[2]
            self.progress(task_id, result, force=item["processed"] == 1)
        self.check_stop()
        try:
            with open_directory(base) as fd:
                os.listdir(fd)
                if (os.fstat(fd).st_dev, os.fstat(fd).st_ino) != root_identity:
                    raise OSError("root_replaced_during_scan")
        except OSError:
            with self.db.write() as session:
                stored = session.get(Root, root.id)
                stored.available, stored.error = False, "root_unavailable"
            item.update(status="unavailable", error="root_unavailable")
            return
        # Only a successful complete traversal can mark unseen files missing.
        with self.db.write() as session:
            unseen = session.scalars(
                select(Video).where(
                    Video.status == "available",
                    Video.path.startswith(str(base) + "/", autoescape=True),
                    Video.seen_scan != task_id,
                    Video.id.not_in(reserved_video_ids()),
                )
            )
            for video in unseen:
                video.status, video.location_key = "missing", None
                result["missing"] += 1
            configured_paths = [r.path for r in roots]
            session.execute(
                delete(Directory).where(
                    Directory.path.startswith(str(base) + "/", autoescape=True),
                    Directory.seen_scan != task_id,
                    Directory.path.not_in(configured_paths),
                )
            )
            stored = session.get(Root, root.id)
            stored.available, stored.error = True, None
        item["status"] = "completed"
        self.progress(task_id, result, force=True)

    def discover(self, fd, path, root, roots, task_id, entries, result, item):
        self.check_stop()
        owner = min((r for r in roots if beneath(path, Path(r.path))), key=lambda r: len(r.path))
        with self.db.write() as session:
            self.catalog.ensure_directory(session, path, owner.id, task_id)
        with os.scandir(fd) as children:
            for child in children:
                self.check_stop()
                full = path / child.name
                if (
                    excluded(full, self.settings.data_dir)
                    or (self.settings.trash_dir and beneath(full, self.settings.trash_dir))
                    or child.is_symlink()
                ):
                    continue
                if child.is_dir(follow_symlinks=False):
                    nested = os.open(
                        child.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd
                    )
                    try:
                        self.discover(nested, full, root, roots, task_id, entries, result, item)
                    finally:
                        os.close(nested)
                elif (
                    child.is_file(follow_symlinks=False) and full.suffix.lower() in VIDEO_EXTENSIONS
                ):
                    info = child.stat(follow_symlinks=False)
                    observed = signature(info)
                    with self.db.write() as session:
                        previous = session.get(Observation, str(full))
                        if not previous:
                            previous = Observation(
                                path=str(full), signature=observed, stable_since=time.time()
                            )
                            session.add(previous)
                        elif previous.signature != observed:
                            previous.signature, previous.stable_since = observed, time.time()
                        stable_since = previous.stable_since
                    entries.append((full, observed, stable_since))
                    item["discovered"] += 1
                    item["bytes_total"] += observed[2]
                    result["progress"]["discovered"] += 1
                    result["progress"]["bytes_total"] += observed[2]
                    self.progress(task_id, result)

    @staticmethod
    def record_state(session, existing, path, task_id, error):
        if not existing or path_reserved(session, path):
            return False
        stored = session.get(Video, existing.id)
        if (
            stored.status not in ("available", "discovered")
            or stored.generation != existing.generation
        ):
            return False
        stored.seen_scan, stored.error = task_id, error
        return True

    def scan_file(
        self, path, observed, root, task_id, result, existing, stable_since, *, initial_import=False
    ):
        thumbnail = None
        with self.db.read() as session:
            if path_reserved(session, path):
                result["deferred"] += 1
                return
            # Logical trash keeps its location reserved. Never re-import or
            # probe the still-present source as an ordinary available video.
            stored = session.get(Video, existing.id) if existing else None
            if stored and stored.status == "trash":
                result["unchanged"] += 1
                return
        with open_video(path, self.settings.mounts) as fd:
            current = signature(os.fstat(fd))
            if current != observed or time.time() - stable_since < self.settings.stability_seconds:
                with self.db.write() as session:
                    self.record_state(session, existing, path, task_id, "file_changing")
                result["deferred"] += 1
                return
            cached = existing and current == [
                existing.device,
                existing.inode,
                existing.size,
                existing.mtime_ns,
                existing.ctime_ns,
            ]
            if (
                cached
                and existing.thumbnail
                and (self.settings.data_dir / "thumbnails" / existing.thumbnail).is_file()
            ):
                with self.db.write() as session:
                    self.record_state(session, existing, path, task_id, None)
                result["unchanged"] += 1
                return
            if cached:
                # Rebuilding a missing optional poster must not hash the whole
                # unchanged original or probe its already verified metadata again.
                digest, quick = existing.sha256, existing.quick_hash
                media = {
                    key: getattr(existing, key)
                    for key in (
                        "duration",
                        "width",
                        "height",
                        "rotation",
                        "video_codec",
                        "audio_codec",
                        "container",
                    )
                }
                try:
                    media["thumbnail"] = make_thumbnail(
                        fd, self.settings.data_dir / "thumbnails", self.settings.probe_timeout
                    )
                except MediaInspectionError as error:
                    media.update(thumbnail=None, thumbnail_warning=error.code)
            else:
                digest, quick = fingerprint(fd, self.stop)
                media = inspect_media(
                    fd, self.settings.data_dir / "thumbnails", self.settings.probe_timeout
                )
            warning = media.pop("thumbnail_warning", None)
            thumbnail = media["thumbnail"]
            # Recheck both opened content and current path after expensive work.
            if signature(os.fstat(fd)) != current:
                if thumbnail:
                    (self.settings.data_dir / "thumbnails" / thumbnail).unlink(missing_ok=True)
                result["deferred"] += 1
                if existing:
                    with self.db.write() as session:
                        self.record_state(session, existing, path, task_id, "file_changing")
                return
            with open_video(path, self.settings.mounts) as fresh:
                if signature(os.fstat(fresh)) != current:
                    if thumbnail:
                        (self.settings.data_dir / "thumbnails" / thumbnail).unlink(missing_ok=True)
                    raise OSError("file_replaced_during_probe")
        with self.db.write() as session:
            stored = session.get(Video, existing.id) if existing else None
            concurrent = session.scalar(select(Video).where(Video.location_key == str(path)))
            if (
                path_reserved(session, path)
                or (
                    stored
                    and (
                        stored.generation != existing.generation
                        or stored.status not in ("available", "discovered")
                    )
                )
                or (not existing and concurrent)
            ):
                if thumbnail:
                    (self.settings.data_dir / "thumbnails" / thumbnail).unlink(missing_ok=True)
                result["deferred"] += 1
                return
            if stored and stored.sha256 != digest:
                stored.status, stored.location_key = "missing", None
                session.flush()
                stored = None
            if not stored:
                stored = Video(
                    root_id=root.id,
                    path=str(path),
                    location_key=str(path),
                    name=path.name,
                    # A library with no history cannot transfer an existing
                    # identity or tags. Publish each fully verified initial
                    # file immediately, so a large first scan is usable.
                    # Later scans still reconcile complete discoveries.
                    status="available" if initial_import else "discovered",
                    sha256=digest,
                    quick_hash=quick,
                    type=path.suffix[1:].upper(),
                    size=current[2],
                    device=current[0],
                    inode=current[1],
                    mtime_ns=current[3],
                    ctime_ns=current[4],
                    seen_scan=task_id,
                    **media,
                )
                session.add(stored)
            else:
                for key, value in media.items():
                    setattr(stored, key, value)
                stored.size, stored.device, stored.inode, stored.mtime_ns, stored.ctime_ns = (
                    current[2],
                    current[0],
                    current[1],
                    current[3],
                    current[4],
                )
                stored.seen_scan, stored.error = task_id, None
            result["unchanged" if cached else "imported"] += 1
            if warning:
                result["thumbnail_failed"] += 1
                result["warning_reasons"][warning] = result["warning_reasons"].get(warning, 0) + 1
                if len(result["warnings"]) < 100:
                    result["warnings"].append(
                        {"root_id": root.id, "name": path.name, "code": warning}
                    )

    def close(self):
        self.stop.set()
        if self.scheduler.is_alive():
            self.scheduler.join(timeout=2)
        self.executor.shutdown(wait=True, cancel_futures=True)

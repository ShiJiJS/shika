import json
import os
import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path
from threading import RLock, get_ident

from alembic import command
from alembic.config import Config
from alembic.script import ScriptDirectory
from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session

from .authority import Authority
from .errors import LibraryError
from .models import Setting


class Database:
    def __init__(self, data_dir: Path):
        data_dir.mkdir(parents=True, exist_ok=True)
        self.path = data_dir / "library.sqlite3"
        self.last_migration_snapshot = None
        self.engine = create_engine(
            f"sqlite:///{data_dir / 'library.sqlite3'}",
            connect_args={"check_same_thread": False, "timeout": 15},
        )
        self.write_lock = RLock()
        self.authority = Authority()
        self.maintenance_task = None
        self.maintenance_owner = None

        @event.listens_for(self.engine, "connect")
        def configure(connection, _record):
            connection.execute("PRAGMA foreign_keys=ON")
            connection.execute("PRAGMA busy_timeout=15000")
            # Keep reads responsive while a large NAS library is discovered.
            # FULL preserves durable command intent before physical file work.
            # Autocheckpoint bounds ordinary WAL growth; readers are short-lived.
            mode = connection.execute("PRAGMA journal_mode=WAL").fetchone()[0]
            if mode.lower() != "wal":
                raise RuntimeError("Management data requires a local filesystem supporting WAL")
            connection.execute("PRAGMA synchronous=FULL")
            connection.execute("PRAGMA wal_autocheckpoint=1000")

    def migrate(self):
        source = Path(__file__).resolve().parent.parent
        config = Config(str(source / "alembic.ini"))
        config.set_main_option("script_location", str(source / "migrations"))
        head = ScriptDirectory.from_config(config).get_current_head()
        snapshot = None
        journal = self.path.parent / "migration-pending.json"
        with self.write_lock:
            if journal.exists():
                record = json.loads(journal.read_text())
                name = record["snapshot"]
                if (
                    not isinstance(name, str)
                    or Path(name).name != name
                    or not name.endswith(".sqlite3")
                ):
                    raise RuntimeError("Invalid migration recovery record")
                previous = self.path.parent / "migration-snapshots" / name
                self.engine.dispose()
                self.restore_migration_snapshot(previous)
                self.clear_migration_journal(journal)

            if self.path.exists():
                with sqlite3.connect(self.path) as connection:
                    version = connection.execute(
                        "SELECT name FROM sqlite_master WHERE name='alembic_version'"
                    ).fetchone()
                    current = (
                        connection.execute("SELECT version_num FROM alembic_version").fetchone()
                        if version
                        else None
                    )
                    if current and current[0] != head:
                        folder = self.path.parent / "migration-snapshots"
                        folder.mkdir(mode=0o700, exist_ok=True)
                        snapshot = (
                            folder / f"before-{current[0]}-to-{head}-{time.time_ns()}.sqlite3"
                        )
                        fd = os.open(snapshot, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
                        os.close(fd)
                        with sqlite3.connect(snapshot) as target:
                            connection.backup(target)
                            if target.execute("PRAGMA quick_check").fetchone() != ("ok",):
                                raise RuntimeError("Pre-migration snapshot failed integrity check")
                        self.last_migration_snapshot = snapshot
                        temporary = journal.with_suffix(".tmp")
                        with temporary.open("w", encoding="utf-8") as marker:
                            os.chmod(temporary, 0o600)
                            json.dump(
                                {"snapshot": snapshot.name, "from": current[0], "to": head}, marker
                            )
                            marker.flush()
                            os.fsync(marker.fileno())
                        temporary.replace(journal)
                        # Make the snapshot and recovery marker discoverable after a crash.
                        for directory in (folder, self.path.parent):
                            fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
                            try:
                                os.fsync(fd)
                            finally:
                                os.close(fd)
            try:
                with self.engine.begin() as connection:
                    config.attributes["connection"] = connection
                    command.upgrade(config, "head")
                self.clear_migration_journal(journal)
            except Exception:
                # Restore even when SQLite committed some DDL before failure.
                self.engine.dispose()
                if snapshot:
                    self.restore_migration_snapshot(snapshot)
                    self.clear_migration_journal(journal)
                raise

    @staticmethod
    def clear_migration_journal(journal):
        journal.unlink(missing_ok=True)
        fd = os.open(journal.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)

    def restore_migration_snapshot(self, snapshot):
        if not snapshot.is_file():
            raise RuntimeError("Migration recovery snapshot is missing")
        with sqlite3.connect(snapshot) as source:
            if source.execute("PRAGMA quick_check").fetchone() != ("ok",):
                raise RuntimeError("Migration recovery snapshot is corrupt")
            with sqlite3.connect(self.path) as target:
                source.backup(target)

    @contextmanager
    def read(self):
        with Session(self.engine, expire_on_commit=False) as session:
            yield session

    @contextmanager
    def write(self, *, session_control=False):
        with self.write_lock, Session(self.engine, expire_on_commit=False) as session:
            if (
                not session_control
                and self.maintenance_task
                and self.maintenance_owner != get_ident()
            ):
                raise LibraryError("restore_in_progress", "管理数据正在恢复，请稍后重试", 503)
            with session.begin():
                # A SELECT does not begin a transaction in SQLite's legacy
                # driver. Reserve its writer before checking the request lease.
                session.connection().exec_driver_sql("BEGIN IMMEDIATE")
                self.authority.check(session)
                pending = session.get(Setting, "maintenance_restore")
                if (
                    not session_control
                    and pending
                    and pending.value
                    and self.maintenance_owner != get_ident()
                ):
                    raise LibraryError("restore_in_progress", "管理数据正在恢复，请稍后重试", 503)
                yield session

    def check_authority(self):
        # Cheap admission check before reading a large request body. The final
        # check in write() closes the check-to-commit race with restore.
        with self.write_lock, self.read() as session:
            self.authority.check(session)

    def close(self):
        self.engine.dispose()

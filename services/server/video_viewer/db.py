from contextlib import contextmanager
from pathlib import Path
from threading import RLock, get_ident

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session

from .errors import LibraryError


class Database:
    def __init__(self, data_dir: Path):
        data_dir.mkdir(parents=True, exist_ok=True)
        self.engine = create_engine(
            f"sqlite:///{data_dir / 'library.sqlite3'}",
            connect_args={"check_same_thread": False, "timeout": 15},
        )
        self.write_lock = RLock()
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
        with self.engine.begin() as connection:
            config.attributes["connection"] = connection
            command.upgrade(config, "head")

    @contextmanager
    def read(self):
        with Session(self.engine, expire_on_commit=False) as session:
            yield session

    @contextmanager
    def write(self):
        with self.write_lock, Session(self.engine, expire_on_commit=False) as session:
            if self.maintenance_task and self.maintenance_owner != get_ident():
                raise LibraryError("restore_in_progress", "管理数据正在恢复，请稍后重试", 503)
            with session.begin():
                yield session

    def close(self):
        self.engine.dispose()

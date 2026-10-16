from contextlib import contextmanager
from pathlib import Path
from threading import RLock

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session


class Database:
    def __init__(self, data_dir: Path):
        data_dir.mkdir(parents=True, exist_ok=True)
        self.engine = create_engine(
            f"sqlite:///{data_dir / 'library.sqlite3'}",
            connect_args={"check_same_thread": False, "timeout": 15},
        )
        self.write_lock = RLock()

        @event.listens_for(self.engine, "connect")
        def configure(connection, _record):
            connection.execute("PRAGMA foreign_keys=ON")
            connection.execute("PRAGMA busy_timeout=15000")
            # Short serialized writes with the default rollback journal. WAL is
            # unnecessary for the initial single-user service and needs separate
            # runtime/checkpoint/version validation before enabling it.
            connection.execute("PRAGMA journal_mode=DELETE")

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
            with session.begin():
                yield session

    def close(self):
        self.engine.dispose()

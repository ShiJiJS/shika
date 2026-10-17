import os
import subprocess
import sys
import threading

from sqlalchemy import text

from video_viewer.db import Database


def test_wal_readers_see_committed_state_while_a_write_is_open(tmp_path):
    db = Database(tmp_path)
    with db.engine.begin() as connection:
        connection.execute(text("CREATE TABLE probe (id INTEGER PRIMARY KEY, value TEXT)"))
        connection.execute(text("INSERT INTO probe VALUES (1, 'committed')"))
    writing, release = threading.Event(), threading.Event()
    failures = []

    def write():
        try:
            with db.write() as session:
                session.execute(text("UPDATE probe SET value='pending' WHERE id=1"))
                writing.set()
                assert release.wait(10)
        except BaseException as error:
            failures.append(error)

    thread = threading.Thread(target=write)
    thread.start()
    try:
        assert writing.wait(5)
        with db.read() as session:
            session.execute(text("PRAGMA busy_timeout=100"))
            assert session.execute(text("SELECT value FROM probe")).scalar_one() == "committed"
            assert session.execute(text("PRAGMA journal_mode")).scalar_one() == "wal"
            assert session.execute(text("PRAGMA synchronous")).scalar_one() == 2
            assert session.execute(text("PRAGMA wal_autocheckpoint")).scalar_one() == 1000
    finally:
        release.set()
        thread.join(10)
    assert not thread.is_alive() and not failures
    with db.read() as session:
        assert session.execute(text("SELECT value FROM probe")).scalar_one() == "pending"
    db.close()


def test_wal_recovers_committed_data_after_process_crash_and_checkpoints(tmp_path):
    code = """
import os, sys
from pathlib import Path
from sqlalchemy import text
from video_viewer.db import Database
db=Database(Path(sys.argv[1]))
with db.engine.begin() as c:
    c.execute(text("CREATE TABLE probe (value TEXT)"))
    c.execute(text("INSERT INTO probe VALUES ('durable receipt')"))
c=db.engine.connect()
transaction=c.begin()
c.execute(text("INSERT INTO probe VALUES ('uncommitted')"))
os._exit(9)
"""
    child = subprocess.run([sys.executable, "-c", code, str(tmp_path)], env=os.environ.copy())
    assert child.returncode == 9
    db = Database(tmp_path)
    try:
        with db.read() as session:
            assert session.execute(text("SELECT value FROM probe")).scalars().all() == [
                "durable receipt"
            ]
            assert session.execute(text("PRAGMA integrity_check")).scalar_one() == "ok"
        with db.engine.connect().execution_options(isolation_level="AUTOCOMMIT") as connection:
            result = connection.execute(text("PRAGMA wal_checkpoint(TRUNCATE)")).one()
            assert tuple(result) == (0, 0, 0)
        assert (tmp_path / "library.sqlite3-wal").stat().st_size == 0
    finally:
        db.close()

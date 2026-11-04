"""Frozen 0004 evidence must survive current migrations without executing work."""

import hashlib
import json
import sqlite3
from pathlib import Path

from shika.db import Database


def test_frozen_0004_preserves_identity_round_trash_and_pending_command(tmp_path):
    fixtures = Path(__file__).parent / "fixtures"
    sql = (fixtures / "lf0-management-0004.sql").read_bytes()
    expected = json.loads((fixtures / "lf0-management-0004.json").read_text())
    assert hashlib.sha256(sql).hexdigest() == expected["sha256"]
    with sqlite3.connect(tmp_path / "library.sqlite3") as connection:
        connection.executescript(sql.decode())
        names = [
            row[0]
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name!='alembic_version'"
            )
        ]
        columns = {
            name: [row[1] for row in connection.execute(f'PRAGMA table_info("{name}")')]
            for name in names
        }
        before = {
            name: sorted(connection.execute(f'SELECT * FROM "{name}"').fetchall(), key=repr)
            for name in names
        }
    database = Database(tmp_path)
    try:
        database.migrate()
        with sqlite3.connect(tmp_path / "library.sqlite3") as connection:
            for name in names:
                fields = ",".join(f'"{column}"' for column in columns[name])
                assert (
                    sorted(
                        connection.execute(f'SELECT {fields} FROM "{name}"').fetchall(), key=repr
                    )
                    == before[name]
                )
            assert database.last_migration_snapshot is not None
            assert connection.execute("SELECT kind, enabled FROM roots").fetchall() == [
                ("video", 1)
            ]
            assert connection.execute("PRAGMA integrity_check").fetchone() == ("ok",)
            assert connection.execute("PRAGMA foreign_key_check").fetchall() == []
            assert connection.execute("SELECT count(*) FROM videos").fetchone() == (4,)
            assert connection.execute("SELECT count(*) FROM access_tokens").fetchone() == (0,)
            assert connection.execute(
                "SELECT video_id FROM round_entries ORDER BY ordinal"
            ).fetchall() == [(identity,) for identity in expected["round_entries"]]
            assert connection.execute("SELECT cursor FROM playback_rounds").fetchone() == (1,)
            assert connection.execute(
                "SELECT video_id, tag_id FROM video_tags ORDER BY video_id"
            ).fetchall() == [("lf0-v1", "lf0-tag"), ("lf0-v2", "lf0-tag")]
            trash = connection.execute(
                "SELECT id, original_path, trash_path FROM trash_items"
            ).fetchall()
            assert next(row for row in trash if row[0] == expected["logical_trash"])[1:] == (
                "/media/lf0/2.mp4",
                "/media/lf0/2.mp4",
            )
            assert (
                next(row for row in trash if row[0] == expected["legacy_physical_trash"])[1]
                != next(row for row in trash if row[0] == expected["legacy_physical_trash"])[2]
            )
            assert connection.execute(
                "SELECT request_key FROM file_operations WHERE id='lf0-pending'"
            ).fetchone() == (expected["pending_file_command"],)
            assert connection.execute(
                "SELECT status FROM tasks WHERE id='lf0-pending'"
            ).fetchone() == ("queued",)
    finally:
        database.close()

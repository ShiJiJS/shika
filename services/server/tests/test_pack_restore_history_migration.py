"""History never executes; 0011 -> 0012 keeps old management rows byte-for-byte."""

import sqlite3
from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import select

from video_viewer.db import Database
from video_viewer.models import (
    ImagePack,
    PackFileOperation,
    PackRestoreBatch,
    PackRestorePlan,
    Task,
)
from video_viewer.pack_scanner import reserved_packs

from .conftest import connect
from .test_pack_purge_plans import fixture
from .test_pack_restore_plans import gate, submit


def test_historical_parent_and_children_never_resume_or_hold_current_reservations(environment):
    settings, media = environment
    first, token = connect(settings)
    entered, release = gate(first)
    try:
        _, _, rows = fixture(first, media, 5)
        original = submit(first, [r["id"] for r in rows])
        identity = original["id"]
        assert entered.wait(10)
        with first.app.state.db.write() as session:
            session.get(PackRestorePlan, identity).historical = True
            task = session.get(Task, identity)
            task.status, task.error = "interrupted", "restored_history"
            for child in session.scalars(select(PackRestoreBatch.operation_id)):
                session.get(PackFileOperation, child).historical = True
                task = session.get(Task, child)
                task.status, task.error = "interrupted", "restored_history"
        release.set()
        first.app.state.pack_restore_plans.futures[identity].result(timeout=10)
    finally:
        release.set()
        first.__exit__(None, None, None)
    second, _ = connect(settings, token=token)
    try:
        assert not second.app.state.pack_restore_plans.futures
        assert not second.app.state.pack_files.futures
        receipt = second.get("/api/v1/pack-restore-requests/whole").json()
        assert receipt["id"] == identity and receipt["historical"]
        assert second.get(f"/api/v1/maintenance-tasks/{identity}").json()["state"] == "historical"
        assert (
            second.post(
                f"/api/v1/pack-restore-plans/{identity}/stop", json={"request_id": "history-stop"}
            ).status_code
            == 404
        )
        assert submit(second, [r["id"] for r in rows])["id"] == identity
        with second.app.state.db.read() as session:
            assert not set(session.scalars(reserved_packs()))
            assert {p.generation for p in session.scalars(select(ImagePack))} == {2}
        assert second.get("/api/v1/pack-trash").json()["total"] == 5
    finally:
        second.__exit__(None, None, None)


def test_0011_upgrade_preserves_old_pack_and_video_tables_and_snapshots_before_ddl(environment):
    settings, media = environment
    client, _ = connect(settings)
    try:
        fixture(client, media, 2)
    finally:
        client.__exit__(None, None, None)
    db = Database(settings.data_dir)
    config = Config(str(Path(__file__).parents[1] / "alembic.ini"))
    config.set_main_option("script_location", str(Path(__file__).parents[1] / "migrations"))
    with db.engine.begin() as connection:
        config.attributes["connection"] = connection
        command.downgrade(config, "0011")
    with sqlite3.connect(db.path) as connection:
        tables = [
            r[0]
            for r in connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name!='alembic_version'"
            )
        ]
        before = {t: connection.execute(f'SELECT * FROM "{t}"').fetchall() for t in tables}
        assert connection.execute("SELECT version_num FROM alembic_version").fetchone() == ("0011",)
    db.migrate()
    try:
        with sqlite3.connect(db.path) as connection:
            assert all(
                connection.execute(f'SELECT * FROM "{t}"').fetchall() == rows
                for t, rows in before.items()
            )
            assert connection.execute("SELECT version_num FROM alembic_version").fetchone() == (
                "0012",
            )
            for table in ("pack_restore_plans", "pack_restore_members", "pack_restore_batches"):
                assert connection.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone() == (0,)
            assert connection.execute("PRAGMA foreign_key_check").fetchall() == []
        assert db.last_migration_snapshot.is_file()
    finally:
        db.close()

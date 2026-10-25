"""Immutable history bundles: bounded task views, members and original receipts.

Only inspected logical graphs enter this module. Nothing here can enqueue work,
write an active library, resolve a media path, or replay a historical command.
The restore coordinator will publish a bundle reference with its library commit;
preparing a bundle alone does not make it the current service's history.
"""

import hashlib
import json
import os
import sqlite3
import tempfile
import uuid
from contextlib import closing, contextmanager
from pathlib import Path
from threading import RLock

from sqlalchemy import case, create_engine, select
from sqlalchemy.orm import Session

from .backup_archive import ArchiveGraph, _check, _private_file, _sync_directory, file_hash
from .backup_format import canonical
from .backup_v2_schema import TABLE_MAP
from .errors import LibraryError
from .file_transfer import rename_new
from .maintenance_tasks import MaintenanceTasks
from .models import PackRestoreBatch, Task
from .paths import open_regular, signature

# Namespace and keys stay distinct: a settings receipt is not a file command,
# and the same string in two command families must not alias.
RECEIPTS = {
    "request_records": ("id", "id", "fingerprint"),
    "file_operations": ("request_key", "id", "request_hash"),
    "pack_file_operations": ("request_key", "id", "request_hash"),
    "pack_restore_plans": ("request_key", "id", "request_hash"),
    "pack_purge_plans": ("request_key", "id", "request_hash"),
    "pack_missing_cleanups": ("request_id", "id", None),
    "playback_rounds": ("request_id", "id", "request_hash"),
    "pack_sessions": ("request_id", "id", "request_hash"),
}


def _missing():
    raise LibraryError("history_not_found", "原历史记录不存在；未重新提交", 404)


def _page(offset, limit):
    if (
        type(offset) is not int
        or not 0 <= offset < 2**63
        or type(limit) is not int
        or not 1 <= limit <= 100
    ):
        raise ValueError("Invalid history page")


@contextmanager
def _engine(path):
    engine = create_engine(
        "sqlite://",
        creator=lambda: sqlite3.connect(Path(path).as_uri() + "?mode=ro&immutable=1", uri=True),
    )
    try:
        yield engine
    finally:
        engine.dispose()


class _ReadOnlyGraph:
    def __init__(self, engine):
        self.engine = engine
        self.write_lock = RLock()

    @contextmanager
    def read(self):
        with Session(self.engine, expire_on_commit=False) as session:
            yield session


def _copy_graph(graph, path, check):
    """Check the bytes actually copied against the inspected manifest digest."""
    if not graph.digest:
        raise ValueError("History requires an inspected graph digest")
    _private_file(path)
    digest = hashlib.sha256()
    with open_regular(graph.database) as descriptor:
        before = signature(os.fstat(descriptor))
        with path.open("wb") as output:
            while chunk := os.read(descriptor, 1024 * 1024):
                _check(check)
                output.write(chunk)
                digest.update(chunk)
            output.flush()
            os.fsync(output.fileno())
        if signature(os.fstat(descriptor)) != before or digest.hexdigest() != graph.digest:
            raise LibraryError("backup_artifact_changed", "历史数据在校验后已变化", 409)


def _index_graph(index, identity, database, check):
    with _engine(database) as engine, engine.connect() as connection:
        statement = MaintenanceTasks.summaries().add_columns(
            case((Task.id.not_in(select(PackRestoreBatch.operation_id)), 1), else_=0).label(
                "listed"
            )
        )
        for row in connection.execution_options(yield_per=1).execute(statement).mappings():
            _check(check)
            summary = dict(row)
            listed = summary.pop("listed")
            summary.update(historical=True, state="historical")
            index.execute(
                "INSERT INTO history_tasks VALUES(?,?,?,?,?,?,?)",
                (
                    identity,
                    row["id"],
                    row["family"],
                    row["created_at"],
                    listed,
                    row["kind"],
                    canonical(summary).decode(),
                ),
            )
        for namespace, (key, subject, fingerprint) in RECEIPTS.items():
            table = TABLE_MAP[namespace]
            columns = [table.c[key], table.c[subject]]
            if fingerprint:
                columns.append(table.c[fingerprint])
            for row in connection.execution_options(yield_per=1).execute(select(*columns)):
                _check(check)
                index.execute(
                    "INSERT INTO history_receipts VALUES(?,?,?,?,?)",
                    (identity, namespace, row[0], row[1], row[2] if fingerprint else None),
                )


class HistoryArchive:
    """One completed bundle; callers select graph IDs to disambiguate old IDs.

    Sources are ordered oldest to newest. A source's library wins over its own
    history. Unscoped task/receipt lookups choose the latest graph containing
    that identity, while explicit graph lookups retain every earlier result.
    No lookup falls back to an older matching family after a newer ID wins.
    """

    def __init__(self, directory):
        self.directory = Path(directory).absolute()
        with self._index() as index:
            complete = index.execute(
                "SELECT value FROM history_info WHERE key='complete'"
            ).fetchone()
        if not complete or json.loads(complete[0]).get("version") != 1:
            raise LibraryError("history_incomplete", "历史索引尚未完成", 409)

    @contextmanager
    def _index(self):
        with closing(
            sqlite3.connect(
                (self.directory / "index.sqlite3").as_uri() + "?mode=ro&immutable=1", uri=True
            )
        ) as index:
            index.row_factory = sqlite3.Row
            yield index

    @classmethod
    def prepare(cls, sources, destination, *, check=None):
        """Copy validated graphs and build a scalar index before atomic publish.

        Does not consume sources or overwrite a previous bundle. A crash can
        leave an unreferenced preparation folder, never a completed destination.
        The parent restore journal owns eventual cleanup of such orphan folders.
        """
        destination = Path(destination).absolute()
        if destination.exists() or destination.is_symlink():
            raise FileExistsError(destination)
        with tempfile.TemporaryDirectory(
            prefix="history-prepare-", dir=destination.parent
        ) as temporary:
            folder = Path(temporary)
            index_path = folder / "index.sqlite3"
            _private_file(index_path)
            with closing(sqlite3.connect(index_path)) as index:
                index.execute("PRAGMA synchronous=FULL")
                index.executescript("""
                    CREATE TABLE history_info(key TEXT PRIMARY KEY,value TEXT NOT NULL);
                    CREATE TABLE history_graphs(identity TEXT PRIMARY KEY,filename TEXT NOT NULL,digest TEXT NOT NULL,mounts TEXT NOT NULL,source_order INTEGER NOT NULL,was_library INTEGER NOT NULL,ordinal INTEGER NOT NULL);
                    CREATE TABLE history_tasks(graph_id TEXT NOT NULL,id TEXT NOT NULL,family TEXT NOT NULL,created_at REAL NOT NULL,listed INTEGER NOT NULL,kind TEXT NOT NULL,summary TEXT NOT NULL,PRIMARY KEY(graph_id,id));
                    CREATE INDEX history_task_identity ON history_tasks(id,graph_id);
                    CREATE INDEX history_task_page ON history_tasks(listed,created_at DESC,id DESC,graph_id);
                    CREATE TABLE history_receipts(graph_id TEXT NOT NULL,namespace TEXT NOT NULL,request_key TEXT NOT NULL,subject TEXT NOT NULL,fingerprint TEXT,PRIMARY KEY(graph_id,namespace,request_key));
                    CREATE INDEX history_receipt_identity ON history_receipts(namespace,request_key,graph_id);
                """)
                for source_order, source in enumerate(sources):
                    for ordinal, graph in enumerate(source.graphs()):
                        _check(check)
                        identity = str(uuid.uuid4()) if graph.kind == "library" else graph.identity
                        mounts = canonical(graph.mounts).decode()
                        prior = index.execute(
                            "SELECT digest,mounts FROM history_graphs WHERE identity=?", (identity,)
                        ).fetchone()
                        if prior:
                            if prior != (graph.digest, mounts):
                                raise LibraryError(
                                    "history_identity_conflict", "同一历史图的内容不一致", 409
                                )
                            index.execute(
                                "UPDATE history_graphs SET source_order=?,was_library=0,ordinal=? WHERE identity=?",
                                (source_order, ordinal, identity),
                            )
                            continue
                        filename = str(uuid.uuid4()) + ".sqlite3"
                        path = folder / filename
                        _copy_graph(graph, path, check)
                        index.execute(
                            "INSERT INTO history_graphs VALUES(?,?,?,?,?,?,?)",
                            (
                                identity,
                                filename,
                                graph.digest,
                                mounts,
                                source_order,
                                graph.kind == "library",
                                ordinal,
                            ),
                        )
                        _index_graph(index, identity, path, check)
                _check(check)
                index.execute(
                    "INSERT INTO history_info VALUES('complete',?)", (json.dumps({"version": 1}),)
                )
                index.commit()
            _sync_directory(folder)
            _check(check)
            rename_new(folder, destination)
            _sync_directory(destination.parent)
        return cls(destination)

    def _path(self, row, *, verify=True):
        path = self.directory / row["filename"]
        if path.parent != self.directory or path.suffix != ".sqlite3":
            raise LibraryError("history_artifact_changed", "历史图路径不正确", 409)
        if verify and file_hash(path) != row["digest"]:
            raise LibraryError("history_artifact_changed", "历史图已变化", 409)
        return path

    def graphs(self, *, verify=True):
        with self._index() as index:
            for row in index.execute(
                "SELECT * FROM history_graphs ORDER BY source_order,was_library,ordinal"
            ):
                path = self._path(row, verify=False)
                if verify and file_hash(path) != row["digest"]:
                    raise LibraryError("history_artifact_changed", "历史图已变化", 409)
                yield ArchiveGraph(
                    row["identity"], "history", path, json.loads(row["mounts"]), row["digest"]
                )

    @staticmethod
    def _projection(table, alias):
        # A later restored library can contain non-executable FK provenance
        # projections of an older operation. Prefer its exact original history
        # over that projection; explicit graph lookups still return that graph.
        if table == "history_tasks":
            return f"coalesce(json_extract({alias}.summary,'$.error')='restored_history',0)"
        return f"EXISTS(SELECT 1 FROM history_tasks projection WHERE projection.graph_id={alias}.graph_id AND projection.id={alias}.subject AND json_extract(projection.summary,'$.error')='restored_history')"

    @staticmethod
    def _latest(table, keys):
        # All identifiers originate in code; external identities are bound values.
        same = " AND ".join(f"newer.{key}=item.{key}" for key in keys)
        return f"""NOT EXISTS(SELECT 1 FROM {table} newer
            JOIN history_graphs ng ON ng.identity=newer.graph_id
            WHERE {same} AND
            (-({HistoryArchive._projection(table, "newer")}),ng.source_order,ng.was_library,ng.ordinal)>
            (-({HistoryArchive._projection(table, "item")}),g.source_order,g.was_library,g.ordinal))"""

    def tasks(self, *, offset=0, limit=24, family="all", graph_id=None, current_database=None):
        _page(offset, limit)
        if family not in {"all", "scan", "video", "pack", "backup", "other"}:
            raise ValueError("Invalid history family")
        where, params = ["item.listed=1"], []
        if graph_id is None:
            where.append(self._latest("history_tasks", ("id",)))
            if current_database is not None:
                where.append(
                    "NOT EXISTS(SELECT 1 FROM current_library.tasks live WHERE live.id=item.id AND substr(live.kind,1,7)='backup_' AND coalesce(live.error,'')<>'restored_history')"
                )
        else:
            where.append("item.graph_id=?")
            params.append(graph_id)
        if family != "all":
            where.append("item.family=?")
            params.append(family)
        query = (
            "FROM history_tasks item JOIN history_graphs g ON g.identity=item.graph_id WHERE "
            + " AND ".join(where)
        )
        with self._index() as index:
            if graph_id is None and current_database is not None:
                index.execute(
                    "ATTACH DATABASE ? AS current_library",
                    (Path(current_database).absolute().as_uri() + "?mode=ro",),
                )
            total = index.execute("SELECT count(*) " + query, params).fetchone()[0]
            rows = index.execute(
                "SELECT item.summary,item.graph_id "
                + query
                + " ORDER BY item.created_at DESC,item.id DESC,item.graph_id DESC LIMIT ? OFFSET ?",
                (*params, limit, offset),
            )
            items = [{**json.loads(row[0]), "graph_id": row[1]} for row in rows]
        return {"items": items, "total": total, "offset": offset, "limit": limit}

    def _locate(self, table, where, params, graph_id):
        if graph_id is not None:
            where += " AND item.graph_id=?"
            params = (*params, graph_id)
        with self._index() as index:
            row = index.execute(
                f"SELECT item.*,g.filename,g.digest FROM {table} item JOIN history_graphs g ON g.identity=item.graph_id WHERE {where} ORDER BY {self._projection(table, 'item')} ASC,g.source_order DESC,g.was_library DESC,g.ordinal DESC LIMIT 1",
                params,
            ).fetchone()
        if row is None:
            _missing()
        return row

    def task(self, identity, *, graph_id=None):
        row = self._locate("history_tasks", "item.id=?", (identity,), graph_id)
        return {**json.loads(row["summary"]), "graph_id": row["graph_id"]}

    def task_record(self, identity, *, graph_id=None):
        row = self._locate("history_tasks", "item.id=?", (identity,), graph_id)
        with _engine(self._path(row)) as engine, engine.connect() as connection:
            task = (
                connection.execute(select(Task.__table__).where(Task.id == identity))
                .mappings()
                .first()
            )
        if task is None:
            _missing()
        return {**dict(task), "historical": True, "graph_id": row["graph_id"]}

    def members(self, identity, *, offset=0, limit=24, unfinished=False, graph_id=None):
        _page(offset, limit)
        if type(unfinished) is not bool:
            raise ValueError("Invalid unfinished filter")
        row = self._locate("history_tasks", "item.id=?", (identity,), graph_id)
        with _engine(self._path(row)) as engine:
            result = MaintenanceTasks(_ReadOnlyGraph(engine)).items(
                identity, offset, limit, unfinished
            )
        return {**result, "historical": True, "graph_id": row["graph_id"]}

    def operation(self, namespace, identity):
        if namespace not in RECEIPTS or namespace in {
            "request_records",
            "playback_rounds",
            "pack_sessions",
        }:
            raise ValueError("Not an operation receipt namespace")
        row = self._locate(
            "history_receipts", "item.namespace=? AND item.subject=?", (namespace, identity), None
        )
        return self.receipt(namespace, row["request_key"], graph_id=row["graph_id"])

    def receipt(self, namespace, request_key, *, graph_id=None):
        """Explicit original receipt read; list queries never materialize results.

        A single requested historical result may be large, within the archive's
        per-record bound. This is not a new command or a promise of source bytes.
        Public route-specific response adapters remain with the coordinator.
        """
        if namespace not in RECEIPTS:
            raise ValueError("Unknown receipt namespace")
        row = self._locate(
            "history_receipts",
            "item.namespace=? AND item.request_key=?",
            (namespace, request_key),
            graph_id,
        )
        table = TABLE_MAP[namespace]
        _, subject, _ = RECEIPTS[namespace]
        with _engine(self._path(row)) as engine, engine.connect() as connection:
            record = (
                connection.execute(select(table).where(table.c[subject] == row["subject"]))
                .mappings()
                .first()
            )
            if record is None:
                _missing()
            task = None
            if namespace in {
                "file_operations",
                "pack_file_operations",
                "pack_restore_plans",
                "pack_purge_plans",
                "pack_missing_cleanups",
            }:
                task = (
                    connection.execute(select(Task.__table__).where(Task.id == row["subject"]))
                    .mappings()
                    .first()
                )
        return {
            "historical": True,
            "graph_id": row["graph_id"],
            "namespace": namespace,
            "request_key": request_key,
            "fingerprint": row["fingerprint"],
            # Original results remain exact; every projected command envelope
            # is historical even if its frozen source flag was still active.
            "record": {**dict(record), "historical": True},
            "task": {**dict(task), "historical": True} if task else None,
        }

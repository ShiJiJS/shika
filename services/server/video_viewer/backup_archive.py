"""Streaming v2 logical graphs. Only validated records become private SQLite data."""

import hashlib
import json
import os
import shutil
import sqlite3
import tempfile
import time
import uuid
from contextlib import ExitStack, closing, contextmanager
from dataclasses import dataclass
from pathlib import Path

from sqlalchemy import create_engine, func, select
from sqlalchemy.exc import IntegrityError, StatementError

from .backup_format import FORMAT, canonical, invalid, unique_pairs
from .backup_format import TABLES as LEGACY_TABLES
from .backup_format import decode as decode_v1
from .backup_v2_schema import (
    SCHEMA,
    TABLE_MAP,
    TABLES,
    finite,
    sanitized,
    settings_from,
    validate_graph,
    validate_mounts,
    validate_row,
    validate_settings,
)
from .errors import LibraryError
from .file_transfer import rename_new
from .models import Base, Root, Setting, Video
from .paths import open_regular, signature

VERSION = 2
MAX_RECORD_BYTES = 256 * 1024 * 1024
_ENCODER = json.JSONEncoder(
    ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False
)


def _check(callback):
    if callback:
        callback()


def file_hash(path):
    result = hashlib.sha256()
    with open_regular(Path(path)) as fd:
        while chunk := os.read(fd, 1024 * 1024):
            result.update(chunk)
    return result.hexdigest()


def _private_file(path):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    os.close(fd)


def _sync_directory(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _readonly(path):
    return create_engine(
        "sqlite://",
        creator=lambda: sqlite3.connect(
            Path(path).as_uri() + "?mode=ro&immutable=1",
            uri=True,
        ),
    )


def _omit_discovery(target):
    # CASCADE relationships must not silently drop user state. Staging has no
    # references outside its own pages; contrary evidence waits for a sync.
    for table in TABLES:
        for reference in table.foreign_keys:
            parent = reference.column.table.name
            if parent not in ("packs", "videos") or table.name == "pack_pages":
                continue
            statement = (
                f'SELECT 1 FROM "{table.name}" WHERE "{reference.parent.name}" IN '
                f'(SELECT id FROM "{parent}" WHERE status=?) LIMIT 1'
            )
            if target.execute(statement, ("discovered",)).fetchone():
                raise LibraryError(
                    "backup_library_scanning", "扫描暂存仍有管理关联，请完成同步后再备份", 409
                )
    target.execute("PRAGMA foreign_keys=ON")
    try:
        target.execute("DELETE FROM packs WHERE status='discovered'")
        target.execute("DELETE FROM videos WHERE status='discovered'")
        target.commit()
    except sqlite3.IntegrityError:
        raise LibraryError(
            "backup_library_scanning", "扫描暂存仍有管理关联，请完成同步后再备份", 409
        ) from None


@dataclass(frozen=True)
class ArchiveGraph:
    identity: str
    kind: str
    database: Path
    mounts: list


@contextmanager
def freeze_graph(db, mounts, directory, *, check=None):
    """Online consistent copy; private snapshot is removed even on cancellation.

    No main-library write lock or long-lived application read transaction is
    held while SQLite's online backup copies pages. Callers may additionally
    use check() to cancel their owning task.
    """
    with tempfile.TemporaryDirectory(prefix="snapshot-", dir=directory) as temporary:
        path = Path(temporary) / "source.sqlite3"
        _private_file(path)
        started = time.monotonic()

        def progress(_status, _remaining, _total):
            _check(check)
            if time.monotonic() - started > 300:
                raise LibraryError("backup_busy", "当前写入繁忙，请稍后重试备份", 409)

        with closing(sqlite3.connect(db.path.as_uri() + "?mode=ro", uri=True)) as source:
            with closing(sqlite3.connect(path)) as target:
                source.backup(target, pages=256, progress=progress, sleep=0.01)
                # Discovered identities have not been published and have no
                # user/command references. Remove only this private copy's
                # staging rows, with FK enforcement to catch contrary evidence.
                _omit_discovery(target)
                if target.execute("PRAGMA quick_check").fetchone() != ("ok",):
                    invalid("管理快照校验失败")
        yield ArchiveGraph("library", "library", path, mounts)


class _Output:
    def __init__(self, stream, maximum):
        self.stream, self.maximum = stream, maximum
        self.size = 0
        self.file_digest, self.body_digest = hashlib.sha256(), hashlib.sha256()

    def record(self, value, *, signed=True):
        count = 0
        for text in _ENCODER.iterencode(value):
            chunk = text.encode("utf-8")
            count += len(chunk)
            if count > min(self.maximum, MAX_RECORD_BYTES):
                raise LibraryError("backup_record_too_large", "备份中单条管理记录超出限制", 413)
            self._write(chunk, signed)
        if count + 1 > min(self.maximum, MAX_RECORD_BYTES):
            raise LibraryError("backup_record_too_large", "备份中单条管理记录超出限制", 413)
        self._write(b"\n", signed)

    def _write(self, chunk, signed):
        self.size += len(chunk)
        if self.size > self.maximum:
            raise LibraryError("backup_too_large", "备份超过当前大小限制", 413)
        self.stream.write(chunk)
        self.file_digest.update(chunk)
        if signed:
            self.body_digest.update(chunk)


def _validate_graph_identity(kind, identity):
    if kind not in ("library", "history") or not isinstance(identity, str):
        invalid("备份数据图标识不正确")
    if kind == "library":
        if identity != "library":
            invalid()
    else:
        try:
            if str(uuid.UUID(identity)) != identity:
                invalid()
        except ValueError:
            invalid()


def _graph_header(graph, connection):
    _validate_graph_identity(graph.kind, graph.identity)
    validate_mounts(graph.mounts)
    preferences = settings_from(connection)
    validate_graph(connection, preferences)
    return {
        "record": "graph",
        "id": graph.identity,
        "kind": graph.kind,
        "mounts": graph.mounts,
        "settings": preferences,
    }


def write_v2(destination, graphs, *, maximum_bytes, check=None):
    """Write immutable logical graphs without loading a library into a list.

    Graph inputs are our own frozen snapshots/staging databases, never a user
    supplied SQLite file. No overwrite; partial files cannot become artifacts.
    """
    destination = Path(destination)
    temporary = destination.with_name("." + uuid.uuid4().hex + ".tmp")
    _private_file(temporary)
    identities, graph_count = set(), 0
    try:
        with temporary.open("wb") as stream:
            output = _Output(stream, maximum_bytes)
            created = time.time()
            output.record(
                {
                    "record": "header",
                    "format": FORMAT,
                    "version": VERSION,
                    "schema": SCHEMA,
                    "created_at": created,
                }
            )
            for graph in graphs:
                _check(check)
                _validate_graph_identity(graph.kind, graph.identity)
                if graph.identity in identities or (graph.kind == "library") != (graph_count == 0):
                    invalid("备份必须有且仅有一个首位媒体库数据图")
                identities.add(graph.identity)
                engine = _readonly(graph.database)
                try:
                    with engine.connect() as connection:
                        output.record(_graph_header(graph, connection))
                        counts = {}
                        for table in TABLES:
                            count = 0
                            result = connection.execution_options(yield_per=100).execute(
                                select(table).order_by(*table.primary_key.columns)
                            )
                            for value in result.mappings():
                                _check(check)
                                row = sanitized(table.name, value)
                                validate_row(table.name, row)
                                output.record({"record": "row", "table": table.name, "value": row})
                                count += 1
                            counts[table.name] = count
                        output.record({"record": "graph_end", "counts": counts})
                finally:
                    engine.dispose()
                graph_count += 1
            if not graph_count:
                invalid("备份没有媒体库数据图")
            checksum = output.body_digest.hexdigest()
            output.record(
                {"record": "complete", "sha256": checksum, "graphs": graph_count}, signed=False
            )
            stream.flush()
            os.fsync(stream.fileno())
            details = {
                "version": VERSION,
                "schema": SCHEMA,
                "checksum": checksum,
                "file_sha256": output.file_digest.hexdigest(),
                "bytes": output.size,
                "graphs": graph_count,
                "created_at": created,
            }
        _check(check)
        os.link(temporary, destination, follow_symlinks=False)
        _sync_directory(destination.parent)
        return details
    finally:
        temporary.unlink(missing_ok=True)


def _load(line):
    try:
        value = json.loads(
            line, object_pairs_hook=unique_pairs, parse_constant=lambda _value: invalid()
        )
        if not isinstance(value, dict):
            invalid()
        return value
    except (ValueError, TypeError, RecursionError, UnicodeError):
        invalid()


def _same_keys(value, keys):
    if set(value) != set(keys):
        invalid("备份记录字段不完整")


class StagedArchive:
    """Durable inspected graphs; only scalar/paged metadata is exposed."""

    def __init__(self, directory):
        self.directory = Path(directory).absolute()
        with self._index() as connection:
            item = connection.execute(
                "SELECT value FROM archive_info WHERE key='complete'"
            ).fetchone()
        if not item:
            invalid("备份尚未完整校验")
        self.details = json.loads(item[0])

    @contextmanager
    def _index(self):
        with closing(
            sqlite3.connect((self.directory / "index.sqlite3").as_uri() + "?mode=ro", uri=True)
        ) as connection:
            yield connection

    def graphs(self, *, verify=True):
        with self._index() as connection:
            cursor = connection.execute(
                "SELECT identity,kind,filename,header,digest FROM archive_graphs ORDER BY ordinal"
            )
            for identity, kind, filename, header, digest in cursor:
                path = self.directory / filename
                if (
                    path.parent != self.directory
                    or path.suffix != ".sqlite3"
                    or (verify and file_hash(path) != digest)
                ):
                    raise LibraryError("backup_artifact_changed", "备份暂存数据在校验后已变化", 409)
                yield ArchiveGraph(identity, kind, path, json.loads(header)["mounts"])

    def counts(self, identity="library"):
        with self._index() as connection:
            row = connection.execute(
                "SELECT counts FROM archive_graphs WHERE identity=?", (identity,)
            ).fetchone()
        if not row:
            invalid("备份数据图不存在")
        return json.loads(row[0])

    def roots(self, *, offset=0, limit=24):
        if (
            type(offset) is not int
            or not 0 <= offset < 2**63
            or type(limit) is not int
            or not 1 <= limit <= 100
        ):
            raise ValueError("Invalid root page")
        # Inspection already verified the bytes. Preview pages read bounded
        # rows; full digest revalidation belongs to confirmation/application.
        graph = next(self.graphs(verify=False))
        engine = _readonly(graph.database)
        try:
            with engine.connect() as connection:
                total = connection.scalar(select(func.count()).select_from(Root))
                rows = connection.execute(
                    select(Root.__table__).order_by(Root.path, Root.id).offset(offset).limit(limit)
                ).mappings()
                return {"total": total, "offset": offset, "items": [dict(row) for row in rows]}
        finally:
            engine.dispose()


def inspect_v2(source, destination, *, maximum_bytes, check=None):
    """Validate the entire stream before returning an independently usable graph.

    Invalid/cancelled input removes only this newly-created staging directory.
    No import SQL, credentials or media bytes are ever executed or copied.
    """
    destination = Path(destination)
    destination.mkdir(mode=0o700)  # Refuse existing directories, never erase another preview.
    engine = connection = index = None
    success = False
    try:
        index_path = destination / "index.sqlite3"
        _private_file(index_path)
        index = sqlite3.connect(index_path)
        index.execute("CREATE TABLE archive_info(key TEXT PRIMARY KEY,value TEXT NOT NULL)")
        index.execute(
            "CREATE TABLE archive_graphs(ordinal INTEGER PRIMARY KEY,identity TEXT UNIQUE NOT NULL,kind TEXT NOT NULL,filename TEXT NOT NULL,header TEXT NOT NULL,digest TEXT,counts TEXT)"
        )
        digest, file_digest, byte_count = hashlib.sha256(), hashlib.sha256(), 0
        graph_count, current, counts, completed = 0, None, None, False
        with open_regular(Path(source)) as fd:
            before = signature(os.fstat(fd))
            if before[2] > maximum_bytes:
                raise LibraryError("backup_too_large", "备份超过当前大小限制", 413)
            with os.fdopen(fd, "rb", closefd=False) as stream:
                ordinal = 0
                while line := stream.readline(min(maximum_bytes, MAX_RECORD_BYTES) + 1):
                    _check(check)
                    byte_count += len(line)
                    if byte_count > maximum_bytes:
                        raise LibraryError("backup_too_large", "备份超过当前大小限制", 413)
                    if len(line) > MAX_RECORD_BYTES:
                        raise LibraryError(
                            "backup_record_too_large", "备份中单条管理记录超出限制", 413
                        )
                    if not line.endswith(b"\n") or completed:
                        invalid("备份被截断或含有多余内容")
                    value = _load(line)
                    record = value.get("record")
                    if ordinal == 0:
                        _same_keys(value, ("record", "format", "version", "schema", "created_at"))
                        if (
                            record != "header"
                            or value["format"] != FORMAT
                            or type(value["version"]) is not int
                            or value["version"] != VERSION
                            or value["schema"] != SCHEMA
                        ):
                            raise LibraryError(
                                "backup_version_unsupported", "备份类型或版本不兼容", 422
                            )
                        if not finite(value["created_at"]):
                            invalid()
                        created_at = value["created_at"]
                    elif record == "graph":
                        if current is not None:
                            invalid("备份数据图未结算")
                        _same_keys(value, ("record", "id", "kind", "mounts", "settings"))
                        if value["kind"] not in ("library", "history") or (
                            value["kind"] == "library"
                        ) != (graph_count == 0):
                            invalid()
                        _validate_graph_identity(value["kind"], value["id"])
                        validate_mounts(value["mounts"])
                        validate_settings(value["settings"])
                        current, counts = value, {table.name: 0 for table in TABLES}
                        filename = uuid.uuid4().hex + ".sqlite3"
                        graph_path = destination / filename
                        _private_file(graph_path)
                        engine = create_engine(f"sqlite:///{graph_path}")
                        connection = engine.connect()
                        Base.metadata.create_all(connection)
                        for key, setting in value["settings"].items():
                            connection.execute(
                                Setting.__table__.insert().values(
                                    key=key,
                                    value=setting
                                    if key
                                    in (
                                        "active_round",
                                        "active_pack_session",
                                        "last_delete_operation",
                                    )
                                    and setting
                                    else ""
                                    if setting is None
                                    else canonical(setting).decode(),
                                )
                            )
                        index.execute(
                            "INSERT INTO archive_graphs(ordinal,identity,kind,filename,header) VALUES(?,?,?,?,?)",
                            (
                                graph_count,
                                value["id"],
                                value["kind"],
                                filename,
                                canonical(value).decode(),
                            ),
                        )
                    elif record == "row":
                        _same_keys(value, ("record", "table", "value"))
                        if current is None:
                            invalid()
                        validate_row(value["table"], value["value"])
                        connection.execute(TABLE_MAP[value["table"]].insert(), value["value"])
                        counts[value["table"]] += 1
                    elif record == "graph_end":
                        _same_keys(value, ("record", "counts"))
                        if (
                            current is None
                            or not isinstance(value["counts"], dict)
                            or value["counts"] != counts
                            or any(type(v) is not int for v in value["counts"].values())
                        ):
                            invalid("备份数据图计数不一致")
                        validate_graph(connection, current["settings"])
                        connection.commit()
                        connection.close()
                        connection = None
                        engine.dispose()
                        engine = None
                        index.execute(
                            "UPDATE archive_graphs SET digest=?,counts=? WHERE identity=?",
                            (file_hash(graph_path), canonical(counts).decode(), current["id"]),
                        )
                        graph_count += 1
                        current = counts = None
                    elif record == "complete":
                        _same_keys(value, ("record", "graphs", "sha256"))
                        if (
                            current is not None
                            or not graph_count
                            or type(value["graphs"]) is not int
                            or value["graphs"] != graph_count
                        ):
                            invalid()
                        if value["sha256"] != digest.hexdigest():
                            raise LibraryError(
                                "backup_checksum_mismatch", "备份完整性校验失败", 422
                            )
                        completed = True
                    else:
                        invalid()
                    if not completed:
                        digest.update(line)
                    file_digest.update(line)
                    ordinal += 1
            if signature(os.fstat(fd)) != before:
                raise LibraryError("backup_artifact_changed", "备份文件在校验时发生变化", 409)
        if not completed:
            invalid("备份未完整写入")
        details = {
            "version": VERSION,
            "schema": SCHEMA,
            "bytes": byte_count,
            "checksum": digest.hexdigest(),
            "file_sha256": file_digest.hexdigest(),
            "graphs": graph_count,
            "created_at": created_at,
        }
        _sync_directory(destination)
        index.execute(
            "INSERT INTO archive_info VALUES('complete',?)", (canonical(details).decode(),)
        )
        index.commit()
        index.close()
        index = None
        _sync_directory(destination)
        _check(check)
        staged = StagedArchive(destination)
        success = True
        return staged
    except (IntegrityError, StatementError, sqlite3.IntegrityError, OverflowError):
        invalid("备份关联或唯一约束不完整")
    except (ValueError, TypeError, KeyError, RecursionError, UnicodeError):
        invalid()
    finally:
        with ExitStack() as cleanup:
            if not success:
                cleanup.callback(shutil.rmtree, destination)
            if index is not None:
                cleanup.callback(index.close)
            if engine is not None:
                cleanup.callback(engine.dispose)
            if connection is not None:
                cleanup.callback(connection.close)


def inspect_backup(source, destination, *, maximum_bytes, check=None):
    """Version seam: validate v1 first, normalize into the same staged graph.

    Legacy JSON retains its original supported 256MiB ceiling and validator.
    v2 never uses this whole-document compatibility parser. Neither version
    accepts an external SQLite database or executes imported statements.
    """
    with open_regular(Path(source)) as fd:
        prefix = os.read(fd, 4096).split(b"\n", 1)[0]
    try:
        head = json.loads(prefix)
    except (ValueError, RecursionError, UnicodeError):
        head = None
    if isinstance(head, dict) and (
        head.get("record") == "header" or head.get("version") == VERSION
    ):
        return inspect_v2(source, destination, maximum_bytes=maximum_bytes, check=check)
    maximum_legacy = min(maximum_bytes, MAX_RECORD_BYTES)
    with open_regular(Path(source)) as fd:
        before = signature(os.fstat(fd))
        if before[2] > maximum_legacy:
            raise LibraryError("backup_too_large", "旧版备份超过支持的大小限制", 413)
        with os.fdopen(fd, "rb", closefd=False) as stream:
            raw = stream.read(before[2] + 1)
        if signature(os.fstat(fd)) != before:
            raise LibraryError("backup_artifact_changed", "备份文件在校验时发生变化", 409)
    _check(check)
    document = decode_v1(raw)
    original = {
        "version": document["version"],
        "schema": document["payload"]["schema"],
        "created_at": document["created_at"],
        "checksum": document["sha256"],
        "file_sha256": hashlib.sha256(raw).hexdigest(),
        "bytes": len(raw),
        "normalized_version": VERSION,
        "normalized_schema": SCHEMA,
        "graphs": 1,
    }
    del raw
    destination = Path(destination)
    with tempfile.TemporaryDirectory(prefix="convert-v1-", dir=destination.parent) as temporary:
        path = Path(temporary) / "legacy.sqlite3"
        _private_file(path)
        engine = create_engine(f"sqlite:///{path}")
        try:
            with engine.begin() as connection:
                Base.metadata.create_all(connection)
                payload = document["payload"]
                mounts = payload["mounts"]
                for table in LEGACY_TABLES:
                    rows = payload["tables"][table.name]
                    for offset in range(0, len(rows), 100):
                        _check(check)
                        connection.execute(table.insert(), rows[offset : offset + 100])
                for key, value in payload["settings"].items():
                    connection.execute(Setting.__table__.insert().values(key=key, value=value))
                # v1 permitted complete but unpublished video records. Keep
                # their identities as candidates for fresh physical checking,
                # never as authority to expose an unverified available video.
                connection.execute(
                    Video.__table__.update()
                    .where(Video.status == "discovered")
                    .values(status="missing", location_key=None)
                )
        finally:
            engine.dispose()
        # Release the compatibility document before streaming the normalized
        # file and inspecting it. Internal expansion cannot reject a previously
        # supported v1 file just because normalized rows have extra fields.
        del rows, payload, document
        graph = ArchiveGraph("library", "library", path, mounts)
        converted = Path(temporary) / "normalized.vvbackup"
        internal_maximum = max(MAX_RECORD_BYTES, 4 * maximum_legacy)
        write_v2(converted, [graph], maximum_bytes=internal_maximum, check=check)
        staged = inspect_v2(
            converted, Path(temporary) / "stage", maximum_bytes=internal_maximum, check=check
        )
        with closing(sqlite3.connect(staged.directory / "index.sqlite3")) as index:
            with index:
                index.execute(
                    "UPDATE archive_info SET value=? WHERE key='complete'",
                    (canonical(original).decode(),),
                )
        _sync_directory(staged.directory)
        _check(check)
        rename_new(staged.directory, destination)
    return StagedArchive(destination)

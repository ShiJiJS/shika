"""Only the history reference committed with the current library is visible."""

import sqlite3
import uuid
from pathlib import Path

from .errors import LibraryError
from .models import Setting

HISTORY_KEY = "management_history_ref"
EPOCHS_KEY = "management_history_epochs"


def current_history(session):
    pointer = session.get(Setting, HISTORY_KEY)
    if not pointer or not pointer.value:
        return None
    try:
        ref = pointer.value
        if str(uuid.UUID(ref)) != ref:
            raise ValueError()
        from .backup_history import HistoryArchive

        base = Path(session.get_bind().url.database).absolute().parent
        return HistoryArchive(base / "management-history" / ref / "bundle")
    except (OSError, sqlite3.Error, ValueError) as error:
        raise LibraryError(
            "history_unavailable", "管理历史暂不可读取；原请求未重新提交", 503
        ) from error


def reject_historical(session, namespace, request_key):
    """Check only the scalar index, under the admitting writer's transaction.

    A current accepted request is resolved by its owning module before this
    guard. A key found only in the retired graphs cannot become a fresh command.
    """
    history = current_history(session)
    if history is None:
        return
    try:
        history._locate(
            "history_receipts",
            "item.namespace=? AND item.request_key=?",
            (namespace, request_key),
            None,
        )
    except LibraryError as error:
        if error.code == "history_not_found":
            return
        raise
    raise LibraryError(
        "historical_request", "原请求属于只读管理历史，请查询原结果，未重新执行", 409
    )


def historical_task(session, identity, *, graph_id=None):
    history = current_history(session)
    if history is None:
        return None
    try:
        return history.task_record(identity, graph_id=graph_id)
    except LibraryError as error:
        if error.code == "history_not_found":
            return None
        raise


def historical_receipt(session, namespace, request_key, *, graph_id=None):
    history = current_history(session)
    if history is None:
        return None
    try:
        return history.receipt(namespace, request_key, graph_id=graph_id)
    except LibraryError as error:
        if error.code == "history_not_found":
            return None
        raise


def historical_operation(session, namespace, *, identity=None, request_key=None):
    history = current_history(session)
    if history is None:
        return None
    try:
        return (
            history.receipt(namespace, request_key)
            if request_key is not None
            else history.operation(namespace, identity)
        )
    except LibraryError as error:
        if error.code == "history_not_found":
            return None
        raise

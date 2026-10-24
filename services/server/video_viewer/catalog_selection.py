"""Complete filtered ID membership in one read, without opening any media."""

from .errors import LibraryError

# UUID lists remain below the client's 2 MiB JSON budget. Never return a prefix
# advertised as a complete selection when the caller must narrow its scope.
MAX_SELECTION_ITEMS = 50_000


def membership(session, statement, identity, kind):
    ids = list(session.scalars(statement.with_only_columns(identity).limit(MAX_SELECTION_ITEMS + 1)))
    if len(ids) > MAX_SELECTION_ITEMS:
        raise LibraryError("selection_too_large", "匹配项超过五万，请缩小筛选范围后全选", 422)
    return {"kind": kind, "ids": ids, "total": len(ids)}

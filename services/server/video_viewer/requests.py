import hashlib
import json

from .errors import LibraryError
from .models import RequestRecord


def once(session, kind, request_id, payload, action):
    key = kind + ":" + request_id
    fingerprint = hashlib.sha256(
        json.dumps(payload, sort_keys=True, ensure_ascii=False).encode()
    ).hexdigest()
    previous = session.get(RequestRecord, key)
    if previous:
        if previous.fingerprint != fingerprint:
            raise LibraryError("idempotency_conflict", "请求标识已用于不同的操作")
        return previous.result
    result = action()
    session.add(RequestRecord(id=key, fingerprint=fingerprint, result=result))
    session.flush()
    return result

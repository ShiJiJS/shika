"""Fence request writes against the library generation committed by restore.

The request lease follows FastAPI's async dependency into thread-pool calls.
Its final check runs under Database.write_lock, in the actual write transaction.
Background workers do not inherit an HTTP lease; restore admission must quiesce
them before replacing a library. An epoch is a generation, not a credential.
"""

import re
import secrets
import time
from contextlib import contextmanager
from contextvars import ContextVar
from dataclasses import dataclass

from sqlalchemy import select, update

from .errors import LibraryError
from .models import AccessToken, Setting

KEY = "management_epoch"
HEADER = "X-Management-Epoch"


def valid_epoch(value):
    return isinstance(value, str) and re.fullmatch(r"[a-f0-9]{32}", value) is not None


@dataclass(frozen=True)
class Principal:
    digest: str
    issued_epoch: str


@dataclass(frozen=True)
class Lease:
    principal: Principal
    expected: str


class Authority:
    def __init__(self):
        self._lease = ContextVar("library_request_authority", default=None)

    @staticmethod
    def initialize(session):
        item = session.get(Setting, KEY)
        if item is None:
            # Only the first upgrade has unbound legacy tokens. Losing an
            # existing authority must not silently authorize old generations.
            if session.scalar(
                select(AccessToken.digest).where(AccessToken.issued_epoch != "").limit(1)
            ):
                raise RuntimeError("Management authority is missing for issued tokens")
            item = Setting(key=KEY, value=secrets.token_hex(16))
            session.add(item)
            session.flush()
        if not valid_epoch(item.value):
            raise RuntimeError("Invalid management authority")
        session.execute(
            update(AccessToken)
            .where(AccessToken.issued_epoch == "")
            .values(issued_epoch=item.value)
        )
        return item.value

    @staticmethod
    def current(session):
        value = session.scalar(select(Setting.value).where(Setting.key == KEY))
        if not valid_epoch(value):
            raise RuntimeError("Invalid management authority")
        return value

    @staticmethod
    def rotate(session):
        item = session.get(Setting, KEY)
        previous = Authority.current(session)
        value = secrets.token_hex(16)
        while value == previous:
            value = secrets.token_hex(16)
        item.value = value
        return value

    @contextmanager
    def bind(self, principal, explicit=None):
        expected = principal.issued_epoch if explicit is None else explicit
        if not valid_epoch(expected):
            raise LibraryError("invalid_management_epoch", "管理数据代次格式不正确", 422)
        token = self._lease.set(Lease(principal, expected))
        try:
            yield
        finally:
            self._lease.reset(token)

    def check(self, session):
        lease = self._lease.get()
        if lease is None:
            return
        token = session.get(AccessToken, lease.principal.digest)
        if (
            not token
            or token.expires_at <= time.time()
            or token.issued_epoch != lease.principal.issued_epoch
        ):
            raise LibraryError("unauthorized", "连接凭据已失效，请重新连接", 401)
        if self.current(session) != lease.expected:
            raise LibraryError(
                "management_changed", "管理数据已恢复，请重新连接并核对当前内容；旧操作未执行", 409
            )

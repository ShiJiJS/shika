import hashlib
import secrets
import threading
import time
from contextlib import contextmanager

from argon2 import PasswordHasher
from argon2.exceptions import VerificationError
from sqlalchemy import delete, select

from .authority import Authority, Principal, valid_epoch
from .errors import LibraryError
from .models import AccessToken, Setting


class Authentication:
    def __init__(self, db, settings):
        self.db, self.settings = db, settings
        self.hasher = PasswordHasher()
        self.login_slots = threading.BoundedSemaphore(1)
        with db.write() as session:
            Authority.initialize(session)
            record = session.get(Setting, "passphrase_hash")
            source = session.get(Setting, "configured_passphrase_hash")
            if not record and (source or session.scalar(select(AccessToken.digest).limit(1))):
                raise RuntimeError("Existing authentication lost its passphrase record")
            if settings.passphrase:
                # The file seeds old deployments and remains an operator reset
                # path. An unchanged seed must not undo a later in-app change.
                reference = source or record
                if not reference or not self.matches(reference.value, settings.passphrase):
                    encoded = self.hasher.hash(settings.passphrase)
                    session.execute(delete(AccessToken))
                    if record:
                        record.value = encoded
                    else:
                        record = Setting(key="passphrase_hash", value=encoded)
                        session.add(record)
                    if source:
                        source.value = encoded
                if not source:
                    session.add(Setting(key="configured_passphrase_hash", value=record.value))
            if not session.get(Setting, "server_id"):
                session.add(Setting(key="server_id", value=secrets.token_hex(16)))

    def matches(self, encoded, supplied):
        try:
            return self.hasher.verify(encoded, supplied)
        except VerificationError:
            return False

    @contextmanager
    def verification_slot(self):
        if not self.login_slots.acquire(blocking=False):
            raise LibraryError("login_busy", "正在验证连接，请稍后重试", 429)
        try:
            yield
        finally:
            self.login_slots.release()

    def initialized(self):
        with self.db.read() as session:
            return session.get(Setting, "passphrase_hash") is not None

    @staticmethod
    def validate_new(passphrase):
        if not 8 <= len(passphrase) <= 1024 or not passphrase.strip():
            raise LibraryError("invalid_passphrase", "个人口令需要8–1024个字符", 422)

    def setup(self, passphrase):
        self.validate_new(passphrase)
        with self.verification_slot():
            if self.initialized():
                raise LibraryError("setup_completed", "此服务已设置口令，请直接登录", 409)
            encoded = self.hasher.hash(passphrase)
            with self.db.write(session_control=True) as session:
                if session.get(Setting, "passphrase_hash"):
                    raise LibraryError("setup_completed", "此服务已设置口令，请直接登录", 409)
                session.add(Setting(key="passphrase_hash", value=encoded))
                return self.issue(session)

    def change(self, current, replacement):
        self.validate_new(replacement)
        with self.verification_slot():
            with self.db.read() as session:
                record = session.get(Setting, "passphrase_hash")
                encoded = record.value if record else None
            if not encoded or not self.matches(encoded, current):
                raise LibraryError("current_passphrase_incorrect", "当前口令不正确", 422)
            updated = self.hasher.hash(replacement)
            with self.db.write(session_control=True) as session:
                record = session.get(Setting, "passphrase_hash")
                if not record or record.value != encoded:
                    raise LibraryError("credentials_changed", "口令已变化，请重新连接", 409)
                record.value = updated
                session.execute(delete(AccessToken))
                return self.issue(session)

    def login(self, passphrase):
        with self.verification_slot():
            return self._login(passphrase)

    def _login(self, passphrase):
        with self.db.read() as session:
            record = session.get(Setting, "passphrase_hash")
            if not record:
                raise LibraryError("setup_required", "首次使用，请先设置个人口令", 409)
            encoded = record.value
        if not self.matches(encoded, passphrase):
            raise LibraryError("invalid_credentials", "口令不正确", 401)
        with self.db.write(session_control=True) as session:
            record = session.get(Setting, "passphrase_hash")
            if not record or record.value != encoded:
                raise LibraryError("invalid_credentials", "口令已变化，请重新登录", 401)
            return self.issue(session)

    def issue(self, session):
        token = secrets.token_urlsafe(32)
        expires = time.time() + self.settings.token_seconds
        session.execute(delete(AccessToken).where(AccessToken.expires_at < time.time()))
        epoch = Authority.current(session)
        session.add(AccessToken(digest=self.digest(token), expires_at=expires, issued_epoch=epoch))
        return {
            "access_token": token,
            "token_type": "bearer",
            "expires_at": expires,
            "management_epoch": epoch,
        }

    @staticmethod
    def digest(token):
        return hashlib.sha256(token.encode()).hexdigest()

    def require(self, header):
        return self.authenticate(header).digest

    def authenticate(self, header):
        if not header or not header.startswith("Bearer ") or len(header) > 256:
            raise LibraryError("unauthorized", "请连接并验证口令", 401)
        digest = self.digest(header[7:])
        with self.db.read() as session:
            token = session.get(AccessToken, digest)
            if not token or token.expires_at <= time.time() or not valid_epoch(token.issued_epoch):
                raise LibraryError("unauthorized", "连接凭据已失效，请重新连接", 401)
            return Principal(digest, token.issued_epoch)

    def revoke(self, digest):
        with self.db.write(session_control=True) as session:
            session.execute(delete(AccessToken).where(AccessToken.digest == digest))

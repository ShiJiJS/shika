import hashlib
import secrets
import threading
import time

from argon2 import PasswordHasher
from argon2.exceptions import VerificationError
from sqlalchemy import delete

from .errors import LibraryError
from .models import AccessToken, Setting


class Authentication:
    def __init__(self, db, settings):
        self.db, self.settings = db, settings
        self.hasher = PasswordHasher()
        self.login_slots = threading.BoundedSemaphore(1)
        with db.write() as session:
            record = session.get(Setting, "passphrase_hash")
            unchanged = record and self.matches(record.value, settings.passphrase)
            if not unchanged:
                session.execute(delete(AccessToken))
                if record:
                    record.value = self.hasher.hash(settings.passphrase)
                else:
                    session.add(
                        Setting(key="passphrase_hash", value=self.hasher.hash(settings.passphrase))
                    )
            if not session.get(Setting, "server_id"):
                session.add(Setting(key="server_id", value=secrets.token_hex(16)))

    def matches(self, encoded, supplied):
        try:
            return self.hasher.verify(encoded, supplied)
        except VerificationError:
            return False

    def login(self, passphrase):
        if not self.login_slots.acquire(blocking=False):
            raise LibraryError("login_busy", "正在验证连接，请稍后重试", 429)
        try:
            return self._login(passphrase)
        finally:
            self.login_slots.release()

    def _login(self, passphrase):
        with self.db.read() as session:
            encoded = session.get(Setting, "passphrase_hash").value
        if not self.matches(encoded, passphrase):
            raise LibraryError("invalid_credentials", "口令不正确", 401)
        token = secrets.token_urlsafe(32)
        expires = time.time() + self.settings.token_seconds
        with self.db.write() as session:
            session.execute(delete(AccessToken).where(AccessToken.expires_at < time.time()))
            session.add(AccessToken(digest=self.digest(token), expires_at=expires))
        return {"access_token": token, "token_type": "bearer", "expires_at": expires}

    @staticmethod
    def digest(token):
        return hashlib.sha256(token.encode()).hexdigest()

    def require(self, header):
        if not header or not header.startswith("Bearer ") or len(header) > 256:
            raise LibraryError("unauthorized", "请连接并验证口令", 401)
        digest = self.digest(header[7:])
        with self.db.read() as session:
            token = session.get(AccessToken, digest)
            if not token or token.expires_at <= time.time():
                raise LibraryError("unauthorized", "连接凭据已失效，请重新连接", 401)
        return digest

    def revoke(self, digest):
        with self.db.write() as session:
            session.execute(delete(AccessToken).where(AccessToken.digest == digest))

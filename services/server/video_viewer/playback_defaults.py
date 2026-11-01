"""Managed defaults are independent from the currently playing round."""

import json

from .errors import LibraryError
from .models import PlaybackRound, RequestRecord, Setting
from .requests import once


class PlaybackDefaults:
    key = "playback_defaults"

    def __init__(self, db):
        self.db = db
        # Capture the old global round once, before any client can change it.
        with db.write() as session:
            self.current(session)

    @classmethod
    def current(cls, session, *, persist=True):
        row = session.get(Setting, cls.key)
        if row:
            return json.loads(row.value)
        pointer = session.get(Setting, "active_round")
        active = session.get(PlaybackRound, pointer.value) if pointer else None
        value = {"order": active.order if active else "random", "revision": 0}
        if persist:
            session.add(Setting(key=cls.key, value=json.dumps(value)))
            session.flush()
        return value

    def read(self):
        with self.db.read() as session:
            return self.current(session, persist=False)

    def write(self, *, order, expected_revision, request_id):
        with self.db.write() as session:

            def action():
                current = self.current(session)
                if current["revision"] != expected_revision:
                    raise LibraryError(
                        "playback_defaults_changed", "默认播放顺序已更新，请重新读取"
                    )
                value = {"order": order, "revision": expected_revision + 1}
                session.get(Setting, self.key).value = json.dumps(value)
                return value

            return once(
                session,
                "playback.defaults",
                request_id,
                {"order": order, "revision": expected_revision},
                action,
            )

    def receipt(self, request_id):
        with self.db.read() as session:
            row = session.get(RequestRecord, "playback.defaults:" + request_id)
            if not row:
                raise LibraryError("defaults_request_not_found", "未找到该默认设置请求", 404)
            return {"status": "completed", "result": row.result}

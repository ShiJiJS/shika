import hashlib
import json
import random

from sqlalchemy import select

from .errors import LibraryError
from .models import PlaybackRound, RoundEntry, Setting, Video, uid


class Playback:
    def __init__(self, db, catalog, streams):
        self.db, self.catalog, self.streams = db, catalog, streams

    def eligible(self, session, round):
        scope = round.scope
        try:
            candidates = (
                self.catalog.video_statement(session, **scope)
                .with_only_columns(Video.id)
                .subquery()
            )
        except LibraryError as error:
            if error.code == "directory_not_found":
                return []
            raise
        return list(
            session.execute(
                select(RoundEntry.ordinal, RoundEntry.video_id)
                .where(
                    RoundEntry.round_id == round.id,
                    RoundEntry.video_id.in_(select(candidates.c.id)),
                )
                .order_by(RoundEntry.ordinal)
            )
        )

    def create(self, order, scope, anchor_video_id=None, request_id=None):
        with self.db.write() as session:
            return self.create_in_session(session, order, scope, anchor_video_id, request_id)

    def create_in_session(
        self,
        session,
        order,
        scope,
        anchor_video_id=None,
        request_id=None,
        *,
        allow_missing_scope=False,
    ):
        request_hash = hashlib.sha256(
            json.dumps(
                {"order": order, "scope": scope, "anchor": anchor_video_id}, sort_keys=True
            ).encode()
        ).hexdigest()
        request_id = request_id or uid()
        previous = session.scalar(
            select(PlaybackRound).where(PlaybackRound.request_id == request_id)
        )
        if previous:
            if previous.request_hash != request_hash:
                raise LibraryError("idempotency_conflict", "请求标识已用于不同的轮次操作")
            return self.summary(session, previous)
        try:
            candidates = list(
                session.scalars(
                    self.catalog.video_statement(session, **scope)
                    .order_by(Video.path, Video.id)
                    .with_only_columns(Video.id)
                )
            )
        except LibraryError as error:
            if not allow_missing_scope or error.code != "directory_not_found":
                raise
            candidates = []
        if anchor_video_id and anchor_video_id not in candidates:
            raise LibraryError("video_outside_scope", "该视频不在当前可播放范围内", 422)
        if order == "random":
            random.SystemRandom().shuffle(candidates)
        round = PlaybackRound(
            request_id=request_id,
            request_hash=request_hash,
            order=order,
            scope=scope,
            cursor=candidates.index(anchor_video_id) if anchor_video_id else 0,
            candidate_count=len(candidates),
            finished=not candidates,
        )
        session.add(round)
        session.flush()
        session.add_all(
            RoundEntry(round_id=round.id, ordinal=i, video_id=video_id)
            for i, video_id in enumerate(candidates)
        )
        pointer = session.get(Setting, "active_round")
        if pointer:
            pointer.value = round.id
        else:
            session.add(Setting(key="active_round", value=round.id))
        session.flush()
        return self.summary(session, round)

    def current(self):
        with self.db.write_lock:
            with self.db.read() as session:
                pointer = session.get(Setting, "active_round")
                active = pointer.value if pointer else None
            if not active:
                return self.create("random", {})
            with self.db.write() as session:
                round = self.get(session, active)
                return self.summary(session, round)

    @staticmethod
    def get(session, round_id):
        round = session.get(PlaybackRound, round_id)
        if not round:
            raise LibraryError("round_not_found", "播放轮次不存在", 404)
        return round

    def playable(self, session, entries):
        # Validate the selected/adjacent files against the current filesystem.
        return [
            (ordinal, video_id)
            for ordinal, video_id in entries
            if self.streams.can_play(session, session.get(Video, video_id))
        ]

    def summary(self, session, round):
        entries = self.eligible(session, round)
        cursor = next((i for i, row in enumerate(entries) if row[0] >= round.cursor), len(entries))
        selected = None
        for i in range(cursor, len(entries)):
            if self.streams.can_play(session, session.get(Video, entries[i][1])):
                selected = i
                break
        if selected is None and entries:
            # At exhaustion keep the last remaining video looping, as the client
            # already does; starting another round is an explicit operation.
            for i in range(min(cursor, len(entries) - 1), -1, -1):
                if self.streams.can_play(session, session.get(Video, entries[i][1])):
                    selected = i
                    break
            round.finished = True
        if selected is not None and entries[selected][0] != round.cursor:
            round.cursor = entries[selected][0]
            round.revision += 1
        window = []
        if selected is not None:
            neighbors = [selected]
            for direction in (-1, 1):
                i = selected + direction
                while 0 <= i < len(entries):
                    if self.streams.can_play(session, session.get(Video, entries[i][1])):
                        neighbors.append(i)
                        break
                    i += direction
            for i in sorted(neighbors):
                window.append(
                    {
                        "position": i,
                        "video": self.catalog.video_json(session.get(Video, entries[i][1])),
                    }
                )
        pointer = session.get(Setting, "active_round")
        return {
            "id": round.id,
            "active": bool(pointer and pointer.value == round.id),
            "order": round.order,
            "scope": round.scope,
            "position": selected or 0,
            "total": len(entries),
            "candidate_count": round.candidate_count,
            "revision": round.revision,
            "finished": round.finished or selected is None,
            "current": self.catalog.video_json(session.get(Video, entries[selected][1]))
            if selected is not None
            else None,
            "window": window,
        }

    def move(self, round_id, expected_revision, video_id=None, finish=False):
        with self.db.write() as session:
            round = self.get(session, round_id)
            pointer = session.get(Setting, "active_round")
            if not pointer or pointer.value != round.id:
                raise LibraryError("round_replaced", "播放范围已变化，请刷新当前轮次")
            entries = self.eligible(session, round)
            target = (
                next((row for row in entries if row[1] == video_id), None) if video_id else None
            )
            if video_id and (
                not target or not self.streams.can_play(session, session.get(Video, video_id))
            ):
                raise LibraryError("video_unavailable", "该视频已不在当前可播放范围内")
            already_applied = (target and target[0] == round.cursor and not round.finished) or (
                finish and round.finished
            )
            if expected_revision != round.revision and not already_applied:
                raise LibraryError("round_conflict", "轮次位置已变化，请刷新后重试")
            if finish:
                remaining = self.playable(session, entries)
                if remaining and round.cursor != remaining[-1][0]:
                    raise LibraryError("round_not_exhausted", "本轮还有未播放的视频")
                if not round.finished:
                    round.finished, round.revision = True, round.revision + 1
            elif target:
                if round.cursor != target[0] or round.finished:
                    round.cursor, round.finished, round.revision = (
                        target[0],
                        False,
                        round.revision + 1,
                    )
            return self.summary(session, round)

    def entries(self, round_id, offset, limit):
        with self.db.read() as session:
            round = self.get(session, round_id)
            entries = self.eligible(session, round)
            return {
                "items": [
                    {"position": i, "video": self.catalog.video_json(session.get(Video, video_id))}
                    for i, (_ordinal, video_id) in enumerate(
                        entries[offset : offset + limit], start=offset
                    )
                ],
                "offset": offset,
                "limit": limit,
                "total": len(entries),
            }

"""Read a verified returned inode without rewriting its page or operation history."""

import hashlib
import os
import threading
from collections import OrderedDict

from sqlalchemy import select

from .models import (
    PackFileOperation,
    PackFileStep,
    PackPurgeExecution,
    PackPurgePlan,
    PackPurgeStep,
    PackTrashItem,
)
from .paths import signature


class ReturnedImageReads:
    # Only signatures/digests are cached, never image bytes or authorization.
    max_entries = 128

    def __init__(self):
        self.verified = OrderedDict()
        self.lock = threading.Lock()

    def matches(self, session, page, pack, root, fd, observed):
        expected = page.signature
        if not page.sha256 or observed[:4] != expected[:4]:
            return False
        statement = (
            select(PackPurgeStep)
            .join(PackFileStep, PackFileStep.id == PackPurgeStep.parent_id)
            .join(PackFileOperation, PackFileOperation.id == PackFileStep.operation_id)
            .join(PackPurgeExecution, PackPurgeExecution.id == PackFileOperation.id)
            .join(PackPurgePlan, PackPurgePlan.id == PackPurgeExecution.plan_id)
            .join(PackTrashItem, PackTrashItem.id == PackFileStep.requested_id)
            .where(
                PackFileStep.pack_id == pack.id,
                PackFileStep.original_path == pack.path,
                PackFileStep.root_path == root.path,
                PackFileOperation.kind == "permanent",
                PackFileOperation.historical.is_(False),
                PackPurgePlan.historical.is_(False),
                PackTrashItem.pack_id == pack.id,
                PackTrashItem.original_path == pack.path,
                PackTrashItem.root_path == root.path,
                PackTrashItem.status == "restored",
                PackPurgeStep.kind == "image",
                PackPurgeStep.page_id == page.id,
                PackPurgeStep.relative_path == page.relative_path,
                PackPurgeStep.phase == "rolled_back",
                PackPurgeStep.outcome != "succeeded",
                PackPurgeStep.expected_hash == page.sha256,
                PackPurgeStep.expected_size == page.size,
            )
            .execution_options(yield_per=32)
        )
        for row in session.scalars(statement):
            if (
                row.state.get("source_signature") != expected
                or row.source_signature[:4] != expected[:4]
            ):
                continue
            key = (row.id, tuple(expected), tuple(observed), page.sha256)
            with self.lock:
                cached = key in self.verified
                if cached:
                    self.verified.move_to_end(key)
            if cached:
                return signature(os.fstat(fd)) == observed
            if self.digest(fd, observed) != page.sha256:
                return False
            with self.lock:
                self.verified[key] = None
                self.verified.move_to_end(key)
                while len(self.verified) > self.max_entries:
                    self.verified.popitem(last=False)
            return True
        return False

    @staticmethod
    def digest(fd, observed):
        # Positional reads leave the response descriptor at byte zero. Bound
        # reads to the indexed size, and reject growth or mutation during hash.
        digest = hashlib.sha256()
        offset = 0
        while offset < observed[2]:
            chunk = os.pread(fd, min(1024 * 1024, observed[2] - offset), offset)
            if not chunk:
                return None
            digest.update(chunk)
            offset += len(chunk)
        return digest.hexdigest() if signature(os.fstat(fd)) == observed else None

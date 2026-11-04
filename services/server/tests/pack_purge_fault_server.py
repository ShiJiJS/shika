"""Private subprocess factory for killing a durable pack purge checkpoint."""

import os
import time
from contextlib import asynccontextmanager
from dataclasses import replace
from pathlib import Path

from shika.app import create_app
from shika.config import Settings


def create_fault_app():
    app = create_app(replace(Settings.from_env(), startup_scan=False))
    original = app.router.lifespan_context

    @asynccontextmanager
    async def lifespan(current):
        async with original(current):

            def checkpoint(phase, identity):
                if phase != os.environ["TEST_PACK_PURGE_PHASE"]:
                    return
                if os.environ.get("TEST_PACK_PURGE_ROOT_ONLY") == "1":
                    if current.state.pack_purge.rows[identity].relative_path != ".":
                        return
                Path(os.environ["TEST_PACK_PURGE_MARKER"]).write_text(phase)
                while True:
                    time.sleep(0.05)

            current.state.pack_purge.fault_hook = checkpoint
            yield

    app.router.lifespan_context = lifespan
    return app

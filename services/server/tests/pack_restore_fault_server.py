"""Private process fixture: block at a durable restore boundary until SIGKILL."""

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
            current.state.pack_restore_plans.batch_size = 2

            def checkpoint(phase, identity):
                if phase != os.environ["TEST_RESTORE_PHASE"]:
                    return
                if phase == "logical_committed":
                    with current.state.db.read() as session:
                        from shika.models import Task

                        if session.get(Task, identity).kind != "pack_restore":
                            return
                marker = Path(os.environ["TEST_RESTORE_MARKER"])
                incoming = marker.with_name(marker.name + ".incoming")
                incoming.write_text(phase)
                incoming.replace(marker)
                while True:
                    time.sleep(0.05)

            current.state.pack_restore_plans.fault_hook = checkpoint
            current.state.pack_files.fault_hook = checkpoint
            yield

    app.router.lifespan_context = lifespan
    return app

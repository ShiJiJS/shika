"""Isolated subprocess factory; fault injection is not exposed by production API."""

import os
import time
from pathlib import Path

from video_viewer.app import create_app


def create_fault_app():
    phase = os.environ["TEST_FILE_PHASE"]
    marker = Path(os.environ["TEST_FILE_MARKER"])

    def checkpoint(current, _step):
        if current == phase:
            marker.write_text(current)
            while True:
                time.sleep(0.05)

    return create_app(file_fault_hook=checkpoint)


def create_backup_fault_app():
    phase = os.environ["TEST_BACKUP_PHASE"]
    marker = Path(os.environ["TEST_BACKUP_MARKER"])

    def checkpoint(current, _task):
        if current == phase:
            marker.write_text(current)
            while True:
                time.sleep(0.05)

    return create_app(backup_fault_hook=checkpoint)


def create_archive_memory_app():
    """Test-only allocation probe in an isolated subprocess, never production."""
    import tracemalloc

    app = create_app()

    @app.post("/test-allocation/reset")
    def reset():
        tracemalloc.stop()
        tracemalloc.start()
        return {"measuring": "python_allocations"}

    @app.get("/test-allocation/peak")
    def peak():
        current, maximum = tracemalloc.get_traced_memory()
        return {"current_bytes": current, "peak_bytes": maximum}

    return app

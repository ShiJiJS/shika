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

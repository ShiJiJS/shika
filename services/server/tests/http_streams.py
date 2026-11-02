"""Real HTTP helpers shared by video and image resource checks."""

import time
from contextlib import contextmanager


def process_kib(pid):
    with open(f"/proc/{pid}/status") as status:
        return int(next(line.split()[1] for line in status if line.startswith("VmRSS:")))


@contextmanager
def available_stream(client, route):
    # Final bytes may arrive before ASGI closes its file/slot. Wait only for
    # this bounded 503 state; a leaked slot still fails within five seconds.
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        with client.stream("GET", route) as response:
            if response.status_code == 200:
                yield response
                return
            assert response.status_code == 503
        time.sleep(0.02)
    raise AssertionError("Stream slot was not released after response completion/cancellation")

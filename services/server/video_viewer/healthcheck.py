"""Small HTTP liveness entry point for the pinned CPython container image.

The C socket module keeps this short-lived probe's import set small. Connect
only to numeric loopback; no application, proxy, DNS, or TLS setup is needed.
"""

import _socket
import time


def healthy(port=8760, timeout=2.0):
    deadline = time.monotonic() + timeout
    connection = None
    try:
        connection = _socket.socket(_socket.AF_INET, _socket.SOCK_STREAM)
        connection.settimeout(timeout)
        connection.connect(("127.0.0.1", port))
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        connection.settimeout(remaining)
        connection.sendall(b"GET /health HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        headers = bytearray()
        while b"\r\n\r\n" not in headers:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or len(headers) >= 8192:
                return False
            connection.settimeout(remaining)
            chunk = connection.recv(min(1024, 8192 - len(headers)))
            if not chunk:
                return False
            headers.extend(chunk)
        status = headers.split(b"\r\n", 1)[0].split()
        return (
            time.monotonic() <= deadline
            and len(status) >= 2
            and status[0] in (b"HTTP/1.0", b"HTTP/1.1")
            and status[1] == b"200"
        )
    except OSError:
        return False
    finally:
        if connection is not None:
            connection.close()


if __name__ == "__main__":
    raise SystemExit(0 if healthy() else 1)

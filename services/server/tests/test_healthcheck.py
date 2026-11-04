import socket
import threading
import time
from contextlib import contextmanager

import pytest

from shika.healthcheck import healthy


@contextmanager
def responding(reply):
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(1)
    port = listener.getsockname()[1]
    stop = threading.Event()
    requests, errors = [], []

    def serve():
        try:
            connection, _ = listener.accept()
            with connection:
                connection.settimeout(1)
                request = bytearray()
                while b"\r\n\r\n" not in request:
                    chunk = connection.recv(1024)
                    if not chunk:
                        return
                    request.extend(chunk)
                requests.append(bytes(request))
                reply(connection, stop)
        except OSError:
            pass  # A timed-out probe can close before a deliberately late reply.
        except Exception as error:
            errors.append(error)

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    try:
        yield port, requests
    finally:
        stop.set()
        listener.close()
        thread.join(2)
        assert not thread.is_alive()
        assert not errors


@pytest.mark.parametrize(
    "status,expected",
    [
        (b"HTTP/1.1 200 OK", True),
        (b"HTTP/1.0 200 OK", True),
        (b"HTTP/1.1 503 Unavailable", False),
        (b"HTTP/1.1 302 Found", False),
        (b"HTTP/1.1 204 No Content", False),
        (b"HTTP/1.1 2000 Invalid", False),
        (b"INVALID 200 OK", False),
    ],
)
def test_liveness_requires_real_200_headers_on_numeric_loopback(status, expected):
    def reply(connection, stop):
        connection.sendall(status + b"\r\nContent-Length: 0\r\n\r\n")

    with responding(reply) as (port, requests):
        assert healthy(port) is expected
        assert requests == [b"GET /health HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n"]


def test_split_status_and_headers_are_reassembled():
    def reply(connection, stop):
        for piece in [b"HT", b"TP/1.1 2", b"00 OK\r\n", b"Content-Length: 0\r\n", b"\r\n"]:
            connection.sendall(piece)
            stop.wait(0.005)

    with responding(reply) as (port, _):
        assert healthy(port)


def test_status_line_without_complete_headers_is_not_healthy():
    with responding(lambda connection, stop: connection.sendall(b"HTTP/1.1 200 OK\r\n")) as (
        port,
        _,
    ):
        assert not healthy(port)


def test_oversized_headers_are_rejected_without_unbounded_reads():
    with responding(
        lambda connection, stop: connection.sendall(b"HTTP/1.1 200 OK\r\nX-Fill: " + b"x" * 16384)
    ) as (port, _):
        assert not healthy(port)


@pytest.mark.parametrize("dribble", [False, True])
def test_unresponsive_or_dribbling_headers_respect_one_overall_deadline(dribble):
    def reply(connection, stop):
        if not dribble:
            stop.wait(1)
            return
        for byte in b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n":
            if stop.wait(0.02):
                return
            connection.sendall(bytes([byte]))

    with responding(reply) as (port, _):
        started = time.monotonic()
        assert not healthy(port, timeout=0.08)
        assert time.monotonic() - started < 0.75


def test_stopped_service_is_not_healthy():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    assert not healthy(port, timeout=0.08)

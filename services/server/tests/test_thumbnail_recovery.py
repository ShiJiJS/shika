import hashlib
import subprocess

import pytest

from video_viewer import media as tools
from video_viewer import scanner

from .conftest import put, scan
from .test_tags import assign, tag


@pytest.mark.parametrize('fault,code', [
    ('timeout', 'thumbnail_timeout'),
    ('decode', 'thumbnail_decode_failed'),
    ('cache', 'thumbnail_cache_unavailable'),
])
def test_optional_thumbnail_failure_keeps_original_and_retries_without_rehash(
    library, samples, monkeypatch, fault, code
):
    client, directory = library
    path = directory / 'valid.mp4'
    digest = put(samples / 'portrait.mp4', path)
    original_run = tools.subprocess.run
    original_thumbnail = tools.make_thumbnail

    def unavailable(command, **kwargs):
        if command[0] == 'ffmpeg':
            if fault == 'timeout':
                raise subprocess.TimeoutExpired(command, 20, stderr=b'private subprocess detail')
            if fault == 'decode':
                raise subprocess.CalledProcessError(1, command, stderr=b'private subprocess detail')
            raise PermissionError('private subprocess detail')
        return original_run(command, **kwargs)

    monkeypatch.setattr(tools.subprocess, 'run', unavailable)
    job = scan(client)
    assert job['result']['imported'] == 1
    assert job['result']['failed'] == 0
    assert job['result']['thumbnail_failed'] == 1
    assert job['result']['warning_reasons'] == {code: 1}
    state = client.get('/api/v1/library-state').json()
    assert state['ready'] and state['counts']['thumbnail_failed'] == 1
    first = client.get('/api/v1/videos').json()['items'][0]
    assert first['thumbnail_url'] is None and first['error'] is None
    assert client.get(first['media_url']).content == path.read_bytes()
    marked = tag(client, '元数据保留')['id']
    assign(client, [first['id']], [marked])

    def no_full_read(*args):
        raise AssertionError('Unchanged originals must not be rehashed or probed for an optional poster')

    monkeypatch.setattr(scanner, 'fingerprint', no_full_read)
    monkeypatch.setattr(scanner, 'inspect_media', no_full_read)
    second_job = scan(client)
    assert second_job['result']['unchanged'] == 1
    assert second_job['result']['failed'] == 0
    assert second_job['result']['warning_reasons'] == {code: 1}

    monkeypatch.setattr(tools.subprocess, 'run', original_run)
    monkeypatch.setattr(scanner, 'make_thumbnail', original_thumbnail)
    recovered = scan(client)
    assert recovered['result']['unchanged'] == 1
    assert recovered['result']['thumbnail_failed'] == 0
    video = client.get('/api/v1/videos').json()['items'][0]
    assert video['id'] == first['id'] and video['tag_ids'] == [marked]
    assert client.get(video['thumbnail_url']).content.startswith(b'\xff\xd8')
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    assert not list((client.app.state.settings.data_dir / 'thumbnails').glob('*.tmp.jpg'))
    assert 'private subprocess detail' not in str(job)


def test_probe_failure_is_distinct_from_optional_thumbnail_warning(library):
    client, directory = library
    (directory / 'broken.mp4').write_bytes(b'not a video')
    job = scan(client)
    assert job['result']['failed'] == 1
    assert job['result']['thumbnail_failed'] == 0
    assert job['result']['failure_reasons'] == {'probe_failed': 1}
    assert job['result']['issues'][0]['code'] == 'probe_failed'
    assert client.get('/api/v1/library-state').json()['failure_reasons'] == {'probe_failed': 1}
    assert client.get('/api/v1/videos').json()['total'] == 0


def test_probe_timeout_keeps_precise_reason_without_subprocess_details(library, samples, monkeypatch):
    client, directory = library
    put(samples / 'portrait.mp4', directory / 'valid.mp4')

    def timeout(command, **kwargs):
        raise subprocess.TimeoutExpired(command, 20, stderr=b'private detail')

    monkeypatch.setattr(tools.subprocess, 'run', timeout)
    job = scan(client)
    assert job['result']['failure_reasons'] == {'probe_timeout': 1}
    assert job['result']['thumbnail_failed'] == 0
    assert 'private detail' not in str(job)


def test_thumbnail_failure_does_not_hide_a_file_changed_during_inspection(library, samples, monkeypatch):
    client, directory = library
    path = directory / 'changing.mp4'
    put(samples / 'portrait.mp4', path)

    def changed(*args):
        with path.open('ab') as output:
            output.write(b'new bytes while inspecting')
        raise tools.MediaInspectionError('thumbnail_timeout')

    monkeypatch.setattr(tools, 'make_thumbnail', changed)
    job = scan(client)
    assert job['result']['deferred'] == 1
    assert job['result']['failed'] == job['result']['thumbnail_failed'] == 0
    assert client.get('/api/v1/videos').json()['total'] == 0

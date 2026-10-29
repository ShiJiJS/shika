"""Read-only verification of frozen evidence; --decode also requires ffmpeg."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(__doc__)
parser.add_argument('--decode', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parent


def read(name):
    return json.loads((root / name).read_text())


manifest = read('manifest.json')
for name, expected in manifest['files'].items():
    data = (root / name).read_bytes()
    assert len(data) == expected['bytes'], name
    assert hashlib.sha256(data).hexdigest() == expected['sha256'], name

report = read('native-5/profile-result.json')['checkbox_motion']
assert report['complete'] and report['directions'] == 90
assert report['live_directions'] == 24
assert report['callbacks'] == {'trash': 18, 'row': 18}
assert report['final_values'] == {'trash': False, 'row': False}
assert report['production_components_only']
assert not report['normal_release_acceptance']
assert not report['accessibility_injected']
assert not report['repository_or_file_commands']
expected_names = set()
for n in (1, 2, 3):
    for kind in ('trash', 'row'):
        prefix = f'round-{n}-{kind}'
        expected_names.update(
            f'{prefix}-{mode}-{action}'
            for mode in ('normal', 'reduced')
            for action in ('select', 'deselect', 'press', 'cancel')
        )
        expected_names.update(f'{prefix}-{suffix}' for suffix in (
            'live-select', 'live-deselect', 'live-press',
            'reduced-cancel-after-live', 'normal-press-before-live',
            'live-cancel', 'disable-held',
        ))
assert len(report['cases']) == 90
assert {c['name'] for c in report['cases']} == expected_names
live = disabled = observed = 0
for case in report['cases']:
    frames = case['frames']
    observed += len(frames)
    key = 'position' if case['channel'] == 'position' else 'reaction'
    target = case['target']

    def endpoint(frame):
        return all(abs(frame[k] - target) < 1e-5 for k in (key, 'paint_' + key))

    assert frames and all(a['frame_us'] < b['frame_us'] for a, b in zip(frames, frames[1:]))
    assert all(endpoint(f) for f in frames[-3:])
    for f in frames:
        assert f['native_flag'] == f['media_query_flag']
        assert f['position_ms'] == (0 if f['native_flag'] else 140)
        assert f['reaction_ms'] == (0 if f['native_flag'] else 100)
        assert f['calls'] == case['calls_before'] + (case['channel'] == 'position')
        assert f['checkbox_value'] == (target == 1 if case['channel'] == 'position' else False)
    if case['channel'] == 'disable':
        i = next(i for i, f in enumerate(frames) if not f['enabled'])
        assert i > 0 and any(f['down'] and f['reaction'] > 0 for f in frames[:i])
        assert all(endpoint(f) and not f['down'] for f in frames[i:])
        disabled += 1
    elif case['live']:
        i = next(i for i, f in enumerate(frames) if f['native_flag'])
        assert i > 0 and 0 < frames[i-1][key] < 1
        assert all(f['native_flag'] and endpoint(f) for f in frames[i:])
        live += 1
    else:
        assert all(f['native_flag'] == case['reduced'] for f in frames)
        assert (all(endpoint(f) for f in frames) if case['reduced']
                else any(0 < f[key] < 1 for f in frames))
assert (live, disabled, observed) == (24, 6, 605)
assert read('native-5/result.json')['exit_code'] == 0
assert read('native-5/result.json')['observer_errors'] == []
for n in range(1, 6):
    restoration = read(f'native-{n}/restoration.json')
    # Runner reuses its observer-error list in restoration.json. Run 2 has
    # the recorded shell-input error, while restored settings still match.
    assert restoration['errors'] == read(f'native-{n}/result.json')['observer_errors']
    assert 'failure' not in restoration
    assert restoration['restored'] == read(f'native-{n}/original-settings.json')
    assert read(f'native-{n}/runtime.json')['emulator_pid'] == 20034
    if n < 5:
        assert read(f'native-{n}/result.json')['exit_code'] != 0
cleanup = read('cleanup-native.json')
assert cleanup['complete'] and cleanup['owned_qemu_absent'] and cleanup['settings_restored']
assert cleanup['original4_services_preserved_healthy'] == read('native-5/runtime.json')['original_container_ids']
source = read('profile-artifact-v2.json')
assert source['production_lib_equal']
assert source['lib_trees']['component'] == source['lib_trees']['native']
assert source['source'] == read('native-5/source.json')['source'] == manifest['source']
assert read('native-5/source.json')['prototype_tree'] == manifest['prototype_tree']
observer = (root / 'checkbox_motion_test.dart').read_text()
observer = observer[observer.index('Map<String, dynamic> read()'):observer.index('void frame(')]
assert re.search(r'\bt\.(state|widget|element)\b', observer) is None
clips = read('independent-decode.json')
assert len(clips) == 6
for clip, pixel in zip(clips, read('pixel-proof-v2.json')):
    video = root / 'native-5' / (clip['name'] + '.mp4')
    assert hashlib.sha256(video.read_bytes()).hexdigest() == clip['sha256']
    assert clip['full_decode_exit'] == 0
    stream = clip['metadata']['streams'][0]
    assert (stream['width'], stream['height']) == (1170, 2532)
    assert pixel['name'] == clip['name'] and pixel['decoded_frames'] > 0
    assert pixel['minimum_dark_green_fraction'] == 0
    assert pixel['light_fraction_at_selected'] > 0.1
    if args.decode:
        subprocess.run(['ffmpeg', '-v', 'error', '-i', str(video), '-map', '0:v:0',
                        '-fps_mode', 'passthrough', '-enc_time_base', 'demux',
                        '-f', 'null', '-'], check=True, timeout=40)
print(json.dumps({'complete': True, 'files': len(manifest['files']),
                  'directions': 90, 'observed_frames': observed,
                  'live_real_in_flight': live, 'held_disabled': disabled,
                  'recordings': 6, 'decoded_again': args.decode,
                  'normal_main_acceptance': False}))

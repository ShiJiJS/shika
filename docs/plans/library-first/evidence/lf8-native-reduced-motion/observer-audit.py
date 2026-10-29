import json
import subprocess
from pathlib import Path

LAB = Path(__file__).resolve().parent
OUT = LAB / 'native-9-current-elements'
report = json.loads((OUT / 'profile-result.json').read_text())['native_motion']
cases = report['cases']
checks = []
expected = {f'round-{r}-{mode}-{scene}' for r in range(1, 4) for mode in ['normal', 'reduced'] for scene in ['app-inline', 'app-fullscreen', 'legacy-component']}
assert len(cases) == 18 and {c['name'] for c in cases} == expected
assert report['complete'] and not report['system_accessibility_injected']
recordings = json.loads((OUT / 'recordings.json').read_text())
assert len(recordings) == 18 and {c['name'] for c in recordings} == expected
assert json.loads((OUT / 'result.json').read_text())['exit_code'] == 0
for case in cases:
    name, reduced, frames = case['name'], case['reduced'], case['frames']
    assert case['native_flag'] == reduced == case['media_query_flag']
    assert case['playing_after']
    assert frames and frames[0]['elapsed_us'] == 0
    assert all(f['elapsed_us'] >= 0 for f in frames)
    values = [f['values'] for f in frames]
    for target in values[0]:
        assert all(v[target]['duration_us'] == (0 if reduced else 160000) for v in values)
        assert values[0][target]['opacity'] == (0 if reduced else 1)
        assert values[-1][target]['opacity'] == 0
        if not reduced:
            assert any(0 < v[target]['opacity'] < 1 for v in values)
    if name.endswith('legacy-component'):
        assert abs(frames[-1]['footer_y'] - case['baseline']['footer_y'] - 34) < .5
        if reduced:
            assert abs(frames[0]['footer_y'] - frames[-1]['footer_y']) < .5
    windows = [(OUT / (name + suffix + '-window.txt')).read_text() for suffix in ['-before', '-after']]
    assert all('mCurrentFocus=' in w and 'io.github.shijijs.video_viewer' in w.splitlines()[0] for w in windows)
    decode = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(OUT / (name + '.mp4')), '-map', '0:v:0', '-fps_mode', 'passthrough', '-enc_time_base', 'demux', '-f', 'null', '-'], capture_output=True, text=True)
    assert decode.returncode == 0 and not decode.stderr, (name, decode.stderr)
    checks.append({'name': name, 'reduced': reduced, 'observed_frames': len(frames), 'last_elapsed_us': frames[-1]['elapsed_us'], 'largest_observation_gap_us': max((b['elapsed_us']-a['elapsed_us'] for a,b in zip(frames,frames[1:])), default=0), 'full_decode_exit': decode.returncode, 'focus_in_app': True, 'passed': True})
for name in ['native-1', 'native-2-enabled', 'native-3-recorder', 'native-4-host', 'native-5-canvas', 'native-6-lifecycle', 'native-7-adb', 'native-8-system-hint', 'native-9-current-elements']:
    path=LAB/name/('restoration-recovered.json' if name=='native-8-system-hint' else 'restoration.json')
    value=json.loads(path.read_text())
    assert not value.get('failure') and value['restored'] == json.loads((LAB/name/'original-settings.json').read_text())
result={'intended_cases':18,'passed_cases':18,'actual_app_cases':12,'native_component_cases':6,'recordings':18,'all_recordings_independently_decoded':True,'all_settings_restored':True,'physical_presentation_latency_accepted':False,'audio_playback_accepted':False,'cases':checks}
(LAB/'audit.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))

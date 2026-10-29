import json
import subprocess
from pathlib import Path
LAB=Path(__file__).resolve().parent
OUT=LAB/'native-4-layout'
report=json.loads((OUT/'profile-result.json').read_text())['page_motion']
cases=report['cases']
expected={f'round-{r}-{mode}-{scene}-{direction}' for r in range(1,4) for mode in ['normal','reduced'] for scene in ['reader','preview','fullscreen','task'] for direction in ['entry','return']}
assert report['complete'] and len(cases)==48 and {c['name'] for c in cases}==expected
assert not report['system_accessibility_injected'] and not report['normal_release_acceptance']
assert json.loads((OUT/'result.json').read_text())['exit_code']==0
checks=[]
for c in cases:
    name,reduced,closing=c['name'],c['reduced'],c['closing']
    assert reduced==(('reduced' in name) != closing)
    frames=c['frames'];target=0 if closing else 1
    assert c['configured_duration_us']==(0 if reduced else 160000 if closing else 240000)
    assert all(f['controller_duration_us']==c['configured_duration_us'] for f in frames)
    assert frames and all(f['native_flag']==reduced==f['media_query_flag_at_action'] for f in frames)
    assert frames[0]['value']==(target if reduced else 1-target) and frames[-1]['value']==target
    assert all(b['frame_us']>=a['frame_us'] for a,b in zip(frames,frames[1:]))
    if not reduced:
        assert any(0<f['value']<1 for f in frames)
        assert any(not f['offstage'] and 0<f['display_value']<1 for f in frames)
    else:assert all(f['display_value']==target for f in frames)
    checks.append({'name':name,'reduced':reduced,'closing':closing,'frames':len(frames),'observed_span_us':frames[-1]['frame_us']-frames[0]['frame_us'],'configured_duration_us':c['configured_duration_us'],'passed':True})
clips=json.loads((OUT/'recordings.json').read_text())
expected_clips={f'round-{r}-{mode}-{scene}' for r in range(1,4) for mode in ['normal','reduced'] for scene in ['reader','video','task']}
assert len(clips)==18 and {c['name'] for c in clips}==expected_clips
for c in clips:
    for suffix in ['before','after']:
        lines=(OUT/f"{c['name']}-{suffix}-window.txt").read_text().splitlines()
        assert lines and 'mCurrentFocus=' in lines[0] and 'io.github.shijijs.video_viewer' in lines[0]
    result=subprocess.run(['ffmpeg','-v','error','-i',str(OUT/(c['name']+'.mp4')),'-map','0:v:0','-fps_mode','passthrough','-enc_time_base','demux','-f','null','-'],capture_output=True,text=True)
    assert result.returncode==0 and not result.stderr,(c['name'],result.stderr)
for name in ['native-1','native-2-observer','native-3-controller','native-4-layout']:
    restored=json.loads((LAB/name/'restoration.json').read_text())
    assert not restored.get('failure') and restored['restored']==json.loads((LAB/name/'original-settings.json').read_text())
value={'passed_cases':48,'recordings':18,'all_recordings_independently_decoded':True,'all_exact_settings_restored':True,'physical_presentation_latency_accepted':False,'audio_playback_accepted':False,'cases':checks}
(LAB/'audit.json').write_text(json.dumps(value,indent=2)+'\n')
print('48 native transition traces and 18 recordings independently verified')

import json,subprocess
from pathlib import Path
L=Path(__file__).resolve().parent;O=L/'native-1'
r=json.loads((O/'profile-result.json').read_text())['overlay_motion'];cases=r['cases']
expected={f'round-{i}-{m}-{s}-{d}' for i in range(1,4) for m in ['normal','reduced'] for s in ['reader-sheet','video-sheet'] for d in ['entry','return']}|{f'dialog-{i}-{m}-{d}' for i in range(1,4) for m in ['normal','reduced'] for d in ['entry','return']}
assert r['complete'] and len(cases)==36 and {v['name'] for v in cases}==expected
for c in cases:
 reduced,closing=c['reduced'],c['closing'];frames=c['frames'];target=0 if closing else 1
 assert reduced==(('reduced' in c['name'])!=closing)
 assert c['configured_duration_us']==(0 if reduced else 160000 if closing else 240000)
 assert frames and all(f['native_flag']==reduced==f['media_query_flag_at_action'] for f in frames)
 assert all(f['controller_duration_us']==c['configured_duration_us'] for f in frames)
 assert frames[0]['value']==(target if reduced else 1-target) and frames[-1]['value']==target
 if reduced:assert all(f['display_value']==target for f in frames)
 else:assert any(not f['offstage'] and 0<f['display_value']<1 for f in frames)
clips=json.loads((O/'recordings.json').read_text());assert len(clips)==18 and all(v['full_decode_exit']==0 for v in clips)
for c in clips:
 for suffix in ['before','after']:
  line=(O/(c['name']+'-'+suffix+'-window.txt')).read_text().splitlines()[0];assert 'mCurrentFocus=' in line and 'io.github.shijijs.video_viewer' in line
code="import sqlite3,json;c=sqlite3.connect('file:/data/library.sqlite3?mode=ro',uri=True);print(json.dumps({n:c.execute('select count(*) from '+n).fetchone()[0] for n in ['videos','packs','pack_sessions','playback_rounds','tags','pack_tag_definitions']}));c.close()"
counts=json.loads(subprocess.check_output(['docker','exec','video-viewer-overlay-motion','python','-c',code]));(L/'catalog-counts.json').write_text(json.dumps(counts,indent=2)+'\n')
trace=[json.loads(v) for v in (O/'trace/requests.jsonl').read_text().splitlines()]
writes=[v for v in trace if v.get('method') not in ['GET','HEAD']]
assert len([v for v in writes if v['path']=='/api/v1/pack-sessions'])==6
assert len([v for v in writes if v['path']=='/api/v1/rounds'])==6
assert all(v['method']=='POST' and (v['path'] in ['/api/v1/auth/login','/api/v1/pack-sessions','/api/v1/rounds'] or v['path'].endswith('/opened')) for v in writes),writes
assert json.loads((O/'restoration.json').read_text())['restored']==json.loads((O/'original-settings.json').read_text())
(L/'audit.json').write_text(json.dumps({'passed_cases':36,'app_sheet_transitions':24,'production_helper_dialog_transitions':12,'recordings':18,'runner_full_decodes':18,'no_file_tag_preference_progress_commands':True,'all_settings_restored':True,'counts':counts,'physical_phone_audio_or_real_save_failure_not_accepted':True},indent=2)+'\n');print('36 traces, 18 finalized recordings, allowed request types and exact restoration verified')

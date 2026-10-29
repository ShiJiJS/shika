import hashlib,json,subprocess
from pathlib import Path
L=Path(__file__).resolve().parent;R=L.parents[1];O=L/'native-1'
read=lambda p:json.loads(p.read_text())
r=read(O/'profile-result.json')['settings_motion'];assert r['complete'] and r['commits']==24
assert len(r['cases'])==24
names={f'round-{n}-{kind}-{motion}-{end}' for n in [1,2,3] for kind in ['theme','preload'] for motion in ['normal','reduced'] for end in ['on','off']}
assert {c['name'] for c in r['cases']}==names
for c in r['cases']:
 fs=c['frames'];assert fs and all(f['native_flag']==c['reduced'] and f['media_query_flag']==c['reduced'] for f in fs)
 target=int(c['target'])
 for k in ['toggle_position']+(['paper_theme_progress'] if c['theme'] else []):
  assert abs(fs[-1][k]-target)<1e-5
  if c['reduced']:assert all(abs(f[k]-target)<1e-5 for f in fs)
  else:assert any(1e-5<f[k]<.99999 for f in fs)
assert read(O/'result.json')=={'exit_code':0,'observer_errors':[],'recordings':12,'finished_at':read(O/'result.json')['finished_at']}
clips=read(O/'recordings.json');assert len(clips)==12 and all(c['full_decode_exit']==0 for c in clips)
assert read(O/'restoration.json')['errors']==[] and 'restored' in read(O/'restoration.json')
source=(L/'source-ref').read_text().strip();assert not subprocess.check_output(['git','diff','--name-only',source,'--','apps/mobile/lib','apps/mobile/integration_test/settings_motion_test.dart'],cwd=R).strip()
prototype=subprocess.check_output(['git','rev-parse','HEAD:design/reference/library-first'],cwd=R,text=True).strip();assert prototype=='1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
assert 'All tests passed!' in (L/'client-tests.log').read_text() and '+740:' in (L/'client-tests.log').read_text()
assert 'No issues found!' in (L/'analyze-final-source.log').read_text()
assert (L/'settings-profile.apk').stat().st_size==read(L/'profile-artifact.json')['bytes']
assert hashlib.sha256((L/'settings-profile.apk').read_bytes()).hexdigest()==read(L/'profile-artifact.json')['sha256']
assert not subprocess.check_output(['git','diff','--name-only','e05cb56e',source,'--','services'],cwd=R).strip()
v={'complete':True,'source':source,'unit_tests':740,'affected_tests':26,'static_switch_pixel_combinations':16,'static_chip_pixel_combinations':16,'native_transitions':24,'native_preference_notifications':24,'fully_decoded_clips':12,'actual_android_flags_not_injected':True,'normal_apk_rebuilt':False,'nas_or_media_actions':False,'service_source_unchanged':True,'prototype_tree':prototype,'live_mid_transition_reduced_proven_in_widget_tests_only':True,'pointer_drag_cancel_proven_in_widget_tests_only':True}
(L/'audit.json').write_text(json.dumps(v,indent=2)+'\n');print(json.dumps(v))

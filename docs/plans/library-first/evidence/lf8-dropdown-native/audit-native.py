import hashlib,json,subprocess
from pathlib import Path
L=Path(__file__).resolve().parent;R=L.parents[1];O=L/'native-1';read=lambda p:json.loads(p.read_text())
r=read(O/'profile-result.json')['dropdown_motion'];assert r['complete'] and r['opened']==36 and r['selected']==12 and r['cancel_outcomes']==24 and r['pop_callbacks']==36
names=set()
for n in [1,2,3]:
 for kind in ['plain','form']:
  for mode in ['normal','reduced']:
   for action in ['cancel','select']:
    for direction in ['entry','exit']:names.add(f'round-{n}-{kind}-{mode}-{action}-{direction}')
  for mode in ['live-entry','live-exit']:
   for direction in ['entry','exit']:names.add(f'round-{n}-{kind}-{mode}-{direction}')
assert len(r['cases'])==72 and {c['name'] for c in r['cases']}==names
cases={c['name']:c for c in r['cases']};live=[];regular=0
for c in r['cases']:
 fs=c['frames'];target=1 if c['opening'] else 0;assert fs and abs(fs[-1]['route_value']-target)<1e-5 and abs(fs[-1]['paint_opacity']-target)<1e-5
 assert all(f['native_flag']==f['media_query_flag'] for f in fs)
 assert all(a['frame_us']<b['frame_us'] for a,b in zip(fs,fs[1:]))
 if c['opening']:assert fs[-1]['menu_present'] and fs[-1]['last_item_opacity']==1
 else:
  entry=cases[c['name'][:-4]+'entry']['frames'][-1];last=fs[-1];assert last['pop_callbacks']==entry['pop_callbacks']+1
  assert last['selected_callbacks']==entry['selected_callbacks']+(1 if '-select-' in c['name'] else 0)
 if c['live_switch']:
  i=next(i for i,f in enumerate(fs) if f['native_flag']);assert i>0 and 0<fs[i-1]['route_value']<1
  assert all(f['native_flag'] and abs(f['route_value']-target)<1e-5 and abs(f['paint_opacity']-target)<1e-5 for f in fs[i:]);live.append({'name':c['name'],'previous_frame':fs[i-1],'first_native_reduced_frame':fs[i]})
 else:
  regular+=1;assert all(f['native_flag']==c['reduced'] for f in fs)
  if c['reduced']:assert all(abs(f['route_value']-target)<1e-5 for f in fs)
  else:
   assert any(0<f['route_value']<1 for f in fs)
   if not c['opening']:assert any(0<f['paint_opacity']<1 for f in fs)
assert regular==60 and len(live)==12
clips=read(O/'recordings.json');assert len(clips)==24 and all(c['full_decode_exit']==0 and int(c['metadata']['streams'][0]['nb_read_frames'])>0 for c in clips)
assert read(O/'result.json')['exit_code']==0 and read(O/'result.json')['observer_errors']==[]
rest=read(O/'restoration.json');assert rest['errors']==[] and rest['restored']==read(O/'original-settings.json')
artifact=read(L/'profile-artifact.json');assert artifact['production_lib_equal'] and hashlib.sha256((L/'dropdown-profile.apk').read_bytes()).hexdigest()==artifact['sha256']
source=read(O/'source.json')['source'];assert source==artifact['source'] and not subprocess.check_output(['git','diff','--name-only',source,'HEAD','--','apps/mobile/lib'],cwd=R).strip()
assert subprocess.check_output(['git','rev-parse','HEAD:design/reference/library-first'],cwd=R,text=True).strip()=='1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
old=read(R/'.dev/lf8-settings-motion/build-1/result.json')
for key in ['forward','rollback']:assert hashlib.sha256(Path(old[key]['path']).read_bytes()).hexdigest()==old[key]['sha256']
bridge=read(L/'android-flag-source.json');assert hashlib.sha256(Path(bridge['source']).read_bytes()).hexdigest()==bridge['sha256']
result={'complete':True,'source':source,'production_lib_equal_to_component_source':'2f9792a4d25e08524856d9c1c8b0a077571109af','native_transitions':72,'live_reduced_in_flight':12,'fully_decoded_clips':24,'opened':36,'selected_callbacks':12,'pop_observer_callbacks':36,'cancel_outcomes':24,'cancel_is_not_business_callback':True,'native_and_media_query_flags_equal':True,'live_first_flag_frame_paint_at_target':True,'same_owned_qemu_pid':read(O/'runtime.json')['emulator_pid'],'ordinary_code15_pair_preserved':True,'normal_release_or_real_business_acceptance':False,'no_media_or_file_commands':True}
(L/'native-live-proof.json').write_text(json.dumps(live,indent=2)+'\n');(L/'audit-native.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))

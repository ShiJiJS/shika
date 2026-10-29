import hashlib,json,os,subprocess,re
from pathlib import Path
L=Path(__file__).resolve().parent;R=L.parents[1];O=L/os.environ.get('VV_CONTROL_RUN','native-5');read=lambda p:json.loads(p.read_text())
r=read(O/'profile-result.json')['checkbox_motion'];assert r['complete'] and r['directions']==90 and r['live_directions']==24 and r['callbacks']=={'trash':18,'row':18} and r['final_values']=={'trash':False,'row':False}
names=set()
for n in [1,2,3]:
 for kind in ['trash','row']:
  p=f'round-{n}-{kind}'
  names.update(p+'-'+mode+'-'+action for mode in ['normal','reduced'] for action in ['select','deselect','press','cancel'])
  names.update(p+'-'+suffix for suffix in ['live-select','live-deselect','live-press','reduced-cancel-after-live','normal-press-before-live','live-cancel','disable-held'])
assert len(r['cases'])==90 and {x['name'] for x in r['cases']}==names
live=[];disable=[];normal_spans=[]
for c in r['cases']:
 fs=c['frames'];target=c['target'];channel=c['channel'];key='position' if channel=='position' else 'reaction';paint='paint_'+key
 assert fs and all(a['frame_us']<b['frame_us'] for a,b in zip(fs,fs[1:]));assert all(f['native_flag']==f['media_query_flag'] for f in fs)
 endpoint=lambda f:abs(f[key]-target)<1e-5 and abs(f[paint]-target)<1e-5
 assert all(endpoint(f) for f in fs[-3:])
 assert all(f['calls']==c['calls_before']+(1 if channel=='position' else 0) for f in fs)
 assert all(f['checkbox_value']==(target==1 if channel=='position' else False) for f in fs)
 for f in fs:
  assert f['position_ms']==(0 if f['native_flag'] else 140)
  assert f['reaction_ms']==(0 if f['native_flag'] else 100)
 if channel=='disable':
  i=next(i for i,f in enumerate(fs) if not f['enabled']);assert i>0 and any(f['down'] and f['reaction']>0 for f in fs[:i]);assert all(endpoint(f) and not f['down'] for f in fs[i:]);disable.append({'name':c['name'],'previous':fs[i-1],'first_disabled':fs[i]})
 elif c['live']:
  i=next(i for i,f in enumerate(fs) if f['native_flag']);assert i>0 and 0<fs[i-1][key]<1;assert all(f['native_flag'] and endpoint(f) for f in fs[i:]);live.append({'name':c['name'],'previous':fs[i-1],'first_native_reduced_frame':fs[i]})
 else:
  assert all(f['native_flag']==c['reduced'] for f in fs)
  if c['reduced']:assert all(endpoint(f) for f in fs)
  else:
   assert any(0<f[key]<1 for f in fs)
   i=next(i for i,f in enumerate(fs) if endpoint(f));normal_spans.append({'name':c['name'],'channel':key,'nominal_ms':140 if key=='position' else 100,'first_observed_to_target_ms':(fs[i]['frame_us']-fs[0]['frame_us'])/1000})
assert len(live)==24 and len(disable)==6
clips=read(O/'recordings.json');expected={f'round-{n}-{kind}' for n in [1,2,3] for kind in ['trash','row']};assert {c['name'] for c in clips}==expected and len(clips)==6
decode=[]
for c in clips:
 p=O/(c['name']+'.mp4');assert c['full_decode_exit']==0
 m=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-count_frames','-show_entries','stream=width,height,nb_read_frames:format=duration','-of','json',str(p)],timeout=40))
 assert int(m['streams'][0]['nb_read_frames'])>0 and (m['streams'][0]['width'],m['streams'][0]['height'])==(1170,2532)
 subprocess.run(['ffmpeg','-v','error','-i',str(p),'-map','0:v:0','-fps_mode','passthrough','-enc_time_base','demux','-f','null','-'],check=True,timeout=40)
 decode.append({'name':c['name'],'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'full_decode_exit':0,'metadata':m})
assert read(O/'result.json')['exit_code']==0 and read(O/'result.json')['observer_errors']==[]
rest=read(O/'restoration.json');assert rest['errors']==[] and rest['restored']==read(O/'original-settings.json')
a=read(L/'profile-artifact-v2.json');assert a['production_lib_equal'] and hashlib.sha256((L/'checkbox-profile-v2.apk').read_bytes()).hexdigest()==a['sha256'];assert read(O/'source.json')['source']==a['source']
assert not subprocess.check_output(['git','diff','--name-only',a['source'],'HEAD','--','apps/mobile/lib'],cwd=R).strip()
s=(R/'apps/mobile/integration_test/checkbox_motion_test.dart').read_text();body=s[s.index('Map<String, dynamic> read()'):s.index('void frame(')];assert re.search(r'\bt\.(state|widget|element)\b',body) is None and all(x not in body for x in ['accessibilityFeaturesTestValue','FakeAccessibilityFeatures'])
old=read(R/'.dev/lf8-checkbox-motion/source-audit.json')
for n,v in old['previous_code16_pairs_unchanged'].items():assert hashlib.sha256((R/'tmp/releases'/n).read_bytes()).hexdigest()==v['sha256']
assert subprocess.check_output(['git','rev-parse','HEAD:design/reference/library-first'],cwd=R,text=True).strip()=='1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
for n,hash in read(R/'.dev/lf8-checkbox-motion/sdk-source.json')['sdk_files'].items():assert hashlib.sha256((R/'.dev/flutter/packages/flutter/lib'/n).read_bytes()).hexdigest()==hash
result={'complete':True,'source':a['source'],'production_lib_same_as_component':'2a4e9cd7','directions':90,'live_real_in_flight':24,'held_disabled':6,'callbacks':r['callbacks'],'decoded_recordings':6,'frame_observer_public_elements_no_tester_api':True,'native_and_mediaquery_flags_match':True,'first_real_native_flag_actual_paint_at_target':True,'same_qemu_pid':read(O/'runtime.json')['emulator_pid'],'normal_code16_pair_preserved':True,'sdk_and_prototype_unchanged':True,'native_component_only_not_normal_main_acceptance':True}
(L/'audit-native.json').write_text(json.dumps(result,indent=2)+'\n');(L/'live-proof.json').write_text(json.dumps(live,indent=2)+'\n');(L/'disabled-proof.json').write_text(json.dumps(disable,indent=2)+'\n');(L/'normal-observed-spans.json').write_text(json.dumps(normal_spans,indent=2)+'\n');(L/'independent-decode.json').write_text(json.dumps(decode,indent=2)+'\n');print(json.dumps(result))

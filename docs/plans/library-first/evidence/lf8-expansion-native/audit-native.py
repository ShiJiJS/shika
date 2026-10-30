import hashlib,json,subprocess,re,os
from pathlib import Path
from collections import Counter
L=Path(__file__).resolve().parent;R=L.parents[1];O=L/os.environ.get('VV_CONTROL_RUN','native-4');read=lambda p:json.loads(p.read_text())
r=read(O/'profile-result.json')['expansion_motion'];assert r['complete'] and r['directions']==18 and r['live_directions']==6 and r['lifecycle_states']==9 and r['lifecycle_pointer_ups']==3
assert not r['accessibility_injected'] and not r['repository_or_file_commands'] and not r['normal_release_acceptance'] and r['actual_production_scan_page']
names={f'round-{n}-{mode}-{direction}' for n in [1,2,3] for mode in ['normal','reduced','live'] for direction in ['expand','collapse']};assert len(r['cases'])==18 and {c['name'] for c in r['cases']}==names
live=[];spans=[];count=0
for c in r['cases']:
 f=c['frames'];target=c['target'];count+=len(f)
 endpoint=lambda a:all(abs(a[k]-v)<1e-5 for k,v in [('value',target),('height',target),('turns',target*.5)])
 assert all(a['frame_us']<b['frame_us'] for a,b in zip(f,f[1:]));assert all(endpoint(a) for a in f[-3:])
 ratios=[]
 for a in f:
  assert a['expanded']==(target==1) and a['tile_present'] and a['node_counts']==[1,1,1]
  assert a['native_flag']==a['media_query_flag'] and a['duration_ms']==(0 if a['native_flag'] else 160)
  assert abs(a['height']-2*a['turns'])<1e-5
  if a['height']>0:assert a['body_px']>0;ratios.append(a['body_px']/a['height'])
  else:assert a['body_px']==0
 assert ratios or target==0
 if ratios:assert max(ratios)-min(ratios)<1
 if c['live']:
  i=next(i for i,a in enumerate(f) if a['native_flag']);assert i>0 and 0<f[i-1]['value']<1 and 0<f[i-1]['height']<1;assert all(a['native_flag'] and endpoint(a) for a in f[i:]);live.append({'name':c['name'],'previous':f[i-1],'first_native_reduced_frame':f[i]})
 elif c['reduced']:assert all(a['native_flag'] and endpoint(a) for a in f)
 else:
  assert all(not a['native_flag'] for a in f) and any(0<a['value']<1 and 0<a['height']<1 for a in f)
  i=next(i for i,a in enumerate(f) if endpoint(a));spans.append({'name':c['name'],'nominal_ms':160,'first_observed_to_target_ms':(f[i]['frame_us']-f[0]['frame_us'])/1000})
assert len(live)==6
assert len(r['lifecycle'])==9 and {x['name'] for x in r['lifecycle']}=={f'round-{n}-{stage}' for n in [1,2,3] for stage in ['scanning','failed','completed']}
for x in r['lifecycle']:
 a=x['before'];b=x['frame'];assert a['expanded'] and 0<a['height']<1 and 0<a['value']<1 and a['body_px']>0 and a['fixture_timer_ms']==40
 assert not a['native_flag'] and not a['media_query_flag'] and b['frame_us']>=a['frame_us'];assert b['tile_present']==(x['stage']=='completed') and b['cards']==(0 if x['stage']=='completed' else 1)
 if x['stage']=='scanning':assert '4 / 5 个' in b['preparation_summary']
 elif x['stage']=='failed':assert b['preparation_summary']=='扫描失败' and b['failure_detail_present']
 else:assert b['height']==0 and not b['expanded'] and '5 / 5 个' in b['header_summary']
events=read(O/'events.json');actions=Counter(x['action'] for x in events);assert actions['tap']==15 and actions['tap_reduce']==6 and actions['capture']==9 and actions['begin']==actions['end']==3
for x in events:
 if x['action'] in ['configure','tap_reduce']:assert set(x['actual'].values())==({'0'} if x['action']=='tap_reduce' or x.get('reduced') else {'1'})
clips=read(O/'recordings.json');assert len(clips)==3 and {c['name'] for c in clips}=={'round-1','round-2','round-3'};decode=[]
for c in clips:
 p=O/(c['name']+'.mp4');m=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-count_frames','-show_entries','stream=width,height,nb_read_frames:format=duration','-of','json',str(p)],timeout=40));s=m['streams'][0];assert (s['width'],s['height'])==(1170,2532) and int(s['nb_read_frames'])>0 and c['full_decode_exit']==0
 subprocess.run(['ffmpeg','-v','error','-i',str(p),'-map','0:v:0','-fps_mode','passthrough','-enc_time_base','demux','-f','null','-'],check=True,timeout=40)
 decode.append({'name':c['name'],'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'metadata':m,'full_decode_exit':0})
assert read(O/'result.json')['exit_code']==0 and not read(O/'result.json')['observer_errors'];rest=read(O/'restoration.json');assert not rest['errors'] and rest['restored']==read(O/'original-settings.json')
a=read(L/'profile-artifact-v4.json');assert a['source']==read(O/'source.json')['source'] and a['production_lib_equal'];assert hashlib.sha256((L/'expansion-profile-v4.apk').read_bytes()).hexdigest()==a['sha256'];assert not subprocess.check_output(['git','diff','--name-only',a['source'],'HEAD','--','apps/mobile/lib'],cwd=R).strip()
s=(R/'apps/mobile/integration_test/expansion_motion_test.dart').read_text();body=s[s.index('Map<String, dynamic> read()'):s.index('void frame(')];assert re.search(r'\bt\.(state|widget|element)\b',body) is None and 'expect(' not in body and 'FakeAccessibilityFeatures' not in s
old=read(R/'.dev/lf8-expansion-motion/baseline-audit.json')
for n,h in old['previous_code17_pair'].items():assert hashlib.sha256((R/'tmp/releases'/n).read_bytes()).hexdigest()==h
for n,h in old['sdk'].items():assert hashlib.sha256((R/'.dev/flutter/packages/flutter/lib/src'/n).read_bytes()).hexdigest()==h
assert subprocess.check_output(['git','rev-parse','HEAD:design/reference/library-first'],cwd=R,text=True).strip()==old['prototype_tree']
result={'complete':True,'source':a['source'],'production_same_as':'6af88978','directions':18,'real_in_flight_flags':6,'observed_motion_frames':count,'lifecycle_native_taps':3,'lifecycle_states':9,'decoded_recordings':3,'public_node_observer_without_tester_queries_or_expect':True,'actual_render_height_and_arrow_match':True,'first_native_reduced_frame_at_endpoint':True,'same_qemu_pid':read(O/'runtime.json')['emulator_pid'],'normal_code17_sdk_prototype_preserved':True,'actual_scan_fixture_not_normal_main_acceptance':True}
for n,v in [('audit-native',result),('live-proof',live),('normal-observed-spans',spans),('independent-decode',decode)]: (L/(n+'.json')).write_text(json.dumps(v,indent=2)+'\n')
print(json.dumps(result))

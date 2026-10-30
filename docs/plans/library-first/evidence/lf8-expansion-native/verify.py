"""Offline read-only raw-frame verification; optional --decode needs ffmpeg."""
import argparse,hashlib,json,re,subprocess
from collections import Counter
from pathlib import Path
p=argparse.ArgumentParser(__doc__);p.add_argument('--decode',action='store_true');args=p.parse_args()
L=Path(__file__).resolve().parent;O=L/'native-4';read=lambda p:json.loads(p.read_text())
m=read(L/'manifest.json')
for name,v in m['files'].items():
 data=(L/name).read_bytes();assert len(data)==v['bytes'] and hashlib.sha256(data).hexdigest()==v['sha256'],name
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

assert r['additional_lifecycle_taps']==3 and r['recording_groups']==3
for n in range(1,5):
 d=L/f'native-{n}';result=read(d/'result.json');rest=read(d/'restoration.json')
 assert not rest['errors'] and rest['restored']==read(d/'original-settings.json')
 assert read(d/'runtime.json')['emulator_pid']==60176
 assert result['exit_code']==(0 if n==4 else 1) and not result['observer_errors']
 if n<4:assert len(read(d/'profile-result.json')['expansion_motion']['cases'])==6
meta=read(L/'profile-artifact-v4.json');assert meta['source']==m['source']==read(O/'source.json')['source']
assert meta['production_lib_equal'] and meta['lib_trees']['component']==meta['lib_trees']['native']
assert read(O/'source.json')['prototype_tree']==m['prototype_tree']
obs=(L/'expansion_motion_test-v4.dart').read_text();body=obs[obs.index('Map<String, dynamic> read()'):obs.index('void frame(')]
assert re.search(r'\bt\.(state|widget|element)\b',body) is None and 'expect(' not in body and 'FakeAccessibilityFeatures' not in obs
cleanup=read(L/'cleanup-native.json');assert cleanup['complete'] and cleanup['owned_qemu_absent'] and cleanup['settings_restored']
assert cleanup['original4_services_preserved_healthy']==read(O/'runtime.json')['original_container_ids']
clips=read(L/'independent-decode.json');assert len(clips)==3
for c in clips:
 video=O/(c['name']+'.mp4');stream=c['metadata']['streams'][0]
 assert hashlib.sha256(video.read_bytes()).hexdigest()==c['sha256'] and c['full_decode_exit']==0
 assert (stream['width'],stream['height'])==(1170,2532) and int(stream['nb_read_frames'])>0
 if args.decode:subprocess.run(['ffmpeg','-v','error','-i',str(video),'-map','0:v:0','-fps_mode','passthrough','-enc_time_base','demux','-f','null','-'],check=True,timeout=40)
assert count==136 and len(live)==6
print(json.dumps({'complete':True,'files':len(m['files']),'directions':18,'frames':count,'real_in_flight_switches':6,'lifecycle_states':9,'recordings':3,'decoded_again':args.decode,'normal_main_acceptance':False}))

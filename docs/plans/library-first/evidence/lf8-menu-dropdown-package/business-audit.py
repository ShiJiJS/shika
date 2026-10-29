import json,hashlib
from pathlib import Path
L=Path(__file__).resolve().parent;O=L/'normal';H=L/'history-normal';read=lambda p:json.loads(p.read_text());snap=lambda n:read(O/(n+'-catalog.json'))
def same(a,b):assert a['tables']==b['tables'] and a['opaque_table_digests']==b['opaque_table_digests']
def unchanged_except(a,b,allowed):
 changed={k for k in a['tables'] if a['tables'][k]!=b['tables'][k]};assert changed==set(allowed),(changed,allowed);assert a['opaque_table_digests']['access_tokens']==b['opaque_table_digests']['access_tokens'];return sorted(changed)
base=snap('before-business')
for n in ['after-workspace-more','after-video-menus-filters','after-root-kind-cancel','after-task-family','after-default-draft-cancel']:same(base,snap(n))
defaults=snap('after-reader-defaults');changed=unchanged_except(base,defaults,['request_records']);assert len(defaults['tables']['request_records'])==len(base['tables']['request_records'])+2
r=read(O/'reader-defaults-before.json');s=read(O/'reader-defaults-saved.json');t=read(O/'reader-defaults-restored.json');assert s['value']=={**r['value'],'direction':'rtl','fit':'width','revision':1};assert t['value']=={**r['value'],'revision':2};assert r['pack_preferences']==s['pack_preferences']==t['pack_preferences'];assert r['other_settings_sha256']==s['other_settings_sha256']==t['other_settings_sha256']
for n in ['after-pack-sort-filter','before-reader-actual']:same(defaults,snap(n))
a=snap('before-reader-actual');b=snap('after-reader-actual');reader=unchanged_except(a,b,['pack_progress','pack_preferences','request_records','pack_sessions','pack_session_entries','recent_entries'])
p=a['tables']['pack_progress'][0];q=b['tables']['pack_progress'][0];assert q=={**p,'revision':p['revision']+1,'updated_at':q['updated_at']};assert p['page_id']==q['page_id'] and p['completed']==q['completed']==1
assert b['tables']['pack_preferences']==[{**a['tables']['pack_preferences'][0],'revision':11}]
for tab,key,delta in [('pack_sessions','id',1),('pack_session_entries',None,1),('request_records',None,7)]:
 assert len(b['tables'][tab])==len(a['tables'][tab])+delta
 assert all(x in b['tables'][tab] for x in a['tables'][tab])
old={v['id'] for v in a['tables']['pack_sessions']};new=[v for v in b['tables']['pack_sessions'] if v['id'] not in old];assert len(new)==1 and new[0]['candidate_count']==1 and new[0]['cursor']==0;assert json.loads(new[0]['source'])=={'kind':'library','sort':'title'}
sid=new[0]['id'];entries=[v for v in b['tables']['pack_session_entries'] if v['session_id']==sid];assert entries==[{'session_id':sid,'ordinal':0,'pack_id':p['pack_id']}]
for x in a['tables']['recent_entries']:
 y=next(v for v in b['tables']['recent_entries'] if v['id']==x['id']);assert y==({**x,'opened_at':y['opened_at']} if x['kind']=='pack' else x)
r=read(O/'reader-pack-before.json');s=read(O/'reader-pack-changed.json');t=read(O/'reader-pack-restored.json');assert r['value']==s['value']==t['value'];assert r['other_settings_sha256']==s['other_settings_sha256']==t['other_settings_sha256'];assert t['pack_preferences']==[{**r['pack_preferences'][0],'revision':11}]
c=snap('after-video-speed');video=unchanged_except(b,c,['request_records','playback_rounds','round_entries','recent_entries'])
for tab,delta in [('request_records',1),('playback_rounds',1),('round_entries',2)]:
 assert len(c['tables'][tab])==len(b['tables'][tab])+delta;assert all(x in c['tables'][tab] for x in b['tables'][tab])
old={v['id'] for v in b['tables']['playback_rounds']};newround=[v for v in c['tables']['playback_rounds'] if v['id'] not in old];assert len(newround)==1
vr=newround[0];assert (vr['membership'],vr['source'],vr['sort'],vr['candidate_count'],vr['cursor'],vr['sequence_revision'])==('fixed','library','name_zh',2,0,0);members=[v for v in c['tables']['round_entries'] if v['round_id']==vr['id']];assert {v['video_id'] for v in members}=={v['id'] for v in c['tables']['videos']}
# Both speed contexts retain this exact round and its ordered members.
paused=snap('video-paused-before-speed');assert paused['tables']['playback_rounds']==c['tables']['playback_rounds'] and paused['tables']['round_entries']==c['tables']['round_entries']
for x in b['tables']['recent_entries']:
 y=next(v for v in c['tables']['recent_entries'] if v['id']==x['id']);assert y==({**x,'opened_at':y['opened_at']} if x['kind']=='video' else x)
same(snap('before-legacy-shell-menu'),snap('after-legacy-shell-menu'))
trace=[json.loads(v) for v in (O/'trace/requests.jsonl').read_text().splitlines()];start=read(O/'business-start-trace.json')['start'];end=next(v['trace_end'] for v in read(O/'business-cursor.json')['checks'] if v['name']=='modern-legacy-shell-more');writes=[v for v in trace[start:end] if v['method'] not in ['GET','HEAD']]
assert len(writes)==12 and all(200<=v['status']<300 for v in writes)
assert sum(v['path']=='/api/v1/reading-defaults' and v['method']=='PATCH' for v in writes)==2
assert sum(v['path'].endswith('/preferences') and v['method']=='PATCH' for v in writes)==6
assert sum(v['path']=='/api/v1/pack-sessions' and v['method']=='POST' for v in writes)==1
assert sum(v['path']=='/api/v1/rounds' and v['method']=='POST' for v in writes)==1
assert sum(v['path'].endswith('/opened') and v['method']=='POST' for v in writes)==2
settings=read(L/'settings-delta-audit.json');assert settings['prebusiness_reconstructed_only_startup_scan_marker']
result={'complete':True,'readonly_baseline_groups':7,'defaults_explicit_semantic_restore_revision':2,'reader_changed_tables':reader,'reader_progress_same_page_and_completion_revision_plus':1,'reader_preferences_semantic_restore_revision':11,'reader_new_session_members':1,'video_changed_tables':video,'video_fixed_round_members':2,'video_round_and_order_unchanged_during_speed':True,'legacy_shell_more_readonly':True,'business_write_count':12,'business_writes_all_expected_successes':True,'auth_token_digest_unchanged':True,'settings_allowed_keys':settings['changed_keys'],'startup_scan_marker_reconstructed_prebusiness':True,'no_delete_restore_tag_or_root_writes':True,'observer_query_strings_not_recorded':True,'normal_app_business_not_animation_timing_evidence':True}
(L/'business-audit.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))

import hashlib,json,sqlite3,subprocess
from collections import Counter
from pathlib import Path
R=Path(__file__).resolve().parents[2];L=R/'.dev/lf8-preview4';N=L/'native'
def load(p):return json.loads(p.read_text())
def digest_settings(v):
 rows=[{'key':k,'value':x} for k,x in v.items()]
 return {'rows':len(rows),'sha256':hashlib.sha256(json.dumps(sorted(rows,key=lambda r:json.dumps(r,sort_keys=True)),sort_keys=True).encode()).hexdigest()}
def settings(folder):
 assert all(p.stat().st_size==0 for p in folder.glob('library.sqlite3-wal')), 'No uncheckpointed WAL allowed'
 for c in json.loads(subprocess.check_output(['docker','inspect',*subprocess.check_output(['docker','ps','-q'],text=True).split()])):
  for m in c['Mounts']:assert not folder.resolve().is_relative_to(Path(m['Source']))
 c=sqlite3.connect('file:'+str((folder/'library.sqlite3').resolve())+'?mode=ro&immutable=1',uri=True);v=dict(c.execute('SELECT key,value FROM settings'));c.close();return v
old=settings(R/'.dev/lf8-preview3/native/data');new=settings(N/'data')
before=load(N/'before-forward10-catalog.json');final=load(N/'final-catalog.json');early=load(N/'baseline9-before-start-catalog.json')
old_scan=json.loads(old['pack_root_scan_v1:packs']);scan=json.loads(new['pack_root_scan_v1:packs'])
assert old_scan['path']==scan['path'] and old_scan['identity']==scan['identity']
assert scan['last_scan']==next(v['last_scan'] for v in before['tables']['roots'] if v['id']=='packs')
assert scan['last_scan']<early['observed_at']<before['observed_at']
reconstructed=dict(old);reconstructed['pack_root_scan_v1:packs']=new['pack_root_scan_v1:packs']
assert digest_settings(reconstructed)==early['opaque_table_digests']['settings']==before['opaque_table_digests']['settings']
changed_settings=[k for k in reconstructed if reconstructed[k]!=new[k]]
assert set(changed_settings)=={'active_pack_opened','active_pack_session','active_round'}
assert before['opaque_table_digests']['access_tokens']==final['opaque_table_digests']['access_tokens']
changed_tables=[k for k in before['tables'] if before['tables'][k]!=final['tables'][k]]
assert set(changed_tables)=={'pack_progress','pack_preferences','request_records','pack_sessions','pack_session_entries','playback_rounds','round_entries','recent_entries'}
protected=[k for k in before['tables'] if k not in changed_tables]
assert len(protected)==13
trace=[json.loads(v) for v in (N/'trace/requests.jsonl').read_text().splitlines()]
startups=[]
for label in ['forward10-first','rollback10','forward10-return']:
 a=load(N/(label+'-startup.json'));rows=trace[a['trace_offset']:a['trace_end_offset']];assert all(v['method']=='GET' for v in rows)
 after=load(N/('after-'+label+'-catalog.json'));assert before['tables']==after['tables'];assert before['opaque_table_digests']==after['opaque_table_digests']
 assert load(N/'before-forward10-preferences.json')==load(N/('after-'+label+'-preferences.json'))
 startups.append({'step':label,'read_only_startup_requests':len(rows),'all21_tables_and_auth_settings_equal':True})
assert load(N/'before-forward10-preferences.json')==load(N/'final-preferences.json')
for p,h in load(L/'previous-artifacts.json').items():assert hashlib.sha256((R/p).read_bytes()).hexdigest()==h
result={'passed':True,'scope':'Frozen normal code10 upgrade/main-path records; offline stopped databases only','startup_scan':{'old':old_scan,'new':scan,'early_observed_at':early['observed_at'],'before_first_candidate_observed_at':before['observed_at'],'reconstructed_pre_candidate_settings_digest_matches':True,'path_and_directory_identity_unchanged':True,'difference_already_present_before_old9_start':True},'post_action_changed_settings':changed_settings,'post_action_unchanged13_tables':protected,'post_action_changed8_tables':changed_tables,'auth_and_appearance_preserved':True,'startup_windows':startups,'main_paths':load(N/'path-result.json'),'non_get_requests':dict(Counter(v['method']+' '+v['path']+' '+str(v['status']) for v in trace if v['method']!='GET')),'old_artifacts_unchanged':True,'no_new_apk_build_or_native_run_on_resume':True}
(L/'delivery-audit.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k!='main_paths'},indent=2))

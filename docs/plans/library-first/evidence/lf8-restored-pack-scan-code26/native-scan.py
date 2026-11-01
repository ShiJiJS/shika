import json,time
import api,helpers as f,media,ui
from snapshot_all import snapshot
L=ui.L
before=json.loads((L/'before-native-directory-scan-all-catalog.json').read_text());files=json.loads((L/'before-native-directory-scan-files.json').read_text())
trace=lambda:[json.loads(x) for x in (L/'requests.jsonl').read_text().splitlines()]
state=json.loads((L/'native-scan-state.json').read_text())
task=api.wait(state['task_id']);assert task['status']=='completed' and task['result']['packs']['deferred']==0
assert task['result']['scope']=={'all':False,'root_ids':['purge']}
assert task['result']['packs']['failure_reasons']=={'pack_empty':8}
f.until(lambda n:'扫描此目录' in f.labels(n) and '正在扫描' not in f.labels(n),'same directory terminal progress')
after=json.loads((L/'after-native-directory-scan-all-catalog.json').read_text())
protected=[k for k in before['tables'] if k not in ['directories','observations','pack_file_steps','pack_pages','packs','roots','tasks']]
assert all(before['tables'][k]==after['tables'][k] for k in protected)
assert before['opaque_table_digests']['access_tokens']==after['opaque_table_digests']['access_tokens']
assert all(v==after['setting_key_sha256'][k] for k,v in before['setting_key_sha256'].items() if k not in ['pack_root_scan_v1:purge','root_scan_progress_v1:purge'])
without_scan=lambda rows:{r['id']:{k:v for k,v in r.items() if k!='seen_scan'} for r in rows}
assert without_scan(before['tables']['pack_pages'])==without_scan(after['tables']['pack_pages'])
assert media.files()==files
posts=[r for r in trace() if r['method']=='POST' and r['path']=='/api/v1/scans']
assert len(posts)==1 and posts[0]['command']=={'root_id':'purge'} and posts[0]['status']==202
assert not [r for r in trace() if r['method']=='POST' and r['path'].startswith(('/api/v1/pack-trash/permanent','/api/v1/pack-restore'))]
state.update(phase='native_scoped_scan_verified',task=task,only_one_native_scan_post=True,pack_page_ids_and_content_unchanged_except_seen_scan=True,initial_seen_scan_comparison_corrected_without_resubmission=True,protected_28_tables_unchanged=protected,non_scan_settings_and_credentials_unchanged=True,all_49_files_unchanged=True,no_native_delete_restore_post=True)
(L/'native-scan-state.json').write_text(json.dumps(state,indent=2));print({'normal_code':26,'one_native_scoped_scan':state['task_id'],'scope':task['result']['scope'],'same_pack_pages':True,'known_empty_packs':8,'remaining_files':49},flush=True)
ui.choose('返回设置');ui.choose('最近');ui.choose('图包');f.until(lambda n:any('Restore-partial' in x for x in f.labels(n)) and any('Restore-read-tall' in x for x in f.labels(n)),'recovered original and tall in recent');ui.snap('04-recovered-recent-three-packs');print(f.labels())

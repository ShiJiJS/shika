import json,time
import api,helpers as f,media,ui
from snapshot_all import snapshot
L=ui.L
assert not (L/'native-scan-state.json').exists()
before=snapshot('normal26','before-native-directory-scan');files=media.save('before-native-directory-scan')
trace=lambda:[json.loads(x) for x in (L/'requests.jsonl').read_text().splitlines()]
assert not [r for r in trace() if r['method']=='POST' and r['path']=='/api/v1/scans']
ui.choose('扫描此目录')
state={'phase':'native_scan_clicked','root_id':'purge','before_task_ids':[t['id'] for t in before['tables']['tasks']]}
(L/'native-scan-state.json').write_text(json.dumps(state,indent=2))
deadline=time.monotonic()+45
while True:
    new=[t for t in api.call('GET','/api/v1/tasks?limit=100')['items'] if t['id'] not in state['before_task_ids']]
    if new:break
    assert time.monotonic()<deadline;time.sleep(.1)
assert len(new)==1 and new[0]['kind']=='scan'
state['task_id']=new[0]['id'];(L/'native-scan-state.json').write_text(json.dumps(state,indent=2))
task=api.wait(new[0]['id']);assert task['status']=='completed' and task['result']['packs']['deferred']==0
assert task['result']['scope']=={'all':False,'root_ids':['purge']}
assert task['result']['packs']['failure_reasons']=={'pack_empty':8}
f.until(lambda n:'扫描此目录' in f.labels(n) and '正在扫描' not in f.labels(n),'same directory terminal progress')
ui.snap('03-directory-native-scan-result')
after=snapshot('normal26','after-native-directory-scan')
protected=[k for k in before['tables'] if k not in ['directories','observations','pack_file_steps','pack_pages','packs','roots','tasks']]
assert all(before['tables'][k]==after['tables'][k] for k in protected)
assert before['opaque_table_digests']['access_tokens']==after['opaque_table_digests']['access_tokens']
assert all(v==after['setting_key_sha256'][k] for k,v in before['setting_key_sha256'].items() if k not in ['pack_root_scan_v1:purge','root_scan_progress_v1:purge'])
assert before['tables']['pack_pages']==after['tables']['pack_pages']
assert media.files()==files
posts=[r for r in trace() if r['method']=='POST' and r['path']=='/api/v1/scans']
assert len(posts)==1 and posts[0]['command']=={'root_id':'purge'} and posts[0]['status']==202
assert not [r for r in trace() if r['method']=='POST' and r['path'].startswith(('/api/v1/pack-trash/permanent','/api/v1/pack-restore'))]
state.update(phase='native_scoped_scan_verified',task=task,only_one_native_scan_post=True,pack_page_ids_and_rows_unchanged=True,protected_28_tables_unchanged=protected,non_scan_settings_and_credentials_unchanged=True,all_49_files_unchanged=True,no_native_delete_restore_post=True)
(L/'native-scan-state.json').write_text(json.dumps(state,indent=2));print({'normal_code':26,'one_native_scoped_scan':state['task_id'],'scope':task['result']['scope'],'same_pack_pages':True,'known_empty_packs':8,'remaining_files':49},flush=True)
ui.choose('返回设置');ui.choose('最近');ui.choose('图包');f.until(lambda n:any('Restore-partial' in x for x in f.labels(n)) and any('Restore-read-tall' in x for x in f.labels(n)),'recovered original and tall in recent');ui.snap('04-recovered-recent-three-packs');print(f.labels())

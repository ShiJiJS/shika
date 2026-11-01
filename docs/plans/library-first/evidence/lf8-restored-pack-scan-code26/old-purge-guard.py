import json
import api,helpers as f,media,ui
from snapshot_all import snapshot
L=ui.L;identity='d4b047ca-b106-46b4-9d7d-1c3e820b5eee'
_,nodes=ui.xml();assert identity in '\n'.join(f.labels(nodes))
assert not (L/'old-purge-after-scan.json').exists()
before=snapshot('normal26','before-old-purge-after-scan');files=media.save('before-old-purge-after-scan')
ui.choose('查看逐项图片结果');f.until(lambda n:'已确认删除 2/3 张' in f.labels(n),'original two of three before retry')
ui.choose('重试原任务');f.until(lambda n:'重试未完成项' in f.labels(n),'explicit original retry confirmation');ui.choose('重试未完成项')
f.until(lambda n:'已确认删除 2/3 张' in f.labels(n),'same task after retry');task=api.wait(identity,route='/api/v1/pack-operations/')
assert task['error']=='stale_pack_state' and task['result']['pages_deleted']==2 and task['result']['pages_total']==3
ui.snap('13-old-purge-protected-after-scan');after=snapshot('normal26','after-old-purge-after-scan')
protected=[k for k in before['tables'] if k not in ['tasks','request_records']]
assert all(before['tables'][k]==after['tables'][k] for k in protected)
for key in ['opaque_table_digests','setting_key_sha256']:assert before[key]==after[key]
assert media.files()==files and len(files)==49
trace=[json.loads(x) for x in (L/'requests.jsonl').read_text().splitlines()]
retries=[r for r in trace if r['method']=='POST' and r['path']=='/api/v1/pack-operations/'+identity+'/retry'];assert len(retries)==1 and retries[0]['status']==202
assert not [r for r in trace if r['method']=='POST' and r['path'].startswith(('/api/v1/pack-trash/permanent','/api/v1/pack-restore'))]
(L/'old-purge-after-scan.json').write_text(json.dumps({'task_id':identity,'task':task,'explicit_native_retry_posts':1,'same_remaining_image_and_attachments_preserved':True,'all_49_files_identical':True,'protected_33_tables_identical':protected,'settings_credentials_identical':True,'no_new_permanent_restore_post':True},indent=2));print({'same_task':identity,'error':task['error'],'deleted':task['result']['pages_deleted'],'all_49_files_preserved':True},flush=True)

import json,time,subprocess
import ui,helpers as f,api,snapshot_all
L=ui.L
held=json.loads((L/'native-restore-held.json').read_text());identity=held['original_task']['id']
assert json.loads((L/'control/executor.json').read_text())['hold_after_commit']
assert not (L/'native-immediate-intent.json').exists()
f.settings_row('备份与恢复')
f.until(lambda n:any(x.startswith('恢复前的快照\n') for x in f.labels(n)),'new restore point')
ui.snap('06-fresh-backup-page-cleanup-still-held')
(L/'native-immediate-intent.json').write_text(json.dumps({'time':time.time(),'held_restore':identity}))
f.prefix('恢复前的快照\n')
end=time.monotonic()+30
while True:
    requests=[json.loads(x) for x in (L/'requests.jsonl').read_text().splitlines()]
    accepted=[x for x in requests if x['method']=='POST' and '/from-snapshot/' in x['path']]
    if len(accepted)==2:break
    assert time.monotonic()<end,'Same inspection; do not tap again'
    time.sleep(.1)
new=accepted[-1];assert new['status']==202 and new['request_epoch_sha256']==held['marker']['management_epoch_sha256']
new_id=new['response_task']['id'];task=api.call('GET','/api/v1/tasks/'+new_id)
assert task['status']=='queued'
original=api.call('GET','/api/v1/tasks/'+identity);assert original==held['original_task']
assert json.loads((L/'control/executor.json').read_text())['hold_after_commit']
runtime=json.loads((L/'runtime.json').read_text());container=json.loads(subprocess.check_output(['docker','inspect',runtime['id']]))[0]
assert container['State']['Health']['Status']=='healthy' and container['RestartCount']==0
snapshot_all.snapshot('held','S1-committed-and-next-inspection-queued')
(L/'native-immediate-accepted.json').write_text(json.dumps({'restore_id':identity,'original_task_unchanged':True,'accepted':new,'queued_task':task,'same_container_healthy':True,'restart_count':0,'hold_still_armed':True},indent=2))
print(f.labels(ui.snap('07-next-inspection-accepted-during-cleanup')))

import json,time
import ui,helpers as f,fixture_control,media,snapshot_all,api
L=ui.L
assert not (L/'native-restore-intent.json').exists()
before=snapshot_all.snapshot('native','before-native-restore')
media.save('before-native-restore')
assert len(before['tables']['pack_tag_definitions'])==1
fixture_control.write(L/'control/executor.json',{'hold_after_commit':True})
ui.choose('我知道恢复会替换现有管理数据')
(L/'native-restore-intent.json').write_text(json.dumps({'time':time.time(),'one_confirmed_native_restore':True}))
ui.choose('确认恢复')
end=time.monotonic()+60
while not (L/'control/committed.json').exists():
    assert time.monotonic()<end,'Waiting same restore; do not resubmit'
    time.sleep(.1)
marker=json.loads((L/'control/committed.json').read_text())
assert marker['task_status']=='completed' and marker['maintenance_task'] is None and marker['maintenance_owner_cleared'] and marker['durable_reservation_empty']
task=api.call('GET','/api/v1/tasks/'+marker['task_id'])
assert task['status']=='completed'
(L/'native-restore-held.json').write_text(json.dumps({'marker':marker,'original_task':task},indent=2))
f.until(lambda n:'恢复备份' not in f.labels(n),'native restore sheet closes',60)
print(f.labels(ui.snap('05-restore-completed-cleanup-held')))

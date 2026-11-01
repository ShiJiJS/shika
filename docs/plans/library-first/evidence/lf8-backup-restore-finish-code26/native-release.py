import json,time
import ui,helpers as f,fixture_control,api,snapshot_all,media
L=ui.L
accepted=json.loads((L/'native-immediate-accepted.json').read_text())
assert json.loads((L/'control/executor.json').read_text())['hold_after_commit']
fixture_control.write(L/'control/executor.json',{})
(L/'native-cleanup-release.json').write_text(json.dumps({'time':time.time(),'same_original_restore':accepted['restore_id'],'no_resubmission':True}))
task=api.wait(accepted['queued_task']['id']);assert task['status']=='completed'
assert task['result']['counts']['pack_tag_definitions']==1
f.until(lambda n:'确认恢复' in f.labels(n),'queued inspection opens original preview',60)
ui.snap('08-queued-inspection-opens-S0-preview')
ui.choose('取消')
f.until(lambda n:'确认恢复' not in f.labels(n),'cancel closes preview')
after=snapshot_all.snapshot('after-inspect','S1-after-inspection-cancel')
assert len(after['tables']['pack_tag_definitions'])==2
assert media.save('after-inspection-cancel')==json.loads((L/'generated-native-inputs-files.json').read_text())
original=api.call('GET','/api/v1/tasks/'+accepted['restore_id'])
assert original==json.loads((L/'native-restore-held.json').read_text())['original_task']
(L/'native-inspection-completed.json').write_text(json.dumps({'original_restore':original,'queued_inspection':task,'active_S1_tags':2,'preview_S0_tags':1,'cancel_did_not_restore':True,'media_unchanged':True},indent=2))
print(f.labels(ui.snap('09-preview-cancel-active-S1-preserved')))

import sys,json,time,subprocess
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import ui,api,facts,gestures
from snapshot_all import snapshot
_,nodes=ui.xml();assert any(n.get('content-desc')=='1 / 5' for n in nodes);assert any(n.get('content-desc')=='纵向拼接' for n in nodes)
before=snapshot('new25','grid-before-pinch');seq=max(r['seq'] for r in facts.trace());gestures.run('grid-expand',gestures.expand);ui.snap('17-grid-tall-pinch');after=snapshot('new25','grid-after-pinch')
for k in ['tables','opaque_table_digests','setting_key_sha256']:assert before[k]==after[k],k
assert not [r for r in facts.trace() if r['seq']>seq and r['method'] not in ['GET','HEAD']]
p0=after['tables']['pack_progress'];gestures.run('grid-single-two-single',gestures.handoff);time.sleep(1);ui.snap('18-grid-remaining-finger');moved=snapshot('new25','grid-after-handoff');changed=[k for k in after['tables'] if after['tables'][k]!=moved['tables'][k]];assert 'pack_progress' in changed;assert set(changed)<={'pack_progress','request_records'},changed
assert after['opaque_table_digests']==moved['opaque_table_digests'];assert after['setting_key_sha256']==moved['setting_key_sha256']
seq=max(r['seq'] for r in facts.trace());gestures.run('grid-shrink',gestures.shrink);ui.snap('19-grid-shrink-min');shrunk=snapshot('new25','grid-after-shrink')
for k in ['tables','opaque_table_digests','setting_key_sha256']:assert moved[k]==shrunk[k],k
assert not [r for r in facts.trace() if r['seq']>seq and r['method'] not in ['GET','HEAD']]
facts.mem('grid-tall-gestures');(ui.L/'grid-gesture-checks.json').write_text(json.dumps({'normal_code':25,'kernel_device':'virtio_input_multi_touch_1','real_slots':[0,1],'pinch_business_and_settings_equal':True,'pinch_writes':0,'single_then_two_then_remaining_single':True,'handoff_changed_tables':changed,'shrink_business_and_settings_equal':True,'shrink_writes':0,'scale_not_instrumented':True,'exact_caps_in_component_checks':True,'visual_comparison':'pending'},indent=2)+'\n');print('Tall grid native pinch, single/two/remaining-single, shrink executed; only intended vertical handoff saved position',flush=True)

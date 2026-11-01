import sys,json,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import ui,facts
from snapshot_all import snapshot
_,nodes=ui.xml();found=[n for n in nodes if '\n03-invalid\n' in n.get('content-desc','') and n.get('clickable')=='true'];assert len(found)==1;ui.tap(found[0],'open-public-known-bad-pack-from-unfiltered-visible-card');deadline=time.monotonic()+45
while True:
 _,nodes=ui.xml()
 if any(n.get('content-desc')=='1 / 2' for n in nodes):break
 assert time.monotonic()<deadline
ui.device('shell','input','tap','540','700');time.sleep(.05);ui.device('shell','input','tap','540','700');ui.snap('24-invalid-good-page-zoom')
# Real vertical drags bring the error page into view without a jump (jump resets zoom).
for i in range(8):
 ui.device('shell','input','swipe','600','1700','600','500','600');time.sleep(.2);_,nodes=ui.xml()
 if any((n.get('content-desc') or n.get('text'))=='跳过这一张' and n.get('clickable')=='true' for n in nodes):break
else:raise AssertionError('bad image skip control never appeared')
ui.device('shell','input','swipe','600','1100','600','1080','700');ui.snap('25-invalid-zoom-error-visible');b=snapshot('new25','invalid-before-retry');seq=max(r['seq'] for r in facts.trace());ui.choose('重试');nodes=ui.snap('26-invalid-retry-still-error');assert any((n.get('content-desc') or n.get('text'))=='跳过这一张' for n in nodes);a=snapshot('new25','invalid-after-retry')
for k in ['tables','opaque_table_digests','setting_key_sha256']:assert b[k]==a[k],k
assert not [r for r in facts.trace() if r['seq']>seq and r['method'] not in ['GET','HEAD']]
ui.choose('跳过这一张');ui.snap('27-invalid-skip-result');end=snapshot('new25','invalid-after-skip');pack=next(p for p in end['tables']['packs'] if p['name']=='03-invalid') if any(p.get('name')=='03-invalid' for p in end['tables']['packs']) else next(p for p in end['tables']['packs'] if p.get('relative_path')=='03-invalid')
progress=next(p for p in end['tables']['pack_progress'] if p['pack_id']==pack['id']);assert not progress['completed']
(ui.L/'invalid-checks.json').write_text(json.dumps({'normal_code':25,'error_reached_by_real_drag_while_zoomed':True,'retry_all_35_tables_and_settings_equal':True,'retry_no_writes':True,'bad_last_skip_did_not_mark_completed':True,'invalid_progress':progress,'visual_review':'pending'},indent=2)+'\n');print('Real 8K last-page zoom and enlarged known-bad retry/skip checked',flush=True)

import json,re,sys,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import ui,facts
from snapshot_all import snapshot
start=json.loads((ui.L/'deep-start-checks.json').read_text());base=start['deep_manifest_offset'];target=base+120;events=[]
def offsets():return [r['page_result']['offset'] for r in facts.trace() if r.get('page_result',{}).get('total')==500]
def checkpoint(name):
 ui.record({'action':'short-real-drag-to-settle-scroll','from':[600,1100],'to':[600,1040],'duration_ms':900});ui.device('shell','input','swipe','600','1100','600','1040','900');nodes=ui.snap(name);c=[int(v.get('content-desc').split()[0]) for v in nodes if re.fullmatch(r'\d+ / 500',v.get('content-desc',''))];assert len(c)==1
 deadline=time.monotonic()+15
 while True:
  p=facts.progress()
  if p['page_ordinal']+1==c[0]:break
  assert time.monotonic()<deadline,('visible/saved mismatch',c,p);time.sleep(.1)
 facts.mem(name);return c[0],p
last=start['counter']
for i in range(1,66):
 ui.record({'action':'forward-fling-at-2x','from':[600,1700],'to':[600,500],'duration_ms':100,'round':i});ui.device('shell','input','swipe','600','1700','600','500','100');time.sleep(.8)
 seen=offsets()
 if i%4==0 or target in seen:
  current,p=checkpoint(f'forward-{i:02}');assert current>=last,('forward moved backward',last,current);last=current;events.append({'direction':'forward','round':i,'counter':current,'progress':p,'offsets':seen});print(json.dumps({'direction':'forward','round':i,'counter':current,'offsets':seen}),flush=True)
 if target in seen:break
else:raise AssertionError('did not reach fourth contiguous page window')
forward_end=checkpoint('forward-end');forward_seq=max(r['seq'] for r in facts.trace());old_count=offsets().count(base)
for i in range(1,66):
 ui.record({'action':'backward-fling-at-2x','from':[600,500],'to':[600,1700],'duration_ms':100,'round':i});ui.device('shell','input','swipe','600','500','600','1700','100');time.sleep(.8)
 seen=offsets();reloaded=seen.count(base)>old_count
 if i%4==0 or reloaded:
  current,p=checkpoint(f'backward-{i:02}');assert current<=last,('backward moved forward',last,current);last=current;events.append({'direction':'backward','round':i,'counter':current,'progress':p,'offsets':seen});print(json.dumps({'direction':'backward','round':i,'counter':current,'offsets':seen}),flush=True)
 if reloaded:break
else:raise AssertionError('did not reload previous window after returning')
back_end=checkpoint('backward-end');snapshot('new25','after-window-walk')
reads=[r for r in facts.trace() if r.get('page_result',{}).get('total')==500];assert all(r['page_result']['limit']==40 and r['page_result']['items']<=40 for r in reads)
assert any(r['seq']>forward_seq and r['page_result']['offset']==base for r in reads)
(ui.L/'window-walk-checks.json').write_text(json.dumps({'normal_code':25,'assumed_zoom_from_prior_doubletap':2,'real_positions_within_display':True,'base_offset':base,'fourth_window_offset':target,'actual_page_reads':[{'seq':r['seq'],**r['page_result']} for r in reads],'monotonic_waypoints':events,'forward_end':forward_end,'backward_end':back_end,'old_window_reloaded_after_forward':True,'resident_count_not_instrumented':True,'memory':'raw dumpsys at checkpoints; no NAS speed conclusion'},indent=2)+'\n');print('Real 500-file forward/back window route passed',flush=True)

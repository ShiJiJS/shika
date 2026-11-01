import sys,json,re,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import ui,facts
from snapshot_all import snapshot
ui.record({'action':'tap-visible-progress-track','point':[500,1983],'intent':'jump to middle of 500-page pack'});ui.device('shell','input','tap','500','1983');deadline=time.monotonic()+45
while True:
 _,n=ui.xml();c=[v.get('content-desc','') for v in n if re.fullmatch(r'\d+ / 500',v.get('content-desc',''))]
 if c and 200<=int(c[0].split()[0])<=350:counter=int(c[0].split()[0]);break
 assert time.monotonic()<deadline,'slider did not reach deep position'
while True:
 progress=facts.progress()
 if progress and progress['page_ordinal']+1==counter:break
 assert time.monotonic()<deadline;time.sleep(.1)
ui.snap('02-deep-before-zoom');before=snapshot('new25','deep-before-zoom');facts.mem('deep-before-zoom');start=max(r['seq'] for r in facts.trace())
ui.record({'action':'double-tap-decoded-long-page','point':[540,1100]});ui.device('shell','input','tap','540','1100');time.sleep(.05);ui.device('shell','input','tap','540','1100');n=ui.snap('03-deep-doubletap');assert any(v.get('content-desc')==f'{counter} / 500' for v in n);after=snapshot('new25','deep-after-zoom')
for k in ['tables','opaque_table_digests','setting_key_sha256']:assert before[k]==after[k],k
new=[r for r in facts.trace() if r['seq']>start];assert not [r for r in new if r['method'] not in ['GET','HEAD']],new
pages=[r for r in facts.trace() if r.get('page_result',{}).get('total')==500];offset=(counter-1)//40*40
assert [r['page_result']['offset'] for r in pages]==[0,offset],pages
assert all(r['page_result']['items']<=40 and r['page_result']['limit']==40 for r in pages)
(ui.L/'deep-start-checks.json').write_text(json.dumps({'counter':counter,'progress':progress,'initial_and_deep_page_results':[r['page_result'] for r in pages],'all_35_business_tables_equal_for_zoom':True,'opaque_and_settings_equal':True,'writes_after_doubletap':0,'trace_before_zoom_seq':start,'deep_manifest_offset':offset,'normal_code':25},indent=2)+'\n');print({'deep_counter':counter,'metadata_offsets':[0,offset],'zoom_kept_progress':True,'zoom_writes':0})

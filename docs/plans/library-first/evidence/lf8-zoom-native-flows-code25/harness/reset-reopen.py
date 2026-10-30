import sys,json,re,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import ui,facts
from snapshot_all import snapshot
_,nodes=ui.xml();assert any(n.get('content-desc')=='纵向拼接' for n in nodes),'controls must be visible before Back';assert any(n.get('content-desc')=='282 / 500' for n in nodes)
before=snapshot('new25','deep-before-back-reset');p0=facts.progress();seq=max(r['seq'] for r in facts.trace());ui.device('shell','input','keyevent','4');ui.record({'action':'system-back','intent':'reset active zoom, retain reader'});time.sleep(.8)
nodes=ui.snap('04-deep-back-reset');assert any(n.get('content-desc')=='282 / 500' for n in nodes);assert any(n.get('content-desc')=='纵向拼接' for n in nodes)
after=snapshot('new25','deep-after-back-reset')
for k in ['tables','opaque_table_digests','setting_key_sha256']:assert before[k]==after[k],k
assert not [r for r in facts.trace() if r['seq']>seq and r['method'] not in ['GET','HEAD']]
oldpid=ui.device('shell','pidof',ui.PACKAGE).decode().strip();seq=max(r['seq'] for r in facts.trace());ui.device('shell','am','force-stop',ui.PACKAGE);ui.device('shell','am','start','-n',ui.PACKAGE+'/.MainActivity');deadline=time.monotonic()+45
while True:
 _,nodes=ui.xml()
 if any(n.get('content-desc')=='媒体库' for n in nodes):break
 assert time.monotonic()<deadline
newpid=ui.device('shell','pidof',ui.PACKAGE).decode().strip();assert oldpid!=newpid
ui.snap('05-deep-cold-library');cold=snapshot('new25','deep-cold-library')
for k in ['tables','opaque_table_digests','setting_key_sha256']:assert after[k]==cold[k],k
ui.choose('图包\n5');ui.fill(0,'04-long');ui.device('shell','input','keyevent','4');_,nodes=ui.xml();found=[n for n in nodes if '\n04-long\n' in n.get('content-desc','') and n.get('clickable')=='true'];assert len(found)==1;ui.tap(found[0],'reopen-long-after-cold-start')
while True:
 _,nodes=ui.xml()
 if any(n.get('content-desc')=='282 / 500' for n in nodes):break
 assert time.monotonic()<deadline
ui.snap('06-deep-cold-resumed');p1=facts.progress()
for k in ['page_id','offset_ratio','completed','content_version']:assert p0[k]==p1[k],(k,p0,p1)
page_reads=[r['page_result'] for r in facts.trace() if r['seq']>seq and r.get('page_result',{}).get('total')==500];assert page_reads and page_reads[0]['offset']==280
assert all(r['limit']==40 and r['items']<=40 for r in page_reads)
(ui.L/'reset-reopen-checks.json').write_text(json.dumps({'normal_code':25,'counter':282,'back_reset_retained_reader':True,'all_35_tables_and_opaque_settings_equal_for_reset':True,'reset_writes':0,'cold_start_new_process':oldpid!=newpid,'cold_start_library_all_tables_equal':True,'resumed_progress_fields_equal':['page_id','offset_ratio','completed','content_version'],'progress_before':p0,'progress_reopened':p1,'cold_page_results':page_reads},indent=2)+'\n');print('Back reset retained reader; cold start opened library; real saved deep position resumed')

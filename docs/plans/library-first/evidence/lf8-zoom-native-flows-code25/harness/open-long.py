import json,sys,time,hashlib,re
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import ui
from snapshot_all import snapshot
checks=json.loads((ui.ROOT/'docs/plans/library-first/evidence/lf8-vertical-strip-zoom/checks.json').read_text());expected=checks['normal_code25'];dump=ui.device('shell','dumpsys','package',ui.PACKAGE).decode();assert re.search(r'versionCode=25\b',dump)
installed=ui.device('shell','pm','path',ui.PACKAGE).decode().strip().removeprefix('package:');assert hashlib.sha256(ui.device('exec-out','cat',installed)).hexdigest()==expected['sha256']
(ui.L/'apk-boundary.json').write_text(json.dumps({'version':25,'source_commit':checks['source_commit'],'sha256':expected['sha256'],'normal_entrypoint':True,'reinstalled_this_phase':False},indent=2)+'\n')
trace=ui.L/'requests.jsonl';start=len(trace.read_text().splitlines()) if trace.exists() else 0
snapshot('new25','before-long-entry');ui.device('shell','am','force-stop',ui.PACKAGE);ui.device('shell','am','start','-n',ui.PACKAGE+'/.MainActivity');deadline=time.monotonic()+45
while True:
 _,nodes=ui.xml()
 if any(v.get('content-desc')=='媒体库' for v in nodes):break
 assert time.monotonic()<deadline,'normal app did not reach library'
ui.choose('图包\n5');ui.fill(0,'04-long');ui.device('shell','input','keyevent','4');_,nodes=ui.xml();found=[n for n in nodes if '\n04-long\n' in n.get('content-desc','') and n.get('clickable')=='true'];assert len(found)==1;ui.tap(found[0],'open-real-500-file-pack')
while True:
 _,nodes=ui.xml()
 if any(v.get('content-desc')=='1 / 500' for v in nodes):break
 assert time.monotonic()<deadline
ui.snap('01-long-1-of-500');snapshot('new25','long-initial-open')
(ui.L/'long-entry.json').write_text(json.dumps({'trace_start_line':start,'expected_counter':'1 / 500','real_files':500,'source':'stdlib-generated PNGs; not photographic performance sample'},indent=2)+'\n')
print('Normal code25 opened the actual 500-file pack at 1/500')

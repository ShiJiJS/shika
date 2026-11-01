import sys,json,time,hashlib,importlib.util
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import ui,api
deadline=time.monotonic()+60
while True:
 try:s=api.call('GET','/api/v1/info');break
 except (OSError,ConnectionError):
  assert time.monotonic()<deadline;time.sleep(.2)
assert {'scoped_scans','root_scan_progress'}<=set(s['capabilities']);deadline=time.monotonic()+60
while True:
 state=api.call('GET','/api/v1/library-state')
 if not state['scanning']:break
 assert time.monotonic()<deadline;time.sleep(.2)
(ui.L/'new-baseline-state.json').write_text(json.dumps(state,indent=2)+'\n');media=ui.L/'new-media';baseline={str(p.relative_to(media)):hashlib.sha256(p.read_bytes()).hexdigest() for p in media.rglob('*') if p.is_file()};(ui.L/'new-media-baseline.json').write_text(json.dumps(baseline,indent=2)+'\n');target=media/'packs-a/06-queue';assert not target.exists();target.mkdir();spec=importlib.util.spec_from_file_location('fixture',ui.ROOT/'scripts/fixtures/generate-lf0-packs.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);files=[]
for i in range(1,1001):
 p=target/f'{i}.png';m.png(p,240,360,((i%80)+80,125,150));files.append({'name':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(ui.L/'new-queue-fixture.json').write_text(json.dumps({'private_media':False,'generated_files':1000,'image_dimensions':[240,360],'purpose':'real file scan long enough to observe native progress/queue; not performance benchmark','files':files},indent=2)+'\n')
ui.device('shell','am','start','-n',ui.PACKAGE+'/.MainActivity');deadline=time.monotonic()+50
while True:
 _,n=ui.xml()
 if any(v.get('content-desc')=='预览此范围' for v in n):break
 assert time.monotonic()<deadline
ui.choose('查看进度');n=ui.snap('11-new-service-root-baseline');buttons=[v for v in n if v.get('content-desc')=='扫描此目录'];assert len(buttons)==3;print('New service ready with A/B independent baseline; 1000 real disposable files added, scan not requested yet',flush=True)

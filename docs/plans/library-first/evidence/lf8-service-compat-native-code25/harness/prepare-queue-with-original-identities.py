import sys,time,json,shutil
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import ui,api
L=ui.L;deadline=time.monotonic()+180;last=0
while True:
 try:
  s=api.call('GET','/api/v1/library-state')
  if not s['scanning']:break
  if time.monotonic()-last>15:print({'warm_preparation':[(r['id'],r['scan']['status'],r['scan']['progress'].get('processed')) for r in s['roots']]},flush=True);last=time.monotonic()
 except (OSError,ConnectionError):pass
 assert time.monotonic()<deadline;time.sleep(.3)
r={v['id']:v for v in s['roots']};assert r['packs-a']['scan']['progress']['processed']==515;assert r['packs-b']['scan']['progress']['processed']==4
p=L/'new-baseline-state.json'
if p.exists():p.rename(L/'new-identity-preparation-deferred.json')
p.write_text(json.dumps(s,indent=2)+'\n');media=Path(json.loads((L/'runtime.json').read_text())['media_source']);assert not (media/'packs-a/06-queue').exists();assert not (media/'packs-b/B Queue').exists();shutil.move(str(L/'pending-media/06-queue'),str(media/'packs-a/06-queue'));shutil.move(str(L/'pending-media/B Queue'),str(media/'packs-b/B Queue'));(L/'pending-media').rmdir()
for ext in ['png','xml']:
 p=L/'screens'/('11-new-service-root-baseline.'+ext)
 if p.exists():p.rename(L/'screens'/('11-identity-preparation-deferred.'+ext))
ui.device('shell','am','start','-n',ui.PACKAGE+'/.MainActivity');deadline=time.monotonic()+50
while True:
 _,n=ui.xml()
 if any(v.get('content-desc')=='预览此范围' for v in n):break
 assert time.monotonic()<deadline
ui.choose('查看进度');n=ui.snap('11-new-service-root-baseline');assert len([v for v in n if v.get('content-desc')=='扫描此目录'])==3;print('Original fixture identity warmed once; A515/B4 baseline ready; new A1000/B600 staged under roots without scan',flush=True)

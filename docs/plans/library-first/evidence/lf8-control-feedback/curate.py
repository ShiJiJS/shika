import hashlib,json,re,shutil
from pathlib import Path
R=Path(__file__).resolve().parents[2];L=R/'.dev/lf8-control-feedback';D=R/'docs/plans/library-first/evidence/lf8-control-feedback';D.mkdir(parents=True,exist_ok=True)
provenance={}
def cp(p,dst):
 target=D/dst;target.parent.mkdir(parents=True,exist_ok=True)
 if p.suffix=='.log':
  raw=p.read_bytes();text=raw.decode(errors='replace');text,count=re.subn(r'(?:https?|wss?)://(?:127\.0\.0\.1|localhost|\[::1\]):\d+/[^\s]+','<redacted-local-vm-service>',text);target.write_text(text);provenance[str(dst)]={'original_sha256':hashlib.sha256(raw).hexdigest(),'redacted_sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'local_vm_urls_removed':count}
 else:shutil.copy2(p,target)
for p in L.iterdir():
 if p.is_file() and (p.suffix in ['.json','.log','.py'] or p.name in ['source-ref','before-test.dart.txt','before-test-valid.dart.txt','before-probe-executed.dart.txt','queue-before-source.dart.txt','preflight-source-ref']):cp(p,p.name)
for folder in ['native-1','native-2','native-3','native-4','native-5','native-6','normal','normal-final','build-2','build-3']:
 for p in (L/folder).iterdir():
  if p.is_file() and p.name!='emulator.log' and p.suffix in ['.json','.txt','.log','.py','.mp4','.png']:cp(p,Path(folder)/p.name)
for folder in ['native-1','native-2','native-3','native-4','native-5','native-6']:
 for p in (L/folder/'trace').glob('*.jsonl'):cp(p,Path(folder)/'trace'/p.name)
for folder in ['normal','normal-final']:
 for p in (L/folder/'screens').iterdir():
  if p.is_file():cp(p,Path(folder)/'screens'/p.name)
 for p in (L/folder/'trace').glob('*.jsonl'):cp(p,Path(folder)/'trace'/p.name)
(D/'log-provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
print('Curated',sum(1 for p in D.rglob('*') if p.is_file()),'inputs')

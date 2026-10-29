import hashlib,json,re,shutil
from pathlib import Path
L=Path(__file__).resolve().parent;R=L.parents[1];D=R/'docs/plans/library-first/evidence/lf8-settings-motion';assert not D.exists();D.mkdir(parents=True)
provenance={}
def cp(p,dst):
 t=D/dst;t.parent.mkdir(parents=True,exist_ok=True)
 if p.suffix=='.log':
  raw=p.read_bytes();s,count=re.subn(r'(?:https?|wss?)://(?:127\.0\.0\.1|localhost|\[::1\]):\d+/[^\s]+','<redacted-local-vm-service>',raw.decode(errors='replace'));t.write_text(s);provenance[str(dst)]={'original_sha256':hashlib.sha256(raw).hexdigest(),'redacted_sha256':hashlib.sha256(t.read_bytes()).hexdigest(),'local_vm_urls_removed':count}
 else:shutil.copy2(p,t)
for p in L.iterdir():
 if p.is_file() and (p.suffix in ['.json','.log','.py'] or p.name in ['source-ref','switch-before-test.dart.txt']) and not p.name.startswith(('emulator-start','launcher-attempt-1.log')):cp(p,p.name)
for p in (L/'native-1').iterdir():
 if p.is_file() and p.suffix in ['.json','.txt','.log','.mp4','.png']:cp(p,Path('native-1')/p.name)
(D/'log-provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
print(len(list(D.rglob('*'))),'curated paths')

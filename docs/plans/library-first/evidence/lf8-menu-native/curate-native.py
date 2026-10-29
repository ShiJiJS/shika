import hashlib,json,re,shutil
from pathlib import Path
L=Path(__file__).resolve().parent; R=L.parents[1]; D=R/'docs/plans/library-first/evidence/lf8-menu-native'
assert not D.exists();D.mkdir(parents=True);provenance={}
def cp(p,dst):
 t=D/dst;t.parent.mkdir(parents=True,exist_ok=True)
 if p.suffix=='.log':
  raw=p.read_bytes();s,n=re.subn(r'(?:https?|wss?)://(?:127\.0\.0\.1|localhost|\[::1\]):\d+/[^\s]+','<redacted-local-vm-service>',raw.decode(errors='replace'));t.write_text(s);provenance[str(dst)]={'original_sha256':hashlib.sha256(raw).hexdigest(),'published_sha256':hashlib.sha256(t.read_bytes()).hexdigest(),'temporary_vm_urls_removed':n}
 else:shutil.copy2(p,t)
for name in ['analyze-native.log','analyze-native-final.log','profile-build.log','native-run.log','cleanup-native.log','profile-artifact.json','android-flag-source.json','audit-native.json','native-live-proof.json','cleanup-native.json','native-source-ref','run-native.py','audit-native.py','cleanup-native.py','curate-native.py']:cp(L/name,Path(name))
for p in sorted((L/'native-1').iterdir()):
 if p.is_file() and p.suffix in ['.json','.txt','.log','.mp4','.png']:cp(p,Path('native-1')/p.name)
(D/'log-provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
print(len(list(D.rglob('*'))),'curated paths')

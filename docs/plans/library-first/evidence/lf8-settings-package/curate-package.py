import hashlib,json,re,shutil
from pathlib import Path
L=Path(__file__).resolve().parent;R=L.parents[1];D=R/'docs/plans/library-first/evidence/lf8-settings-package';assert not D.exists();D.mkdir(parents=True);provenance={}
def cp(p,dst):
 t=D/dst;t.parent.mkdir(parents=True,exist_ok=True)
 if p.suffix=='.log':
  raw=p.read_bytes();s,n=re.subn(r'(?:https?|wss?)://(?:127\.0\.0\.1|localhost|\[::1\]):\d+/[^\s]+','<redacted-local-vm-service>',raw.decode(errors='replace'));t.write_text(s);provenance[str(dst)]={'original_sha256':hashlib.sha256(raw).hexdigest(),'published_sha256':hashlib.sha256(t.read_bytes()).hexdigest(),'temporary_vm_urls_removed':n}
 else:shutil.copy2(p,t)
for name in ['normal-build.log','normal-upgrade-initial.log','normal-upgrade-2.log','ordinary-settings.log','normal-setup.py','normal-setup.log','normal-emulator-start.log','package-build-audit.json','same-production-tree.json','package-audit.py','package-audit.json','package-cleanup.py','package-cleanup.json','package-cleanup.log','previous-apks.json','curate-package.py']:
 cp(L/name,name)
for p in (L/'normal').rglob('*'):
 relative=p.relative_to(L/'normal')
 if relative.parts[0] in ['config','data','observe','__pycache__']:continue
 if p.is_file() and p.suffix in ['.json','.py','.txt','.xml','.png','.jsonl']:cp(p,Path('normal')/relative)
for p in (L/'build-1').iterdir():
 if p.is_file() and p.suffix in ['.json','.log']:cp(p,Path('build-1')/p.name)
(D/'log-provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
print('Curated',sum(p.is_file() for p in D.rglob('*')),'package inputs')

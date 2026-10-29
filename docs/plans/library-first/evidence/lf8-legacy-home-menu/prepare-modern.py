import hashlib,json,shutil,socket,subprocess,time
from pathlib import Path
R=Path(__file__).resolve().parents[2];L=R/'.dev/lf8-legacy-home-menu';D=R/'.dev/lf8-menu-dropdown-package/normal';O=L/'modern';assert not O.exists();expected=json.loads((L/'legacy/runtime.json').read_text())['original_containers'];legacy=json.loads((L/'legacy/runtime.json').read_text())['container'];ids=subprocess.check_output(['docker','ps','-q'],text=True).split();active=json.loads(subprocess.check_output(['docker','inspect',*ids]));assert {c['Name']:c['Id'] for c in active}=={**expected,'/video-viewer-legacy-menu-legacy':legacy}
for c in active:
 for m in c['Mounts']:
  p=Path(m['Source']).resolve();assert not(p==D.resolve() or p in D.resolve().parents or D.resolve() in p.parents)
def hashes(p):return {str(x.relative_to(p)):hashlib.sha256(x.read_bytes()).hexdigest() for x in p.rglob('*') if x.is_file()}
# Copy the entire inactive data directory including WAL/SHM. Do NOT host-open
# this source SQLite; only the new owning container performs normal recovery.
files=hashes(D/'data');wal={p.name:p.stat().st_size for p in (D/'data').glob('*-wal') if p.stat().st_size}
assert wal
with socket.socket() as s:s.bind(('127.0.0.1',8772))
O.mkdir();(O/'trace').mkdir();(O/'screens').mkdir()
for n in ['data','config','observe']:shutil.copytree(D/n,O/n)
assert hashes(O/'data')==files
old=json.loads((D/'runtime.json').read_text());cmd=[v.replace(str(D),str(O)).replace('video-viewer-menu-dropdown-normal','video-viewer-legacy-menu-modern').replace('lf8-menu-dropdown-normal','lf8-legacy-menu-modern') for v in old['command']]
meta={'kind':'modern','donor':str(D),'donor_data_sha256':files,'donor_config_sha256':hashes(D/'config'),'source_nonempty_wal':wal,'copy_method':'entire inactive directory including WAL/SHM; never host-open source SQLite; new owner recovers its own copy','image':'sha256:886b79b72ecb9116087d892f230471943121f24ccef093113cc3197b4607fef4','port':8772,'command':cmd,'original_containers':expected};(O/'runtime.json').write_text(json.dumps(meta,indent=2)+'\n');meta['container']=subprocess.check_output(cmd,text=True).strip();(O/'runtime.json').write_text(json.dumps(meta,indent=2)+'\n');print(json.dumps({'kind':'modern','container':meta['container'],'copied_files':len(files),'wal_preserved':True}),flush=True)
media={n:hashes(R/'.dev/lf8-preview-package/upgrade'/n) for n in ['videos','packs']};(L/'media-before.json').write_text(json.dumps(media,indent=2)+'\n')

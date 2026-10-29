import hashlib,json,shutil,socket,subprocess
from pathlib import Path
R=Path(__file__).resolve().parents[2];L=R/'.dev/lf8-settings-motion';D=R/'.dev/lf8-control-feedback/normal-final';O=L/'normal'
assert not O.exists()
containers=json.loads(subprocess.check_output(['docker','inspect',*subprocess.check_output(['docker','ps','-q'],text=True).split()]))
for c in containers:
 for m in c['Mounts']:assert not D.resolve().is_relative_to(Path(m['Source']))
assert not any(p.stat().st_size for p in (D/'data').glob('*-wal'))
with socket.socket() as s:s.bind(('127.0.0.1',8772))
original={c['Name']:c['Id'] for c in containers};assert len(original)==4 and all(c['State']['Health']['Status']=='healthy' for c in containers)
O.mkdir()
for name in ['data','config','observe']:shutil.copytree(D/name,O/name)
for name in ['trace','screens']:(O/name).mkdir()
cmd=[v.replace(str(D),str(O)).replace('video-viewer-control-final','video-viewer-settings-normal').replace('lf8-control-final','lf8-settings-normal') for v in json.loads((D/'runtime.json').read_text())['command']]
meta={'donor':str(D),'command':cmd,'donor_hashes':{str(p.relative_to(D/'data')):hashlib.sha256(p.read_bytes()).hexdigest() for p in (D/'data').rglob('*') if p.is_file()},'original_containers':original}
(O/'runtime.json').write_text(json.dumps(meta,indent=2)+'\n')
meta['container']=subprocess.check_output(cmd,text=True).strip();(O/'runtime.json').write_text(json.dumps(meta,indent=2)+'\n')
for name in ['driver.py','ui_driver.py','snapshot.py']:
 s=(D/name).read_text().replace('.dev/lf8-control-feedback/normal-final','.dev/lf8-settings-motion/normal').replace('video-viewer-control-final','video-viewer-settings-normal').replace('build-3/result.json','build-1/result.json');(O/name).write_text(s)
s=(D/'check-upgrade.py').read_text().replace('baseline13','baseline14').replace("=='13'","=='14'").replace('before14','before15').replace('forward14','forward15').replace('rollback14','rollback15');(O/'check-upgrade.py').write_text(s)
print(meta['container'])

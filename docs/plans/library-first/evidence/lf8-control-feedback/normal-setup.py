import hashlib,json,shutil,socket,subprocess
from pathlib import Path
R=Path(__file__).resolve().parents[2];L=R/'.dev/lf8-control-feedback';D=R/'.dev/lf8-notice-motion/normal';O=L/'normal'
assert not O.exists()
for c in json.loads(subprocess.check_output(['docker','inspect',*subprocess.check_output(['docker','ps','-q'],text=True).split()])):
 for m in c['Mounts']:assert not D.resolve().is_relative_to(Path(m['Source']))
with socket.socket() as s:s.bind(('127.0.0.1',8772))
O.mkdir()
for name in ['data','config','observe']:shutil.copytree(D/name,O/name)
for name in ['trace','screens']:(O/name).mkdir()
cmd=[v.replace(str(D),str(O)).replace('video-viewer-notice-normal','video-viewer-control-normal').replace('lf8-notice-normal','lf8-control-normal') for v in json.loads((D/'runtime.json').read_text())['command']]
meta={'donor':str(D),'command':cmd,'container':subprocess.check_output(cmd,text=True).strip(),'donor_hashes':{str(p.relative_to(D/'data')):hashlib.sha256(p.read_bytes()).hexdigest() for p in (D/'data').rglob('*') if p.is_file()},'original_containers':json.loads((R/'.dev/lf8-notice-motion/normal-cleanup.json').read_text())['original_containers_preserved']};(O/'runtime.json').write_text(json.dumps(meta,indent=2)+'\n')
for name in ['driver.py','ui_driver.py','snapshot.py']:
 s=(D/name).read_text().replace('.dev/lf8-notice-motion/normal','.dev/lf8-control-feedback/normal').replace('video-viewer-notice-normal','video-viewer-control-normal').replace("build-1/result.json","build-2/result.json");(O/name).write_text(s)
s=(D/'check-upgrade.py').read_text().replace('baseline11','baseline12').replace("=='11'","=='12'").replace('before12','before13').replace('forward12','forward13').replace('rollback12','rollback13');(O/'check-upgrade.py').write_text(s)
print(meta['container'])

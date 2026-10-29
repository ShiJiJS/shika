import json,shutil,socket,subprocess,hashlib
from pathlib import Path
R=Path(__file__).resolve().parents[2];L=R/'.dev/lf8-overlays-motion';O=L/'normal';D=R/'.dev/lf8-preview4/native'
assert not O.exists()
for c in json.loads(subprocess.check_output(['docker','inspect',*subprocess.check_output(['docker','ps','-q'],text=True).split()])):
 for m in c['Mounts']:assert not D.resolve().is_relative_to(Path(m['Source']))
with socket.socket() as s:s.bind(('127.0.0.1',8772))
O.mkdir()
for name in ['data','config','observe']:shutil.copytree(D/name,O/name)
for name in ['screens','trace']:(O/name).mkdir()
cmd=json.loads((D/'runtime.json').read_text())['command'];cmd=[v.replace(str(D),str(O)).replace('video-viewer-preview4-native','video-viewer-overlay-normal').replace('lf8-preview4-native','lf8-overlay-normal') for v in cmd]
meta={'donor':str(D),'command':cmd,'donor_hashes':{str(p.relative_to(D/'data')):hashlib.sha256(p.read_bytes()).hexdigest() for p in (D/'data').rglob('*') if p.is_file()},'container':subprocess.check_output(cmd,text=True).strip()};(O/'runtime.json').write_text(json.dumps(meta,indent=2)+'\n')
for name in ['driver.py','ui_driver.py','snapshot.py']:
 s=(D/name).read_text().replace('.dev/lf8-preview4/native','.dev/lf8-overlays-motion/normal').replace('video-viewer-preview4-native','video-viewer-overlay-normal');(O/name).write_text(s)
print(meta['container'])

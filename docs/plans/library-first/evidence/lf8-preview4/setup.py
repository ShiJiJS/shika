import hashlib,json,shutil,socket,subprocess,time
from pathlib import Path
R=Path('/Users/jiangxinyi/Documents/Project/video-viewer');O=R/'.dev/lf8-preview4/native';donor=R/'.dev/lf8-preview3/native'
def hashes(p):return {str(v.relative_to(p)):hashlib.sha256(v.read_bytes()).hexdigest() for v in sorted(p.rglob('*')) if v.is_file()}
assert not O.exists()
containers=json.loads(subprocess.check_output(['docker','inspect',*subprocess.check_output(['docker','ps','-q'],text=True).split()]))
for c in containers:
 for m in c['Mounts']:assert not Path(m['Source']).is_relative_to(donor) and not donor.is_relative_to(Path(m['Source']))
with socket.socket() as s:s.bind(('127.0.0.1',8772))
O.mkdir(parents=True)
for name in ['data','config','observe']:shutil.copytree(donor/name,O/name)
for name in ['trace','screens']: (O/name).mkdir()
assert hashes(O/'data')==hashes(donor/'data')
meta={'donor':str(donor),'donor_hashes':hashes(donor/'data'),'original_containers':{c['Name']:c['Id'] for c in containers},'media_read_only':True,'source':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()}
cmd=json.loads((donor/'runtime.json').read_text())['command']
cmd=[v.replace('video-viewer-preview3-native','video-viewer-preview4-native').replace('lf8-preview3-native','lf8-preview4-native').replace(str(donor),str(O)) for v in cmd]
identity=subprocess.check_output(cmd,text=True).strip();meta.update(container=identity,command=cmd,started_at=time.time())
(O/'runtime.json').write_text(json.dumps(meta,indent=2)+'\n')
for name in ['ui_driver.py','driver.py','snapshot.py']:
 s=(donor/name).read_text().replace('.dev/lf8-preview3/native','.dev/lf8-preview4/native').replace('lf8-preview3-ui','lf8-preview4-ui').replace('video-viewer-preview3-native','video-viewer-preview4-native')
 (O/name).write_text(s)
print(json.dumps({'container':identity,'port':8772,'copy_verified':True}))

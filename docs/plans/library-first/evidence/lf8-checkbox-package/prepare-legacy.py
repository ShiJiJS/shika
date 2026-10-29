import json,hashlib,shutil,subprocess,socket,urllib.request,uuid,time
from pathlib import Path
R=Path(__file__).resolve().parents[2];L=R/'.dev/lf8-checkbox-package';D=R/'.dev/lf8-legacy-home-menu/legacy';O=L/'legacy';assert not O.exists()
def hashes(p):return {str(f.relative_to(p)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(p.rglob('*')) if f.is_file()}
ids=subprocess.check_output(['docker','ps','-q'],text=True).split();active=json.loads(subprocess.check_output(['docker','inspect',*ids]));orig=json.loads((L/'normal/runtime.json').read_text());assert {c['Name']:c['Id'] for c in active}=={**orig['original_containers'],'/video-viewer-checkbox-normal':orig['container']}
for c in active:
 for m in c['Mounts']:
  p=Path(m['Source']).resolve();assert not(p==D.resolve() or p in D.resolve().parents or D.resolve() in p.parents)
with socket.socket() as s:s.bind(('127.0.0.1',8774))
O.mkdir();(O/'trace').mkdir();(O/'screens').mkdir()
for n in ['data','config','observe']:shutil.copytree(D/n,O/n)
files=hashes(D/'data');assert files==hashes(O/'data');old=json.loads((D/'runtime.json').read_text());cmd=[x.replace(str(D),str(O)).replace('video-viewer-legacy-menu-legacy','video-viewer-checkbox-legacy').replace('lf8-legacy-menu-legacy','lf8-checkbox-legacy') for x in old['command']]
meta={'donor':str(D),'donor_data_sha256':files,'donor_config_sha256':hashes(D/'config'),'command':cmd,'image':old['image'],'original_containers':orig['original_containers'],'copy_method':'whole inactive directory including any WAL/SHM; no host SQLite open'};(O/'runtime.json').write_text(json.dumps(meta,indent=2)+'\n');meta['container']=subprocess.check_output(cmd,text=True).strip();(O/'runtime.json').write_text(json.dumps(meta,indent=2)+'\n')
end=time.monotonic()+30
while True:
 c=json.loads(subprocess.check_output(['docker','inspect',meta['container']]))[0]
 if c['State'].get('Health',{}).get('Status')=='healthy':break
 assert time.monotonic()<end;time.sleep(.3)
headers={};events=[]
def req(method,path,body=None):
 r=urllib.request.Request('http://127.0.0.1:8774/api/v1'+path,data=None if body is None else json.dumps(body).encode(),headers={**headers,'Content-Type':'application/json'},method=method)
 with urllib.request.urlopen(r,timeout=20) as response:raw=response.read();events.append({'method':method,'path':path,'status':response.status})
 return raw
v=json.loads(req('POST','/auth/login',{'passphrase':(O/'config/passphrase').read_text().strip()}));headers['Authorization']='Bearer '+v['access_token'];info=json.loads(req('GET','/info'));assert 'backup_v2' not in info.get('capabilities',[])
task=json.loads(req('POST','/backups',{'request_id':str(uuid.uuid4())}));end=time.monotonic()+30
while True:
 t=json.loads(req('GET','/tasks/'+task['id']))
 if t['status'] not in ['queued','running']:assert t['status']=='completed';break
 assert time.monotonic()<end;time.sleep(.1)
raw=req('GET','/backups/'+task['id']+'/download');assert hashlib.sha256(raw).hexdigest()==t['result']['file_sha256'];doc=L/'checkbox-code17-legacy.json';doc.write_bytes(raw)
subprocess.run([str(R/'.dev/android-sdk/platform-tools/adb'),'-s','emulator-5556','push',str(doc),'/sdcard/Download/'+doc.name],check=True,stdout=subprocess.DEVNULL)
(L/'legacy-preparation.json').write_text(json.dumps({'container':meta['container'],'document':{'name':doc.name,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()},'requests':events,'no_backup_v2_capability':True},indent=2)+'\n');print(json.dumps({'ready':True,'container':meta['container'],'file_bytes':len(raw)}))

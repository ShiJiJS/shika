import json,urllib.request,time,uuid,hashlib,subprocess
from pathlib import Path
R=Path(__file__).resolve().parents[2];L=R/'.dev/lf8-checkbox-package';O=L/'normal';base='http://127.0.0.1:8772/api/v1';headers={};events=[]
def req(method,path,value=None):
 b=None if value is None else json.dumps(value).encode();h={**headers,'Content-Type':'application/json'}
 with urllib.request.urlopen(urllib.request.Request(base+path,data=b,headers=h,method=method),timeout=20) as response:raw=response.read();status=response.status
 events.append({'method':method,'path':path,'status':status});return raw
login=json.loads(req('POST','/auth/login',{'passphrase':(O/'config/passphrase').read_text().strip()}));headers['Authorization']='Bearer '+login['access_token'];info=json.loads(req('GET','/info'));headers['X-Management-Epoch']=info['management_epoch']
def wait(path):
 end=time.monotonic()+30
 while True:
  v=json.loads(req('GET',path))
  if v['status'] not in ['queued','running']:assert v['status']=='completed',v;return v
  assert time.monotonic()<end;time.sleep(.1)
# Prepare only isolated logical marks; media mounts are read-only.
videos=json.loads(req('GET','/videos'))['items'];packs=json.loads(req('GET','/packs'))['items'];jobs=[]
for path,key,ids,progress in [('/videos/trash','video_ids',[videos[0]['id']],'/operations/'),('/packs/trash','pack_ids',[packs[0]['id']],'/pack-operations/')]:
 job=json.loads(req('POST',path,{'request_id':str(uuid.uuid4()),key:ids}));jobs.append(wait(progress+job['id']))
exported=json.loads(req('POST','/management-backups',{'request_id':str(uuid.uuid4())}));done=wait('/tasks/'+exported['id']);raw=req('GET','/management-backups/'+exported['id']+'/download');assert hashlib.sha256(raw).hexdigest()==done['result']['file_sha256']
doc=L/'checkbox-preview17.vvbackup';assert not doc.exists();doc.write_bytes(raw)
metadata={'capabilities':info['capabilities'],'logical_marks':jobs,'document':{'name':doc.name,'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw),'export_task':done['id']},'preparation_requests':events,'media_read_only':True,'not_actual_restore_or_permanent_delete':True};(L/'business-preparation.json').write_text(json.dumps(metadata,indent=2)+'\n')
subprocess.run([str(R/'.dev/android-sdk/platform-tools/adb'),'-s','emulator-5556','push',str(doc),'/sdcard/Download/'+doc.name],check=True,stdout=subprocess.DEVNULL)
print(json.dumps({'prepared':True,'capabilities':info['capabilities'],'marks':len(jobs),'document_bytes':len(raw)}))

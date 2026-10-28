import sys,json,shutil,socket,os,subprocess,time,urllib.error
from pathlib import Path
ROOT=Path('/Users/jiangxinyi/Documents/Project/video-viewer')
sys.path.insert(0,str(ROOT/'.dev/lf8-upgrade-rollback'))
from lab import tables,tree,sha
import urllib.request
EPOCH=None
def api(path,method="GET",body=None,token=None):
 headers={"Content-Type":"application/json"}
 if token:headers["Authorization"]="Bearer "+token
 if EPOCH:headers["X-Management-Epoch"]=EPOCH
 req=urllib.request.Request("http://127.0.0.1:8772"+path,headers=headers,method=method,data=None if body is None else json.dumps(body).encode())
 with urllib.request.urlopen(req,timeout=30) as r:
  raw=r.read();return json.loads(raw) if raw else None
LAB=ROOT/'.dev/lf8-app-rollback'
DATA=LAB/'lab/data'
DONOR=ROOT/'.dev/lf8-upgrade-rollback/baseline-backup/data'
MEDIA=ROOT/'.dev/lf8-preview-package/upgrade/videos'
PACKS=ROOT/'.dev/lf8-preview-package/upgrade/packs'
IMAGE='sha256:886b79b72ecb9116087d892f230471943121f24ccef093113cc3197b4607fef4'
def save(name,v):
 p=LAB/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,indent=2,ensure_ascii=False)+'\n')
def setup():
 assert not DATA.exists()
 with socket.socket() as s:s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);s.bind(('127.0.0.1',8772))
 DATA.parent.mkdir();shutil.copytree(DONOR,DATA,copy_function=shutil.copyfile)
 for name in ['config','observe','trace','screens']:(LAB/name).mkdir(exist_ok=True)
 for f in ['passphrase','mounts.json']:shutil.copyfile(ROOT/'.dev/lf8-upgrade-rollback/config'/f,LAB/'config'/f)
 mounts=json.loads((LAB/'config/mounts.json').read_text());mounts.append({'id':'packs','name':'Upgrade packs','path':'/media/packs'});(LAB/'config/mounts.json').write_text(json.dumps(mounts))
 (LAB/'config/passphrase').chmod(0o600)
 for f in ['path_log.py','logging.json']:shutil.copyfile(ROOT/'.dev/lf8-upgrade-rollback/observe'/f,LAB/'observe'/f)
 save('baseline.json',tables(DATA/'library.sqlite3',stopped=True));save('donor-before.json',tree(DONOR));save('videos-before.json',tree(MEDIA));save('packs-before.json',tree(PACKS))
 names=['video-viewer-server-1','video-viewer-client-e2e-server-1','video-viewer-archive-app-lf7','video-viewer-history-purge-app-lf7']
 (LAB/'services-before.txt').write_bytes(subprocess.check_output(['docker','inspect','--format','{{.Id}} {{.Name}} {{.State.Running}}',*names]))
 binds=[(LAB/'config','/fixture','ro'),(LAB/'observe','/observe','ro'),(LAB/'trace','/trace','rw'),(DATA,'/data','rw'),(MEDIA,'/media/videos','ro'),(PACKS,'/media/packs','ro')]
 cmd=['docker','run','-d','--name','video-viewer-app-rollback-lab','--label','video-viewer.lab=lf8-app-rollback','--read-only','--user',f'{os.getuid()}:{os.getgid()}','--shm-size=256m','--tmpfs','/tmp:mode=1777','-p','127.0.0.1:8772:8760']
 for src,dest,mode in binds:cmd+=['-v',f'{src}:{dest}:{mode}']
 cmd+=['-e','PYTHONPATH=/app:/observe','-e','VV_PASSPHRASE_FILE=/fixture/passphrase','-e','VV_MOUNTS_FILE=/fixture/mounts.json','-e','VV_SCAN_INTERVAL=0','-e','VV_STABILITY_SECONDS=0','--entrypoint','uvicorn',IMAGE,'video_viewer.app:create_app','--factory','--host','0.0.0.0','--port','8760','--workers','1','--log-config','/observe/logging.json']
 cid=subprocess.check_output(cmd,text=True).strip();save('owner.json',{'container':cid,'image':IMAGE,'command':cmd})
 for _ in range(200):
  try:api('/health');break
  except (urllib.error.URLError,ConnectionError):time.sleep(.2)
 else:raise RuntimeError('server not ready')
 save('runtime.json',json.loads(subprocess.check_output(['docker','inspect',cid],text=True))[0])
 seed()
def seed():
 global EPOCH
 token=api('/api/v1/auth/login','POST',{'passphrase':(LAB/'config/passphrase').read_text()})['access_token']
 EPOCH=api('/api/v1/info',token=token)['management_epoch']
 for _ in range(300):
  if not api('/api/v1/library-state',token=token)['scanning']:break
  time.sleep(.1)
 else:raise RuntimeError('initial scan not finished')
 api('/api/v1/roots/packs','PUT',{'name':'Upgrade packs','path':'/media/packs','kind':'pack'},token)
 task=api('/api/v1/scans','POST',{},token)
 for _ in range(300):
  actual=api('/api/v1/tasks/'+task['id'],token=token)
  if actual['status'] in ['completed','failed']:break
  time.sleep(.1)
 assert actual['status']=='completed',actual
 packs=api('/api/v1/packs',token=token)['items'];assert len(packs)==1
 tag=api('/api/v1/pack-tags','POST',{'name':'PACK_ONLY','request_id':'app-rollback-pack-tag'},token)
 api('/api/v1/pack-tag-links','PATCH',{'pack_ids':[packs[0]['id']],'tag_ids':[tag['id']],'mode':'add','request_id':'app-rollback-pack-link'},token)
 api('/api/v1/auth/session','DELETE',token=token)
 save('prepared.json',{'pack_id':packs[0]['id'],'tag_id':tag['id'],'prep_token_revoked':True})
 save('prepared-projection.json',tables(DATA/'library.sqlite3'))
 print('prepared')
if __name__=='__main__':setup()

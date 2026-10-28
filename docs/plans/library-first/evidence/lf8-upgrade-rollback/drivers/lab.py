import hashlib,json,os,shutil,socket,sqlite3,subprocess,time,urllib.request,urllib.error
from pathlib import Path
ROOT=Path('/Users/jiangxinyi/Documents/Project/video-viewer')
LAB=ROOT/'.dev/lf8-upgrade-rollback'
DONOR=ROOT/'.dev/lf8-preview-package/legacy-upgrade'
MEDIA=ROOT/'.dev/lf8-preview-package/upgrade/videos'
OLD=(ROOT/'.dev/lf8-preview-package/legacy-image-id.txt').read_text().strip()
NEW=(LAB/'current-runtime-image.txt').read_text().strip() if (LAB/'current-runtime-image.txt').exists() else 'sha256:8a1c5320fab247c7c61fc65842e8e20c1e2e6a690e2c6ae373953920feb8af20'
SOURCE='b79da7b9c4d2ab099c055b8eb855904e32abb0a5'
PORT=8772

def save(name,value):
 p=LAB/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n')
def sha(path):
 d=hashlib.sha256()
 with path.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):d.update(b)
 return d.hexdigest()
def tree(folder):return {str(f.relative_to(folder)):sha(f) for f in sorted(folder.rglob('*')) if f.is_file()}
def api(path,method='GET',body=None,token=None):
 headers={'Content-Type':'application/json'}
 if token:headers['Authorization']='Bearer '+token
 request=urllib.request.Request(f'http://127.0.0.1:{PORT}'+path,headers=headers,method=method,data=None if body is None else json.dumps(body).encode())
 with urllib.request.urlopen(request,timeout=30) as r:
  data=r.read();return json.loads(data) if data else None

def tables(path,columns=None,stopped=False):
 # immutable is used only for a stopped DB with no WAL; never for a live DB.
 if stopped:assert not Path(str(path)+'-wal').exists()
 connection=sqlite3.connect(path.as_uri()+'?mode=ro'+('&immutable=1' if stopped else ''),uri=True)
 connection.row_factory=sqlite3.Row
 result={}
 with connection as c:
  names=[r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")]
  for name in names:
   if columns is not None and name not in columns:continue
   fields=columns[name] if columns is not None else [r[1] for r in c.execute('PRAGMA table_info("'+name+'")')]
   rows=[dict(r) for r in c.execute('SELECT '+','.join('"'+s+'"' for s in fields)+' FROM "'+name+'"')]
   rows.sort(key=lambda r:json.dumps(r,sort_keys=True))
   if name=='access_tokens':
    result[name]={'columns':fields,'count':len(rows),'rows_sha256':hashlib.sha256(json.dumps(rows,sort_keys=True).encode()).hexdigest()}
   else:
    if name=='settings':
     for r in rows:
      if r['key']=='passphrase_hash':r['value']='redacted-sha256:'+hashlib.sha256(r['value'].encode()).hexdigest()
    result[name]={'columns':fields,'count':len(rows),'rows':rows}
  result['integrity']=c.execute('PRAGMA integrity_check').fetchall()[0][0]
  result['foreign_key_errors']=[list(r) for r in c.execute('PRAGMA foreign_key_check')]
 connection.close()
 return result

def preflight(phase):
 expected=sha(LAB/'data/library.sqlite3')
 code="import sqlite3,json,hashlib;from pathlib import Path;p=Path('/data/library.sqlite3');before=hashlib.sha256(p.read_bytes()).hexdigest();c=sqlite3.connect(p);schema=c.execute('select version_num from alembic_version').fetchone()[0];check=c.execute('pragma integrity_check').fetchone()[0];c.close();after=hashlib.sha256(p.read_bytes()).hexdigest();print(json.dumps({'before_sha256':before,'after_sha256':after,'schema':schema,'integrity':check}))"
 command=['docker','run','--rm','--read-only','--network','none','--user',str(os.getuid())+':'+str(os.getgid()),'-v',str(LAB/'data')+':/data:rw','--entrypoint','python',OLD,'-c',code]
 actual=json.loads(subprocess.check_output(command,text=True))
 assert actual['before_sha256']==actual['after_sha256']==expected
 assert actual['schema']=='0004' and actual['integrity']=='ok'
 assert sha(LAB/'data/library.sqlite3')==expected
 save(phase+'/container-preflight.json',{'image':OLD,'host_sha256':expected,**actual,'no_logical_write':True})

def setup():
 assert not (LAB/'data').exists()
 previous=json.loads((ROOT/'.dev/lf8-preview-package/cleanup.json').read_text());assert previous['cleanup_complete']
 for cid in [x['id'] for x in previous['owned_containers']]:assert subprocess.run(['docker','inspect',cid],capture_output=True).returncode!=0
 with socket.socket() as s:
  s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
  s.bind(('127.0.0.1',PORT))
 for name in ['config','observe','trace','screens']: (LAB/name).mkdir(exist_ok=True)
 shutil.copytree(DONOR/'data',LAB/'data',copy_function=shutil.copyfile)
 for f in ['passphrase','mounts.json']:shutil.copyfile(DONOR/'config'/f,LAB/'config'/f)
 for f in ['path_log.py','logging.json']:shutil.copyfile(ROOT/'.dev/lf8-preview-package/upgrade/observe'/f,LAB/'observe'/f)
 os.chmod(LAB/'config/passphrase',0o600)
 initial=tables(LAB/'data/library.sqlite3',stopped=True);assert initial['alembic_version']['rows']==[{'version_num':'0004'}]
 save('donor-projection.json',initial);save('donor-files.json',tree(DONOR/'data'));save('media-before.json',tree(MEDIA))
 names=['video-viewer-server-1','video-viewer-client-e2e-server-1','video-viewer-archive-app-lf7','video-viewer-history-purge-app-lf7']
 (LAB/'original-services-before.txt').write_text(subprocess.check_output(['docker','inspect','--format','{{.Id}} {{.Name}} {{.State.Running}}',*names],text=True))
 save('owner.json',{'port':PORT,'data':str(LAB/'data'),'donor':str(DONOR/'data'),'old_image':OLD,'new_image':NEW,'source':SOURCE,'uid':os.getuid(),'gid':os.getgid(),'copied_while_stopped':True})

def start(phase,version):
 assert version in ['old','new'];image=OLD if version=='old' else NEW
 with socket.socket() as s:
  s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
  s.bind(('127.0.0.1',PORT))
 preflight(phase)
 (LAB/'trace'/phase).mkdir()
 binds=[(LAB/'config','/fixture','ro'),(LAB/'observe','/observe','ro'),(LAB/'trace'/phase,'/trace','rw'),(LAB/'data','/data','rw'),(MEDIA,'/media/videos','ro')]
 command=['docker','run','-d','--name','video-viewer-upgrade-rollback-'+phase,'--label','video-viewer.lab=lf8-upgrade-rollback','--read-only','--user',str(os.getuid())+':'+str(os.getgid()),'--shm-size=256m','--tmpfs','/tmp:mode=1777','-p',f'127.0.0.1:{PORT}:8760']
 for src,dest,mode in binds:command.extend(['-v',str(src)+':'+dest+':'+mode])
 command.extend(['-e','PYTHONPATH=/app:/observe','-e','VV_PASSPHRASE_FILE=/fixture/passphrase','-e','VV_MOUNTS_FILE=/fixture/mounts.json','-e','VV_SCAN_INTERVAL=0','-e','VV_STABILITY_SECONDS=0','--entrypoint','uvicorn',image,'video_viewer.app:create_app','--factory','--host','0.0.0.0','--port','8760','--workers','1','--log-config','/observe/logging.json'])
 cid=subprocess.check_output(command,text=True).strip();save(phase+'/owner.json',{'container':cid,'image':image,'phase':phase,'command':command})
 for _ in range(200):
  try:api('/health');break
  except (urllib.error.URLError,ConnectionError):
   running=subprocess.run(['docker','inspect','--format','{{.State.Running}}',cid],capture_output=True,text=True)
   if running.stdout.strip()!='true':
    (LAB/phase/'startup-error.log').write_bytes(subprocess.check_output(['docker','logs',cid],stderr=subprocess.STDOUT));raise RuntimeError('Owned runtime exited; inspect startup-error.log')
   time.sleep(.2)
 else:raise RuntimeError('Owned server not ready')
 runtime=json.loads(subprocess.check_output(['docker','inspect',cid],text=True))[0]
 save(phase+'/runtime.json',{k:runtime[k] for k in ['Id','Name','Image','Path','Args','Mounts']})
 print(json.dumps({'phase':phase,'container':cid,'image':image,'ready':True}),flush=True)
 return cid

def stop(phase):
 r=json.loads((LAB/phase/'owner.json').read_text());cid=r['container']
 actual=json.loads(subprocess.check_output(['docker','inspect',cid],text=True))[0]
 assert actual['Config']['Labels']['video-viewer.lab']=='lf8-upgrade-rollback'
 assert any(m['Destination']=='/data' and m['Source']==str(LAB/'data') for m in actual['Mounts'])
 subprocess.run(['docker','stop','--time','15',cid],check=True,capture_output=True)
 (LAB/phase/'server.log').write_bytes(subprocess.check_output(['docker','logs',cid],stderr=subprocess.STDOUT))
 subprocess.run(['docker','rm',cid],check=True,capture_output=True)
 assert subprocess.run(['docker','inspect',cid],capture_output=True).returncode!=0
 save(phase+'/stopped.json',{'container':cid,'removed':True,'data_files':tree(LAB/'data')})

def seed():
 token=api('/api/v1/auth/login','POST',{'passphrase':(LAB/'config/passphrase').read_text()})['access_token']
 for _ in range(300):
  if not api('/api/v1/library-state',token=token)['scanning']:break
  time.sleep(.1)
 else:raise RuntimeError('Old scan not done')
 videos=api('/api/v1/videos',token=token)['items'];assert len(videos)==2
 target=next(v for v in videos if 'portrait' in v['name']);tag=api('/api/v1/tags',token=token)['items'][0]
 api('/api/v1/video-tags','PATCH',{'video_ids':[target['id']],'tag_ids':[tag['id']],'mode':'add','request_id':'upgrade-rollback-seed-link'},token)
 task=api('/api/v1/videos/trash','POST',{'video_ids':[target['id']],'request_id':'upgrade-rollback-seed-trash'},token)
 for _ in range(300):
  task=api('/api/v1/operations/'+task['id'],token=token)
  if task['status'] in ['completed','failed','interrupted']:break
  time.sleep(.1)
 assert task['status']=='completed' and task['result']['succeeded']==1
 receipt=api('/api/v1/file-requests/upgrade-rollback-seed-trash',token=token);assert receipt['id']==task['id']
 listing=api('/api/v1/videos',token=token);trash=api('/api/v1/trash',token=token);info=api('/api/v1/info',token=token);assert listing['total']==1 and trash['total']==1 and 'capabilities' not in info
 api('/api/v1/auth/session','DELETE',token=token)
 save('seeded.json',{'info':info,'videos':listing,'trash':trash,'task':task,'receipt':receipt,'prep_token_revoked':True})
 assert tree(MEDIA)==json.loads((LAB/'media-before.json').read_text())
 print(json.dumps({'seeded':True,'available_videos':1,'trash':1,'media_unchanged':True}))

if __name__=='__main__':
 import sys
 if sys.argv[1]=='setup':setup()
 elif sys.argv[1]=='start':start(sys.argv[2],sys.argv[3])
 elif sys.argv[1]=='stop':stop(sys.argv[2])
 elif sys.argv[1]=='seed':seed()
 else:raise ValueError(sys.argv[1])

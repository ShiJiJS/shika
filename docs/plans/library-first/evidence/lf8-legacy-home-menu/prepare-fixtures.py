import hashlib,json,shutil,socket,sqlite3,subprocess,time,urllib.request,urllib.error
from pathlib import Path
R=Path(__file__).resolve().parents[2];L=R/'.dev/lf8-legacy-home-menu';expected=json.loads((R/'.dev/lf8-menu-dropdown-package/cleanup.json').read_text())['original4_services_preserved_healthy'];ids=subprocess.check_output(['docker','ps','-q'],text=True).split();active=json.loads(subprocess.check_output(['docker','inspect',*ids]));assert {c['Name']:c['Id'] for c in active}==expected and all(c['State']['Health']['Status']=='healthy' for c in active)
def hashes(p):return {str(x.relative_to(p)):hashlib.sha256(x.read_bytes()).hexdigest() for x in p.rglob('*') if x.is_file()}
records=[]
for kind,donor,image,port in [('legacy',R/'.dev/lf8-preview-package/legacy-upgrade',(R/'.dev/lf8-preview-package/legacy-image-id.txt').read_text().strip(),8774),('modern',R/'.dev/lf8-menu-dropdown-package/normal','sha256:886b79b72ecb9116087d892f230471943121f24ccef093113cc3197b4607fef4',8772)]:
 out=L/kind;assert not out.exists()
 for c in active:
  for m in c['Mounts']:
   p=Path(m['Source']).resolve();assert not (p==donor.resolve() or p in donor.resolve().parents or donor.resolve() in p.parents)
 assert not any(x.stat().st_size for x in (donor/'data').glob('*-wal'))
 with socket.socket() as s:s.bind(('127.0.0.1',port))
 db=sqlite3.connect((donor/'data/library.sqlite3').as_uri()+'?mode=ro&immutable=1',uri=True);schema=db.execute('SELECT version_num FROM alembic_version').fetchone()[0];db.close();assert schema==('0004' if kind=='legacy' else '0014'),schema
 out.mkdir();(out/'trace').mkdir();(out/'screens').mkdir()
 for name in ['data','config']:shutil.copytree(donor/name,out/name)
 shutil.copytree(R/'.dev/lf8-menu-dropdown-package/normal/observe',out/'observe')
 name='video-viewer-legacy-menu-'+kind;cmd=['docker','run','-d','--name',name,'--label','video-viewer.lab=lf8-legacy-menu-'+kind,'--read-only','--shm-size=256m','--tmpfs','/tmp:mode=1777','-p',f'127.0.0.1:{port}:8760','-v',str(out/'config')+':/fixture:ro','-v',str(out/'observe')+':/observe:ro','-v',str(out/'trace')+':/trace:rw','-v',str(out/'data')+':/data:rw','-v',str(R/'.dev/lf8-preview-package/upgrade/videos')+':/media/videos:ro']
 if kind=='modern':cmd+=['--user','501:20','-v',str(R/'.dev/lf8-preview-package/upgrade/packs')+':/media/packs:ro']
 cmd+=['-e','PYTHONPATH=/app:/observe','-e','VV_PASSPHRASE_FILE=/fixture/passphrase','-e','VV_MOUNTS_FILE=/fixture/mounts.json','-e','VV_SCAN_INTERVAL=0','-e','VV_STABILITY_SECONDS=0','--entrypoint','uvicorn',image,'video_viewer.app:create_app','--factory','--host','0.0.0.0','--port','8760','--workers','1','--log-config','/observe/logging.json']
 meta={'kind':kind,'donor':str(donor),'donor_data_sha256':hashes(donor/'data'),'donor_config_sha256':hashes(donor/'config'),'source_schema':schema,'image':image,'port':port,'command':cmd,'original_containers':expected};(out/'runtime.json').write_text(json.dumps(meta,indent=2)+'\n');meta['container']=subprocess.check_output(cmd,text=True).strip();(out/'runtime.json').write_text(json.dumps(meta,indent=2)+'\n');records.append(meta);print(json.dumps({'kind':kind,'container':meta['container'],'port':port,'schema':schema}),flush=True)
media={}
for name in ['videos','packs']:media[name]=hashes(R/'.dev/lf8-preview-package/upgrade'/name)
(L/'media-before.json').write_text(json.dumps(media,indent=2)+'\n')

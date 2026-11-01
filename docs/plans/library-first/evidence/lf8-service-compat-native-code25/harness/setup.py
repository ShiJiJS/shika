from pathlib import Path
import shutil,json,subprocess,time,hashlib
R=Path('/Users/jiangxinyi/Documents/Project/video-viewer');L=R/'.dev/lf8-service-compat-native25';L.mkdir(exist_ok=False);(L/'screens').mkdir();old=R/'.dev/lf8-zoom-flow-native25';origin=R/'.dev/lf8-preview18-native';ids=['73096298c97346dd9f06932457c8a736929e168c38fc7057da669213c2580d91','be71112ad645c5816c4295d175d597ce3235ba0be9b1644d9a49d611472f5b88'];assert all(not v['State']['Running'] for v in json.loads(subprocess.check_output(['docker','inspect',*ids])))
# Offline copy only. No host process opens SQLite.
shutil.copytree(origin/'data',L/'data');shutil.copytree(origin/'config',L/'config');(L/'config').chmod(0o700)
for p in (L/'config').iterdir():
 if p.is_file():p.chmod(0o600)
for name in ['ui.py','snapshot_all.py']:
 s=(old/name).read_text().replace('lf8-native25-flow-ui.xml','lf8-native25-compat-ui.xml');(L/name).write_text(s)
s=(old/'api.py').read_text().replace('8785','8786');(L/'api.py').write_text(s)
s=(old/'proxy.py').read_text().replace('8785','8786');s=s.replace("record['request_bytes']=length", "record['request_bytes']=length\n   if parsed.path=='/api/v1/scans' and body:\n    scoped=json.loads(body);record['scan_request']={'all':not bool(scoped.get('root_id')),'root_id':scoped.get('root_id')}");(L/'proxy.py').write_text(s)
# Session credentials copied for read-only control queries; never logged.
shutil.copyfile(old/'config/session-private.json',L/'config/session-private.json');(L/'config/session-private.json').chmod(0o600)
args=['docker','run','-d','--name','video-viewer-old-service-native25','--user','0:0','--read-only','--shm-size','64m','--tmpfs','/tmp:rw,size=128m','--memory','768m','--cpus','1.5','-p','127.0.0.1:8786:8760','-e','VV_SCAN_INTERVAL=0','-e','VV_DATA_DIR=/data','-v',str(origin/'media')+':/media:ro','-v',str(L/'data')+':/data','-v',str(L/'config')+':/config:ro','-v',str(L/'config/passphrase')+':/run/secrets/passphrase:ro','video-viewer-server:0.2.0-preview.2']
cid=subprocess.check_output(args,text=True).strip();v=json.loads(subprocess.check_output(['docker','inspect',cid]))[0];(L/'runtime.json').write_text(json.dumps({'id':cid,'name':'video-viewer-old-service-native25','image':v['Image'],'server_source_expected':'b79da7b9c4d2ab099c055b8eb855904e32abb0a5','data_copy_isolated':True,'origin_stopped_containers':ids,'upstream_port':8786,'proxy_port':8783},indent=2)+'\n')
with (L/'proxy-stdout.log').open('wb') as out:p=subprocess.Popen(['python3',str(L/'proxy.py')],stdout=out,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,start_new_session=True)
(L/'proxy-process.json').write_text(json.dumps({'pid':p.pid,'script':str(L/'proxy.py'),'listen':'127.0.0.1:8783','upstream':'127.0.0.1:8786'},indent=2)+'\n');print({'container':cid,'own_phase':str(L),'offline_copy_created':True,'proxy_pid':p.pid,'media_read_only':True})

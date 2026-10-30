import hashlib,json,shutil,socket,subprocess,time,urllib.request,uuid
from pathlib import Path
R=Path(__file__).resolve().parents[2];L=R/'.dev/lf8-current-filters';S=R/'.dev/lf8-fidelity-reference';P=L/'normal';assert not P.exists()
def hashes(p):return {str(x.relative_to(p)):hashlib.sha256(x.read_bytes()).hexdigest() for x in sorted(p.rglob('*')) if x.is_file()}
active_ids=subprocess.check_output(['docker','ps','-q'],text=True).split();active=json.loads(subprocess.check_output(['docker','inspect',*active_ids]));expected=json.loads((R/'.dev/lf8-expansion-package/cleanup.json').read_text())['original4_services_preserved_healthy'];assert {x['Name']:x['Id'] for x in active}==expected and all(x['State']['Health']['Status']=='healthy' for x in active)
with socket.socket() as sock:sock.bind(('127.0.0.1',8776))
for p in ['config','data','trace','observe','screens','videos','packs']:(P/p).mkdir(parents=True)
meta=json.loads((R/'.dev/lf8-expansion-package/normal/runtime.json').read_text());template=R/'.dev/lf8-expansion-package/normal'
shutil.copytree(template/'observe',P/'observe',dirs_exist_ok=True)
shutil.copy2(template/'config/passphrase',P/'config/passphrase')
packs=json.loads((S/'packs.json').read_text());source_hash=hashes(S/'raster');media={}
for pack in packs:
 folder=P/'packs'/pack['folder'];folder.mkdir()
 for n,page in enumerate(pack['pages'],1):shutil.copy2(S/'raster'/Path(page).with_suffix('.png').name,folder/f'{n:04d}.png')
for i in range(1,28):
 folder=P/'packs'/f'Scope {i:02d}';folder.mkdir()
 for n in range(1,7):shutil.copy2(S/'raster'/f'summer-{n}.png',folder/f'{n:04d}.png')
for orient,title in [('landscape','风里的花园'),('portrait','水边的花')]:
 folder=P/'videos'/('横屏' if orient=='landscape' else '竖屏');folder.mkdir();shutil.copy2(R/'.dev/lf8-preview-package/upgrade/videos'/f'flower-{orient}.mp4',folder/(title+'.mp4'))
for i in range(1,28):
 folder=P/'videos'/('Landscape/Child' if i%2 else 'Portrait/Child');folder.mkdir(parents=True,exist_ok=True);shutil.copy2(R/'.dev/lf8-preview-package/upgrade/videos'/('flower-landscape.mp4' if i%2 else 'flower-portrait.mp4'),folder/f'Scope {i:02d}.mp4')
(P/'config/mounts.json').write_text(json.dumps([{'id':'videos','name':'短视频','path':'/media/videos'},{'id':'packs','name':'图包','path':'/media/packs'}],ensure_ascii=False))
cmd=[v.replace(str(template),str(P)).replace('video-viewer-expansion-normal','video-viewer-current-filters-normal').replace('lf8-expansion-normal','lf8-current-filters-normal').replace(str(R/'.dev/lf8-expansion-package/media/videos'),str(P/'videos')).replace(str(R/'.dev/lf8-expansion-package/media/packs'),str(P/'packs')).replace('127.0.0.1:8772:8760','127.0.0.1:8776:8760').replace('VV_STABILITY_SECONDS=15','VV_STABILITY_SECONDS=0') for v in meta['command']]
cmd=[v.replace('127.0.0.1:8772:8760','127.0.0.1:8776:8760') for v in cmd]
meta={'image':meta['image'],'command':cmd,'original_containers':expected,'source_raster_sha256':source_hash,'public_media_sha256':{k:hashes(P/k) for k in ['videos','packs']},'fresh_empty_data':True,'production_server_unmodified':True}
(P/'runtime.json').write_text(json.dumps(meta,indent=2)+'\n');meta['container']=subprocess.check_output(cmd,text=True).strip();(P/'runtime.json').write_text(json.dumps(meta,indent=2)+'\n')
headers={};events=[]
def req(method,path,v=None):
 raw=None if v is None else json.dumps(v).encode()
 with urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8776/api/v1'+path,data=raw,method=method,headers={**headers,'Content-Type':'application/json'}),timeout=30) as r:answer=json.load(r);status=r.status
 events.append({'time':time.time(),'method':method,'path':path,'status':status});(L/'preparation-requests.json').write_text(json.dumps(events,indent=2)+'\n');return answer
end=time.monotonic()+30
while True:
 try:
  headers['Authorization']='Bearer '+req('POST','/auth/login',{'passphrase':(P/'config/passphrase').read_text().strip()})['access_token'];break
 except OSError:
  assert time.monotonic()<end;time.sleep(.25)
(P/'config/observer-token').write_text(headers['Authorization'].removeprefix('Bearer '));(P/'config/observer-token').chmod(0o600)
headers['X-Management-Epoch']=req('GET','/info')['management_epoch']
def wait():
 end=time.monotonic()+60
 while True:
  s=req('GET','/library-state')
  if not s['scanning']:assert s['status']=='completed';return s
  assert time.monotonic()<end;time.sleep(.25)
wait();roots=req('GET','/roots')['items'];packroot=next(r for r in roots if r['path']=='/media/packs');req('PUT','/roots/'+packroot['id'],{'name':'图包','path':'/media/packs','kind':'pack','enabled':True});req('POST','/scans');ready=wait()
videos=req('GET','/videos')['items'];indexed=req('GET','/packs?limit=100')['items'];assert len(videos)==29 and len(indexed)==31 and all(p['page_count']==6 for p in indexed)
ids={}
for kind,names in [('video',['户外','自然','喜欢','Scope','Intersection']),('pack',['和服','户外','白裙','角色','喜欢','Scope','Intersection'])]:
 tags={}
 for name in names:
  tag=req('POST','/tags' if kind=='video' else '/pack-tags',{'request_id':str(uuid.uuid4()),'name':name});tags[name]=tag['id']
 ids[kind]=tags
for v in videos:
 names=['户外','Scope']+(['Intersection'] if 'Scope ' in v['name'] or '风里' in v['name'] else []);req('PATCH','/video-tags',{'request_id':str(uuid.uuid4()),'video_ids':[v['id']],'tag_ids':[ids['video'][n] for n in names],'mode':'replace'})
for p in indexed:
 description=({'tags':['Scope','Intersection']} if p['name'].startswith('Scope ') else {'tags':next(x for x in packs if x['folder']==p['name'])['tags']+['Scope']});req('PATCH','/pack-tag-links',{'request_id':str(uuid.uuid4()),'pack_ids':[p['id']],'tag_ids':[ids['pack'][n] for n in description['tags']],'mode':'replace'})
(L/'seed.json').write_text(json.dumps({'ready':ready,'videos':videos,'packs':indexed,'tags':ids,'public_fixture_only':True,'progress_seeded':False,'no_direct_database_writes':True},indent=2,ensure_ascii=False)+'\n')
for n in ['driver.py','ui_driver.py','business_ui.py','snapshot_all.py']:
 text=(template/n).read_text().replace('.dev/lf8-expansion-package/normal','.dev/lf8-current-filters/normal').replace('video-viewer-expansion-normal','video-viewer-current-filters-normal');(P/n).write_text(text)
print(json.dumps({'ready':True,'container':meta['container'],'videos':len(videos),'packs':len(indexed),'images':sum(p['page_count'] for p in indexed)}))

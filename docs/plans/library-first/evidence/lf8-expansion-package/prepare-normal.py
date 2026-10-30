import hashlib,json,shutil,socket,subprocess
from pathlib import Path
R=Path(__file__).resolve().parents[2];L=R/'.dev/lf8-expansion-package';D=R/'.dev/lf8-checkbox-package/normal';O=L/'normal';assert not O.exists()
def hashes(p):return {str(x.relative_to(p)):hashlib.sha256(x.read_bytes()).hexdigest() for x in sorted(p.rglob('*')) if x.is_file()}
ids=subprocess.check_output(['docker','ps','-q'],text=True).split();active=json.loads(subprocess.check_output(['docker','inspect',*ids]));expected=json.loads((R/'.dev/lf8-expansion-native/cleanup-native.json').read_text())['original4_services_preserved_healthy'];assert {c['Name']:c['Id'] for c in active}==expected and all(c['State']['Health']['Status']=='healthy' for c in active)
for c in active:
 for m in c['Mounts']:
  p=Path(m['Source']).resolve();assert not (p==D.resolve() or p in D.resolve().parents or D.resolve() in p.parents)
with socket.socket() as s:s.bind(('127.0.0.1',8772))
files=hashes(D/'data');config=hashes(D/'config');O.mkdir();(O/'trace').mkdir();(O/'screens').mkdir()
for n in ['data','config','observe']:shutil.copytree(D/n,O/n)
assert hashes(O/'data')==files and hashes(O/'config')==config
old=json.loads((D/'runtime.json').read_text())
media_source=R/'.dev/lf8-preview-package/upgrade'
(L/'media').mkdir()
for name in ['videos','packs']:shutil.copytree(media_source/name,L/'media'/name)
cmd=[v.replace(str(D),str(O)).replace('video-viewer-checkbox-normal','video-viewer-expansion-normal').replace('lf8-checkbox-normal','lf8-expansion-normal').replace(str(media_source/'videos'),str(L/'media/videos')).replace(str(media_source/'packs'),str(L/'media/packs')).replace('VV_STABILITY_SECONDS=0','VV_STABILITY_SECONDS=15') for v in old['command']]
meta={'donor':str(D),'donor_data_sha256':files,'donor_config_sha256':config,'source_nonempty_wal':{p.name:p.stat().st_size for p in (D/'data').glob('*-wal') if p.stat().st_size},'copy_method':'entire inactive data including WAL/SHM; no host SQLite open; new owner recovers copy','original_containers':expected,'image':old['image'],'command':cmd};(O/'runtime.json').write_text(json.dumps(meta,indent=2)+'\n')
meta['container']=subprocess.check_output(cmd,text=True).strip();(O/'runtime.json').write_text(json.dumps(meta,indent=2)+'\n')
for n in ['driver.py','ui_driver.py','business_ui.py','snapshot.py','snapshot_all.py']:
 text=(D/n).read_text().replace('.dev/lf8-checkbox-package/normal','.dev/lf8-expansion-package/normal').replace('video-viewer-checkbox-normal','video-viewer-expansion-normal')
 (O/n).write_text(text)
media={n:hashes(R/'.dev/lf8-preview-package/upgrade'/n) for n in ['videos','packs']};(L/'media-before.json').write_text(json.dumps(media,indent=2)+'\n')
print(json.dumps({'ready':True,'container':meta['container'],'copied_files':len(files),'nonempty_wal':meta['source_nonempty_wal']}))

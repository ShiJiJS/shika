"""Read only verification of fixed public artifacts; no device, service or SQLite."""
import hashlib,json,xml.etree.ElementTree as ET
from pathlib import Path
from PIL import Image,ImageChops
R=Path(__file__).resolve().parent
read=lambda name:json.loads((R/name).read_text())
m=read('manifest.json');files={str(p.relative_to(R)) for p in R.rglob('*') if p.is_file() and p.name!='manifest.json' and '__pycache__' not in p.parts};assert files==set(m['files'])
for name,v in m['files'].items():
 p=R/name;raw=p.read_bytes();assert not p.is_symlink() and len(raw)==v['bytes'] and hashlib.sha256(raw).hexdigest()==v['sha256'],name
b=read('build-1/result.json');assert b['complete'] and b['source']==m['source'] and len(b['steps'])==13
for s in b['steps']:
 assert s['exit_code']==0 and hashlib.sha256((R/'build-1'/(s['name']+'.log')).read_bytes()).hexdigest()==s['log_sha256']
for kind in ['forward','rollback']:
 assert b[kind]['version_code']==21 and b[kind]['certificate_sha256']=='f5abd3bd11d94b3aaee66ab65e6a666a228a4d64edf4b86de9327ae9b8a59161'
assert '+27: All tests passed!' in (R/'focus-final.log').read_text();assert 'No issues found!' in (R/'analyze-final.log').read_text()
for name,kind in [('install21','forward'),('rollback21','rollback'),('return21','forward')]:
 a,z=[read('normal/'+name+'-'+x+'-all-catalog.json') for x in ['before','after']];assert len(a['tables'])==35
 for key in ['tables','opaque_table_digests','setting_key_sha256']:assert a[key]==z[key],(name,key)
 assert read('normal/'+name+'-before-preferences.json')==read('normal/'+name+'-after-preferences.json')
 v=read('normal/'+name+'-install.json');assert '-r' in v['command'] and v['sha256']==b[kind]['sha256'] and v['no_uninstall_or_clear']
 for key in ['firstInstallTime','dataDir','appId']:assert v['before'][key]==v['after'][key]
 assert v['after']['versionCode'].split()[0]=='21'
for name,kind in [('current21','forward'),('rollback21','rollback'),('return21','forward')]:assert read('normal/'+name+'-actual-apk.json')['sha256']==b[kind]['sha256']
for n in range(1,4):
 name=f'cold21-{n}';a,z=[read('normal/'+name+'-'+x+'-all-catalog.json') for x in ['before','after']]
 for key in ['tables','opaque_table_digests','setting_key_sha256']:assert a[key]==z[key]
 assert read('normal/'+name+'-before-preferences.json')==read('normal/'+name+'-after-preferences.json')
 run=read('cold21-result.json')['runs'][n-1];assert run['old_pid']!=run['new_pid'];assert all(json.loads(line)['method'] in ['GET','HEAD'] for line in run['request_lines'])
 nodes=list(ET.parse(R/'normal/screens'/(name+'-landing.xml')).iter('node'));labels=[x.get('content-desc') or x.get('text') for x in nodes];assert all(x in labels for x in ['媒体库','标签','最近','设置']);assert '视频预览' not in labels
flow=read('reader-flow3-result.json');assert flow['rounds']==3 and len(flow['checks'])==33 and flow['same_signed_normal_code']==21
for c in flow['checks']:
 v=read(c['name']+'-observer.json');s=v['session'];assert s['scope']['search']=='Scope' and s['scope']['tag_ids']==[] and s['source']['kind']=='library' and s['candidate_count']==27 and s['cursor']==25;assert v['pack']['progress']['page_index']==c['page_index'];items=v['entries']['items'];assert len(items)==27 and [x['ordinal'] for x in items]==list(range(27));assert [x['pack']['name'] for x in items]==[f'Scope {n:02}' for n in range(1,28)]
for i in range(1,4):
 v=read(f'flow3-round-{i}-returned-anchor.json');assert v['before']==v['after'] and v['search']=='Scope' and v['matched']==27
v=read('tag-source-range.json');assert v['session']['source']['kind']=='tags' and v['session']['scope']['search']=='' and len(v['session']['scope']['tag_ids'])==2 and v['session']['candidate_count']==27
v=read('recent-source-range.json');assert v['session']['source']['kind']=='recent' and v['session']['scope']['search']=='' and v['session']['scope']['tag_ids']==[] and v['session']['candidate_count']==1
for name,count,source in [('video-library-source',2,'library'),('video-tag-source',1,'tags')]:
 v=read(name+'-round.json');assert v['round']['source']==source and v['round']['membership']=='fixed' and v['round']['candidate_count']==count and len(v['entries'])==count
# The gestures below were actually executed on code20, whose reader module is unchanged.
assert read('source-boundary.json')['gesture_execution_code']==20
S=R/'normal/screens'
def picture(state):
 with Image.open(next(S.glob('*-'+state+'.png'))) as im:return im.convert('RGB').crop((0,315,1170,2160))
base=picture('gesture2-baseline');before=read('gesture2-before-reader-service.json')['progress']
for i in range(1,4):
 for kind in ['pinch','double']:
  for state in ['zoomed','panned','back-reset']:
   label=f'gesture2-round-{i}-{kind}-{state}';delta=ImageChops.difference(base,picture(label));assert (delta.getbbox() is None)==(state=='back-reset');assert read(label+'-reader-service.json')['progress']==before
for key in ['tables','opaque_table_digests','setting_key_sha256']:assert read('normal/gesture2-baseline-all-catalog.json')[key]==read('normal/gesture2-after-all-catalog.json')[key]
pts=[float(x['pts_time']) for x in read('gesture2-frame-times.json')['frames']];assert len(pts)==323 and all(a<z for a,z in zip(pts,pts[1:]));assert read('gesture2-framehash-result.json')['decoded_frame_rows']==323;assert read('gesture2-framehash-result.json')['exit_code']==0;assert (R/'gesture2-framehash-decode.log').read_bytes()==b''
c=read('cleanup.json');assert c['restored_device_settings']==read('original-settings.json') and c['exact_initial_uid_restored'] and c['original_containers_before']==c['original_containers_after'];assert read('media-integrity-final.json')['files']==188
print(json.dumps({'verified_files':len(files),'normal_code':21,'cover_installs':3,'cold_starts':3,'reader_flow_rounds':3,'gesture_execution_code':20,'whole_acceptance_ids_passed':0}))

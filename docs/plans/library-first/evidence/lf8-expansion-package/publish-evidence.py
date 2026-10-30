import hashlib,json,shutil,subprocess
from pathlib import Path
L=Path(__file__).resolve().parent;R=L.parents[1];O=L/'normal';read=lambda p:json.loads(p.read_text())
assert read(L/'business-audit.json')['complete'] and read(L/'cleanup.json')['complete']
D=R/'docs/plans/library-first/evidence/lf8-expansion-package';assert not D.exists();D.mkdir()
for p in L.iterdir():
 if p.is_file() and (p.suffix in ['.json','.py','.log'] or p.name=='source-ref'):shutil.copy2(p,D/p.name)
for folder in ['normal','business-2','build-1']:
 (D/folder).mkdir()
 for p in (L/folder).iterdir():
  if p.is_file() and p.suffix in ['.json','.jsonl','.py','.txt','.log']:shutil.copy2(p,D/folder/p.name)
for folder in ['normal/screens','normal/trace']:shutil.copytree(L/folder,D/folder)
a=read(O/'before-scan-business-2-all-catalog.json');b=read(O/'after-scan-business-2-all-catalog.json');(D/'normal/proof-posters').mkdir()
for name,v in [('before',a),('after',b)]:
 row=next(x for x in v['tables']['videos'] if x['name']=='Expansion-probe.mp4');shutil.copy2(O/'data/thumbnails'/row['thumbnail'],D/'normal/proof-posters'/(name+'.jpg'))
s=(L/'audit-business.py').read_text();s=s[:s.index("result={'complete'")]
s=s.replace("L=Path(__file__).resolve().parent;O=L/'normal';B=L/'business-2';read=lambda p:json.loads(p.read_text())",'''L=Path(__file__).resolve().parent;O=L/'normal';B=L/'business-2';read=lambda p:json.loads(p.read_text())
m=read(L/'manifest.json')
for name,v in m['files'].items():
 data=(L/name).read_bytes();assert len(data)==v['bytes'] and hashlib.sha256(data).hexdigest()==v['sha256'],name''')
s=s.replace("(O/'data/thumbnails'/old['thumbnail']).read_bytes()","(O/'proof-posters/before.jpg').read_bytes()").replace("(O/'data/thumbnails'/new_v[key]['thumbnail']).read_bytes()","(O/'proof-posters/after.jpg').read_bytes()")
s+='''
cleanup=read(L/'cleanup.json');assert cleanup['complete'] and cleanup['owned_qemu_absent'] and cleanup['entering_uid_restored']
assert cleanup['settings_restored']==read(L/'original-settings.json') and cleanup['original4_services_preserved_healthy']==read(O/'runtime.json')['original_containers']
build=read(L/'build-1/result.json');assert build['complete'] and build['source']==m['source'] and len(build['steps'])==13
for step in build['steps']:
 assert step['exit_code']==0 and hashlib.sha256((L/'build-1'/(step['name']+'.log')).read_bytes()).hexdigest()==step['log_sha256']
for kind,version in [('forward','0.2.0-preview.12'),('rollback','0.1.4-rollback.12')]:
 v=build[kind];assert v['version_code']==18 and v['version']==version and v['normal_entrypoint'] and not v['integration_test_plugin'] and v['flutter_engine_abis']==['arm64-v8a']
 assert v['certificate_sha256']=='f5abd3bd11d94b3aaee66ab65e6a666a228a4d64edf4b86de9327ae9b8a59161'
assert read(L/'installed-final-apk.json')['sha256']==build['forward']['sha256']
assert read(L/'package-audit.json')['production_lib']=='2f02bc78653acbf12de64107e41e3236d61cb9cf'
assert m['prototype_tree']=='1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
print(json.dumps({'complete':True,'frozen_inputs':len(m['files']),'upgrade_checks':3,'business_rounds':3,'ordinary_reduced_directions':12,'additional_open_before_scan':3,'recovery_directions':6,'state_checks':9,'critical_xml_png_states':len(proof),'normal_main':True,'resources_restored':True,'target_phone_nas_acceptance':False}))
'''
(D/'verify.py').write_text('"""Offline read-only check: no APKs, devices, services or databases opened."""\n'+s)
# README is written separately before freezing, so diagnostic boundaries stay explicit.
shutil.copy2(L/'EVIDENCE-README.md',D/'README.md')
files={str(p.relative_to(D)):{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(D.rglob('*')) if p.is_file()}
(D/'manifest.json').write_text(json.dumps({'source':read(L/'build-1/result.json')['source'],'prototype_tree':'1cbf605af8f03fa067a4ce8e914bb809e3a487ca','files':files},indent=2)+'\n')
print(json.dumps({'frozen_inputs':len(files),'bytes':sum(v['bytes'] for v in files.values())}))

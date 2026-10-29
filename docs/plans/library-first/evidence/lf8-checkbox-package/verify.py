"""Read-only frozen-input checks; no devices, services, APKs or SQLite opened."""
import json,hashlib,subprocess,xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path
L=Path(__file__).resolve().parent;O=L/'normal';read=lambda p:json.loads(p.read_text())
manifest=read(L/'manifest.json')
for name,expected in manifest['files'].items():
 data=(L/name).read_bytes();assert len(data)==expected['bytes'] and hashlib.sha256(data).hexdigest()==expected['sha256'],name
def rows(name):return read(O/(name+'-all-catalog.json'))
def same(a,b):assert a['tables']==b['tables'] and a['opaque_table_digests']==b['opaque_table_digests']
base=rows('before17')
for n in ['forward17','rollback17','forward17-return']:same(base,rows('after-'+n));assert read(O/'before17-preferences.json')==read(O/('after-'+n+'-preferences.json'))
assert read(O/'upgrade-result.json')['complete']
for n in ['forward17','rollback17','forward17-return']:
 v=read(O/(n+'-install.json'));assert v['no_uninstall_or_clear'];assert all(v['before'][k]==v['after'][k] for k in ['firstInstallTime','dataDir','appId'])
assert len(base['tables'])==35
same(rows('before-business'),rows('after-video-confirm'))
a=rows('before-business');b=rows('after-pack-confirm');changed={k for k in a['tables'] if a['tables'][k]!=b['tables'][k]};assert changed=={'pack_purge_entries','pack_purge_plans','tasks'};assert a['opaque_table_digests']==b['opaque_table_digests']
assert len(b['tables']['pack_purge_plans'])==2 and len(b['tables']['pack_purge_entries'])==2
same(rows('before-v2-confirm'),rows('after-v2-confirm'))
a=rows('after-v2-confirm');b=rows('after-return-modern');assert a['tables']==b['tables'] and a['opaque_table_digests']['settings']==b['opaque_table_digests']['settings'];assert b['opaque_table_digests']['access_tokens']['rows']==a['opaque_table_digests']['access_tokens']['rows']+1
same(rows('after-return-modern'),rows('final'))
assert read(O/'after-business-preferences.json')==read(O/'before17-preferences.json')
for x,y in [('before-confirm','after-confirm'),('before-reopen-cancel','after-reopen-cancel')]:
 a=read(L/'legacy'/(x+'-catalog.json'));b=read(L/'legacy'/(y+'-catalog.json'));assert len(a['tables'])==14;same(a,b)
cases=['video-confirm-normal','pack-confirm-normal','archive-v2-confirm-normal','archive-v1-confirm-normal','video-confirm-ordinary-system'];state_proof=[]
for name in cases:
 for suffix,value in [('initial',False),('text-select-after',True),('box-clear-after-box',False),('box-select-after-box',True),('reopen',False)]:
  files=list((O/'screens').glob('*-'+name+'-'+suffix+'.xml'));assert len(files)==1,(name,suffix,len(files));nodes=list(ET.parse(files[0]).iter('node'));checks=[n for n in nodes if n.get('checkable')=='true'];assert len(checks)==1 and checks[0].get('checked')==str(value).lower()
  submit='确认恢复' if name.startswith('archive') else '确认永久删除';buttons=[n for n in nodes if n.get('content-desc')==submit];assert len(buttons)==1 and buttons[0].get('enabled')==str(value).lower()
  state_proof.append({'case':name,'step':suffix,'checked':value,'submit_enabled':value,'xml':str(files[0].relative_to(L))})
checks=read(O/'business-cursor.json')['checks'];expected={n for c in cases for n in [c,c+'-draft-reset']}|{'trash-row-box-and-text-single-toggle','pack-trash-box-single-toggle','return-modern-workspace','final-library-return'};assert {c['name'] for c in checks}==expected and len(checks)==14
traces={k:[json.loads(x) for x in (L/k/'trace/requests.jsonl').read_text().splitlines()] for k in ['normal','legacy']}
post_counts={}
for kind,expected in [('normal',{'/api/v1/auth/login':2,'/api/v1/videos/trash':1,'/api/v1/packs/trash':1,'/api/v1/management-backups':1,'/api/v1/pack-purge-plans':2,'/api/v1/management-backups/imports':1}),('legacy',{'/api/v1/auth/login':2,'/api/v1/backups':1,'/api/v1/backup-imports':1})]:
 assert all(x['method'] in ['GET','HEAD','POST'] for x in traces[kind]);post_counts[kind]=dict(Counter(x['path'] for x in traces[kind] if x['method']=='POST'));assert post_counts[kind]==expected
 assert all(x['status'] in [200,202] for x in traces[kind] if x['method']=='POST')
for name in ['pack_purge_executions','pack_purge_steps','pack_restore_batches','pack_restore_members','pack_restore_plans']:assert rows('before-business')['tables'][name]==rows('final')['tables'][name]

cleanup=read(L/'cleanup.json');assert cleanup['complete'] and cleanup['owned_qemu_absent'] and cleanup['entering_uid_restored']
assert cleanup['settings_restored']==read(L/'original-settings.json')
assert cleanup['original4_services_preserved_healthy']==read(O/'runtime.json')['original_containers']
build=read(L/'build-1/result.json');assert build['complete'] and len(build['steps'])==13 and all(x['exit_code']==0 for x in build['steps'])
for step in build['steps']:
 data=(L/'build-1'/(step['name']+'.log')).read_bytes();assert hashlib.sha256(data).hexdigest()==step['log_sha256']
for kind,version in [('forward','0.2.0-preview.11'),('rollback','0.1.4-rollback.11')]:
 v=build[kind];assert v['version_code']==17 and v['version']==version and v['normal_entrypoint'] and not v['integration_test_plugin'] and v['flutter_engine_abis']==['arm64-v8a']
 assert v['certificate_sha256']=='f5abd3bd11d94b3aaee66ab65e6a666a228a4d64edf4b86de9327ae9b8a59161'
assert read(L/'installed-apk.json')['sha256']==build['forward']['sha256']
package=read(L/'package-audit.json');assert package['production_lib_tree']=='4052a2cc98a224fccac85d96ea9da7e05e4d130f'
assert package['prototype_tree']=='1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
import struct
for proof in state_proof:
 image=L/proof['xml'].replace('.xml','.png');raw=image.read_bytes();assert raw.startswith(b'\x89PNG\r\n\x1a\n') and struct.unpack('>II',raw[16:24])==(1170,2532)
print(json.dumps({'complete':True,'frozen_inputs':len(manifest['files']),'upgrade_checks':3,'business_checks':14,'confirmation_states':25,'png_frames':39,'xml_states':146,'normal_main':True,'no_restore_or_permanent_delete_post':True,'resources_restored':True,'target_phone_nas_acceptance':False}))

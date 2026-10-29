import json,hashlib,subprocess,xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path
L=Path(__file__).resolve().parent;R=L.parents[1];O=L/'normal';read=lambda p:json.loads(p.read_text())
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
def hashes(p):return {str(f.relative_to(p)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(p.rglob('*')) if f.is_file()}
for kind in ['normal','legacy']:
 m=read(L/kind/'runtime.json');assert hashes(Path(m['donor'])/'data')==m['donor_data_sha256'];assert hashes(Path(m['donor'])/'config')==m['donor_config_sha256']
media=read(L/'media-before.json');assert {n:hashes(R/'.dev/lf8-preview-package/upgrade'/n) for n in ['videos','packs']}==media
result={'complete':True,'source':read(L/'build-1/result.json')['source'],'three_upgrade_installs_35_tables_preserved':True,'ui_checks':14,'confirmation_state_observations':25,'five_confirmation_cycles_including_ordinary_system_followup':cases,'four_distinct_confirmation_pages':True,'normal_and_legacy_restore_cancel_tables_unchanged':True,'normal_post_counts':post_counts['normal'],'legacy_post_counts':post_counts['legacy'],'no_permanent_delete_or_restore_post':True,'media_sha256_unchanged':True,'both_donors_data_and_config_sha256_unchanged':True,'preferences_unchanged':True,'normal_main_only_not_timing_or_target_phone_acceptance':True}
(L/'business-audit.json').write_text(json.dumps(result,indent=2)+'\n');(L/'confirmation-state-proof.json').write_text(json.dumps(state_proof,indent=2)+'\n');print(json.dumps(result))

"""Only inspect fixed public files; never connect to devices/services/SQLite."""
import hashlib,json,re,xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import parse_qs
R=Path(__file__).resolve().parent
read=lambda n:json.loads((R/n).read_text())
m=read('manifest.json');files={str(p.relative_to(R)) for p in R.rglob('*') if p.is_file() and p.name!='manifest.json' and '__pycache__' not in p.parts};assert files==set(m['files'])
for name,v in m['files'].items():
 p=R/name;raw=p.read_bytes();assert not p.is_symlink() and len(raw)==v['bytes'] and hashlib.sha256(raw).hexdigest()==v['sha256'],name
assert '+23: All tests passed!' in (R/'controller-tests.log').read_text()
proof=read('recovery-result.json');assert proof['complete'] and proof['normal_code']==22 and {(x['kind'],x['round']) for x in proof['runs']}=={(k,i) for k in ['video','pack'] for i in range(1,4)}
seed=read('seed.json');events=[json.loads(x) for x in (R/'proxy-events.jsonl').read_text().splitlines()]
S=R/'normal/screens'
def nodes(context):
 paths=sorted(S.glob('*-'+context+'.xml'));assert len(paths)==1,context;return list(ET.parse(paths[0]).iter('node'))
def text(context):return '\n'.join(n.get('content-desc','')+'\n'+n.get('text','') for n in nodes(context))
def field(context):
 a=[n for n in nodes(context) if n.get('class')=='android.widget.EditText'];assert len(a)==1;return a[0].get('text')
def rect(n):return list(map(int,re.findall(r'\d+',n.get('bounds'))))
def card(rows,name):
 a=[n for n in rows if n.get('clickable')=='true' and name in n.get('content-desc','').splitlines()];assert len(a)==1;return rect(a[0])
for run in proof['runs']:
 k,i=run['kind'],run['round'];prefix=f'v2-r{i}-{k}';path='/api/v1/videos' if k=='video' else '/api/v1/packs';kind='视频' if k=='video' else '图包'
 source=seed['videos' if k=='video' else 'packs'];last={x['id'] for x in source if x['name'].startswith(('Scope 25','Scope 26','Scope 27'))};first={x['id'] for x in source if x['name'].startswith('Scope ') and x['id'] not in last};assert len(last)==3 and len(first)==24
 failure=run['failure'];assert failure['event']=='injected_failure' and failure['status']==503 and failure['authenticated_authority_header_preserved'];q=parse_qs(failure['query']);assert q['search']==['Scope'] and q['offset']==['24']
 retry=run['retry_page'];assert retry['rule'] is None and retry['time']>failure['time'] and retry['body_summary']['total']==27 and set(retry['body_summary']['ids'])==last;assert parse_qs(retry['query'])==q
 anchor=read(prefix+'-retry-anchor.json');a,b=anchor['before'],anchor['after'];assert a['card']['name']==b['card']['name'] and abs(a['inset']-b['inset'])<=3
 errorfiles=[p for p in S.glob('*-'+prefix+'-scroll-*.xml')];assert len(errorfiles)==1;errorrows=list(ET.parse(errorfiles[0]).iter('node'));assert card(errorrows,a['card']['name'])==a['card']['bounds'];assert card(nodes(prefix+'-retried'),b['card']['name'])==b['card']['bounds']
 for value,rows in [(a,errorrows),(b,nodes(prefix+'-retried'))]:
  views=[rect(n) for n in rows if n.get('scrollable')=='true'];assert views==[value['viewport']];assert value['card']['bounds'][1]-value['viewport'][1]==value['inset']
 tails=list(S.glob('*-'+prefix+'-after-retry-tail-*.xml'));assert len(tails)==1;assert any('Scope 27' in n.get('content-desc','').splitlines() for n in ET.parse(tails[0]).iter('node'))
 empty=run['initial_empty_retry_same_query'];assert field(prefix+'-empty-error')==field(prefix+'-empty-restored')==empty and '测试读取暂不可用' in text(prefix+'-empty-error');assert f'0 个{kind}' in text(prefix+'-empty-restored')
 er=[x for x in events if x.get('rule')==prefix+'-initial-fail' and x['event']=='injected_failure'];assert er and er[-1]['authenticated_authority_header_preserved']
 held=run['held'];released=run['released'];assert held['body_summary']['total']==27 and set(held['body_summary']['ids'])==first and held['time']<released['time'];new=run['new_query_after_release']
 newer=[e for e in events if e['event']=='catalog_response' and e['path']==path and parse_qs(e['query']).get('search')==[new] and e['body_summary']['total']==0 and held['time']<e['time']<released['time']];assert newer
 assert run['outcomes'] and all(e['event'] in ['sent','client_closed'] and e['time']>=released['time'] for e in run['outcomes'])
 for suffix in ['new-search-ready','after-late-release','late-still-empty']:
  context=prefix+'-'+suffix;assert field(context)==new and f'0 个{kind}' in text(context);label='预览此范围' if k=='video' else '快速整理';assert any(n.get('content-desc')==label and n.get('enabled')=='false' for n in nodes(context))
a,z=[read('normal/read-recovery-v2-'+x+'-all-catalog.json') for x in ['before','after']];assert len(a['tables'])==35
for key in ['tables','opaque_table_digests','setting_key_sha256']:assert a[key]==z[key]
assert read('normal/read-recovery-v2-before-preferences.json')==read('normal/read-recovery-v2-after-preferences.json')
for table in ['playback_rounds','pack_sessions','pack_progress','recent_entries']:assert a['tables'][table]==[]
before,after=read('initial-app-data-digests.json'),read('after-reconcile-app-data-digests.json');stable=lambda v:{k:x for k,x in v.items() if '/cache/' not in k and '/code_cache/' not in k};assert len(stable(before))==8 and stable(before)==stable(after);delta=read('install-cache-delta.json');assert not delta['added'] and not delta['changed'] and all('/cache/' in p for p in delta['removed'])
installed=read('installed-apk.json');assert installed['no_uninstall_or_clear'] and installed['not_an_independent_new_upgrade_cycle_proof'] and installed['sha256']==read('integrity-final.json')['normal_apk_sha256']
c=read('cleanup.json');assert c['restored_device_settings']==read('original-settings.json') and c['exact_initial_uid_restored'] and c['original_containers_before']==c['original_containers_after'] and c['guest_sync_before_stop'];assert c['proxy_pid_stopped']==read('proxy-process.json')['pid']
p=read('persistence-check.json');assert p['package_available'] and p['no_reinstall_clear_or_launch'] and p['root_not_enabled'] and p['owned_qemu_stopped'] and p['sha256']==installed['sha256'];assert read('integrity-final.json')['source_media_files']==215 and read('integrity-final.json')['original4_healthy_after_persistence_boot']
print(json.dumps({'verified_files':len(files),'normal_code':22,'native_runs':6,'controller_tests':23,'all_tables_unchanged':35,'wire_sent_late_responses':sum(e['event']=='sent' for x in proof['runs'] for e in x['outcomes']),'one_post_sync_boot_package_available':True,'whole_acceptance_ids_passed':0}))

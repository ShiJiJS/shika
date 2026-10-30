"""Read only fixed public artifacts, never devices, services or SQLite."""
import hashlib,json,xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import parse_qs
R=Path(__file__).resolve().parent
read=lambda n:json.loads((R/n).read_text())
m=read('manifest.json');files={str(p.relative_to(R)) for p in R.rglob('*') if p.is_file() and p.name!='manifest.json' and '__pycache__' not in p.parts};assert files==set(m['files'])
for n,v in m['files'].items():
 p=R/n;raw=p.read_bytes();assert not p.is_symlink() and len(raw)==v['bytes'] and hashlib.sha256(raw).hexdigest()==v['sha256'],n
assert '+791: All tests passed!' in (R/'flutter-test.log').read_text();assert '+27: All tests passed!' in (R/'summary-tests.log').read_text();assert 'No issues found!' in (R/'summary-analyze.log').read_text()
b=read('build-1/result.json');assert b['source']==m['source'] and b['complete'] and len(b['steps'])==13
for s in b['steps']:assert s['exit_code']==0 and hashlib.sha256((R/'build-1'/(s['name']+'.log')).read_bytes()).hexdigest()==s['log_sha256']
for k in ['forward','rollback']:assert b[k]['version_code']==22 and b[k]['certificate_sha256']=='f5abd3bd11d94b3aaee66ab65e6a666a228a4d64edf4b86de9327ae9b8a59161'
seed=read('seed.json');video27={v['id'] for v in seed['videos'] if v['name'].startswith('Scope ')};video14={v['id'] for v in seed['videos'] if '/Landscape/Child/' in v['path']};pack27={p['id'] for p in seed['packs'] if p['name'].startswith('Scope ')};assert len(video27)==len(pack27)==27 and len(video14)==14
for kind,ids in [('video',video27),('pack',pack27)]:
 v=read('selection-responses.json')[kind];assert v['app_request']['method']=='GET' and v['app_request']['status']==200 and parse_qs(v['app_request']['query'])['search']==['Scope'];assert set(v['readback']['ids'])==ids and v['readback']['kind']==kind and v['readback']['total']==27
first=read('video-27-first24-round.json')['round']['created_at']
reads=[json.loads(x) for x in (R/'normal/trace/requests.jsonl').read_text().splitlines()]
initial=[x for x in reads if x['time']<first and x['path']=='/api/v1/videos' and parse_qs(x.get('query','')).get('search')==['Scope']]
assert initial and all(parse_qs(x['query']).get('offset')==['0'] and parse_qs(x['query']).get('limit')==['24'] for x in initial)
names=[('video-27-first24',video27)]+[(f'video-combo-{i}-preview',video14) for i in range(1,4)]+[('summary22-preview14',video14)]
for name,ids in names:
 v=read(name+'-round.json');r=v['round'];assert r['membership']=='fixed' and r['source']=='library' and r['candidate_count']==len(ids);assert {e['video_id'] for e in v['entries']}==ids and [e['ordinal'] for e in v['entries']]==list(range(len(ids)));q=json.loads(r['scope']);assert q['search']=='Scope'
 if ids==video14:assert q['directory_id']==read('landscape-directory.json')['id'] and q['orientation']=='landscape' and q['duration']=='short' and q['file_type']=='MP4' and q['tag_ids']==[seed['tags']['video']['Intersection']]
def labels(context):
 p=next((R/'normal/screens').glob('*-'+context+'.xml'));return list(ET.parse(p).iter('node'))
def text(context):return '\n'.join((n.get('content-desc','')+'\n'+n.get('text','')) for n in labels(context))
for i in range(1,4):
 v=read(f'video-combo-{i}-long-empty.json');assert v['response']['total']==0 and v['response']['items']==[]
 for suffix,count in [('cancel-preserves',14),('long-empty',0),('mov-empty',0),('restored',27)]:assert f'{count} 个视频' in text(f'video-combo-{i}-{suffix}')
 for suffix,count in [('unread26',26),('reading1',1),('completed0',0),('directory1',1),('search-empty',0),('reset27',27)]:assert f'{count} 个图包' in text(f'pack-combo-{i}-{suffix}')
 assert any(n.get('content-desc')=='预览此范围' and n.get('enabled')=='false' for n in labels(f'video-combo-{i}-long-empty'))
 assert any(n.get('content-desc')=='快速整理' and n.get('enabled')=='false' for n in labels(f'pack-combo-{i}-search-empty'))
assert '已选 1' in text('video-selection-independent-after') and '已选 27' in text('pack-selection-independent-after')
a,z=read('normal/before-video-flow-all-catalog.json'),read('normal/all-flows-after-all-catalog.json')
for k in ['pack_tag_definitions','pack_tag_links','tags','video_tags','packs','pack_pages','roots','videos']:assert a['tables'][k]==z['tables'][k]
assert a['opaque_table_digests']['access_tokens']==z['opaque_table_digests']['access_tokens'];assert read('normal/pack-reading-established-all-catalog.json')['tables']['pack_progress']==z['tables']['pack_progress']
assert '横版 · 10 秒以上 · MOV' in text('summary22-properties-empty');assert all(v in text('summary22-combined14') for v in ['横版','10 秒以内','MP4','Intersection','Scope'])
for name,kind in [('upgrade22','forward'),('rollback22','rollback'),('return22','forward')]:
 a,z=[read('normal/'+name+'-'+x+'-all-catalog.json') for x in ['before','after']];assert len(a['tables'])==35
 for k in ['tables','opaque_table_digests','setting_key_sha256']:assert a[k]==z[k]
 assert read('normal/'+name+'-before-preferences.json')==read('normal/'+name+'-after-preferences.json');v=read('normal/'+name+'-install.json');assert '-r' in v['command'] and v['sha256']==b[kind]['sha256'] and v['no_uninstall_or_clear']
 for k in ['firstInstallTime','dataDir','appId']:assert v['before'][k]==v['after'][k]
 assert read('normal/'+name+'-actual-apk.json')['sha256']==b[kind]['sha256']
c=read('cleanup.json');assert c['restored_device_settings']==read('original-settings.json') and c['exact_initial_uid_restored'] and c['original_containers_before']==c['original_containers_after'];assert read('integrity-final.json')['source_media_files']==215
assert read('summary-source.json')['changed_production_files']==['apps/mobile/lib/features/library/video_catalog_page.dart']
print(json.dumps({'verified_files':len(files),'behavior_code':21,'video_rounds':3,'pack_rounds':3,'summary_and_signed_cover_code':22,'cover_installs':3,'whole_acceptance_ids_passed':0}))

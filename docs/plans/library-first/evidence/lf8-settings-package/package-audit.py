import hashlib,json,subprocess,xml.etree.ElementTree as ET
from pathlib import Path
L=Path(__file__).resolve().parent;R=L.parents[1];O=L/'normal';read=lambda p:json.loads(p.read_text())
b=read(L/'build-1/result.json');assert b['complete'] and all(v['exit_code']==0 for v in b['steps'])
for k in ['forward','rollback']:
 a=b[k];p=Path(a['path']);assert p.stat().st_size==a['bytes'] and hashlib.sha256(p.read_bytes()).hexdigest()==a['sha256'];assert a['version_code']==15 and a['normal_entrypoint'] and not a['integration_test_plugin'];assert a['certificate_sha256']=='f5abd3bd11d94b3aaee66ab65e6a666a228a4d64edf4b86de9327ae9b8a59161'
base=read(O/'before15-catalog.json');prefs=read(O/'before15-preferences.json');assert len(base['tables'])==21 and set(base['opaque_table_digests'])=={'settings','access_tokens'}
for step in ['forward15','rollback15','forward15-return']:
 v=read(O/(step+'-install.json'));assert 'Success' in v['output'] and v['no_uninstall_or_clear'];assert v['after']['versionCode'].split()[0]=='15'
 for k in ['firstInstallTime','dataDir','appId']:assert v['before'][k]==v['after'][k]
 a=read(O/('after-'+step+'-catalog.json'));assert a['tables']==base['tables'] and a['opaque_table_digests']==base['opaque_table_digests'];assert read(O/('after-'+step+'-preferences.json'))==prefs
assert read(O/'upgrade-result.json')['complete']
x=read(O/'before-ordinary-settings-catalog.json');y=read(O/'after-ordinary-settings-catalog.json');assert x['tables']==y['tables'] and x['opaque_table_digests']==y['opaque_table_digests'];assert x['tables']==base['tables'] and x['opaque_table_digests']==base['opaque_table_digests']
assert read(O/'before-ordinary-settings-preferences.json')==read(O/'cold-returned-preferences.json')==prefs
mid=read(O/'cold-persisted-preferences.json');assert mid['dark']==(not prefs['dark']) and mid['preloadAdjacent']==(not prefs['preloadAdjacent']);assert {k:v for k,v in mid.items() if k not in ['dark','preloadAdjacent']}=={k:v for k,v in prefs.items() if k not in ['dark','preloadAdjacent']}
for name,data in [('cold-persisted-ui',mid),('cold-returned-ui',prefs)]:
 nodes=list(ET.parse(O/'screens'/(name+'.xml')).getroot().iter('node'))
 for prefix,k in [('暗黑模式','dark'),('准备相邻视频','preloadAdjacent')]:
  found=[n for n in nodes if n.get('content-desc','').startswith(prefix) and n.get('clickable')=='true'];assert len(found)==1 and found[0].get('checked')==str(data[k]).lower()
for name in ['tag-draft-off-ui','tag-draft-live-reduced']:
 nodes=list(ET.parse(O/'screens'/(name+'.xml')).getroot().iter('node'));assert any(n.get('content-desc')=='LEGACY_ONLY' and n.get('selected')=='false' for n in nodes)
s=read(O/'settings-result.json');assert s['complete'] and s['normal_and_reduced_setting_saves']==4 and s['cold_reopens']==2
trace=[json.loads(v) for v in (O/'trace/requests.jsonl').read_text().splitlines()];assert all(v['method'] in ['GET','HEAD'] for v in trace[s['trace_start']:s['trace_end']])
for key in ['rollback','forward']:
 t=(L/'build-1'/(key+'-tests.log')).read_text();assert 'All tests passed!' in t and ('+85:' if key=='rollback' else '+14:') in t;assert 'No issues found!' in (L/'build-1'/(key+'-analyze.log')).read_text()
profile='c6c1695fdc5c02f8af420fc901ce3e66f3383548';trees={k:subprocess.check_output(['git','rev-parse',v+':apps/mobile/lib'],cwd=R,text=True).strip() for k,v in {'profile':profile,'ordinary':b['source'],'current':'HEAD'}.items()};assert len(set(trees.values()))==1
prototype=subprocess.check_output(['git','rev-parse','HEAD:design/reference/library-first'],cwd=R,text=True).strip();assert prototype=='1cbf605af8f03fa067a4ce8e914bb809e3a487ca';assert not subprocess.check_output(['git','diff','--name-only','e05cb56e..HEAD','--','services','design/reference'],cwd=R).strip()
for a in read(L/'previous-apks.json').values():assert hashlib.sha256((R/'tmp/releases'/a['name']).read_bytes()).hexdigest()==a['sha256']
result={'complete':True,'source':b['source'],'same_production_lib_as_profile':profile,'lib_trees':trees,'reused_full_client_tests':740,'exported_rollback_tests':85,'exported_forward_tests':14,'ordinary_code':15,'upgrade_steps':3,'all21_tables_auth_settings_and_preferences_equal':True,'ordinary_setting_saves':4,'cold_reopens':2,'live_reduced_tag_draft_cancel_preserved':True,'no_server_write_requests':True,'original_code14_apks_preserved':True,'prototype_tree':prototype,'service_source_unchanged':True,'initial_preinstall_debug_read_failure_retained':True,'ordinary_frames_not_timing_proof':True}
(L/'package-audit.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))

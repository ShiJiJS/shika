import hashlib,json,subprocess,zipfile
from pathlib import Path
L=Path(__file__).resolve().parent;R=L.parents[1];O=L/'normal';read=lambda p:json.loads(p.read_text())
b=read(L/'build-1/result.json');assert b['complete'] and all(x['exit_code']==0 for x in b['steps'])
for x in b['steps']:assert hashlib.sha256((L/'build-1'/(x['name']+'.log')).read_bytes()).hexdigest()==x['log_sha256']
for k in ['forward','rollback']:
 a=b[k];p=Path(a['path']);assert p.stat().st_size==a['bytes'] and hashlib.sha256(p.read_bytes()).hexdigest()==a['sha256'];assert a['version_code']==16 and a['normal_entrypoint'] and not a['integration_test_plugin'];assert a['flutter_engine_abis']==['arm64-v8a'];assert a['certificate_sha256']=='f5abd3bd11d94b3aaee66ab65e6a666a228a4d64edf4b86de9327ae9b8a59161'
 with zipfile.ZipFile(p) as z:assert not any('design/reference' in n or 'library-first/app.html' in n or 'integration_test' in n for n in z.namelist())
base=read(O/'before16-catalog.json');prefs=read(O/'before16-preferences.json');assert len(base['tables'])==21
for step in ['forward16','rollback16','forward16-return']:
 a=read(O/(step+'-install.json'));assert 'Success' in a['output'] and a['no_uninstall_or_clear'];assert a['after']['versionCode'].split()[0]=='16'
 for k in ['firstInstallTime','dataDir','appId']:assert a['before'][k]==a['after'][k]
 now=read(O/('after-'+step+'-catalog.json'));assert now['tables']==base['tables'] and now['opaque_table_digests']==base['opaque_table_digests'];assert read(O/('after-'+step+'-preferences.json'))==prefs
assert read(O/'upgrade-result.json')['complete']
for k,count in [('rollback',85),('forward',14)]:
 log=(L/'build-1'/(k+'-tests.log')).read_text();assert 'All tests passed!' in log and f'+{count}:' in log;assert 'No issues found!' in (L/'build-1'/(k+'-analyze.log')).read_text()
assert '+766: All tests passed!' in (L/'client-tests.log').read_text();assert 'No issues found!' in (L/'analyze-final.log').read_text();assert '+1: All tests passed!' in (L/'pending-reader-test-3.log').read_text()
trees={k:subprocess.check_output(['git','rev-parse',v+':apps/mobile/lib'],cwd=R,text=True).strip() for k,v in {'built':b['source'],'dropdown_source':'2f9792a4','native_source':'6f4f5e00','current':'HEAD'}.items()};assert set(trees.values())=={'3fa6e5011c2cfeaef29fc1b03a68411d5565e50c'}
prototype=subprocess.check_output(['git','rev-parse','HEAD:design/reference/library-first'],cwd=R,text=True).strip();assert prototype=='1cbf605af8f03fa067a4ce8e914bb809e3a487ca';assert not subprocess.check_output(['git','diff','--name-only',b['source']+'..HEAD','--','services','design/reference'],cwd=R).strip()
for n,a in read(L/'previous-apks.json').items():assert hashlib.sha256((R/'tmp/releases'/n).read_bytes()).hexdigest()==a['sha256']
for name in ['business-audit','history-audit']:assert read(L/(name+'.json'))['complete']
result={'complete':True,'source':b['source'],'lib_trees':trees,'full_client_tests':766,'exported_old_ui_tests':85,'exported_forward_related_tests':14,'actual_reader_pending_save_test':True,'build_log_hashes_verified':True,'ordinary_release_code':16,'upgrade_steps':3,'upgrade_all21_auth_settings_and_preferences_equal':True,'signature_original_windows':True,'normal_main_no_integration_or_prototype':True,'old14_15_apks_preserved':True,'business_data_audit':True,'historical_readonly_audit':True,'prototype_tree':prototype,'services_unchanged':True,'not_phone_nas_audio_or_complete_acceptance':True}
(L/'package-audit.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))

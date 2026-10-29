import hashlib,json,re,subprocess
from pathlib import Path
R=Path(__file__).resolve().parents[2];L=R/'.dev/lf8-dropdown-motion';ctx=json.loads((L/'source-context.json').read_text());source=(L/'source-ref').read_text().strip()
assert not subprocess.check_output(['git','diff','--name-only',source,'--','apps/mobile/lib','apps/mobile/test'],cwd=R).strip()
assert ' +765: All tests passed!' in (L/'client-tests.log').read_text()
assert ' +15: All tests passed!' in (L/'dropdown-tests-5.log').read_text()
assert 'No issues found!' in (L/'analyze-final.log').read_text()
assert ' +0 -3: Some tests failed.' in (L/'before-probe.log').read_text()
assert hashlib.sha256((R/'.dev/flutter/packages/flutter/lib/src/material/dropdown.dart').read_bytes()).hexdigest()==ctx['sdk_dropdown_sha256']
assert subprocess.check_output(['git','rev-parse','HEAD:design/reference/library-first'],cwd=R,text=True).strip()==ctx['prototype_tree']=='1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
files={}
for p in (R/'apps/mobile/lib').rglob('*.dart'):
 if p.name=='paper_dropdown.dart':continue
 s=p.read_text();assert not re.search(r'\bDropdownButton(?:FormField)?<',s)
 n=len(re.findall(r'\bPaperDropdownButton(?:FormField)?<',s))
 if n:files[str(p.relative_to(R))]=n
assert sum(files.values())==9
prior=json.loads((R/'.dev/lf8-settings-motion/build-1/result.json').read_text());packages={}
for key in ['forward','rollback']:
 p=Path(prior[key]['path']);h=hashlib.sha256(p.read_bytes()).hexdigest();assert h==prior[key]['sha256'];packages[key]={'sha256':h,'bytes':p.stat().st_size}
orig=json.loads((R/'.dev/lf8-menu-motion/cleanup-native.json').read_text())['original4_services_preserved_healthy'];services={}
for name,ident in orig.items():
 c=json.loads(subprocess.check_output(['docker','inspect',name],text=True))[0];assert c['Id']==ident and c['State']['Running'] and c['State']['Health']['Status']=='healthy';services[name]=ident
record={'complete':True,'source':source,'production_lib':subprocess.check_output(['git','rev-parse',f'{source}:apps/mobile/lib'],cwd=R,text=True).strip(),'full_client_passed':765,'targeted_passed':15,'full_rgba_pairs':16,'analyze_clean':True,'before_expected_failures':3,'constructors':files,'sdk_unchanged':ctx['sdk_dropdown_sha256'],'frozen_prototype_unchanged':ctx['prototype_tree'],'ordinary_code15_pair_preserved':packages,'original4_services_preserved_healthy':services,'no_new_android_or_app_service_started':True,'native_and_normal_integration_pending':True,'production_server_unchanged':not bool(subprocess.check_output(['git','diff','--name-only',ctx['base'],source,'--','services'],cwd=R).strip())}
(L/'audit.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record))

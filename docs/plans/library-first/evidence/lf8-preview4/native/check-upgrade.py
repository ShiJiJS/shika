import json,time
from pathlib import Path
import driver,snapshot
O=Path(__file__).resolve().parent
manifest=json.loads((O.parent/'build-1/result.json').read_text());assert manifest['complete']
base=snapshot.snapshot('before-forward10');prefs=driver.appearance('before-forward10')
checks=[]
for name,kind in [('forward10-first','forward'),('rollback10','rollback'),('forward10-return','forward')]:
 driver.install(name,kind)
 after=snapshot.snapshot('after-'+name);actual=driver.appearance('after-'+name)
 assert base['tables']==after['tables'],[k for k in base['tables'] if base['tables'][k]!=after['tables'][k]]
 assert base['opaque_table_digests']==after['opaque_table_digests']
 assert prefs==actual,(prefs,actual)
 checks.append({'step':name,'all21_tables_equal':True,'settings_and_auth_digests_equal':True,'appearance_equal':True,'version':manifest[kind]['version'],'sha256':manifest[kind]['sha256']})
 driver.save('upgrade-result.json',{'checks':checks,'complete':len(checks)==3,'no_uninstall_or_clear':True,'time':time.time()})
 print(json.dumps(checks[-1]),flush=True)

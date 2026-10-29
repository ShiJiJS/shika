import driver,snapshot,snapshot_all,json
from pathlib import Path
O=Path(__file__).resolve().parent
state=driver.package_state('baseline16');assert state['versionCode'].split()[0]=='16'
driver.cold('baseline16','new');base=snapshot.snapshot('before17');allbase=snapshot_all.snapshot('normal','before17');prefs=driver.appearance('before17');checks=[]
for name,kind in [('forward17','forward'),('rollback17','rollback'),('forward17-return','forward')]:
 driver.install(name,kind);after=snapshot.snapshot('after-'+name);allafter=snapshot_all.snapshot('normal','after-'+name)
 assert base['tables']==after['tables'] and base['opaque_table_digests']==after['opaque_table_digests']
 assert allbase['tables']==allafter['tables'] and allbase['opaque_table_digests']==allafter['opaque_table_digests']
 assert prefs==driver.appearance('after-'+name)
 checks.append({'step':name,'all35_tables_auth_settings_and_appearance_equal':True})
 driver.save('upgrade-result.json',{'complete':len(checks)==3,'checks':checks});print(name,'passed',flush=True)

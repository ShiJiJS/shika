import driver,snapshot,json
from pathlib import Path
O=Path(__file__).resolve().parent
print(driver.package_state('baseline12'),flush=True)
assert driver.package_state('baseline12')['versionCode'].split()[0]=='12'
driver.cold('baseline12','new');base=snapshot.snapshot('before13');prefs=driver.appearance('before13')
original={k:driver.device('shell',*args).decode().strip() for k,args in {'size':['wm','size'],'density':['wm','density'],'window':['settings','get','global','window_animation_scale'],'transition':['settings','get','global','transition_animation_scale'],'animator':['settings','get','global','animator_duration_scale'],'font':['settings','get','system','font_scale'],'rotation':['settings','get','system','user_rotation'],'accel':['settings','get','system','accelerometer_rotation'],'immersive':['settings','get','secure','immersive_mode_confirmations']}.items()};driver.save('original-settings.json',original)
checks=[]
for name,kind in [('forward13','forward'),('rollback13','rollback'),('forward13-return','forward')]:
 driver.install(name,kind);after=snapshot.snapshot('after-'+name);assert base['tables']==after['tables'];assert base['opaque_table_digests']==after['opaque_table_digests'];assert prefs==driver.appearance('after-'+name)
 checks.append({'step':name,'all21_tables_auth_settings_and_appearance_equal':True})
 driver.save('upgrade-result.json',{'complete':len(checks)==3,'checks':checks})
 print(name,'passed',flush=True)

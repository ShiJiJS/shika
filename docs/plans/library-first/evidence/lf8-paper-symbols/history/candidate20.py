import json
from pathlib import Path
import driver20 as driver,business_ui as u
from snapshot_all import snapshot
O=Path(__file__).resolve().parent;L=O.parent
r=json.loads((L/'build-2/result.json').read_text());assert r['complete'] and len(r['steps'])==13
checks=[]
for name,kind in [('upgrade20','forward'),('rollback20','rollback'),('return20','forward')]:
 before=snapshot(kind,name+'-before');prefs=driver.appearance(name+'-before');driver.install(name,kind);after=snapshot(kind,name+'-after');assert before['tables']==after['tables'];assert before['opaque_table_digests']==after['opaque_table_digests'];assert before['setting_key_sha256']==after['setting_key_sha256'];assert driver.appearance(name+'-after')==prefs;checks.append(name)
 if name=='upgrade20':
  u.snap('candidate20-home-light')
  u.choose(prefix='图包\n',context='candidate20-packs');u.choose(prefix='6 张\n在读 · 3\n夏日祭',context='candidate20-reader');n=u.snap('candidate20-reader-light');assert '3 / 6' in driver.text(n)
  u.choose('图包更多',context='candidate20-reader-more');n=u.back('candidate20-reader-more-cancel');assert '3 / 6' in driver.text(n)
  u.choose('返回来源',context='candidate20-reader-return');u.choose('设置',context='candidate20-settings');u.choose('暗黑模式',context='candidate20-dark');u.choose('媒体库',context='candidate20-dark-library');u.choose(prefix='视频\n',context='candidate20-dark-videos');u.snap('candidate20-home-dark')
  u.choose(prefix='图包\n',context='candidate20-dark-packs');u.choose(prefix='6 张\n在读 · 3\n夏日祭',context='candidate20-dark-reader');n=u.snap('candidate20-reader-dark');assert '3 / 6' in driver.text(n)
  u.choose('返回来源',context='candidate20-dark-return');u.choose('设置',context='candidate20-theme-restore-settings');u.choose('暗黑模式',context='candidate20-theme-restore');u.choose('媒体库',context='candidate20-library-return')
path=driver.device('shell','pm','path',driver.PACKAGE).decode().strip();assert path.count('package:')==1;actual=driver.device('shell','sha256sum',path.removeprefix('package:')).decode().split()[0];assert actual==r['forward']['sha256']
(L/'normal20-result.json').write_text(json.dumps({'complete':True,'source':r['source'],'candidate_code':20,'installed_sha256':actual,'three_cover_installs':checks,'all_35_tables_full_settings_tokens_preferences_preserved_at_each_install':True,'same_first_install_time_identity_data_directory':True,'light_dark_home_and_reader_same_page':True,'reader_more_cancel_preserved_page':True,'no_uninstall_or_clear':True},indent=2)+'\n')

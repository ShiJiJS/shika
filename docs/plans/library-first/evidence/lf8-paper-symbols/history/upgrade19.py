import json
from pathlib import Path
import driver,business_ui as u
from snapshot_all import snapshot
O=Path(__file__).resolve().parent;L=O.parent
r=json.loads((L/'build-1/result.json').read_text());assert r['complete'] and len(r['steps'])==13
before=snapshot('new','upgrade19-before');prefs=driver.appearance('upgrade19-before');driver.install('upgrade19-forward','forward');after=snapshot('new','upgrade19-after');assert before['tables']==after['tables'];assert before['opaque_table_digests']==after['opaque_table_digests'];assert before['setting_key_sha256']==after['setting_key_sha256'];assert driver.appearance('upgrade19-after')==prefs
u.snap('candidate19-home-light')
u.choose('更多',context='candidate19-home-more');u.back('candidate19-home-more-cancel')
u.choose(prefix='图包\n',context='candidate19-pack-library')
u.choose(prefix='6 张\n夏日祭',context='candidate19-summer-open');n=u.snap('candidate19-reader-light');assert '3 / 6' in driver.text(n)
u.choose('阅读设置',context='candidate19-reader-settings');u.choose('关闭面板',context='candidate19-reader-settings-cancel')
u.choose('总览',context='candidate19-overview');u.back('candidate19-overview-cancel')
u.choose('沉浸',context='candidate19-immersive');n=u.back('candidate19-immersive-exit');assert '3 / 6' in driver.text(n) and '返回来源' in driver.text(n)
u.choose('返回来源',context='candidate19-reader-return')
u.choose('标签',context='candidate19-tags');u.snap('candidate19-tags-light')
u.choose('最近',context='candidate19-recent');u.snap('candidate19-recent-light')
u.choose('设置',context='candidate19-settings');u.snap('candidate19-settings-light')
u.choose('暗黑模式',context='candidate19-dark-theme')
u.choose('媒体库',context='candidate19-dark-home');u.snap('candidate19-home-dark')
u.choose(prefix='图包\n',context='candidate19-dark-packs');u.choose(prefix='6 张\n夏日祭',context='candidate19-dark-reader');n=u.snap('candidate19-reader-dark');assert '3 / 6' in driver.text(n)
u.choose('返回来源',context='candidate19-dark-reader-return');u.choose('设置',context='candidate19-light-restore-settings');u.choose('暗黑模式',context='candidate19-light-restore');u.choose('媒体库',context='candidate19-light-home')
rounds=[]
for name,kind in [('rollback19','rollback'),('return19','forward')]:
 before=snapshot('new',name+'-before');prefs=driver.appearance(name+'-before');driver.install(name,kind);after=snapshot('new',name+'-after');assert before['tables']==after['tables'];assert before['opaque_table_digests']==after['opaque_table_digests'];assert before['setting_key_sha256']==after['setting_key_sha256'];assert driver.appearance(name+'-after')==prefs;rounds.append(name)
(L/'normal-result.json').write_text(json.dumps({'complete':True,'candidate_code':19,'upgrade_no_table_token_or_preference_loss':True,'rollback_then_forward_preserved_tables_tokens_preferences':rounds,'overview_settings_more_cancel_and_immersive_exit':True,'actual_light_and_dark_screens':True},indent=2)+'\n')

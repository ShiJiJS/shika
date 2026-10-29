import business_ui as u,driver,json
from pathlib import Path
L=u.O.parent
for key in ['window_animation_scale','transition_animation_scale','animator_duration_scale']:
 u.device('shell','settings','put','global',key,'1');assert u.device('shell','settings','get','global',key).decode().strip()=='1';u.record({'action':'system-animation-scale','key':key,'value':'1'})
u.choose('设置',context='entering-settings');u.choose(prefix='服务连接',context='legacy-connection-open')
from ui_driver import fill
fill(1,'8774','legacy-fixture-port');fill(2,(L/'legacy/config/passphrase').read_text().strip(),'legacy-fixture-password');n=u.choose('连接并保存',context='legacy-connect')
i=u.matches(n,prefix='正在播放，');assert len(i)==1,driver.text(n);label=i[0].get('content-desc');u.tap(i[0],'pause observed old homepage '+label);n=u.snap('legacy-paused-home');assert '已暂停，' in driver.text(n);u.check('normal16-original-service-home',{'observed_running_label':label,'pause_by_surface':True,'original_service_no_capabilities':True,'normal_system_animation':True})

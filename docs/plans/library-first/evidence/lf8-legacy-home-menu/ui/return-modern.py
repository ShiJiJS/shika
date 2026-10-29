import sys,json
import business_ui as u,driver
from ui_driver import fill
sys.path.insert(0,str(u.O.parent));from snapshot import snapshot
u.choose('设置',context='legacy-finish-settings');u.choose(prefix='服务连接',context='modern-connection-open');fill(1,'8772','modern-fixture-port');fill(2,(u.O.parent/'modern/config/passphrase').read_text().strip(),'modern-fixture-password');n=u.choose('连接并保存',context='modern-connection-restore');assert '媒体库' in driver.text(n) and '2 个视频' in driver.text(n);driver.package_state('returned-modern');driver.appearance('returned-modern');u.check('modern-workspace-return',{'videos':2,'packs':1,'normal_library_entry':True,'no_automatic_preview':True});snapshot('modern','after-return')

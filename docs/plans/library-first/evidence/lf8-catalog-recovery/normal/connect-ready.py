import json,time
from pathlib import Path
import business_ui as u,driver
from ui_driver import device
O=Path(__file__).resolve().parent;L=O.parent
u.choose('连接',context='connection-retry-after-fixture-fix');end=time.monotonic()+40
while True:
 n=u.snap('connection-ready-wait')
 if '媒体库' in driver.text(n):break
 assert time.monotonic()<end,'connection did not become ready';time.sleep(.2)
for k,v in [('size','1170x2715'),('density','480')]:device('shell','wm',k,v)
p=driver.package_state('entering-code22');old=json.loads((L.parents[0]/'lf8-current-filters/normal/return22-after-package.json').read_text())
for k in ['firstInstallTime','appId','dataDir']:assert p[k]==old[k]
n=u.snap('normal22-connected-ready');(L/'connection-ready-result.json').write_text(json.dumps({'connected_through_proxy':True,'version_code':22,'package_identity_preserved_after_reinstall':True,'reinstall_not_a_new_upgrade_cycle':True},indent=2)+'\n')

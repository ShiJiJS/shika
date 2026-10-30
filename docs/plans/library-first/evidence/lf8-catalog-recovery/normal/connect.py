import json,time
from pathlib import Path
import business_ui as u,driver
from ui_driver import device,fill
O=Path(__file__).resolve().parent
device('shell','am','force-stop',driver.PACKAGE);device('shell','am','start','-n',driver.PACKAGE+'/.MainActivity')
end=time.monotonic()+35
while True:
 n=u.snap('connection-form')
 if any(x.get('class')=='android.widget.EditText' for x in n):break
 assert time.monotonic()<end;time.sleep(.2)
fill(0,'http://10.0.2.2:8778','fixture-address');fill(2,(O/'config/passphrase').read_text().strip(),'fixture-password')
n=u.choose('连接',context='fixture-login');u.expect_text(n,'媒体库')
for key,value in [('size','1170x2715'),('density','480')]:device('shell','wm',key,value)
prefs=driver.appearance('entering')
if prefs.get('dark',False):
 u.choose('设置',context='light-settings');u.choose('暗黑模式',context='light-theme');u.choose('媒体库',context='library-return')
u.snap('code22-home-connected');driver.package_state('entering-code22')

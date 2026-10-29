import json,time,subprocess
from pathlib import Path
import driver,snapshot
O=Path(__file__).resolve().parent
checks=[]
def require(name,*labels):
 n=driver.capture(name);s=driver.text(n)
 for label in labels:assert label in s,(name,label,s)
 checks.append({'state':name,'required':labels});print(json.dumps(checks[-1],ensure_ascii=False),flush=True)
 return n
require('candidate-library','媒体库','flower-landscape','视频')
driver.tap_label('candidate-pack-tab',prefix='图包\n')
require('candidate-packs','继续阅读','Upgrade Pack')
driver.tap_label('candidate-continue',prefix='继续阅读\n')
require('candidate-reader-vertical','2 / 3','纵向拼接')
driver.tap_label('candidate-mode',label='纵向拼接')
driver.snap('candidate-mode-panel')
driver.save('path-progress.json',{'checks':checks,'stage':'inspect-mode-panel'})

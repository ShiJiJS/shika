import driver,json,time
from pathlib import Path
O=Path(__file__).resolve().parent
checks=json.loads((O/'path-progress.json').read_text())['checks']
def require(name,*labels):
 n=driver.capture(name);s=driver.text(n)
 for label in labels:assert label in s,(name,label,s)
 checks.append({'state':name,'required':labels});print(json.dumps(checks[-1],ensure_ascii=False),flush=True);return n
driver.tap_label('candidate-select-horizontal',label='横向翻页');driver.tap_label('candidate-resume-horizontal',label='继续阅读');require('candidate-reader-horizontal','2 / 3','横向翻页')
driver.tap_label('candidate-next',label='下一张');require('candidate-reader-page3','3 / 3')
driver.tap_label('candidate-previous',label='上一张');require('candidate-reader-page2','2 / 3')
driver.tap_label('candidate-horizontal-mode',label='横向翻页');driver.tap_label('candidate-select-vertical',label='纵向拼接');driver.tap_label('candidate-resume-vertical',label='继续阅读');require('candidate-reader-vertical-again','2 / 3','纵向拼接')
# Exercise the integrated route after a live Android animation preference change.
for k in ['window_animation_scale','transition_animation_scale','animator_duration_scale']:driver.device('shell','settings','put','global',k,'0')
driver.device('shell','input','keyevent','4');require('candidate-reader-return','继续阅读','Upgrade Pack','媒体库')
driver.tap_label('candidate-reopen',prefix='继续阅读\n');require('candidate-reader-resumed','2 / 3','纵向拼接');driver.device('shell','input','keyevent','4');require('candidate-reader-return2','媒体库','继续阅读')
for k in ['window_animation_scale','transition_animation_scale','animator_duration_scale']:driver.device('shell','settings','put','global',k,'1')
driver.tap_label('candidate-tags',label='标签');driver.tap_label('candidate-video-tags',label='视频');n=require('candidate-video-tags-shown','LEGACY_ONLY');assert 'PACK_ONLY' not in driver.text(n)
driver.tap_label('candidate-pack-tags',label='图包');n=require('candidate-pack-tags-shown','PACK_ONLY');assert 'LEGACY_ONLY' not in driver.text(n)
driver.tap_label('candidate-settings',label='设置');require('candidate-settings-shown','服务连接','操作任务');p=driver.appearance('candidate-after-reader');assert p['dark'] and not p['preloadAdjacent']
driver.tap_label('candidate-library-again',label='媒体库');driver.tap_label('candidate-video-tab',prefix='视频\n');require('candidate-videos','flower-landscape','预览此范围');driver.tap_label('candidate-preview',label='预览此范围');driver.snap('candidate-preview-controls')
driver.save('path-progress.json',{'checks':checks,'stage':'inspect-preview'})

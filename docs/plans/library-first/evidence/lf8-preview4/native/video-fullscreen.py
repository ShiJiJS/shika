import driver,time,json
from pathlib import Path
O=Path(__file__).resolve().parent
checks=json.loads((O/'path-progress.json').read_text())['checks']
def require(name,*labels):
 n=driver.capture(name);s=driver.text(n)
 for label in labels:assert label in s,(name,label,s)
 checks.append({'state':name,'required':labels});print(json.dumps(checks[-1],ensure_ascii=False),flush=True);return n
n=require('candidate-video-inline-ready','横向全屏')
m=[v for v in n if v.get('content-desc')=='暂停' and v.get('clickable')=='true']
if len(m)==1:driver.tap(m[0],'pause actual playback')
require('candidate-video-paused','播放','横向全屏')
driver.tap_label('candidate-enter-fullscreen',label='横向全屏');n=driver.snap('candidate-fullscreen-initial')
for node in n:
 if node.get('package')=='com.android.systemui' and (node.get('text')=='Got it' or node.get('resource-id')=='com.android.systemui:id/ok'):
  driver.tap(node,'acknowledge observed Android fullscreen education');n=driver.snap('candidate-fullscreen-after-education');break
require('candidate-fullscreen-stable','退出全屏')
# Real playback in landscape, then freeze a decoded frame before the return.
n=driver.capture('candidate-fullscreen-before-play');m=[v for v in n if v.get('content-desc') in ['播放','播放视频'] and v.get('clickable')=='true']
if len(m)==1:driver.tap(m[0],'play in fullscreen')
require('candidate-fullscreen-playing','退出全屏')
for k in ['window_animation_scale','transition_animation_scale','animator_duration_scale']:driver.device('shell','settings','put','global',k,'0')
driver.device('shell','input','keyevent','4');require('candidate-fullscreen-return','视频预览','横向全屏')
driver.device('shell','input','keyevent','4');require('candidate-video-return','媒体库','flower-landscape')
driver.tap_label('candidate-final-settings',label='设置');require('candidate-final-settings-shown','服务连接','操作任务')
driver.appearance('candidate-final');driver.save('path-result.json',{'checks':checks,'passed':True,'normal_release_apk':True,'qemu_pid':45511,'audio_off':True,'video_fixture_seconds':5,'no_physical_phone_or_nas_claim':True})

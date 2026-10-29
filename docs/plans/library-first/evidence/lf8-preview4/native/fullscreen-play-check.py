import driver,json,time
from pathlib import Path
O=Path(__file__).resolve().parent
driver.tap_label('verify-video-library',label='媒体库');driver.tap_label('verify-video-preview',label='预览此范围');driver.tap_label('verify-fullscreen-entry',label='横向全屏')
n=driver.capture('verify-fullscreen-controls')
play=[v for v in n if v.get('content-desc')=='播放视频' and v.get('clickable')=='true']
if len(play)==1:driver.tap(play[0],'explicit actual fullscreen play')
else:
 play=[v for v in n if v.get('content-desc')=='播放' and v.get('clickable')=='true'];assert len(play)==1;driver.tap(play[0],'explicit actual fullscreen play')
n=driver.capture('verify-fullscreen-actual-playing');labels=[v.get('content-desc','') for v in n];assert any(s.startswith('正在播放，') for s in labels),labels
print(json.dumps({'actual_fullscreen_playing_semantics':[s for s in labels if s.startswith('正在播放，')]}),flush=True)
driver.device('shell','input','keyevent','4');driver.snap('verify-fullscreen-back');driver.device('shell','input','keyevent','4');driver.snap('verify-video-back');driver.tap_label('verify-end-settings',label='设置')
v=json.loads((O/'path-result.json').read_text());v['fullscreen_explicit_play_verified']=True;v['earlier_playing_capture_name_not_a_playback_assertion']=True;driver.save('path-result.json',v)

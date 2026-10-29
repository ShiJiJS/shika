import driver,json,hashlib
from pathlib import Path
O=Path(__file__).resolve().parent
n=driver.capture('verify-fullscreen-actual-playing');labels=[v.get('content-desc','') for v in n];assert any(s.startswith('正在播放，') for s in labels),labels
n2=driver.capture('verify-fullscreen-actual-playing-frame2');labels2=[v.get('content-desc','') for v in n2];assert any(s.startswith('正在播放，') for s in labels2),labels2
assert (O/'screens/verify-fullscreen-actual-playing.png').read_bytes()!=(O/'screens/verify-fullscreen-actual-playing-frame2.png').read_bytes()
print(json.dumps({'actual_fullscreen_playing':True,'consecutive_decoded_images_differ':True}),flush=True)
driver.device('shell','input','keyevent','4');driver.snap('verify-fullscreen-back');driver.device('shell','input','keyevent','4');driver.snap('verify-video-back');driver.tap_label('verify-end-settings',label='设置')
v=json.loads((O/'path-result.json').read_text());v['fullscreen_active_playback_verified']=True;v['earlier_playing_capture_name_not_a_playback_assertion']=True;v['extra_play_helper_failed_because_already_playing_controls_hidden']=True;driver.save('path-result.json',v)

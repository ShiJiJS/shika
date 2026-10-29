import driver,json
from pathlib import Path
O=Path(__file__).resolve().parent
checks=[]
def require(name,*labels):
 n=driver.capture(name);v=driver.text(n)
 for label in labels:assert label in v,(name,label,v)
 checks.append({'state':name,'required':labels});print(name,flush=True);return n
require('release11-library','媒体库')
driver.tap_label('release11-pack-tab',prefix='图包\n');driver.tap_label('release11-continue',prefix='继续阅读\n');n=require('release11-reader','2 / 3','纵向拼接')
driver.tap_label('release11-reader-settings-open',label='纵向拼接');require('release11-reader-settings','阅读设置','图片之间留间距')
for k in ['window_animation_scale','transition_animation_scale','animator_duration_scale']:driver.device('shell','settings','put','global',k,'0')
driver.tap_label('release11-reader-settings-close',label='继续阅读');require('release11-reader-retained','2 / 3','纵向拼接');driver.device('shell','input','keyevent','4');require('release11-pack-return','媒体库','继续阅读')
driver.tap_label('release11-video-tab',prefix='视频\n');driver.tap_label('release11-preview',label='预览此范围');n=require('release11-preview-ready','视频预览')
m=[v for v in n if v.get('content-desc','').startswith('媒体库 · 全部视频') and v.get('clickable')=='true'];assert len(m)==1;driver.tap(m[0],'open actual release video range');require('release11-video-range','范围','关闭')
for k in ['window_animation_scale','transition_animation_scale','animator_duration_scale']:driver.device('shell','settings','put','global',k,'1')
driver.device('shell','input','keyevent','4');require('release11-video-range-return','视频预览');driver.device('shell','input','keyevent','4');require('release11-video-library-return','媒体库')
driver.save('sheets-result.json',{'passed':True,'normal_entrypoint':True,'checks':checks,'timing_measurement_claim':False,'profile36_is_separate':True})

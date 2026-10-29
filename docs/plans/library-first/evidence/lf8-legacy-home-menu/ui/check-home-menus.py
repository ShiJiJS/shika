import sys,json
from pathlib import Path
import business_ui as u,driver
sys.path.insert(0,str(u.O.parent));from snapshot import snapshot
baseline=json.loads((u.O.parent/'legacy/before-menus-catalog.json').read_text());title='flower-portrait.mp4'
def verify(n):
 assert title in driver.text(n) and '01 / 02' in driver.text(n),driver.text(n)
def unchanged(label):
 v=snapshot('legacy',label);assert v['tables']==baseline['tables'] and v['opaque_table_digests']==baseline['opaque_table_digests'] and v['setting_key_sha256']==baseline['setting_key_sha256'];return True
n=u.back('normal-more-cancel');verify(n);u.check('legacy-normal-menu-cancel',{'same_video':title,'same_position':1,'full_catalog_equal':unchanged('after-normal-cancel')})
u.choose('更多',context='normal-more-details-open');n=u.choose('视频详情',context='normal-video-details');assert title in driver.text(n);u.back('normal-video-details-close');u.choose('更多',context='normal-more-review-open');u.choose('进入快速整理',context='normal-review-enter');u.choose('更多',context='normal-review-more-open');n=u.choose('返回日常浏览',context='normal-review-exit');verify(n);u.check('legacy-normal-details-review',{'same_video':title,'same_position':1,'full_catalog_equal':unchanged('after-normal-details-review')})
for key in ['window_animation_scale','transition_animation_scale','animator_duration_scale']:
 u.device('shell','settings','put','global',key,'0');assert u.device('shell','settings','get','global',key).decode().strip()=='0';u.record({'action':'system-animation-scale','key':key,'value':'0'})
u.choose('更多',context='reduced-more-open');n=u.choose('Dismiss menu',context='reduced-outside-cancel');verify(n);u.check('legacy-reduced-menu-cancel',{'same_video':title,'same_position':1,'full_catalog_equal':unchanged('after-reduced-cancel')})
u.choose('更多',context='reduced-more-details-open');n=u.choose('视频详情',context='reduced-video-details');assert title in driver.text(n);u.back('reduced-details-close');u.choose('更多',context='reduced-more-review-open');u.choose('进入快速整理',context='reduced-review-enter');u.choose('更多',context='reduced-review-more-open');n=u.choose('返回日常浏览',context='reduced-review-exit');verify(n);u.check('legacy-reduced-details-review',{'same_video':title,'same_position':1,'full_catalog_equal':unchanged('after-reduced-details-review')})

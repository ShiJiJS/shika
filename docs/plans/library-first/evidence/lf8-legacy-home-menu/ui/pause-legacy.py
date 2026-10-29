import business_ui as u,driver
n=u.snap('legacy-home-before-pause-observed');i=[v for v in n if v.get('content-desc','').startswith('正在播放，')];assert len(i)==1
label=i[0].get('content-desc');u.record({'action':'observed-video-surface','semantic_clickable':i[0].get('clickable'),'bounds':i[0].get('bounds'),'reason':'legacy surface merged semantics; tap actual video area'});u.tap(i[0],'pause actual old homepage surface');n=u.snap('legacy-paused-home-observed');assert '已暂停，' in driver.text(n);u.check('normal16-original-service-home',{'observed_running_label':label,'pause_by_actual_video_area':True,'original_service_no_capabilities':True,'normal_system_animation':True})
u.choose('更多',context='legacy-normal-more-first-open')

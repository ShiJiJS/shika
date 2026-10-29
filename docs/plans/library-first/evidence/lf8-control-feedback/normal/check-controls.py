import driver,snapshot,json
O=driver.OUT
before=snapshot.snapshot('before-mode-switch')
driver.tap_label('release13-horizontal',label='横向翻页');n=driver.snap('release13-horizontal-after');assert any(v.get('content-desc')=='横向翻页' and v.get('selected')=='true' for v in n)
for key in ['window_animation_scale','transition_animation_scale','animator_duration_scale']:driver.device('shell','settings','put','global',key,'0')
driver.tap_label('release13-vertical-reduced',label='纵向拼接');n=driver.snap('release13-vertical-reduced-after');assert any(v.get('content-desc')=='纵向拼接' and v.get('selected')=='true' for v in n)
driver.tap_label('release13-reading-confirm',label='继续阅读');n=driver.snap('release13-reading-confirm-after');assert '2 / 3' in driver.text(n)
driver.tap_label('release13-open-tags',label='整包标签');driver.snap('release13-tag-editor')

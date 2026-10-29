import driver,json
n=driver.snap('candidate-video-current')
m=[v for v in n if v.get('content-desc')=='暂停' and v.get('clickable')=='true']
if len(m)==1:driver.tap(m[0],'pause fixture before fullscreen');driver.snap('candidate-video-paused')

import json,time
import driver,snapshot
O=driver.OUT
before=snapshot.snapshot('before-ordinary-settings');prefs=driver.appearance('before-ordinary-settings');offset=driver.trace_count();events=[]
def flag(reduced):
 val='0' if reduced else '1'
 for k in ['window_animation_scale','transition_animation_scale','animator_duration_scale']:driver.device('shell','settings','put','global',k,val)
 actual={k:driver.device('shell','settings','get','global',k).decode().strip() for k in ['window_animation_scale','transition_animation_scale','animator_duration_scale']};assert set(actual.values())=={val};events.append({'action':'actual-system-preference','reduced':reduced,'scales':actual})
def settings(name):
 driver.tap_label(name,label='设置');return driver.snap(name+'-settings')
def expect_ui(name,dark,preload):
 n=driver.snap(name)
 for prefix,value in [('暗黑模式',dark),('准备相邻视频',preload)]:
  found=[v for v in n if v.get('content-desc','').startswith(prefix) and v.get('clickable')=='true'];assert len(found)==1,(prefix,[v.get('content-desc') for v in n]);assert found[0].get('checked')==str(value).lower(),found[0]
 return n
def toggle(name,field,value):
 if field=='dark':driver.tap_label(name,label='暗黑模式')
 else:driver.tap_label(name,prefix='准备相邻视频')
 end=time.monotonic()+10
 while True:
  actual=driver.appearance(name+'-readback')
  if actual[field]==value:break
  assert time.monotonic()<end,'Preference save did not complete';time.sleep(.1)
 events.append({'action':'actual-setting-save','field':field,'value':value,'readback':actual})
 return actual
initial_dark,initial_preload=prefs['dark'],prefs['preloadAdjacent'];assert isinstance(initial_dark,bool) and isinstance(initial_preload,bool)
settings('open-settings');flag(False)
toggle('normal-dark-change','dark',not initial_dark);toggle('normal-preload-change','preloadAdjacent',not initial_preload);expect_ui('normal-persisted-ui',not initial_dark,not initial_preload)
driver.cold('settings-persisted-cold','new');settings('reopen-persisted');expect_ui('cold-persisted-ui',not initial_dark,not initial_preload);saved=driver.appearance('cold-persisted');assert saved['dark']==(not initial_dark) and saved['preloadAdjacent']==(not initial_preload)
flag(True);toggle('reduced-dark-return','dark',initial_dark);toggle('reduced-preload-return','preloadAdjacent',initial_preload);expect_ui('reduced-returned-ui',initial_dark,initial_preload);assert driver.appearance('returned-prefs')==prefs
# Rebuilding the root for live reduced motion must retain a real unsaved draft.
driver.tap_label('back-to-library',label='媒体库');flag(False);driver.tap_label('open-tag-draft',label='编辑标签 flower-landscape.mp4');driver.tap_label('tag-draft-off',label='LEGACY_ONLY');n=driver.snap('tag-draft-off-ui');assert any(v.get('content-desc')=='LEGACY_ONLY' and v.get('selected')=='false' for v in n)
flag(True);n=driver.snap('tag-draft-live-reduced');assert any(v.get('content-desc')=='LEGACY_ONLY' and v.get('selected')=='false' for v in n)
driver.tap_label('cancel-tag-draft',label='取消');n=driver.snap('tag-cancelled-library');assert '媒体库' in driver.text(n) and '编辑标签 flower-landscape.mp4' in driver.text(n)
driver.cold('settings-returned-cold','new');settings('reopen-original');expect_ui('cold-returned-ui',initial_dark,initial_preload);assert driver.appearance('cold-returned')==prefs
end=snapshot.snapshot('after-ordinary-settings');assert before['tables']==end['tables'];assert before['opaque_table_digests']==end['opaque_table_digests']
trace=[json.loads(v) for v in (O/'trace/requests.jsonl').read_text().splitlines()[offset:]];assert trace and all(v['method'] in ['GET','HEAD'] for v in trace),trace
result={'complete':True,'ordinary_version_code':15,'actual_persisted_fields':['dark','preloadAdjacent'],'normal_and_reduced_setting_saves':4,'cold_reopens':2,'final_preferences_equal_original':True,'all21_tables_auth_and_settings_equal':True,'real_tag_draft_preserved_on_live_reduced_then_cancelled':True,'no_server_write_requests':True,'trace_start':offset,'trace_end':driver.trace_count(),'events':events,'ordinary_screens_not_timing_evidence':True}
driver.save('settings-result.json',result);print('Ordinary settings saved/cold-read, draft cancelled, all data preserved',flush=True)

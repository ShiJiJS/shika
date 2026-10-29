import driver,snapshot,json
before=snapshot.snapshot('before-final-controls');offset=driver.trace_count()
for name,value in [('release14-tag-off-normal',False),('release14-tag-on-reduced',True),('release14-tag-off-reduced',False)]:
 if value:
  for key in ['window_animation_scale','transition_animation_scale','animator_duration_scale']:driver.device('shell','settings','put','global',key,'0')
 driver.tap_label(name,label='PACK_ONLY');n=driver.snap(name+'-after');assert any(v.get('content-desc')=='PACK_ONLY' and v.get('selected')==str(value).lower() for v in n)
driver.tap_label('release14-cancel',label='取消');n=driver.snap('release14-cancel-after');assert '图包操作 Upgrade Pack' in driver.text(n)
after=snapshot.snapshot('after-final-controls');assert before['tables']==after['tables'];assert before['opaque_table_digests']==after['opaque_table_digests']
trace=[json.loads(v) for v in (driver.OUT/'trace/requests.jsonl').read_text().splitlines()[offset:]];assert all(v['method'] in ['GET','HEAD'] for v in trace),trace
driver.save('quick-flow-result.json',{'complete':True,'ordinary_release_code':14,'normal_and_live_reduced_tag_draft_toggles':[False,True,False],'actual_quick_cancel_returned_library':True,'all21_tables_auth_and_settings_equal':True,'no_write_requests':True,'trace_start_offset':offset,'trace_end_offset':driver.trace_count(),'ordinary_screens_not_frame_timing':True})

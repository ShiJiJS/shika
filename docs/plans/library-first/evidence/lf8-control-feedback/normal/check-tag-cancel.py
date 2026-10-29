import driver,snapshot
before=snapshot.snapshot('before-tag-draft')
driver.tap_label('release13-tag-draft',label='PACK_ONLY');n=driver.snap('release13-tag-draft-after');assert any(v.get('content-desc')=='PACK_ONLY' and v.get('selected')=='false' for v in n)
driver.tap_label('release13-tag-cancel',label='取消');n=driver.snap('release13-tag-cancel-after');assert '2 / 3' in driver.text(n)
driver.device('shell','input','keyevent','4');n=driver.snap('release13-source-return');assert '媒体库' in driver.text(n) and '图包操作 Upgrade Pack' in driver.text(n)
after=snapshot.snapshot('after-real-controls')
for k in ['videos','tags','video_tags','packs','pack_pages','pack_tag_definitions','pack_tag_links','tasks','file_operations','file_steps','request_records','trash_items']:
 assert before['tables'][k]==after['tables'][k],k
driver.save('tag-cancel-result.json',{'complete':True,'ordinary_code':13,'real_tag_draft_changed_then_cancelled':True,'twelve_content_tag_task_and_file_tables_equal_during_cancel':True,'returned_page':'2 / 3','library_card_restored':True})

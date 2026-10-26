"""Read-only check of fixed-source native reader evidence."""
import hashlib,json,subprocess
from pathlib import Path
from PIL import Image
H=Path(__file__).resolve().parent;R=H.parents[4]
def read(p):return json.loads(p.read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def git(*a):return subprocess.check_output(['git',*a],cwd=R,text=True).strip()
def gsha(c,p):return hashlib.sha256(subprocess.check_output(['git','show',c+':'+p],cwd=R)).hexdigest()
def proof(log,marker):return json.loads(next(l.split(marker,1)[1] for l in log.splitlines() if l.startswith(marker)))
c=read(H/'source.json');source=c['commit'];manifest=read(H/'manifest.json')
for p,h in manifest.items():
 assert sha(H/p)==h,p
 git('ls-files','--error-unmatch',str((H/p).relative_to(R)))
for p,h in c['files'].items():assert sha(R/p)==gsha(source,p)==h,p
for tree in ['apps/mobile/lib','apps/mobile/test']:
 assert git('rev-parse','HEAD:'+tree)==git('rev-parse',source+':'+tree)==git('rev-parse',c['unit_source_commit']+':'+tree)
for tree in ['services/server/video_viewer','services/server/tests']:
 assert git('rev-parse','HEAD:'+tree)==git('rev-parse',source+':'+tree)==git('rev-parse',c['base_commit']+':'+tree)
assert git('rev-parse','HEAD:design/reference/library-first')==c['prototype_tree']=='1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
for f in read(H/'reference/served-source.json'):assert f['status']==200 and sha(R/'design/reference/library-first'/f['path'])==f['sha256']
screens=0;media=None;runtime=None
for name in ['normal-1','normal-2','normal-3','large','landscape','recent']:
 run=H/name;result=read(run/'result.json');captured=read(run/'source.json');metrics=read(run/'metrics.json');db=read(run/'database.json');log=(run/'flutter.log').read_text();requests=read(run/'requests.json')
 assert result['passed'] and captured['commit']==source and captured['prototype_tree']==c['prototype_tree']
 for p,h in captured['files'].items():assert sha(R/p)==gsha(source,p)==h,p
 image=read(run/'runtime.json')[0]['Image'];runtime=runtime or image;assert image==runtime
 assert len(metrics)==(17 if name=='recent' else 13) and result['screens']==[m['state'] for m in metrics]
 before=read(run/'media-before.json');assert len(before)==26 and before==read(run/'media-after.json');media=media or before;assert media==before
 restore=read(run/'restored-viewport.json');assert restore['before']==restore['after'] and restore['font_before']==restore['font_after'] and not restore['errors']
 assert read(run/'prepared.json')=={'videos':2,'packs':4,'pages':24}
 size=[360,740] if name=='large' else [844,390] if name=='landscape' else [390,844] if name=='recent' else [390,905]
 for m in metrics:
  assert m['size']==size and m['textScale']==(2 if name=='large' else 1)
  assert Image.open(run/(m['state']+'.png')).size==tuple(round(v*m['dpr']) for v in size)
  assert any('mCurrentFocus=' in l and 'io.github.shijijs.video_viewer' in l for l in (run/(m['state']+'-window.txt')).read_text().splitlines())
 screens+=len(metrics)
 assert 'All tests passed!' in log and 'PROTOTYPE_FIDELITY_VERIFIED' in log
 assert not any(s in log for s in ['READER_CHROME_ERROR:','RECENT_HISTORY_ERROR:','EXCEPTION CAUGHT','A RenderFlex overflowed'])
 assert [db['counts'][t] for t in ['videos','packs','pack_pages']]==[2,4,24]
 assert not db['operations'] and not db['trash']
 assert not any(r['method']=='POST' and r['path']=='/api/v1/scans' for r in requests)
 if name=='recent':
  p=proof(log,'RECENT_HISTORY_VERIFIED:');assert p['before_retry']==p['after_retry'];assert len(db['sessions'])==3 and len(db['recent'])==4;continue
 p=proof(log,'READER_CHROME_VERIFIED:');assert p['partial']==p['after_panels']==p['before_return']
 assert p['candidate_count']==4 and p['seed_progress']['revision']==1 and p['seed_progress']['page_index']==2
 assert p['partial']['page_index']==3 and p['partial']['page_id']==p['page_id'] and p['partial']['offset_ratio']>.03
 assert abs(p['return_offset']-p['expected_return_offset'])<=1
 assert len(db['sessions'])==2 and all(s['candidate_count']==4 for s in db['sessions'])
 for s in db['sessions']:
  assert json.loads(s['source'])['kind']=='library'
  assert [e['pack_id'] for e in db['entries'] if e['session_id']==s['id']]==p['expected_ids']
 assert len(db['recent'])==1 and db['recent'][0]['pack_id']==p['pack']
 pref=next(r for r in db['preferences'] if r['pack_id']==p['pack']);assert pref['mode']=='vertical'
 progress=next(r for r in db['progress'] if r['pack_id']==p['pack']);assert progress['page_id']==p['page_id'] and progress['ordinal']==3 and not progress['completed']
 assert abs(progress['offset_ratio']-p['ratio'])<.02 and progress['revision']==p['final_progress']['revision']
 assert p['final_progress']['page_id']==p['page_id'] and abs(p['final_progress']['offset_ratio']-p['ratio'])<.02
 stages={m['state']:m for m in metrics};initial=stages['reader-paged'];canvas=initial['keys']['reader-canvas']
 if name=='landscape':
  assert abs(canvas[1]-initial['viewPadding'][1])<.01
  assert abs(canvas[3]-(size[1]-initial['viewPadding'][1]-initial['viewPadding'][3]))<.01
  assert initial['keys']['reader-controls'][2]==360 and initial['keys']['reader-controls'][3]<=60
  assert 'reader-tools' not in initial['keys'] and 'reader-scope' not in initial['keys']
 else:
  assert 'reader-tools' in initial['keys'] and 'reader-scope' in initial['keys']
  assert initial['keys']['reader-header'][1]+initial['keys']['reader-header'][3]<=canvas[1]+.01
  assert canvas[1]+canvas[3]<=initial['keys']['reader-controls'][1]+.01
 assert all(stages[n]['reading']['page_id']==p['page_id'] and abs(stages[n]['reading']['ratio']-p['ratio'])<.02 for n in ['reader-strip-scroll','reader-immersive','reader-restored','reader-quick','reader-quick-exit','reader-reopen'])
 assert not stages['reader-immersive']['reading']['controls'] and 'reader-header' not in stages['reader-immersive']['keys'] and 'reader-controls' not in stages['reader-immersive']['keys']
 for state,key in [('reader-settings','reader-settings-done'),('reader-range','reader-range-pagination')]:
  action=stages[state]['keys'][key];assert action[1]+action[3]<=size[1]-stages[state]['viewPadding'][3]+.01
 assert stages['reader-restored']['reading']['controls'] and stages['reader-quick']['reading']['quick'] and not stages['reader-quick-exit']['reading']['quick']
 assert 'reader-trash-pack' in stages['reader-quick']['keys']
assert screens==82
assert '+530: All tests passed!' in (H/'checks/client.log').read_text()
assert 'No issues found!' in (H/'checks/analyze.log').read_text() and '0 changed' in (H/'checks/format.log').read_text() and 'All checks passed!' in (H/'checks/ruff.log').read_text()
print(json.dumps({'verified':True,'source':source,'screens':screens,'client':530,'manifest_inputs':len(manifest),'scope':'Reader canvas/tools and recent regression; LF8 remains open'}))

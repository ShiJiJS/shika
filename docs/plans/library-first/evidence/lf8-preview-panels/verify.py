"""Read-only verification of fixed-source preview/panel evidence."""
import hashlib,json,subprocess
from pathlib import Path
from PIL import Image
H=Path(__file__).resolve().parent;R=H.parents[4]
def read(p):return json.loads(p.read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def git(*a):return subprocess.check_output(['git',*a],cwd=R,text=True).strip()
def gsha(c,p):return hashlib.sha256(subprocess.check_output(['git','show',c+':'+p],cwd=R)).hexdigest()
def proof(log,key):return json.loads(next(l.split(key,1)[1] for l in log.splitlines() if l.startswith(key)))
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
count=0;media=None;runtime=None
for name in ['normal-1','normal-2','normal-3','large','landscape','reader','recent']:
 run=H/name;result=read(run/'result.json');captured=read(run/'source.json');metrics=read(run/'metrics.json');db=read(run/'database.json');log=(run/'flutter.log').read_text();requests=read(run/'requests.json')
 assert result['passed'] and captured['commit']==source and captured['prototype_tree']==c['prototype_tree']
 for p,h in captured['files'].items():assert sha(R/p)==gsha(source,p)==h,p
 image=read(run/'runtime.json')[0]['Image'];runtime=runtime or image;assert image==runtime
 expected=13 if name=='reader' else 17 if name=='recent' else 19
 assert len(metrics)==expected and result['screens']==[m['state'] for m in metrics]
 before=read(run/'media-before.json');assert len(before)==26 and before==read(run/'media-after.json');media=media or before;assert media==before
 restore=read(run/'restored-viewport.json');assert restore['before']==restore['after'] and restore['font_before']==restore['font_after'] and not restore['errors']
 assert read(run/'prepared.json')=={'videos':2,'packs':4,'pages':24}
 size=[360,740] if name=='large' else [844,390] if name=='landscape' else [390,905] if name=='reader' else [390,844]
 for m in metrics:
  assert m['size']==size and m['textScale']==(2 if name=='large' else 1)
  assert Image.open(run/(m['state']+'.png')).size==tuple(round(v*m['dpr']) for v in size)
  assert any('mCurrentFocus=' in l and 'io.github.shijijs.video_viewer' in l for l in (run/(m['state']+'-window.txt')).read_text().splitlines())
 count+=len(metrics)
 assert 'All tests passed!' in log and 'PROTOTYPE_FIDELITY_VERIFIED' in log
 assert not any(s in log for s in ['PREVIEW_PANELS_ERROR:','READER_CHROME_ERROR:','RECENT_HISTORY_ERROR:','EXCEPTION CAUGHT','A RenderFlex overflowed'])
 assert [db['counts'][t] for t in ['videos','packs','pack_pages']]==[2,4,24]
 assert not db['operations'] and not db['pack_operations'] and not db['trash']
 assert not any(r['method']=='POST' and r['path']=='/api/v1/scans' for r in requests)
 if name=='recent':
  p=proof(log,'RECENT_HISTORY_VERIFIED:');assert p['before_retry']==p['after_retry'];assert len(db['sessions'])==3 and len(db['recent'])==4;continue
 if name=='reader':
  p=proof(log,'READER_CHROME_VERIFIED:');assert p['partial']==p['after_panels']==p['before_return'];assert p['candidate_count']==4 and abs(p['return_offset']-p['expected_return_offset'])<=1;continue
 p=proof(log,'PREVIEW_PANELS_VERIFIED:');assert p['ids']==p['queue_ids'] and p['recent']==p['ids'][::-1] and p['seek_ms']>2000 and p['restored_speed']==1.5
 # prepare() seeds one summer-pack progress row before any video action.
 assert db['counts']['pack_sessions']==0 and db['counts']['pack_progress']==1
 seeded=db['progress'][0]
 assert {k:seeded[k] for k in ['offset_ratio','completed','revision','updated_at','content_version','recovery_reason']}=={'offset_ratio':0.0,'completed':0,'revision':1,'updated_at':1000.0,'content_version':1,'recovery_reason':None}
 assert db['progress_pages']==[{'name':'示例作者 NO.034 - 夏日祭','ordinal':2}]
 assert not any(r['method'] in ['POST','PUT','PATCH','DELETE'] and '/packs/' in r['path'] for r in requests)
 assert len(db['rounds'])==2 and len(db['recent'])==2
 full=next(r for r in db['rounds'] if r['id']==p['full_round']);one=next(r for r in db['rounds'] if r['id']==p['filtered_round'])
 assert [full['candidate_count'],one['candidate_count']]==[2,1] and full['membership']==one['membership']=='fixed' and full['source']==one['source']=='library'
 assert full['order']=='sequential' and full['finished'] and full['cursor']==1
 assert [r['video_id'] for r in db['round_entries'] if r['round_id']==full['id']]==p['ids']
 assert [r['video_id'] for r in db['round_entries'] if r['round_id']==one['id']]==p['ids'][:1]
 assert not any(r['method'] in ['POST','PUT','PATCH','DELETE'] and any(t in r['path'] for t in ['/tags','/delete','/trash']) for r in requests)
 stages={m['state']:m for m in metrics}
 paused=stages['preview-paused'];seek=stages['preview-seek'];boost=stages['preview-boost']
 assert paused['players'][0]['initialized'] and not paused['players'][0]['playing']
 assert not seek['players'][0]['playing'] and seek['players'][0]['position_ms']>2000
 assert boost['players'][0]['playing'] and boost['players'][0]['speed']==2
 for state in ['preview-paused','preview-seek']:
  bar=stages[state]['keys']['playback-controls'];assert stages[state]['keys']['video-progress-touch'][2]>=88
  assert bar[3]==(96 if name=='large' else 48)
  assert bar[1]+bar[3]<=size[1]-stages[state]['viewPadding'][3]
  if 'inline-play' in stages[state]['keys']:
   button=stages[state]['keys']['inline-play'];assert button[1]+button[3]<=bar[1]
 assert stages['preview-queue']['queue_decoded']>=2 and stages['preview-queue']['queue_order_enabled']
 assert stages['preview-dark']['dark'] and not stages['preview-light']['dark']
 assert stages['preview-dark']['theme_primary']==stages['preview-dark']['back_color']==0xffb1c5a0
 assert stages['preview-light']['theme_primary']==0xff53664a
 for state in ['preview-paused','preview-seek','preview-boost','preview-quick','preview-tags','preview-more','preview-details','preview-dark','preview-light','preview-queue']:
  assert stages[state]['round']==p['full_round'] and stages[state]['current']==p['ids'][0]
assert count==125
assert '+540: All tests passed!' in (H/'checks/client.log').read_text()
assert 'No issues found!' in (H/'checks/analyze.log').read_text() and '0 changed' in (H/'checks/format.log').read_text() and 'All checks passed!' in (H/'checks/ruff.log').read_text()
print(json.dumps({'verified':True,'source':source,'screens':count,'client':540,'manifest_inputs':len(manifest),'scope':'Preview panels/control combinations; full LF8 remains open'}))

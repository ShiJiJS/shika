"""Read-only evidence, source, native geometry, media and SQL checks."""
import hashlib,json,subprocess
from functools import lru_cache
from pathlib import Path
from PIL import Image
H=Path(__file__).resolve().parent;R=H.parents[4]
def read(p): return json.loads(p.read_text())
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def git(*a): return subprocess.check_output(['git',*a],cwd=R,text=True).strip()
@lru_cache(None)
def gsha(c,p): return hashlib.sha256(subprocess.check_output(['git','show',c+':'+p],cwd=R)).hexdigest()
def proof(log,key): return json.loads(next(l.split(key,1)[1] for l in log.splitlines() if l.startswith(key)))
c=read(H/'source.json');source=c['commit'];manifest=read(H/'manifest.json')
tracked=set(git('ls-files').splitlines())
for p,h in manifest.items():
 assert sha(H/p)==h,p
 assert str((H/p).relative_to(R)) in tracked,p
for p,h in c['files'].items(): assert sha(R/p)==gsha(source,p)==h,p
for tree in ['apps/mobile/lib','apps/mobile/test']:
 assert git('rev-parse','HEAD:'+tree)==git('rev-parse',source+':'+tree)==git('rev-parse',c['unit_source_commit']+':'+tree)
for tree in ['services/server/video_viewer','services/server/tests']:
 assert git('rev-parse','HEAD:'+tree)==git('rev-parse',source+':'+tree)==git('rev-parse',c['base_commit']+':'+tree)
assert git('rev-parse','HEAD:design/reference/library-first')==c['prototype_tree']=='1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
for p,v in read(H/'reference/served-source.json')['files'].items(): assert sha(R/'design/reference/library-first'/p)==v['served_sha256']==v['disk_sha256']
count=0;media=None;runtime=None
profiles=['normal-1','normal-2','normal-3','large','landscape','reader-landscape','preview-landscape','recent-landscape']
for name in profiles:
 run=H/name;result=read(run/'result.json');s=read(run/'source.json');metrics=read(run/'metrics.json');db=read(run/'database.json');log=(run/'flutter.log').read_text();requests=read(run/'requests.json')
 assert result['passed'] and s['commit']==source and s['prototype_tree']==c['prototype_tree']
 for p,h in s['files'].items(): assert sha(R/p)==gsha(source,p)==h,p
 expected={'reader-landscape':13,'preview-landscape':20,'recent-landscape':17}.get(name,21)
 assert len(metrics)==expected and result['screens']==[m['state'] for m in metrics]
 count+=len(metrics)
 actual=read(run/'media-before.json');assert len(actual)==26 and actual==read(run/'media-after.json');media=media or actual;assert media==actual
 image=read(run/'runtime.json')[0]['Image'];runtime=runtime or image;assert runtime==image
 restore=read(run/'restored-viewport.json');assert restore['before']==restore['after'] and restore['font_before']==restore['font_after'] and not restore['errors']
 assert read(run/'prepared.json')=={'videos':2,'packs':4,'pages':24}
 size=[844,390] if 'landscape' in name else [360,740] if name=='large' else [390,844]
 for m in metrics:
  assert m['size']==size and m['textScale']==(2 if name=='large' else 1)
  assert Image.open(run/(m['state']+'.png')).size==tuple(round(v*m['dpr']) for v in size)
  assert any('mCurrentFocus=' in l and 'io.github.shijijs.video_viewer' in l for l in (run/(m['state']+'-window.txt')).read_text().splitlines())
 assert 'All tests passed!' in log and 'PROTOTYPE_FIDELITY_VERIFIED' in log
 assert not any(t in log for t in ['SETTINGS_PANELS_ERROR:','READER_CHROME_ERROR:','PREVIEW_PANELS_ERROR:','RECENT_HISTORY_ERROR:','EXCEPTION CAUGHT','A RenderFlex overflowed'])
 assert [db['counts'][t] for t in ['videos','packs','pack_pages','file_operations','pack_file_operations','pack_trash_items']]==[2,4,24,0,0,0]
 assert not any(r['method']=='POST' and r['path']=='/api/v1/scans' for r in requests)
 stages={m['state']:m for m in metrics}
 if name=='reader-landscape':
  p=proof(log,'READER_CHROME_VERIFIED:');assert p['partial']==p['after_panels']==p['before_return'];assert p['candidate_count']==4
  assert abs(p['return_offset']-p['expected_return_offset'])<=1
  assert p['partial']['page_id']==p['page_id'] and p['partial']['page_index']==3 and p['partial']['offset_ratio']>.03
  assert p['final_progress']['page_id']==p['page_id'] and abs(p['final_progress']['offset_ratio']-p['ratio'])<.02
  assert db['counts']['pack_sessions']==2 and len(db['recent'])==1
  for session in db['sessions']:
   assert session['candidate_count']==4 and [e['pack_id'] for e in db['pack_entries'] if e['session_id']==session['id']]==p['expected_ids']
  assert next(pref for pref in db['preferences'] if pref['pack_id']==p['pack'])['mode']=='vertical'
  overview=stages['reader-overview']['keys']['reader-overview-sheet'];assert overview[2]>800
  continue
 if name=='preview-landscape':
  p=proof(log,'PREVIEW_PANELS_VERIFIED:');assert p['ids']==p['queue_ids'] and p['recent']==p['ids'][::-1] and p['seek_ms']>2000 and p['restored_speed']==1.5
  frame=stages['preview-queue']['keys']['preview-queue-frame'];assert frame[2]>800 and frame[3]<=390*.92+1
  assert len(db['rounds'])==2 and len(db['recent'])==2 and db['counts']['pack_sessions']==0
  continue
 if name=='recent-landscape':
  p=proof(log,'RECENT_HISTORY_VERIFIED:');assert p['before_retry']==p['after_retry']
  assert db['counts']['pack_sessions']==3 and len(db['recent'])==4
  continue
 p=proof(log,'SETTINGS_PANELS_VERIFIED:')
 assert p['round_before']==p['round_after'] and p['roots_before']==p['roots_after'] and p['order_before']==p['order_after']
 assert p['reader_saved']=={'mode':'vertical','direction':'rtl','gap':True,'fit':'width','revision':1}
 assert p['reader_before']=={'mode':'horizontal','direction':'ltr','gap':False,'fit':'contain','revision':0}
 assert p['reader_restored']==dict(p['reader_before'],revision=2)
 assert db['counts']['pack_sessions']==0 and not db['recent'] and db['counts']['pack_progress']==1
 seed=db['progress'][0];assert {k:seed[k] for k in ['offset_ratio','completed','revision','updated_at','content_version','recovery_reason']}=={'offset_ratio':0.0,'completed':0,'revision':1,'updated_at':1000.0,'content_version':1,'recovery_reason':None}
 assert db['progress_pages']==[{'name':'示例作者 NO.034 - 夏日祭','ordinal':2}]
 defaults={r['key']:json.loads(r['value']) for r in db['defaults']};assert defaults['reader_defaults']==p['reader_restored'] and defaults['playback_defaults']==p['order_before']
 assert len(db['rounds'])==1
 rnd=db['rounds'][0];assert rnd['id']==p['round_before']['id'] and rnd['candidate_count']==2 and rnd['cursor']==0 and not rnd['finished'] and rnd['order']=='sequential'
 assert [r['video_id'] for r in db['entries']]==[e['video']['id'] for e in p['round_before']['window']]
 assert [{k:r[k] for k in ['id','name','path','kind','enabled','available']} for r in db['roots']]==[{k:r[k] for k in ['id','name','path','kind','enabled','available']} for r in sorted(p['roots_before'],key=lambda r:r['id'])]
 writes=[r for r in requests if r['method'] not in ['GET','HEAD']]
 assert [(r['method'],r['path'],r['status']) for r in writes]==[('POST','/api/v1/auth/login',200),('POST','/api/v1/rounds',201),('PUT','/api/v1/roots/videos',409),('PATCH','/api/v1/reading-defaults',200),('PATCH','/api/v1/reading-defaults',200)]
 for state,key in [('settings-connection-keyboard','connection-port'),('settings-root-keyboard','root-name')]:
  m=stages[state];assert m['viewInsets'][3]>0
  r=m['keys'][key];assert r[1]>=m['viewPadding'][1] and r[1]+r[3]<=size[1]-m['viewInsets'][3]+1
 for state in ['settings-root-invalid','settings-root-conflict']:
  m=stages[state];error=m['keys']['root-error'];save=m['keys']['root-save'];assert error[1]>=0 and error[1]+error[3]<=save[1]+1
 for state,key in [('settings-root-add','root-save'),('settings-reader','defaults-save'),('settings-playback','defaults-save')]:
  m=stages[state];r=m['keys'][key];assert r[0]>=0 and r[0]+r[2]<=size[0]+1 and r[1]+r[3]<=size[1]-m['viewPadding'][3]+1
  if name=='landscape': assert r[2]>800
 assert stages['settings-dark-reader']['theme_primary']==stages['settings-dark-roots']['theme_primary']==0xffb1c5a0
 assert stages['settings-return']['theme_primary']==0xff53664a
 if name=='large': assert stages['settings-roots']['keys']['management-header'][3]==72
assert count==155
assert '+550: All tests passed!' in (H/'checks/client.log').read_text()
assert 'No issues found!' in (H/'checks/analyze.log').read_text() and '0 changed' in (H/'checks/format.log').read_text() and 'All checks passed!' in (H/'checks/ruff.log').read_text()
print(json.dumps({'verified':True,'source':source,'screens':count,'client':550,'manifest_inputs':len(manifest),'scope':c['scope']}))

"""Read-only source, native geometry, media, SQL and evidence checks."""
import hashlib,json,subprocess
from pathlib import Path
from PIL import Image
H=Path(__file__).resolve().parent;R=H.parents[4]
def read(p):return json.loads(p.read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def git(*args):return subprocess.check_output(['git',*args],cwd=R,text=True).strip()
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
media=None;runtime=None;count=0
for name in ['normal-1','normal-2','normal-3','large','landscape']:
 run=H/name;result=read(run/'result.json');s=read(run/'source.json');metrics=read(run/'metrics.json');db=read(run/'database.json');log=(run/'flutter.log').read_text();requests=read(run/'requests.json')
 assert result['passed'] and s['commit']==source and s['prototype_tree']==c['prototype_tree']
 for p,h in s['files'].items():assert sha(R/p)==gsha(source,p)==h,p
 assert len(metrics)==20 and result['screens']==[m['state'] for m in metrics]
 count+=len(metrics)
 actual=read(run/'media-before.json');assert len(actual)==26 and actual==read(run/'media-after.json');media=media or actual;assert media==actual
 image=read(run/'runtime.json')[0]['Image'];runtime=runtime or image;assert runtime==image
 restore=read(run/'restored-viewport.json');assert restore['before']==restore['after'] and restore['font_before']==restore['font_after'] and not restore['errors']
 assert read(run/'prepared.json')=={'videos':2,'packs':4,'pages':24}
 size=[844,390] if name=='landscape' else [360,740] if name=='large' else [390,844]
 for m in metrics:
  assert m['size']==size and m['textScale']==(2 if name=='large' else 1)
  assert Image.open(run/(m['state']+'.png')).size==tuple(round(v*m['dpr']) for v in size)
  assert any('mCurrentFocus=' in l and 'io.github.shijijs.video_viewer' in l for l in (run/(m['state']+'-window.txt')).read_text().splitlines())
 assert 'All tests passed!' in log and 'PROTOTYPE_FIDELITY_VERIFIED' in log
 assert not any(t in log for t in ['PREVIEW_PANELS_ERROR:','EXCEPTION CAUGHT','A RenderFlex overflowed'])
 assert [db['counts'][t] for t in ['videos','packs','pack_pages','pack_sessions','file_operations','pack_file_operations','pack_trash_items']]==[2,4,24,0,0,0,0]
 # The shared public fixture deliberately seeds one read position before video actions.
 assert db['counts']['pack_progress']==1
 seed=db['progress'][0]
 assert {k:seed[k] for k in ['offset_ratio','completed','revision','updated_at','content_version','recovery_reason']}=={'offset_ratio':0.0,'completed':0,'revision':1,'updated_at':1000.0,'content_version':1,'recovery_reason':None}
 assert db['progress_pages']==[{'name':'示例作者 NO.034 - 夏日祭','ordinal':2}]
 assert not any(r['method'] in ['POST','PUT','PATCH','DELETE'] and any(t in r['path'] for t in ['/tags','/delete','/trash','/packs/','/scans']) for r in requests)
 p=proof(log,'PREVIEW_PANELS_VERIFIED:');assert p['ids']==p['queue_ids'] and p['recent']==p['ids'][::-1] and p['seek_ms']>2000 and p['restored_speed']==1.5
 assert len(db['rounds'])==2 and len(db['recent'])==2
 full=next(r for r in db['rounds'] if r['id']==p['full_round']);one=next(r for r in db['rounds'] if r['id']==p['filtered_round'])
 assert [full['candidate_count'],one['candidate_count']]==[2,1] and full['membership']==one['membership']=='fixed' and full['source']==one['source']=='library'
 assert full['order']=='sequential' and full['finished'] and full['cursor']==1
 assert [r['video_id'] for r in db['entries'] if r['round_id']==full['id']]==p['ids']
 assert [r['video_id'] for r in db['entries'] if r['round_id']==one['id']]==p['ids'][:1]
 stages={m['state']:m for m in metrics};queue=stages['preview-queue'];frame=queue['keys']['preview-queue-frame']
 assert queue['queue_decoded']>=2 and queue['queue_order_enabled']
 assert abs(frame[2]-(size[0]-queue['viewPadding'][0]-queue['viewPadding'][2]))<=1
 assert 0<frame[3]<=size[1]*(.92 if size[1]<=700 else .88)+1
 if name.startswith('normal'):
  assert frame[3]<520
  note=queue['keys']['preview-queue-note'];assert note[1]+note[3]<=size[1]-queue['viewPadding'][3]
  reference=read(H/'reference/normal-queue.json')['rects']['.sheet'];assert abs(frame[3]-queue['viewPadding'][3]-reference[3])<40
 if name in ['normal-1','landscape']:
  before=next(m for m in read(H/'before'/name/'metrics.json') if m['state']=='preview-queue')['keys']['preview-queue']
  assert frame[3]<before[3]-100 if name=='normal-1' else frame[2]>before[2]+150
 bottom=stages['preview-queue-bottom'];note=bottom['keys']['preview-queue-note'];viewport=bottom['keys']['preview-queue']
 assert note[1]>=viewport[1]-1 and note[1]+note[3]<=viewport[1]+viewport[3]+1
 if name!='large':assert stages['preview-quick']['keys']['preview-cleanup'][3]==48
 for state in ['preview-paused','preview-seek']:
  m=stages[state];bar=m['keys']['playback-controls'];assert m['keys']['video-progress-touch'][2]>=88 and bar[3]==(96 if name=='large' else 48)
  if 'inline-play' in m['keys']:assert m['keys']['inline-play'][1]+m['keys']['inline-play'][3]<=bar[1]
 assert stages['preview-paused']['players'][0]['initialized'] and not stages['preview-paused']['players'][0]['playing']
 assert not stages['preview-seek']['players'][0]['playing'] and stages['preview-seek']['players'][0]['position_ms']>2000
 assert stages['preview-boost']['players'][0]['playing'] and stages['preview-boost']['players'][0]['speed']==2
 assert stages['preview-dark']['theme_primary']==stages['preview-dark']['back_color']==0xffb1c5a0 and stages['preview-light']['theme_primary']==0xff53664a
 for state in ['preview-paused','preview-seek','preview-boost','preview-quick','preview-tags','preview-more','preview-details','preview-dark','preview-light','preview-queue','preview-queue-bottom']:assert stages[state]['round']==p['full_round'] and stages[state]['current']==p['ids'][0]
assert count==100
assert '+544: All tests passed!' in (H/'checks/client.log').read_text()
assert 'No issues found!' in (H/'checks/analyze.log').read_text() and '0 changed' in (H/'checks/format.log').read_text()
assert 'All checks passed!' in (H/'checks/ruff.log').read_text()
print(json.dumps({'verified':True,'source':source,'screens':count,'client':544,'manifest_inputs':len(manifest),'scope':c['scope']}))

"""Read-only verification of one fixed recent-history implementation and captures."""
import hashlib
import json
import subprocess
from pathlib import Path
from PIL import Image
H=Path(__file__).resolve().parent
R=H.parents[4]
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
 assert git('rev-parse','HEAD:'+tree)==git('rev-parse',source+':'+tree)==git('rev-parse',c['server_check_source_commit']+':'+tree)
assert git('rev-parse','HEAD:design/reference/library-first')==c['prototype_tree']=='1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
for f in read(H/'reference/served-source.json'):
 assert f['status']==200 and sha(R/'design/reference/library-first'/f['path'])==f['sha256']
media=None;runtime=None;screens=0
for name in ['normal-1','normal-2','normal-3','large','landscape','video-order','cards']:
 run=H/name;result=read(run/'result.json');captured=read(run/'source.json');metrics=read(run/'metrics.json');requests=read(run/'requests.json');db=read(run/'database.json');log=(run/'flutter.log').read_text()
 assert result['passed'] and captured['commit']==source and captured['prototype_tree']==c['prototype_tree']
 for p,h in captured['files'].items():assert sha(R/p)==gsha(source,p)==h,p
 image=read(run/'runtime.json')[0]['Image'];runtime=runtime or image;assert image==runtime
 assert len(metrics)==(8 if name=='video-order' else 6 if name=='cards' else 17)
 assert result['screens']==[m['state'] for m in metrics]
 before=read(run/'media-before.json');assert len(before)==26 and before==read(run/'media-after.json')
 media=media or before;assert media==before
 restore=read(run/'restored-viewport.json');assert restore['before']==restore['after'] and restore['font_before']==restore['font_after'] and not restore['errors']
 assert read(run/'prepared.json')=={'videos':2,'packs':4,'pages':24}
 size=[360,740] if name=='large' else [844,390] if name=='landscape' else [844,442] if name=='cards' else [390,905] if name=='video-order' else [390,844]
 for m in metrics:
  assert m['size']==size and m['textScale']==(2 if name=='large' else 1)
  assert Image.open(run/(m['state']+'.png')).size==tuple(round(v*m['dpr']) for v in size)
  assert any('mCurrentFocus=' in l and 'io.github.shijijs.video_viewer' in l for l in (run/(m['state']+'-window.txt')).read_text().splitlines())
 screens+=len(metrics)
 assert 'All tests passed!' in log and 'PROTOTYPE_FIDELITY_VERIFIED' in log
 assert not any(s in log for s in ['RECENT_HISTORY_ERROR:','VIDEO_NAME_ORDER_ERROR:','CATALOG_CARDS_ERROR:','EXCEPTION CAUGHT','A RenderFlex overflowed'])
 assert [db['counts'][t] for t in ['videos','packs','pack_pages']]==[2,4,24]
 assert not db['operations'] and not db['trash']
 assert not any(r['method']=='POST' and r['path']=='/api/v1/scans' for r in requests)
 if name=='cards':
  p=proof(log,'CATALOG_CARDS_VERIFIED:');assert p['before_progress']==p['after_progress'];continue
 if name=='video-order':
  p=proof(log,'VIDEO_NAME_ORDER_VERIFIED:');assert len(db['rounds'])==2 and len(db['recent'])==2;continue
 p=proof(log,'RECENT_HISTORY_VERIFIED:');assert p['before_retry']==p['after_retry'] and p['initial_progress']['revision']==1
 assert p['before_read']['page_index']==p['before_retry']['page_index']==2 and p['library_video_search']=='风里的花园' and p['recent_video_entries']==1
 assert len(db['rounds'])==3 and sorted(r['candidate_count'] for r in db['rounds'])==[1,1,1]
 r=next(r for r in db['rounds'] if r['id']==p['recent_round']);assert r['source']=='recent'
 assert [e['video_id'] for e in db['round_entries'] if e['round_id']==r['id']]==[p['video_ids'][0]]
 assert len(db['sessions'])==3 and sorted(s['candidate_count'] for s in db['sessions'])==[1,1,2]
 s=next(s for s in db['sessions'] if s['id']==p['recent_pack_range']);assert json.loads(s['source'])['kind']=='recent'
 assert [e['pack_id'] for e in db['entries'] if e['session_id']==s['id']]==p['pack_ids']
 assert len(db['recent'])==4
 assert [r['video_id'] for r in db['recent'] if r['kind']=='video']==p['video_ids'][::-1]
 assert [r['pack_id'] for r in db['recent'] if r['kind']=='pack']==p['pack_ids']
 for endpoint in ['/api/v1/videos','/api/v1/packs']:
  rows=[r for r in requests if r['path']==endpoint and dict(r.get('query',[])).get('source')=='recent' and dict(r['query']).get('limit')!='1']
  assert any(r['status']==503 for r in rows) and any(r['status']==200 for r in rows)
  assert all(not dict(r['query']).get('search','') and dict(r['query']).get('sort')=='recent' for r in rows)
  a=next(i for i,r in enumerate(requests) if r['path']==endpoint and r['status']==503)
  b=next(i for i in range(a+1,len(requests)) if requests[i]['path']==endpoint and requests[i]['status']==200 and dict(requests[i].get('query',[])).get('source')=='recent')
  assert all(r['method']=='GET' for r in requests[a:b+1])
 for m in metrics:
  if m['state'].startswith('recent-keyboard-'):
   assert m['viewInsets'][3]>0
   if name=='large':
    action='快速整理' if m['state'].endswith('pack') else '预览此范围'
    rect=next(t['rect'] for t in m['texts'] if t['text']==action)
    assert rect[1]+rect[3]<=size[1]-m['viewInsets'][3]
  if m['state'] in ['recent-video-two','recent-packs-two']:
   assert len(m['history_rows'])==2
   assert all(r[0]==20 and r[2]==size[0]-40 for r in m['history_rows'])
   state=m['video_catalog'] if m['state']=='recent-video-two' else m['pack_catalog']
   assert state['source']=='recent' and state['scrollOffset']>=0
   assert abs(m['history_rows'][1][1]-m['history_rows'][0][1]-state['stride'])<.01
   if name.startswith('normal'):assert all(abs(r[3]-111)<1e-6 for r in m['history_rows'])
  if m['state'] in ['recent-video-error','recent-pack-error']:
   text=next(t for t in m['texts'] if t['text'].startswith('当前列表已保留：'))
   assert text['rect'][0]==20 and text['fontSize']==12
assert screens==99
assert '+518: All tests passed!' in (H/'checks/client.log').read_text()
assert '26 passed' in (H/'checks/server.log').read_text()
assert 'No issues found!' in (H/'checks/analyze.log').read_text()
assert 'All checks passed!' in (H/'checks/ruff.log').read_text()
assert read(H/'diagnostics/keyboard-replay.json')['old_result']!=0
assert '-2: Some tests failed.' in (H/'diagnostics/keyboard-old-source.log').read_text()
assert '-gpu host' in (H/'recovery/new-emulator-process.txt').read_text()
assert 'Service window: found' in (H/'recovery/boot-check.json').read_text()
assert 'Service settings: found' in (H/'recovery/boot-check.json').read_text()
restored=read(H/'recovery/display-restored.json')
assert restored[-3]['out']=='Physical size: 1080x2400\n' and restored[-2]['out']=='Physical density: 420\n' and restored[-1]['out'].strip()=='1.0'
print(json.dumps({'verified':True,'source':source,'screens':screens,'manifest_inputs':len(manifest),'client':518,'related_server':26,'scope':'recent history/keyboard/error and two regression scenarios; remaining LF8 open'},ensure_ascii=False))

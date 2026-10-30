import json,time,urllib.request,urllib.parse
from pathlib import Path
import business_ui as u,driver,flows as f
from ui_driver import device,fill
from snapshot_all import snapshot
O=Path(__file__).resolve().parent;L=O.parent;seed=f.seed;results=[]
def req(path):
 r=urllib.request.Request('http://127.0.0.1:8776/api/v1'+path,headers={'Authorization':'Bearer '+(O/'config/observer-token').read_text().strip()})
 with urllib.request.urlopen(r,timeout=20) as x:return json.load(x)
directory=req('/directories/resolve?path='+urllib.parse.quote('/media/videos/Landscape',safe=''));(L/'landscape-directory.json').write_text(json.dumps(directory,indent=2)+'\n')
expected=[v['id'] for v in seed['videos'] if '/Landscape/Child/' in v['path']];assert len(expected)==14
for i in range(1,4):
 name=f'video-combo-{i}'
 if i>1:
  u.choose('筛选视频',context=name+'-filter');u.choose('更换目录',context=name+'-directory');u.choose(prefix='短视频\n',context=name+'-root');u.choose(prefix='Landscape\n',context=name+'-parent')
 u.choose('使用此目录',context=name+'-use-parent');u.choose('Intersection',context=name+'-tag');f.dropdown('画面方向\n','横版',name+'-orientation');f.dropdown('时长\n','10 秒以内',name+'-duration');f.dropdown('文件类型\n','MP4',name+'-type');u.choose('应用筛选',context=name+'-apply');f.count('视频',14,name+'-matched')
 scope={'directory_id':directory['id'],'search':'Scope','tag_ids':[seed['tags']['video']['Intersection']],'orientation':'landscape','duration':'short','file_type':'MP4'}
 f.preview(name+'-preview',expected,scope)
 u.choose('筛选视频',context=name+'-draft');f.dropdown('画面方向\n','竖版',name+'-draft-portrait');u.choose('关闭面板',context=name+'-cancel');f.count('视频',14,name+'-cancel-preserves')
 u.choose('筛选视频',context=name+'-long');n=u.snap(name+'-unchanged-draft');assert '画面方向\n横版' in driver.text(n);f.dropdown('时长\n','10 秒以上',name+'-long-duration');offset=driver.trace_count();u.choose('应用筛选',context=name+'-long-apply');n=f.count('视频',0,name+'-long-empty');buttons=[x for x in n if x.get('content-desc')=='预览此范围'];assert len(buttons)==1 and buttons[0].get('enabled')=='false'
 lines=[json.loads(x) for x in (O/'trace/requests.jsonl').read_text().splitlines()[offset:]];assert not any(x['method']=='POST' and 'round' in x['path'] for x in lines);reads=[x for x in lines if x['path']=='/api/v1/videos'];assert reads;params=urllib.parse.parse_qs(reads[-1]['query']);assert params['duration']==['long'] and params['directory_id']==[directory['id']] and params['file_type']==['MP4'];answer=req('/videos?'+reads[-1]['query']);assert answer['total']==0 and answer['items']==[];(L/(name+'-long-empty.json')).write_text(json.dumps({'requests':lines,'response':answer,'preview_enabled':False},indent=2)+'\n')
 u.choose('筛选视频',context=name+'-format-empty');f.dropdown('时长\n','10 秒以内',name+'-short-again');f.dropdown('文件类型\n','MOV',name+'-mov');u.choose('应用筛选',context=name+'-mov-apply');f.count('视频',0,name+'-mov-empty')
 u.choose('筛选视频',context=name+'-reset');u.choose('清除条件',context=name+'-clear');u.choose('应用筛选',context=name+'-reset-apply');n=f.count('视频',27,name+'-restored');fields=[x for x in n if x.get('class')=='android.widget.EditText'];assert len(fields)==1 and fields[0].get('text')=='Scope'
 results.append({'round':i,'combined_count':14,'long_duration_count':0,'mov_count':0,'cancel_preserved':True,'reset_keeps_search':True})
 (L/'video-combinations-result.json').write_text(json.dumps({'complete':i==3,'normal_code':21,'rounds':results,'previews':f.checks},indent=2)+'\n')
print('THREE VIDEO COMBINATIONS COMPLETE',flush=True)

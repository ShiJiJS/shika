import hashlib,json,re,subprocess
from pathlib import Path
import business_ui as u,driver,flows as f
from ui_driver import device,fill,tap
from snapshot_all import snapshot
O=Path(__file__).resolve().parent;L=O.parent

def same(a,b):
 for k in ['tables','opaque_table_digests','setting_key_sha256']:assert a[k]==b[k],k

def cover(name,kind):
 a=snapshot('new',name+'-before');prefs=driver.appearance(name+'-before');driver.install(name,kind);b=snapshot(kind,name+'-after');same(a,b);assert driver.appearance(name+'-after')==prefs
 path=device('shell','pm','path',driver.PACKAGE).decode().strip().removeprefix('package:');sha=hashlib.sha256(device('exec-out','cat',path)).hexdigest();build=json.loads((L/'build-1/result.json').read_text());assert sha==build[kind]['sha256'];driver.save(name+'-actual-apk.json',{'sha256':sha,'version_code':22,'matches_build':True})

cover('upgrade22','forward')
u.choose('筛选视频',context='summary22-property-filter');f.dropdown('画面方向\n','横版','summary22-orientation');f.dropdown('时长\n','10 秒以上','summary22-long');f.dropdown('文件类型\n','MOV','summary22-type');u.choose('应用筛选',context='summary22-properties-apply');n=f.count('视频',0,'summary22-properties-empty');text=driver.text(n);assert '横版 · 10 秒以上 · MOV' in text
# Clear is still the original full query clear action.
u.choose('清除',context='summary22-clear');f.count('视频',29,'summary22-clear-all29');fill(0,'Scope','summary22-search');device('shell','input','keyevent','4');f.count('视频',27,'summary22-search27')
u.choose('筛选视频',context='summary22-combined-filter');u.choose('更换目录',context='summary22-directory');u.choose(prefix='短视频\n',context='summary22-root');u.choose(prefix='Landscape\n',context='summary22-parent');u.choose('使用此目录',context='summary22-use-parent');u.choose('Intersection',context='summary22-tag');f.dropdown('画面方向\n','横版','summary22-combo-orientation');f.dropdown('时长\n','10 秒以内','summary22-short');f.dropdown('文件类型\n','MP4','summary22-mp4');u.choose('应用筛选',context='summary22-combined-apply');n=f.count('视频',14,'summary22-combined14');text=driver.text(n);assert all(v in text for v in ['/media/videos/Landscape','# Intersection','Scope','横版','10 秒以内','MP4'])
expected=[v['id'] for v in f.seed['videos'] if '/Landscape/Child/' in v['path']];directory=json.loads((L/'landscape-directory.json').read_text());f.preview('summary22-preview14',expected,{'directory_id':directory['id'],'search':'Scope','tag_ids':[f.seed['tags']['video']['Intersection']],'orientation':'landscape','duration':'short','file_type':'MP4'})
cover('rollback22','rollback');cover('return22','forward')
(L/'summary22-result.json').write_text(json.dumps({'complete':True,'normal_code':22,'properties_empty_count':0,'clear_count':29,'combined_count':14,'scope_properties_visible_in_native_semantics':True,'three_cover_installs_preserve_all35_tables_settings_tokens_preferences_identity':True,'previews':f.checks},indent=2)+'\n')
print('SUMMARY22 COMPLETE',flush=True)

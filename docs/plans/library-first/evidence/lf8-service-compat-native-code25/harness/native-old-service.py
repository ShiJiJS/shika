import json,sys,time,re,hashlib
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import ui,api
from snapshot_all import snapshot
info=api.call('GET','/api/v1/info');assert not {'scoped_scans','root_scan_progress'}&set(info['capabilities']);(ui.L/'old-info-public-capabilities.json').write_text(json.dumps({'schema_version':info['schema_version'],'api_version':info['api_version'],'capabilities':info['capabilities']},indent=2)+'\n')
before=snapshot('old-service','before-native');checks=json.loads((ui.ROOT/'docs/plans/library-first/evidence/lf8-vertical-strip-zoom/checks.json').read_text());installed=ui.device('shell','pm','path',ui.PACKAGE).decode().strip().removeprefix('package:');assert hashlib.sha256(ui.device('exec-out','cat',installed)).hexdigest()==checks['normal_code25']['sha256'];ui.device('shell','am','force-stop',ui.PACKAGE);ui.device('shell','am','start','-n',ui.PACKAGE+'/.MainActivity');deadline=time.monotonic()+50
while True:
 _,nodes=ui.xml()
 if any(n.get('class')=='android.widget.EditText' for n in nodes) and any(n.get('content-desc')=='预览此范围' for n in nodes):break
 assert time.monotonic()<deadline
ui.snap('01-new-app-old-service-library');ui.choose('查看进度');nodes=ui.snap('02-old-service-root-progress');labels=[n.get('content-desc') or n.get('text') or '' for n in nodes];text='\n'.join(labels);assert '视频目录' in text and '图包目录' in text;assert not any(s in ['扫描此目录','正在扫描'] for s in labels);print(text,flush=True)
(ui.L/'old-native-first-read.json').write_text(json.dumps({'normal_code':25,'actual_apk_sha256':checks['normal_code25']['sha256'],'old_service_source':'b79da7b9c4d2ab099c055b8eb855904e32abb0a5','cold_new_library':True,'no_scoped_scan_button':True,'visible_root_labels':labels},ensure_ascii=False,indent=2)+'\n')

import sys,json,subprocess,time,shutil
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));from driver import *
import runpy
ROOT=OUT.parent.parent
x=runpy.run_path(str(OUT/'lab.py'));device('shell','am','force-stop',PACKAGE);assert subprocess.run([ADB,'-s',SERIAL,'shell','pidof',PACKAGE],capture_output=True).returncode!=0
# Close only this stage's owned profile, after preserving its log/process identity.
cmd=subprocess.check_output(['ps','-p','63606','-o','command='],text=True).strip();assert ' -avd video_viewer_upgrade_36 ' in cmd and ' -port 5556 ' in cmd
shutil.copyfile(ROOT/'.dev/logs/emulator-5556.log',OUT/'emulator-final.log');device('emu','kill')
for _ in range(100):
 if subprocess.run(['kill','-0','63606'],capture_output=True).returncode!=0:break
 time.sleep(.2)
else:raise RuntimeError('Owned emulator did not close')
cid=json.loads((OUT/'owner.json').read_text())['container'];runtime=json.loads(subprocess.check_output(['docker','inspect',cid],text=True))[0];assert runtime['Config']['Labels']['video-viewer.lab']=='lf8-app-rollback';assert any(m['Destination']=='/data' and m['Source']==str(x['DATA']) for m in runtime['Mounts'])
subprocess.run(['docker','stop','--time','15',cid],capture_output=True,check=True);(OUT/'server-final.log').write_bytes(subprocess.check_output(['docker','logs',cid],stderr=subprocess.STDOUT));x['save']('stopped-final-projection.json',x['tables'](x['DATA']/'library.sqlite3',stopped=True));subprocess.run(['docker','rm',cid],capture_output=True,check=True);assert subprocess.run(['docker','inspect',cid],capture_output=True).returncode!=0
names=['video-viewer-server-1','video-viewer-client-e2e-server-1','video-viewer-archive-app-lf7','video-viewer-history-purge-app-lf7'];after=subprocess.check_output(['docker','inspect','--format','{{.Id}} {{.Name}} {{.State.Running}}',*names]);assert after==(OUT/'services-before.txt').read_bytes();(OUT/'services-after.txt').write_bytes(after)
for folder,name in [(x['DONOR'],'donor'),(x['MEDIA'],'videos'),(x['PACKS'],'packs')]:assert x['tree'](folder)==json.loads((OUT/(name+'-before.json')).read_text())
save('cleanup.json',{'owned_container':cid,'removed':True,'owned_emulator_pid':63606,'owned_emulator_command':cmd,'emulator_closed':True,'original_four_services_unchanged':True,'donor_unchanged':True,'videos_unchanged':True,'packs_unchanged':True,'phone_nas_untouched':True})
print('cleanup passed')

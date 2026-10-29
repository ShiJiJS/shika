import hashlib,json,shlex,subprocess,time
from pathlib import Path
R=Path('/Users/jiangxinyi/Documents/Project/video-viewer');O=R/'.dev/lf8-preview4/native';ADB=R/'.dev/android-sdk/platform-tools/adb'
def run(args):return subprocess.check_output([str(v) for v in args],text=True,timeout=30).strip()
def device(*args):return run([ADB,'-s','emulator-5556',*args])
cmd=run(['ps','-p','45511','-o','command=']);assert ' -avd video_viewer_upgrade_36 ' in cmd and ' -no-audio ' in cmd
original=json.loads((O/'original-device').read_text());result={'reason':'user requested stop before final delivery','owned_qemu':45511}
device('shell','am','force-stop','io.github.shijijs.video_viewer')
for key,orig in [('window_animation_scale','window'),('transition_animation_scale','transition'),('animator_duration_scale','animator')]:
 value=original[orig];device('shell','settings','delete' if value=='null' else 'put','global',key,*([] if value=='null' else [value]));assert device('shell','settings','get','global',key)==value
for key,orig in [('font_scale','font'),('user_rotation','rotation'),('accelerometer_rotation','accel')]:
 value=original[orig];device('shell','settings','put','system',key,value);assert device('shell','settings','get','system',key)==value
value=original['immersive'];device('shell','settings put secure immersive_mode_confirmations '+shlex.quote(value));assert device('shell','settings','get','secure','immersive_mode_confirmations')==value
assert device('shell','wm','size')==original['size'];assert device('shell','wm','density')==original['density'];result['settings_restored']=True
result['emulator_shutdown']=device('emu','kill')
end=time.monotonic()+15
while subprocess.run(['ps','-p','45511'],stdout=subprocess.DEVNULL).returncode==0:
 assert time.monotonic()<end;time.sleep(.2)
meta=json.loads((O/'runtime.json').read_text());name='video-viewer-preview4-native';c=json.loads(run(['docker','inspect',name]))[0];assert c['Id']==meta['container'];assert c['Config']['Labels']['video-viewer.lab']=='lf8-preview4-native';run(['docker','stop','--time','10',name]);run(['docker','rm',name]);result['owned_container_removed']=c['Id']
for name,identity in meta['original_containers'].items():
 c=json.loads(run(['docker','inspect',name]))[0];assert c['Id']==identity and c['State']['Running'];assert c['State']['Health']['Status']=='healthy'
result['original_containers_preserved']=meta['original_containers']
donor=Path(meta['donor'])/'data'
for p,h in meta['donor_hashes'].items():assert hashlib.sha256((donor/p).read_bytes()).hexdigest()==h,p
result['donor_hashes_preserved']=True;result['all_lab_data_and_apks_retained']=True
(O.parent/'stop-cleanup.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))

import hashlib
import json
import subprocess
import time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
LAB=ROOT/'.dev/lf8-native-reduced-motion'
ADB=ROOT/'.dev/android-sdk/platform-tools/adb'
RUNTIME=json.loads((LAB/'native-9-current-elements/runtime.json').read_text())

def run(args):
    return subprocess.check_output([str(a) for a in args], text=True)

def save(name, value):
    (LAB/name).write_text(json.dumps(value,indent=2)+'\n')

assert json.loads((LAB/'audit.json').read_text())['passed_cases']==18
actual=json.loads(run(['docker','inspect','video-viewer-native-motion']))[0]
assert actual['Id']==RUNTIME['container'] and actual['Config']['Labels']['video-viewer.lab']=='lf8-native-reduced-motion'
counts=run(['docker','exec','video-viewer-native-motion','python','-c',"import sqlite3,json; c=sqlite3.connect('file:/data/library.sqlite3?mode=ro',uri=True); names=['videos','packs','playback_rounds','pack_sessions','pack_progress','tags','pack_tag_definitions']; result={n:c.execute('select count(*) from '+n).fetchone()[0] for n in names}; c.close(); print(json.dumps(result))"])
save('catalog-after-counts.json',json.loads(counts))
restoration=json.loads((LAB/'native-9-current-elements/restoration.json').read_text())
assert not restoration.get('failure')
original=json.loads((LAB/'native-9-current-elements/original-settings.json').read_text())
for group,table in [('scales','global'),('system','system'),('secure','secure')]:
    for key,value in original[group].items():
        assert run([ADB,'-s','emulator-5558','shell','settings','get',table,key]).strip()==value
for key,value in original['display'].items():
    assert run([ADB,'-s','emulator-5558','shell','wm',key]).strip()==value
assert run([ADB,'-s','emulator-5558','emu','avd','name']).splitlines()[0]=='video_viewer_reader_perf_36'
pid=str(RUNTIME['emulator_pid'])
command=run(['ps','-p',pid,'-o','command='])
assert 'qemu-system-aarch64-headless' in command and '-avd video_viewer_reader_perf_36' in command and '-port 5558' in command
shutdown=run([ADB,'-s','emulator-5558','emu','kill'])
end=time.monotonic()+30
while subprocess.run(['kill','-0',pid],capture_output=True).returncode==0:
    assert time.monotonic()<end,'Owned emulator has not exited'
    time.sleep(.2)
run(['docker','stop',RUNTIME['container']])
run(['docker','rm',RUNTIME['container']])
remaining=json.loads(run(['docker','inspect',*('video-viewer-client-e2e-server-1','video-viewer-history-purge-app-lf7','video-viewer-archive-app-lf7','video-viewer-server-1')]))
expected={line.split()[1]:line.split()[0] for line in RUNTIME['original_containers'].splitlines()}
checks=[]
for item in remaining:
    name=item['Name'].lstrip('/')
    assert item['Id'].startswith(expected[name]) and item['State']['Running'] and item['State']['Health']['Status']=='healthy'
    checks.append({'name':name,'id':item['Id'],'health':item['State']['Health']['Status']})
donor=ROOT/'.dev/lf8-preview3/native/data'
for item in remaining:
    for mount in item['Mounts']:
        source=Path(mount['Source'])
        assert donor!=source and source not in donor.parents
observed={str(p.relative_to(donor)):hashlib.sha256(p.read_bytes()).hexdigest() for p in donor.rglob('*') if p.is_file()}
assert observed==RUNTIME['donor_hashes']
save('cleanup.json',{'owned_emulator_pid':int(pid),'owned_emulator_absent':True,'shutdown_receipt':shutdown,'owned_container_removed':RUNTIME['container'],'original_services':checks,'donor_data_unchanged':True,'donor_files':len(observed),'settings_restored':original,'lab_data_retained':True,'sdk_or_host_audio_settings_changed':False})
print('Owned resources closed; exact settings, four services and donor hashes verified')

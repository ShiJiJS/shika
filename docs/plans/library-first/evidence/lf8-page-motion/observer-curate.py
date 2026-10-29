import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
LAB=ROOT/'.dev/lf8-page-motion'
PUBLIC=ROOT/'docs/plans/library-first/evidence/lf8-page-motion'
ATTEMPTS=['native-1','native-2-observer','native-3-controller','native-4-layout']

def read(p):return json.loads(p.read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v):p.write_text(json.dumps(v,indent=2)+'\n')
assert not PUBLIC.exists()
assert read(LAB/'audit.json')['passed_cases']==48
assert read(LAB/'cleanup.json')['owned_emulator_absent']
assert '+687: All tests passed!' in (LAB/'client-tests-observer.log').read_text()
assert 'No issues found!' in (LAB/'analyze-layout.log').read_text()
assert not subprocess.check_output(['git','diff','--name-only','8dbb703f','--','services/server']).strip()
PUBLIC.mkdir()
requests=[json.loads(line) for line in (LAB/'native-1/trace/requests.jsonl').read_text().splitlines()]
for name in ATTEMPTS:
    src,dst=LAB/name,PUBLIC/name;dst.mkdir()
    for p in src.iterdir():
        if p.is_file() and (p.suffix in ['.json','.xml','.png','.mp4'] or p.name.endswith('-window.txt')):shutil.copyfile(p,dst/p.name)
    source,result=read(src/'source.json'),read(src/'result.json')
    window=[v for v in requests if source['started_at']<=v['time']<=result['finished_at']]
    (dst/'requests-window.jsonl').write_text(''.join(json.dumps(v)+'\n' for v in window))
    provenance={}
    for filename in ['emulator.log','flutter-drive.log']:
        p=src/filename
        if not p.exists():continue
        raw=p.read_bytes();content=raw.decode(errors='replace')
        if filename=='emulator.log':
            lines=content.splitlines();kept=[l for l in lines if 'Sending adb public key' not in l and 'qemu.adb.pubkey=' not in l];count=len(lines)-len(kept);content='\n'.join(kept)+'\n'
        else:content,count=re.subn(r'(?:https?|wss?)://(?:127\.0\.0\.1|localhost|\[::1\]):\d+/[^\s]+','<redacted-local-vm-service>',content)
        target=dst/filename.replace('.log','.redacted.log');target.write_text(content)
        provenance[filename]={'original_sha256':hashlib.sha256(raw).hexdigest(),'redacted_sha256':sha(target),'redaction_count':count}
    save(dst/'log-provenance.json',provenance)
for name in ['before-source.json','before-test.dart','before-tests.log','after-entry-tests.log','page-tests.log','page-tests-final.log','client-tests.log','client-tests-observer.log','analyze-layout.log','cleanup.json','audit.json','catalog-after-counts.json','profile-artifact.json','profile-artifact-observer.json','profile-artifact-controller.json','profile-artifact-layout.json']:
    shutil.copyfile(LAB/name,PUBLIC/('before-test.dart.txt' if name=='before-test.dart' else name))
for name in ['prepare.py','run.py','run-observer.py','run-controller.py','run-layout.py','audit.py','cleanup.py','curate.py']:
    shutil.copyfile(LAB/name,PUBLIC/('observer-'+name))
artifacts=read(ROOT/'.dev/lf8-preview3/build-1/result.json');normal={}
for kind in ['forward','rollback']:
    v=artifacts[kind];assert sha(Path(v['path']))==v['sha256'];normal[kind]={'filename':Path(v['path']).name,'sha256':v['sha256']}
source={'source':(LAB/'source-ref').read_text().strip(),'page_implementation_source':'871a08b2e40e63976ff83d53511639796b0024f0','navigator_observer_source':'fa11bc1fb2794d15f16061b03f5415376f602ee5','base':'8dbb703f2e1f89786d928c9e709a9e4b5a0f59ab','prototype_tree':subprocess.check_output(['git','rev-parse','HEAD:design/reference/library-first'],text=True).strip(),'normal_code9_artifacts_unchanged':normal,'normal_code9_contains_this_fix':False,'full_client_tests':687,'normal_release_acceptance':False,'phone_or_nas_acceptance':False,'all_attempts_preserved':ATTEMPTS}
assert source['prototype_tree']=='1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
assert sha(PUBLIC/'before-test.dart.txt')==read(PUBLIC/'before-source.json')['test_sha256']
save(PUBLIC/'source.json',source)
print('Curated native page-motion evidence; README and manifest still required')

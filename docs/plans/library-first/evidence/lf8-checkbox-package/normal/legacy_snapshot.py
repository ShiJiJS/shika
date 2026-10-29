import json,subprocess,sys
from pathlib import Path
from snapshot_all import CODE
L=Path(__file__).resolve().parent.parent;O=L/'legacy'
def snapshot(name):
 p=O/(name+'-catalog.json');assert not p.exists();m=json.loads((O/'runtime.json').read_text());raw=subprocess.check_output(['docker','exec',m['container'],'python','-c',CODE],timeout=20);p.write_bytes(raw);v=json.loads(raw);print(json.dumps({'legacy_snapshot':name,'tables':len(v['tables'])}));return v
if __name__=='__main__':snapshot(sys.argv[1])

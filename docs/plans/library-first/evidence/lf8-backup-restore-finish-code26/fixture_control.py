import json, subprocess
from pathlib import Path

def write(path, value):
    path=Path(path)
    if path.parent.name=='control' and path.name=='executor.json':
        runtime=json.loads((path.parent.parent/'runtime.json').read_text())
        code="import os,json,pathlib,sys; p=pathlib.Path('/control/executor.json'); tmp=p.with_name('executor.guest-incoming'); data=json.loads(sys.argv[1]); f=tmp.open('w'); json.dump(data,f); f.flush(); os.fsync(f.fileno()); f.close(); os.replace(tmp,p)"
        subprocess.run(['docker','exec',runtime['id'],'python','-c',code,json.dumps(value)],check=True,capture_output=True)
        return
    incoming=path.with_suffix(path.suffix+'.incoming')
    incoming.write_text(json.dumps(value));incoming.replace(path)

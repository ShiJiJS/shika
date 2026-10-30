import json,subprocess
from pathlib import Path
L=Path(__file__).resolve().parent
CODE="""import sqlite3,json,sys
c=sqlite3.connect('file:/data/library.sqlite3?mode=ro',uri=True);c.row_factory=sqlite3.Row
row=c.execute('SELECT p.*,g.ordinal AS page_ordinal FROM pack_progress p LEFT JOIN pack_pages g ON g.id=p.page_id AND g.pack_id=p.pack_id WHERE p.pack_id=?',(sys.argv[1],)).fetchone();print(json.dumps(dict(row) if row else None));c.close()
"""
def progress():
 pack=json.loads((L/'catalog-before.json').read_text())['long_pack']['id'];runtime=json.loads((L/'runtime.json').read_text());return json.loads(subprocess.check_output(['docker','exec',runtime['id'],'python','-c',CODE,pack],text=True))
def trace():
 p=L/'requests.jsonl'
 return [json.loads(line) for line in p.read_text().splitlines() if line.strip()] if p.exists() else []
def mem(name):
 adb=L.parents[1]/'.dev/android-sdk/platform-tools/adb';raw=subprocess.check_output([str(adb),'-s','emulator-5554','shell','dumpsys','meminfo','io.github.shijijs.video_viewer'],text=True);(L/(name+'-meminfo.txt')).write_text(raw);return raw

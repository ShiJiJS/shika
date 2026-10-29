"""Offline read-only verification; no SQLite, device, or HTTP access."""
import hashlib,json
from pathlib import Path
E=Path(__file__).resolve().parent;read=lambda n:json.loads((E/n).read_text());m=read('manifest.json')['inputs']
for n,v in m.items():
 p=E/n;assert p.stat().st_size==v['bytes'] and hashlib.sha256(p.read_bytes()).hexdigest()==v['sha256'],n
source=read('legacy-source-proof.json');assert source['all_python_source_files_match'] and len(source['files'])==24;assert 'capabilities' not in read('legacy/service-proof.json')['info']
a=read('legacy/before-menus-catalog.json');assert len(a['tables'])==14
for n in ['after-normal-cancel','after-normal-details-review','after-reduced-cancel','after-reduced-details-review','after-menus']:
 b=read('legacy/'+n+'-catalog.json');assert a['tables']==b['tables'] and a['opaque_table_digests']==b['opaque_table_digests'] and a['setting_key_sha256']==b['setting_key_sha256']
end=read('legacy/after-menus-catalog.json')['observed_at'];trace=[json.loads(x) for x in (E/'legacy/trace/requests.jsonl').read_text().splitlines()];requests=[r for r in trace if a['observed_at']<r['time']<=end];assert len(requests)==19 and all(r['method'] in ['GET','HEAD'] and 200<=r['status']<300 for r in requests)
a=read('modern/before-away-catalog.json');b=read('modern/after-return-catalog.json');assert len(a['tables'])==35 and a['tables']==b['tables'] and a['setting_key_sha256']==b['setting_key_sha256'];assert b['opaque_table_digests']['access_tokens']['rows']==a['opaque_table_digests']['access_tokens']['rows']+1
assert read('ui/entering-modern-preferences.json')==read('ui/returned-modern-preferences.json')
a=read('ui/entering-modern-package.json');b=read('ui/returned-modern-package.json')
for k in ['appId','dataDir','firstInstallTime','versionCode','versionName']:assert a[k]==b[k]
a=read('initial-app-data-digests.json');b=read('after-reconcile-app-data-digests.json');assert {k for k in a.keys()|b.keys() if a.get(k)!=b.get(k)}=={'/data/user/0/io.github.shijijs.video_viewer/cache/oat_primary/arm64/base.art'}
assert read('installed-apk.json')['sha256']=='d05d83d792c14de2ff66b919fd9f987c84ddd9245633f0acc40399c18221bea8';assert read('audit.json')['complete'] and read('cleanup.json')['complete']
print(f'{len(m)} immutable inputs verified; original-service home menus, modern return and cleanup passed')

"""Read-only verification of the source/widget phase; no Android claim."""
import hashlib,json
from pathlib import Path
E=Path(__file__).resolve().parent;read=lambda n:json.loads((E/n).read_text());m=read('manifest.json')
for n,v in m['inputs'].items():
 p=E/n;assert p.stat().st_size==v['bytes'] and hashlib.sha256(p.read_bytes()).hexdigest()==v['sha256'],n
a=read('source-audit.json');assert a['source']==m['source'] and a['full_client_tests']==777 and a['targeted_tests']==11 and a['static_rgba_configurations']==96
assert '+777: All tests passed!' in (E/'client-tests.log').read_text()
assert '+11: All tests passed!' in (E/'target-4.log').read_text()
assert 'No issues found!' in (E/'analyze-2.log').read_text()
for mode in ['ordinary','reduced','live']:assert 'ACTUAL trash '+mode in (E/'diagnostic-1.log').read_text()
assert '+0 -3: Some tests failed.' in (E/'diagnostic-1.log').read_text()
assert 'setState() or markNeedsBuild() called during build' in (E/'original-disable-diagnostic.log').read_text()
assert a['not_native_or_normal_app_business_acceptance']
print(str(len(m['inputs']))+' inputs verified; 11 targeted / 96 RGBA / 777 full / analyze passed; native and normal-package checks pending')

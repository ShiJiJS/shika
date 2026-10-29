import json,re
from pathlib import Path
import driver
L=Path(__file__).resolve().parent.parent
read=lambda n:json.loads((L/n).read_text())
a=read('initial-app-data-digests.json');b=read('after-reconcile-app-data-digests.json');changed={k for k in a.keys()|b.keys() if a.get(k)!=b.get(k)};assert changed=={'/data/user/0/io.github.shijijs.video_viewer/cache/oat_primary/arm64/base.art'};assert all(v==b[k] for k,v in a.items() if k not in changed)
package=driver.package_state('entering-modern');old=(L/'initial-package-missing.txt').read_text()
for k in ['appId','dataDir','firstInstallTime']:assert package[k]==re.search(r'\b'+k+r'=([^\n]+)',old).group(1).strip()
assert package['versionCode'].split()[0]=='16';path=driver.device('shell','pm','path',driver.PACKAGE).decode().strip();sha=driver.device('shell','sha256sum',path.removeprefix('package:')).decode().split()[0];assert sha=='d05d83d792c14de2ff66b919fd9f987c84ddd9245633f0acc40399c18221bea8';driver.appearance('entering-modern')
v={'package':driver.PACKAGE,'sha256':sha,'normal_main_preview10':True,'initial_pkg_null_missing_code_path':True,'initial_data_directory_retained':True,'reinstall_r':True,'installer_success_assertion_reached':True,'installer_stdout_not_retained':True,'same_appid_data_dir_first_install_time':True,'noncache_data_files_sha256_unchanged':len(b),'only_removed_art_cache':sorted(changed),'initial_full_file_equality_observer_failed_on_art_cache':True,'no_uninstall_or_clear':True,'not_an_independent_new_upgrade_cycle_proof':True,'cause_not_diagnosed':True};(L/'installed-apk.json').write_text(json.dumps(v,indent=2)+'\n');print(json.dumps(v))

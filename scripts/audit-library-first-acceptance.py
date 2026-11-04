#!/usr/bin/env python3
"""Read-only acceptance provenance audit. No service/device/database access.

--write updates only the named report. Hash equality locates reusable evidence;
it does not turn historical screenshots or test counts into product acceptance.
"""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLAN = ROOT / 'docs/plans/library-first'
EVIDENCE = PLAN / 'evidence'
APP = '12d6ca67ef3a8b307894468923dc08e612e02587'
SERVER = 'b79da7b9c4d2ab099c055b8eb855904e32abb0a5'
PROTOTYPE = '1cbf605af8f03fa067a4ce8e914bb809e3a487ca'

def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])

def digest(p):
    h = hashlib.sha256()
    with p.open('rb') as f:
        for block in iter(lambda: f.read(1048576), b''):
            h.update(block)
    return h.hexdigest()

def tree(ref, path):
    return git('rev-parse', ref + ':' + path).decode().strip()

FAMILIES = {
    'scanner': (SERVER, 'lf8-upgrade-rollback',
                ['services/server/shika/pack_scanner.py', 'services/server/shika/images.py', 'services/server/shika/pack_api.py'],
                ['services/server/tests/test_packs.py', 'services/server/tests/test_pack_continuation.py']),
    'navigation': ('a8d6180a', 'lf8-current-navigation',
                   ['app/media_workspace.dart', 'features/library/browse_context.dart', 'features/library/library_query_controller.dart', 'features/library/pack_query_controller.dart'],
                   ['media_workspace_widget_test.dart', 'catalog_entry_focus_test.dart']),
    'tags': ('6f7ce972', 'lf8-video-tag-definitions',
             ['ui/media_tag_editor.dart', 'features/library/tag_catalog_page.dart', 'features/library/catalog_selection.dart'],
             ['tag_catalog_paging_widget_test.dart', 'server_catalog_selection_test.dart']),
    'preview': ('98507ea7', 'lf8-preview-lifecycle',
                ['features/preview/video_preview_route.dart', 'ui/player.dart', 'ui/device_controls.dart', 'library/server_repository.dart'],
                ['fixed_preview_widget_test.dart', 'player_lifecycle_test.dart', 'preview_exit_lifecycle_test.dart']),
    'reader': ('81a11a98', 'lf8-reader-performance',
               ['features/packs/pack_reader_page.dart', 'features/packs/pack_reading_session.dart', 'features/packs/reader_images.dart', 'library/server_pack_reading.dart'],
               ['pack_reading_session_test.dart', 'pack_reader_widget_test.dart', 'pack_reader_image_error_test.dart']),
    'trash': ('88a45eca', 'lf8-trash-management',
              ['library/pack_files.dart', 'library/server_pack_trash.dart', 'features/packs/pack_file_action.dart', 'features/packs/pack_trash_page.dart'],
              ['pack_file_action_test.dart', 'pack_reader_cleanup_widget_test.dart', 'pack_trash_widget_test.dart']),
    'purge': ('35a29d4f', 'lf8-purge-management',
              ['library/pack_purge.dart', 'library/server_pack_purge.dart', 'features/packs/pack_purge_review.dart', 'features/packs/pack_purge_result.dart'],
              ['pack_purge_test.dart', 'pack_purge_widget_test.dart', 'pack_purge_selections_test.dart']),
    'settings': ('81b598f5', 'lf8-settings-forms',
                 ['features/settings/default_settings_session.dart', 'features/settings/default_settings_sheet.dart', 'features/settings/media_root_sheet.dart', 'ui/preferences.dart', 'ui/home.dart'],
                 ['default_settings_session_test.dart', 'default_settings_widget_test.dart', 'connection_widget_test.dart', 'media_root_sheet_test.dart']),
    'backup': ('848a1b8a', 'lf8-backup-upload-diagnostics',
               ['library/management_archives.dart', 'library/server_archive_backups.dart', 'library/backup_document.dart', 'library/backup_work_store.dart', 'features/settings/archive_backup_page.dart'],
               ['server_archive_backups_test.dart', 'archive_backup_widget_test.dart', 'archive_upload_connection_recovery_test.dart']),
    'compatibility': ('12d6ca67', 'lf8-current-filters',
                      ['library/credentials.dart', 'library/scoped_journal.dart', 'library/server_repository.dart'],
                      ['preferences_test.dart', 'scoped_journal_test.dart', 'backup_capabilities_test.dart']),
    'visual': ('701fb7da', 'lf8-paper-symbols',
               ['ui/paper.dart', 'ui/paper_icons.dart', 'ui/media_layout.dart', 'ui/paper_menu.dart', 'ui/paper_dropdown.dart', 'ui/paper_checkbox.dart', 'ui/paper_notice.dart'],
               ['media_workspace_widget_test.dart', 'pack_reader_settings_semantics_test.dart', 'checkbox_motion_diagnostic_test.dart', 'menu_motion_test.dart', 'notice_motion_test.dart']),
}

# Each original requirement remains literal; these are workflow owners, not passes.
BINDINGS = {
 'NAV-01':('navigation','R7 R8'), 'NAV-02':('navigation','R5 R8'), 'NAV-03':('navigation','R5 R8'),
 'LIB-01':('navigation','R5 R6 R8'), 'LIB-02':('reader','R4 R5 R6 R8'), 'LIB-03':('navigation','R5 R8'),
 'TAG-01':('tags','R5 R8'), 'TAG-02':('tags','R5 R8'),
 'PRE-01':('preview','R3 R5 R8'), 'PRE-02':('preview','R3 R8'), 'PRE-03':('preview','R3 R5 R8'), 'PRE-04':('preview','R3 R8'), 'PRE-05':('preview','R3 R8'),
 'PKG-01':('scanner','R4 R8'), 'PKG-02':('scanner','R4 R8'), 'PKG-03':('scanner','R4 R8'),
 'READ-01':('reader','R4 R6 R8'), 'READ-02':('reader','R4 R8'), 'READ-03':('reader','R2 R4 R8'), 'READ-04':('reader','R4 R8'), 'READ-05':('reader','R4 R8'), 'READ-06':('reader','R4 R8'),
 'REC-01':('navigation','R1 R3 R8'),
 'DEL-01':('trash','R1 R8'), 'DEL-02':('trash','R1 R8'), 'DEL-03':('trash','R1 R8'), 'DEL-04':('trash','R1 R8'), 'DEL-05':('purge','R1 R8'), 'DEL-06':('trash','R1 R2 R8'),
 'SET-01':('settings','R2 R6 R8'), 'SET-02':('settings','R2 R3 R8'), 'SET-03':('settings','R2 R7 R8'), 'SET-04':('settings','R4 R7 R8'), 'SET-05':('settings','R1 R2 R8'),
 'BAK-01':('backup','R2 R8'), 'BAK-02':('backup','R2 R8'), 'BAK-03':('backup','R2 R8'),
 'UP-01':('compatibility','R7 R8'), 'UP-02':('compatibility','R7 R8 R9'),
 'UI-01':('visual','R6 R8'), 'UI-02':('visual','R1 R3 R4 R6 R8'), 'UI-03':('visual','R2 R6 R8'), 'UI-04':('visual','R1 R2 R5 R6 R8'), 'UI-05':('visual','R6 R8'), 'UI-06':('visual','R6 R8'),
}

def manifest_files(folder):
    data = json.loads((folder / 'manifest.json').read_text())
    values = data.get('files', data)
    assert isinstance(values, dict)
    result = {}
    for name, entry in values.items():
        expected = entry.get('sha256') if isinstance(entry, dict) else entry
        if isinstance(expected, str) and re.fullmatch(r'[a-f0-9]{64}', expected):
            p = folder / name
            assert p.resolve().is_relative_to(folder.resolve()) and not p.is_symlink()
            assert p.is_file() and digest(p) == expected, str(p)
            result[name] = expected
    assert result
    return result

def audit():
    assert not git('status', '--porcelain', '--untracked-files=all', '--',
                   'apps/mobile', 'services/server', 'design/reference/library-first').strip(), 'Uncommitted product sources'
    current = json.loads((PLAN / 'INTEGRATED-CHECKLIST.json').read_text())
    assert len(current['items']) == len(BINDINGS) == 45
    assert set(x['id'] for x in current['items']) == set(BINDINGS)
    original = {}
    for line in (PLAN / 'ACCEPTANCE.md').read_text().splitlines():
        parts = [p.strip() for p in line.strip().strip('|').split('|')]
        if len(parts) in [3, 4] and re.fullmatch(r'[A-Z]+-\d\d', parts[0]):
            original[parts[0]] = parts
    assert set(original) == set(BINDINGS)
    for item in current['items']:
        row = original[item['id']]
        assert item['reference_state'] == row[1] and item['requirement'] == row[2]
        assert item['owner'] == (row[3] if len(row) == 4 else 'LF8')
    assert current['candidate_code'] == 22 and current['candidate_source'] == APP
    assert tree('HEAD','apps/mobile') == tree(APP,'apps/mobile')
    assert tree('HEAD','services/server') == tree(SERVER,'services/server')
    assert tree('HEAD','design/reference/library-first') == PROTOTYPE
    runtime = json.loads((EVIDENCE / 'lf8-upgrade-rollback/runtime-source.json').read_text())
    assert runtime['source'] == SERVER and len(runtime['files']) == 73
    server_files = {}
    for name, expected in runtime['files'].items():
        p = ROOT / 'services/server' / name
        assert digest(p) == expected, name
        server_files[name] = expected
    checks = json.loads((EVIDENCE / 'lf8-upgrade-rollback/checks.json').read_text())
    assert checks['source'] == SERVER and checks['server_tests'] == 462 and checks['server_test_exit'] == 0
    for name, expected in checks['logs'].items():
        assert digest(EVIDENCE / 'lf8-upgrade-rollback' / name) == expected
    assert '462 passed' in (EVIDENCE / 'lf8-upgrade-rollback/server-full.log').read_text()
    test_log = EVIDENCE / 'lf8-acceptance-audit/current22-flutter-test.log'
    assert '+791: All tests passed!' in test_log.read_text()
    context = json.loads((test_log.parent / 'test-context.json').read_text())
    assert context['app_source'] == APP and context['candidate_code'] == 22
    assert context['app_tree'] == tree(APP, 'apps/mobile')
    assert context['test_tree'] == tree(APP, 'apps/mobile/test')
    assert context['exit_code'] == 0 and context['passed'] == 791
    assert context['log_sha256'] == digest(test_log)
    families = {}
    for name, (ref, evidence, entries, tests) in FAMILIES.items():
        ref = git('rev-parse', ref + '^{commit}').decode().strip()
        assert (EVIDENCE / evidence / 'README.md').is_file(), evidence
        entry_rows = []
        for relative in entries:
            path = relative if relative.startswith('services/') else 'apps/mobile/lib/' + relative
            assert (ROOT / path).is_file(), path
            old = git('show', ref + ':' + path)
            now = (ROOT / path).read_bytes()
            entry_rows.append({'path':path, 'baseline_sha256':hashlib.sha256(old).hexdigest(),
                               'current_sha256':hashlib.sha256(now).hexdigest(), 'same':old == now})
        test_rows = []
        for file in tests:
            path = file if file.startswith('services/') else 'apps/mobile/test/' + file
            assert (ROOT / path).is_file(), path
            test_rows.append({'path':path, 'sha256':digest(ROOT / path)})
        business_changed = git('diff','--name-only',ref,APP,'--','apps/mobile/lib/library').decode().splitlines()
        ui_changed = git('diff','--name-only',ref,APP,'--','apps/mobile/lib/app','apps/mobile/lib/features','apps/mobile/lib/ui').decode().splitlines()
        families[name] = {'baseline_source':ref, 'historical_evidence':'evidence/' + evidence + '/README.md',
                          'code_entries':entry_rows, 'tests':test_rows,
                          'changed_library_files':business_changed, 'changed_ui_files':ui_changed,
                          'does_not_establish_transitive_ui_or_target_acceptance':True}
    records = {}
    for name in ['lf8-current-navigation','lf8-current-filters','lf8-catalog-recovery','lf8-upgrade-rollback','lf8-backup-upload-diagnostics','lf8-tag-assignment']:
        folder = EVIDENCE / name
        hashes = manifest_files(folder)
        records[name] = {'manifest_sha256':digest(folder / 'manifest.json'),
                         'checked_file_count':len(hashes),'verification_scope':'fixed_file_integrity_only'}
    rows = []
    for item in current['items']:
        family, work = BINDINGS[item['id']]
        rows.append({**{k:item[k] for k in ['id','reference_state','requirement','owner']},
                     'implementation_and_test_family':family, 'remaining_workflows':work.split(),
                     'current_candidate_status':item['current_candidate'],
                     'existing_current_observations':item['observations'],
                     'full_target_acceptance':'not_proven'})
    return {'candidate_code':22,'candidate_source':APP,'app_tree':tree(APP,'apps/mobile'),
            'original_requirements_sha256':digest(PLAN / 'ACCEPTANCE.md'),
            'server_source':SERVER,'server_tree':tree(SERVER,'services/server'),
            'server_runtime_files':server_files,'server_test_count_reused':462,
            'server_suite_rerun_this_audit':False,'current_client_tests':791,
            'current_client_log_sha256':digest(test_log),'prototype_tree':PROTOTYPE,
            'families':families,'historical_record_integrity':records,'requirements':rows,
            'whole_acceptance_ids_passed':0,'scope_preserved':True}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    parser.add_argument('--report', type=Path, default=PLAN / 'ACCEPTANCE-COVERAGE.json')
    args = parser.parse_args()
    result = audit()
    if args.write:
        args.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    else:
        assert json.loads(args.report.read_text()) == result, 'Audit stale: inspect changes, then explicitly --write'
    print(json.dumps({'requirements':len(result['requirements']),'families':len(result['families']),
                      'server_runtime_files_unchanged':73,'current_client_tests':791,
                      'server_tests_reused_without_rerun':462,'whole_acceptance_ids_passed':0}))

if __name__ == '__main__':
    main()

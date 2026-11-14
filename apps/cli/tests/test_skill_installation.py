"""The optional skill installer must isolate dependencies and preserve existing installs."""

import importlib.util
import json
from pathlib import Path
from unittest.mock import Mock

import pytest

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location(
    "skill_install", ROOT / "skills/video-tagging/scripts/install.py"
)
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


@pytest.fixture(autouse=True)
def isolated_runtime(monkeypatch, tmp_path):
    monkeypatch.setenv("SHIKA_TAGGING_HOME", str(tmp_path / "private-runtime"))


def test_existing_unmanaged_environment_is_preserved(tmp_path):
    folder = installer.environment_paths()[0]
    folder.mkdir(parents=True)
    personal_file = folder / "keep.txt"
    personal_file.write_text("existing environment")
    with pytest.raises(ValueError, match="not owned"):
        installer.setup_cli("unused")
    assert personal_file.read_text() == "existing environment"


def test_token_in_dependency_url_is_rejected_before_install():
    with pytest.raises(ValueError, match="credentials"):
        installer.setup_cli("git+https://example-token@example.invalid/repo.git")
    assert not installer.runtime_home().exists()


@pytest.mark.parametrize("version", [None, "0.1.0", "0.1.1", "0.1.1rc1"])
def test_unavailable_or_old_cli_does_not_pass_readiness_check(version, monkeypatch, capsys):
    monkeypatch.setattr(installer, "installed_version", lambda: version)
    monkeypatch.setattr(installer.sys, "argv", ["install.py", "--check"])
    assert installer.main() == 1
    assert '"status": "ready"' not in capsys.readouterr().out


def test_readiness_uses_the_installed_runtime_even_with_old_system_python(monkeypatch, capsys):
    monkeypatch.setattr(installer.sys, "version_info", (3, 9, 6))
    monkeypatch.setattr(installer, "installed_version", lambda: "0.1.2")
    monkeypatch.setattr(installer.sys, "argv", ["install.py", "--check"])
    assert installer.main() == 0
    assert json.loads(capsys.readouterr().out)["status"] == "ready"


def test_skill_conflict_does_not_replace_existing_content(tmp_path):
    destination = tmp_path / "agent/video-tagging"
    destination.mkdir(parents=True)
    original = destination / "SKILL.md"
    original.write_text("user version")
    with pytest.raises(ValueError, match="already exists"):
        installer.validate_destination(destination.parent, update=False)
    assert original.read_text() == "user version"


def test_manual_update_backs_up_previous_skill_and_omits_runtime_files(tmp_path, monkeypatch):
    source = tmp_path / "source"
    source.mkdir()
    (source / "SKILL.md").write_text("new public skill")
    (source / ".gitignore").write_text("/runs/\n")
    (source / "manifest.json").write_text("private runtime input")
    for name in ("scripts", "assets", "references"):
        (source / name).mkdir()
    (source / "scripts/tool.py").write_text("print('tool')")
    (source / "scripts/__pycache__").mkdir()
    (source / "scripts/__pycache__/tool.pyc").write_bytes(b"cache")
    monkeypatch.setattr(installer, "SKILL", source)
    destination = tmp_path / "agent/video-tagging"
    destination.mkdir(parents=True)
    (destination / "SKILL.md").write_text("old user skill")
    installer.install_copy(installer.validate_destination(destination.parent, update=True))
    assert (destination / "SKILL.md").read_text() == "new public skill"
    backups = list((installer.runtime_home() / "skill-backups").glob("*/video-tagging/SKILL.md"))
    assert len(backups) == 1 and backups[0].read_text() == "old user skill"
    assert not (destination / "manifest.json").exists()
    assert not (destination / "scripts/__pycache__").exists()


def test_skillshare_install_keeps_the_audit_and_runs_sync(monkeypatch):
    monkeypatch.setattr(installer.shutil, "which", lambda name: "/bin/skillshare")
    monkeypatch.setattr(installer, "setup_cli", Mock(return_value=Path("isolated/shika")))
    run = Mock()
    monkeypatch.setattr(installer.subprocess, "run", run)
    monkeypatch.setattr(installer.sys, "argv", ["install.py", "--skillshare"])
    assert installer.main() == 0
    assert run.call_args_list[0].args[0] == [
        "skillshare",
        "install",
        "ShiJiJS/shika/skills/video-tagging",
        "-g",
    ]
    assert run.call_args_list[1].args[0] == ["skillshare", "sync", "-g"]


def test_direct_skill_install_does_not_require_a_skill_manager(monkeypatch, tmp_path):
    manager = Mock(side_effect=AssertionError("No global Skillshare access expected"))
    monkeypatch.setattr(installer.shutil, "which", manager)
    monkeypatch.setattr(installer, "setup_cli", Mock(return_value=Path("isolated/shika")))
    monkeypatch.setattr(
        installer.sys, "argv", ["install.py", "--skills-dir", str(tmp_path / "agent")]
    )
    assert installer.main() == 0
    manager.assert_not_called()
    copied = tmp_path / "agent/video-tagging"
    assert (copied / "SKILL.md").is_file()
    assert (copied / "scripts/extract_keyframes.py").is_file()
    assert (copied / "assets/requirements-extract.txt").is_file()


def test_failed_dependency_install_does_not_install_skill(tmp_path, monkeypatch):
    setup = Mock(side_effect=RuntimeError("install failed"))
    copy = Mock()
    monkeypatch.setattr(installer, "setup_cli", setup)
    monkeypatch.setattr(installer, "install_copy", copy)
    monkeypatch.setattr(
        installer.sys, "argv", ["install.py", "--skills-dir", str(tmp_path / "agent")]
    )
    with pytest.raises(RuntimeError, match="install failed"):
        installer.main()
    copy.assert_not_called()


def test_skillshare_update_uses_the_registered_source(monkeypatch):
    monkeypatch.setattr(installer.shutil, "which", lambda name: "/bin/skillshare")
    monkeypatch.setattr(installer, "setup_cli", Mock(return_value=Path("isolated/shika")))
    run = Mock()
    monkeypatch.setattr(installer.subprocess, "run", run)
    monkeypatch.setattr(installer.sys, "argv", ["install.py", "--skillshare", "--update"])
    assert installer.main() == 0
    assert run.call_args_list[0].args[0] == ["skillshare", "update", "video-tagging", "-g"]
    assert run.call_args_list[1].args[0] == ["skillshare", "sync", "-g"]


def test_symlinked_skill_is_left_to_its_manager(tmp_path):
    original = tmp_path / "managed"
    original.mkdir()
    target = tmp_path / "agent"
    target.mkdir()
    try:
        (target / "video-tagging").symlink_to(original, target_is_directory=True)
    except OSError:
        pytest.skip("This Windows account cannot create symlinks")
    with pytest.raises(ValueError, match="managed by a link"):
        installer.validate_destination(target, update=True)

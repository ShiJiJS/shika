"""Install the optional skill and its isolated shika CLI; no media or login access."""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import venv
from pathlib import Path
from urllib.parse import urlsplit

SKILL = Path(__file__).resolve().parents[1]
DEPENDENCIES = json.loads(
    (SKILL / "assets/dependencies.json").read_text(encoding="utf-8")
)
CLI_SOURCE = DEPENDENCIES["cli_source"]
SKILL_SOURCE = "ShiJiJS/shika/skills/video-tagging"


def runtime_home():
    configured = os.environ.get("SHIKA_TAGGING_HOME")
    if configured:
        return Path(configured).expanduser().resolve()
    if os.name == "nt":
        base = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData/Local"))
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    return base / "shika/video-tagging"


def environment_paths():
    folder = runtime_home() / "cli"
    binaries = folder / ("Scripts" if os.name == "nt" else "bin")
    return (
        folder,
        binaries / ("python.exe" if os.name == "nt" else "python"),
        binaries / ("shika.exe" if os.name == "nt" else "shika"),
    )


def installed_version():
    _, python, cli = environment_paths()
    if not python.is_file() or not cli.is_file():
        return None
    result = subprocess.run(
        [
            str(python),
            "-c",
            "from importlib.metadata import version; import rv.cli; print(version('shika-cli'))",
        ],
        capture_output=True,
        text=True,
        timeout=20,
        check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else None


def default_cli_source():
    checkout = SKILL.parent.parent / "apps/cli"
    return str(checkout) if (checkout / "pyproject.toml").is_file() else CLI_SOURCE


def compatible_cli(version):
    try:
        actual = tuple(int(part) for part in version.split("."))
        required = tuple(
            int(part) for part in DEPENDENCIES["minimum_cli_version"].split(".")
        )
        return len(actual) == 3 and actual >= required
    except (AttributeError, ValueError):
        return False


def setup_cli(source, update=False):
    if source.startswith("git+https://") and urlsplit(source[4:]).username:
        raise ValueError(
            "Use existing Git authentication; do not put credentials in the source URL"
        )
    folder, python, cli = environment_paths()
    marker = folder / ".shika-skill-environment"
    if folder.is_symlink() or (folder.exists() and not marker.is_file()):
        raise ValueError(
            "CLI directory is not owned by this installer; choose another SHIKA_TAGGING_HOME"
        )
    if compatible_cli(installed_version()) and not update:
        return cli
    folder.mkdir(parents=True, exist_ok=True)
    marker.write_text("shika-video-tagging-cli\n", encoding="utf-8")
    if not python.is_file():
        venv.EnvBuilder(with_pip=True).create(folder)
    log = runtime_home() / "cli-install.log"
    with log.open("w", encoding="utf-8") as output:
        result = subprocess.run(
            [
                str(python),
                "-m",
                "pip",
                "install",
                "--disable-pip-version-check",
                "--upgrade",
                source,
            ],
            stdout=output,
            stderr=subprocess.STDOUT,
            check=False,
        )
    if result.returncode or not compatible_cli(installed_version()):
        raise RuntimeError(f"CLI installation failed; inspect the local log: {log}")
    return cli


def validate_destination(skills_dir, update):
    destination = skills_dir.expanduser().resolve() / "video-tagging"
    if (
        destination == SKILL
        or destination in SKILL.parents
        or SKILL in destination.parents
    ):
        raise ValueError("Choose an Agent skill directory outside the source package")
    if destination.is_symlink():
        raise ValueError("Destination is managed by a link; use its skill manager")
    if destination.exists() and (not destination.is_dir() or not update):
        raise ValueError(
            "Skill already exists; review it and use --update to save a backup before replacing"
        )
    return destination


def install_copy(destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=".shika-skill-", dir=destination.parent
    ) as temporary:
        staged = Path(temporary) / "video-tagging"
        staged.mkdir()
        for name in ("SKILL.md", ".gitignore"):
            shutil.copyfile(SKILL / name, staged / name)
        for name in ("assets", "references", "scripts"):
            shutil.copytree(
                SKILL / name,
                staged / name,
                ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
            )
        backup = None
        if destination.exists():
            backup = (
                runtime_home() / "skill-backups" / str(time.time_ns()) / "video-tagging"
            )
            backup.parent.mkdir(parents=True)
            shutil.move(str(destination), str(backup))
        try:
            staged.rename(destination)
        except OSError:
            if backup:
                shutil.move(str(backup), str(destination))
            raise
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument(
        "--skillshare",
        action="store_true",
        help="Install through configured global Skillshare",
    )
    modes.add_argument(
        "--skills-dir", type=Path, help="Install to an unmanaged Agent skill directory"
    )
    modes.add_argument(
        "--cli-only",
        action="store_true",
        help="Configure the companion CLI for an already installed skill",
    )
    modes.add_argument(
        "--check", action="store_true", help="Check CLI readiness without installing"
    )
    parser.add_argument(
        "--update",
        action="store_true",
        help="Update CLI and skill; manual skill copies are backed up",
    )
    parser.add_argument(
        "--cli-source", help="Local apps/cli directory or Git package source"
    )
    parser.add_argument(
        "--skill-source", default=SKILL_SOURCE, help="Skillshare upstream source"
    )
    args = parser.parse_args()
    if sys.version_info < (3, 10):  # noqa: UP036 - check system Python before creating the CLI environment
        parser.error("Python 3.10 or newer is required")
    if args.check:
        version = installed_version()
        ready = compatible_cli(version)
        print(
            json.dumps(
                {
                    "status": "ready"
                    if ready
                    else "incompatible"
                    if version
                    else "missing",
                    "cli_version": version,
                }
            )
        )
        return 0 if ready else 1
    destination = (
        validate_destination(args.skills_dir, args.update) if args.skills_dir else None
    )
    if args.skillshare and not shutil.which("skillshare"):
        parser.error(
            "Install and configure Skillshare first, or explicitly choose --skills-dir"
        )
    cli = setup_cli(args.cli_source or default_cli_source(), args.update)
    if args.skillshare:
        command = ["skillshare", "install", args.skill_source, "-g"]
        if args.update:
            command.append("--update")
        subprocess.run(command, check=True)
        subprocess.run(["skillshare", "sync", "-g"], check=True)
    elif destination:
        install_copy(destination)
    print(
        json.dumps(
            {
                "status": "installed",
                "cli": str(cli),
                "skill": str(destination)
                if destination
                else "skillshare"
                if args.skillshare
                else None,
            }
        )
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)

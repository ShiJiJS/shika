"""Run the skill's isolated CLI without changing shell PATH or global Python."""

import subprocess
import sys

from install import compatible_cli, environment_paths, installed_version

if __name__ == "__main__":
    if not compatible_cli(installed_version()):
        print(
            "Configure the optional CLI first: python scripts/install.py --cli-only",
            file=sys.stderr,
        )
        sys.exit(1)
    sys.exit(subprocess.call([str(environment_paths()[2]), *sys.argv[1:]]))

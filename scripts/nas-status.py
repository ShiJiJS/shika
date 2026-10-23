#!/usr/bin/env python3
"""Read-only NAS check using this machine's private infos/SSH registration."""

import json
import os
import shlex
import subprocess
from pathlib import Path
from urllib.request import urlopen

home = Path.home()
registry = Path(
    os.environ.get("INFOS_LOCATION_CONFIG", home / ".config/infos/location.json")
)
root = (
    Path(os.environ["INFOS_DIR"])
    if os.environ.get("INFOS_DIR")
    else Path(json.loads(registry.read_text())["root"])
)
resources = json.loads((root / "服务器信息/信息索引.json").read_text())["resources"]
service = json.loads((root / resources["video-viewer.connection"]).read_text())
connections = json.loads((root / resources["ssh.connections"]).read_text())[
    "connections"
]
connection = connections[service["ssh_connection"]]
local = json.loads((registry.parent / "ssh-local.json").read_text())
identity = Path(
    local["identities"][connection["local_identity"]]["identity_file"]
).expanduser()
command = [
    "ssh",
    "-i",
    str(identity),
    "-p",
    str(connection["port"]),
    "-o",
    "BatchMode=yes",
    "-o",
    "IdentitiesOnly=yes",
    "-o",
    "StrictHostKeyChecking=yes",
    "-o",
    "ConnectTimeout=10",
    f"{connection['user']}@{connection['host']}",
    "sudo -n docker inspect --format '{{.Name}} {{.Config.Image}} {{.State.Status}} {{.State.Health.Status}}' "
    + shlex.quote(service["container"]),
]
subprocess.run(command, check=True)
with urlopen(service["url"].rstrip("/") + "/health", timeout=10) as response:
    print(f"NAS HTTP health: {response.status}")

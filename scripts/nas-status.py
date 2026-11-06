#!/usr/bin/env python3
"""Read-only NAS check using private infos and fnos-cli (or legacy SSH)."""

import json
import os
import shlex
import shutil
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
resource = resources.get("shika.connection") or resources["video-viewer.connection"]
service = json.loads((root / resource).read_text())
management = service.get("nas_management", {})
if management.get("transport") == "fnos-cli":
    suffix = "fnos-cli.cmd" if os.name == "nt" else "fnos-cli"
    skill_launcher = home / ".config/skillshare/skills/fnos/scripts" / suffix
    launcher = os.environ.get("FNOS_CLI") or (
        str(skill_launcher) if skill_launcher.is_file() else shutil.which("fnos-cli")
    )
    if not launcher:
        raise SystemExit("Install the fnos-cli skill or set FNOS_CLI to its launcher.")
    command = [launcher, "--profile", management["profile"]]
    for name in ("host", "port", "scheme"):
        if name in management:
            command.extend(["--" + name, str(management[name])])
    if management.get("allow_insecure_http"):
        command.append("--allow-insecure-http")
    if management.get("tls_insecure"):
        command.append("--tls-insecure")
    command.extend(["docker", "container", "inspect", service["container"]])
    inspected = json.loads(subprocess.check_output(command, text=True))
    state = inspected["State"]
    health = state.get("Health", {}).get("Status", "unavailable")
    print(f"{inspected['Name']} {inspected['Config']['Image']} {state['Status']} {health}")
    if not state.get("Running") or health != "healthy":
        raise SystemExit("NAS container is not healthy.")
else:
    connections = json.loads((root / resources["ssh.connections"]).read_text())["connections"]
    connection = connections[service["ssh_connection"]]
    local = json.loads((registry.parent / "ssh-local.json").read_text())
    identity = Path(local["identities"][connection["local_identity"]]["identity_file"]).expanduser()
    command = [
        "ssh", "-i", str(identity), "-p", str(connection["port"]),
        "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
        "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=10",
        f"{connection['user']}@{connection['host']}",
        "sudo -n docker inspect --format '{{.Name}} {{.Config.Image}} {{.State.Status}} {{.State.Health.Status}}' "
        + shlex.quote(service["container"]),
    ]
    subprocess.run(command, check=True)
with urlopen(service["url"].rstrip("/") + "/health", timeout=10) as response:
    print(f"NAS HTTP health: {response.status}")

#!/usr/bin/env python3
"""Write machine-local SDK paths; leave shared launch/tasks and unrelated settings intact."""

import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
dev = root / ".dev"
environment = {
    "VV_DEV_HOME": str(dev),
    "FLUTTER_ROOT": str(dev / "flutter"),
    "ANDROID_HOME": str(dev / "android-sdk"),
    "ANDROID_SDK_ROOT": str(dev / "android-sdk"),
    "ANDROID_USER_HOME": str(dev / "android-user"),
    "ANDROID_AVD_HOME": str(dev / "avd"),
    "JAVA_HOME": str(dev / "jdk/Contents/Home"),
    "PUB_CACHE": str(dev / "pub-cache"),
    "PUB_HOSTED_URL": "https://pub.flutter-io.cn",
    "GRADLE_USER_HOME": str(dev / "gradle"),
    "VV_SERVER_DEV_HOME": str(dev / "server"),
    "VV_E2E_HOME": str(dev / "e2e"),
}
path = (
    ":".join(
        str(dev / name)
        for name in (
            "flutter/bin",
            "android-sdk/platform-tools",
            "android-sdk/emulator",
            "android-sdk/cmdline-tools/latest/bin",
            "jdk/Contents/Home/bin",
        )
    )
    + ":/opt/homebrew/bin:/usr/local/bin:${env:PATH}"
)
settings_file = root / ".vscode/settings.json"
settings = json.loads(settings_file.read_text()) if settings_file.exists() else {}
settings.update(
    {
        "dart.flutterSdkPath": str(dev / "flutter"),
        "java.jdt.ls.java.home": environment["JAVA_HOME"],
    }
)
settings["python.defaultInterpreterPath"] = str(dev / "venv/bin/python")
settings["dart.analysisExcludedFolders"] = [str(dev), str(root / "apps/mobile/build")]
settings["python.analysis.extraPaths"] = [str(root / "services/server")]
ignored_repositories = settings.setdefault("git.repositoryScanIgnoredFolders", [])
if ".dev" not in ignored_repositories:
    ignored_repositories.append(".dev")
settings.setdefault("dart.env", {}).update(environment)
settings.setdefault("terminal.integrated.env.osx", {}).update(environment, PATH=path)
settings.setdefault("files.watcherExclude", {}).update(
    {"**/.dev/**": True, "**/build/**": True}
)
settings.setdefault("search.exclude", {}).update({".dev": True, "**/build": True})
settings_file.parent.mkdir(exist_ok=True)
settings_file.write_text(json.dumps(settings, indent=2) + "\n")
workspace = root / "Video Viewer.code-workspace"
workspace_data = (
    json.loads(workspace.read_text())
    if workspace.exists()
    else {"folders": [{"path": "."}], "settings": {}}
)
# Flutter's workspace daemon reads workspace-scoped environment in a multi-root window.
workspace_data.setdefault("settings", {}).update(settings)
workspace.write_text(json.dumps(workspace_data, indent=2) + "\n")
print("VS Code SDK paths and terminal environment configured for this checkout.")

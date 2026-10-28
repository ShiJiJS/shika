"""Three real UI transition repetitions, not a 500-page performance run."""

import json
import subprocess
import time
from pathlib import Path

import driver

OUT = Path(__file__).resolve().parent
completed = []


def require(name, *labels):
    nodes = driver.capture(name)
    value = driver.text(nodes)
    for label in labels:
        assert label in value, (name, label, value)
    return value


for cycle in range(1, 4):
    name = "host-cycle-" + str(cycle)
    driver.tap_label(name + "-library", label="媒体库")
    driver.tap_label(name + "-pack-tab", prefix="图包\n")
    driver.tap_label(name + "-continue", prefix="继续阅读\n")
    require(name + "-reader", "2 / 3", "纵向拼接")
    driver.device("shell", "input", "keyevent", "4")
    require(name + "-reader-return", "继续阅读", "Upgrade Pack")
    driver.tap_label(name + "-tags", label="标签")
    driver.tap_label(name + "-video-tags", label="视频")
    video = require(name + "-video-tag-page", "LEGACY_ONLY")
    assert "PACK_ONLY" not in video
    driver.tap_label(name + "-pack-tags", label="图包")
    packs = require(name + "-pack-tag-page", "PACK_ONLY")
    assert "LEGACY_ONLY" not in packs
    driver.tap_label(name + "-settings", label="设置")
    require(name + "-settings-page", "服务连接", "操作任务")
    prefs = driver.appearance(name)
    assert prefs["dark"] and not prefs["preloadAdjacent"]
    assert "unrelated-server-public-fixture" in prefs["defaultMigrations"]
    command = subprocess.check_output(["ps", "-p", "61904", "-o", "command="], text=True)
    assert " -avd video_viewer_upgrade_36 " in command and " -gpu host " in command
    completed.append({"cycle": cycle, "qemu_pid": 61904, "time": time.time()})
    (OUT / "host-cycles-progress.json").write_text(json.dumps({"completed": completed}, indent=2) + "\n")
    print(json.dumps({"completed_ui_cycle": cycle}), flush=True)

driver.save("host-cycles-result", {
    "passed": True, "cycles": completed, "scope": "Page2 of three-page pack, Android back, separate tags, settings; normal release APK9",
    "performance_run": False, "sdk_or_app_modified": False, "does_not_close_emulator_issue78": True,
})

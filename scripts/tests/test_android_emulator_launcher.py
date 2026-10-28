#!/usr/bin/env python3
"""CLI contract tests using an isolated synthetic SDK, not the installed SDK."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = Path(
    os.environ.get("VV_LAUNCHER_UNDER_TEST", ROOT / "scripts/start-android-emulator.sh")
)
TOOL = """#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
p=Path(os.environ['VV_TEST_STATE']);scenario=os.environ['VV_TEST_SCENARIO']
name=Path(sys.argv[0]).name;args=sys.argv[1:]
if name=='emulator':
 if args==['-list-avds']:print('video_viewer_api_36');raise SystemExit(0)
 p.with_suffix('.session.json').write_text(json.dumps({'isolated':os.getsid(0)==os.getpid()}))
 p.write_text(json.dumps(args));raise SystemExit(0)
if name=='ps':
 if p.exists() or scenario in {'existing','other','profile','decoder','audio-off'}:
  flags=json.loads(p.read_text()) if p.exists() else ['-avd','other' if scenario=='other' else 'video_viewer_api_36','-port','5554','-gpu','host' if scenario=='profile' else 'software','-feature','-GLDMA','-feature','HardwareDecoder','-no-snapshot']
  if scenario=='audio-off':flags+=['-no-audio']
  print('stub/qemu-system-aarch64 '+' '.join(flags))
 raise SystemExit(0)
if args==['start-server']:raise SystemExit(0)
if args==['devices']:print('List of devices attached\\nemulator-5554\\toffline');raise SystemExit(0)
args=args[2:]
live=p.exists() or scenario in {'existing','other','profile','decoder','audio-off'}
if args==['get-state']:
 if live:print('device');raise SystemExit(0)
 raise SystemExit(1)
if args==['emu','avd','name']:print('other' if scenario=='other' else 'video_viewer_api_36');print('OK');raise SystemExit(0)
if args==['shell','getprop','sys.boot_completed']:print('1' if live else '');raise SystemExit(0)
if args==['shell','getprop','ro.boot.qemu.hwcodec.avcdec']:print('' if scenario=='decoder' else '2');raise SystemExit(0)
raise SystemExit('Unexpected synthetic SDK invocation: '+repr(args))
"""


class LauncherContract(unittest.TestCase):
    def run_launcher(self, scenario, **overrides):
        with tempfile.TemporaryDirectory(prefix="launcher-contract-", dir=ROOT / ".dev") as raw:
            directory = Path(raw)
            sdk = directory / "android-sdk"
            binpath = directory / "bin"
            for name in ("platform-tools/adb", "emulator/emulator"):
                path = sdk / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(TOOL)
                path.chmod(0o755)
            binpath.mkdir()
            (binpath / "ps").write_text(TOOL)
            (binpath / "ps").chmod(0o755)
            env = {
                **os.environ,
                "VV_DEV_HOME": str(directory),
                "ANDROID_HOME": str(sdk),
                "ANDROID_SDK_ROOT": str(sdk),
                "VV_EMULATOR_TIMEOUT": "5",
                "VV_EMULATOR_HEADLESS": "1",
                "VV_EMULATOR_GPU": "software",
                "VV_EMULATOR_GLDMA": "off",
                "VV_EMULATOR_HOST_VIDEO": "on",
                "VV_EMULATOR_AUDIO": "on",
                "VV_TEST_STATE": str(directory / "started.json"),
                "VV_TEST_SCENARIO": scenario,
                "PATH": str(binpath) + os.pathsep + os.environ["PATH"],
                **overrides,
            }
            result = subprocess.run(
                ["bash", str(LAUNCHER)],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
            marker = directory / "started.json"
            session = marker.with_suffix(".session.json")
            result.session_isolated = (
                json.loads(session.read_text())["isolated"] if session.exists() else None
            )
            return result, json.loads(marker.read_text()) if marker.exists() else None

    def test_offline_transport_without_process_starts_once(self):
        result, args = self.run_launcher("stale")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNotNone(args, "Offline ADB serial must not suppress a new launch")
        self.assertIn("-GLDMA", args)
        self.assertIn("HardwareDecoder", args)
        self.assertIn("-no-window", args)
        self.assertTrue(
            result.session_isolated,
            "Emulator must outlive the IDE startup command session",
        )
        self.assertIn("GLDMA=off", result.stdout)

    def test_matching_live_profile_is_reused(self):
        result, args = self.run_launcher("existing")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(args)

    def test_other_emulator_is_preserved(self):
        result, args = self.run_launcher("other")
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(args)

    def test_mismatched_gpu_is_not_reported_ready(self):
        result, args = self.run_launcher("profile")
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIsNone(args)

    def test_mismatched_decoder_is_not_reported_ready(self):
        result, args = self.run_launcher("decoder")
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIsNone(args)

    def test_invalid_profile_is_rejected_before_launch(self):
        result, args = self.run_launcher("stale", VV_EMULATOR_GLDMA="invalid")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIsNone(args)

    def test_audio_disabled_launch_is_explicit(self):
        result, args = self.run_launcher("stale", VV_EMULATOR_AUDIO="off")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-no-audio", args)
        self.assertIn("audio=off", result.stdout)

    def test_matching_audio_disabled_process_is_reused(self):
        result, args = self.run_launcher("audio-off", VV_EMULATOR_AUDIO="off")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(args)

    def test_audio_mismatch_never_restarts_the_live_process(self):
        for scenario, requested in [("existing", "off"), ("audio-off", "on")]:
            with self.subTest(scenario=scenario):
                result, args = self.run_launcher(scenario, VV_EMULATOR_AUDIO=requested)
                self.assertEqual(result.returncode, 3, result.stderr)
                self.assertIsNone(args)

    def test_invalid_audio_mode_is_rejected_before_launch(self):
        result, args = self.run_launcher("stale", VV_EMULATOR_AUDIO="invalid")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIsNone(args)


if __name__ == "__main__":
    unittest.main(verbosity=2)

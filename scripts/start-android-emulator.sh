#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dev-env.sh"
avd_name="${VV_AVD_NAME:-video_viewer_api_36}"
port="${VV_EMULATOR_PORT:-5554}"
device="emulator-$port"
timeout_seconds="${VV_EMULATOR_TIMEOUT:-240}"
gpu_mode="${VV_EMULATOR_GPU:-}"
if [[ -z "$gpu_mode" ]]; then
  if [[ "$(uname -s)" == Darwin ]]; then
    gpu_mode=host
  else
    gpu_mode=software
  fi
fi
adb="$ANDROID_HOME/platform-tools/adb"
emulator="$ANDROID_HOME/emulator/emulator"
[[ -x "$adb" && -x "$emulator" ]] || { echo 'Install Android platform-tools and emulator first.' >&2; exit 1; }
"$emulator" -list-avds | grep -Fxq "$avd_name" || { echo "Missing AVD: $avd_name" >&2; exit 1; }
"$adb" start-server
if ! "$adb" devices | awk '{print $1}' | grep -Fxq "$device"; then
  mkdir -p "$VV_DEV_HOME/logs"
  # A previous emulator crash must not block unattended startup on a consent dialog.
  options=(-avd "$avd_name" -port "$port" -no-boot-anim -gpu "$gpu_mode" -feature -Vulkan -no-snapshot -no-metrics -crash-report-mode never)
  [[ "${VV_EMULATOR_HEADLESS:-0}" == 1 ]] && options+=(-no-window)
  nohup "$emulator" "${options[@]}" > "$VV_DEV_HOME/logs/emulator-$port.log" 2>&1 < /dev/null &
fi
deadline=$((SECONDS + timeout_seconds))
while (( SECONDS < deadline )); do
  if [[ "$("$adb" -s "$device" get-state 2>/dev/null || true)" == device ]]; then
    running_name="$("$adb" -s "$device" emu avd name 2>/dev/null | tr -d '\r' | head -n 1)"
    [[ "$running_name" == "$avd_name" ]] || { echo "Port $port belongs to another emulator: $running_name" >&2; exit 1; }
    if [[ "$("$adb" -s "$device" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then
      echo "$avd_name is ready on $device."
      exit 0
    fi
  fi
  sleep 2
done
echo "Emulator did not boot within $timeout_seconds seconds; see $VV_DEV_HOME/logs/emulator-$port.log" >&2
exit 1

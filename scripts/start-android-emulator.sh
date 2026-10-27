#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dev-env.sh"
avd_name="${VV_AVD_NAME:-video_viewer_api_36}"
port="${VV_EMULATOR_PORT:-5554}"
device="emulator-$port"
timeout_seconds="${VV_EMULATOR_TIMEOUT:-240}"
# Validated local video profile. Explicit overrides are for separate experiments.
gpu_mode="${VV_EMULATOR_GPU:-software}"
gldma="${VV_EMULATOR_GLDMA:-off}"
host_video="${VV_EMULATOR_HOST_VIDEO:-on}"
case "$gldma" in on) dma_feature=GLDMA ;; off) dma_feature=-GLDMA ;; *) echo 'VV_EMULATOR_GLDMA must be on or off.' >&2; exit 2 ;; esac
case "$host_video" in on) codec_feature=HardwareDecoder ;; off) codec_feature=-HardwareDecoder ;; *) echo 'VV_EMULATOR_HOST_VIDEO must be on or off.' >&2; exit 2 ;; esac
adb="$ANDROID_HOME/platform-tools/adb"
emulator="$ANDROID_HOME/emulator/emulator"
[[ -x "$adb" && -x "$emulator" ]] || { echo 'Install Android platform-tools and emulator first.' >&2; exit 1; }
"$emulator" -list-avds | grep -Fxq "$avd_name" || { echo "Missing AVD: $avd_name" >&2; exit 1; }
"$adb" start-server
if ! "$adb" devices | awk '{print $1}' | grep -Fxq "$device"; then
  mkdir -p "$VV_DEV_HOME/logs"
  # A previous emulator crash must not block unattended startup on a consent dialog.
  options=(-avd "$avd_name" -port "$port" -no-boot-anim -gpu "$gpu_mode" -feature -Vulkan -feature "$dma_feature" -feature "$codec_feature" -no-snapshot -no-metrics -crash-report-mode never)
  [[ "${VV_EMULATOR_HEADLESS:-0}" == 1 ]] && options+=(-no-window)
  nohup "$emulator" "${options[@]}" > "$VV_DEV_HOME/logs/emulator-$port.log" 2>&1 < /dev/null &
fi
deadline=$((SECONDS + timeout_seconds))
while (( SECONDS < deadline )); do
  if [[ "$("$adb" -s "$device" get-state 2>/dev/null || true)" == device ]]; then
    running_name="$("$adb" -s "$device" emu avd name 2>/dev/null | tr -d '\r' | head -n 1)"
    [[ "$running_name" == "$avd_name" ]] || { echo "Port $port belongs to another emulator: $running_name" >&2; exit 1; }
    if [[ "$("$adb" -s "$device" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then
      # A booted device can still be running an older, incompatible profile.
      running_command="$(ps -ax -o command= | awk -v avd="$avd_name" -v port="$port" 'index($0, "qemu-system") && index($0, " -avd " avd " ") && index($0, " -port " port " ") { print }')"
      if [[ "$running_command" != *" -gpu $gpu_mode "* || "$running_command" != *" -feature $dma_feature "* ]]; then
        echo "The owned AVD is booted with another render profile. Stop it before starting GPU=$gpu_mode, GLDMA=$gldma; userdata is preserved." >&2
        exit 3
      fi
      avc="$("$adb" -s "$device" shell getprop ro.boot.qemu.hwcodec.avcdec | tr -d '\r')"
      if [[ ( "$host_video" == on && "$avc" != 2 ) || ( "$host_video" == off && "$avc" == 2 ) ]]; then
        echo "The owned AVD has another video decoder profile. Stop it before starting host-video=$host_video; userdata is preserved." >&2
        exit 3
      fi
      echo "$avd_name is ready on $device (GPU=$gpu_mode, GLDMA=$gldma, host-video=$host_video)."
      exit 0
    fi
  fi
  sleep 2
done
echo "Emulator did not boot within $timeout_seconds seconds; see $VV_DEV_HOME/logs/emulator-$port.log" >&2
exit 1

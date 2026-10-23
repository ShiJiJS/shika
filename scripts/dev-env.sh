#!/usr/bin/env bash
# Source this file in Bash/Zsh, or use: bash scripts/dev.sh <command> [args...].
if [[ -n "${BASH_VERSION:-}" ]]; then
  _vv_script="${BASH_SOURCE[0]}"
else
  _vv_script="${(%):-%x}"
fi
_vv_root="$(cd "$(dirname "$_vv_script")/.." && pwd)"
export VV_DEV_HOME="${VV_DEV_HOME:-$_vv_root/.dev}"
export FLUTTER_ROOT="${FLUTTER_ROOT:-$VV_DEV_HOME/flutter}"
export ANDROID_HOME="${ANDROID_HOME:-$VV_DEV_HOME/android-sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_USER_HOME="${ANDROID_USER_HOME:-$VV_DEV_HOME/android-user}"
export ANDROID_AVD_HOME="${ANDROID_AVD_HOME:-$VV_DEV_HOME/avd}"
export PUB_CACHE="${PUB_CACHE:-$VV_DEV_HOME/pub-cache}"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$VV_DEV_HOME/gradle}"
export VV_SERVER_DEV_HOME="${VV_SERVER_DEV_HOME:-$VV_DEV_HOME/server}"
export VV_E2E_HOME="${VV_E2E_HOME:-$VV_DEV_HOME/e2e}"
if [[ -d "$VV_DEV_HOME/jdk/Contents/Home" ]]; then
  export JAVA_HOME="${JAVA_HOME:-$VV_DEV_HOME/jdk/Contents/Home}"
fi
export PATH="$FLUTTER_ROOT/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:${JAVA_HOME:+$JAVA_HOME/bin:}$PATH"
unset _vv_script _vv_root

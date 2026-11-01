#!/usr/bin/env bash
# Pinned Apple Silicon toolchain. All downloaded tools and caches stay in .dev/.
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo 'This bootstrap requires Apple Silicon macOS.' >&2; exit 1; }
source "$repo_dir/scripts/dev-env.sh"
mkdir -p "$VV_DEV_HOME"/{downloads,logs,android-user,avd,pub-cache,gradle}
if [[ ! -d "$VV_DEV_HOME/jdk/Contents/Home" ]]; then
  installed_java="$(/usr/libexec/java_home -v 17)"
  cp -R "$(dirname "$(dirname "$installed_java")")" "$VV_DEV_HOME/jdk"
fi
export JAVA_HOME="$VV_DEV_HOME/jdk/Contents/Home"
fetch() {
  local url="$1" target="$2" bits="$3" expected="$4"
  [[ -f "$target" ]] || curl --fail --location --retry 3 --output "$target" "$url"
  printf '%s  %s\n' "$expected" "$target" | shasum -a "$bits" --check
}
if [[ ! -x "$FLUTTER_ROOT/bin/flutter" ]]; then
  bundle="$VV_DEV_HOME/downloads/flutter_macos_arm64_3.47.7-stable.zip"
  fetch 'https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.47.7-stable.zip' "$bundle" 256 dd9da574c3168460550117eb0e8dd0313ae934fabf64a82a6d557fff5fd1422e
  unzip -q "$bundle" -d "$VV_DEV_HOME"
fi
if [[ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]]; then
  bundle="$VV_DEV_HOME/downloads/commandlinetools-mac-13114758_latest.zip"
  fetch 'https://dl.google.com/android/repository/commandlinetools-mac-13114758_latest.zip' "$bundle" 1 c3e06a1959762e89167d1cbaa988605f6f7c1d24
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  unzip -q "$bundle" -d "$ANDROID_HOME/cmdline-tools"
  mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
fi
sdkmanager="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
set +e
yes | "$sdkmanager" --sdk_root="$ANDROID_HOME" --licenses > "$VV_DEV_HOME/logs/sdk-licenses.log" 2>&1
license_status=${PIPESTATUS[1]}
set -e
(( license_status == 0 )) || { echo "SDK license setup failed; see .dev/logs/sdk-licenses.log" >&2; exit "$license_status"; }
"$sdkmanager" --sdk_root="$ANDROID_HOME" 'platform-tools' 'platforms;android-36' 'platforms;android-35' 'build-tools;36.0.0' 'ndk;28.2.13676358' 'cmake;3.22.1' 'emulator' 'system-images;android-36;google_apis;arm64-v8a'
if ! "$ANDROID_HOME/emulator/emulator" -list-avds | grep -Fxq video_viewer_api_36; then
  printf 'no\n' | "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" create avd --name video_viewer_api_36 --device pixel_7 --package 'system-images;android-36;google_apis;arm64-v8a'
fi
if [[ ! -x "$VV_DEV_HOME/venv/bin/python" ]]; then
  python_command=''
  for candidate in python3.14 python3.13 python3; do
    if command -v "$candidate" > /dev/null && "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 13))'; then
      python_command="$candidate"
      break
    fi
  done
  [[ -n "$python_command" ]] || { echo 'Python 3.13+ is required for the local editor environment.' >&2; exit 1; }
  "$python_command" -m venv "$VV_DEV_HOME/venv"
fi
PIP_CACHE_DIR="$VV_DEV_HOME/pip-cache" "$VV_DEV_HOME/venv/bin/python" -m pip install --require-hashes -r "$repo_dir/services/server/requirements-test.lock"
python3 "$repo_dir/scripts/configure-vscode.py"
code_cli='/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code'
if [[ -x "$code_cli" ]]; then
  "$code_cli" --install-extension Dart-Code.flutter
  "$code_cli" --install-extension ms-python.python
fi
(cd "$repo_dir/apps/mobile" && "$FLUTTER_ROOT/bin/flutter" pub get)
bash "$repo_dir/scripts/prepare-server-dev.sh"
echo 'Ready. Open Video Viewer.code-workspace in VS Code; see docs/macos-development.md.'

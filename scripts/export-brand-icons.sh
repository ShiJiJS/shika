#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_image="$root/assets/branding/shika-icon.png"
res="$root/apps/mobile/android/app/src/main/res"
for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density="${pair%%:*}"
  pixels="${pair##*:}"
  mkdir -p "$res/mipmap-$density"
  sips --resampleHeightWidth "$pixels" "$pixels" "$source_image" --out "$res/mipmap-$density/ic_launcher.png" >/dev/null
done

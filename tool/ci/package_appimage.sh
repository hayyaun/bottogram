#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."

bundle="$PWD/build/linux/x64/release/bundle"
appdir="$PWD/build/appimage/AppDir"
tools="$PWD/build/ci-tools"
output="$PWD/dist/bottogram-linux-x86_64.AppImage"
version=1-alpha-20251107-1
digest=c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d

test -x "$bundle/bottogram"
# Require a fresh AppDir rather than deleting a potentially misconfigured path.
if [[ -e "$appdir" ]]; then
  printf '%s\n' 'AppDir already exists. Use a fresh build workspace.' >&2
  exit 1
fi
mkdir -p "$tools" "$appdir/usr/bin" "$PWD/dist"
linuxdeploy="$tools/linuxdeploy-x86_64.AppImage"
if [[ ! -f "$linuxdeploy" ]]; then
  curl --fail --location --retry 3 --connect-timeout 20 --max-time 300 \
    "https://github.com/linuxdeploy/linuxdeploy/releases/download/$version/linuxdeploy-x86_64.AppImage" \
    --output "$linuxdeploy"
fi
printf '%s  %s\n' "$digest" "$linuxdeploy" | sha256sum --check -
chmod +x "$linuxdeploy"

# Flutter resolves data and its own libraries relative to its executable.
cp -a "$bundle/." "$appdir/usr/bin/"
cp assets/icon/foreground.png "$tools/bottogram.png"
cat > "$tools/bottogram.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Bottogram
Comment=Telegram bots running on your device
Exec=bottogram
Icon=bottogram
Terminal=false
Categories=Network;InstantMessaging;
DESKTOP

args=(--appdir "$appdir" --executable "$appdir/usr/bin/bottogram"
  --deploy-deps-only "$appdir/usr/bin/lib"
  --desktop-file "$tools/bottogram.desktop" --icon-file "$tools/bottogram.png")
# --deploy-deps-only handles dynamically loaded Flutter/plugin libraries in
# place, preserving their executable-relative layout and collecting dependencies.

# FUSE is available in the CI runner; no extraction or runtime patch is needed.
LDAI_OUTPUT="$output" ARCH=x86_64 "$linuxdeploy" "${args[@]}" --output appimage
test -s "$output"
chmod +x "$output"

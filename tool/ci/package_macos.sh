#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."

if [[ "$(uname -s)" != Darwin ]]; then
  printf '%s\n' 'macOS packaging requires a macOS host.' >&2
  exit 1
fi

app="build/macos/Build/Products/Release/bottogram.app"
test -x "$app/Contents/MacOS/bottogram"

# Release builds retain Flutter's universal default. Verify every embedded
# framework as well as the launcher before labelling the archive universal.
lipo "$app/Contents/MacOS/bottogram" -verify_arch arm64 x86_64
for framework in "$app"/Contents/Frameworks/*.framework; do
  name="$(basename "$framework" .framework)"
  lipo "$framework/$name" -verify_arch arm64 x86_64
done

# Existing Xcode ad-hoc signing is sufficient for a test artifact. Verify it
# without changing identities, entitlements, sandboxing or quarantine policy.
codesign --verify --deep --strict "$app"
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent "$app" dist/bottogram-macos-universal.zip
(
  cd dist
  shasum -a 256 bottogram-macos-universal.zip > SHA256SUMS.txt
)

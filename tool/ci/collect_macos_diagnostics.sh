#!/usr/bin/env bash
# Read-only diagnostics from this disposable CI runner; preserve the build failure.
set -u
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."

output=build/verification/macos-diagnostics
app=build/macos/Build/Products/Debug/bottogram.app
mkdir -p "$output"
if [[ -d "$app" ]]; then
  codesign --verify --deep --strict "$app" > "$output/signature-verification.txt" 2>&1
  codesign -dvvv "$app" > "$output/signature-details.txt" 2>&1
  codesign -d --entitlements :- "$app" > "$output/entitlements.txt" 2>&1
fi
/usr/bin/log show --last 10m --style compact \
  --predicate 'process == "bottogram" OR eventMessage CONTAINS[c] "bottogram"' \
  > "$output/app-system-log.txt" 2>&1
for directory in "$HOME/Library/Logs/DiagnosticReports" /Library/Logs/DiagnosticReports; do
  for report in "$directory"/bottogram*.ips; do
    if [[ -f "$report" ]]; then
      cp "$report" "$output/$(basename "$report")"
    fi
  done
done
exit 0

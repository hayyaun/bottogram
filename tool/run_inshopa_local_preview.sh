#!/usr/bin/env bash
# Run in a desktop D-Bus session so Linux secure storage can use GNOME Keyring.
# Argument: a private connection-file path, never a token or API key.
set -eu
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  printf '%s\n' 'Supply the private local-test connection-file path.' >&2
  exit 2
fi
flutter=/home/garfield/flutter-sdk/flutter/bin/flutter
mkdir -p build/verification
printf '%s\n' 'Configuring the local test bot using the normal app and secure storage...'
if ! "$flutter" test --no-pub -d linux integration_test/inshopa_local_setup_test.dart \
  "--dart-define=BOTTOGRAM_LOCAL_TEST_CREDENTIALS=$1" \
  "--dart-define=BOTTOGRAM_LOCAL_TEST_REPORT=$PWD/build/verification/inshopa-local-app-setup.json" \
  --reporter expanded > build/verification/inshopa-local-app-setup.log 2>&1; then
  printf '%s\n' 'Setup stopped. The private-safe diagnostic log is in build/verification/inshopa-local-app-setup.log.'
  exit 1
fi
printf '%s\n' 'Setup complete. Opening Bottogram; press Start on Inshopa local test.'
exec "$flutter" run -d linux --debug --no-pub \
  --pid-file build/verification/linux-flutter.pid

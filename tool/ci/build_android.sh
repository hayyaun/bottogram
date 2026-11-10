#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."

mode="${1:?Choose trusted or pull-request}"
umask 077
signing_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/bottogram-signing.XXXXXXXX")"
export BOTTOGRAM_KEYSTORE_PATH="$signing_dir/bottogram.p12"
trap 'rm -f -- "$BOTTOGRAM_KEYSTORE_PATH" "$signing_dir/certificate.der"; rmdir -- "$signing_dir"' EXIT

case "$mode" in
  trusted)
    # Missing secrets fail explicitly rather than publishing a different identity.
    : "${BOTTOGRAM_KEYSTORE_BASE64:?Missing permanent signing keystore}"
    : "${BOTTOGRAM_KEYSTORE_PASSWORD:?Missing signing store password}"
    : "${BOTTOGRAM_KEY_ALIAS:?Missing signing alias}"
    : "${BOTTOGRAM_KEY_PASSWORD:?Missing signing key password}"
    python3 - <<'PY'
import base64, os, pathlib
pathlib.Path(os.environ['BOTTOGRAM_KEYSTORE_PATH']).write_bytes(
    base64.b64decode(os.environ['BOTTOGRAM_KEYSTORE_BASE64'], validate=True))
PY
    unset BOTTOGRAM_KEYSTORE_BASE64
    keytool -exportcert -keystore "$BOTTOGRAM_KEYSTORE_PATH" \
      -storepass:env BOTTOGRAM_KEYSTORE_PASSWORD -alias "$BOTTOGRAM_KEY_ALIAS" \
      -file "$signing_dir/certificate.der"
    python3 - "$signing_dir/certificate.der" <<'PY'
import pathlib, ssl, sys
expected = ssl.PEM_cert_to_DER_cert(
    pathlib.Path('android/signing/bottogram-certificate.pem').read_text())
if pathlib.Path(sys.argv[1]).read_bytes() != expected:
    raise SystemExit('Signing certificate does not match Bottogram identity.')
PY
    ;;
  pull-request)
    # These public throwaway values are only for untrusted PR build validation.
    export BOTTOGRAM_KEYSTORE_PASSWORD=bottogram-pr-validation-only
    export BOTTOGRAM_KEY_ALIAS=bottogram-pr-validation
    export BOTTOGRAM_KEY_PASSWORD=bottogram-pr-validation-only
    keytool -genkeypair -noprompt -storetype PKCS12 -keyalg RSA -keysize 2048 \
      -validity 2 -dname 'CN=Bottogram PR validation' \
      -keystore "$BOTTOGRAM_KEYSTORE_PATH" -alias "$BOTTOGRAM_KEY_ALIAS" \
      -storepass:env BOTTOGRAM_KEYSTORE_PASSWORD -keypass:env BOTTOGRAM_KEY_PASSWORD
    ;;
  *) printf '%s\n' 'Unknown signing mode.' >&2; exit 2 ;;
esac

build_args=(--release --no-pub)
if [[ -n "${GITHUB_RUN_NUMBER:-}" ]]; then
  build_args+=(--build-number "$GITHUB_RUN_NUMBER")
fi
flutter build apk "${build_args[@]}"
"${ANDROID_HOME:?Android SDK is required}/build-tools/35.0.0/apksigner" verify \
  --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk

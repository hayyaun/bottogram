# Android signing for direct APK downloads

Bottogram is distributed directly as an APK through GitHub, so the persistent
key is its app-signing identity, not a Play Store upload key. Future installable
updates must keep that identity. A JKS/PKCS12 key can technically sign several
apps, but Bottogram uses its own key to keep compromise/recovery separate from
other projects. The PKCS12 file and its passwords are private, outside Git.

## Build configuration

`android/app/build.gradle.kts` reads these environment variables:

- `BOTTOGRAM_KEYSTORE_PATH`: absolute path to the PKCS12 keystore.
- `BOTTOGRAM_KEYSTORE_PASSWORD`: keystore password.
- `BOTTOGRAM_KEY_ALIAS`: private-key alias.
- `BOTTOGRAM_KEY_PASSWORD`: private-key password.

An incomplete configuration fails immediately. With no configuration Gradle has
no release signing identity; it never substitutes the debug certificate. Ordinary
debug builds remain available. Never distribute an unsigned build or replace the
permanent key with a freshly generated one merely to make a build pass.

## GitHub Actions

Trusted branch/manual builds use four repository Actions secrets:

- `BOTTOGRAM_KEYSTORE_BASE64`: Base64 encoding of the private PKCS12 file.
- `BOTTOGRAM_KEYSTORE_PASSWORD`.
- `BOTTOGRAM_KEY_ALIAS`.
- `BOTTOGRAM_KEY_PASSWORD`.

`tool/ci/build_android.sh trusted` reconstructs the key in a private temporary
directory, builds the release APK and verifies its APK signature. The temporary
key is removed on exit. No signing files enter the uploaded artifact or cache.
Missing secrets fail the build instead of changing the app's identity.
The reconstructed certificate must exactly match
`android/signing/bottogram-certificate.pem` before compilation starts. Its SHA-256
fingerprint is `F7:D1:54:E5:56:D5:29:74:E0:75:68:43:79:BF:74:AF:35:29:BD:B1:BC:9A:A5:4C:54:64:AA:C8:DC:02:4E:82`.

PR builds use a separate, ephemeral validation certificate and are uploaded as
`bottogram-android-pr-validation`. The permanent secrets are only injected into
the trusted build step. PR artifacts are not upgrade-compatible distribution
builds. Do not change the workflow to execute untrusted PR code with signing secrets.

Storing these secrets on GitHub grants trusted workflow code the ability to sign APKs.
Keep an independent protected backup of the key, passwords and alias; losing the
key can prevent compatible future updates for direct-download users.

## Transition from previous artifacts

Earlier artifacts were signed with development/debug certificates. Android will
not accept the permanently signed APK as an ordinary update over those builds.
Uninstalling an old build removes its local data, so users must plan for that
transition before installing. Once permanent signing starts, retain the same key
and increment application version codes for subsequent distributed updates.
The CI script uses `GITHUB_RUN_NUMBER` as the Android version code. Keep future
distribution in the same workflow, or explicitly preserve a higher version-code
sequence if changing workflows. Local builds use the pubspec build number unless
a build number is supplied separately.

References: [Android app signing](https://developer.android.com/studio/publish/app-signing),
[GitHub encrypted secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets).

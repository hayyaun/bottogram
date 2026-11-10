# Test builds, without publishing releases

The [build workflow](../.github/workflows/build.yml) runs on pushes to `main`,
pull requests targeting `main`, and manual dispatch. Analysis and unit/widget
tests must pass before the three native builds run. Packaged SQL isolation tests
also run on a headless Android emulator, Linux under Xvfb and Windows. Live
Telegram/shop integration tests stay opt-in and receive no customer credentials
in CI.

Outputs, retained for 14 days in the workflow run's **Artifacts** section:

- Android: universal `bottogram-android-release.apk` with a SHA-256 checksum.
  Built with `flutter build apk --release`; CI checks that the APK is not
  debuggable. Trusted builds use Bottogram's permanent signing identity, whose
  public certificate is pinned in the repository. PR artifacts are named
  `bottogram-android-pr-validation` and use a temporary validation key.
  Earlier debug-signed APKs cannot be updated directly to the permanent identity.
  See [Android signing and key backup requirements](ANDROID_SIGNING.md).
- Windows x64: `bottogram-windows-x64.zip`, containing `bottogram.exe`, DLLs,
  and data, plus a checksum. Extract the whole folder before running the EXE.
  This is unsigned, without an installer; a clean Windows machine may need the
  Microsoft Visual C++ runtime. Clean-machine runtime testing remains required.
- Linux x86_64: a tarball containing `bottogram-linux-x86_64.AppImage` and its
  checksum. The tarball preserves the executable permission. Built on Ubuntu
  22.04; older glibc systems are not a compatibility target. A running desktop
  keyring remains necessary for plugin secret storage, and the normal AppImage
  runtime requires FUSE. Test desktop integration and keyring access on a clean
  distribution before treating the package as ready for users.

The workflow uses read-only repository permissions, private Android signing
secrets only in the trusted build step, no tags, no release jobs, and no store uploads. “Release” in Flutter
Flutter build commands means optimized compilation, not a published release.

Flutter is pinned to 3.47.9; Android uses JDK 17,
SDK 36 and NDK 28.2.13676358 to match the project. The AppImage builder uses the
official linuxdeploy `1-alpha-20251107-1` binary with its published asset digest.
Actions are pinned to verified commit IDs. Updating tools means reviewing those
pins and the linuxdeploy checksum together, then rerunning the builds.

Setup-android accepts SDK licenses in CI. Flutter/Gradle then provisions the
configured SDK platform, AGP's default build tools 35.0.0 and NDK 28.2.13676358.
Android build/test steps also set `ANDROID_NDK_HOME` to that version because
Flutter's native compiler resolution gives this environment variable priority.
For a local Android invocation with `ANDROID_HOME` configured, select it with
`ANDROID_NDK_HOME="$ANDROID_HOME/ndk/28.2.13676358" flutter ...`.

SQLite is compiled from the pinned upstream amalgamation through the documented
`sqlite3` source hook. Its authorization and progress hooks remain enabled. The
application-owned security bridge uses SQLite's public extension ABI, and checks
the actual packaged core before any creator SQL runs. Neither a system-library
fallback nor `sqlite3_flutter_libs` is used. Source hashes and update instructions
are in [native/sqlite/README.md](../native/sqlite/README.md).

Run the same packaged isolation suite locally with a configured native target:

```sh
xvfb-run -a flutter test integration_test/sqlite_isolation_test.dart -d linux --no-pub --reporter expanded
flutter test integration_test/sqlite_isolation_test.dart -d emulator-5554 --no-pub --reporter expanded
flutter test integration_test/sqlite_isolation_test.dart -d windows --no-pub --reporter expanded
```

The suite creates temporary databases, attacks a second bot's existing file,
checks reserved-table protection and rollback, and proves a long query can be
interrupted while the UI isolate remains responsive. It uses no real bot tokens
or application storage.

Local packaging after `flutter build linux --release`:

```sh
bash tool/ci/package_appimage.sh
```

This requires the build/packaging packages listed in the Linux workflow job and
a fresh `build/appimage/AppDir`. Outputs remain ignored by Git. The script retains
Flutter's executable-relative data/library layout and asks linuxdeploy to collect
dependencies of the executable and its dynamically loaded plugin libraries.

After the workflow is pushed, inspect its first GitHub run and download/test
all three artifacts. A syntax check or an existing Android APK build does not
prove that the new hosted Windows/AppImage jobs passed.

References: [Flutter Windows distribution](https://docs.flutter.dev/platform-integration/windows/building),
[linuxdeploy packaging](https://docs.appimage.org/packaging-guide/from-source/linuxdeploy-user-guide.html),
[artifact retention and file permissions](https://github.com/actions/upload-artifact).

## Verification on 2026-11-09

`actionlint` passed, YAML parsed, Bash syntax passed, and the Windows packaging
snippet parsed as PowerShell. A local optimized Linux build and the complete
AppImage packaging command passed. Extracting the resulting AppImage verified its
executable, `libapp.so` and ICU data without starting a second application/Hive
owner. The checksum and permission-preserving tarball were also generated.
Logs are under `build/verification/ci-*`; local outputs are ignored in `dist/`.
This local build used WSL Ubuntu's installed libraries, not a fresh Ubuntu 22.04
runner, and does not establish clean-desktop compatibility. The first hosted
workflow execution, native Windows build, new CI Android build and actual desktop
runtime tests remain pending. No GitHub release was created.

## SQL packaging verification on 2026-11-10

The source build uses SQLite 3.54.1. The full 132-test unit/widget suite and
analysis pass with Flutter 3.47.9. Native Linux integration passes all eight
isolation groups, including real cross-bot file attempts, reserved-table foreign
key protection, rollback and interruption at about two seconds while the main
isolate remains responsive. Queue, shutdown and local-media-input regressions
also pass; generic media actions accept file IDs/HTTP(S), without filesystem reads.

The final Linux release bundle and AppImage build successfully. The actual
release libraries and extracted AppImage payload pass the functional security
probe against the pinned core/source ID. Outputs and checksums are in `dist/`;
logs are under `build/verification/sqlite-*`. This is a local WSL build, with the
same clean-distribution compatibility limits described above.

Android API 35 x86_64 emulator verification passes all eight native isolation
groups after Flutter/Gradle automatically provisioned NDK 28.2.13676358. The
installed test APK reports SQLite 3.54.1 and the pinned source ID, with authorization
and progress hooks active. Its long query was interrupted after 2,009 ms while
the main isolate recorded 100 heartbeats. This verifies emulator execution and
native-library packaging; physical Android devices and other ABIs were not run.
The log is `build/verification/sqlite-android-native.log`.

Windows native execution remains unverified locally; its native integration and
release-library probe are configured in CI. No hosted workflow run or public
release is claimed by these local checks.

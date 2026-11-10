# Builds and GitHub releases

The [build workflow](../.github/workflows/build.yml) runs on pushes to `main`,
pull requests targeting `main`, and manual dispatch. Analysis and unit/widget
tests must pass before the four platform builds run. Packaged SQLite isolation
and bot-template tests also run on a headless Android emulator, Linux under Xvfb,
Windows, and both Intel and Apple silicon macOS runners. macOS additionally tests
native credential storage. Live
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
  A separate `bottogram-windows-x64-setup.exe` installs for the current user,
  creates a Start menu shortcut, offers a desktop shortcut, and provides an
  uninstaller. Both packages include compiler runtime DLLs through CMake's
  `InstallRequiredSystemLibraries`. They are unsigned; clean-machine runtime
  testing remains required. See [Windows installer details](WINDOWS_INSTALLER.md).
- macOS Intel and Apple silicon: `bottogram-macos-universal.zip`, containing
  `bottogram.app`, plus a checksum. Packaging verifies both architectures in the
  launcher and every embedded framework, along with the app's existing ad-hoc
  signature. This is not Developer ID signing or Apple notarization, so macOS
  may block opening a downloaded package. Credentials use the macOS login
  Keychain without a shared access group.
- Linux x86_64: a tarball containing `bottogram-linux-x86_64.AppImage` and its
  checksum. The tarball preserves the executable permission. Built on Ubuntu
  22.04; older glibc systems are not a compatibility target. A running desktop
  keyring remains necessary for plugin secret storage, and the normal AppImage
  runtime requires FUSE. Test desktop integration and keyring access on a clean
  distribution before treating the package as ready for users.

The build workflow uses read-only repository permissions and private Android
signing secrets only in the trusted build step. It does not publish packages to
GitHub Releases or app stores. “Release” in Flutter build commands means optimized
compilation. Public GitHub releases use the separate tag workflow below.

## Publish a verified GitHub release

The [release workflow](../.github/workflows/release.yml) runs when a `v*` tag is
pushed. It accepts stable SemVer tags only, such as `v1.0.0`; the version must match
`pubspec.yaml` without its `+build` number. Push the commit to `main` and wait for
its complete **Build test artifacts** run to succeed before tagging that exact
commit:

```sh
git tag -a v1.0.0 <verified-commit-sha> -m 'Bottogram 1.0.0'
git push origin v1.0.0
```

The release job uses GitHub's preinstalled `gh` CLI and the workflow's automatic
`GITHUB_TOKEN`; no personal token or additional secret is needed. Its permissions
are scoped to that job: `actions: read` for downloading build artifacts and
`contents: write` for creating the release. It never rebuilds a package.

[prepare_release.py](../tool/ci/prepare_release.py) looks up a successful
`build.yml` run triggered by a push to `main` whose commit SHA exactly equals the
tagged commit. It does not use the latest unrelated build or a PR artifact. All
five artifact names must be present in that one run:

- `bottogram-android-release`
- `bottogram-windows-x64`
- `bottogram-windows-x64-installer`
- `bottogram-macos-universal`
- `bottogram-linux-x86_64`

The script downloads each artifact by its selected run ID, validates its expected
files and existing SHA-256 checksum, and prepares one flat release folder. For
Linux it validates the executable AppImage and checksum inside the tarball
without extracting arbitrary archive paths. The published Linux asset remains
the tarball so its executable permission survives download. The combined release
`SHA256SUMS.txt` covers the APK, Windows installer, both ZIP files, and the Linux
tarball itself.

Only after all checks pass does `gh release create --verify-tag` publish the five
packages and combined checksum. Release notes link to the exact successful build
and source commit. Publication stops if there is no successful exact-commit build,
or if an artifact is missing or expired, a version differs, or a checksum fails. If a
workflow attempt fails before creating the release, fix the stated cause and
rerun that failed release workflow after all five artifacts are available. It
does not replace an existing release or overwrite its assets.

Download a release's `SHA256SUMS.txt` beside its packages and verify them, for
example on Linux:

```sh
sha256sum --check SHA256SUMS.txt
```

This uses the documented [workflow-run filters](https://docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-workflow),
[run-specific artifact downloads](https://cli.github.com/manual/gh_run_download),
and [release creation with existing-tag verification](https://cli.github.com/manual/gh_release_create).

## Toolchain and native checks

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
flutter test integration_test/sqlite_isolation_test.dart -d macos --no-pub --reporter expanded
flutter test integration_test/secret_vault_test.dart -d macos --no-pub --reporter expanded
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

Inspect the complete GitHub build run and download/test all four platform
artifacts before tagging. Automated checks do not establish clean-machine
compatibility or Apple notarization.

References: [Flutter Windows distribution](https://docs.flutter.dev/platform-integration/windows/building),
[linuxdeploy packaging](https://docs.appimage.org/packaging-guide/from-source/linuxdeploy-user-guide.html),
[artifact retention and file permissions](https://github.com/actions/upload-artifact).

## Earlier local verification on 2026-11-09

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

## Bot templates verification on 2026-11-10

The full 151-test unit/widget suite passes with clean analysis. The new native
template smoke test passes on Linux and an Android API 35 x86_64 emulator. It
executes all seven generated action flows against real temporary per-bot SQLite
files, including scoring, private tasks/favorites, survey submission, admin
replies, registration capacity and API error presentation. Both platforms report
SQLite 3.54.1 with authorization/progress hooks active.

The current Linux release was rebuilt, its native SQLite probe passed, and the
visible WSLg preview was restarted from an immutable copy of that bundle using
normal saved app data. The updated AppImage was built and extracted for checking.
Its compiled code, read-only data, unwind data, static data and build-ID sections
match the release. Full ELF bytes differ because linuxdeploy updates RPATH; this
is recorded in the packaging log. The extracted SQLite probe also passes.
The AppImage SHA256 is
67c89451149cff0516be095b28461947956eac749689a693f444a1388db5def8.
The permission-preserving tarball and both checksums are in dist/.

The previous package and AppDir were retained with timestamped before-templates
names. These remain local WSL artifacts with the clean-distribution limits noted
above. Windows native template testing is configured in CI but has not run here;
physical Android devices, other ABIs and hosted workflow execution are unverified.
No public release was created. Logs use the build/verification/templates- prefix.

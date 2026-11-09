# Test builds, without publishing releases

The [build workflow](../.github/workflows/build.yml) runs on pushes to `main`,
pull requests targeting `main`, and manual dispatch. Analysis and unit/widget
tests must pass before the three native builds run. Native/live integration
tests stay opt-in and never receive customer credentials in CI.

Outputs, retained for 14 days in the workflow run's **Artifacts** section:

- Android: universal `bottogram-android-debug.apk` with a SHA-256 checksum.
  This is a debug-signed testing build. Ephemeral runner debug keys can differ
  between runs, so Android may refuse an in-place update from another run.
  A stable signing identity and its secure CI storage are future release work.
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

The workflow uses read-only repository permissions, no publishing/signing
secrets, no tags, no release jobs, and no store uploads. “Release” in desktop
Flutter build commands means optimized compilation, not a published release.

Flutter is pinned to the locally verified 3.29.1 version; Android uses JDK 17,
SDK 36 and NDK 27.0.12077973 to match the project. The AppImage builder uses the
official linuxdeploy `1-alpha-20251107-1` binary with its published asset digest.
Actions are pinned to verified commit IDs. Updating tools means reviewing those
pins and the linuxdeploy checksum together, then rerunning the builds.

Local packaging after `flutter build linux --release`:

```sh
bash tool/ci/package_appimage.sh
```

This requires the build/packaging packages listed in the Linux workflow job and
a fresh `build/appimage/AppDir`. Outputs remain ignored by Git. The script retains
Flutter's executable-relative data/library layout and asks linuxdeploy to collect
dependencies of the executable and its dynamically loaded plugin libraries.

🟣 After the workflow is pushed, inspect its first GitHub run and download/test
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

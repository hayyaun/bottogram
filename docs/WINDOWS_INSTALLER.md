# Windows installer

Releases include `bottogram-windows-x64-setup.exe` alongside the portable ZIP.
The installer supports Windows 10 and newer on x64-compatible systems. It uses
Inno Setup 6 from the hosted Windows runner and requires no administrator rights.
Windows may display a publisher warning because the installer and app are unsigned.

The default destination is `%LOCALAPPDATA%\Programs\Bottogram`. Installation adds
a Start menu shortcut and an entry in Windows' installed-app list. A desktop
shortcut and opening Bottogram after installation are optional. Installing does
not start bots automatically.

Updates reuse a stable installer AppId and the previous destination. Close
Bottogram before updating; stopping it also stops running bots. Uninstallation
removes installed program files and shortcuts. It does not delete bot settings,
messages, databases or saved credentials, and does not remove unmanaged files.
The installer never runs a saved-data migration.

Both Windows packages include compiler-provided Visual C++ runtime libraries
beside the executable, using CMake's supported `InstallRequiredSystemLibraries`
module. No runtime download or system-wide runtime installation is needed.

## Build and verification

After `flutter build windows --release --no-pub`, run this on the configured
Windows CI runner with Inno Setup 6 installed:

```powershell
./tool/ci/package_windows_installer.ps1
```

The script reads version and build numbers from `pubspec.yaml`, requires the
complete Flutter bundle and runtime DLLs, compiles `windows_installer.iss`, and
writes the installer plus its SHA-256 checksum to `dist-installer/`.
It then silently installs to a fresh directory under `RUNNER_TEMP`, verifies every
payload file's hash and the Start menu shortcut, reinstalls while retaining an
unmanaged marker, and uninstalls while checking that marker remains. The smoke
test runs only on the disposable hosted runner, without opening Bottogram.
These checks do not establish compatibility on a clean consumer Windows device.

The release workflow requires the separate `bottogram-windows-x64-installer`
artifact from the same successful main build as the other downloads. It verifies
the installer's checksum before publishing it and includes that checksum in the
combined release manifest.

References: [Flutter Windows distribution](https://docs.flutter.dev/platform-integration/windows/building),
[CMake runtime packaging](https://cmake.org/cmake/help/latest/module/InstallRequiredSystemLibraries.html),
[Inno Setup per-user installation](https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm),
[installer command-line parameters](https://jrsoftware.org/ishelp/topic_setupcmdline.htm).

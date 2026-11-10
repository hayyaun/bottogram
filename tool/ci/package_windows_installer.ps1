$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$project = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Set-Location -LiteralPath $project
$bundle = (Resolve-Path 'build/windows/x64/runner/Release').Path
foreach ($name in @('bottogram.exe', 'flutter_windows.dll', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'data/app.so', 'data/icudtl.dat')) {
    if (!(Test-Path -LiteralPath (Join-Path $bundle $name) -PathType Leaf)) {
        throw "Missing installer payload: $name"
    }
}
$versionLine = @(Get-Content -LiteralPath pubspec.yaml | Where-Object { $_ -match '^version:' })
if ($versionLine.Count -ne 1 -or $versionLine[0] -notmatch '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
    throw 'Expected one version: MAJOR.MINOR.PATCH+BUILD in pubspec.yaml.'
}
$appVersion = $Matches[1]
$buildNumber = $Matches[2]
$compiler = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'
if (!(Test-Path -LiteralPath $compiler -PathType Leaf)) { throw 'The runner must include Inno Setup 6.' }
$output = Join-Path $project 'dist-installer'
New-Item -ItemType Directory -Path $output -Force | Out-Null
& $compiler "/DAppVersion=$appVersion" "/DBuildNumber=$buildNumber" "/DBundleDir=$bundle" "/DOutputDir=$output" tool/ci/windows_installer.iss
if ($LASTEXITCODE -ne 0) { throw "Installer compiler failed: $LASTEXITCODE" }
$installer = Join-Path $output 'bottogram-windows-x64-setup.exe'
$digest = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
"$digest  bottogram-windows-x64-setup.exe" | Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Encoding ascii

# Exercise the real installer and uninstaller on the disposable CI runner.
$testDir = Join-Path $env:RUNNER_TEMP 'bottogram-installer-smoke'
if (Test-Path -LiteralPath $testDir) { throw 'Installer smoke directory must be fresh.' }
$arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', "/DIR=`"$testDir`"")
function Install-TestPackage {
    $process = Start-Process -FilePath $installer -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Installer failed: $($process.ExitCode)" }
}
Install-TestPackage
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Bottogram.lnk'
if (!(Test-Path -LiteralPath $shortcut -PathType Leaf)) { throw 'Start menu shortcut is missing.' }
foreach ($file in Get-ChildItem -LiteralPath $bundle -File -Recurse | Where-Object { $_.Extension -ne '.pdb' }) {
    $relative = [IO.Path]::GetRelativePath($bundle, $file.FullName)
    $installed = Join-Path $testDir $relative
    if (!(Test-Path -LiteralPath $installed -PathType Leaf) -or
        (Get-FileHash -LiteralPath $installed).Hash -ne (Get-FileHash -LiteralPath $file.FullName).Hash) {
        throw "Installed file differs: $relative"
    }
}
$marker = Join-Path $testDir 'preserve-unmanaged-user-file.txt'
Set-Content -LiteralPath $marker -Value 'Installer upgrade and uninstall must retain unmanaged files.'
Install-TestPackage
if (!(Test-Path -LiteralPath $marker)) { throw 'Upgrade removed unmanaged data.' }
$uninstaller = Join-Path $testDir 'unins000.exe'
$process = Start-Process -FilePath $uninstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -WindowStyle Hidden -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Uninstaller failed: $($process.ExitCode)" }
if (Test-Path -LiteralPath (Join-Path $testDir 'bottogram.exe')) { throw 'Uninstall left the installed executable.' }
if (Test-Path -LiteralPath $shortcut) { throw 'Uninstall left the Start menu shortcut.' }
if (!(Test-Path -LiteralPath $marker)) { throw 'Uninstall removed unmanaged data.' }
Write-Output 'Installer, payload integrity, upgrade, and uninstall checks passed.'

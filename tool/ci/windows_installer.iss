#ifndef AppVersion
  #error AppVersion must be supplied by the packaging script
#endif
#ifndef BuildNumber
  #error BuildNumber must be supplied by the packaging script
#endif
#ifndef BundleDir
  #error BundleDir must be supplied by the packaging script
#endif
#ifndef OutputDir
  #error OutputDir must be supplied by the packaging script
#endif

[Setup]
AppId={{D27C194D-468D-471F-B768-8D831945BE64}
AppName=Bottogram
AppVersion={#AppVersion}
AppPublisher=Hayyaun
AppPublisherURL=https://github.com/hayyaun/bottogram
AppSupportURL=https://github.com/hayyaun/bottogram/issues
AppUpdatesURL=https://github.com/hayyaun/bottogram/releases
VersionInfoVersion={#AppVersion}.{#BuildNumber}
DefaultDirName={localappdata}\Programs\Bottogram
DefaultGroupName=Bottogram
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=bottogram-windows-x64-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\bottogram.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Excludes: "*.pdb"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Bottogram"; Filename: "{app}\bottogram.exe"
Name: "{autodesktop}\Bottogram"; Filename: "{app}\bottogram.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\bottogram.exe"; Description: "Open Bottogram"; Flags: nowait postinstall skipifsilent unchecked

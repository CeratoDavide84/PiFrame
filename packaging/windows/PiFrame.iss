#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "."
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

[Setup]
AppId={{A9C50DD7-27AF-44C0-A1A4-9C132A354C4A}
AppName=PiFrame
AppVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\PiFrame
DefaultGroupName=PiFrame
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
UninstallDisplayIcon={app}\PiFrame.exe
OutputDir={#OutputDir}
OutputBaseFilename=PiFrame-Setup-{#AppVersion}-windows-x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.WebView2\*,*.WebView2"

[Icons]
Name: "{autoprograms}\PiFrame"; Filename: "{app}\PiFrame.exe"
Name: "{autodesktop}\PiFrame"; Filename: "{app}\PiFrame.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\PiFrame.exe"; Description: "Launch PiFrame"; Flags: postinstall nowait skipifsilent

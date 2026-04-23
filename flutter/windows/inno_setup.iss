#ifndef AppVersion
#define AppVersion "0.0.0"
#endif

[Setup]
AppId={{DE850239-5B22-480D-B91F-3413B6B98CC4}}
AppName=Drift
AppVersion={#AppVersion}
AppPublisher=Drift
DefaultDirName={autopf}\Drift
DefaultGroupName=Drift
OutputDir=.\
OutputBaseFilename=drift-windows-setup
SetupIconFile=runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Drift"; Filename: "{app}\Drift.exe"
Name: "{commondesktop}\Drift"; Filename: "{app}\Drift.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Drift.exe"; Description: "{cm:LaunchProgram,Drift}"; Flags: nowait postinstall skipifsilent

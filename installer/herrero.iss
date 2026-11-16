#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{6B0E8B9C-6C0B-4E8A-9F55-0B6F7A1C2D31}
AppName=Herrero
AppVersion={#AppVersion}
AppPublisher=Herrero
DefaultDirName={autopf}\Herrero
DefaultGroupName=Herrero
OutputDir=Output
OutputBaseFilename=Herrero-Setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
WizardStyle=modern

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Herrero"; Filename: "{app}\herrero.exe"
Name: "{autodesktop}\Herrero"; Filename: "{app}\herrero.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\herrero.exe"; Description: "{cm:LaunchProgram,Herrero}"; Flags: nowait postinstall skipifsilent

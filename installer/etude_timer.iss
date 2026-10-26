; Script Inno Setup (https://jrsoftware.org/isinfo.php) — installeur Windows optionnel.
; Prérequis : avoir lancé scripts\build_windows.ps1 (dossier build\windows\x64\runner\Release).
; Les données restent dans %APPDATA%\etude-timer : elles survivent à une mise à jour ou une désinstallation.

#define AppName "Étude Timer"
#define AppVersion "2.0.0"
#define AppExe "etude_timer.exe"

[Setup]
AppId={{6B2B7C0E-4B7A-4E4C-9D55-3A6D2E1F0A11}
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={autopf}\EtudeTimer
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=EtudeTimer-setup-{#AppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
WizardStyle=modern
UninstallDisplayIcon={app}\{#AppExe}

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Créer un raccourci sur le Bureau"; Flags: unchecked

[Run]
Filename: "{app}\{#AppExe}"; Description: "Lancer {#AppName}"; Flags: nowait postinstall skipifsilent

; Inno Setup script for the SpaceDragon Robot Programmer.
;
; Every path comes in on the command line, so nothing machine-specific is
; stored in this file and it builds the same on any PC:
;
;   ISCC.exe /DDeployDir="<folder produced by windeployqt>" ^
;            /DOutDir="<where the setup .exe should land>" ^
;            /DAppVersion=1.0 ^
;            packaging\installer.iss
;
; Get Inno Setup from https://jrsoftware.org/isdl.php (free).

#ifndef DeployDir
  #error DeployDir is required, e.g. /DDeployDir="C:\build\stage\SpaceDragon"
#endif

#ifndef OutDir
  #define OutDir "."
#endif

#ifndef AppVersion
  #define AppVersion "1.0"
#endif

#define AppName      "SpaceDragon Robot Programmer"
#define AppPublisher "SpaceDragon"
#define AppExe       "SpaceDragon.exe"

[Setup]
; Keep this GUID stable forever: it is how Windows recognises an upgrade of
; an existing install rather than a second, parallel one.
AppId={{8F3A2C41-6B7D-4E9A-9C15-2D7E4B8A1F60}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}

DefaultDirName={autopf}\SpaceDragon Robot Programmer
DefaultGroupName=SpaceDragon
DisableProgramGroupPage=yes

OutputDir={#OutDir}
OutputBaseFilename=SpaceDragon-{#AppVersion}-Setup
SetupIconFile=spacedragon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}

Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

; Per-user install by default, so downloading and installing needs no admin
; rights. The first page still lets the user pick an all-users install.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#DeployDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}";  Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

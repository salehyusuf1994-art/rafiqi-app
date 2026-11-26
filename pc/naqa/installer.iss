; مثبّت «نقاء» — لا يحتاج صلاحيات مدير، ويثبَّت لحساب المستخدم فقط
#define MyAppName "نقاء"
#define MyAppVersion "1.0.0"
#ifndef LANG
  #define LANG "english"
#endif

[Setup]
AppId={{8B1E6C2A-5F3D-4C9E-9A71-2D7F0B6E4A11}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher=Saleh
DefaultDirName={localappdata}\Programs\Naqa
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\installer
OutputBaseFilename=Naqa-Setup-{#MyAppVersion}
SetupIconFile=naqa.ico
UninstallDisplayIcon={app}\Naqa.exe
UninstallDisplayName={#MyAppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes

[Languages]
#if LANG == "arabic"
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
#else
Name: "english"; MessagesFile: "compiler:Default.isl"
#endif

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "dist\Naqa\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\Naqa.exe"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\Naqa.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Naqa.exe"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; الحذف كامل: النموذج والإعدادات وبقايا أي فصل غير مكتمل
Type: filesandordirs; Name: "{localappdata}\Naqa"

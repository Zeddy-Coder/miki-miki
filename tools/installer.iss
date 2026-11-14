; Inno Setup script for Miki Miki (Windows). Build with tools\build_installer.ps1 (or tools\build_installer.bat).
; Needs Inno Setup 6.3 or newer: winget install JRSoftware.InnoSetup

#define AppName "Miki Miki"
#define AppExe "MikiMiki.exe"
#define AppPublisher "Zeddy"
#define AppUrl "https://github.com/Zeddy-Coder/miki-miki"
#ifndef AppVersion
  #define AppVersion "1.1.5"
#endif
; The folder with the release build (+ Visual C++ runtime), prepared by build_installer.ps1
#ifndef SourceDir
  #define SourceDir "..\build\installer\stage"
#endif

[Setup]
; Never change AppId: it is how upgrades and the uninstaller find the installed copy
AppId={{04B55832-4420-41D7-9C3F-D009D938D6A8}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases
VersionInfoVersion={#AppVersion}
; Per-user install by default (no admin prompt); the wizard offers "for all users" as well
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\{#AppName}
UsePreviousAppDir=yes
DisableDirPage=no
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build
OutputBaseFilename=MikiMiki-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; A running copy is closed before files are replaced and started again afterwards
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "ukrainian"; MessagesFile: "compiler:Languages\Ukrainian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
ukrainian.DesktopIcon=Створити ярлик на робочому столі
ukrainian.StartMenuIcon=Створити ярлик у меню «Пуск»
ukrainian.RunAfter=Запустити {#AppName}
ukrainian.RemoveData=Видалити також налаштування, історію переглядів і журнали ({#AppName})?%n%nЯкщо планується перевстановлення, краще відповісти «Ні».
english.DesktopIcon=Create a desktop shortcut
english.StartMenuIcon=Create a Start menu shortcut
english.RunAfter=Launch {#AppName}
english.RemoveData=Also remove settings, watch history and logs ({#AppName})?%n%nIf you plan to reinstall, answer "No".

[Tasks]
Name: "desktopicon"; Description: "{cm:DesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startmenuicon"; Description: "{cm:StartMenuIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Tasks: startmenuicon
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:RunAfter}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[Code]
// The app keeps settings, history and logs in %APPDATA%\MikiMiki (outside the install folder).
// The uninstaller asks before removing them, so a reinstall keeps everything by default.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    DataDir := ExpandConstant('{userappdata}\MikiMiki');
    if DirExists(DataDir) and (not UninstallSilent) then
      if MsgBox(ExpandConstant('{cm:RemoveData}'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
        DelTree(DataDir, True, True, True);
  end;
end;

#define MyAppName "Music Time"
#define MyAppVersion "2.5.4"
[Setup]
AppId=MusicTime.Experimental
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={localappdata}\Programs\Music Time
DefaultGroupName=Music Time
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=MusicTime-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\music_time.exe
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\Music Time"; Filename: "{app}\music_time.exe"; AppUserModelID: "MusicTime.Desktop"
Name: "{autodesktop}\Music Time"; Filename: "{app}\music_time.exe"; AppUserModelID: "MusicTime.Desktop"; Tasks: desktopicon
[Tasks]
Name: "desktopicon"; Description: "{cm:DesktopShortcut}"; Flags: unchecked
[Run]
Filename: "{app}\music_time.exe"; Description: "{cm:OpenMusicTime}"; Flags: nowait postinstall skipifsilent

[CustomMessages]
english.DesktopShortcut=Create a desktop shortcut
english.OpenMusicTime=Open Music Time
brazilianportuguese.DesktopShortcut=Criar atalho na area de trabalho
brazilianportuguese.OpenMusicTime=Abrir Music Time

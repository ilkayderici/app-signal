; App Signal Windows kurulum programı (Inno Setup 6).
;
; Önce: flutter build windows --release
; Derleme: "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DAppVersion=1.0.4 windows\installer\app_signal.iss
; Çıktı: dist\AppSignal-<sürüm>-setup.exe
;
; AppUserModelID, lib/data/drops.dart içindeki appUserModelId ile aynı
; olmalı; yoksa Windows bildirimleri görünmez.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#define AppName "App Signal"
#define AppExe "app_signal.exe"
#define AppId "dev.appsignal.AppSignal"
#define BuildDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{8C1E4F2A-5B7D-4E61-9A3C-2F0D7B6E1A94}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=dev.appsignal
AppPublisherURL=https://github.com/ilkayderici/app-signal
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\..\dist
OutputBaseFilename=AppSignal-{#AppVersion}-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Kullanıcı başına kurulum (%LOCALAPPDATA%\Programs): UAC sormaz, HKCU
; otomatik başlatma doğru kullanıcıya yazılır, sessiz güncelleme takılmaz.
PrivilegesRequired=lowest
; WinSparkle güncellemesi kurulumu sessiz çalıştırır; açık uygulamayı kapat.
CloseApplications=force
RestartApplications=no

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "autostart"; Description: "Oturum açılınca başlat"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; AppUserModelID: "{#AppId}"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#AppName}"; ValueData: """{app}\{#AppExe}"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\{#AppExe}"; Description: "{#AppName} uygulamasını başlat"; Flags: nowait postinstall skipifsilent
; Sessiz kurulumdan (WinSparkle güncellemesi) sonra da yeniden aç.
Filename: "{app}\{#AppExe}"; Flags: nowait; Check: WizardSilent

[UninstallRun]
Filename: "{cmd}"; Parameters: "/C taskkill /IM {#AppExe} /F"; Flags: runhidden; RunOnceId: "KillApp"

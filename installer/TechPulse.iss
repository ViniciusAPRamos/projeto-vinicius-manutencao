; Instalador do TechPulse (Inno Setup 6). Gerado pelo tools\build.ps1:
;   ISCC.exe /DAppVersion=2.1.0 /DStage=<pasta preparada> /DOutDir=<saída> installer\TechPulse.iss
; Atualização silenciosa (usada pelo próprio app): TechPulse-Setup-x.y.z.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
; Os dados do usuário (Documentos\OtimizadorVinicius) nunca são tocados.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef Stage
  #define Stage "..\dist\app"
#endif
#ifndef OutDir
  #define OutDir "..\dist"
#endif

[Setup]
; AppId fixo: é por ele que o Windows sabe que uma versão nova substitui a antiga. NUNCA mude.
AppId={{6F1C2B7A-4E3D-4C8B-9A51-7D2E0B9C4F13}
AppName=TechPulse
AppVersion={#AppVersion}
AppVerName=TechPulse {#AppVersion}
AppPublisher=Vinícius
AppPublisherURL=https://github.com/ViniciusAPRamos/projeto-vinicius-manutencao
AppUpdatesURL=https://github.com/ViniciusAPRamos/projeto-vinicius-manutencao/releases
DefaultDirName={autopf}\TechPulse
DefaultGroupName=TechPulse
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutDir}
OutputBaseFilename=TechPulse-Setup-{#AppVersion}
SetupIconFile=..\assets\techpulse.ico
UninstallDisplayIcon={app}\TechPulse.exe
UninstallDisplayName=TechPulse
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
VersionInfoVersion={#AppVersion}
VersionInfoProductName=TechPulse

[Languages]
Name: "ptbr"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "atalho"; Description: "Criar atalho na Área de Trabalho"; GroupDescription: "Atalhos:"

[Files]
Source: "{#Stage}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; Atualização limpa: arquivos de versões antigas que saíram do pacote não ficam para trás
Type: filesandordirs; Name: "{app}\src"

[Icons]
Name: "{group}\TechPulse"; Filename: "{app}\TechPulse.exe"
Name: "{autodesktop}\TechPulse"; Filename: "{app}\TechPulse.exe"; Tasks: atalho

[Run]
Filename: "{app}\TechPulse.exe"; Description: "Abrir o TechPulse agora"; Flags: nowait postinstall skipifsilent shellexec

; =============================================================================
;  TATACORA — Système de gestion Intégré : installateur Windows (Inno Setup 6)
;
;  Compilé par build_windows.bat, qui passe la version lue dans pubspec.yaml :
;      ISCC.exe /DAppVersion=1.0.0 installer\tatacora.iss
;  Produit : build\installer\TATACORA_Setup_<version>.exe
;
;  Ce qui est installé : TOUT le dossier de sortie de
;  `flutter build windows --release` (build\windows\x64\runner\Release\) —
;  tatacora_flutter.exe, les DLL (flutter_windows.dll, sqlite3.dll, greffons)
;  et le dossier data\ (flutter_assets, icudtl.dat, app.so) — dans
;  {autopf}\TATACORA (C:\Program Files\TATACORA), plus le modèle
;  poste.example.json.
;
;  Ce qui n'est JAMAIS dans le dossier d'installation, donc JAMAIS effacé par la
;  désinstallation :
;    * la base Drift : %LOCALAPPDATA%\TATACORA\donnees\tatacora.sqlite
;      (lib\core\database\emplacement_base.dart, décision du PO du 17/10/2026 :
;      plus dans Documents ; une ancienne base de Documents y est déménagée au
;      premier démarrage et renommée tatacora.sqlite.deplacee-vers-appdata) ;
;    * la configuration du poste : %APPDATA%\TATACORA\poste.json
;      (mot de passe SMTP, lib\features\transverse\data\configuration_poste.dart).
;  Aucune section [UninstallDelete] ne les vise, et il ne faut pas en ajouter.
; =============================================================================

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#define AppName "TATACORA — Système de gestion Intégré"
#define AppPublisher "TATACORA AFRIQUE"
#define AppExeName "tatacora_flutter.exe"
#define SourceDir AddBackslash(SourcePath) + "..\build\windows\x64\runner\Release"
#define IconFile AddBackslash(SourcePath) + "..\windows\runner\resources\app_icon.ico"

#if !FileExists(SourceDir + "\" + AppExeName)
  #error "Exécutable absent : lancez d'abord flutter build windows --release (build_windows.bat le fait)."
#endif

[Setup]
; Identifiant FIXE de l'application : ne le changez jamais, c'est lui qui fait
; qu'une nouvelle version REMPLACE l'ancienne au lieu de s'installer à côté.
AppId={{DEC5CA97-1885-4584-B238-56FFB05C2724}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoProductName={#AppName}
DefaultDirName={autopf}\TATACORA
DefaultGroupName=TATACORA
DisableProgramGroupPage=yes
OutputDir=..\build\installer
OutputBaseFilename=TATACORA_Setup_{#AppVersion}
#if FileExists(IconFile)
SetupIconFile={#IconFile}
#endif
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Flutter Windows ne produit que du x64.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
; Une mise à jour ferme l'application ouverte avant de remplacer ses fichiers.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Le MODÈLE de la configuration du poste (aucune valeur réelle) — à recopier
; en %APPDATA%\TATACORA\poste.json, voir README_DEPLOY.md.
Source: "poste.example.json"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,TATACORA}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,TATACORA}"; Flags: nowait postinstall skipifsilent

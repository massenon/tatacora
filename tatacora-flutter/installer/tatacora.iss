; =============================================================================
;  TATACORA — Système de gestion Intégré : installateur Windows (Inno Setup 6)
;
;  Compilé par build_windows.bat, qui passe la version lue dans pubspec.yaml :
;      ISCC.exe /DAppVersion=1.0.0 installer\tatacora.iss
;  Produit : build\installer\LogiReStock_Setup_<version>.exe
;
;  Ce qui est installé : TOUT le dossier de sortie de
;  `flutter build windows --release` (build\windows\x64\runner\Release\) —
;  tatacora_flutter.exe, les DLL (flutter_windows.dll, sqlite3.dll, greffons)
;  et le dossier data\ (flutter_assets, icudtl.dat, app.so) — dans
;  {autopf}\LogiReStock (C:\Program Files\LogiReStock ; une installation
;  existante garde son dossier : même AppId), plus le modèle
;  poste.example.json.
;
;  Ce qui n'est PAS dans le dossier d'installation (DÉCISION DU PO du 28/10/2026 :
;  la désinstallation les SUPPRIME, après un avertissement et un choix Oui / Non —
;  voir [UninstallDelete] et [Code] plus bas ; une MISE À JOUR, même AppId, n'y
;  touche jamais) :
;    * la base Drift : %LOCALAPPDATA%\TATACORA\donnees\tatacora.sqlite
;      (lib\core\database\emplacement_base.dart, décision du PO du 17/10/2026 :
;      plus dans Documents ; une ancienne base de Documents y est déménagée au
;      premier démarrage et renommée tatacora.sqlite.deplacee-vers-appdata) ;
;    * la configuration du poste : %APPDATA%\TATACORA\poste.json
;      (mot de passe SMTP, lib\features\transverse\data\configuration_poste.dart).
;  Le coffre du système (Gestionnaire d'identifiants Windows) n'est pas touché.
;  Désinstallation silencieuse (/SILENT, /VERYSILENT) : les données sont GARDÉES
;  (aucune confirmation possible, donc aucune suppression).
; =============================================================================

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

; Nom commercial et éditeur : build_windows.bat les passe à ISCC
; (/DAppName=… /DAppPublisher=…) ; ces valeurs ne servent que si l'on compile
; ce fichier seul.
#ifndef AppName
  #define AppName "LogiReStock"
#endif
#ifndef AppPublisher
  #define AppPublisher "Dr MASSENON Rhodes"
#endif
; Nom du fichier de l'installateur (sans extension, sans la version).
#define SetupBaseName "LogiReStock_Setup"
#define AppExeName "tatacora_flutter.exe"
; Les noms des dossiers de DONNÉES (%LOCALAPPDATA%\TATACORA, %APPDATA%\TATACORA)
; ne changent PAS avec le nom commercial : ils contiennent la base du poste.
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
DefaultDirName={autopf}\LogiReStock
DefaultGroupName=LogiReStock
DisableProgramGroupPage=yes
OutputDir=..\build\installer
OutputBaseFilename={#SetupBaseName}_{#AppVersion}
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
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[UninstallDelete]
; Décision du PO du 28/10/2026 : la désinstallation supprime la base du poste,
; sa configuration, les archives et les reçus — SEULEMENT si l'utilisateur a
; répondu Oui à l'avertissement (SupprimerLesDonnees, posé par
; InitializeUninstall). Une mise à jour ne passe jamais par ici.
Type: filesandordirs; Name: "{localappdata}\TATACORA"; Check: SupprimerLesDonnees
Type: filesandordirs; Name: "{userappdata}\TATACORA"; Check: SupprimerLesDonnees

[Code]
var
  SupprimerDonnees: Boolean;

{ Avertissement AVANT toute désinstallation. Oui = désinstaller ET supprimer les
  données du poste. Non = la désinstallation est ANNULÉE (rien n'est retiré).
  Le bouton par défaut est Non : un Entrée distrait ne supprime rien. }
function InitializeUninstall(): Boolean;
begin
  Result := True;
  SupprimerDonnees := False;
  { Silencieux : pas de question possible, donc les données sont gardées. }
  if UninstallSilent then
    Exit;
  if MsgBox(
    'Désinstaller {#AppName} supprimera aussi TOUTES les données de ce poste :' + #13#10 +
    '  - la base locale (réservations, ventes, factures, stocks, comptabilité...)' + #13#10 +
    '  - la configuration (jeton d''appairage, messagerie SMTP)' + #13#10 +
    '  - les archives de clôture et les reçus de dépenses' + #13#10 + #13#10 +
    'Les saisies NON ENCORE SYNCHRONISÉES avec le serveur seront PERDUES, définitivement. ' +
    'Cette action est irréversible.' + #13#10 + #13#10 +
    'Voulez-vous désinstaller et supprimer ces données ?' + #13#10 + #13#10 +
    'Oui : tout supprimer.     Non : annuler la désinstallation.',
    mbError, MB_YESNO or MB_DEFBUTTON2) = IDYES then
    SupprimerDonnees := True
  else
    Result := False;
end;

function SupprimerLesDonnees(): Boolean;
begin
  Result := SupprimerDonnees;
end;

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

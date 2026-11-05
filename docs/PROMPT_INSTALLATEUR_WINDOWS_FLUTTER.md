# Installateur Windows d'une application Flutter (Inno Setup) — guide et prompt réutilisable

> Tiré de `tatacora-flutter/installer/tatacora.iss` et `tatacora-flutter/build_windows.bat`
> (LogiReStock). Le bloc `text` de la fin se colle tel quel à Claude dans l'autre projet.

## 1. Le principe
Deux fichiers produisent un `Setup.exe` :
- **`build_windows.bat`** enchaîne : `flutter pub get`, génération du code (Drift/build_runner),
  `flutter build windows --release`, puis compile l'installateur avec Inno Setup (`ISCC.exe`).
  Chaque étape ARRÊTE le script si elle échoue.
- **`installer/<app>.iss`** décrit l'installateur : où installer, quels fichiers copier,
  raccourcis, désinstallation.

Sortie : `build\installer\<Nom>_Setup_<version>.exe` (à déplacer vers `installer\Output`
si vous voulez qu'un `flutter clean` ne l'efface pas).

## 2. Prérequis sur la machine de construction
Flutter (dans le PATH), Visual Studio avec « Développement Desktop en C++ », Inno Setup 6
(https://jrsoftware.org/isdl.php, dossier par défaut).

## 3. Les points qui font la différence (leçons réelles)
1. **AppId fixe, jamais modifié.** C'est lui qui fait qu'une nouvelle version REMPLACE
   l'ancienne au lieu de s'installer à côté. Générez-le une fois (GUID) et ne le changez plus.
2. **Les données de l'utilisateur vivent HORS du dossier d'installation** (par exemple
   `%LOCALAPPDATA%\<App>\` pour la base, `%APPDATA%\<App>\` pour la configuration). Une mise
   à jour ne les touche jamais.
3. **Désinstallation** : sans `[UninstallDelete]`, les données restent. Pour les supprimer,
   demandez confirmation (Oui/Non, bouton par défaut = Non), et ne supprimez rien en mode
   silencieux (`/SILENT`, `/VERYSILENT`). Idéalement, proposez d'abord une sauvegarde dans
   `Documents\<App>-Sauvegarde-<date>`, application fermée.
4. **Version lue dans `pubspec.yaml`** (`version: 1.0.0+1`) et passée à ISCC par `/DAppVersion=`,
   pour qu'il n'y ait qu'une seule source de vérité.
5. **Garde-fous de build** : refuser le flavor « demo » en production ; vérifier que
   l'exécutable existe (`#error` dans le `.iss` sinon) ; vérifier que CHAQUE fichier source du
   `.iss` existe et NOMMER celui qui manque. Incident réel : un fichier `poste.example.json`
   supprimé en local a fait échouer Inno Setup avec « The system cannot find the path
   specified », sans nommer le fichier. Réparation : `git restore installer/poste.example.json
   installer/<app>.iss`, puis relancer le script.
6. **Runtime Visual C++** : un poste neuf peut ne pas avoir `msvcp140.dll`, `vcruntime140.dll`,
   `vcruntime140_1.dll` ; sans elles l'application ne démarre pas, sans message utile. Le script
   les copie depuis `C:\Windows\System32` à côté de l'exécutable et ARRÊTE la construction si
   l'une manque. (Vérifiez le droit de redistribution.)
7. **Fermer l'application avant de construire** : un `sqlite3.dll` verrouillé par un
   `flutter_tester` ou une instance en cours fait échouer `flutter build` (« Flutter failed to
   delete file … sqlite3.dll »). `taskkill /F /IM flutter_tester.exe`, fermer l'app, relancer.
8. **`build_runner`** : sur les versions récentes, l'option `--delete-conflicting-outputs`
   n'existe plus (simple avertissement) ; `dart run build_runner build` suffit.
9. **Mise à jour sur place** : `CloseApplications=yes` ferme l'application ouverte avant de
   remplacer ses fichiers ; `RestartApplications=no`.
10. **Un seul nom commercial** (variable du `.bat`, passée à ISCC) pour le nom, l'éditeur, le
    menu Démarrer, « Applications et fonctionnalités » et les propriétés de l'exe.

## 4. Squelette du `.iss`
```ini
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef AppName
  #define AppName "MonApp"
#endif
#ifndef AppPublisher
  #define AppPublisher "Mon Éditeur"
#endif
#define AppExeName "mon_app.exe"
#define SourceDir AddBackslash(SourcePath) + "..\build\windows\x64\runner\Release"
#define IconFile  AddBackslash(SourcePath) + "..\windows\runner\resources\app_icon.ico"
#if !FileExists(SourceDir + "\" + AppExeName)
  #error "Exécutable absent : lancez d'abord flutter build windows --release."
#endif

[Setup]
AppId={{GUID-FIXE-A-GENERER-UNE-FOIS}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\build\installer
OutputBaseFilename={#AppName}_Setup_{#AppVersion}
#if FileExists(IconFile)
SetupIconFile={#IconFile}
#endif
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[UninstallDelete]
Type: filesandordirs; Name: "{localappdata}\MonApp"; Check: SupprimerLesDonnees
Type: filesandordirs; Name: "{userappdata}\MonApp";  Check: SupprimerLesDonnees

[Code]
var SupprimerDonnees: Boolean;
function InitializeUninstall(): Boolean;
begin
  Result := True; SupprimerDonnees := False;
  if UninstallSilent then Exit;
  if MsgBox('Désinstaller supprimera aussi TOUTES les données de ce poste (base, configuration, archives). ' +
            'Les saisies non synchronisées seront PERDUES.' + #13#10 + #13#10 +
            'Oui : tout supprimer.   Non : annuler la désinstallation.',
            mbError, MB_YESNO or MB_DEFBUTTON2) = IDYES
  then SupprimerDonnees := True
  else Result := False;
end;
function SupprimerLesDonnees(): Boolean;
begin Result := SupprimerDonnees; end;

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
```

## 5. Le prompt à coller dans l'autre projet
```text
Tu es ingénieur release Windows. Dans ce projet Flutter (cible Windows), crée l'installateur
Inno Setup 6 et son script de construction. Réponds en français, avance par étapes testables.

LIVRABLES
1. `installer/<app>.iss` : AppId FIXE (GUID généré une fois, jamais modifié), AppName/
   AppPublisher/AppVersion passés par /D (valeurs de repli pour une compilation seule),
   installation dans {autopf}\<App>, copie récursive de
   build\windows\x64\runner\Release, raccourcis menu Démarrer + bureau (case décochée),
   lancement en fin d'installation, CloseApplications=yes, x64 uniquement, français,
   icône si windows\runner\resources\app_icon.ico existe, #error si l'exe est absent.
2. `build_windows.bat` (à lancer depuis le dossier du projet, `cd /d "%~dp0"`) : lit la version
   dans pubspec.yaml (partie avant le +), refuse le flavor « demo » en production, vérifie
   `flutter` et ISCC.exe (Program Files (x86)\Inno Setup 6, Program Files, LOCALAPPDATA,
   where), puis : flutter pub get ; dart run build_runner build (si le projet génère du code ;
   sans --delete-conflicting-outputs, retiré des versions récentes) ; flutter analyze (stop
   si erreur) ; flutter test (option --sans-tests) ; flutter build windows --release
   --dart-define=ENV=<production|recette|dev> ; copie des DLL du runtime Visual C++
   (msvcp140.dll, vcruntime140.dll, vcruntime140_1.dll depuis System32) à côté de l'exe, ARRÊT
   si l'une manque ; VÉRIFIE que chaque fichier source cité dans le .iss existe et NOMME celui
   qui manque (un fichier supprimé en local donne sinon « The system cannot find the path
   specified » sans nom) ; puis ISCC /DAppVersion=... "/DAppName=..." "/DAppPublisher=..." ;
   chaque étape arrête le script avec un message clair ; le nom de sortie suit
   l'environnement (suffixe -recette/-dev hors production) ; sortie finale dans
   installer\Output (un `flutter clean` détruit build\).
3. Données utilisateur HORS du dossier d'installation (%LOCALAPPDATA%\<App>\ base,
   %APPDATA%\<App>\ configuration) : une mise à jour (même AppId) ne les touche jamais.
4. Désinstallation : proposer d'abord une sauvegarde dans Documents\<App>-Sauvegarde-<date>
   (application fermée avant la copie), puis avertissement Oui/Non (défaut = Non, Non annule
   la désinstallation), puis suppression des deux dossiers de données SEULEMENT si Oui ;
   désinstallation silencieuse = données gardées.
5. README_DEPLOY.md : prérequis (Flutter, Visual Studio « Développement Desktop en C++ »,
   Inno Setup 6), commande de construction, où est le .exe, contenu installé, emplacement des
   données, comment tester (installer, mettre à jour, désinstaller Oui/Non/silencieux), et les
   pièges : fermer l'app et tout flutter_tester avant de construire (sqlite3.dll verrouillé),
   `git restore` d'un fichier d'installateur supprimé, runtime Visual C++ sur un poste neuf.

TESTS À DÉCRIRE ET FAIRE FAIRE (sur Windows, tu ne peux pas compiler Inno Setup sur Linux) :
installation neuve ; installation par-dessus une version précédente (données conservées) ;
désinstallation Non (rien n'est retiré) ; Oui (données supprimées) ; silencieuse (gardées) ;
poste sans runtime Visual C++ ; fichier source manquant (message qui nomme le fichier).
```

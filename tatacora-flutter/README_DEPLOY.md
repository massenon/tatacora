# TATACORA — Déploiement sur les postes Windows

Ce document explique comment **construire l'installateur** de TATACORA —
Système de gestion Intégré, puis comment **l'installer** et **le mettre en
service** sur les postes du Comptable et du Gérant.

Chaque poste a **sa propre base de données**, sur son disque : le logiciel
fonctionne entièrement hors connexion, des jours durant s'il le faut. Deux
actions réseau existent, toutes deux en **tâche de fond** — aucun écran ne les
attend, la clôture de caisse comprise :

- la **synchronisation** des saisies du poste vers le serveur
  `https://logirestock.digitonpro.com`, une fois le poste **appairé**
  (section 6) ;
- l'envoi des messages à l'éditeur (« Contactez l'éditeur »), par courriel
  (SMTP, section 5).

---

## 1. Le PC de construction (une seule machine, chez l'intégrateur)

### Prérequis

| Outil | Version | Remarque |
|---|---|---|
| Windows 10 ou 11, 64 bits | — | La construction Windows ne se fait que sous Windows. |
| Flutter | canal stable, Dart compatible avec `sdk: ^3.12.2` (`pubspec.yaml`) | Installer Flutter, puis ajouter `…\flutter\bin` au `PATH`. Vérifier avec `flutter doctor`. |
| Visual Studio 2022 (Community suffit) | charge de travail **« Développement Desktop en C++ »** | Avec le SDK Windows 10/11 et les outils CMake (cochés par défaut dans cette charge). `flutter doctor` doit afficher la ligne Visual Studio en vert. |
| Inno Setup 6 | 6.x | https://jrsoftware.org/isdl.php — installer dans le dossier proposé (`C:\Program Files (x86)\Inno Setup 6`). Le français est inclus. |
| Git | — | Pour récupérer le code. |

Activer la cible Windows une fois : `flutter config --enable-windows-desktop`.

### Construire l'installateur

Dans une invite de commandes, depuis le dossier `tatacora-flutter` :

```bat
build_windows.bat
```

Le script enchaîne, et **s'arrête à la première erreur** :

1. `flutter pub get`
2. `dart run build_runner build --delete-conflicting-outputs` (code de la base Drift)
3. `flutter build windows --release -t lib\main.dart --dart-define=ENV=production`
   — le point d'entrée de **production** (jamais `main_demo.dart`)
4. Inno Setup (`ISCC.exe`) compile `installer\tatacora.iss`

Résultat : **`build\installer\TATACORA_Setup_<version>.exe`** (la version est
celle de la ligne `version:` de `pubspec.yaml`, sans le `+build`).

Si Inno Setup est introuvable, le script le dit et s'arrête : l'installer, puis
relancer. Un autre flavor que la production se construit avec
`build_windows.bat recette` (le flavor `demo` est refusé).

> Avant de livrer une nouvelle version : augmenter `version:` dans
> `pubspec.yaml` (par exemple `1.0.1+2`).

---

## 2. Installer sur le PC du Comptable et sur le PC du Gérant

Sur **chaque** poste, avec un compte Windows administrateur :

1. Copier `TATACORA_Setup_<version>.exe` sur le poste (clé USB, partage…).
2. Le lancer et suivre l'assistant (en français). Si Windows SmartScreen
   avertit « éditeur inconnu », cliquer sur « Informations complémentaires »
   puis « Exécuter quand même » (l'installateur n'est pas signé).
3. Dossier proposé : `C:\Program Files\TATACORA` — le garder.
4. Cocher « Créer une icône sur le Bureau » si souhaité. Un raccourci est
   toujours créé dans le menu Démarrer.
5. Terminer : le logiciel peut se lancer tout de suite.

Rien d'autre à installer : les bibliothèques nécessaires (dont `sqlite3.dll`)
sont dans le dossier d'installation.

---

## 3. Premier lancement

1. **Création du compte Administrateur.** Un poste neuf n'a aucun compte, et
   aucun mot de passe par défaut n'existe. L'écran de démarrage demande de
   créer le compte administrateur (« Créer le compte administrateur ») :
   choisir un identifiant et un mot de passe solide, et **les conserver en
   lieu sûr** — ils ne peuvent pas être récupérés.
2. **Créer les autres comptes.** Connecté en administrateur, ouvrir
   **« Comptes utilisateurs »** et créer un compte par personne qui utilisera
   ce poste, avec **le bon rôle** : « Comptable » pour le Comptable,
   « Gérant / Direction » pour le Gérant. Les droits de chaque rôle se
   règlent dans **« Rôles & Permissions »**. Transmettre à chacun son
   identifiant et son mot de passe ; il pourra le changer depuis « Mon profil ».
3. **Paramètres à renseigner tout de suite** (écran **Paramètres**) :
   - onglet **« Activation & Sécurité »**, section « Charges sociales » :
     **« CNSS risques professionnels (%) »** — le taux figurant sur la
     **notice d'immatriculation / l'avis de la CNSS** de l'établissement
     (entre 1 et 4 %). Tant qu'il est vide, la charge patronale de la paie
     n'est publiée qu'en fourchette ;
   - onglet **« Identité & Légal »**, « Informations légales & fiscales » :
     **« Régime fiscal »** (réel normal, réel simplifié ou TPU) — il est
     imprimé dans les mentions légales des états ;
   - vérifier au passage les informations de l'établissement (raison sociale,
     IFU, RCCM…), pré-remplies à la création du premier compte, et l'onglet
     **« Email (SMTP) »** (serveur, port, sécurité, utilisateur — également
     pré-remplis).
4. **Configurer le mot de passe SMTP** du poste (section 5) pour que
   « Contactez l'éditeur » puisse envoyer.
5. **Appairer le poste au serveur** (section 6) pour que ses saisies
   remontent.

---

## 4. Où vivent les données, et comment les sauvegarder

| Quoi | Où | Effacé à la désinstallation ? |
|---|---|---|
| Le logiciel | `C:\Program Files\TATACORA\` | Oui |
| **La base de données** (toutes les saisies) | `%LOCALAPPDATA%\TATACORA\donnees\tatacora.sqlite` — un dossier **caché** du compte Windows (par exemple `C:\Users\Comptable\AppData\Local\TATACORA\donnees\tatacora.sqlite`), hors de Documents pour éviter une suppression involontaire | **Non** |
| La configuration du poste (mot de passe SMTP, appairage au serveur) | `%APPDATA%\TATACORA\poste.json` (par exemple `C:\Users\Comptable\AppData\Roaming\TATACORA\poste.json`) | **Non** |

Remarques importantes :

- La base est **propre au compte Windows** : deux comptes Windows sur le même
  PC auraient deux bases distinctes. Utiliser TOUJOURS le même compte Windows
  pour TATACORA sur un poste donné.
- **Mise à jour d'un poste installé avant le 17/10/2026** : sa base était dans
  `Documents\tatacora.sqlite`. Au premier démarrage de la nouvelle version, elle
  est **copiée automatiquement** dans le nouveau dossier (journal compris), puis
  l'ancien fichier est renommé `tatacora.sqlite.deplacee-vers-appdata` — il
  n'est jamais effacé et n'est plus jamais relu. Une fois le poste vérifié
  (les saisies sont là), ce fichier renommé peut être archivé ou supprimé.
- Le nouveau dossier n'est **pas** synchronisé par OneDrive (une base SQLite
  synchronisée par OneDrive se corrompt). Ne jamais copier la base d'un PC sur
  un autre : chaque poste a la sienne, la synchronisation avec le serveur fait
  le reste.
- Pour voir le dossier : touche Windows + R, taper `%LOCALAPPDATA%\TATACORA`,
  Entrée.

### Sauvegarder

Dans le logiciel : **Import & Export → onglet « Sauvegardes de la base » →
« Générer une sauvegarde de la base »**. Une fenêtre « Enregistrer sous »
s'ouvre : enregistrer la copie **hors du PC** (clé USB, disque externe) et
garder plusieurs copies datées. Le faire **au moins chaque jour de
travail**, et toujours avant une mise à jour.

Le logiciel ne conserve aucune sauvegarde de lui-même : sans ce geste, une
panne du disque fait perdre toutes les saisies du poste.

---

## 5. Configurer le mot de passe SMTP (« Contactez l'éditeur »)

« Contactez l'éditeur » (« Envoyer un message », « Signaler un bug ») envoie
réellement un courriel à l'éditeur. Le serveur, le port, la sécurité et
l'utilisateur SMTP se règlent dans **Paramètres → « Email (SMTP) »**. Le **mot
de passe**, lui, n'est **jamais** enregistré dans le logiciel ni dans sa base :
il se pose dans un fichier du poste.

Sur chaque poste :

1. Ouvrir l'Explorateur, taper `%APPDATA%` dans la barre d'adresse, Entrée.
2. Créer le dossier **`TATACORA`** s'il n'existe pas.
3. Y copier le modèle `C:\Program Files\TATACORA\poste.example.json` et le
   **renommer `poste.json`** (vérifier que Windows n'a pas ajouté `.txt`).
4. L'ouvrir avec le Bloc-notes et écrire le mot de passe entre les guillemets :

   ```json
   {
     "smtp_mot_de_passe": "le-mot-de-passe-de-la-boite-d-envoi"
   }
   ```

   (Un guillemet `"` ou une barre oblique inverse `\` dans le mot de passe
   s'écrit `\"` ou `\\`.)
5. Enregistrer. Aucun redémarrage n'est nécessaire : le fichier est relu à
   chaque envoi.

Ce fichier ne doit **jamais** être copié dans le dépôt de code, envoyé par
courriel ni laissé sur une clé USB.

### Comment se comporte l'envoi

- Le message est **d'abord enregistré sur le poste**, puis envoyé (20 s au
  plus). Envoyé : « Message envoyé à l'éditeur. ». Hors connexion ou refusé :
  « Message enregistré sur ce poste — il partira dès que la connexion
  reviendra. »
- Les messages en attente repartent **seuls** : au démarrage du logiciel,
  puis toutes les 5 minutes (avec un délai croissant après chaque échec).
- L'écran « Contactez l'éditeur » affiche l'encart **« Messages en attente
  d'envoi »** (nombre et dernière erreur) et le bouton « Renvoyer
  maintenant ». Si le mot de passe manque, la dernière erreur le dit et donne
  le chemin du fichier attendu.
- Aucun message n'est jamais supprimé.

---

## 6. Appairer le poste au serveur (synchronisation)

Le poste enregistre tout sur place, puis **envoie ses opérations au serveur en
tâche de fond** : au démarrage, toutes les 5 minutes tant qu'il en reste à
envoyer, et juste après chaque clôture de caisse. Pour cela, il doit être
**appairé une fois** à un compte du serveur.

Sur chaque poste, connecté avec un compte **Administrateur** du poste :

1. Ouvrir **Paramètres → onglet « Synchronisation »** (l'onglet n'apparaît
   qu'aux Administrateurs).
2. Saisir l'**identifiant** et le **mot de passe d'un compte du serveur**
   (compte gérant ou administrateur créé sur le serveur — pas un compte du
   poste). Ce mot de passe sert à obtenir un jeton et n'est **enregistré
   nulle part**.
3. Vérifier le **Nom du poste** : il est pré-rempli avec le nom Windows du PC
   (lettres, chiffres, `-`, `_`, `.`). Deux postes doivent avoir des noms
   **différents** : c'est sous ce nom que le serveur reconnaît chaque poste.
4. Cliquer **« Appairer le poste »**. Réussi : « Poste « … » appairé ». L'état
   affiche alors le serveur, le nom du poste, le compte et la date.
5. Cliquer **« Tester la connexion »** : « Connexion établie… ».

Messages possibles et que faire :

| Message | Que faire |
|---|---|
| Identifiants refusés par le serveur | Vérifier l'identifiant et le mot de passe du compte **serveur**. |
| Ce compte est désactivé sur le serveur | Faire réactiver le compte sur le serveur, ou en utiliser un autre. |
| Trop de tentatives | Attendre quelques minutes (blocage du serveur après 5 échecs). |
| Serveur injoignable | Vérifier la connexion Internet du poste, puis réessayer. |
| Jeton refusé — réappairer le poste | Le jeton a été révoqué (ou le compte appairé une seconde fois sous le même nom de poste) : refaire les étapes 2 à 4. La synchronisation reste suspendue jusque-là ; rien n'est perdu. |

Ce que l'appairage écrit : le nom du poste, le jeton, l'adresse du serveur, la
date et l'identifiant du compte, dans `%APPDATA%\TATACORA\poste.json` (à côté
du mot de passe SMTP, qui est conservé). Le fichier est remplacé d'un bloc à
chaque écriture. **Ne pas modifier ces clés à la main.**

**« Dissocier »** retire le jeton du poste (et le révoque au serveur si le
réseau est là). Les opérations en attente **restent sur le poste** : elles
partiront après un nouvel appairage.

Un poste hors connexion continue de travailler normalement : ses opérations
attendent, et repartent seules quand le réseau revient (avec un délai
croissant après chaque échec, une heure au plus). Rien n'est jamais supprimé.

---

## 7. Mettre à jour

1. Faire une **sauvegarde** (section 4).
2. Fermer TATACORA.
3. Lancer le nouveau `TATACORA_Setup_<version>.exe` : il remplace l'ancienne
   version au même endroit.
4. Au premier lancement, la base est mise à jour automatiquement, sans perte
   de données (migrations additives). Ne jamais revenir à une version
   antérieure du logiciel sur une base déjà mise à jour.

## 8. Désinstaller

Panneau de configuration → Programmes → « TATACORA — Système de gestion
Intégré » → Désinstaller (ou le raccourci « Désinstaller TATACORA » du groupe
TATACORA du menu Démarrer).

La désinstallation **ne supprime ni la base** (`%LOCALAPPDATA%\TATACORA\donnees\tatacora.sqlite`)
**ni la configuration** (`%APPDATA%\TATACORA\poste.json`) : une
réinstallation retrouve toutes les données. Pour effacer réellement les
données d'un poste (poste réformé), supprimer ces deux fichiers à la main,
**après** en avoir fait une sauvegarde.

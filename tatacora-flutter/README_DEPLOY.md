# TATACORA — Déploiement sur les postes Windows

Ce document explique comment **construire l'installateur** de TATACORA —
Système de gestion Intégré, puis comment **l'installer** et **le mettre en
service** sur les postes du Comptable et du Gérant.

Chaque poste a **sa propre base de données**, sur son disque : le logiciel
fonctionne entièrement hors connexion. La **seule** action réseau est l'envoi
des messages à l'éditeur (« Contactez l'éditeur »), par courriel (SMTP).

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

---

## 4. Où vivent les données, et comment les sauvegarder

| Quoi | Où | Effacé à la désinstallation ? |
|---|---|---|
| Le logiciel | `C:\Program Files\TATACORA\` | Oui |
| **La base de données** (toutes les saisies) | `%USERPROFILE%\Documents\tatacora.sqlite` — le dossier **Documents** du compte Windows (par exemple `C:\Users\Comptable\Documents\tatacora.sqlite`) | **Non** |
| La configuration du poste (mot de passe SMTP) | `%APPDATA%\TATACORA\poste.json` (par exemple `C:\Users\Comptable\AppData\Roaming\TATACORA\poste.json`) | **Non** |

Remarques importantes :

- La base est **propre au compte Windows** : deux comptes Windows sur le même
  PC auraient deux bases distinctes. Utiliser TOUJOURS le même compte Windows
  pour TATACORA sur un poste donné.
- Si le dossier Documents est synchronisé par OneDrive, la base peut se
  trouver sous `C:\Users\<compte>\OneDrive\Documents\`. Ne pas ouvrir le
  logiciel sur deux PC à partir de la même base synchronisée.

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

## 6. Mettre à jour

1. Faire une **sauvegarde** (section 4).
2. Fermer TATACORA.
3. Lancer le nouveau `TATACORA_Setup_<version>.exe` : il remplace l'ancienne
   version au même endroit.
4. Au premier lancement, la base est mise à jour automatiquement, sans perte
   de données (migrations additives). Ne jamais revenir à une version
   antérieure du logiciel sur une base déjà mise à jour.

## 7. Désinstaller

Panneau de configuration → Programmes → « TATACORA — Système de gestion
Intégré » → Désinstaller (ou le raccourci « Désinstaller TATACORA » du groupe
TATACORA du menu Démarrer).

La désinstallation **ne supprime ni la base** (`Documents\tatacora.sqlite`)
**ni la configuration** (`%APPDATA%\TATACORA\poste.json`) : une
réinstallation retrouve toutes les données. Pour effacer réellement les
données d'un poste (poste réformé), supprimer ces deux fichiers à la main,
**après** en avoir fait une sauvegarde.

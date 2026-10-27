# Guide : cloner, tester, mettre à jour, repartir d'une base propre (web + poste)

> Rédigé le 20/10/2026 pour le Product Owner. Il porte sur la branche de
> travail `claude/quirky-johnson-2pbs4t`, celle de la PR #2, **pas encore
> fusionnée dans `main`**.

## 0. Avant tout : la bonne branche

Tout le travail récent est sur la branche **`claude/quirky-johnson-2pbs4t`** :

- exploitation (cron, essais, vérifications) ;
- passage d'année ;
- clôture SYSCOHADA ;
- archive légale ;
- comparatif N / N−1.

`main` (la branche clonée par défaut) n'a **pas** ces fichiers. C'est
pourquoi `docs/` y paraît presque vide.

```bash
# Nouveau clone, directement sur la branche
git clone -b claude/quirky-johnson-2pbs4t https://github.com/massenon/tatacora.git
cd tatacora

# Ou, dans un clone existant
git fetch origin
git checkout claude/quirky-johnson-2pbs4t
git pull origin claude/quirky-johnson-2pbs4t
```

Le dépôt contient trois dossiers :

| Dossier | Contenu |
|---|---|
| `tatacora-api/` | Le serveur : Laravel 12 et la PWA web. |
| `tatacora-flutter/` | Le poste Windows, hors ligne. |
| `docs/` | Les guides, dont celui-ci. |

⚠ **La base du poste est la même quel que soit le type de build.** Elle
est rangée dans `%LOCALAPPDATA%\TATACORA\donnees\tatacora.sqlite`. Une
version de test lancée sur un PC de production ouvre donc la base réelle.

**Testez sur un PC (ou un compte Windows) qui n'est pas un poste en
service**, ou sauvegardez la base avant (section B6).

---

## A. Le WEB (serveur)

Deux cas : **A1** pour tester sur votre PC, **A2** pour déployer la branche
sur cPanel.

### A1. Tester sur un PC (local)

**Prérequis** :

- PHP 8.2 ou plus, avec les extensions `pdo_mysql`, `bcmath`, `zip`,
  `mbstring`, `gd` ;
- Composer 2 ;
- MySQL 8 ou MariaDB 10.6 ou plus ;
- Git.

Node n'est **pas** nécessaire : la PWA n'a aucun fichier à compiler.

```bash
cd tatacora-api
composer install
cp .env.example .env            # Windows : copy .env.example .env
php artisan key:generate
```

Dans `.env`, renseigner au minimum :

```ini
DB_DATABASE=tatacora_dev        # créer la base vide dans MySQL avant
DB_USERNAME=root
DB_PASSWORD=...
# Les comptes réels : mots de passe lus UNIQUEMENT ici (aucun mot de passe dans le code)
COMPTE_RODRIGUE_MOT_DE_PASSE=...
COMPTE_BIENVENU_MOT_DE_PASSE=...
COMPTE_NOEL_MOT_DE_PASSE=...
COMPTE_SUPER_ADMIN_MOT_DE_PASSE=...
```

**Base propre et premiers comptes** :

```bash
php artisan migrate:fresh --seed                     # EFFACE tout, recrée les tables + référentiels
php artisan db:seed --class=ComptesReelsSeeder       # crée rodrigue, bienvenu, noel, super_admin
# facultatif, jeu de démonstration :
# php artisan db:seed --class=DemonstrationSeeder
```

`--seed` ne sème que les référentiels indispensables :

- rôles et droits ;
- canaux de réservation ;
- plan comptable SYSCOHADA, journaux (dont CL et AN), centres de coût et
  exercice de l'année ;
- les 20 paramètres de l'établissement ;
- les modèles de notification.

Il ne sème **aucune** donnée métier.

**Lancer** :

```bash
php artisan serve --host=0.0.0.0 --port=8000
```

Ouvrir **http://localhost:8000/pwa/connexion** et se connecter avec
`rodrigue` ou `noel`, avec les mots de passe du `.env`. Le port **8000** est
celui qu'attend la version « dev » du poste (section B3).

**Passer les tests automatiques**. Ils utilisent une base séparée,
`tatacora_test`, à créer vide dans MySQL :

```bash
php artisan test                # ~12 min, 1 787 tests au 20/10/2026
```

### A2. Déployer la branche sur cPanel (logirestock.digitonpro.com)

**Première installation**, dans le Terminal cPanel (ou *Git Version
Control*, en indiquant la branche `claude/quirky-johnson-2pbs4t`) :

```bash
cd ~
git clone -b claude/quirky-johnson-2pbs4t https://github.com/massenon/tatacora.git
cd tatacora/tatacora-api
composer install --no-dev --optimize-autoloader
cp .env.example .env
php artisan key:generate         # UNE SEULE FOIS, jamais plus : le mot de passe SMTP chiffré en dépend
```

Faire pointer le domaine (*Document Root*) vers `.../tatacora/tatacora-api/public`.

Dans le `.env` de production :

```ini
APP_ENV=production
APP_DEBUG=false
APP_URL=https://logirestock.digitonpro.com
DB_DATABASE=... DB_USERNAME=... DB_PASSWORD=...
MAIL_PASSWORD=                   # vide : le mot de passe SMTP se saisit dans la PWA (Paramètres → Email), chiffré en base
TATACORA_PHASE_ESSAIS=true       # PENDANT les essais seulement (voir C)
COMPTE_..._MOT_DE_PASSE=...      # le temps de créer les comptes, puis les retirer du .env
```

Puis :

```bash
php artisan migrate --force
php artisan db:seed --force                              # référentiels (idempotent, ne double rien)
php artisan db:seed --class=ComptesReelsSeeder --force   # premiers comptes
php artisan optimize:clear
php artisan tatacora:verifier-production                 # aucun ÉCHEC attendu
```

Enfin, **poser la ligne cron** (section D).

### A3. Mettre à jour le web après un nouveau `git pull`

**En local** :

```bash
cd tatacora/tatacora-api
git pull origin claude/quirky-johnson-2pbs4t
composer install
php artisan migrate
php artisan optimize:clear
```

**Sur cPanel** :

```bash
cd ~/tatacora/tatacora-api
git pull origin claude/quirky-johnson-2pbs4t
composer install --no-dev --optimize-autoloader
php artisan migrate --force
php artisan optimize:clear
php artisan tatacora:verifier-production
```

La mise à jour du 20/10/2026 ajoute, via `migrate` :

- la table `clotures_exercices` ;
- les journaux **CL** (clôture) et **AN** (à-nouveaux) ;
- la table `generations_donnees`, ajoutée le 19/10.

### A4. Repartir d'une base propre (web)

| Situation | Commande / geste | Ce qui est effacé |
|---|---|---|
| **PC de test** | `php artisan migrate:fresh --seed`, puis `php artisan db:seed --class=ComptesReelsSeeder` | **Tout**, comptes compris (recréés par le seeder). Supprimer aussi `storage/app/private/archives/` s'il existe. |
| **Production pendant les essais** | PWA : Paramètres → Activation & Sécurité → ouvrir « Réinitialisation des données de test », puis Import & Export → onglet « Réinitialiser les données de test » → « Réinitialiser comme neuf », taper `VIDER`. Une sauvegarde est faite juste avant. | Toutes les opérations (clients, ventes, factures, écritures…). Les **comptes, paramètres, chambres, cartes, plan comptable sont gardés**. Les exercices clôturés pendant les essais redeviennent ouverts, et les archives d'essai sont effacées. |
| **Production après les essais** | Impossible, par conception. | — |

⚠ **Ne lancez jamais `migrate:fresh` sur la production.** Il efface tout, y
compris les comptes, l'appairage des postes et le journal d'audit, sans
sauvegarde. La procédure détaillée des essais est dans
[`ESSAIS_EN_PRODUCTION_ET_REINITIALISATION.md`](ESSAIS_EN_PRODUCTION_ET_REINITIALISATION.md).

---

## B. Le POSTE (Windows)

### B1. Prérequis (PC de construction, sous Windows uniquement)

| Outil | Remarque |
|---|---|
| Windows 10 ou 11, 64 bits | — |
| Flutter (canal stable, Dart compatible avec `sdk: ^3.12.2`) | Ajouter `...\flutter\bin` au `PATH`, puis `flutter config --enable-windows-desktop`, puis `flutter doctor`. |
| Visual Studio 2022, charge « Développement Desktop en C++ » | Doit être en vert dans `flutter doctor`. |
| Inno Setup 6 | Seulement pour fabriquer l'installateur (B4). |
| Git | — |

Détail complet : [`tatacora-flutter/README_DEPLOY.md`](../tatacora-flutter/README_DEPLOY.md).

### B2. Préparer le code

```bat
cd tatacora\tatacora-flutter
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### B3. Tester contre VOTRE serveur local (version « dev »)

La version dev parle à `http://localhost:8000/api/v1`. Il faut donc
lancer d'abord le serveur sur le même PC (A1 : `php artisan serve --port=8000`).

```bat
flutter run -d windows
```

1. **Premier lancement** : l'écran demande de créer le compte administrateur
   **du poste**. Il n'existe aucun mot de passe par défaut.
2. **Appairer le poste** : Paramètres → onglet **Synchronisation**. Saisir un
   compte **du serveur** (par exemple `rodrigue`) et un nom de poste unique,
   puis « Appairer le poste » et « Tester la connexion ».
3. Le bouton de synchronisation (barre du haut) passe au **vert** quand
   tout est envoyé.

### B4. Fabriquer l'installateur (production → logirestock.digitonpro.com)

```bat
cd tatacora\tatacora-flutter
build_windows.bat
```

Le résultat est `build\installer\LogiReStock_Setup_<version>.exe`.

1. Installez-le sur chaque poste, en commençant par un poste de test.
2. Créez le compte administrateur du poste, puis appairez-le (B3, étape 2)
   avec un compte du serveur de production.

Avant de livrer une nouvelle version, augmentez `version:` dans
`pubspec.yaml`, par exemple `1.0.1+2`.

### B5. Mettre à jour le poste après un `git pull`

```bat
cd tatacora\tatacora-flutter
git pull origin claude/quirky-johnson-2pbs4t
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d windows            REM en test
build_windows.bat                 REM ou nouvel installateur, à réinstaller par-dessus
```

La réinstallation **garde la base et l'appairage**, rangés hors du dossier
du logiciel. Si le schéma de la base change, la base se met à niveau toute
seule au démarrage, sans rien effacer.

Exemple de ce que cette mise à jour apporte au poste :

- l'exercice N+1 s'ouvre de lui-même ;
- les exercices descendent du serveur avec leur statut ;
- les boutons « ← Exercice N−1 » / « Exercice N+1 → » ;
- le bandeau « en clôture » / « clôturé ».

### B6. Repartir d'une base propre (poste)

| Situation | Geste |
|---|---|
| **Après la réinitialisation du serveur (essais)** | (1) « Synchroniser maintenant » : le voyant passe au **rouge** (« Le serveur a été réinitialisé… »). (2) En administrateur du poste : Import & Export → onglet « Réinitialiser les données de test » → « Réinitialiser comme neuf », taper `VIDER`. (3) « Synchroniser maintenant » : le catalogue remis à neuf descend, le voyant passe au **vert**. Les comptes et l'appairage du poste sont gardés. |
| **PC de test : tout effacer, comme une première installation** | Fermer TATACORA, puis supprimer les fichiers du tableau ci-dessous. Au lancement suivant, le poste repart vierge : il faut recréer le compte administrateur et réappairer. |

Fichiers à supprimer pour tout effacer sur un PC de test (Windows + R, puis
coller le chemin) :

| Chemin | Ce qu'il contient |
|---|---|
| `%LOCALAPPDATA%\TATACORA\donnees\tatacora.sqlite`, avec ses fichiers `-wal` et `-shm` | La base du poste. |
| `%APPDATA%\TATACORA\poste.json` | L'appairage et le mot de passe SMTP du poste. |

⚠ Effacer la base d'un poste supprime **définitivement** ce qui n'a pas
encore été envoyé au serveur. Avant, cliquez « Synchroniser maintenant » et
attendez le **vert**.

**Sauvegarde** avant tout essai sur un vrai poste : copier le dossier
`%LOCALAPPDATA%\TATACORA\donnees\`, application fermée.

### B7. Tests automatiques du poste (facultatif, développeur)

```bat
flutter analyze
flutter test        REM ~9 min, 3 717 tests au 20/10/2026
```

Ils exigent PHP, Node et la base MySQL `tatacora_test` : plusieurs tests
rejouent le vrai serveur pour comparer les résultats.

---

## C. Ordre conseillé pour une campagne d'essais complète

1. **Serveur** : déployer la branche (A2), `TATACORA_PHASE_ESSAIS=true`,
   `verifier-production` sans ÉCHEC, ligne cron posée (D).
2. **Postes** : installer la version courante (B4) **avant** toute
   réinitialisation du serveur, puis les appairer.
3. **Essais** : suivre les scénarios de
   [`ESSAIS_EN_PRODUCTION_ET_REINITIALISATION.md`](ESSAIS_EN_PRODUCTION_ET_REINITIALISATION.md),
   plus ceux de la clôture
   ([`CLOTURE_EXERCICE_SYSCOHADA.md`](CLOTURE_EXERCICE_SYSCOHADA.md)) :
   1. démarrer la clôture ;
   2. passer une écriture d'inventaire ;
   3. clôturer ;
   4. télécharger l'archive ;
   5. rouvrir (en comptable) ;
   6. naviguer entre N−1 et N.
4. **Remise à neuf** : le serveur d'abord (A4), puis **chaque poste** (B6).
5. **Fin des essais** : retirer `TATACORA_PHASE_ESSAIS`, lancer
   `php artisan optimize:clear` puis `verifier-production`. Suivre ensuite
   [`VERIFICATIONS_APRES_MISE_EN_PRODUCTION.md`](VERIFICATIONS_APRES_MISE_EN_PRODUCTION.md).

---

## D. Les tâches cron sur cPanel

Détail complet : [`LISTE_DES_CRON_JOBS_CPANEL.md`](LISTE_DES_CRON_JOBS_CPANEL.md).

**Une seule ligne** à poser dans cPanel → *Tâches Cron* → « Ajouter une
nouvelle tâche cron » :

| Champ | Valeur |
|---|---|
| Fréquence | Une fois par minute (`* * * * *`) |
| Commande | `cd /home/<COMPTE>/tatacora/tatacora-api && /usr/local/bin/php artisan schedule:run >> /dev/null 2>&1` |

- Remplacez `<COMPTE>` par votre compte cPanel.
- Vérifiez le chemin de PHP (8.2 ou plus) avec `which php` puis `php -v`.
  Selon le serveur, ce peut être `/opt/cpanel/ea-php83/root/usr/bin/php`.
- Ne créez **pas** une ligne par tâche : Laravel répartit lui-même les
  tâches ci-dessous.

Heures en UTC : ajoutez 1 h pour l'heure du Bénin.

| Tâche | Quand | Rôle |
|---|---|---|
| `tatacora:battement-planificateur` | chaque minute | Preuve que le cron tourne. |
| `queue:work --stop-when-empty` | chaque minute | Envoie les courriels et les notifications en attente. |
| `tatacora:ouvrir-exercices` | chaque jour à 00:05 | Ouvre l'exercice de l'année (et le suivant dès décembre). |
| Seuils de stock (RG-07) | toutes les 15 min | Alertes de stock bas. |
| Rejeu MECeF (RG-03) | toutes les 30 min | Recertifie les factures dont l'envoi a échoué. |
| Sauvegarde de la base | chaque jour à 02:00 | Écrit dans `storage/app/sauvegardes/`. |
| Purge de la déduplication | chaque jour à 03:00 | Nettoie la synchronisation (7 jours). |
| Purge du journal d'audit | le 1er du mois à 04:00 | Inerte tant que la durée n'est pas fixée. |
| `contact-editeur:rejouer` | chaque heure | Renvoie les messages « Contactez l'éditeur » en échec. |
| `notifications:relancer-emails` | toutes les 15 min | Relance les e-mails de notification dont l'envoi a échoué. |
| `notifications:detecter` | chaque heure | Compose les notifications et met les e-mails en file d'envoi. |

**Vérifier** que le cron tourne :

- `php artisan tatacora:verifier-production` doit dire « planificateur :
  OK » ;
- `php artisan schedule:list` liste le planning.

⚠ Les **archives de clôture** sont dans
`storage/app/private/archives/`. La sauvegarde SQL **ne les contient
pas** : ajoutez ce dossier à vos sauvegardes cPanel.

---

## E. État des travaux au 20/10/2026

### Fait et poussé sur la branche (PR #2)

| Lot | Contenu |
|---|---|
| Synchronisation F1 à F7 | File d'envoi, appairage, descente du catalogue et des documents de tous les postes, POS hébergés, cycle des réservations, pièces du serveur en lecture seule, contrôle de cohérence, essai à 5 postes. |
| Tous les modules | Tables du restaurant, M8 Véhicules, M13 RH, paramètres et rôles, modèles de notification. |
| Bouton « Synchroniser » | Côté serveur (PWA) et côté poste. |
| Configurations | Mot de passe SMTP (serveur chiffré, poste dans `poste.json`). Révocation de l'appairage. |
| Exploitation | Cron documenté, essais en production puis réinitialisation (web et postes, génération des données), `tatacora:verifier-production`. |
| Passage d'année | Ouverture automatique de N+1 (serveur et poste), descente des exercices. |
| Clôture SYSCOHADA annuelle | Statut « en clôture », journaux CL et AN, résultat en 131 ou 139, à-nouveaux provisoires puis définitifs, réouverture par le comptable. |
| Archive légale | Écritures, balance et états PDF avec empreinte SHA-256, vérifiée avant téléchargement, contrôle en production. |
| Consultation N / N−1 | Comparatif au résultat et au bilan, navigation, bandeau de statut, saisie d'inventaire en clôture. |

Les tests, mesurés le 20/10/2026, sont tous verts : serveur 1 787, poste
3 717, comparateur PWA → poste en PASS.

### À faire de votre côté

1. Changer le mot de passe SMTP communiqué pendant le développement.
2. Faire valider par l'expert-comptable le format du fichier des écritures
   attendu par la DGI Bénin (colonnes, encodage).
3. Fusionner la PR #2 dans `main` quand les essais vous conviennent.
4. Au déploiement : `migrate`, `verifier-production`, ligne cron, sauvegarde
   du dossier `storage/app/private/archives/`.

### Proposé, pas encore commencé (à décider)

1. **Grand livre et notes annexes.** Afficher les soldes d'ouverture
   (à-nouveaux). Ces écrans disent encore « aucun report à nouveau ».
2. **Alerte avant de démarrer une clôture.** Signaler les postes qui ont
   encore des opérations à envoyer : une fois N en clôture, le serveur
   refuse leurs pièces datées de N.
3. **Libellés de la PWA à reprendre sur le poste.** Il en reste 438, sur 101
   blocs d'écran.
4. ~~**Synchronisation encore absente** : congés, plannings, entretiens de
   véhicules, indisponibilités de la carte.~~ Fait le 21/10/2026, bar et
   restaurant compris. L'écran « Congés & Plannings » existe désormais à la
   PWA **et** sur le poste, avec les mêmes règles (RG-13 pas de double
   planification, RG-14 préavis et couverture). Pour valider un congé il faut
   renseigner dans Paramètres le préavis (`delai_preavis_conge_jours`) et la
   couverture minimale (`couverture_minimale_par_service`) : sans eux la
   validation est refusée, volontairement.
5. ~~**Sortie de stock à la vente sur le poste (RG-05).**~~ Fait le
   21/10/2026 : le poste affiche « −X en attente d'envoi » sous le stock.
6. **Compte de résultat, bilan et comparatif sur le poste.** Cela
   exigerait de faire descendre les écritures du serveur, ce qui revient sur
   la décision « Q1 = A ». À trancher par vous.

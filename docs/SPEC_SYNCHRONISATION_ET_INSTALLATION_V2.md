# Spécification produit — Synchronisation et installation, V2 (combler les écarts constatés)

> **Statut** : brouillon à valider par le Product Owner — 29/10/2026. **Documentation seule** : aucun code ni test modifié.
> **Base factuelle** : `docs/BLUEPRINT_SYNCHRONISATION_MULTI_POSTES.md` (§1.5, §3, §4, §5, §7, §8), `docs/PRD_REINSTALLATION_ET_DEMARRAGE_RESILIENT.md` (R4), `tatacora-flutter/installer/tatacora.iss`, `tatacora-flutter/build_windows.bat`, `tatacora-flutter/README_DEPLOY.md`, et le code cité en `fichier:ligne` (relu le 29/10/2026, commit `dfdca88`).
> **Abréviations** : `API/` = `tatacora-api/app/Shared/Sync/` ; `FL/` = `tatacora-flutter/lib/` ; `SYNC/` = `FL/features/synchronisation/`.

---

## Résumé (une demi-page)

**Le problème.** TATACORA / LogiReStock fonctionne : cinq postes Windows autonomes, un serveur Laravel, aucune opération perdue. Mais neuf trous, tous vérifiés dans le code, laissent l'exploitation dépendre de gestes manuels ou de chance : le serveur ne peut **rien pousser** (les postes l'interrogent toutes les 5 min / 30 s) ; on ne peut appairer un poste que **depuis le poste** ; les jetons **n'expirent jamais** et un « poste » n'existe que par le nom d'un jeton ; les **conflits financiers sont écrits mais jamais tranchés** ; **presque rien ne se supprime** de façon synchronisée ; la **base n'est pas sauvegardée avant migration** ni avant désinstallation ; et l'installateur peut produire un `.exe` qui **ne démarre pas** sur un poste neuf (runtime Visual C++ absent) ou qui échoue **sans nommer le fichier** manquant.

**Ce qu'on propose.** Neuf exigences, classées par risque de perte de donnée ou de blocage :
- **P0 (lots 1 à 3)** : garde-fous de construction et runtime VC++ (EX-7, EX-9) ; sauvegardes avant migration et à la désinstallation (EX-6, EX-8) ; écran de décision des conflits financiers (EX-4).
- **P1 (lots 4 à 6)** : table `postes` + expiration/rotation des jetons + supervision (EX-3) ; code d'appairage créé sur le web (EX-2) ; suppression synchronisée par règles de table (EX-5).
- **P2 (lot 7)** : signal quasi instantané (EX-1), l'interrogation restant le filet de sécurité.

**Décisions à ne pas rouvrir** (PO) : le poste fonctionne **sans** la synchronisation ; comptes utilisateurs non synchronisés ; **pas** de limite d'essais de connexion au poste ; mot de passe perdu = réinitialisation par un administrateur + code de secours (pas d'e-mail) ; nom commercial **LogiReStock**, éditeur **Dr MASSENON Rhodes** ; la désinstallation supprime les données après avertissement Oui/Non ; journal d'audit « poste » = nom de machine ; poste privilégié sur la comptabilité.

**Les 4 questions qui bloquent** (§8) : hébergement compatible temps réel ? (EX-1) ; qui tranche les conflits financiers ? (EX-4) ; rétention des suppressions et des sauvegardes ? (EX-5, EX-6) ; emplacement de la sortie de l'installateur ? (EX-9, recommandation : `installer\Output`).

---

## 0. Décisions du PO déjà prises (à respecter — non négociables ici)

| # | Décision | Conséquence sur cette spec |
|---|---|---|
| D1 | **Le poste fonctionne SANS la synchronisation** (principe directeur, `tatacora-flutter/CLAUDE.md`) | Toute nouveauté réseau lit l'interrupteur `synchronisation_activée` (`FL/features/transverse/data/configuration_poste.dart:179`) ; l'interrogation reste le filet de sécurité (EX-1) ; aucun écran du poste ne dépend du serveur (EX-2, EX-3, EX-4 sont **web**). |
| D2 | **Comptes utilisateurs non synchronisés** (PA-103) | Aucune exigence ne synchronise un compte ; la révocation d'un jeton ne touche pas aux comptes du poste. |
| D3 | **Pas de limite d'essais de connexion au poste** (Blueprint §1.5) | Aucune exigence n'en ajoute. Le code d'appairage (EX-2) est un cas **différent** : c'est un secret serveur, il est limité (le web/API limitent déjà à 5 essais / 300 s, `AuthController.php:84`). |
| D4 | **Mot de passe perdu = réinitialisation par un administrateur + code de secours, pas d'e-mail** (Blueprint §7.5) | Pas de circuit e-mail pour les codes d'appairage ni les alertes de supervision. |
| D5 | **Nom commercial LogiReStock, éditeur Dr MASSENON Rhodes** | Noms de sortie, dossiers de sauvegarde (`LogiReStock-Sauvegarde-<date>`) ; les dossiers de **données** restent `TATACORA` (`tatacora.iss:47-48`). |
| D6 | **La désinstallation supprime les données, après avertissement Oui/Non** (défaut = Non, silencieux = garde) (`tatacora.iss:105-148`) | EX-8 s'ajoute **avant** cette suppression ; il ne la remplace pas et ne change pas le défaut. |
| D7 | **Journal d'audit « poste » = nom de machine** (`FL/core/database/auteur_ecriture.dart:35`, colonne `poste_nom`) | La table `postes` (EX-3) garde **deux** notions distinctes : `poste_id` (identité d'appairage) et `nom_machine` ; l'audit continue de citer la machine. |
| D8 | **Poste privilégié sur la comptabilité** | Le poste d'origine d'une écriture reste prioritaire ; le serveur reste le seul comptable (`SynchronisationService.php:59`). L'arbitrage (EX-4) ne crée **jamais** de pièce comptable à la main : il choisit une version, le service de domaine passe les écritures. |

---

## 1. Énoncé du problème

**Qui est touché.**
- **L'administrateur web** (Dr MASSENON ou délégué) : il ne voit pas ce que les postes font en temps utile, ne peut ni émettre un accès pour un poste ni expirer un accès perdu, et ne peut pas décider d'un conflit financier que le système lui signale.
- **Le gérant au poste** (Natitingou, connexion instable) : il attend jusqu'à ~5 min pour voir la saisie d'un autre poste ; une réinstallation ou une migration défaillante peut lui coûter sa seule copie des saisies non synchronisées ; un poste neuf peut ne pas démarrer, sans message.
- **Le technicien qui installe un poste** : il doit saisir identifiant et mot de passe d'un compte serveur **au poste**, et reçoit des erreurs d'installateur illisibles.
- **Le comptable** : des documents financiers restent « en conflit » indéfiniment, hors des écritures du serveur.

**Pourquoi maintenant.** Le moteur de synchronisation est mûr (Blueprint, 29/10/2026) ; ce qui manque est l'**exploitation** autour de lui. Un incident réel l'illustre : un fichier `installer/poste.example.json` supprimé en local a fait échouer Inno Setup avec « The system cannot find the path specified » **sans nommer le fichier** (cas d'école, EX-9).

**Coût de l'inaction.** Un conflit financier sans arbitre bloque un document pour toujours (l'opération du poste reste `conflit`, la version du serveur reste en place, la version du poste n'est que dans `conflits_synchronisation`). Un jeton perdu reste valide indéfiniment. Une migration défaillante sans sauvegarde peut détruire la seule copie de ce qui n'est pas parti.

### État actuel, écart par écart (vérifié)

| Réf. | Écart | État actuel (fichier:ligne) |
|---|---|---|
| EX-1 | Pas de notification serveur → poste | Polling seul : `periodeSynchronisation = 5 min` (`SYNC/presentation/providers_synchronisation.dart:314`), `periodeDemandeServeur = 30 s` (`:319`) ; le poste lit `GET /sync/demande` (`tatacora-api/routes/api.php:80`) ; délai HTTP 20 s (`SYNC/data/transport_synchronisation.dart:34`) ; aucune dépendance Reverb/Pusher/FCM (Blueprint §1.5). |
| EX-2 | Pas d'écran web de création de jeton / code | L'appairage = login d'un compte serveur depuis le poste : `AuthController.php:141-143` (`delete` puis `createToken($poste)`) ; le web ne fait que lister, révoquer, demander (`routes/api.php:82-85`, `PWA/SynchronisationPostes.php`). |
| EX-3 | Pas d'expiration, pas de table `postes` | Pas de `tatacora-api/config/sanctum.php` (vérifié : fichier absent) → expiration par défaut `null` ; la colonne « Expiration » lit `MAX(expires_at)` (`API/Services/SuiviPostesService.php:145`) ; un poste = nom de jeton + `etats_postes_synchronisation` + `sessions_synchronisation` (`SuiviPostesService.php:130-184`). Aucune version d'application ni de schéma n'est remontée. |
| EX-4 | Conflits financiers jamais tranchés | Écrits en `en_attente_arbitrage` (`API/Services/SynchronisationService.php:725-734`) ; réponse `financier_arbitrage_requis` (`:737-744`) ; le modèle expose `arbitre_par_id`, `date_arbitrage` (`API/Models/ConflitSynchronisation.php:28-37`) mais **aucun** écran ni service ne les renseigne (seul `SynchronisationService.php` référence le modèle). Le poste affiche « En attente d'arbitrage sur le serveur : aucune action sur ce poste. » (`SYNC/domain/suivi_synchronisation.dart:43-44`). 16 tables financières concernées (`API/Services/ClassificationConflitService.php:34-65`). |
| EX-5 | Suppression synchronisée limitée | « Supprimer = archiver » ; seule exception la purge d'unités d'hébergement et de véhicules (`API/Services/CatalogueDescendantService.php:52-66`) ; côté poste, registre fermé `accepteSuppression: true` pour 2 tables (`SYNC/domain/operation_sync.dart:44-50,88`). |
| EX-6 | Pas de sauvegarde avant migration (R4) | Aucune occurrence de « avant-v » dans `FL/` (recherche vide) ; PRD R4 classé P1 non livré (`docs/PRD_REINSTALLATION_ET_DEMARRAGE_RESILIENT.md:92-94`) ; seule la réconciliation non destructive existe (`FL/core/database/reconcilier_schema.dart`). |
| EX-7 | DLL runtime VC++ non embarquées | `build_windows.bat` (112 lignes) ne copie aucune DLL ; `tatacora.iss:95` installe uniquement le contenu de `Release\` ; `README_DEPLOY.md:89-90` affirme « Rien d'autre à installer » (**affirmation non vérifiée**, piège n°1 du `CLAUDE.md`). |
| EX-8 | Pas de sauvegarde proposée à la désinstallation | `InitializeUninstall` n'avertit que (`tatacora.iss:120-143`) ; l'application n'est pas fermée avant la suppression, aucune copie n'est proposée. |
| EX-9 | `build_windows.bat` sans garde-fous | Pas de `flutter analyze` ni de tests ; seul le flavor `demo` est refusé (`build_windows.bat:35-38`) ; sortie fixe `build\installer` (`tatacora.iss:70`, `build_windows.bat:104`, `README_DEPLOY.md:64`) sans suffixe d'environnement ; aucune vérification des fichiers sources de l'installateur (`tatacora.iss:98` : `poste.example.json`) ; seul `tatacora_flutter.exe` est testé (`build_windows.bat:92`, `tatacora.iss:52`). |

---

## 2. Objectifs (mesurables)

| # | Objectif | Cible | Exigence |
|---|---|---|---|
| O1 | **Un poste neuf démarre** après installation, sans installer le runtime à la main | 100 % des installations sur Windows 10/11 vierge (VM sans VC++) ; 0 démarrage muet | EX-7 |
| O2 | **Aucune construction ne produit un installateur incomplet ou mal étiqueté**, et toute erreur nomme sa cause | 0 erreur « sans nom de fichier » ; 100 % des fichiers sources vérifiés et nommés ; flavor demo en production = refus | EX-9 |
| O3 | **Aucune perte irréversible sans copie proposée** : migration et désinstallation | 100 % des migrations précédées d'une copie datée vérifiée ; 100 % des désinstallations interactives proposent la copie avant la suppression | EX-6, EX-8 |
| O4 | **Plus aucun conflit financier orphelin** | Délai médian de décision ≤ 2 jours ouvrés ; 0 conflit `en_attente_arbitrage` de plus de 7 jours (alerte) ; 100 % des décisions avec motif et auteur | EX-4 |
| O5 | **Un poste se supervise et se révoque sans accès au poste** | Appairage par code en ≤ 3 min sans saisir de mot de passe serveur au poste ; 100 % des jetons avec expiration ; postes visibles avec version d'application et de schéma | EX-2, EX-3 |
| O6 | **Latence de propagation** d'une saisie d'un poste vers les autres, postes en ligne | p95 ≤ 15 s (aujourd'hui cible ≤ 10 min, Blueprint §5.6), avec le filet 5 min intact | EX-1 |

---

## 3. Hors périmètre (avec la raison)

1. **Synchroniser les comptes utilisateurs** — décision D2 ; chaque côté garde ses comptes.
2. **Limiter les essais de connexion au poste** — décision D3 ; hors sujet ici.
3. **Fusion automatique de deux saisies d'argent** — risque comptable (RG-17) ; EX-4 donne un **arbitre humain**, pas une fusion. Le choix est « garder A » ou « garder B », jamais une moyenne.
4. **Mise à jour automatique de l'application (auto-update) et signature de code** — sujet distinct (distribution) ; EX-3 n'affiche que la version déployée. À instruire à part si le PO le veut.
5. **Notification par e-mail / SMS des alertes de supervision** — décision D4 (pas d'e-mail pour ce circuit) ; les alertes restent à l'écran web.
6. **Réparer une base SQLite corrompue** — déjà hors périmètre du PRD de réinstallation ; EX-6 sauvegarde et restaure, il ne répare pas.

---

## 4. Récits utilisateur

**Administrateur web**
- En tant qu'**administrateur web**, je veux **créer un code d'appairage à usage unique** afin d'**autoriser un nouveau poste sans communiquer le mot de passe d'un compte** (EX-2).
- En tant qu'**administrateur web**, je veux **voir chaque poste avec sa version d'application, sa version de schéma, sa dernière synchro et son statut** afin de **repérer un poste en retard ou périmé** (EX-3).
- En tant qu'**administrateur web**, je veux **faire expirer ou renouveler le jeton d'un poste** afin de **limiter les dégâts d'un poste perdu ou volé** (EX-3).
- En tant qu'**administrateur web**, je veux **trancher un conflit financier en choisissant une version et en donnant un motif** afin que **le document sorte de l'attente et que la décision soit tracée** (EX-4).
- En tant qu'**administrateur web**, je veux **définir ce qui se supprime, comment et pour combien de temps** afin que **les postes hors ligne ne ressuscitent pas une donnée supprimée** (EX-5).

**Gérant au poste**
- En tant que **gérant**, je veux **voir ce qu'un autre poste vient de saisir en quelques secondes** afin de **ne pas vendre une chambre ou un plat déjà pris** (EX-1).
- En tant que **gérant**, je veux que **mon poste continue à tout faire sans le serveur** afin de **ne jamais être bloqué par une panne réseau** (D1, garde de toutes les exigences).
- En tant que **gérant**, je veux que **mes données soient copiées avant une mise à jour de la base, et pouvoir revenir en arrière depuis l'écran de panne** afin de **ne pas perdre mes saisies non synchronisées** (EX-6).
- En tant que **gérant**, je veux qu'**on me propose une copie de mes données avant une désinstallation** afin de **ne pas les perdre par un clic distrait** (EX-8).
- En tant que **gérant**, je veux **savoir si ma saisie est en conflit et qui doit la trancher** afin de **ne pas la ressaisir** (EX-4).

**Technicien qui installe un poste**
- En tant que **technicien**, je veux que **l'installateur apporte tout ce qu'il faut pour démarrer** afin de **ne pas courir après un runtime manquant** (EX-7).
- En tant que **technicien**, je veux que **le script de construction s'arrête en nommant le fichier ou l'étape en cause** afin de **corriger en une minute** (EX-9).
- En tant que **technicien**, je veux **saisir un code court au poste** afin de **appairer sans connaître de mot de passe** (EX-2).

**Comptable**
- En tant que **comptable**, je veux **voir les conflits financiers en attente avec les deux versions côte à côte** afin de **décider en connaissance de cause** (EX-4).
- En tant que **comptable**, je veux que **toute suppression respecte l'immuabilité des pièces (RG-11)** afin que **la comptabilité reste auditable** (EX-5).
- En tant que **comptable**, je veux **un journal d'audit des décisions** afin de **justifier un écart devant l'auditeur** (EX-4).

---

## 5. Exigences

> **Convention des critères** : Étant donné / Quand / Alors. Chaque exigence couvre le cas nominal, les erreurs, et au moins un cas négatif. Priorités : **P0** = perte de donnée ou blocage ; **P1** = exploitation sûre ; **P2** = confort et rapidité.
> **Ordre de lecture** : par priorité, puis par numéro d'écart (EX-n correspond à la liste du PO).

---

### P0

#### EX-7 — Runtime Visual C++ embarqué (P0)

**Description.** Un poste Windows neuf peut ne pas avoir le runtime Visual C++ : `tatacora_flutter.exe` ne démarre alors pas, sans message. `build_windows.bat` copie `msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll` depuis `%SystemRoot%\System32` dans `build\windows\x64\runner\Release\` (donc dans l'installateur, qui embarque tout le dossier : `tatacora.iss:95`), et **arrête la construction** si l'une d'elles est absente.

**Critères d'acceptation**
- *Nominal.* **Étant donné** une machine de construction où les trois DLL existent dans System32, **quand** `build_windows.bat` termine l'étape 3, **alors** les trois fichiers sont à côté de `tatacora_flutter.exe` et le script affiche leur liste ; l'installateur les contient (vérifié par `ISCC` sans erreur et par l'étape de contrôle de EX-9).
- *Nominal poste.* **Étant donné** une VM Windows 10/11 sans runtime VC++ installé, **quand** on installe `LogiReStock_Setup_<v>.exe` puis lance l'application, **alors** la fenêtre s'ouvre (écran d'attente puis connexion).
- *Erreur.* **Étant donné** que `vcruntime140_1.dll` est absente de System32, **quand** le script atteint cette étape, **alors** il s'arrête avec le message `[ERREUR] vcruntime140_1.dll introuvable dans <chemin> : installez « Microsoft Visual C++ Redistributable 2015-2022 x64 » sur cette machine de construction`, code de sortie 1, **aucun** `.exe` d'installateur n'est produit.
- *Négatif.* **Étant donné** que le flavor est `demo`, **quand** on lance le script, **alors** il refuse avant toute copie (EX-9) ; **et** une DLL déjà présente dans `Release\` n'est jamais écrasée par une version **plus ancienne** (comparaison de version, ou copie conditionnelle documentée).
- *Négatif.* **Étant donné** une machine de construction 32 bits, **alors** le script refuse (Flutter Windows ne produit que du x64, `tatacora.iss:81`).

**Considérations techniques.** Source : `%SystemRoot%\System32` (jamais `SysWOW64`, qui contient les DLL 32 bits). Copier à l'étape 3 bis, **après** `flutter build windows` (qui vide `Release\`). Redistribuabilité : ces trois DLL font partie du « Visual C++ Redistributable » dont la redistribution « app-local » est permise par Microsoft ; **le PO/juridique doit confirmer** (Q-9). Alternative écartée : lancer `vc_redist.x64.exe` depuis l'installateur (plus lourd, nécessite droits et redémarrage possible) ; à garder comme plan B si la copie app-local pose problème. Corriger aussi `README_DEPLOY.md:89-90` (« Rien d'autre à installer ») et son chemin de dossier d'installation `C:\Program Files\TATACORA` alors que l'installateur écrit `{autopf}\LogiReStock` (`tatacora.iss:67`).

**Dépendances.** Aucune ; livrable avec EX-9 (même fichier). Recette sur une VM vierge (PO ou technicien).

---

#### EX-9 — `build_windows.bat` avec garde-fous (P0)

**Description.** Le script de construction vérifie avant de produire un installateur : analyse statique, tests, flavor, présence de **chaque** fichier source de l'installateur (en le **nommant**), DLL runtime (EX-7), et nomme la sortie selon l'environnement. Les erreurs sont lisibles : *quoi*, *où*, *que faire*.

| Garde-fou | Règle |
|---|---|
| Analyse | `flutter analyze` lancé avant la construction ; **toute** erreur ou `warning` arrête (le `CLAUDE.md` du poste dit : « `warning` est BLOQUANT ») ; `info` seul ne bloque pas |
| Tests | `flutter test` lancé par défaut (~6 min annoncées dans `tatacora-flutter/CLAUDE.md`, ~20 min pour la suite complète) ; option `--sans-tests` pour l'ignorer, **avec avertissement affiché** et mention dans le nom de sortie des journaux ; interdite pour `production` si le PO le décide (Q-10) |
| Flavor demo | Refusé (déjà le cas, `build_windows.bat:35-38`) ; ajouter : toute valeur hors `production`, `recette`, `dev` est refusée avec la liste des valeurs admises |
| Nom de sortie | `production` : `LogiReStock_Setup_<v>.exe` ; `recette` : `LogiReStock_Setup_<v>-recette.exe` ; `dev` : `…-dev.exe`. Impossible de confondre un installateur de recette avec la production |
| Fichiers sources | Avant `ISCC`, vérifier l'existence de : `tatacora_flutter.exe`, les trois DLL (EX-7), `installer\poste.example.json`, `installer\tatacora.iss`, `windows\runner\resources\app_icon.ico` (optionnel : avertissement si absent, `tatacora.iss:72-74`) ; **chaque absent est nommé** avec son chemin complet |
| Sortie | Voir ci-dessous (recommandation tranchée) |
| Journal | Le script écrit un journal horodaté (`build\journal_construction.txt`) de chaque étape ; en cas d'échec, la dernière ligne dit l'étape et le fichier fautif |

**Cas d'école à documenter (incident réel).** Un fichier `installer/poste.example.json` supprimé en local a fait échouer Inno Setup avec « The system cannot find the path specified » **sans nommer le fichier** : `tatacora.iss:98` déclare `Source: "poste.example.json"` et la directive `#error` du `.iss` ne protège que l'exécutable (`tatacora.iss:52-54`). Le fichier **est versionné** (`git ls-files` : `tatacora-flutter/installer/poste.example.json`) ; sa suppression n'était donc qu'un état local. Le garde-fou est : `if not exist "installer\poste.example.json" (echo [ERREUR] Fichier source de l'installateur absent : installer\poste.example.json ... restaurez-le avec « git checkout -- installer/poste.example.json » ...)`. Même motif ajouté dans le `.iss` (`#if !FileExists(...) #error "…nom du fichier…"`) pour le cas où on compile le `.iss` seul.

**Décision sur l'emplacement de la sortie (tranchée).** **Recommandation : `installer\Output\`** (dossier `tatacora-flutter/installer/Output`), pas `build\installer`. Raisons : (a) `build\` est le dossier que `flutter clean` **détruit** — un installateur livrable ne doit pas disparaître avec lui ; (b) cohérence avec l'usage Inno Setup par défaut (`Output\`) et avec la doc AgriERP fournie par le PO ; (c) le dossier est à ajouter au `.gitignore`. Conséquence : changer `OutputDir=..\build\installer` (`tatacora.iss:70`) en `OutputDir=Output`, le message final (`build_windows.bat:104`) et `README_DEPLOY.md:64`. Les anciens installateurs de `build\installer` ne sont pas migrés. À valider par le PO (Q-8).

**Critères d'acceptation**
- *Nominal.* **Étant donné** un arbre propre, **quand** `build_windows.bat` (production) s'exécute, **alors** `flutter analyze` passe, les tests passent, les DLL sont copiées, tous les fichiers sources sont vérifiés, et `installer\Output\LogiReStock_Setup_<v>.exe` existe ; le script affiche son chemin absolu et sa taille.
- *Nominal `--sans-tests`.* **Quand** on passe `--sans-tests`, **alors** l'étape tests est sautée, un bandeau `[ATTENTION] Tests ignorés` est affiché et inscrit au journal.
- *Nominal recette.* **Quand** on passe `recette`, **alors** le fichier s'appelle `LogiReStock_Setup_<v>-recette.exe` et l'`ENV` compilé est `recette` (`--dart-define=ENV=recette`, `build_windows.bat:89`).
- *Erreur — fichier absent (cas d'école).* **Étant donné** `installer\poste.example.json` supprimé, **quand** on lance le script, **alors** il s'arrête **avant** l'étape de construction Flutter (gain de temps) avec `[ERREUR] Fichier source de l'installateur absent : installer\poste.example.json`, code 1.
- *Erreur — analyse.* **Étant donné** un `warning` dans `lib/`, **alors** arrêt avec le nombre de problèmes et la première ligne ; aucune construction.
- *Erreur — tests.* **Étant donné** un test rouge, **alors** arrêt, nom du premier test en échec ; pas d'installateur.
- *Négatif — flavor.* **Quand** on passe `demo`, `prod`, ou une valeur inconnue, **alors** refus avec la liste des valeurs admises ; rien n'est construit.
- *Négatif — pas d'écrasement silencieux.* **Étant donné** un installateur de même nom déjà présent, **quand** la construction réussit, **alors** il est remplacé et le message le dit ; en cas d'échec, l'ancien **n'est pas** supprimé.
- *Négatif — code retour.* Aucune étape échouée ne laisse un code retour 0 (revue de `if errorlevel 1` après **chaque** appel, déjà fait aux étapes 1 à 4).

**Considérations techniques.** `flutter analyze` retourne un code non nul sur `info` par défaut dans certaines versions : utiliser `--no-fatal-infos` et conserver `warning` bloquant. L'analyse et les tests sont lents : ordre analyse → fichiers → build_runner → build → DLL → ISCC, pour échouer le plus tôt possible. Piège n°4 du `CLAUDE.md` : ne pas écrire le `.bat` par heredoc sans balayer les caractères de contrôle. Batch : encodage sans accents (déjà le cas) ; guillemets autour des chemins avec espaces (`Program Files (x86)`).

**Dépendances.** EX-7 (DLL). Aucune dépendance serveur.

---

#### EX-6 — Sauvegarde automatique avant migration (R4) (P0)

**Description.** Avant toute montée de version de la base du poste, l'application copie `tatacora.sqlite` (avec `-wal` et `-shm` s'ils existent) en une copie **datée et versionnée** : `tatacora.sqlite.avant-v<NN>-<AAAAMMJJ-HHMMSS>`, dans `%LOCALAPPDATA%\TATACORA\donnees\sauvegardes-migration\`. On garde les **3** plus récentes (rétention 1 à 3, proposée : 3 — Q-5). Si la migration échoue, l'**écran de panne** propose « Restaurer la sauvegarde » (avec confirmation).

**Critères d'acceptation**
- *Nominal.* **Étant donné** une base à `user_version` 44 et une application qui migre vers 46, **quand** l'application démarre, **alors** une copie `…avant-v44-…` existe **avant** le premier `ALTER`, sa taille est celle de l'original, son intégrité est vérifiée (`PRAGMA integrity_check` = `ok` sur la copie), et la migration continue.
- *Nominal — restauration.* **Étant donné** une migration qui lève, **quand** l'écran de panne s'affiche (`FL/core/demarrage/demarrage_resilient.dart`), **alors** il propose « Restaurer la sauvegarde d'avant la mise à jour » ; **après confirmation**, la base d'origine est remise (la base défaillante est conservée sous `.echec-<date>`), et l'application redémarre sur l'ancienne version de schéma avec un message clair.
- *Erreur — disque plein.* **Étant donné** un espace insuffisant, **alors** la migration **ne démarre pas** : écran « Espace disque insuffisant pour sauvegarder avant la mise à jour : libérez X Mo » (le poste reste sur l'ancienne base intacte) — la sauvegarde est une **condition** de la migration, pas un best effort. *(Arbitrage à confirmer : Q-5.)*
- *Erreur — copie corrompue.* **Étant donné** que la vérification d'intégrité de la copie échoue, **alors** la migration ne démarre pas et l'écran de panne le dit.
- *Négatif.* **Étant donné** une base déjà à la version courante (aucune migration), **alors** **aucune** copie n'est faite ; **et** la sauvegarde n'est jamais supprimée avant que la suivante soit vérifiée ; **et** aucune donnée n'est lue de la copie hors du geste « Restaurer ».
- *Négatif.* **Étant donné** une base neuve (première installation), **alors** aucune copie (rien à protéger).
- *Négatif — secrets.* La copie contient le contenu de la base, pas `poste.json` : le jeton n'est pas dupliqué dans ce dossier.

**Considérations techniques.** Utiliser la copie de fichier fermé ou `VACUUM INTO` (cohérent même base ouverte) plutôt que la copie brute d'une base en mode WAL ; le déménagement de base existant fournit déjà un modèle (copie avec `-wal`/`-shm`, tailles vérifiées, `FL/core/database/emplacement_base.dart`). Point d'insertion : avant l'ouverture migrante, dans le démarrage résilient (`demarrage_resilient.dart`, délai de 45 s à relever ou à suspendre pendant la copie). La désinstallation supprime ce dossier (même arbre `{localappdata}\TATACORA`) — c'est cohérent avec D6, mais EX-8 doit alors couvrir aussi ces copies. Test : base issue d'un des 20 dumps réels (`test/fixtures/schemas_anciens/`), migration forcée en échec, restauration, comparaison des lignes. Mutation obligatoire (retirer l'appel de sauvegarde doit faire rougir).

**Dépendances.** Démarrage résilient (livré, PRD E1-E3). Q-5 (rétention, échec bloquant). Complète EX-8 (autre usage de la copie).

---

#### EX-8 — Sauvegarde proposée à la désinstallation (P0)

**Description.** Dans `InitializeUninstall` (`tatacora.iss:120`), **avant** l'avertissement Oui/Non de suppression, l'installateur **propose** de sauvegarder : « Voulez-vous d'abord enregistrer une copie de vos données dans `Documents\LogiReStock-Sauvegarde-<AAAA-MM-JJ>` ? ». Si Oui : l'application est **fermée** (pour que la base soit cohérente), les données sont copiées, la taille est vérifiée, puis l'avertissement de suppression existant s'affiche. Cette fonction **n'efface jamais** : elle précède la décision D6 et en laisse intacts le défaut (Non), l'annulation et le mode silencieux.

**Critères d'acceptation**
- *Nominal.* **Étant donné** une désinstallation interactive, **quand** l'utilisateur répond Oui à la sauvegarde, **alors** l'application est fermée (si ouverte), `%LOCALAPPDATA%\TATACORA\donnees\` (base, `-wal`, `-shm`) et `%APPDATA%\TATACORA\` (`poste.json`, archives, reçus) sont copiés sous `Documents\LogiReStock-Sauvegarde-<date>\`, un message affiche le chemin et la taille copiée, **puis** l'avertissement D6 s'affiche.
- *Nominal — Non à la sauvegarde.* **Alors** on passe directement à l'avertissement D6, inchangé.
- *Erreur — application impossible à fermer.* **Alors** la copie n'a pas lieu et le message dit : « Fermez LogiReStock puis recommencez » ; la désinstallation est **annulée** (rien supprimé).
- *Erreur — copie incomplète* (disque plein, fichier verrouillé) : **alors** message « La sauvegarde a échoué : <fichier> » ; l'avertissement D6 est précédé d'un texte explicite « aucune sauvegarde n'a pu être faite » et le défaut reste **Non**.
- *Négatif — silencieux.* **Étant donné** `/SILENT` ou `/VERYSILENT`, **alors** aucune question, aucune copie, **données gardées** (inchangé, `tatacora.iss:125-126`).
- *Négatif — mise à jour.* Une mise à jour (même `AppId`) ne passe jamais par ce code ; ni sauvegarde ni suppression.
- *Négatif — date existante.* **Étant donné** que le dossier du jour existe, **alors** on suffixe `-2`, `-3`… ; jamais d'écrasement.
- *Négatif — secrets.* L'avertissement dit que la sauvegarde contient **le jeton d'appairage et le mot de passe SMTP** (`poste.json`) : à protéger ; option de ne pas inclure `poste.json` (Q-6).

**Considérations techniques.** Pascal Script d'Inno Setup : fermeture par `taskkill`/`Restart Manager` ou envoi de `WM_CLOSE`, puis attente avec délai maximal ; copie récursive par `Exec` de `robocopy`/`xcopy` ou routine Pascal avec contrôle des tailles. `Documents` : dossier connu `{userdocs}` ; **attention OneDrive** (pour une copie archive, pas une base vivante, c'est acceptable ; le dire dans le message). La liste de ce qui est perdu (`tatacora.iss:128-134`) mentionne déjà « les sauvegardes (Paramètres > Sauvegardes) » : la nouvelle sauvegarde est **hors** de ces dossiers et ne sera pas supprimée. Test : script Inno Setup non testable en unitaire → recette manuelle sur VM (cases D5 de `docs/RESTE_A_FAIRE.md` à étendre : « Oui à la sauvegarde », « Non », « silencieux », « appli ouverte »).

**Dépendances.** D6 (déjà livrée). Q-6 (contenu de la sauvegarde). Ne dépend d'aucun code Flutter.

---

#### EX-4 — Écran web pour trancher les conflits (surtout financiers) (P0)

**Description.** Un écran web « Conflits à trancher » liste les lignes `conflits_synchronisation` au statut `en_attente_arbitrage`, montre **côte à côte** la version du poste (`version_locale`) et celle du serveur (`version_serveur`), et permet à un **arbitre habilité** de choisir **« garder la version du serveur »** ou **« appliquer la version du poste »**, avec un **motif obligatoire**. La décision est exécutée **par le service de domaine** (jamais une écriture brute, `SynchronisationService.php:46-58`), tracée au journal d'audit, et le poste est informé au passage suivant (l'opération passe de `conflit` à un état final).

**Options comparées (qui peut trancher).**

| Option | Pour | Contre |
|---|---|---|
| A. Administrateurs seulement | Simple | Un administrateur n'est pas toujours compétent en comptabilité |
| B. **Administrateurs et Comptable** (recommandée) | Aligne sur `CorrectionReceptionService::estAutorise` (`API/Services/CorrectionReceptionService.php:66`) et sur « annuler un document d'un autre poste » (`DocumentsDesAutresPostes.php:29`) | Deux rôles à tracer |
| C. Comptable seulement | Séparation des tâches nette | Indisponibilité du comptable = blocage |

**Recommandation : B**, avec la règle que **l'arbitre ne tranche pas un conflit sur un document dont il est l'auteur** (séparation des tâches) ; décision finale au PO (Q-2).

**Critères d'acceptation**
- *Nominal — garder le serveur.* **Étant donné** un conflit `en_attente_arbitrage` sur `ventes`, **quand** le comptable choisit « garder la version du serveur » avec le motif « Saisie du poste BAR périmée », **alors** le statut devient `resolu_serveur`, `arbitre_par_id` et `date_arbitrage` sont renseignés, une ligne `journal_audit` est écrite (conflit, table, entité, choix, motif, auteur, IP), l'opération du poste est marquée résolue (« version du serveur conservée »), et aucune écriture comptable nouvelle n'est créée.
- *Nominal — appliquer la version du poste.* **Quand** l'arbitre choisit « appliquer la version du poste », **alors** la modification du poste est rejouée par `GestionnaireXxx::modifier()` dans **une transaction** (service de domaine, mêmes règles que l'écran web) ; si le service la refuse (période clôturée, pièce validée immuable RG-11, stock insuffisant), la décision n'est **pas** enregistrée et la phrase du service est montrée ; sinon statut `resolu_local` et audit.
- *Nominal — consultation.* L'écran affiche : table, document (numéro), poste d'origine, auteur, horodatage de saisie des deux côtés, **différences surlignées** champ par champ (montants en décimal, jamais en flottant).
- *Erreur — conflit déjà tranché.* **Étant donné** deux arbitres simultanés, **alors** le second reçoit « Ce conflit a déjà été tranché par <nom> à <heure> » ; verrou de ligne (`lockForUpdate`) comme pour `CorrectionReceptionService`.
- *Erreur — motif vide.* **Alors** refus côté serveur (pas seulement côté interface), message « Le motif est obligatoire ».
- *Erreur — entité disparue.* **Étant donné** que l'entité a été supprimée/annulée depuis, **alors** l'écran le dit et ne propose que « Classer sans suite » avec motif.
- *Négatif — droits.* **Étant donné** un utilisateur sans rôle d'arbitrage, **alors** l'écran est inaccessible (403), et l'action Livewire est inscrite dans `PwaActionsReluesTest` / `PwaEcritureAutoriseeTest` (garde existante).
- *Négatif — pièce immuable.* Aucune décision ne modifie ni ne supprime une écriture validée (RG-11) ; une correction passe par une contre-passation par le service existant.
- *Négatif — anti-masse.* Pas de « tout garder le serveur » en un clic sur plusieurs conflits financiers sans revue (au plus une sélection de 20 avec confirmation nominative) ; chaque décision a son motif.
- *Poste.* **Étant donné** un conflit tranché, **quand** le poste passe, **alors** le libellé `En attente d'arbitrage sur le serveur…` (`SYNC/domain/suivi_synchronisation.dart:43`) est remplacé par le résultat (« Tranché le …, version du serveur conservée, motif … ») ; si c'est la version du poste qui est appliquée, l'opération passe `synchronise`.

**Considérations techniques.** Pas de table nouvelle obligatoire : les colonnes `statut`, `arbitre_par_id`, `date_arbitrage` existent (`ConflitSynchronisation.php:28-37`) ; ajouter `choix`, `motif`, une valeur de statut `classe_sans_suite`, et le **retour au poste** : soit le résultat de l'opération est mis à jour dans `deduplication_synchronisation`, soit l'état est lu par un point d'API `GET /sync/conflits/{id}` interrogé pour les opérations `conflit` — à trancher en conception (Q-11). Composant Livewire dans `PWA/` + route + entrée de menu (`routes/web.php:116` pour le modèle). Respecter la règle : un conflit d'argent n'est **jamais** absorbé en silence (Blueprint §5.6). Rappel de la distinction : les chevauchements (`TABLES_STRUCTURELLES`) sont **rejetés**, pas arbitrés (`ClassificationConflitService.php:69`) ; hors de cet écran. Test PHP : chaque branche (serveur, poste, refus du service, concurrence, droits) + mutation (retirer le motif obligatoire, retirer le verrou).

**Dépendances.** Aucune technique ; Q-2 (qui tranche), Q-11 (retour au poste). Bénéficie de EX-3 (colonne « Poste » fiable).

---

### P1

#### EX-3 — Table `postes`, expiration et rotation des jetons, supervision web (P1)

**Description.** Créer une table serveur `postes` portant l'**identité stable** du poste et son état, remplacer la déduction « un poste = le nom d'un jeton ».

| Colonne | Rôle |
|---|---|
| `poste_id` (clé stable, unique) | Aujourd'hui : le nom saisi à l'appairage (`PosteDuJeton.php:39-45`) ; **conservé tel quel** pour la compatibilité |
| `nom_machine` | `COMPUTERNAME` / `Platform.localHostname`, remonté (D7 : l'audit continue de citer la machine) |
| `version_application` | issue de `pubspec.yaml`, envoyée à chaque requête (en-tête) |
| `version_schema` | `user_version` du poste (46 aujourd'hui, `FL/core/database/app_database.dart:525`) |
| `derniere_synchro_montee` / `_descente` | déjà dans `etats_postes_synchronisation` ; à rattacher |
| `statut` | `actif`, `silencieux`, `expire`, `revoque`, `non_appaire` (aujourd'hui calculés : `SuiviPostesService.php:130-184`) |
| `appaire_le`, `revoque_le`, `revoque_par` | traçabilité |

**Expiration et rotation des jetons.** Les jetons reçoivent une `expires_at`. **Options comparées** :

| Option | Pour | Contre |
|---|---|---|
| a. Jeton sans expiration (statu quo) | Aucun risque de coupure | Poste perdu = accès éternel (`config/sanctum.php` absent ; défaut `null`) |
| b. Expiration longue fixe (ex. 90 jours), renouvellement manuel | Simple | Un poste hors ligne > 90 jours est coupé ; geste manuel pénible |
| c. **Expiration glissante + rotation automatique** (recommandée) : jeton valable 90 jours depuis le dernier usage ; au-delà de 60 jours d'âge, le serveur émet un jeton neuf dans la réponse, le poste le range dans `poste.json` (écriture atomique) et l'ancien reste valable 24 h | Poste actif jamais coupé ; poste perdu s'éteint seul | Écriture de `poste.json` à fiabiliser ; cas « réponse perdue » (ancien jeton gardé 24 h) |

**Recommandation : c**, durée de 90 jours à confirmer (Q-4). Raison : le contexte (connexion instable, postes qui peuvent rester éteints des semaines) interdit une expiration courte non glissante, et la règle D1 interdit qu'un poste soit bloqué sans pouvoir être réparé : un jeton expiré **n'arrête pas le poste**, il arrête seulement la synchronisation (état `jetonRefuse`, file intacte, `sync_manager.dart:407-412`).

**Écran de supervision web.** L'écran « Postes & Appairage » existant (`PWA/SynchronisationPostes.php`, route `pwa.synchronisation-postes`) gagne : version d'application, version de schéma, nom de machine, date d'expiration, avertissement « version obsolète » (inférieure à la version minimale paramétrée), actions *Révoquer*, *Renouveler le jeton*, *Prolonger*. Les états sont lus de la table, plus de déduction à la volée.

**Critères d'acceptation**
- *Nominal — migration des postes existants.* **Étant donné** des jetons existants sans `expires_at`, **quand** la migration s'exécute, **alors** une ligne `postes` est créée par nom de jeton distinct, les jetons reçoivent une expiration (date de migration + durée), **aucun** poste n'est coupé à la migration, et les tests existants (`RevocationAppairageTest.php`) restent verts.
- *Nominal — rotation.* **Étant donné** un jeton de plus de 60 jours, **quand** le poste fait une requête valide, **alors** la réponse porte le jeton neuf (en-tête dédié, jamais journalisé) ; le poste l'écrit dans `poste.json` de façon atomique ; la requête suivante utilise le neuf ; l'ancien expire sous 24 h.
- *Nominal — supervision.* **Étant donné** un poste qui a envoyé ses versions, **alors** l'écran affiche version d'application, schéma, machine, dernier contact, expiration.
- *Erreur — jeton expiré.* **Quand** un poste présente un jeton expiré, **alors** 401 ; le poste consigne `appairage_refuse`, la file reste intacte et le poste continue de fonctionner hors synchronisation (D1) ; l'écran web montre « Expiré le … » et propose *Prolonger* ou le réappairage.
- *Erreur — rotation interrompue.* **Étant donné** que le poste n'a pas pu écrire le jeton neuf (coupure), **alors** il réutilise l'ancien tant qu'il est valable (24 h), puis la rotation se refait.
- *Négatif.* **Étant donné** un administrateur, **alors** il ne peut pas révoquer *son propre poste* (règle existante, `SuiviPostesController.php:57`) ; **et** un en-tête de version falsifié ne donne aucun droit (information de supervision seulement) ; **et** le jeton en clair n'apparaît jamais dans l'écran, le journal ni `journal_audit`.
- *Négatif — compat.* **Étant donné** un poste ancien sans en-têtes de version, **alors** il fonctionne ; l'écran affiche « version inconnue ».

**Considérations techniques.** Publier `config/sanctum.php` avec `expiration` en minutes + job de nettoyage des jetons expirés (à documenter dans `docs/LISTE_DES_CRON_JOBS_CPANEL.md`, garde `ListeCronDocumenteeTest.php`). Le poste envoie `X-Tatacora-Poste-Version`, `…-Schema`, `…-Machine` (le middleware `GenerationDesDonnees` fournit déjà le modèle d'en-têtes). `poste_id` reste le nom du jeton pour ne pas casser classification des conflits, `origines_synchronisation` et correspondances (`PosteDuJeton.php:39-45`). Écriture de `poste.json` : réutiliser `_modifier` (atomique, `configuration_poste.dart:435-455`). Test : jeton réel (jamais `Sanctum::actingAs`, piège n°12 du Blueprint).

**Dépendances.** Fondation de EX-2 et EX-1 (identité du poste). Q-4 (durée).

---

#### EX-2 — Création d'un jeton / code d'appairage depuis le web (P1)

**Description.** Sur « Postes & Appairage », un administrateur crée un **code d'appairage** pour un nom de poste donné. Le code est **à usage unique**, de **durée courte**, **affiché une seule fois**, **révocable** tant qu'il n'est pas utilisé. Au poste, le technicien saisit le nom du poste et le code (pas de mot de passe de compte serveur). L'appairage **depuis le poste** (identifiant + mot de passe) **reste disponible** (c'est un chemin existant, `service_appairage.dart:40`).

**Options comparées.**

| Option | Pour | Contre |
|---|---|---|
| a. Afficher directement un jeton Sanctum longue durée à copier | Simple | Secret durable en clair dans un presse-papiers, un message, une capture |
| b. **Code court à usage unique échangé contre un jeton** (recommandée) | Le secret durable ne transite jamais par l'humain ; expiration courte ; révocable | Une table et un point d'API de plus |
| c. QR code | Pas de saisie | Poste de comptoir sans caméra fiable ; ajoute un composant |

**Recommandation : b.** Code de 12 caractères en 3 groupes sans caractères ambigus (pas de `0/O`, `1/I/l`), durée de vie **15 minutes** (Q-4), haché en base (seul le hash est stocké, comme le code de secours, Blueprint §7.5).

**Critères d'acceptation**
- *Nominal.* **Étant donné** un administrateur, **quand** il crée un code pour `COMPTOIR-2`, **alors** le code s'affiche **une fois** (fenêtre « Copier / Imprimer »), avec l'heure d'expiration ; la liste montre ensuite seulement « Code émis pour COMPTOIR-2, expire à 14:35, non utilisé » (jamais le code).
- *Nominal — poste.* **Étant donné** un code valide, **quand** le technicien saisit nom + code au poste, **alors** le serveur échange le code contre un jeton nommé `COMPTOIR-2` (même contrat que `createToken($poste)`, `AuthController.php:143`), le code est consommé, le poste range le jeton dans `poste.json`, et la ligne `postes` (EX-3) est créée.
- *Erreur — code expiré / déjà utilisé / inconnu.* **Alors** un message **identique** quelle que soit la cause (« Code invalide ou expiré »), sans indice ; compté pour la limite.
- *Erreur — limite.* **Étant donné** 5 codes faux en 300 s depuis la même adresse ou pour le même nom de poste, **alors** blocage temporaire (même politique que `AuthController.php:84`), par couple (nom de poste + IP) — au Gîte tous les postes sortent par la même IP publique (`AuthController.php:80-83`).
- *Erreur — nom en conflit.* **Étant donné** que `COMPTOIR-2` a déjà un jeton valide, **alors** la création demande une confirmation explicite « remplacer l'appairage existant ? » ; l'échange révoque l'ancien jeton (comportement de `AuthController.php:141`).
- *Négatif — révocation.* **Étant donné** un code non utilisé, **quand** l'administrateur le révoque, **alors** il est inutilisable immédiatement.
- *Négatif — droits.* **Étant donné** un non-administrateur, **alors** 403 ; l'action est inscrite aux gardes Livewire ; un administrateur ne crée pas de code pour un compte qu'il ne peut pas gérer.
- *Négatif — secrets.* Le code n'apparaît ni dans `journal_audit`, ni dans les logs, ni dans la session (garde `SessionSansDonneeMetierTest`, clé à ajouter) ; l'audit note seulement « code créé / utilisé / révoqué » + poste + auteur.
- *Négatif — D1.* Un poste non appairé fonctionne entièrement hors synchronisation ; l'absence de code n'empêche aucune saisie.

**Considérations techniques.** Table `codes_appairage` (hash, `poste_id`, `cree_par`, `expire_le`, `utilise_le`, `revoque_le`) ; point d'API **public mais limité** `POST /api/v1/appairage/code` (le seul endpoint sans jeton, avec limitation de débit et middleware de génération). Le jeton est émis pour un **utilisateur de service** ou pour l'administrateur créateur ? **Question ouverte** (Q-12) : aujourd'hui un jeton est lié à un compte dont les droits (RBAC par module) bornent ce que le poste peut écrire (`SynchronisationService.php:415`, `utilisateurAutorise`). Il faut décider du compte porteur des droits du poste. Écran du poste : `FL/features/parametres/presentation/widgets/onglet_synchronisation.dart:77`, ajouter un second mode « J'ai un code ». Respecter l'interrupteur (D1) et `nettoyerNomPoste` (piège n°13).

**Dépendances.** EX-3 (table `postes`). Q-12.

---

#### EX-5 — Suppression synchronisée généralisée (P1)

**Description.** Étendre la suppression synchronisée au-delà des unités d'hébergement et véhicules (`CatalogueDescendantService.php:52-60`), **par règle de table**. Principes : (1) **supprimer ≠ effacer** : on utilise une **suppression logique** (marqueur `supprime_le`, « tombstone ») qui descend comme un élément `supprime: true` (mécanisme existant, `SuppressionsDescendantes`) ; (2) la purge physique n'a lieu qu'après une **rétention** ; (3) tout ce qui est **comptable ou immuable** reste archivage ou contre-passation.

**Règles par famille de table (proposition).**

| Famille | Exemples | Règle |
|---|---|---|
| Écritures et pièces comptables | `ecritures_comptables`, factures validées, avoirs, paiements | **Jamais supprimées** (RG-11 pièces immuables) ; correction = contre-passation par le service existant |
| Documents sources financiers | ventes, dépenses, commandes d'achat, bons de réception | **Annulation** (statut), jamais suppression ; l'annulation descend déjà |
| Référentiels avec historique | articles, clients, fournisseurs, plats | **Archivage** (`actif: false`, déjà le cas) ; suppression seulement si **aucun** document ne les cite |
| Référentiels sans historique | tables de salle, canaux, lieux, centres de coût inutilisés | Suppression logique + purge après rétention, si non cités |
| Brouillons / paniers non validés | paniers ouverts, brouillons | Suppression logique autorisée, rétention courte |
| Déjà en place | unités d'hébergement, véhicules | Inchangé |

**Critères d'acceptation**
- *Nominal.* **Étant donné** une table de salle jamais utilisée, **quand** l'administrateur la supprime sur le web, **alors** une suppression logique est posée, elle descend à chaque poste comme `supprime: true`, chaque poste la retire s'il n'a **aucune saisie locale** qui la cite, et le journal de réception le consigne.
- *Nominal — poste hors ligne.* **Étant donné** un poste hors ligne 20 jours, **quand** il revient, **alors** il reçoit la suppression (le tombstone vit au moins la rétention) et l'applique ; la file du poste partant de sa saisie sur cet élément est traitée selon la règle (rejet `entite_inconnue` lisible dans « À traiter » ; rien n'est perdu sans trace).
- *Erreur — poste hors ligne trop longtemps.* **Étant donné** un poste absent plus longtemps que la rétention, **alors** son premier passage déclenche une **redescente complète** automatique contrôlée (« Redescendre depuis le début », `JournalEnvoiService.php:112-150`) pour ne pas ressusciter l'élément, et l'écran le signale.
- *Erreur — élément cité.* **Étant donné** un élément cité par un document, **alors** la suppression est refusée avec la phrase « Cet élément est utilisé par N documents : archivez-le » (pas de suppression en cascade).
- *Négatif — comptabilité.* **Quelle que soit la table financière**, la demande de suppression est refusée (`piece_immuable`) ; les triggers RG-11 restent en place et un test de balayage vérifie qu'aucune table de `TABLES_FINANCIERES` n'accepte `accepteSuppression` (`ClassificationConflitService.php:34`).
- *Négatif — saisie locale en attente.* Le poste **ne supprime pas** un élément auquel une saisie locale non synchronisée est rattachée : il le conserve et le dit au journal (comportement existant à étendre).
- *Négatif — registres alignés.* Le registre serveur (`accepteSuppression`) et celui du poste (`operation_sync.dart:44-50,88`) restent identiques (test existant de relecture du PHP à étendre).
- *Négatif — D1/D2.* Aucune suppression ne vide la base d'un poste hors ligne ; les comptes utilisateurs ne sont jamais concernés.

**Considérations techniques.** Rétention des tombstones : **proposition 90 jours**, supérieure au TTL d'idempotence (30 jours, `SynchronisationService.php:84`) et à la plus longue absence réaliste (Q-3). Nécessite un champ `supprime_le` par table concernée (migrations additives, schéma poste incrémenté, `retour_arriere_schema.dart` à jour), le curseur existant sur `suppressions_synchronisation` (pseudo-source `suppressions`, `:120`), et le cas aligneur « supprimer » (`aligneur_catalogue.dart`, aujourd'hui « l'élément reste et le bilan le compte »). Pas de « suppression synchronisée » pour une table sans règle écrite : **liste fermée**, comme aujourd'hui (« toute table ajoutée demain n'obtient aucun comportement par omission »). Piège n°11 : chaque table a **deux moitiés** (qui supprime, qui descend la suppression) — un test par table.

**Dépendances.** Q-3 (rétention) ; EX-3 (état du poste pour détecter les absences trop longues). Lot 6 après arbitrage.

---

### P2

#### EX-1 — Notification quasi instantanée en plus de l'interrogation (P2)

**Description.** Le serveur **signale** aux postes en ligne qu'il y a du nouveau, afin qu'ils lancent aussitôt un passage de synchronisation (au lieu d'attendre 5 min ; le bouton web « Synchroniser » passe aujourd'hui par un sondage de 30 s, Blueprint §6). **Contrainte non négociable (D1)** : un poste derrière un réseau instable continue de fonctionner **sans** le serveur, et l'interrogation toutes les 5 min **reste le filet de sécurité** : le signal n'est qu'un **accélérateur**, jamais une condition de correction. Un signal perdu ou en double est sans conséquence (le passage est idempotent, curseur par table).

**Options comparées.**

| Option | Fonctionnement | Pour | Contre | Adéquation |
|---|---|---|---|---|
| **WebSocket (Laravel Reverb / Pusher)** | Connexion persistante poste ↔ serveur | Vrai temps réel, bidirectionnel, écosystème Laravel | Processus long (Reverb) incompatible avec un cPanel mutualisé à cron minute (`LISTE_DES_CRON_JOBS_CPANEL.md`) ; port/proxy WebSocket ; Pusher = service tiers payant ; reconnexions à gérer sur réseau instable ; dépendance Flutter à ajouter | Bonne si l'hébergeur le permet (VPS). **À vérifier** |
| **SSE (Server-Sent Events)** | Flux HTTP unidirectionnel ouvert | Plus simple que WebSocket, passe les proxys HTTP | Un worker PHP-FPM occupé par poste ; coupures nombreuses sur réseau instable ; timeouts d'hébergeur | Moyenne |
| **Long-polling court** | `GET /sync/signal?depuis=<marqueur>` : le serveur garde la requête ≤ 20-25 s et répond dès qu'un changement survient (ou « rien ») ; le poste relance aussitôt | Aucun nouveau protocole, aucune nouvelle dépendance Flutter, **fonctionne derrière les proxys, sur un hébergement PHP classique**, dégrade en simple sondage | Un worker occupé par poste pendant l'attente (5 postes : acceptable) ; latence ≤ quelques secondes plutôt que 0 | **Bonne par défaut** |
| **FCM (Firebase Cloud Messaging)** | Notification push du fabricant | Réveille un appareil éteint | **Pas de support Flutter Windows de bureau** ; dépendance Google ; inutile pour un poste de comptoir toujours allumé ; secrets Firebase à gérer | Écartée |

**Recommandation (à confirmer, Q-1).** Livrer en deux temps : **(1) long-polling court** (`GET /sync/signal`), qui remplace le sondage de 30 s et cible un p95 ≤ 15 s sans changer l'hébergement ; **(2) migrer vers WebSocket (Reverb)** **seulement si** l'hébergeur autorise un processus persistant et que la mesure montre que le long-polling ne suffit pas (charge ou latence). Dans les deux cas, `periodeSynchronisation = 5 min` (`providers_synchronisation.dart:314`) **est conservée** et relue par l'interrupteur D1.

**Critères d'acceptation**
- *Nominal.* **Étant donné** deux postes en ligne, **quand** A clôture une caisse (ou qu'un administrateur clique « Synchroniser » sur le web), **alors** B lance un passage dans les 15 s (p95), reçoit le flux depuis **son** curseur, sans rejouer ce qui est déjà descendu.
- *Nominal — dégradation.* **Étant donné** que le canal de signal est indisponible, **alors** le poste continue de se synchroniser toutes les 5 min, sans erreur visible, sans blocage d'écran.
- *Erreur — réseau instable.* **Étant donné** des coupures de 10 s toutes les minutes, **alors** le poste ne boucle pas en reconnexions serrées : repli exponentiel plafonné (30 s → 1 h, comme `bilan_synchronisation.dart:142-153`) ; aucune file n'est perdue.
- *Erreur — jeton refusé / génération périmée.* **Alors** 401/409 sont traités comme aujourd'hui (arrêt, `appairage_refuse`), le signal ne contourne pas ces gardes.
- *Négatif — interrupteur.* **Étant donné** `synchronisation_activee = false`, **alors** **zéro** requête de signal (test à transport qui lève, comme `synchronisation_desactivee_test.dart:85`).
- *Négatif — tempête.* **Étant donné** 20 signaux en 10 s, **alors** un seul passage à la fois (verrou existant, anti-rebond de 60 s côté demande `SuiviPostesService.php:39` conservé pour le bouton web).
- *Négatif — pas de donnée dans le signal.* Le signal ne transporte **aucune donnée métier** (juste « du nouveau, venez voir » + un marqueur) : le contrôle d'accès RBAC par table reste appliqué au `GET /referentiels`.
- *Négatif — D2.* Le signal est par poste (jeton) ; un poste ne reçoit pas le signal d'un autre poste révoqué.

**Considérations techniques.** Marqueur de changement serveur à bas coût (compteur en cache ou table à une ligne incrémentée par les gestionnaires), **sans** casser l'horizon de stabilité de 5 s du flux (`CatalogueDescendantService.php:110`) : un signal peut précéder de 5 s la disponibilité de l'élément ; le poste doit retenter après l'horizon. Délai HTTP de 20 s (`transport_synchronisation.dart:34`) **inférieur** à la durée d'attente du long-polling : prévoir un délai distinct pour ce seul appel. Mesure : horodater le signal et le début du passage. `BROADCAST_CONNECTION=log` (`.env.example:43`) ne change que pour l'option WebSocket.

**Dépendances.** EX-3 (identité et statut du poste, pour ne signaler que des postes actifs) ; Q-1 (hébergement). Décision à prendre avant toute dépendance ajoutée à `pubspec.yaml` / `composer.json`.

---

## 6. Indicateurs de réussite

| Type | Indicateur | Cible | Méthode de mesure |
|---|---|---|---|
| Avancé | Taux de démarrage réussi après installation sur VM vierge | 100 % (≥ 5 installations, 2 versions de Windows) | Recette manuelle avant chaque livraison (case dans `docs/RESTE_A_FAIRE.md`) |
| Avancé | Constructions échouées avec fichier ou étape nommés | 100 % | Revue du journal de construction ; test d'un fichier supprimé à chaque évolution du `.bat` |
| Avancé | Migrations précédées d'une copie vérifiée | 100 % | Test automatisé sur les 20 dumps réels + ligne de `demarrage.log` |
| Avancé | Conflits financiers en attente > 7 jours | 0 | Requête sur `conflits_synchronisation` (statut, `created_at`), affichée sur l'écran |
| Avancé | Délai de propagation poste → poste (postes en ligne) | p95 ≤ 15 s (aujourd'hui ≤ 10 min visé) | Horodatage saisie / réception sur banc d'essai à 5 postes (`essai_cinq_postes_test.dart`) puis en production |
| Avancé | Jetons sans expiration | 0 | Requête sur `personal_access_tokens` |
| Avancé | Postes avec versions remontées | 100 % des postes à jour | Écran de supervision |
| Retardé | Décisions de conflit avec motif et auteur | 100 % | Audit de `journal_audit` à 30 jours |
| Retardé | Délai médian de décision d'un conflit | ≤ 2 jours ouvrés | Écart `created_at` → `date_arbitrage`, mensuel |
| Retardé | Pertes de données signalées après désinstallation/migration | 0 sur 6 mois | Journal des incidents ; retour des gérants |
| Retardé | Appairages sans mot de passe au poste | ≥ 90 % des nouveaux appairages à 3 mois | Compte des appairages par code vs login |
| Retardé | Rapport signal / interrogation (si EX-1 livré) | ≥ 80 % des passages déclenchés par signal | Compteur de cause de passage dans le bilan de synchronisation |
| Retardé | Postes rattrapés par redescente après absence > rétention | 100 % sans élément ressuscité | Test de contrôle de cohérence (`CoherenceService`) après retour |

---

## 7. Plan et calendrier par lots

> Estimations **relatives** : S = quelques heures à 1 jour ; M = quelques jours ; L = une à deux semaines. Pas de dates tant que les questions bloquantes (§8) ne sont pas levées. Chaque lot garde les pratiques du dépôt : migrations additives, mutation des gardes, suite complète, mise à jour de `docs/JOURNAL_DES_LOTS.md`.

| Lot | Contenu | Exigences | Estimation | Dépend de | Pourquoi dans cet ordre |
|---|---|---|---|---|---|
| **1** | Garde-fous de construction : `analyze`, tests / `--sans-tests`, flavors, fichiers sources nommés, DLL VC++, nom de sortie, dossier `installer\Output`, journal ; correction de `README_DEPLOY.md` | EX-7, EX-9 | **S** (M avec recette VM) | Q-8, Q-9, Q-10 | Gain immédiat, zéro risque pour les données, débloque un poste neuf |
| **2** | Sauvegarde avant migration + restauration depuis l'écran de panne ; sauvegarde proposée à la désinstallation | EX-6, EX-8 | **M** | Lot 1 (installateur), Q-5, Q-6 | Protège la seule copie des saisies ; EX-6 avant tout futur changement de schéma (lots 3 et 5) |
| **3** | Écran « Conflits à trancher » + retour au poste | EX-4 | **L** | Q-2, Q-11 | Seul écart qui bloque des documents financiers |
| **4** | Table `postes`, en-têtes de version, expiration glissante et rotation, supervision web | EX-3 | **M/L** | Lot 2 (sauvegarde avant schéma), Q-4 | Fondation d'EX-2 et d'EX-1 |
| **5** | Code d'appairage créé sur le web, saisi au poste | EX-2 | **M** | Lot 4, Q-12 | Dépend de l'identité stable et de l'expiration |
| **6** | Suppression synchronisée par règles de table, tombstones, rétention, redescente automatique | EX-5 | **L** | Lots 2 et 4, Q-3 | Touche au schéma poste et à l'immuabilité comptable : après sauvegardes et supervision |
| **7** | Signal quasi instantané : long-polling court (puis WebSocket si justifié) | EX-1 | **M** (long-polling) / **L** (WebSocket) | Lot 4, Q-1 | Confort, pas de risque de perte ; dernier |

Lots 1 et 2 sont indépendants des lots serveur 3 à 7 et peuvent se dérouler en parallèle du lot 3.

---

## 8. Questions ouvertes (priorisées)

### Bloquantes (avant de démarrer le lot concerné)

| # | Question | Qui répond | Bloque | Recommandation |
|---|---|---|---|---|
| **Q-1** | **Quel transport temps réel ?** L'hébergement actuel (cron cPanel, `LISTE_DES_CRON_JOBS_CPANEL.md`) autorise-t-il un processus persistant (Reverb) ou seulement PHP classique ? Quel budget (Pusher) ? | PO + hébergeur / administrateur serveur | Lot 7 | Long-polling court d'abord ; WebSocket seulement après réponse de l'hébergeur |
| **Q-2** | **Qui tranche les conflits financiers ?** Administrateurs seuls, Administrateurs + Comptable, Comptable seul ? Un arbitre peut-il trancher son propre document ? | PO, avec le comptable | Lot 3 | Administrateurs + Comptable, jamais son propre document |
| **Q-3** | **Politique de rétention des suppressions** (tombstones) : combien de jours ? que faire d'un poste absent plus longtemps ? | PO (+ comptable pour les tables financières) | Lot 6 | 90 jours ; redescente automatique au retour |
| **Q-8** | **Emplacement de la sortie de l'installateur** : `installer\Output` (recommandé) ou `build\installer` (actuel) ? | PO | Lot 1 | `installer\Output`, car `flutter clean` détruit `build\` |
| **Q-9** | **Redistribution des DLL VC++** : confirmer que la copie app-local de `msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll` est acceptable pour la distribution (sinon plan B : `vc_redist.x64.exe`) | PO / éditeur (Dr MASSENON) | Lot 1 | Copie app-local, plan B documenté |

### Non bloquantes (réponse avant la fin du lot concerné)

| # | Question | Qui répond | Concerne | Recommandation |
|---|---|---|---|---|
| **Q-4** | **Durées de vie** : jeton (90 jours glissants ?), rotation à 60 jours, code d'appairage (15 min) | PO | Lots 4 et 5 | Valeurs proposées ci-dessus |
| **Q-5** | **Sauvegarde avant migration** : rétention (1 à 3, proposé 3) ; l'échec de sauvegarde (disque plein) **bloque-t-il** la migration ? | PO | Lot 2 | 3 copies ; oui, elle bloque |
| **Q-6** | **Contenu de la sauvegarde à la désinstallation** : inclure `poste.json` (jeton et mot de passe SMTP en clair) ? | PO | Lot 2 | Inclure avec avertissement, ou exclure le jeton |
| **Q-7** | **Ancienneté minimale de version** : à partir de quelle version un poste est-il affiché « obsolète » ? qui la paramètre ? | PO | Lot 4 | Paramètre serveur modifiable par l'administrateur |
| **Q-10** | **`--sans-tests` autorisé en production ?** | PO / responsable technique | Lot 1 | Interdit en production, permis en recette et dev |
| **Q-11** | **Retour de la décision au poste** : mise à jour du résultat mémorisé ou interrogation d'un point `GET /sync/conflits/{id}` ? | Architecte | Lot 3 | À trancher en conception ; préférer le chemin qui n'exige aucune migration du poste |
| **Q-12** | **Compte porteur des droits d'un poste appairé par code** : quel utilisateur reçoit le jeton (celui qui crée le code, un compte de service, un compte choisi) ? Cela borne le RBAC par module des écritures du poste | PO + Architecte | Lot 5 | Compte choisi à la création du code, modifiable ensuite |

---

## 9. Risques et garde-fous transverses

- **La donnée non synchronisée est la seule copie qui existe** : EX-6, EX-8 et EX-5 sont conçues autour de cette phrase ; aucune ne supprime ou n'écrase sans copie ou sans refus lisible.
- **Poste autonome** : EX-1, EX-2, EX-3, EX-4 ne rendent aucun écran du poste dépendant du réseau ; les nouveaux chemins réseau lisent l'interrupteur (test à transport qui lève).
- **Schéma poste** : toute évolution (EX-5 principalement) = migration additive conditionnelle, fixture de retour arrière, test sur fichier réel et sur les dumps anciens (pièges n°2 et n°3 du `CLAUDE.md` poste).
- **Gardes à mettre à jour** : `PwaActionsReluesTest`, `PwaEcritureAutoriseeTest`, `SessionSansDonneeMetierTest`, `ListeCronDocumenteeTest`, test de relecture du registre PHP par le poste ; chaque garde nouvelle est prouvée par **mutation**.
- **Honnêteté des affirmations** (piège n°1 et n°13) : la phrase « Rien d'autre à installer » de `README_DEPLOY.md:89` et le chemin `C:\Program Files\TATACORA` sont à corriger dans le lot 1 ; un écran ne dit « sauvegarde faite » que si la copie a été vérifiée.
- **Ce que cette spec n'a pas pu vérifier** : le comportement de l'hébergeur (Q-1), la possibilité de redistribuer les DLL (Q-9) et l'effet réel de `flutter analyze` sur le dépôt (nombre de `warning` actuels) — à mesurer avant le lot 1.

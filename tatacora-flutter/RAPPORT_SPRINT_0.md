# RAPPORT DE VÉRIFICATION — SPRINT 0 FLUTTER

| | |
|---|---|
| **Dossier** | `tatacora_flutter/` |
| **Prompt exécuté** | `docs/PROMPT_LANCEMENT_NOUVELLE_IMPLEMENTATION_FLUTTER.md` v1.1 |
| **Chaîne d'outils** | Flutter 3.44.8 stable · Dart 3.12.2 |
| **Date** | 18/08/2026 |
| **Statut** | Livré — vérifié par exécution réelle |

---

## 1. Vérification — `GUIDE_VERIFICATION_FLUTTER.md`

| Étape | Commande | Résultat |
|---|---|---|
| 1. Génération de code | `dart run build_runner build --delete-conflicting-outputs` | **529 Ko générés**, 0 erreur |
| 2. Analyse statique | `flutter analyze` | **`No issues found!`** — 0 error, 0 warning |
| 3. Compilation réelle | `flutter build windows --debug` | **`tatacora_flutter.exe` produit** en 44,9 s |
| 4. Tests | `flutter test` | **`All tests passed!`** — 15 tests |

> **La règle qui a manqué au lot des 91 fichiers Dart est respectée** :
> l'analyse et la compilation ont réellement tourné sur cette machine, pas
> « devraient passer ».

---

## 2. Livrables du Sprint 0

| # | Attendu | État |
|---|---|---|
| 1 | Projet initialisé, 4 flavors, arborescence conforme | Livré |
| 2 | Thème complet et vérifiable | Livré — tokens exacts du §2 |
| 3 | Base Drift fonctionnelle, test d'insertion/lecture | Livré — **20 tables**, 5 tests |
| 4 | Écran de connexion contre l'API Laravel | Livré — voir §4 |
| 5 | Navigation de base opérationnelle | Livré — barre basse + menu flottant + sidebar |
| 6 | Résumé, clarifications, points bloquants | Ce document |

### 2.1 Tâche 1 — Projet

`flutter create tatacora_flutter --org bj.faguezsarl`, cibles Windows, Android,
iOS. Arborescence reproduite depuis `ARBORESCENCE_COMPLETE_PROJET_FLUTTER.md` :
`core/{network,database,sync,rbac,theme,responsive,router,di,config}`,
`features/auth/{data,domain,presentation}`, `shared_widgets/`.

`analysis_options.yaml` en mode strict, avec `strict-casts`,
`strict-inference`, `strict-raw-types`, et les règles qui cassent en production
remontées au rang d'erreur — dont `unawaited_futures` : un `Future` non attendu
produit un ordre d'exécution imprévisible, et l'écriture locale peut partir
après l'appel réseau qui la lit.

### 2.2 Tâche 2 — Thème

Tokens repris **exactement** du §2 : navy `#14213D`, gold `#B8891E`,
fondClair `#F2F2F2`, anthracite `#262626`, les trois sémantiques, les deux
dérivées de badge, l'échelle neutre à 7 crans.

Deux points de vigilance appliqués :

- **Seule la 2ᵉ révision typographique (15/08/2026) est appliquée.** Le
  document en porte deux successives à la hausse ; les appliquer en cascade
  donnerait des tailles doublement majorées.
- La `ColorScheme` est **construite explicitement**, pas dérivée par
  `ColorScheme.fromSeed` : un algorithme de dérivation produirait des teintes
  que le client n'a pas approuvées.

Point de rupture unique à **1024 px** — au-delà, sidebar permanente ; en deçà,
barre basse.

### 2.3 Tâche 3 — Base Drift

**20 tables**, bornées au périmètre offline du §0 : M1, M2, M5, M6, M8, M9,
plus les référentiels et l'infrastructure de synchronisation. **Aucune table
hors périmètre** — pas de M4, M7, M10 à M13.

Les définitions ont été **extraites des trois documents de migration**, pas
retranscrites : transcrire 20 tables à la main introduit des écarts invisibles,
et un `nullable()` oublié ne se voit qu'à la première insertion en production.

`PRAGMA foreign_keys = ON` est posé à l'ouverture : sous SQLite, les clés
étrangères ne sont **pas** actives par défaut, et sans cette ligne une ligne de
facture peut survivre à sa facture.

`*.g.dart` et `*.freezed.dart` sont exclus du contrôle de version.

### 2.4 Tâche 4 — Authentification

Jeton Sanctum dans `flutter_secure_storage` **uniquement**. Il n'est pas porté
par l'objet `Session` : un jeton dans l'état applicatif finit dans un
`toString()` de log ou une capture de débogage.

**L'écran de connexion ne contient qu'un formulaire identifiant / mot de
passe.** Aucune grille de comptes cliquables, aucun raccourci par rôle, dans
**aucun flavor y compris `demo`** (`SECURITY_STRICT.md` §12).

Deux décisions de conception qui méritent d'être signalées :

- **Un serveur injoignable n'est pas un identifiant incorrect.** Les confondre
  pousse l'utilisateur à ressaisir son mot de passe indéfiniment alors qu'il
  n'y peut rien. Deux exceptions distinctes, deux messages distincts.
- **Le jeton est effacé avant l'appel de déconnexion.** Si la requête échoue
  faute de réseau, l'utilisateur doit tout de même être déconnecté localement —
  l'inverse laisserait une session active sur un poste qu'on croyait fermé.

RBAC premier niveau (`GardeAcces`) : un droit ne s'obtient **jamais** par
omission. Code inconnu, absent, mal orthographié ou de type inattendu →
« aucun accès ». Dix tests le vérifient.

### 2.5 Tâche 5 — Navigation

`go_router`, arbre unique. Redirection vers `/connexion` portée par le
**routeur**, pas par un contrôle dans chaque écran — un contrôle par écran
s'oublie sur le onzième.

Barre basse à **5 items** (Accueil, Réservations, Stocks, Dépenses, Rapports),
menu flottant à **10 raccourcis**, les deux filtrés RBAC. Un item sans droit
est **retiré**, pas grisé : un item grisé invite à cliquer et produit un refus.

Les écrans métier sont des coquilles nommées, conformément au périmètre.

---

## 3. Divergences avec la spécification — à arbitrer

Deux, signalées plutôt que contournées silencieusement.

### 3.1 `riverpod_generator` est incompatible avec `drift_dev`

**Constat.** `drift_dev 2.34.0` impose `analyzer 12.1.0` ;
`riverpod_generator` exige `analyzer ^13`. Aucune combinaison de versions ne
résout sur ce SDK.

**Décision.** `drift_dev` est conservé — la Tâche 3 exige explicitement
`dart run build_runner build` pour Drift. `riverpod_generator` est retiré : il
n'apporte que du sucre syntaxique sur la déclaration de providers.

**Ce que cela ne change pas.** Riverpod reste le mécanisme d'état, sans
exception. Seule la génération d'annotations disparaît ; les providers sont
déclarés à la main (`Provider`, `NotifierProvider`), ce qui est l'API standard.

**À arbitrer :** réintroduire `riverpod_generator` quand les contraintes
d'`analyzer` convergeront, ou acter la déclaration manuelle.

### 3.2 `sqlite3_flutter_libs` est devenu un paquet vide

**Constat.** La spécification liste ce paquet et son
`applyWorkaroundToOpenSqlite3OnOldAndroidVersions()`. Depuis
`package:sqlite3` 3.x — la version qu'embarque Drift 2.34 —, la version
`0.6.0+eol` **ne fait plus rien**, et son mainteneur demande explicitement de
la retirer des dépendances.

**Décision.** Retiré. Conserver un paquet no-op parce qu'un document l'énumère
serait pire qu'une divergence signalée : personne ne saurait, dans six mois,
s'il est encore nécessaire.

**À faire :** mettre à jour
`PROMPT_LANCEMENT_NOUVELLE_IMPLEMENTATION_FLUTTER.md` §Tâche 1, écrit à l'ère
0.5.x du paquet.

---

## 4. Point bloquant — levé le 18/08/2026, et pire que prévu

> **État initial (18/08/2026, rédaction du Sprint 0)** — L'écran de connexion
> appelle `POST /login` sur la base URL du flavor. Il n'avait pas été confronté
> à un backend Laravel en fonctionnement. Deux inconnues : la route existe-t-elle,
> et le format de réponse `{token, utilisateur:{id, nom, role, droits}}` est-il
> le bon ? Ce contrat était **une hypothèse de conception, pas un constat**.

La vérification a donné la réponse la plus défavorable des deux : **la route
n'existait pas**. `createToken` n'apparaissait nulle part dans `app/` — ni
contrôleur, ni route, ni test d'authentification. Les 32 points d'entrée de
l'API étaient tous derrière `auth:sanctum`, et aucun code n'émettait le jeton
qu'ils exigent. **L'API était inaccessible à tout client.**

Ce qui l'a masqué mérite d'être retenu : 421 tests verts, dont 303 tests
Feature qui s'authentifient par `actingAs()`. Cette méthode injecte
l'utilisateur directement dans le guard et n'a jamais besoin d'un jeton. Une
suite verte ne dit rien d'un chemin qu'aucun test n'emprunte.

Trois défauts en cascade sont apparus derrière, chacun invisible tant que le
précédent n'était pas corrigé :

| # | Défaut | Pourquoi il ne pouvait pas se voir avant |
|---|---|---|
| 1 | Table `personal_access_tokens` absente | Depuis Sanctum 4, le paquet ne charge plus ses migrations depuis `vendor/` : elles doivent être publiées. Aucun code ne les utilisait, donc rien ne s'en plaignait |
| 2 | La migration de Sanctum est inutilisable telle quelle | Elle déclare `morphs('tokenable')`, soit un `BIGINT UNSIGNED`, alors que `utilisateurs.id` est un `uuid`. La colonne aurait été incapable de porter la clé qu'elle référence — d'où `uuidMorphs` |
| 3 | Aucun `lang/fr/auth.php`, alors que 4 clés `auth.*` étaient déjà appelées | `MessagesUtilisateurTest` ne contrôle que les groupes de traduction **présents**. Créer le fichier a fait entrer le groupe `auth` dans son périmètre et révélé les quatre clés d'un coup. En production, un refus RBAC affichait littéralement `auth.module_refuse` |

### Le contrat, maintenant vérifié

`POST /api/v1/login` — `{identifiant, mot_de_passe, poste?}` →
`{token, utilisateur:{id, login, nom, role, droits}}`, `droits` portant
**les 16 modules**, y compris ceux sans accès, à `'-'`.

Deux ajustements côté client en découlent : `Session` porte désormais `login`
(un compte technique n'a pas de fiche employé, le serveur renvoie alors le
login en guise de nom), et le client envoie un `poste` **persistant** — le
serveur s'en sert pour révoquer le jeton antérieur du même appareil, ce qu'un
identifiant tiré à chaque démarrage rendrait impossible.

| Vérification | Résultat |
|---|---|
| `php artisan test` | **435 tests** (421 avant), dont 14 pour l'authentification |
| `./vendor/bin/pint --test` · `phpstan analyse` | passed · **0 erreur** |
| `flutter analyze` · `flutter test` | `No issues found!` · **29 tests** (15 avant) |
| Contrôles contre `php artisan serve` réel | **21 / 21**, compte jetable détruit après coup |

La Definition of Ready de `SDLC_FLUTTER.md` §6.1 — *vérifier que les routes
existent, pas les supposer* — a payé son coût dès sa première application.
Détail complet en **PA-54** (`docs/PLAN_ACTION_SEQUENCE_POST_AUDIT.md` §3).

---

## 5. Commandes

```bash
cd tatacora_flutter

dart run build_runner build --delete-conflicting-outputs   # AVANT toute analyse
flutter analyze                                             # 0 error, 0 warning
flutter test                                                # 15 tests
flutter build windows --debug                               # compilation réelle

# Lancement par flavor
flutter run --dart-define=ENV=dev
flutter run --dart-define=ENV=demo -t lib/main_demo.dart
```

Le backend local doit tourner pour le flavor `dev` :

```bash
cd ../tatacora-api && php artisan serve   # http://localhost:8000
```

---

## 6. Suite

`docs/SPRINT_1_FLUTTER_BOUT_EN_BOUT.md` — tranche verticale M1 Hébergement, de
la saisie hors ligne au rejet serveur RG-01.

---

## Historique des révisions

| Version | Date | Auteur | Modification |
|---|---|---|---|
| 1.0 | 18/08/2026 | Adderly (Cabinet FAGUEZ SARL) | Création. Sprint 0 exécuté et vérifié par compilation réelle : 20 tables Drift extraites des documents de migration, thème aux tokens exacts, authentification à jeton confiné, navigation filtrée RBAC. Deux divergences signalées — `riverpod_generator` incompatible avec `drift_dev`, et `sqlite3_flutter_libs` devenu un paquet vide. Un point bloquant : le contrat de la route de connexion n'a pas été confronté au backend |
| 1.1 | 18/08/2026 | Adderly (Cabinet FAGUEZ SARL) | **§4 : point bloquant levé, et la réponse est la plus défavorable des deux envisagées — la route de connexion n'existait pas.** Aucun jeton n'était jamais émis alors que les 32 routes de l'API l'exigeaient : l'API était inaccessible à tout client, et 421 tests verts ne le montraient pas (`actingAs()` court-circuite le guard). Trois défauts en cascade derrière : table `personal_access_tokens` jamais publiée, migration Sanctum incompatible avec une clé `uuid`, et quatre clés `auth.*` sans fichier de langue — un refus RBAC affichait sa clé brute à l'utilisateur. Contrat désormais figé des deux côtés et confronté à un serveur réel : 435 tests Laravel, 29 tests Dart, 21 contrôles bout en bout. Client aligné : `Session` porte `login`, et le `poste` envoyé est persistant. Voir PA-54 |

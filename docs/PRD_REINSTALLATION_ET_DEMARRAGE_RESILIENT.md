# PRD — Réinstallation et démarrage résilient du poste (« le logiciel ne s'ouvre pas »)

> Statut : **brouillon à valider par le Product Owner** (28/10/2026). Origine : retour
> d'expérience d'un autre projet (AgriERP, même pile Flutter + Drift/SQLite) : après
> désinstallation puis réinstallation sur un ancien PC, le processus tourne mais aucune
> fenêtre n'apparaît. Ce document dit **ce que TATACORA a déjà, ce qui lui manque, et
> comment le combler** sans toucher à la règle d'or du poste : *la donnée non synchronisée
> est la seule copie qui existe*.

## 1. État des lieux (vérifié dans le code le 28/10/2026)

| Sujet | Constat dans TATACORA | Écart |
|---|---|---|
| Où vit la base | `%LOCALAPPDATA%\TATACORA\donnees\tatacora.sqlite` (`emplacement_base.dart`) ; configuration `%APPDATA%\TATACORA\poste.json` (jeton, SMTP) ; dossiers `archives/` et `recus_depenses/` à côté de `poste.json` | Hors du dossier du programme : une désinstallation ne les touche pas (voulu). |
| Désinstallation | `installer/tatacora.iss` : **aucune** section `[UninstallDelete]`, et un commentaire interdit d'en ajouter (la base est la seule copie des saisies non synchronisées) | Décision déjà prise, **opposée** à celle d'AgriERP : voir §6. |
| Mise à jour | Même `AppId` : le programme est remplacé, les données restent | OK. |
| Migrations | `AppDatabase.onUpgrade` (schéma **v44**, 77 tables) : additives, **conditionnelles** (`PRAGMA table_info` avant chaque `addColumn`), jamais destructives sauf v10 | Pas de **réconciliation finale** qui compare la base au schéma courant : une base à `user_version` correct mais incomplète (paliers sautés, branches parallèles) échoue au premier accès (`no such table / column`). |
| Tests de migration | 33 fichiers `migration_vNN_*_test.dart` sur **fichier réel**, mais les « anciennes » bases sont fabriquées par `retour_arriere_schema.dart` **depuis le schéma courant** (piège 3 du `CLAUDE.md`) | Aucune base issue d'un **vrai ancien commit** ; aucune comparaison « base migrée = base neuve ». |
| Ouverture de la base | Paresseuse : `baseLocaleProvider` crée `AppDatabase()` à la première lecture, après `runApp` | La fenêtre s'affiche à la première image (runner Windows `SetNextFrameCallback`), donc le symptôme « aucune fenêtre » est **moins probable** qu'ailleurs ; mais une migration qui échoue produit un écran bloqué ou une erreur brute. |
| Filet au démarrage | `main()` = `ensureInitialized()` + `runApp(...)` : ni `try/catch`, ni `runZonedGuarded`, ni `FlutterError.onError`, ni **journal de démarrage**, ni écran « l'application ne peut pas démarrer », ni délai maximal | **Absent.** C'est le plus gros écart. |

Conclusion : TATACORA évite par construction la cause n°1 d'AgriERP (reconstruction de table
qui copie des colonnes inexistantes : aucune migration ne recrée de table sauf v43, qui copie
colonne par colonne) mais est **exposé aux causes n°2 et n°3** (base incomplète, aucun filet).

## 2. Problème

Un poste réinstallé ou mis à jour peut retrouver une base qui ne correspond plus exactement
au schéma attendu. Le jour où cela arrive, le gérant voit un logiciel muet ou figé, sans
message, et personne ne peut dire pourquoi. Pire : rien dans l'application ne protège la
donnée non synchronisée pendant qu'on cherche.

## 3. Objectifs

- G1. **Aucun démarrage muet** : toute erreur avant ou pendant l'ouverture de la base affiche
  un écran lisible et laisse une trace.
- G2. **Toute base ancienne ou incomplète migre vers le schéma courant** sans perdre une
  ligne, quelle que soit sa `user_version` de départ.
- G3. **Preuve** : une base issue de chaque version réelle passée, migrée par le code
  courant, a exactement le schéma d'une base neuve.
- G4. **Décision écrite et visible** sur le sort des données à la désinstallation.

## 4. Hors périmètre

- Réparer ou reconstruire une base **corrompue** (fichier illisible) : on diagnostique et on
  sauvegarde, on ne « répare » pas.
- Changer l'emplacement de la base ou de `poste.json` (décision du 17/10/2026).
- Migrer automatiquement vers un autre moteur de base.

## 5. Exigences

### Indispensables (P0)

**R1 — Écran de panne et journal de démarrage.**
- `main()` enveloppe le démarrage (`runZonedGuarded`, `FlutterError.onError`,
  `PlatformDispatcher.onError`). Toute erreur de démarrage affiche « L'application ne peut pas
  démarrer » : message en français, **cause lisible**, chemin du journal, boutons
  « Copier le détail », « Ouvrir le dossier des données », « Quitter ».
- Journal `demarrage.log` dans le dossier de données (`%LOCALAPPDATA%\TATACORA\donnees\`),
  écriture synchrone et atomique, **tournant** (5 fichiers), jamais de mot de passe ni de
  jeton (`expurgerSecret` existant).
- Ouverture et migration de la base **avant** le premier écran métier, avec un écran
  d'attente (« Mise à jour de la base du poste… »). Au-delà de **45 s** : message « préparation
  bloquée » avec les mêmes boutons.
- *Critère* : une base volontairement cassée (colonne absente, fichier tronqué) donne l'écran
  de panne et une ligne de journal ; jamais une fenêtre vide ni un processus muet.

**R2 — Réconciliation finale du schéma.**
- À la fin de `onUpgrade` **et** à chaque ouverture si `user_version` = version courante mais
  qu'un contrôle rapide trouve un écart (compte de tables), `reconcilierSchema` compare la base à
  `allSchemaEntities` : table absente → `createTable` ; colonne absente → `ALTER TABLE ADD COLUMN`
  (nullable, ou `DEFAULT` explicite pour un `NOT NULL`) ; index et **déclencheurs RG-11** absents
  → recréés (`creerDeclencheursComptables`).
- Jamais destructive : une colonne ou une table **en trop** est laissée et journalisée.
- *Critère* : à partir d'une base `user_version = 44` à laquelle on retire une table, une
  colonne et un déclencheur, l'ouverture rétablit le schéma exact et journalise ce qu'elle a posé.

**R3 — Migration prouvée depuis de VRAIES anciennes bases.**
- Un outil `tool/migration/extraire_schemas_anciens.dart` produit, pour chaque version de
  schéma, le dump SQL (`sqlite_master`) à partir du **commit réel** où cette version est
  apparue (`git archive <commit> lib`) ; les dumps (texte, quelques dizaines de Ko chacun) sont
  versionnés dans `test/fixtures/schemas_anciens/`.
- Un test construit un fichier à partir de chaque dump (avec quelques lignes réalistes),
  l'ouvre avec le code courant, puis compare **tables, colonnes (nom, type, `NOT NULL`, défaut),
  index et déclencheurs** à ceux d'une base neuve : écart zéro, aucune ligne perdue.
- Deux formes de base à reproduire : paliers sautés (v26 → v44 d'un coup) et colonne ajoutée
  après la copie d'une table (cas v43).
- *Critère* : v10, v14, v20, v26, v30, v35, v38, v40, v43 (au minimum) migrent à écart zéro.

### Souhaitables (P1)

- **R4 — Sauvegarde avant migration** : copie `tatacora.sqlite.avant-vNN` (1 exemplaire, la
  plus récente) avant toute montée de version ; l'écran de panne propose « Restaurer la
  sauvegarde » si la migration échoue.
- **R5 — Désinstallation** (selon la décision du §6) : case « Supprimer aussi les données de
  ce poste » **décochée par défaut**, avec une confirmation qui nomme ce qui sera perdu.

### Pour plus tard (P2)

- Rapport de santé du poste (écran Paramètres → Diagnostic : version du schéma, dernier
  démarrage, écarts réconciliés).

## 6. Décision à prendre par le Product Owner

AgriERP a choisi que la désinstallation **supprime** la base, avec confirmation. Pour TATACORA :

| Option | Effet | Risque |
|---|---|---|
| **A (recommandée)** Garder les données ; case optionnelle « Supprimer aussi les données » décochée, confirmation qui nomme les saisies non synchronisées, `poste.json` et les reçus | Une réinstallation retrouve tout ; un poste qu'on met au rebut peut tout effacer volontairement | Il faut R1 à R3 pour que « retrouver une vieille base » marche. |
| B Supprimer toujours (confirmation) | Réinstallation = poste neuf, plus aucun risque de vieille base | Perte **irréversible** de la seule copie des saisies hors ligne si la confirmation est cliquée trop vite. |
| C Statu quo (jamais supprimer) | Aucune perte | Un poste réinstallé garde un vieux jeton d'appairage et une vieille base. |

Autres questions ouvertes : le jeton d'appairage et le mot de passe SMTP (`poste.json`) doivent-ils
survivre à une réinstallation ? (recommandation : oui avec l'option A, avec le bouton
« Révoquer » du serveur en cas de doute).

## 7. Indicateurs de réussite

- Zéro démarrage muet : chaque échec de démarrage laisse une ligne dans `demarrage.log`.
- Les 9 versions de R3 migrent à écart zéro à chaque livraison (garde de test).
- Une base `user_version = 44` incomplète se répare seule à l'ouverture (test R2).

## 8. Plan de livraison

1. **R1** (écran de panne + journal + délai) — sans schéma, le plus rentable.
2. **R2** (réconciliation) puis **R3** (dumps anciens + test de comparaison) — R3 prouve R2.
3. **R4/R5** après la décision du §6, avec la mise à jour de `installer/tatacora.iss`
   (le commentaire « ne pas ajouter `[UninstallDelete]` » est alors réécrit) et de
   `README_DEPLOY.md`.
Contrainte transverse : le poste reste autonome sans synchronisation, et aucune étape
n'écrit ni ne supprime de donnée métier sans geste explicite.

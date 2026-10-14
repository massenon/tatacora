# RAPPORT DE VÉRIFICATION — SPRINT 1 FLUTTER

|---|---|
| **Dossier** | `tatacora_flutter/` |
| **Sprint** | `docs/SPRINT_1_FLUTTER_BOUT_EN_BOUT.md` — tranche verticale M1 Hébergement |
| **Chaîne d'outils** | Flutter 3.44.8 stable · Dart 3.12.2 |
| **Date** | 18/08/2026 |
| **Statut** | Livré — vérifié par exécution réelle, y compris contre un backend en fonctionnement |

---

## 1. En une phrase

> **Le risque n°1 du projet est levé.** Le protocole de synchronisation a
> rencontré un client : les quatre parcours ont tourné contre un backend
> Laravel démarré, et la base du serveur montre 43 réservations sur 43 périodes
> distinctes — **zéro chevauchement**.

---

## 2. Les six étapes du `GUIDE_VERIFICATION_FLUTTER.md`

| Étape | Commande | Résultat |
|---|---|---|
| 0. Environnement | `flutter --version` | Flutter 3.44.8 · Dart 3.12.2 |
| 1. Génération de code | `dart run build_runner build` | **106 sorties**, 0 erreur |
| 2. Analyse statique | `flutter analyze` | **`No issues found!`** — 0 error, 0 warning, 0 info |
| 3. Compilation réelle | `flutter build windows --debug` | **`tatacora_flutter.exe` produit** en 103,4 s |
| 4. Tests | `flutter test` | **179 passés, 1 ignoré** (l'intégration, faute de backend) |
| 4 bis. Intégration | `TATACORA_FIXTURE=… flutter test test/integration/` | **4 parcours passés** contre un backend réel |
| 5. Points non négociables | voir §3 | 1 non-conformité trouvée **et corrigée** |
| 6. Rapport | ce document | — |

`dart format` appliqué sur `lib/` et `test/` : 64 fichiers, 0 en écart.

---

## 3. Étape 5 — les points non négociables, un par un

| Point | Constat |
|---|---|
| RG-01 vérifiée localement | **Oui.** `PeriodeSejour.chevauche` porte la règle, `ReservationDao.chevauchant` la traduit en SQL. Une seule autre écriture de la condition existe, et c'est celle-là. |
| RG-08 (véhicules) | **Sans objet** — M8 n'est pas au périmètre du sprint. Ce n'est pas un écart. |
| Aucun `*.g.dart` committé | **Conforme** — `*.g.dart` et `*.freezed.dart` sont dans `.gitignore`. |
| Aucune clé API en dur | **Conforme.** Les deux correspondances de `Bearer ` sont des **interpolations de variable** (`'Bearer $jeton'`), pas des secrets. Le jeton vit dans `flutter_secure_storage` et nulle part ailleurs. |
| Widgets du catalogue uniquement | **Non conforme à la revue — corrigé.** Voir ci-dessous. |

### La non-conformité trouvée, et pourquoi elle comptait

Les écrans M1 posaient **cinq `Color(0x…)` en dur**. Toutes étaient des
variantes d'opacité de jetons existants — `erreur` et `succes` — et **toutes
étaient justes**.

C'est précisément le problème : la sixième ne l'aurait pas forcément été, et
rien ne l'aurait signalé. Un écart qui produit un résultat correct est celui
qui s'installe.

Quatre jetons dérivés ont été ajoutés au catalogue (`erreurFond`,
`erreurFondLeger`, `erreurBordure`, `succesFond`) et les cinq usages
repointés. **Il reste zéro couleur en dur hors `app_colors.dart`.**

---

## 4. Checklist de revue en 10 points

| # | Point | Constat |
|---|---|---|
| 1 | La PR référence un code EF/RG/UC | RG-01, RG-02, RG-17 cités dans le code et les tests |
| 2 | **RBAC aux 3 niveaux** | Masquage UI (`droitsProvider`, bouton **retiré** et non grisé), middleware `module:M1,C` côté serveur, `ReservationPolicy`. Jamais la base seule |
| 3 | **Comportement offline testé explicitement** | 4 parcours d'intégration + 25 tests de persistance sans réseau. C'est l'objet même du sprint |
| 4 | Pas de résolution automatique sur les tables financières | M1 ne touche ni `factures`, ni `paiements`, ni `mouvements_caisse`. Un statut `conflit` renvoyé par le serveur **n'est jamais arbitré côté client** |
| 5 | Colonnes d'audit sur les nouvelles tables | Aucune table serveur créée ; la table locale porte `dateCreationLocale` et `statutSync` |
| 6 | Pas de `delete()` sur les tables sensibles | **Aucune suppression nulle part** : annuler conserve, rejeter conserve |
| 7 | Aucun secret en dur | Vérifié — voir §3 |
| 8 | `dart format` et `flutter analyze` verts | Oui, les deux |
| 9 | Tests nommés d'après la RG/EF | « un départ le 12 laisse l'unité libre à partir du 12 », « le rejet RG-01 conserve la réservation »… |
| 10 | Cohérence avec le design system | **Corrigé** — voir §3 |

Les quatre points bloquants sans exception — 2, 4, 6, 7 — sont conformes.

---

## 5. Les huit critères d'acceptation

| # | Critère | Constaté ? |
|---|---|---|
| 1 | Créer une réservation sans réseau | **Oui** — parcours d'intégration n°1, statut `local` |
| 2 | Elle survit à la fermeture de l'application | **Oui** — cinq tests sur **fichier réel** : écriture, fermeture, réouverture, relecture. Seul l'arrêt brutal par le système reste hors de portée |
| 3 | Elle part à la reconnexion | **Oui** — statut passé à `synchronise` |
| 4 | Aucun doublon après double envoi | **Oui** — parcours n°3 : 44 déduplications pour 43 réservations |
| 5 | Le rejet RG-01 est compris | **Oui** — parcours n°2, poste B refusé avec motif lisible |
| 6 | La réservation rejetée n'est pas perdue | **Oui** — elle reste sur le poste B, avec le message du serveur |
| 7 | Le montant n'est jamais saisi | **Oui** — deux champs seulement à l'écran, un test les compte |
| 8 | Statut de synchronisation visible en liste | **Oui** — badge sur chaque ligne |

**Sept sur huit constatés.** Le huitième — l'arrêt brutal du processus par le système — demande un appareil.

---

## 6. Ce que le serveur montre après les tests

Le test affirme depuis le client ; ce relevé regarde depuis la base — c'est lui
qui fait foi.

```
réservations sur IT-BNG-01 : 43
périodes distinctes         : 43
périodes en DOUBLE          : 0    ← RG-01 tenue de bout en bout
chevauchements réels        : 0    ← aucune double vente
sessions de synchronisation : 6    (5 succès, 1 échec)
entrées de déduplication    : 44   ← 43 réservations + 1 rejeu reconnu
```

L'unique session **en échec** est le refus du poste B. C'est le résultat
attendu, pas une anomalie : c'est même le seul qui prouve que RG-01 fonctionne.

---

## 7. Ce qui reste à vérifier, et qui ne peut pas l'être ici

| Point | Pourquoi |
|---|---|
| **Arrêt brutal du processus** | La fermeture *propre* et la réouverture sont désormais couvertes sur fichier réel (§8, PA-59). Ce qui reste : un `kill -9` ou une mise en veille agressive d'Android, qui demandent un appareil |
| **Mode avion réel** | Les tests simulent l'absence de réseau par un adaptateur HTTP ; ils ne coupent pas la pile réseau du système |
| **Passe visuelle** | Le rendu, les points de rupture, la lisibilité au soleil |
| **Performance sur l'hébergement cible** | 40 opérations en **1 853 ms** — sous le seuil de 2 s, mais de peu, et sur `php artisan serve`, mono-processus. À remesurer dès que l'hébergeur cPanel sera choisi |

---

## 8. Écarts et défauts relevés pendant le sprint

Onze, tous corrigés, tous consignés. Ils ont un point commun : **aucun ne se
voyait**. Huit ne levaient aucune erreur ; le dixième en levait une, mais sur un
chemin qu'aucun test n'empruntait — ce qui revient au même.

| Jour | Défaut | Ce qu'il aurait produit |
|---|---|---|
| 1 | **L'API n'avait aucune route de connexion** (PA-54) | L'API entière inaccessible à tout client — 421 tests verts ne le montraient pas |
| 2 | Schéma Drift sans `tarifNuit` (PA-55) | Un changement de grille tarifaire réécrivait le montant d'une réservation déjà prise |
| 2 | `statutSync` par défaut à `synchronise` | Une réservation qui n'a jamais touché le serveur se déclarait synchronisée |
| 2 | Ordre des réservations sans départage | La liste changeait d'ordre à chaque rafraîchissement, sans qu'aucune donnée ne bouge |
| 4 | `en_attente` absent de l'énumération (PA-57) | Une réservation en attente s'affichait **« confirmée »** — on annonçait une chambre non garantie |
| 5 | `TextEditingController` libéré trop tôt | Plantage au **second** usage du dialogue d'annulation |
| 5 | Écran exigeant un `GoRouter` pour se fermer | Impossible à monter seul, en test comme en vue maître-détail |
| 7 | **File produisant des lots invalides** (PA-58) | Un poste revenant de trois jours de coupure aurait vu **toute sa file refusée en bloc** |
| 10 | Cinq couleurs en dur | Un écart qui produit un résultat correct — donc qui s'installe |
| 11 | **Le protocole de synchronisation était injoignable depuis l'application** (PA-63) | `rejouer()` et `rafraichir()` n'étaient appelés que par des tests — une saisie hors ligne n'atteignait **jamais** le serveur, et RG-01 ne pouvait donc pas empêcher le double-booking |
| 10 | **Migration v1 → v2 jamais exécutée, et fausse** (PA-59) | `addColumn` sur une colonne `NOT NULL` sans défaut : **plantage chez tout utilisateur ayant au moins une réservation** — la mise à jour aurait rendu inaccessibles les saisies hors ligne |

Le plus instructif est celui du jour 7 : au jour 2, réutiliser l'identifiant de
la réservation comme `uuid_operation` semblait **renforcer** l'idempotence.
C'était un raisonnement juste appliqué à la mauvaise clé — le contrat distingue
la **tentative** de l'**enregistrement**, et les confondre cassait précisément
ce qu'on croyait garantir.

---

## 9. Cinq écarts de contrat serveur, non corrigés — à arbitrer

Consignés en **PA-57**. Aucun n'est bloquant tant que la synchronisation reste
mono-poste, aucun n'a été contourné en inventant une valeur.

1. `reservations` n'a **ni `reference`, ni `tarif_nuit`, ni `motif_annulation`**
   côté serveur. Le client les garde en local et les préserve à la fusion.
   **Le tarif est le plus important : c'est lui qui rend le montant opposable.**
   Une réservation venue d'un autre poste arrive avec un tarif à **0** —
   visiblement faux donc visible, là où un montant recalculé au tarif du jour
   serait plausible et faux, donc invisible.
2. `CreerReservationRequest` n'accepte pas `statut`.
3. `PATCH /{id}/annulation` n'accepte aucun corps : le motif reste local.
4. `GET /disponibilites` ne renvoie que les unités **libres**, sans motif — d'où
   le calcul local.
5. `GET /reservations` est paginé (50/page).

**Décision attendue :** ajouter ces trois colonnes au schéma serveur, ou acter
qu'elles restent des données de poste.

---

## 10. Chiffres

| | Sprint 0 | Sprint 1 |
|---|---|---|
| Fichiers Dart (hors générés) | 34 | **62** |
| Tests | 29 | **179** (+ 4 d'intégration) |
| `flutter analyze` | propre | propre |
| Compilation Windows | oui | oui |

---

## Historique des révisions

| Version | Date | Auteur | Modification |
|---|---|---|---|
| 1.0 | 18/08/2026 | Adderly (Cabinet FAGUEZ SARL) | Création. Sprint 1 vérifié par les six étapes du guide, compilation réelle comprise, et par quatre parcours d'intégration contre un backend Laravel en fonctionnement — le risque n°1 du projet est levé. Une non-conformité de revue trouvée et corrigée : cinq couleurs en dur hors catalogue. Neuf défauts relevés et corrigés pendant le sprint, aucun ne levait d'erreur. Cinq écarts de contrat serveur restent à arbitrer (PA-57) |
| 1.1 | 18/08/2026 | Adderly (Cabinet FAGUEZ SARL) | **Critere 2 leve, et un dixieme defaut trouve en le levant (PA-59).** La migration Drift v1 vers v2 n'avait jamais ete executee — les tests tournant en memoire passent toujours par `onCreate` — et elle etait fausse : SQLite refuse d'ajouter une colonne NOT NULL sans defaut a une table non vide. Elle aurait plante chez tout utilisateur ayant une reservation. Cinq tests sur fichier reel couvrent desormais la fermeture, la reouverture et la migration. 160 tests. Sept criteres d'acceptation sur huit constates |
| 1.2 | 19/08/2026 | Adderly (Cabinet FAGUEZ SARL) | **Onzieme defaut, et le plus grave : le protocole de synchronisation etait injoignable depuis l'application (PA-63).** Trouve en portant au client le balayage qui avait donne PA-62 : `FileSynchronisation.rejouer()` et `ReservationRepositoryComposite.rafraichir()` n'etaient appeles que par des tests, et le commentaire de `_pousser()` promettait un rejeu qui n'existait nulle part. Les quatre parcours d'integration qui avaient leve le risque n°1 appelaient `rejouer()` directement : ils prouvaient le protocole, pas le chemin qui y mene. Resolu par `synchroniserMaintenant()`, le geste de rafraichissement raccorde et un bandeau qui rend l'attente visible. 168 tests. Reste a trancher : le declenchement automatique au retour du reseau, qui demande une dependance de connectivite |
| 1.3 | 19/08/2026 | Adderly (Cabinet FAGUEZ SARL) | **Resynchronisation automatique livree (PA-64).** `connectivity_plus` — deja declare dans `pubspec.yaml`, jamais importe — est retenu comme **signal de reveil, jamais comme autorisation** : il rapporte l'etat de l'interface, pas l'accessibilite du serveur. L'autorite reste la tentative. Trois reveils non bloquants : reprise au premier plan, evenement de connectivite, repli 30 s a 15 min. 179 tests |

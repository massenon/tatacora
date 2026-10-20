# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Client Flutter TATACORA — guide de travail

Ce fichier ne répète pas le `CLAUDE.md` de la racine : lisez-le d'abord, il porte
le contexte projet, les six règles sans exception et l'état des 14 modules. Ici,
seulement ce qui est propre au client Flutter.

## Commandes

```bash
flutter pub get
flutter run -d windows                     # le poste cible du Gîte
flutter analyze                            # `warning` est BLOQUANT, pas seulement `error`
dart format .                              # avant toute livraison
flutter test                               # 2 953 tests + 24 ignorés (mesuré le 12/10/2026), ~6 min : les scripts PHP sur tatacora_test sont SÉRIALISÉS (verrou de fichier, D279)
flutter test test/features/pos/salle_test.dart          # un fichier
flutter test --plain-name 'un chevauchement est refusé' # un cas, par son nom

# Après TOUTE modification d'une table Drift, d'un `@DriftAccessor` ou d'un `part`
dart run build_runner build --delete-conflicting-outputs

# Les tests d'intégration tournent sur la VRAIE fenêtre Windows, pas en VM Dart
flutter test -d windows integration_test/socle_desktop_test.dart
```

Un test d'intégration **s'ignore lui-même** sans la variable `TATACORA_FIXTURE` :
c'est le seul mécanisme de filtrage, `dart_test.yaml` ne fait que déclarer le tag.

**Un fichier verrouillé** (`Flutter failed to delete … sqlite3.dll`) veut dire
qu'un `flutter_tester` d'une exécution précédente tourne encore. Le tuer, puis
relancer.

## Ce que ce client est

Une application **offline-first**, sur un poste de comptoir à Natitingou, dont la
connexion tombe. Trois conséquences qui commandent toute l'architecture :

1. **Toutes les lectures viennent de la base locale Drift.** Le poste est zéro
   réseau : rien ne rafraîchit depuis un serveur. Aucun écran n'a de branche « si connecté ».
2. **L'UUID naît côté client**, à la création de l'objet, jamais à l'envoi :
   c'est lui qui rend le rejeu idempotent quand le réseau coupe entre le
   traitement serveur et la réponse.
3. **La donnée non synchronisée est la seule copie qui existe.** Une migration
   qui recrée une table, un panier perdu à la fermeture de la fenêtre, une file
   qui ne repart jamais : ce sont les trois défauts déjà rencontrés ici.

## Les quatorze pièges de ce dépôt, tous rencontrés pour de vrai

**1. Un indicateur qui affirme un état qu'il n'a pas vérifié.** PA-59/60/61 :
une migration jamais exécutée, une sauvegarde de 802 octets au nom conforme, un
badge « certifié » pendant que tout partait en démonstration. Avant d'écrire
qu'une chose *va* se produire, cherchez l'appelant. **Un commentaire qui décrit
un déclencheur n'est pas un déclencheur** (PA-63 : les deux moitiés du protocole
offline-first n'étaient appelées que par des tests).

**2. `onUpgrade` n'est jamais emprunté par un test en mémoire.** `onCreate`
tourne à chaque test, `onUpgrade` jamais — et c'est pourtant lui, le chemin de la
mise à jour. Toute migration se prouve sur un **fichier réel portant des
données**, y compris en sautant des versions (le poste qui a raté une livraison).

**3. Le piège de `createTable`, rencontré deux fois.** `m.createTable` crée la
définition **courante** de la table : un poste ancien reçoit donc des colonnes
qu'une migration ultérieure voudra ajouter, et l'`addColumn` échoue sur
« duplicate column name ». Côté test, le même piège à l'envers : une fixture
« v3 » fabriquée depuis le schéma courant n'imite pas une v3. Les retraits sont
centralisés dans **`test/core/database/retour_arriere_schema.dart`** — ajouter
une version au schéma, c'est ajouter son entrée là, et rien d'autre.

**4. Un caractère de contrôle invisible vide une garde.** ⚠ **Vu naître le
26/08/2026** (PA-141) : le shell de cet environnement **collapse les antislashs
doublés**, si bien qu'un `\b` de regex écrit par heredoc devient l'octet 0x08.
C'est la troisième occurrence documentée. Après tout heredoc, balayez les octets. Un `\b` écrit par un
script devient l'octet 0x08 et le motif ne correspond plus à rien : le test passe
**à vide**. `test/core/qualite/caracteres_de_controle_test.dart` relit chaque
fichier octet par octet et porte un **plancher de fichiers**, sans quoi un dossier
renommé rendrait le balayage vide, donc vert. Ne jamais écrire un fichier source
par heredoc sans revérifier ses antislashs.

**5. Un test qui n'emprunte pas le chemin ne protège pas le chemin.** Éprouvé le
25/08/2026 : une mutation retirant la fiche de `Reservation.copyWith` laissait la
suite verte, parce que le test passait par `majStatutSync`, qui écrit en SQL
direct. **Mutez ce que vous venez d'écrire** — c'est la seule preuve qu'une
assertion n'est pas vide.

**6. Un défaut de SÉQUENCE de rendu ne se voit pas à la relecture.** Deux fois
en une journée : des boutons calculés avant la donnée qui les active seraient
restés grisés pour toujours (PA-111), et un catalogue demandé avant le
pré-remplissage était calculé sur la période par défaut — une chambre déjà
prise se serait présentée libre (PA-115). Dans les deux cas, tout le reste de
l'écran était juste. Quand un rendu dépend d'un état posé pendant ce même
rendu, demandez-vous dans quel ordre les deux ont lieu.

**7. Une borne ne se teste que sur un contenu plus grand qu'elle.** Retirer
le `maxHeight` d'une modale n'a fait rougir aucun test : celui qui la mesurait
montait une fiche courte. Il a fallu la remplir jusqu'à déborder. Même
famille que le piège 5 — l'assertion existait, elle n'atteignait rien.

Corollaire éprouvé le 25/08/2026 (PA-123) : une mutation qui ne mord pas
accuse parfois le **cas**, pas le code. Remplacer `any` par `every` dans le
filtre d'activité laissait la suite verte — la facture d'essai ne portait
qu'une activité, où les deux disent la même chose.

**11. Une table répliquée a DEUX moitiés : qui l'écrit, qui la descend.**
Les clients montaient depuis PA-116 et ne descendaient pas (PA-127). Comme
`reservations_local.client_id` est une vraie clé étrangère, la première
réservation d'un autre poste violait la contrainte et l'exception emportait
**tout le lot** d'alignement. 726 tests étaient verts. Le défaut n'existe
qu'à deux postes — c'est-à-dire dans le cas normal.

La même question posée à l'autre clé étrangère a donné PA-128 : le **parc**
n'était écrit par personne, et un poste neuf ne pouvait prendre aucune
réservation. Et une troisième fois (PA-129) : **aucun catalogue vendable**
n'était écrit — le point de vente n'avait rien à vendre. Posez-la à **chaque**
table que vous lisez.

**12. Un prédicat dérivé du champ qu'il vérifie ne vérifie RIEN.** `aUnEcran`
se définit par `route != null` ; le test « une destination sans écran n'annonce
aucune route » comparait donc le champ à lui-même (PA-133). Il n'a jamais pu
échouer, et trois écrans livrés sont restés inatteignables par un clic. Quand un
test porte sur une cohérence, ancrez-le sur une source **extérieure** — ici le
routeur, relu dans son code source.

**9. Une colonne qui existe au schéma n'est pas une valeur qui est écrite.**
`clients_local.solde` vaut zéro pour tout le monde : aucune ligne de code ne
l'alimente (PA-126). L'afficher aurait donné un zéro plausible sur la fiche
d'un débiteur. Avant de lire une colonne, cherchez qui l'écrit — et si
personne ne l'écrit, calculez, ou refusez d'afficher.

**10. Une `DataRow.key` n'atteint pas l'arbre de widgets.** Rencontré deux
fois. `find.byKey` ne la trouve jamais : posez la clé sur un widget d'une
cellule. Une clé introuvable est une clé qui ment.

**8. Un commentaire qui affirme une garantie n'est pas une garantie.** Le
graphique du tableau de bord portait « l'axe part de ZÉRO, toujours — c'est le
trucage le plus courant » ; tronquer l'axe ne faisait rougir aucun test
(PA-122). Quand vous écrivez qu'une propriété est tenue, cherchez le cas qui
la tient — ou écrivez-le.

**13. Une phrase de la vue sur de l'argent se vérifie en EXÉCUTANT le serveur,
et se remplace quand elle ment.** Trois phrases de l'écran Approvisionnement
disaient que la réception « a recalculé le coût moyen pondéré » ; le serveur,
exécuté, n'y touche pas (D265). Décision du Lead (D276) : un poste n'affiche pas
une affirmation fausse sur de l'argent — la règle d'honnêteté prévaut sur la
fidélité littérale à la vue. On met la phrase VRAIE, avec le maximum des mots de
la vue ; l'écart est NOMMÉ au code (fichier de la vue, ce qu'elle dit, pourquoi
on s'en écarte) ; un test épingle la fausseté à la source (il rougit le jour où
la vue est corrigée) et un autre refuse la phrase fausse dans le code RENDU ;
l'Architecte est saisi. Corollaire de mesure : écrire le chemin
`pwa/….blade.php` dans un commentaire fait du fichier un PORTEUR de la vue —
l'écart commenté avait fait baisser la dette (« Point de stockage ») sans qu'un
pixel change. Écrire « la vue d'approvisionnement ».

**14. Un lecteur câblé n'est pas un lecteur DÉCLARÉ, et une sonde qui s'exclut
ne voit rien.** `activation_suppression` était lue (règle d'archivage des
fournisseurs) pendant que Paramètres affichait encore « Aucun module de ce poste
ne lit encore cette valeur » : l'entrée du registre n'avait pas de `lecteur`
(D278). Le test censé le détecter excluait tout `features/parametres/` — là où
vivait le lecteur. Une sonde n'écarte que les fichiers qui DÉFINISSENT les clés,
et se prouve par mutation (retirer le lecteur doit rougir). Même famille :
l'aide du serveur (« tous les modules ») sur-promet quand un seul module lit ;
l'aide, confrontée à la vue, ne se touche pas — l'écart se dit en ligne par la
`correction` (« Sur ce poste : … »).

## Le maître de mise en page est la VUE BLADE de la PWA — et elle seule

**Décisions du Product Owner du 10/09/2026 (PA-182, PA-183).** Le client
Flutter se conforme à la **vue Blade** de la PWA — `tatacora-api/resources/views/pwa/`,
les classes `app/Pwa/` et les libellés `lang/fr/` — écran par écran, onglet par
onglet, aux mêmes emplacements. Elle porte la dernière version de chaque écran,
écarts datés du Product Owner compris (bouton « Vente », pastille « Réseau »,
Journal d'Audit au menu de compte, bascule plein écran, recherche globale,
masquage `gerant`, style d'onglets unique `Onglets.php`). **`prototype_v2/`
est une ANCIENNE version** : ne vous y référez plus, même pour départager.
`docs/DOCTRINE_PORTAGE_FIDELE_FLUTTER.md` et `docs/DIRECTIVE_CONFORMITE_100.md`
Article 0, à lire avant tout écran. Le code Flutter est une **traduction**, pas
une réinterprétation. Trois règles :

- **Quand la spécification écrite et la vue Blade se contredisent sur ce qui se
  voit, la vue gagne.** ⚠ Jusqu'au 10/09/2026, ce fichier disait l'inverse
  (« Une vue Blade ne fait jamais foi ») et faisait de `prototype_v2/` le
  maître : ne rétablissez ni l'un ni l'autre. Les citations
  `prototype_v2/pages/…` et les jetons `maitre-refuse:` qui subsistent dans le
  code sont l'HISTORIQUE de décisions passées, pas une référence.
- **Aucune valeur en dur dans un widget.** Couleurs, tailles, espacements et
  largeurs vivent dans `lib/core/theme/`. **Mesurez sur la vue et sur la
  feuille de style que sert la PWA**, ne supposez pas : la plupart des tailles
  de police sont des valeurs entre crochets (`text-[13px]`), pas l'échelle
  nommée de Tailwind.
- **Tout écart se documente dans le code** : fichier et ligne de la **vue
  Blade**, ce qu'elle fait, pourquoi on s'en écarte.

**La garde tourne avec `flutter test`** : `test/core/qualite/conformite_blade_test.dart` lance `tool/conformite_blade/t-blade-flutter.js`. Node et PHP sont requis — sans eux le test ÉCHOUE, il ne saute pas. Le comparateur résout les clés de langue par PHP, puis confronte le titre, les onglets, les libellés de chaque bloc, les modales et le châssis de chaque vue au code Flutter. **Un écran cite sa vue** — `// Vue Blade maîtresse (PA-183) : pwa/<module>/<vue>.blade.php` — et c'est le SEUL ancrage : un écran qui ne la cite pas n'est pas mesuré, et un `ecran_*.dart` sans vue est signalé comme ajout. Ce qu'on ne rend pas se **nomme avec les mots de la vue** ; un bloc entier refusé se déclare par `blade-refuse:<vue>#<bloc>` ; un écran dont les libellés viennent de l'API déclare `libelles-du-serveur:<vue>`. La dette de départ est figée dans `tool/conformite_blade/dette-blade-flutter.json` et ne peut que décroître : un progrès non resserré (`--figer-dette`) fait aussi échouer.

**Cette garde a été verte À VIDE sur les deux cartes jusqu'au 11/09/2026 (PA-187).** Un commentaire PHP `//` dans les arguments d'un `@include` portait une apostrophe (« qu'elle ») ; le comparateur la prenait pour un guillemet, ne dépliait pas `pwa.carte.corps`, et sept modales des cartes bar et restaurant n'étaient jamais mesurées. Deux leçons. (1) **Un chiffre de dette bas n'est pas une preuve de conformité** : quand une vue affiche peu d'absents, vérifiez que ses modales sont comptées (colonne MODALES à `0/0` sur une vue qui en a = suspect). (2) **Citer `pwa/…blade.php` dans un fichier Flutter en fait un PORTEUR de cette vue** : dans un écran signalé comme ajout, une simple mention en commentaire efface le signalement. Écrivez le chemin sans son préfixe quand vous ne portez pas la vue. (3) **La correspondance se fait par SOUS-CHAÎNE** (PA-189) : l'en-tête « Nouveau » d'une modale non portée est compté présent parce que « Nouveau prix de vente (FCFA) » existe ailleurs dans le code. Un libellé court peut faire baisser la dette d'un bloc que personne n'a porté — une baisse inattendue se vérifie avant d'être figée. (4) **Depuis PA-196, titre, onglets et blocs de page se cherchent dans le CODE QUE L'ÉCRAN ATTEINT** — ses porteurs et tout ce qu'ils importent, transitivement — et non plus dans tout `lib/` : quatre faux positifs en une journée venaient d'un fichier sans rapport avec l'écran. Conséquence pratique : **un widget qui rend un libellé doit être IMPORTÉ par l'écran** (directement ou non) pour compter ; un texte posé dans un fichier que l'écran n'atteint pas ne satisfait plus rien. La sous-chaîne, elle, demeure à l'intérieur de ce périmètre (« Magasin » ⊂ « Magasinier »).

**Le maître écrit l'apostrophe DROITE** — 581 fois contre 39 typographiques. C'est aussi la sûre : les polices intégrées des PDF ne couvrent pas U+2019, qui disparaît du papier sans rien signaler.

**Le maître distingue le PLURIEL du SINGULIER**, et ce n'est pas une négligence : une option de filtre désigne un ENSEMBLE (« Terminées »), un badge qualifie UN objet (« Terminée »). Un champ unique servant aux deux met le singulier dans une liste déroulante.

**Une garde peut aussi relire le SERVEUR** : `conformite_stocks_test.dart`
extrait `CHAMPS_CALCULES` et les types saisissables des `FormRequest` PHP
(PA-136). Une liste recopiée côté Dart ne vérifierait qu'elle-même et resterait
verte le jour où l'API changerait. Prouvez l'extraction **non vide**, sinon le
balayage est vert à vide.

**Les gardes de conformité relisent le maître, elles ne figent pas de
constantes** — `vocabulaire_pos_test.dart`, `conformite_reservation_test.dart`.
Un test qui figerait `'Encaisser'` ne vérifierait que lui-même et resterait vert
le jour où le maître change. Ces tests **échouent** si le prototype est
introuvable ; ils ne sautent pas.

État mesuré du portage : `docs/AUDIT_CONFORMITE_ECRANS_FLUTTER.md`.

## Architecture

```
lib/core/{config,database,dev,di,format,impression,navigation,rbac,responsive,router,theme}
# sync/ et network/ n'existent plus depuis « zéro réseau » (v10) : ne pas les recréer
lib/features/<module>/{domain,data,presentation}
    achats(M7) auth bar(M5) caisse comptabilite(M10) crm(M3) depenses etats(M14)
    facturation(M2) hebergement(M1) notifications(M12) parametres pos restaurant(M4)
    rh(M13) stocks(M6) tableau_de_bord(M11) tourisme(M9) vehicules(M8) ventes
```

- **Riverpod exclusivement**, providers déclarés à la main : `riverpod_generator`
  est retiré (incompatible avec `drift_dev` sur `analyzer`).
- **Un `Repository` n'expose jamais un modèle Drift ni un DTO à
  `presentation/`** — toujours une entité de domaine, sans quoi renommer une
  colonne casse un widget et la bascule offline/online cesse d'être invisible.
- Un DAO ne rend que des entités. Le contrat de dépôt ne dit **pas** d'où vient
  la donnée : c'est ce qui interdit les branches « si connecté » dans les écrans.
- (Historique : `rafraichir()` et `alignementProvider` ont disparu avec « zéro
  réseau » ; vérifié le 12/10/2026.)

## Encaissement de facture LOCAL (12/10/2026, D227–D237)

`PaiementsFactureDao` est le seul écrivain de `paiements_facture_local` : paiement et pièce (Dr trésorerie / Cr 4111) dans UNE transaction, pièce refusée = rien écrit ; reste dû = TTC − avoirs − paiements actifs − acomptes liés (`creances.dart`, une seule formule) ; balance âgée ancrée sur la date d'émission. Le comptoir écrit `session_encaissement_id` à la clôture d'un panier au comptant (refus sans caisse `bar` ouverte) ; le théorique de clôture est calculé comme le serveur (il ignore les recouvrements en espèces : incohérence D230 répliquée). D237-1 est FERMÉ par le lot 6 (ci-dessous). Onze défauts du serveur répliqués, à remonter à l'Architecte (D233).

## Les mouvements d'argent du poste passent leur PIÈCE (lot 6, 12/10/2026, D238–D248)

`PanierDao.cloturer` (seul écrivain de `cloture`) passe la pièce `VTE` — un débit (trésorerie du mode, ou `4111` pour la note de chambre), un crédit par module (M4 `7061` / Restaurant, M5 `7011` / Bar), la TVA par module (`4432` / `4431`) — dans la même transaction ; `ReservationDao.creer` passe la pièce de l'acompte (Dr trésorerie / Cr `4191`, rien à crédit ou sans mode) ; `annulerAvecConditions` fixe taux, commission (sur le montant GLOBAL) et remboursement (plafonné à l'acompte, Dr `4191` / Cr `5711`) et écrit 8 colonnes (v19). Refus du serveur dans son ordre, rejoués par `tool/ventes/rejouer_ventes.php` et `tool/hebergement/rejouer_annulations.php`. Calculs en entiers (`DecimalBc`, `calcul_tva.dart`). Un DAO sans moteur LÈVE. Écarts du poste : mode absent refusé, prix figé à l'ajout, pas de numéro `V-`, séjour toujours sur la note de chambre, M8/M9 refusés. **NON portés** : sorties de stock de la vente (RG-05, D240), pièces rétroactives des ventes d'avant (D246), mode démo (écrit sans pièce). La clôture de caisse DIT les ventes en espèces sans session (R2). Piège : un fichier de messages qui porte les mots d'une modale doit citer la vue (sinon le comparateur ne les voit pas), et le rendu se prouve par un test ; un commentaire d'un fichier importé peut aussi fournir un libellé par sous-chaîne (gain de mesure, jamais revendiqué).

## Sessions de caisse LOCALES, réplique du serveur (12/10/2026, D219–D226)

Seul `SessionsCaisseDao` écrit `sessions_caisse_local` ; montants en centimes. Ouverture et clôture répliquent `PosComptant` (le serveur n'a pas de service), refus dans l'ordre du serveur, messages relus par PHP (`tool/caisse/rejouer_caisse.php` rejoue le vrai composant). **Aucune pièce comptable** : le serveur n'en passe aucune. Depuis le lot 5 (D231), le panier au comptant porte `session_encaissement_id` et `especesDeLaSessionProvider` rend les espèces de la session : la clôture calcule théorique et écart comme le serveur (D221–D223 dépassés), et DIT les ventes en espèces sans session (lot 6, R2). `sessionOuverteLaPlusRecente` est appelée en production depuis le lot 5 (encaissement de facture et tableau de bord : la caisse « la plus récente tous points confondus », comme le serveur). La trésorerie de caisse de M11 est calculée depuis le lot 5 (D234). Piège : un `abort(403)` rendu par le harnais Livewire est une exception, pas un statut.

## Base locale Drift — schéma **v21**, 53 tables ⚠ (titre historique : v29, 62 tables depuis le 18/10/2026) (v21 : colonne `fournisseurs_local.actif`, aucune table ; v20 : `reglements_fournisseur_local` ; v19 : huit colonnes d'annulation sur `reservations_local`, aucune table ; v18 : `paiements_facture_local` + colonne `paniers_local.session_encaissement_id` ; v17 : `sessions_caisse_local` ; v16 : deux colonnes `ecriture_id`/`ecriture_refus` sur `depenses_local`, aucune table ; v15 : six tables du moteur comptable M10 ; v14 : quatre tables du restaurant ; v11 : `parametres_systeme_local` ; v12 : sept colonnes de stock, aucune table neuve ; v13 : cinq tables d'achats)

Historique des versions dans `lib/core/database/app_database.dart`, chacune avec
sa raison : v2 fiche de réservation (`tarifNuit`, `reference`…), v3 panier,
v4 registre de facturation, v5 `utilisateurs_local` (authentification locale),
v6 tables de salle, v7 fiche du maître (canal, mode de paiement, remise),
v8 `lignes_reservation_local` (les cinq services d'une réservation), **v9 renommage
des tables du restaurant (préfixe « T » -> « R », PA-130) — une migration de
DONNÉES, la seule à ce jour : un libellé persisté ne change pas parce qu'on
change la constante qui l'a produit.**

**v10 (14/09/2026) — « zéro réseau », et c'est la SEULE migration DESTRUCTIVE du
dépôt.** `sync_queue` et `sync_conflict_local` sont retirées : sans serveur, une
file d'attente n'annoncerait qu'une attente sans fin (PA-59/60/61). Ses lignes
sont **irrécupérables**, et le retour arrière les recrée VIDES — c'est écrit dans
la fixture, pas découvert après coup. S'y ajoutent huit tables pour les quatre
modules d'exploitation portés en local pur (dépenses ×2, notifications ×2,
personnel & paie ×4) et `circuits_local.duree`. ⚠ L'ajout de colonne y est
**conditionnel** (`PRAGMA table_info`) : la fixture de retour arrière recrée
`circuits_local` depuis sa définition COURANTE, qui porte déjà `duree` — piège 3,
rencontré pour de vrai en écrivant cette version.

**Toute migration est additive.** Recréer une table effacerait les saisies hors
ligne. Et **on ne déduit pas de données** : la v8 ne fabrique aucune ligne pour
les réservations existantes, parce qu'elle vaudrait zéro franc sur celles reprises
de la v1 — plausible, donc invisible.

`app_database_test.dart` fige le **nombre de tables** délibérément : c'est ce qui
oblige à rouvrir le test le jour où une table entre au périmètre offline, et donc
à se demander si elle y a sa place. La taille de la base conditionne la durée de
la fenêtre hors ligne.

## File d'envoi (lot F1, 15/10/2026) — la synchronisation REVIENT, en tâche de fond

Décisions du PO des 14–15/10/2026 : « zéro réseau » devient une règle d'USAGE (le
poste marche des jours sans réseau), la synchronisation une tâche de fond qui ne
bloque jamais un geste (la clôture de caisse d'abord). Le poste pousse des
documents SOURCES, jamais une écriture (D246) ; il crée ET modifie son catalogue.

- **Schéma v26** : `operations_sync_local` (58 tables), seul auteur
  `OperationsSyncDao` (`features/synchronisation/`). `enfiler` LÈVE hors d'une
  transaction Drift : chaque écrivain l'appelle dans SA transaction. `seq`
  (AUTOINCREMENT) est l'ordre d'envoi ; le payload est FIGÉ au contrat du serveur
  (`domain/charges_synchronisation.dart`, conversions d'unités en tête).
- `TableSynchronisee` est relu du registre PHP par un test ; aucune table
  d'écritures ; une `modification` sur une table que le serveur ne modifie pas est
  refusée à l'enfilement.
- **Ancrage extérieur** : `tool/sync/valider_charge.php` pousse la file d'une
  journée complète au VRAI `SynchronisationService` sur `tatacora_test` (rollback)
  et relit les lignes écrites (`charges_contre_serveur_test.dart`).
- Ne partent PAS : la vente sur séjour (phase 2 serveur), les alignements
  descendants (`aligner*`), le cycle des unités, l'envoi/clôture d'une commande,
  le rattrapage d'une dépense, le stock d'ouverture, tout ce qui précède la v26.
  Le mode démo n'enfile rien (`AppDatabase.fileSynchronisationActive`).
- Depuis F2b, l'écran `/synchronisation` LIT la file (section F2b). Le
  moteur d'envoi existe depuis F2a. Piège rencontré : `m.createTable` ne crée PAS les
  index `@TableIndex`, et un `CREATE INDEX` nu échoue sur un fichier rabaissé.

## Moteur d'envoi et appairage (lot F2a, 15/10/2026)

- **Transport** : `package:http` (pur Dart, déjà transitif) derrière
  `TransportSynchronisation` (`data/transport_synchronisation.dart`) — rend une
  `IssueHttp` (`ReponseHttp` | `ServeurInjoignable`), ne lève jamais ; 20 s de
  connexion et de requête ; `Accept: application/json`, Bearer. Tests :
  `MockClient` ou `FauxTransport` (`test/features/synchronisation/support/`).
- **Appairage** (Paramètres → onglet « Synchronisation », Administrateurs
  seulement, `peutAdministrerComptes`) : `POST /login` avec `poste` = nom du
  poste nettoyé (`nettoyerNomPoste`) ; `poste_id`, `jeton_api`, `serveur`,
  `appaire_le`, `compte` (+ `appairage_refuse` posé par le moteur sur 401/403)
  dans `poste.json` À CÔTÉ de `smtp_mot_de_passe`, écrit en E/S SYNCHRONES via
  `poste.json.tmp` + renommage (une file de `Future` statique s'était bloquée
  entre deux tests : zone FakeAsync morte). Le mot de passe serveur n'est écrit
  nulle part ; les refus sont des phrases (`TextesAppairage`), jamais le corps.
- **`SyncManager.synchroniserMaintenant()`** (`data/sync_manager.dart`) : un
  futur partagé dans le processus + le bail de `reclamerLot` entre processus ;
  `libererBauxExpires` puis `reclamerLot(50)` → `POST /sync` → `marquerResultat`
  en boucle. Politique : injoignable/408/429/5xx = repli 30 s→2 min→5 min→15 min
  →1 h (ou `Retry-After`) et arrêt ; 401/403 = lot rendu INTACT
  (`rendreEnAttente`, la tentative ne compte pas), refus consigné, plus rien
  avant réappairage ou « Tester la connexion » réussi ; 422 = bissection (seule
  l'opération fautive est `rejete`, et une opération suivante du même élément
  encore réclamée est rendue puis BLOQUÉE) ; 413 = taille ÷ 2 ; autre 4xx =
  `rejete` + alerte. Démonstration (`synchronisationInterditeProvider`) et poste
  non appairé : aucune requête. File vide : aucun `POST` (depuis F2b, chaque passage
  descend le catalogue : un `GET /referentiels`, sur son propre repli).
- **Déclencheurs, chacun avec son appelant prouvé** : `main.dart` (après la
  première image) lit `synchronisationAutomatiqueProvider` (une fois + toutes
  les 5 min) ; `cloturerLaCaisse` appelle `declencheurSynchronisationProvider`
  sans l'attendre (un transport qui lève ou ne répond jamais ne change rien à
  la clôture) ; le bouton « Synchroniser maintenant » de l'onglet. Le dernier
  bilan : `dernierBilanSynchronisationProvider` (pour l'écran de F2b).
- **Bout en bout** : `synchronisation_serveur_reel_test.dart` démarre
  `php artisan serve --no-reload` sur `tatacora_test` (sans `--no-reload`,
  artisan RETIRE `DB_DATABASE` de l'environnement du serveur, qui relirait
  `.env` = la base de dev), tient le verrou de `tatacora_test` tout l'essai, et
  `tool/sync/serveur_reel.php` prend un instantané puis RESTAURE chaque table
  modifiée (le serveur écrit pour de bon). `HttpOverrides.global = null`.
- Production : `https://logirestock.digitonpro.com/api/v1`. Un appairage fait
  vers une autre adresse que celle du build rend `autreServeur`, rien ne part.

## Descente du catalogue et écran de synchronisation (lot F2b, 15/10/2026)

- **Schéma v27** (60 tables) : `etat_synchronisation_local` (clé/valeur :
  `descente.curseur`, repli propre `descente.echecs`/`prochaine_tentative`,
  bilan `descente.derniere`, éléments gardés `element_differe:<table>:<id>`,
  et `operation_remplacee:<uuid>` écrit par `OperationsSyncDao.renvoyer`) et
  `correspondances_sync_local` (table, id_serveur → id_local, origine
  `flux`|`file`|`libelle`). Aucune clé primaire locale n'est réécrite.
- **`DescenteCatalogue`** (`data/descente_catalogue.dart`), appelée par
  `SyncManager` APRÈS l'envoi, sauf 401/403 ; son PROPRE repli (une descente
  en échec ne retarde jamais un envoi, un envoi en échec n'empêche pas la
  descente). `GET /referentiels?poste_id&depuis&limite` page après page ;
  chaque page dans UNE transaction : correspondances, puis chaque élément dans
  un point de sauvegarde (une ligne fautive est comptée refusée, la page
  passe), puis le curseur — jamais avant. 422 = curseur oublié, reprise du
  début. Les `fusionne_avec` de la file sont retenus en correspondances avant
  chaque descente (le flux des correspondances n'arrive qu'en fin de
  catalogue).
- **`AligneurCatalogue`** : un écrivain par table, n'enfile JAMAIS (balayage
  du source + compte de la file). Ligne locale avec une opération
  `en_attente`/`en_cours`/`bloque` → CONSERVÉE, élément gardé ; repris quand
  plus rien n'attend : appliqué si le serveur a gardé sa version
  (`version_serveur_conservee`, rejet, fusion), oublié si la modification du
  poste a été appliquée (la nouvelle version redescend). Homonyme local
  (clé naturelle) non encore poussé → conservé (pas de doublon avant la
  fusion). Dépendance absente → gardé, repris en boucle en fin de descente et
  à la suivante. Conversions inverses de F1 par `entierDepuisDecimal` (chaîne,
  jamais `double`) ; une fraction de franc est REFUSÉE. Archives : fournisseur
  `actif`, unité `hors_service` (une unité existante ne reçoit que
  l'archivage, son statut reste celui du cycle local) ; un ARTICLE archivé
  reste (aucune archive locale), et le bilan le compte. Centres de coût :
  reconnus par id puis libellé normalisé, jamais renommés, créés seulement
  s'ils manquent. `cree_par` d'une création descendue = compte connecté, à
  défaut le plus ancien administrateur actif (écart nommé ; sans compte, la
  ligne attend).
- **Bail** : `SyncManager` le PROLONGE avant chaque `POST /sync`
  (`prolongerBail`) — une bissection longue n'est jamais reprise par un autre
  processus.
- **Écran `/synchronisation`** (`presentation/ecran_synchronisation.dart`,
  ajout du PO déclaré dans `classification-exemptions.json`, hors menu, gardé
  par Paramètres, lien depuis Paramètres → Synchronisation) : état, compteurs
  par statut, dernière descente, « À traiter » paginé (rejetées, conflits,
  bloquées ; « Renvoyer » = même document, même horodatage, NOUVEL uuid,
  l'ancienne reste rejetée et marquée remplacée, la remplaçante passe devant
  les bloquées ; « Débloquer » seulement quand les antérieures sont abouties ;
  les deux réservés aux Administrateurs ; conflit = « arbitrage sur le
  serveur »), signalements du serveur en français (registre relu de
  `AnomalieSynchronisation`). « Synchronisé » ne se dit que du confirmé.
- **Bout en bout** : `synchronisation_serveur_reel_test.dart` crée un
  catalogue AU SERVEUR (`serveur_reel.php creer_catalogue`), le descend, et
  rejoue le dernier écrit gagnant (`renommer`) contre une modification locale.

## Descente des clients et des réservations, bouton de la barre (lot F3, 16/10/2026)

Décision du PO du 16/10/2026 (« le poste B aura-t-il ce que le poste A a
enregistré ? ») : le flux `GET /referentiels` porte aussi `clients` puis
`reservations` (de TOUS les postes, filtrés par M3 / M1), après le parc et
les fournisseurs, avant les centres de coût. Les ventes, dépenses, caisses,
commandes et réceptions des autres postes NE descendent PAS (consultées au
serveur, seul comptable, D246).

- **Client** (`AligneurCatalogue._client`) : dernière saisie gagnante (une
  fiche en suspens est conservée), aucun contrôle d'homonyme (le serveur ne
  fusionne jamais deux clients), `solde` ne descend pas, un client archivé
  reste proposé (compté dans `archivesNonPortees`).
- **Réservation** (`_reservation`) : NOUVELLE → écrite sans pièce (le
  serveur a passé celle de l'acompte), référence `SRV-` + 8 caractères,
  tarif absent = 0 (précédent `ReservationDto`), aucune ligne de service,
  canal non descendu ; elle occupe la chambre pour `chevauchant` (RG-01).
  EXISTANTE → seul le STATUT bouge, et seulement vers l'avant
  (`en_attente` → `confirmee` → `en_cours` → `terminee`) ; annulée ici =
  intouchable ; annulée au serveur = annulée ici avec ses conditions, sans
  pièce. Dates, unité, montants d'une réservation existante ne sont PAS
  réécrits (écart nommé : le poste ne pousse que la création).
- **Bouton de la barre supérieure** (`presentation/bouton_synchronisation.dart`,
  AJOUT du PO, à gauche de la cloche) : voyant pur `voyantDe`
  (`domain/voyant_synchronisation.dart`) — gris / rouge (+ nombre à traiter
  ou jeton refusé) / orange (+ nombre en attente) / vert (RIEN en attente) ;
  les comptes sont relus au signal de tables de Drift (`surveillerFile` ; une requête `.watch()` laisse un minuteur que le banc refuse, et le bouton est sur TOUS les écrans), le badge
  suit une vente enfilée sans attendre le moteur. La modale : compteurs,
  dernier passage, dernière réception, « Synchroniser maintenant » (TOUS les
  comptes), « Voir le détail » seulement si `accesRoute('/synchronisation')`
  l'autorise. La pastille « Réseau » de la vue reste refusée.
- Piège rencontré : un faux serveur qui reprend APRÈS le curseur ne re-sert
  pas un élément « modifié » ; sans `effacerCurseur()` entre deux descentes,
  les cas « rien n'est réécrit » passaient À VIDE. Et la sonde des écrivains
  ne lisait pas `_db.into(t)` : l'aligneur y échappait jusqu'au F3 (déclaré
  exception nommée depuis).

## Documents de tous les postes, POS hébergés, factures (lots F4–F5, 17/10/2026)

Décisions du PO du 17/10/2026 (« NE PLUS LIMITER », Q1 = A, Q2 = A,
« F-AAAA-NNNNN au serveur ») : la section F3 ci-dessus est DÉPASSÉE sur un
point — ventes, dépenses, caisses, commandes, réceptions, règlements,
mouvements de stock, tourisme, séjours, factures, avoirs et encaissements de
TOUS les postes descendent (`aligneur_documents.dart`), schéma **v28**
(61 tables : `origines_documents_local`, le poste d'origine).

- **Q1** : un document descendu n'a JAMAIS de pièce locale (le journal du
  poste ne tient que ses pièces) ; le rattrapage d'une dépense descendue est
  refusé ; les entrées de stock de SA réception ne redescendent pas au poste
  qui les a écrites (`tablesMiroirs` au serveur).
- **Facture** : numéro PROVISOIRE `PROV-AAAA-NNNNN` sous synchronisation
  (l'ancien `F-` en démonstration), imprimé « FACTURE PROVISOIRE » ;
  émission et annulation s'enfilent (`factures`) ; le numéro du serveur est
  posé par `FactureDao.regulariserNumeros` — depuis la réponse de l'envoi
  (`SyncManager`) ET depuis la descente (réponse perdue). Les avoirs
  désignent leur facture par NUMÉRO (clé étrangère) : réécrits ensemble,
  contraintes différées. Une pièce d'avant (`non_transmissible`) ne part
  jamais ; si le serveur attribue son numéro à une autre, elle devient
  `LOC-<numéro>`.
- **Encaissement** : part (`paiements`, centimes, caisse du poste) si sa
  facture part ; au serveur, une facture non certifiée et une caisse
  inconnue sont ADMISES et signalées (l'argent est reçu). L'annulation d'un
  paiement régularisé retrouve la pièce passée sous le numéro provisoire
  par l'UUID du paiement (et dans ce seul cas : la parité serveur tient).
- **Lot F6 (17/10/2026)** : partent l'annulation d'une réservation (taux et
  MONTANT remboursé, mode `montant` : même somme au centime), son
  déplacement (chambre, dates, comparées au JOUR, depuis
  `ReservationDao.enregistrer`), l'envoi et la clôture d'une commande — et
  seulement si le serveur détient le document
  (`DocumentsAutresPostes.connuDuServeur` : descendu, ou création en file non
  rejetée). **Q3** : un document descendu (réservation, facture,
  encaissement) ne s'annule ici que par `administrateur`, `super_admin` ou
  `comptable` (`peutAnnuler`), comme au serveur. Les autres retouches d'une
  fiche de réservation restent locales ; le poste n'annule qu'un panier
  OUVERT (aucune annulation de vente ne part). Un document de CE poste
  annulé AU SERVEUR (vente, encaissement, règlement fournisseur) suit en
  statut ET sa pièce locale est contre-passée en entier, une seule fois
  (18/10/2026).

## Tous les modules, bouton « Synchroniser », cohérence (18/10/2026)

Décisions du PO du 18/10/2026 (« tous les modules » ; « le serveur doit
avoir aussi le bouton synchroniser » ; tables du restaurant « il faut le
créer »). Schéma **v29** (62 tables : `occupations_tables_local`).

- **Montent en plus** : tables de salle et additions ouvertes (une table
  occupée ailleurs se refuse, `TableOccupeeAilleurs`), véhicules et
  contrats (M8), employés et bulletins (M13 ; matricule et numéro du
  serveur régularisés), règlements fournisseur, mouvements de stock SAISIS
  (`StocksDao.ajouterMouvement`, `envoyer: false` pour l'entrée d'une
  réception), paramètres (UN enregistrement de l'écran = une opération,
  dernier écrit gagnant clé par clé), rôles (libellé + matrice entière),
  modèles de notification (couple événement × canal), canal d'une
  réservation (par son NOM). Tout descend aussi, aligné par clé naturelle ;
  une retouche locale en attente est gardée (`ConserveLocalement`).
- **Jamais** : comptes et mots de passe (PA-103), messages de notification
  tracés, pièces du serveur (Q1 = A). Non portés faute d'écran ou de table :
  congés, plannings, entretiens de véhicules, indisponibilités de la carte.
- **Bouton du serveur** : la PWA (menu de compte « Synchroniser les
  postes ») et l'écran du même nom ici (`/synchronisation-postes`, ouvert à
  tout compte) enregistrent une DEMANDE ; le poste la lit toutes les 30 s
  (`SyncManager.suivreDemandeDuServeur`, `GET /sync/demande`) et passe
  aussitôt (envoi puis descente, repli levé). Le flux reçoit `en_attente`.
- **Contrôle de cohérence (P1-1)** : écran de synchronisation, « Contrôler
  maintenant » — `GET /sync/coherence` (par table et par jour MÉTIER,
  nombre et total en centimes) contre les mêmes comptes locaux
  (`ControleCoherence.requetes`) ; « Ce poste a tout reçu jusqu'au … ».
- **Essai de réception** : `essai_cinq_postes_test.dart`, cinq postes contre
  le vrai serveur avec coupures au hasard (avant envoi, réponse perdue) :
  rien de perdu ni doublé, cohérence sans écart sur chaque poste, conflit
  RG-01 réel dans « À traiter ». ⚠ Le flux ne livre qu'au-delà de son
  HORIZON (5 s) ; un banc qui avance l'horloge du moteur doit la donner
  AUSSI au DAO de la file (l'échéance d'une reprise se juge sur elle).

## Configurations saisies à l'écran : mot de passe SMTP, appairage (19/10/2026)

Décision du PO du 19/10/2026 (« enregistrer les configurations dans le poste
et le web » ; serveur : « chiffré en base » ; poste : « onglet Email »).

- **Poste** : Paramètres → Email (SMTP), champ « Mot de passe SMTP »
  (`widgets/champ_mot_de_passe_smtp.dart`, Administrateurs seulement) →
  `EcrivainConfigurationPoste.enregistrerMotDePasseSmtp` / `effacer…` dans
  `poste.json` (+ `smtp_mot_de_passe_le`/`_par`), JAMAIS dans Drift ; l'écran
  ne relit que l'ÉTAT (`etatMotDePasseSmtp`). Écart nommé : la mention de la
  vue (« chiffré sur le serveur », repli `.env`) est fausse ici.
- **Serveur** : `secrets_configuration` (cast `encrypted`, `APP_KEY`), registre
  fermé `SecretsConfigurationService::CLES`, exclu de l'export, conservé par
  la réinitialisation, jamais dans le flux ; `ConfigurationMailService`
  l'applique avant `MAIL_PASSWORD`.
- **Révocation d'appairage** : « Synchroniser les postes » (PWA et poste),
  colonne « Appairage », bouton « Révoquer » (Administrateurs, jamais son
  propre poste) → `POST /sync/postes/{poste}/revocation` supprime les jetons
  de ce NOM ; le poste révoqué reçoit 401 et garde sa file.

## Essais en production, génération des données (19/10/2026)

Décision du PO du 19/10/2026 (« les essais en production suivis de la
réinitialisation, sur le web et le poste » ; procédure :
`docs/ESSAIS_EN_PRODUCTION_ET_REINITIALISATION.md`).

- **Serveur** : la réinitialisation « comme neuf » ouvre une GÉNÉRATION
  nouvelle (`generations_donnees`, conservée). Les routes `/sync`,
  `/sync/demande`, `/sync/coherence`, `/referentiels` donnent
  `X-Tatacora-Generation` (+ `X-Tatacora-Phase-Essais`) et REFUSENT (409,
  code `generation_perimee`) une `generation` rappelée qui n'est plus la
  courante. En Production, la réinitialisation n'existe que pendant la phase
  d'essais (`TATACORA_PHASE_ESSAIS=true` au `.env`).
- **Poste** : `DescenteCatalogueDao` retient la PREMIÈRE génération vue
  (`serveur.generation`) et la rappelle (corps du `POST /sync`, paramètre des
  `GET`) ; sur 409, le lot est rendu INTACT, `serveur.reinitialise_le` est
  consigné, plus aucune requête (`EtatSynchronisation.serveurReinitialise`,
  voyant rouge). `ReinitialisationLocale` s'ouvre alors même en build
  production et bascule fermée (rôle et « VIDER » exigés) ; elle vide
  `etat_synchronisation_local`, donc le poste réadopte la génération nouvelle.
- ⚠ Un poste d'une version antérieure ne connaît pas la génération : il doit
  être mis à jour AVANT la réinitialisation du serveur.

## Exploitation : cron et vérifications (19/10/2026)

`docs/LISTE_DES_CRON_JOBS_CPANEL.md` (une ligne cron `schedule:run`, test
`ListeCronDocumenteeTest` qui confronte le planning au document) ;
`php artisan tatacora:verifier-production` et
`docs/VERIFICATIONS_APRES_MISE_EN_PRODUCTION.md` (liste serveur + postes).

## Synchronisation — ⚠ HISTORIQUE, retirée par « zéro réseau »

⚠ **Vérifié le 12/10/2026 : `synchroniserMaintenant`, `DeclencheurSynchronisation`,
`dioProvider` et `dioEnLigneProvider` n'existent plus dans `lib/`** (seules
subsistent des mentions en commentaire). **Depuis le lot F2a (15/10/2026),
`synchroniserMaintenant` existe de nouveau** — dans `SyncManager`, voir la
section F2a ; depuis F2b il pousse la file PUIS descend le catalogue
(section F2b). La phrase « le poste ne pousse ni ne descend rien » est
périmée.
Cette section et les deux suivantes (« socle réseau », « écrans qui exigent le
réseau ») décrivent l'état d'avant ; elles sont gardées pour leurs leçons, pas
comme description du code.

`synchroniserMaintenant()` était le point d'entrée **unique** : pousser, aligner,
recharger, dans cet ordre. Le déclenchement automatique passe par
`DeclencheurSynchronisation` — trois réveils, aucun bloquant (retour au premier
plan, événement `connectivity_plus`, repli 30 s → 2 min → 5 min → 15 min).

**`connectivity_plus` est un signal de réveil, jamais une autorisation** : il
rapporte l'état de l'interface, pas l'accessibilité du serveur — au Gîte, un
routeur allumé au lien amont coupé annonce « connecté » pendant que rien ne
passe. L'autorité est la tentative (`BilanSynchronisation.reseauIndisponible`).
Le paquet n'apparaît **qu'au provider** ; ne l'introduisez pas dans
`DeclencheurSynchronisation`, qui doit rester testable sans canal de plateforme.

**Une valeur CALCULÉE par le serveur ne descend pas en base** : le stock est
lu en direct par l'écran Carte du bar, jamais stocké (PA-129) — figé, il
serait faux à la première vente. ⚠ **La carte lit `stock_vendable`, jamais
`stock_disponible`** (PA-199) : le second est le solde BRUT en unités de STOCK
(casiers), le premier le chiffre de la carte PWA en unités VENDABLES
(bouteilles) — pour un casier de 24, 2 contre 48. Les deux sortent du même
auteur serveur (`StockDeCarteService`) ; `stock_disponible` n'a gardé son sens
que pour ne rien casser chez un client qui le lirait. Et « injoignable » se distingue de « vide » :
un rayon qui rend `null` laisse le catalogue local intact.

**L'ordre de l'alignement descendant est contraint par les clés étrangères** :
parc (catégories puis unités, PA-128), clients (PA-127), réservations. Chaque
étage est la clé étrangère du suivant, et l'inverse rejoue la violation.
**Aucun alignement ne supprime** : une ligne retirée du serveur peut être
référencée par une saisie locale non encore poussée. Ce qui ne peut pas
s'écrire est **compté et affiché**, jamais avalé.

**Le référentiel client descend AVANT les réservations**
(PA-127) : `reservations_local.client_id` est une vraie clé étrangère, et
l'ordre inverse rejoue la violation. Ce qui ne peut toujours pas s'écrire est
**compté et affiché**, jamais avalé.

**Ce qui ne part PAS au serveur, et qu'aucun écran ne doit annoncer comme « en
attente » :** les paniers, les factures, et la fiche de réservation (canal, type
de client, mode de paiement, remise) — `TABLES_SYNCHRONISABLES` ne connaît que
`reservations` et `clients`. Les écrans disent « enregistré sur ce poste ».

## Authentification — locale, jamais par l'API

Décision du Product Owner (PA-103). `SessionRepositoryLocal` lit la table Drift
`utilisateurs_local`, et **un test relit son code source** pour qu'aucun `dio`,
`http`, `localhost` ni `/api/` n'y entre jamais.

- **Aucun mot de passe stocké** : un dérivé PBKDF2-HMAC-SHA256 seulement (sel
  aléatoire, 120 000 tours, comparaison à temps constant). **PBKDF2 est écrit à
  la main** — ne jamais y toucher sans rejouer les trois vecteurs publics de
  `verificateur_hors_ligne_test.dart`, dont `c=2`, seul à éprouver la boucle de
  chaînage.
- **Aucun mot de passe par défaut nulle part**, et il ne doit jamais en entrer :
  un poste vierge fait créer le compte administrateur.
- **Aucun message du serveur ne doit atteindre l'écran de connexion**, et un
  compte inconnu rend le même message qu'un mot de passe faux.
- Le RBAC vient de `droitsJson`, relu par la **même** fabrique
  `GardeAcces.depuisJson` que la voie serveur.

## M11 se lit sur le poste, indicateur par indicateur (10/10/2026, D157–D173)

M11 ne possède aucune table (schéma v14 inchangé) : il relit les modules
sources. Un indicateur n'est calculé que si TOUTES ses sources sont détenues ET
écrites ici : taux d'occupation, réservations en attente, valeur du stock
(« hors N article(s) sans coût »), employés actifs, ventilation du CA facturé.
CA encaissé, trésorerie de caisse et factures non soldées sont calculés depuis
le lot 5 (12/10/2026, D234 : `PaiementsFactureDao` écrit les paiements, formules
du serveur répliquées avec leurs incohérences D233). Dépenses cumulées et séries
mensuelles restent « — » avec leur raison datée. La fenêtre de temps (`FenetreTableauDeBord`) est calculée sur le
poste et confrontée au vrai `Periode` PHP
(`tool/tableau_de_bord/exporter_indicateurs.php`). Piège : une clé de
fournisseur `family` a besoin de `==`/`hashCode`. Pas de cache : un « — » vaut
mieux que le chiffre d'hier.

**Le pilotage consolidé reprend la BANDE (12/10/2026, D289–D295).** Les cartes
« Chiffre d'affaires encaissé » et « Trésorerie (caisse) », et les alertes
« À traiter » factures / réservations, sont les indicateurs M11 de
`TableauDeBordLocal`, transmis à l'onglet (`EcranPilotageConsolide(tableau:)`)
et mis en forme par `valeurIndicateurAffichee`, écran et PDF compris. Seul
« Résultat net » relève de M10 (`PilotageApi` → `SourceAbsente`, raison datée).
« Exercice entier » règle la période de tout l'écran ; la période personnalisée
n'est pas portée (dit à l'écran). La carte « Valeur du stock » lit encore M6, pas
l'indicateur de la bande (écart ouvert). Piège : un `DropdownButton` garde tous
ses libellés dans sa pile — `find.text` y trouve n'importe quelle option ; lire
`FormFieldState.value`.

## Le socle réseau — RÉPARÉ et PROUVÉ le 27/08/2026 (PA-154) — ⚠ HISTORIQUE (transports retirés, voir « Synchronisation »)

Deux défauts rendaient **tous** les écrans « en ligne » non fonctionnels contre un vrai
serveur. Les deux sont corrigés, et la réparation est prouvée contre un Laravel qui
tourne — c'était la seule preuve recevable, parce qu'**aucune suite ne pouvait voir ces
défauts** : les tests montent leur propre client HTTP.

**1. Deux transports, deux contrats — ne les confondez plus.**

| Provider | `validateStatus` | Pour qui |
|---|---|---|
| `dioProvider` | `statutAccepte` — les 4xx **ne lèvent pas** | Offline-first : `ReservationApi` (409 de conflit RG-01), `FileSynchronisation`, `ParcApi`, `ClientApi`, `CatalogueApi`. **Les cinq lisent `reponse.statusCode` explicitement.** |
| `dioEnLigneProvider` | `statutAccepteStrict` — tout sauf 2xx **lève** | Écrans en ligne : M5, M8 (Paramètres, M4, M6, M7, M11 et M14 sont locaux depuis le 09/10/2026). **Ces écrans ne lisent `statusCode` que dans `e.response`** — ils sont écrits comme si un 403 levait. |

Le défaut était de **câblage, pas de code client** : un seul `dioProvider` lenient servait
les deux contrats, si bien que la branche « refusé » des écrans en ligne était un chemin
que rien n'empruntait. Un droit manquant tombait dans « réponse illisible ».
⚠ **Avant de brancher un nouveau client, demandez-vous lequel des deux il attend.**

**2. Le jeton est pris À LA CONNEXION** (voie (a), tranchée par le Product Owner).
`SessionNotifier.connecter` appelle `acquerirJeton()` **en plus** de la connexion locale.

- **PA-103 ne change pas** : `SessionRepositoryLocal` décide seul qui entre, et le test qui
  relit son code source reste vert — l'acquisition vit dans `SessionRepositoryImpl`.
- **L'échec est silencieux et n'empêche jamais d'entrer.** Aucun message du serveur
  n'atteint l'écran de connexion.
- **Quatre états, pas trois** (`EtatJetonApi`) : le quatrième est celui du Gîte — un compte
  créé au premier démarrage **n'existe pas côté serveur** et n'aura jamais de jeton. Ce
  n'est ni une panne, ni un droit manquant.
- Le jeton ne vit qu'au **coffre sécurisé**, relu à chaque requête ; le mot de passe n'est
  ni stocké ni journalisé, et un test le vérifie.

**⚠ Le piège rencontré en écrivant la preuve, et qui vaut pour tout essai réseau :**
`TestWidgetsFlutterBinding` installe un `HttpOverrides` qui **rend 400 à toute requête sans
jamais l'émettre**. Un « essai contre un vrai serveur » écrit sous ce binding ne touche
aucun serveur — il mesure le bouchon du framework. `HttpOverrides.global = null` après
`ensureInitialized()`, sans quoi la preuve ne prouve rien.

```bash
php artisan serve --port=8123                       # depuis tatacora-api/
TATACORA_API=http://127.0.0.1:8123/api/v1 TATACORA_MDP='...' flutter test test/integration/socle_reseau_reel_test.dart --tags integration
```

Les comptes d'essai sont créés par l'opérateur, **jamais par un seeder** : un compte livré
avec le code est connu de quiconque lit le code.

## Les écrans qui exigent le réseau — ⚠ titre HISTORIQUE : le poste est zéro réseau ; la section décrit surtout les modules devenus LOCAUX

⚠ **Vérifié le 12/10/2026 : aucun écran n'exige plus le réseau.** Véhicules (M8,
`vehicule_dao.dart`) et le catalogue du bar (`boissons_api.dart`) lisent la base
locale, comme les autres. La leçon d'avant reste valable : une donnée que le poste
ne détient pas s'affiche « — » avec sa raison, jamais la dernière réponse en cache
ni un zéro.

**M14 est LOCAL depuis le 10/10/2026** (aucune table, schéma v14, D175–D187).
Registre fermé de 12 états relu du code PHP (`tool/etats/exporter_registre.php`) ;
catalogue filtré par le droit de lecture sur le module SOURCE (éditer l'état des
stocks exige M6, pas M14). L'aperçu de 10 états est calculé depuis les lecteurs
des modules sources (`apercus_etats.dart`, cellules au format du serveur).
Créances clients est calculé depuis le lot 5 (12/10/2026, D234). La balance
reste listée et refusée, avec la raison réécrite le 12/10/2026 (D282) :
comptabilité du poste partielle. Aucun export, archive ni PDF (PA-192 ouvert).
Ce que l'aperçu ne mesure pas est dit dans l'encadré « Sur ce poste », jamais un
zéro.

**L'écran Paramètres est LOCAL depuis le 09/10/2026** (Drift v11, table
`parametres_systeme_local`, décisions D104–D114 du ticket) : plus aucun appel
réseau. Son registre fermé de 31 clés est relu du serveur par un test (PHP
exécuté, `tool/parametres/exporter_registre.php`) ; une clé inconnue est refusée,
aucune valeur réglementaire n'est posée par défaut, aucun secret n'entre en base.
Seul `EnregistrerParametres` écrit ; les taux de paie passent par `PaieDao`. Les
badges (TVA, MECeF jamais « actif ») sont dérivés. Les valeurs saisies que
aucun module ne lit encore (en-tête des documents) le disent à l'écran :
`EnteteEtablissement` n'est pas encore branché (lot à part). Une clé lue par UN
seul module le dit aussi, en ligne : `activation_suppression` n'est honorée que
par les fournisseurs de M7 (D278, piège 14).

**M4 Restaurant est LOCAL depuis le 09/10/2026** (schéma v14, D144–D156). Seul
`RestaurantDao` écrit ; fiche et composition en une transaction. Portions, coût
matière et taux ne sont jamais stockés (rejoués du stock de M6, confrontés au
VRAI `CarteRestaurantService` par PHP). Un article journalier ne borne aucune
portion (écart serveur D146). Les ventes ne décrémentent pas ce stock (RG-05
non portée, D240) ; depuis le lot 6 la vente du rayon passe sa pièce `VTE`
(crédit `7061`, centre Restaurant, TVA `4432`). Catégorie du plat = type de son menu (D148 ouvert).

**M7 Achats est LOCAL depuis le 09/10/2026, complet depuis le lot 7 (12/10/2026,
D253–D281)** (schéma v13, puis v20 et v21). Trois écrivains, un par table :
`AchatsDao` (commandes, bons, entrées de stock de la réception, archivage du
fournisseur — `fournisseurs_local.actif`, v21), `ReglementsFournisseurDao`
(`reglements_fournisseur_local`, v20). **Le règlement et sa pièce (Dr 4011 /
Cr trésorerie du mode, au journal de ce mode) s'écrivent dans UNE transaction** ;
pièce refusée = rien d'écrit ; montant en centimes entiers, tronqué à deux
décimales comme `bcmath` ; reste dû = montant de la commande − règlements
ACTIFS ; refus dans l'ordre du serveur (commande, montant, trésorerie). Le DAO
sait annuler (contre-passation de la pièce ENTIÈRE), aucun écran ne l'offre : le
serveur n'a aucun appelant (D257). **La réception ne valorise PAS** : le serveur,
exécuté (`tool/achats/rejouer_receptions.php`), laisse le coût moyen pondéré et
le dernier prix d'achat inchangés ; l'entrée de stock naît SANS coût, un article
qui n'entre que par réception reste « — » en M6 et « hors N article(s) sans
coût » en M11 (D265). Les trois phrases de la vue qui affirment le contraire sont
remplacées par la vraie, écart nommé, Architecte à saisir (piège 13, D276).
**L'archivage d'un fournisseur obéit à UNE règle**
(`core/rbac/regle_archivage.dart`) : droit C sur M7 ET (administrateur /
super_admin OU bascule `activation_suppression`), relue à chaque geste ; seuls
les fournisseurs la honorent — la Paie et les autres écrans qui archivent gardent
leur règle propre (D272, rebranchement = lot à part). La tolérance RG-10 se lit
des Paramètres, jamais devinée. Parité PHP rejouée : règlements (84 opérations),
archivage (107), réception. Huit défauts du SERVEUR sont répliqués, non corrigés
(D257–D263, D271) : à remonter à l'Architecte. Non porté : réécriture
rétroactive des entrées déjà valorisées (D265), Montant et date de l'onglet
Commandes non reformatés.

**M6 Stocks est LOCAL depuis le 09/10/2026** (schéma v12, D115–D130 du ticket).
Les trois tables de stock (`articles_local`, `points_stockage_local`,
`mouvements_stock_local`) ont un seul auteur de SAISIE, `StocksDao` ; depuis F2b,
points et articles DESCENDENT aussi (`AligneurCatalogue`, jamais enfilé). Stock, CMP et dernier prix d'achat ne sont jamais stockés : ils sont
rejoués depuis les mouvements (`domain/calcul_stock.dart`, entiers). Un CMP sans
entrée valorisée s'affiche « — », jamais 0 ; M11 dit « hors N article(s) sans
coût ». ⚠ `MouvementsStockLocal.statutSync` a pour défaut
`en_attente_synchronisation` dans le schéma — piège : `StocksDao` écrit toujours
`local`, ne l'affichez jamais. Les ventes bar/restaurant ne décrémentent pas ce
stock (RG-05 non portée) et aucune écriture comptable n'est produite.

**`PageCarte` réserve la gouttière de 8 px de la vue quand la page déborde**
(`AppLayout.gouttiereDefilement`, D188) : un `Scrollbar` Flutter se pose par-dessus,
la barre classique du navigateur prend sa place. Filtrer les notifications de
défilement sur profondeur 0 et axe vertical, sinon les défilements internes font
osciller la page. Mesure de `rh/paie` : le banc monte l'écran SANS les taux
(bandeau « non paramétrés »), état inatteignable en production tant que D113 est
ouvert — gain de mesure pour cet état.

**M10 : moteur comptable LOCAL, réplique du serveur (10/10/2026, D192–D204).**
Seul `MoteurComptable` écrit `ecritures_local` (balayage de `lib/` en test).
Montants en centimes entiers. RG-11 = 4 triggers SQLite dont le code est traduit
en phrase du serveur. Séquence des pièces = compteur persisté (journal, année),
alloué dans la transaction de la pièce. Plan comptable = le fichier du PO
(SYSCOHADA révisé, 1332 comptes, 4 chiffres au maximum), asset octet-identique à
la copie du serveur, installé au démarrage par `installerReferentielComptable`,
jamais dans la migration. La correspondance rôle → compte (`ComptesSyscohada`,
« à valider par le comptable ») est confrontée par PHP à celle du serveur. Les
refus sont ceux du serveur, relus par PHP. Tout test qui lance PHP porte
`@Timeout(Duration(minutes: 2))` ; `rejouer_scenario.php` exige MySQL
`tatacora_test`. L'exercice de l'année courante s'ouvre à chaque démarrage
(écart assumé avec le serveur, D210) ET, depuis le 20/10/2026, à la première
pièce de l'année (`MoteurComptable`, règle `ouvertureAutomatiquePermise` :
année en cours, la suivante en décembre ; date réelle, année sans exercice) —
un poste laissé allumé au passage d'année n'a plus à redémarrer. Le serveur
fait de même (`ExerciceComptableService::assurer`, tâche
`tatacora:ouvrir-exercices`), et ses exercices DESCENDENT avec leur statut
(`TableDescendue.exercicesComptables`, apparié par l'année).

**Lot 3 Dépenses (D205–D215)** : la dépense écrit sa pièce dans la même
transaction (`DepenseDao.enregistrer` → `MoteurComptable.passerEtValider` ; le
moteur arrive par résolveur, sans lui l'écriture lève). `ecriture_id` = ligne de
trésorerie ; le n° de pièce est lu de l'écriture, jamais recopié. Seul chemin
d'argent sans pièce : `enregistrerHistoriqueSansPiece` (mode démo). Le
rattrapage (`comptabiliser(dépense, centreId)`) exige un centre EXPLICITE choisi au
bandeau (select, départ « Choisir un centre »), passé aux charges ET à la
trésorerie ; sans centre, refus RG-12 aux mots du serveur (consigné) ; le choix
n'est stocké nulle part (D216). Le poste tient une comptabilité depuis le
10/10/2026 ; le règlement fournisseur, lui, est porté depuis le lot 7 (D66 fermé, voir M7). Comptes de charge
lus du plan (4 chiffres) ; l'ancien registre à 6 chiffres sert seulement à nommer.
Confrontation : `tool/depenses/rejouer_depenses.php`. Piège : deux tests PHP
parallèles sur `tatacora_test` s'interbloquent — `executerPhp` les SÉRIALISE par
un verrou de fichier partagé entre processus (D279) et ne rejoue plus qu'en
filet, sur contention reconnue (`estContentionMysql`) ; la police de test (Ahem) élargit les tableaux :
`ensureVisible` avant de cliquer.

## Impression et exports

**L'en-tête et le pied A4 vivent dans `core/impression/entete_a4.dart`** —
point unique. Les recopier dans un état est la non-conformité n° 1 de
`RESPECT_TABLEAU_RAPPORT.md` §4.

**Un EXPORT porte la zone de signatures et le pied de rapport ; un document
REMIS AU CLIENT, jamais** (Directive §6, décision du PO du 11/09/2026 —
PA-194 serveur, PA-195 ici). `zoneSignaturesA4(visas: Visas.x)` et
`piedRapportA4(...)` pour un export ; `piedA4` seul pour une confirmation, une
facture, un ticket, une fiche des prix, le détail d'une vente. Les visas vivent
dans `core/impression/visas.dart` et sont **relus contre les gabarits serveur**
(`test/core/impression/pdf_directive_test.dart`) : un nouvel état se CLASSE au
registre de ce test, sinon il échoue.

Tout document passe par une **action injectable** (`imprimerTicketProvider`,
`imprimerEtatHistoriqueProvider`…), jamais par un `Printing.layoutPdf` recopié
dans un écran : un test de widget n'a pas de greffon natif, et il doit exister
un seul endroit où l'impression est déclenchée.

**Tout texte d'un PDF passe par `texteTicket`.** Les polices intégrées du format
couvrent Latin-1 et rien de plus : l'apostrophe typographique de « Chiffre
d'affaires » disparaissait réellement du papier, sans erreur ni trace. La garde
(`caracteresNonImprimables`) relit les textes **réellement composés**, jamais un
échantillon écrit à la main.

**Une mention qui BORNE la portée d'un document s'imprime avec lui.** La fiche
de stock porte un drapeau `coherent` vérifié par le serveur ; à `false`, elle ne
vaut pas justificatif (PA-135). L'afficher à l'écran sans l'imprimer laisserait
le document circuler comme pièce probante. Et le défaut par défaut est le
**refus** : une réponse muette sur ce drapeau est lue comme incohérente.

**Un document imprimé n'affirme jamais un statut fiscal qu'il n'a pas.** Le
papier remis à la prise de réservation s'appelle « Confirmation de
réservation », pas « Facture » : sans numéro de séquence continue ni cachet
MECeF, ce serait un faux document fiscal (PA-113). Et `numeroSuivant()`
**alloue et persiste** — ne l'appelez jamais pour composer un document.

**Un export porte sur ce qui est AFFICHÉ**, filtre compris, et le document le
dit. Une liste vide se refuse plutôt que de produire une page blanche. Aucun
document n'affirme une certification MECeF : la mention se **dérive** des
pièces, elle n'est jamais figée (PA-119).

**Les exports tableur sont des CSV**, avec BOM UTF-8 et point-virgule : c'est la
convention du serveur (RG-19) et ce qu'attend un Excel en configuration
française. Le maître écrit « Excel » sur le bouton ; l'écart est nommé en
PA-111, pas masqué. Les colonnes de montants partent en **nombres bruts** — un
tableur ne sait pas additionner « 56 000 FCFA ».

## Conventions

- Identifiants en anglais, **contenu visible en français**. Les entités métier
  centrales gardent leur nom français : `Reservation`, `Facture`, jamais
  `Booking`/`Invoice`.
- Montants en **entiers** (le XOF n'a pas de sous-unité en circulation). La
  conversion depuis les `REAL` de Drift se fait au DAO, une fois.
- **Prix ET libellé figés à l'ajout** sur toute ligne (panier, service de
  réservation) : le catalogue dit ce qu'on vend aujourd'hui, la ligne dit ce qui
  a été vendu.
- Un registre fermé (`enum` + `switch` exhaustif) plutôt qu'une chaîne libre —
  un cas ajouté demain ne doit pas obtenir un comportement par omission.
- Tout cas d'usage implémentant une RG porte un `///` avec `@see EF-M#-##` /
  `RG-##`.
- Ce qui est **calculable** s'affiche en lecture seule, jamais dans un champ.

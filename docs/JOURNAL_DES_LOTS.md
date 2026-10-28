# Journal des lots du client Flutter (archive de l'ancien CLAUDE.md)

> Copie INTÉGRALE de l'ancien `tatacora-flutter/CLAUDE.md` au 28/10/2026, déplacée ici pour
> alléger le contexte chargé à chaque session. À lire À LA DEMANDE (chercher le module ou le
> lot concerné) ; les nouveaux lots s'ajoutent ICI, jamais dans `CLAUDE.md`.

---

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

`PanierDao.cloturer` (seul écrivain de `cloture`) passe la pièce `VTE` — un débit (trésorerie du mode, ou `4111` pour la note de chambre), un crédit par module (M4 `7061` / Restaurant, M5 `7011` / Bar), la TVA par module (`4432` / `4431`) — dans la même transaction ; `ReservationDao.creer` passe la pièce de l'acompte (Dr trésorerie / Cr `4191`, rien à crédit ou sans mode) ; `annulerAvecConditions` fixe taux, commission (sur le montant GLOBAL) et remboursement (plafonné à l'acompte, Dr `4191` / Cr `5711`) et écrit 8 colonnes (v19). Refus du serveur dans son ordre, rejoués par `tool/ventes/rejouer_ventes.php` et `tool/hebergement/rejouer_annulations.php`. Calculs en entiers (`DecimalBc`, `calcul_tva.dart`). Un DAO sans moteur LÈVE. Écarts du poste : mode absent refusé, prix figé à l'ajout, numéro `V-` reçu du serveur seulement (v38), séjour toujours sur la note de chambre, M8/M9 refusés AU SÉJOUR seulement (encaissables au comptoir depuis le 22/10/2026 : M8 `7073`, M9 `7061`, TVA `4432` — voir la section « Tourisme et location au comptoir »). **NON portés** : sorties de stock de la vente (RG-05, D240), pièces rétroactives des ventes d'avant (D246), mode démo (écrit sans pièce). La clôture de caisse DIT les ventes en espèces sans session (R2). Piège : un fichier de messages qui porte les mots d'une modale doit citer la vue (sinon le comparateur ne les voit pas), et le rendu se prouve par un test ; un commentaire d'un fichier importé peut aussi fournir un libellé par sous-chaîne (gain de mesure, jamais revendiqué).

## Sessions de caisse LOCALES, réplique du serveur (12/10/2026, D219–D226)

Seul `SessionsCaisseDao` écrit `sessions_caisse_local` ; montants en centimes. Ouverture et clôture répliquent `PosComptant` (le serveur n'a pas de service), refus dans l'ordre du serveur, messages relus par PHP (`tool/caisse/rejouer_caisse.php` rejoue le vrai composant). **Aucune pièce comptable** : le serveur n'en passe aucune. Depuis le lot 5 (D231), le panier au comptant porte `session_encaissement_id` et `especesDeLaSessionProvider` rend les espèces de la session : la clôture calcule théorique et écart comme le serveur (D221–D223 dépassés), et DIT les ventes en espèces sans session (lot 6, R2). `sessionOuverteLaPlusRecente` est appelée en production depuis le lot 5 (encaissement de facture et tableau de bord : la caisse « la plus récente tous points confondus », comme le serveur). La trésorerie de caisse de M11 est calculée depuis le lot 5 (D234). Piège : un `abort(403)` rendu par le harnais Livewire est une exception, pas un statut.

## Base locale Drift — schéma **v44, 77 tables** (v43 : CHECK de `operations_sync_local` élargi au type `suppression`, table recréée, aucune table de plus ; v44 : `pieces_saisie_local` + colonne `piece_origine_id`, voir la section « Comptes du plan et pièces saisies à la main ») — l'historique ci-dessous s'arrête à la v40 : **v40, 76 tables** (mesuré le 27/10/2026 ; l'historique ci-dessous commence à la v21 = 53 tables, voir « Le poste fait comme le web » pour la v38) (v21 : colonne `fournisseurs_local.actif`, aucune table ; v20 : `reglements_fournisseur_local` ; v19 : huit colonnes d'annulation sur `reservations_local`, aucune table ; v18 : `paiements_facture_local` + colonne `paniers_local.session_encaissement_id` ; v17 : `sessions_caisse_local` ; v16 : deux colonnes `ecriture_id`/`ecriture_refus` sur `depenses_local`, aucune table ; v15 : six tables du moteur comptable M10 ; v14 : quatre tables du restaurant ; v11 : `parametres_systeme_local` ; v12 : sept colonnes de stock, aucune table neuve ; v13 : cinq tables d'achats)

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
  l'archivage, son statut reste celui du cycle local) ; un ARTICLE archivé est archivé ici aussi (`articles_local.actif`, v35 : `false` archive, `null` ou `true` actif ; la restauration descend de même) — la descente n'écrase jamais un archivage encore en file. Centres de coût :
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
  tracés, pièces du serveur (Q1 = A). Rien ne reste « non porté faute d'écran
  ou de table » depuis le 21/10/2026 (option B du PO : le poste fait ce que le
  web fait, avec sa synchronisation) : indisponibilités de la carte (v31),
  entretiens de véhicules (v32), plannings et congés (v33) — sections suivantes.
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
- **Le catalogue se vide aussi** (correction du PO) : « Quand je VIDE les
  seeders ou les données de test, PLATS, INGRÉDIENTS, ARTICLES, CARTES BOISSON
  et leurs AUTRES TABLES LIÉES EN JOINTURE doivent être vidées AUSSI. » Serveur
  (`ReinitialisationDonneesTestService`) et poste (`ReinitialisationLocale`) ne
  gardent plus que les LIEUX (`points_stockage`, `tables_salle`) ; articles,
  plats, menus, recettes, compositions, cartes de boisson, mouvements,
  inventaires, retraits de la carte et (serveur) `historique_prix_carte` (joint
  sans clé étrangère par `source_id`) sont vidés. Deux sondes énumèrent les
  jointures au lieu de recopier une liste : `ReinitialisationCatalogueTest`
  (PHP, `information_schema`) et `reinitialisation_catalogue_test.dart`
  (`PRAGMA foreign_key_list` + noms de colonnes `article_id`, `plat_id`…, car
  `lignes_inventaire_local` et `indisponibilites_carte_local` n'ont pas de FK).

## Stock estimé hors ligne, RG-05 (21/10/2026, schéma v30)

Le serveur sort le stock d'une vente à sa RÉCEPTION et ces sorties redescendent
à tous les postes (celui qui a vendu compris) : un mouvement LOCAL serait compté
deux fois. Le poste DIT donc ce que ses ventes encore en file sortiront
(« −X en attente d'envoi », sous le stock de l'écran Stocks) sans rien écrire ni
soustraire (`stock_en_attente.dart`, `stockEnAttenteProvider`). Le facteur de
conversion (`unites_vendables_par_unite_stock`) descend dans la colonne
`cartes_boisson_local.unites_vendables` (v30, NULLABLE : jamais un 1 inventé ; la
migration oublie le curseur pour que le catalogue redescende). Seules les
boissons (M5) sont estimées ; les plats (M4) ne le sont pas.

## Retraits de la carte du jour (21/10/2026, schéma v31)

Décision du PO du 21/10/2026 (option B : « ce que le web fait, le poste le
fait + synchronisation »). Table `indisponibilites_carte_local` (63 tables) :
une ligne par retrait (boisson OU plat, motif du registre fermé, commentaire,
instant, retour), sans clé étrangère. Seul écrivain de saisie :
`IndisponibilitesCarteDao` (retrait = `creation`, remise = l'unique
`modification`, tous deux enfilés dans la transaction) ; la descente
(`AligneurCatalogue._indisponibilite`) n'enfile jamais. Un article déjà retiré
ne double rien (le serveur fusionne, `fusionne_avec`) ; un retrait local encore
en file est CONSERVÉ face à celui du serveur. Le droit est celui du rayon
(boisson M5, plat M4). La carte du bar sait désormais l'état de chaque ligne
(`disponibiliteConnue`), donc « Rendre indispo. » / « Remettre » sont offerts et
la modale est un vrai formulaire. **Le restaurant (plats) l'est aussi** :
`RetraitsPlats` (même DAO), colonne « Disponible » oui/non, motif ambre sous le
nom, cartes « Articles à la carte » / « Retirés du jour » COMPTÉES (plus de
« — »), boutons « Rendre indispo. » / « Remettre » (droit M4). « Prix » et « Historique des prix » sont portés depuis la v38 (« Le poste fait comme le web »), « Lier au stock » depuis la v36. Écart nommé : le
filtre d'état « Retirés du jour » reste non servi, parce que l'API du serveur le
refuse encore (`CarteRestaurantService::ETATS_SANS_SCHEMA`, relu par un test) ;
le lever demande de changer le serveur ET ce test ensemble. Piège : la sonde « un SEUL auteur de la file » compte aussi
les LECTURES de `operationsSyncLocal` ; lire la file par `OperationsSyncDao`.

## « Lier au stock » du restaurant (21/10/2026, schéma v36)

Le PO ne pouvait « ni créer un menu de restaurant ni le lier au stock » : menu,
fiche (ingrédients = articles de stock) et plat se créaient déjà (prouvé par
`chaine_reelle_restaurant_test`) ; ce qui manquait était le **lien direct
plat -> article** (« Lier au stock », refusé faute de colonne). Deux colonnes
NULLABLES ajoutées à `plats_local` : `article_id` (sans clé étrangère, l'article
peut descendre après le plat) et `unites_vendables` (texte décimal du serveur,
« 24.0000 »). Seul écrivain : `RestaurantDao.lierAuStock` / `delierDuStock`
(les DEUX colonnes partent ensemble ; refus aux phrases du serveur) ; la
modification du plat part avec `article_id` + `unites_vendables_par_unite_stock`
(`null` des deux pour délier). Le lien l'emporte sur la fiche : portions =
solde du point cuisine × conditionnement (`LienDirectCalcule`) ; la carte nomme
l'article et « 24 par casier » ; « Modifier le lien » / « Délier » (droit M4).
Serveur : `GestionnairePlats` valide et écrit le lien (sans lui `validated()` le
jetait en silence). Descente : `AligneurCatalogue._plat` (article absent =
attente). « Prix » et « Historique des prix » sont portés depuis la v38. Les ventes ne
décrémentent toujours rien (RG-05 non portée). Preuves :
`lier_au_stock_plat_test.dart` (mutations éprouvées : retirer l'enfilement, ou
ignorer le lien dans le calcul, fait rougir), `migration_v36_lien_plat_test.dart`,
côté serveur `CatalogueRestaurantSynchronisationTest`.

## Entretiens de véhicules (21/10/2026, schéma v32)

Table `entretiens_vehicule_local` (64 tables) : un FAIT daté — type
(`entretien` | `carburation`), jour, coût en francs entiers, chauffeur
facultatif, login de l'auteur (`null` pour une ligne descendue : l'écran rend
« — »). Seul écrivain de saisie : `VehiculeDao.enregistrerEntretien` (une
`creation`, jamais de modification : `accepteModification: false`), qui enfile
d'abord le véhicule s'il est inconnu du serveur. « Immobiliser » écrit
désormais cette ligne et **ne touche plus au statut** du véhicule — comme la
PWA (statut ≠ disponibilité) ; sortir un véhicule du parc louable se fait depuis
sa ligne. L'onglet « Immobilisations » lit la table. Descente :
`AligneurDocuments._entretienVehicule` (n'enfile jamais ; véhicule absent =
attente ; fraction de franc refusée). « Au » reste inerte : aucune colonne de fin.

## Plannings et congés (21/10/2026, schéma v33)

Écran créé d'abord à la PWA (« Congés & Plannings », `pwa/rh/conges-plannings`,
libellés dans `lang/fr/rh_conges_pwa.php`), repris ici au mot, route
`/conges-plannings`, menu « Ressources humaines », droit M13. Deux tables
(66 tables), sans clé étrangère : `plannings_local` (employé, service, jour,
heures `HH:MM`) et `conges_local` (nature, bornes incluses, statut, login du
validateur — `null` pour une ligne descendue, l'écran rend « — »). Seul
écrivain de saisie : `CongesPlanningsDao` (classe simple, pas d'accesseur
Drift), qui **rejoue RG-13 et RG-14 aux mots du serveur** (`lang/fr/rh.php`
exécuté par PHP dans `messages_conges_plannings_test.dart`) et enfile chaque
geste dans sa transaction.

- **RG-13** : même employé, même jour, `début < autreFin && fin > autreDébut`
  (une borne commune passe) ; refus avant : employé hors effectif, congé VALIDÉ
  couvrant la date (bornes incluses).
- **RG-14** : DEMANDER est toujours accepté ; VALIDER lit
  `delai_preavis_conge_jours` puis `couverture_minimale_par_service` dans
  `parametres_systeme_local` et **refuse s'ils manquent** (jamais de valeur
  devinée ; ce fichier est leur `lecteur` déclaré) ; préavis = jours entre
  aujourd'hui et le premier jour, couverture = effectif `actif` du service −
  (absents validés qui se recoupent, sans cette demande, + 1) ≥ minimum ;
  REFUSER garde la demande. Une demande décidée ne se rouvre pas.
- **Synchronisation** : `plannings` (création seule) et `conges` (création +
  l'unique modification `statut_validation`), après `bulletins_paie` au registre
  PHP comme dans `TableSynchronisee` / `TableDescendue`. Le planning porte le
  service par identifiant (traduit par la correspondance retenue à la descente)
  ET par libellé : le serveur retombe sur le libellé tant que le poste n'a rien
  reçu. Le serveur rejoue RG-13/RG-14 avec SES données et ses paramètres : une
  décision refusée là-bas revient dans « À traiter ». Descente : un créneau ou
  une demande d'un autre poste s'écrit sans rien renvoyer ; la décision du
  serveur descend vers l'avant seulement ; une décision locale encore en file
  est conservée (règle commune de `AligneurCatalogue.aligner`).
- **Pièges** : la barre latérale de l'administrateur a gagné 35 px — le banc
  `barre_laterale_blade_test.dart` monte la fenêtre à 1 500 px de haut, sinon
  « Paramètres » tombe sous le pied et se compte manquant ; les compteurs
  figés « vingt-quatre destinations » sont passés à 25 ; une phrase de la vue
  doit tenir en UN littéral pour que le comparateur la trouve (le sous-titre).

## Postes & Appairage (21/10/2026)

L'écran « Synchroniser les postes » devient **« Postes & Appairage »**, à la PWA
(`pwa.synchronisation-postes`) et sur le poste (`/synchronisation-postes`),
inspiré d'une autre application (demande du PO). Neuf colonnes : Poste,
Utilisateur, Appairé le (premier jeton), Dernier contact (dernier usage du
jeton), Expiration (jeton le plus durable ; « Sans expiration »), Dernier envoi,
Dernier contrôle, État, Actions (« Révoquer »), plus « Actualiser » (relit,
n'écrit rien) et « Demander la synchronisation des postes ». L'**état** est
calculé par le serveur (`SuiviPostesService::etats()`) : `actif`, `sans
nouvelles` (jeton valide, silence de plus de 24 h), `expiré`, `non appairé` ;
un code inconnu se lit « non appairé », jamais « actif ». Le « dernier contrôle »
est noté quand le poste passe sur `GET /sync/coherence` (colonne
`dernier_controle_le`, son nom est celui de son jeton). L'entrée de menu
« Synchronisation » est dans « Pilotage & administration » des deux côtés (droit
Paramètres, masquée au gérant) en plus de l'entrée du menu de compte ; l'écran
de la FILE locale du poste (`/synchronisation`) reste atteint par Paramètres →
Synchronisation et par « Voir le détail » du bouton de la barre supérieure.

## Réception : journal, causes, corrections, relances (26/10/2026, schéma v37)

Demande du PO : « une partie de RÉCEPTION dans la page de synchronisation, avec
toutes les informations reçues, les ÉCHECS, les RELANCES, les CORRECTIONS :
identifier la CAUSE des échecs, CORRIGER et RELANCER ». `/synchronisation` a
désormais DEUX parties (onglets **Envoi** — par défaut — et **Réception**, avec
le nombre d'éléments à traiter) sous la carte d'état.

- **Schéma v37** (73 tables) : `journal_reception_local`, UNE table neuve, clé
  (`table_serveur`, `element_id`), migration conditionnelle (fixture
  `_ajoutsParVersion[37]`, `tablesAjouteesEnV37`, test sur fichier réel
  `migration_v37_journal_reception_test.dart`). Une ligne par élément reçu : issue
  (`aligne` / `conserve` / `attente` / `refuse`), cause, motif de l'aligneur,
  champ fautif, élément lié manquant, nom lisible, poste d'origine, tentatives,
  dates ; `element_json` garde l'élément TANT QU'IL RESTE À TRAITER (c'est ce
  que « Relancer » rejoue). Une nouvelle version (autre `modifie_le`) repart à
  une tentative ; la reprise de fin de descente ne recompte pas un élément que la
  page vient de consigner (`_vuCetPassage`).
- **Seul écrivain** : `JournalReceptionDao` (`data/journal_reception_dao.dart`),
  appelé par `DescenteCatalogue` SEULE (`_consigner`, les éléments illisibles,
  la version périmée oubliée, les relances) — jamais l'aligneur, jamais la file ;
  il n'enfile rien. Sonde dans `journal_reception_test.dart`. Rétention bornée :
  `purger()` en fin de descente — les alignés de plus de 30 jours, puis au-delà
  de 5 000 lignes les alignés les plus anciens ; un élément à traiter n'est jamais
  purgé par l'âge. « Réinitialiser comme neuf » le vide (non gardé).
- **La cause** (`domain/journal_reception.dart`, pur) : l'aligneur ne rend
  qu'une phrase ; `analyserMotif` en déduit une `CauseReception` (registre
  fermé : élément lié manquant — avec sa TABLE —, compte local absent, conflit
  avec une saisie locale, homonyme local, donnée illisible — avec son CHAMP —,
  valeur inconnue — champ et valeur —, précision non tenue, écriture impossible,
  règle du poste) et `expliquer` en fait la phrase, la correction et le geste
  (`ActionCorrection` : ouvrir l'écran de création — `ecranDeCreation` —, voir
  les éléments liés, voir la file d'envoi). `cause_reception_domaine_test.dart`
  BALAIE tous les motifs de `aligneur_catalogue.dart` et `aligneur_documents.dart` :
  un motif nouveau non classé fait rougir l'essai (les règles propres du poste
  sont nommées une à une). Toute table se dit par `libelleTableServeur`.
- **« Relancer »** (`DescenteCatalogue.relancerElement`, sans réseau) rejoue
  l'aligneur sur l'élément gardé (`element_differe:*` ou, pour un refus, l'élément
  du journal) ; réussi, il reprend aussi les éléments qui le citaient.
  **« Relancer tout »** (`relancerToutProvider`) : les refusés, puis la reprise
  de tous les gardés, puis la levée du repli et un PASSAGE COMPLET (envoi, puis
  descente depuis le curseur). ⚠ Un élément REFUSÉ pour une donnée fausse AU
  SERVEUR ne change pas en le relançant : la même version est rejugée ; on corrige
  à la source, puis « Relancer tout » reçoit la version corrigée (le texte de la
  cause le dit). Les deux gestes, « Corriger » et « Relancer », sont réservés aux
  Administrateurs.
- **« Corriger »** (réception) : la cause exacte, comment la corriger, et ce que
  le poste sait faire pour elle (ouvrir « Comptes utilisateurs » quand aucun compte
  n'existe pour porter l'écriture, ouvrir l'écran qui crée l'élément lié, filtrer
  le journal sur sa table, voir la file d'envoi), puis « Relancer ».
- **Liste** : compteurs (reçus, alignés, conservés, en attente, refusés — un clic
  filtre), filtres par table, par issue et par date de dernière tentative,
  pagination commune, détail d'un élément (fiche, cause, correction, tentatives).
  Providers dans `providers_reception.dart` (relecture au signal de tables de
  Drift, jamais un `.watch()`) ; modales dans `modales_reception.dart`.
- **Envoi** (`domain/cause_envoi.dart`, pur) : pour une opération rejetée ou
  bloquée, la CAUSE lisible vient du `code_motif` du serveur (registre FERMÉ, relu
  du PHP par `cause_envoi_test.dart`), de sa phrase et de ses `erreurs` par champ
  (ajoutés au serveur dans `SynchronisationService::rejet`, avec le journal
  d'envoi du web — aucune autre modification serveur ici). Chaque ligne dit sa
  cause, les phrases du serveur par champ, le nombre de tentatives et le dernier
  code HTTP ; « Détail » ajoute l'historique des opérations du même élément.
  **« Corriger »** = un formulaire GÉNÉRÉ de la charge FIGÉE : seuls les champs du
  registre (libellés, noms, montants, dates, quantités — jamais un identifiant,
  un statut ou une ligne) sont proposés, typés comme la charge (entier, décimal
  à la précision d'origine, `AAAA-MM-JJ`, instant), validés (`corrigerCharge`) ;
  valide, `OperationsSyncDao.renvoyer(uuid, chargeCorrigee:)` crée la remplaçante
  sous un NOUVEL uuid avec la charge corrigée, l'ancienne reste rejetée, intacte,
  marquée remplacée. Le serveur rejuge à l'envoi.
- **Annonces et cohérence** : la partie Réception range le catalogue reçu
  (dernier bilan de descente), le contrôle de cohérence — le DERNIER contrôle
  mesuré est rangé (`coherence.dernier`, `DescenteCatalogueDao`) et relu après un
  redémarrage, avec ses écarts —, les annonces du serveur (phase d'essais,
  génération des données, réinitialisation constatée) et le nombre de
  signalements d'envoi.
- **Pièges rencontrés** : un `Provider<void>` « signal » ne notifie jamais
  (sa valeur ne change pas) — chaque provider s'abonne et se relit lui-même
  (`invalidateSelf`) ; la largeur intrinsèque d'une rangée `Expanded` fait de la
  plus longue phrase la largeur de TOUTES les colonnes (boutons hors écran) —
  largeurs fixes par colonne (`MesuresTransverses.colonnesReception`,
  `colonnesATraiter`) ; un faux serveur qui repart de zéro exige `effacerCurseur()`.
- **Essai réel** : `reception_serveur_reel_test.dart` — vrai `artisan serve` sur
  la base d'essai PRIVÉE `tatacora_syncposte_test` (`TATACORA_BASE_ESSAI`, accepté
  maintenant par `tool/sync/serveur_reel.php`, qui gagne l'action `modifier`) :
  un client à l'e-mail invalide est refusé, corrigé par le formulaire, renvoyé et
  ACCEPTÉ ; un point de stockage au type inconnu est refusé (la cascade article →
  fiche → plat attend), un poste sans compte ne peut pas écrire un menu — compte
  créé, donnée corrigée à la source, « Relancer tout » : tout est aligné.

## Compte de résultat et bilan sur le poste (21/10/2026, schéma v34)

Décision du PO (« oui » au bilan et au compte de résultat sur le poste ; option B :
le poste fait ce que le web fait). Le serveur reste le seul comptable (D246) :
les **écritures VALIDÉES** lui descendent (`TableDescendue.ecrituresComptables`,
après les exercices ; lecture sous M10 ; brouillons jamais) dans la table
`ecritures_serveur_local` (67 tables), un **miroir de LECTURE**, immuable (RG-11),
sans clé étrangère : chaque ligne porte l'année de son exercice, le code du
journal, le numéro, le libellé et la classe du compte (résolus par le serveur,
`CatalogueDescendantService::ecrituresDeLaPage`). Seul écrivain :
`EcrituresServeurDao.ajouterSiAbsente` (insert-if-absent, jamais réécrit, rien
n'est enfilé ; sonde `ecrivains_ecritures_serveur_test.dart`).

- **Jamais mêlé aux pièces du poste** : `ecritures_local` (journal et balance du
  poste) est inchangé ; le serveur passe sa propre pièce pour chaque document que
  ce poste lui envoie, donc additionner les deux compterait chaque vente deux
  fois. Les états se lisent ICI et disent (encadré « provenance ») combien
  d'écritures le poste a reçues et combien d'opérations il n'a pas encore
  envoyées.
- **Calcul** : `domain/etats_financiers.dart` (centimes entiers) reprend
  `BalanceGeneraleService` (journal `CL` exclu, à-nouveaux PROVISOIRES récursifs
  quand l'exercice précédent n'est pas clôturé, 131/139 selon le signe),
  `CompteResultatService` (cascade `SoldesIntermediairesGestion::CASCADE`, impôt
  lu de la classe 89, jamais un taux) et `BilanService` (préfixes
  `RubriquesSyscohada`, comptes hors rubrique). **Confronté au VRAI serveur** :
  `etats_financiers_contre_serveur_test.dart` (script
  `tool/etats/rejouer_etats_financiers.php`, quatre exercices dont un clôturé,
  un en clôture, perte et bénéfice, report en chaîne, compte hors nomenclature)
  et relit la cascade et les préfixes du serveur. Mutations éprouvées (retirer
  l'exclusion de `CL`, inverser 131/139).
- **Écran** : onglets « Compte de résultat » et « Bilan » du hub
  (`widgets/onglets_etats_financiers.dart`) aux colonnes, totaux et bandeaux des
  vues, avec la colonne « Exercice N-1 » quand l'exercice précédent existe. Le
  filtre de statut ne s'y applique pas (seules les validées descendent) — dit à
  l'écran. Grand livre, Analytique, Immobilisations, Plan comptable et Clôtures
  sont portés depuis (voir « Clôture annuelle SYSCOHADA »).
- **Pièges** : le comparateur compte par SOUS-CHAÎNE dans tout le code que
  l'écran atteint, commentaires compris — un en-tête de commentaire « Seules les
  … » dans le fichier de la table a fait baisser la dette du journal d'audit
  sans qu'un pixel change ; reformulé plutôt que figé. Une classe `CompteDuPlan`
  existait déjà (entité) : celle du report s'appelle `CompteDeReport`.

## Immobilisations sur le poste (21/10/2026, schéma v35)

Onglet « Immobilisations » du hub comptable porté de bout en bout (refus
`immo_modale_titre` et `modale-titre-calcule` levés). Table
`immobilisations_local`, seul écrivain de saisie `ImmobilisationsDao`
(`comptabilite/data/`) : `creer` rejoue `ImmobilisationService::creer` (libellé,
valeur > 0, durée obligatoire sans défaut, date, compte connu du plan) **aux
phrases du serveur** et enfile une `creation` dans la même transaction (le
serveur : `GestionnaireImmobilisations`, M10, création seule, jamais
« financière »). Le **code** `IMMO-AAAA-NNNNN` est provisoire sur le poste ; celui
du serveur revient à l'accusé (`SyncManager` → `regulariserCode`) ou à la
descente. Le **plan est CALCULÉ, jamais stocké** (`domain/immobilisations.dart`,
centimes, `BigInt` pour les dix décimales de `bcdiv`) et **confronté au vrai
service** (`plan_amortissement_contre_serveur_test.dart`,
`tool/comptabilite/rejouer_immobilisations.php` : prorata en mois entamés, dernière
annuité = solde, annuité nulle sautée, valeurs > 64 bits). Descente
(`AligneurDocuments._immobilisation`) : insère si absent, ne réécrit qu'un code,
n'enfile jamais ; fraction de centime, durée absente ou date illisible refusées.
Écarts nommés : date saisie `JJ/MM/AAAA` (calendrier réel exigé, le serveur ne
vérifie que la forme) ; aucune écriture de dotation, ici comme au serveur ;
la phrase « … · N ans · linéaire · mise en service … » de la modale « Plan »
reste comptée absente par le comparateur (l'interpolation sépare « · » de « ans »).

## Relances, archivage des clients, avoir partiel (21/10/2026, schéma v35)

Option B du PO (« tout au complet ») : le poste fait ce que la PWA fait pour
`crm/clients-creances` et `facturation`, avec sa synchronisation. Les trois
refus `blade-refuse:` de l'écran Clients et le refus de l'avoir partiel sont
LEVÉS.

- **Relances** (`relances_clients_local`, v35, aucune clé étrangère) : un FAIT
  daté, création seule. Seul écrivain de saisie : `RelancesClientsDao`
  (`crm/data/`, classe simple) — réplique de `RelanceClientService` aux phrases
  du serveur (`messages_relance.dart`, confrontées par PHP exécuté, validation
  Laravel du montant comprise : « Le champ relance montant est obligatoire. »).
  Montant en CENTIMES, envoyé en chaîne décimale exacte (`"10000.50"`). Un
  client d'avant la synchronisation (`statut_sync = local`, aucune création en
  file) est ENVOYÉ avant sa relance (`ClientDao.assurerConnuDuServeur`), sans
  quoi le serveur répondrait « client inconnu » à chaque essai. « Clients à
  relancer » = `clientsARelancer` (pur) : débiteurs du registre sans relance
  depuis 30 jours (`joursAvantRelance`, relu du serveur par un test) ; la borne
  est incluse (une relance faite il y a 30 jours est récente). Serveur :
  `GestionnaireRelancesClients` (M3, création seule), après `clients` au
  registre et dans `COLONNES` ; `RelanceClientService::enregistrer` accepte un
  `id` (rejeu idempotent). Descente : `AligneurDocuments._relanceClient`
  (n'enfile jamais ; client absent = attente ; canal inconnu / fraction de centime
  / date illisible = refusé et compté).
- **Archivage d'un client** (`clients_local.actif`, nullable : `null`/`true` =
  actif). Seul écrivain : `ArchivageClients` (`crm/data/`), qui rejoue les
  QUATRE verrous du serveur sur les données locales (séjour : départ ≥
  aujourd'hui, non annulé ; location : fin ≥ aujourd'hui, contrat NON annulé (statut local, v38) ; circuit non
  annulé à venir ; facture non soldée par `CreanceFacture.estImpayee`, jamais une
  seconde formule). Le verrou est recontrôlé DANS la transaction qui écrit. La
  règle « qui peut archiver » est `core/rbac/regle_archivage.dart`, exigée à
  l'ouverture ET à l'exécution ; restaurer n'exige que l'écriture sur M3. La
  modale est `ModaleArchivageAchats` (le composant est partagé, son fichier cite
  la vue des clients). Serveur : `GestionnaireClients` accepte `actif` (via
  `ReferentielClientService` + `DroitArchivageService`, comme les fournisseurs) ;
  un archivage refusé rejette TOUTE l'opération. L'`AligneurCatalogue._client`
  applique `actif` (plus d'« archive non portée » pour les clients) et retient
  l'origine du client (`connuDuServeur`). Comme à la PWA, les sélecteurs de
  clients proposent encore les archivés.
- **Avoir partiel** : `FactureDao.emettreAvoirPartiel` — la règle est celle du
  SERVICE (`emettreAvoir` : jamais plus que le TTC, avoirs non cumulés), le TTC
  entier reste l'annulation (`annuler`). L'avoir est une pièce à lui, d'UNE ligne
  « Avoir partiel — motif » (quantité −1), la facture reste émise ; reste dû =
  `creances.dart`, formule inchangée. Il part en `{montant (francs), motif,
  avoir_id}` : l'avoir naît au serveur sous l'UUID du poste (`avoir_id`), rend
  SON numéro (`numero_avoir`, `avoir_id`) que `FactureDao.regulariserAvoir` pose
  — depuis la réponse d'envoi OU depuis la descente (`_avoir` reconnaît son id).
  `avoirProvisoireDe` ne sert plus que l'avoir d'une facture ANNULÉE ici. Pas de
  garde Q3 sur l'avoir partiel (il n'annule rien ; la PWA l'ouvre à tout compte
  M2) ; l'annulation, elle, la garde.
- **Ancrages extérieurs** : `charges_relances_archivage_avoir_contre_serveur_test`
  (le vrai `SynchronisationService`, ce que le serveur a ÉCRIT est relu),
  `messages_relance_test` (PHP exécuté), et côté serveur
  `RelancesEtArchivageClientsSynchronisationTest`, `AvoirPartielSynchronisationTest`.
- **Pièges** : `TestWidgetsFlutterBinding` + deux `monter()` dans un test avec des
  `ProviderScope` différents réutilise le premier état — un test par rôle ; le
  message de succès d'un `SnackBar` bloque le suivant 4 s (`pump(5 s)`).

## Inventaire physique et archivage des articles (21/10/2026, schéma v35)

Option B du PO (« tout au complet ») : le poste ouvre un inventaire par point,
saisit les comptages, le clôture et le régularise ; il archive et restaure les
articles. Écran `/stocks/inventaires` (cycle, feuille, historique) et `/stocks`
(cases, « Supprimer », badge « Archivé », « Restaurer »).

- **Inventaire** : le comptage en cours vit EN MÉMOIRE (`inventaireEnCoursProvider`,
  remis à zéro au changement de compte) jusqu'à la clôture — le schéma serveur ne
  porte aucun statut (PA-150), une ligne écrite avant ne se distinguerait pas d'un
  inventaire clos. Fermer la fenêtre avant de clôturer abandonne le comptage ;
  la feuille le dit. Un comptage FIGE le théorique du point à cet instant
  (`InventaireService::compter`), un second écrase le premier. `StocksDao.
  cloturerInventaire` écrit l'inventaire, ses lignes (centièmes) et un mouvement
  de régularisation par écart dans UNE transaction, enfilés dans cet ordre :
  l'excédent en `inventaire` NON valorisée, le manquant en `perte` (forcée si le
  disponible d'aujourd'hui ne le couvre plus), motif `Régularisation inventaire
  <id> — écart de ±x.xx`. Un seul `INSERT` de mouvement (`_inserer`) pour la
  saisie et la régularisation. Un écart dont l'article n'a aucune entrée
  valorisée n'est pas valorisé (« — » + une ligne qui le dit), jamais zéro.
  Modale « Inventaire incomplet » : quand tout est compté elle devient
  « Clôturer et régulariser » (la vue y dirait « 0 article(s) n'ont pas été
  comptés », faux). L'historique liste `inventaires_local` (clôturés ici OU
  descendus), « — » aux trois montants comme la vue.
- **Synchronisation** : UN document `inventaires` (point, jour, lignes :
  théorique figé, constaté, écart en centièmes) — gestionnaire serveur
  `GestionnaireInventaires`, une transaction, valeurs du poste écrites TELLES
  QUELLES (écart vérifié contre lui-même seulement) — puis ses mouvements
  (`mouvements_stock` accepte désormais `inventaire`, l'excédent). Descente : les
  lignes descendent AVEC l'inventaire (`CatalogueDescendantService::ENFANTS`),
  `AligneurDocuments._inventaire` l'écrit en entier ou le met en attente
  (point/article pas reçu), un inventaire détenu n'est jamais réécrit, aucun
  mouvement n'est réécrit.
- **Archivage** : `StocksDao.verrousArticle` rejoue les quatre verrous du serveur
  (`ReferentielArticleService::verrous`) sur les données locales — solde > 0 tous
  points, LIGNES de commande en cours (un statut inconnu engage), boissons de la
  carte, compositions de recette — aux phrases de `lang/fr/stocks_pwa.php`,
  recontrôlés à l'exécution, motifs joints par une espace. La règle est
  `core/rbac/regle_archivage.dart` (`peutArchiverProvider`, relue à chaque geste
  par `StocksApi`) ; « Restaurer » n'est pas derrière elle. Le verrou
  « plat lié au stock » (`plats.article_id`) est rejoué depuis la v36
  (`plats_local.article_id`), compté avec les boissons dans « vendu à la carte ». L'archivage part en
  `{'actif': false}`, la restauration en `{'actif': true}`.
- **Preuves contre le serveur** : `archivage_inventaire_contre_serveur_test.dart`
  (phrases du `lang/` PHP + six scénarios de verrous rejoués par
  `tool/stocks/rejouer_archivage.php` sur `ReferentielArticleService`),
  `inventaire_archivage_contre_serveur_test.dart` (la file poussée à
  `SynchronisationService`, lignes relues). `TATACORA_BASE_ESSAI=tatacora_<nom>_test`
  remplace `tatacora_test` dans ces deux scripts quand plusieurs essais tournent
  ensemble (la base partagée est migrée sous les pieds de l'un ou de l'autre).
- **Pièges rencontrés** : un `SnackBar` s'EMPILE (le message d'ouverture restait
  quatre secondes après la clôture) — `clearSnackBars()` avant d'annoncer ; la
  mesure de conformité cherche les libellés d'une MODALE dans les seuls fichiers
  qui citent la vue (pas leurs imports) : la phrase du serveur de la modale
  « Inventaire incomplet » est écrite dans `modales_inventaire.dart` ET dans
  `MessagesStock`, et un test confronte les deux au fichier de langue PHP ;
  `ORDER BY type_mouvement` trie un `enum` MySQL par INDEX, pas par ordre
  alphabétique.

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
réseau. Son registre fermé de 46 clés (31 + les 15 `compte_<rôle>` de la correspondance des comptes) est relu du serveur par un test (PHP
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
(crédit `7061`, centre Restaurant, TVA `4432`). ⚠ Catégorie du plat : portée depuis la v41 (27/10/2026), voir « Les champs du web portés : véhicule, contrat, plat, guide » ; la CARTE du restaurant (filtre, groupes de la couverture, impressions), elle, classe encore par TYPE DE MENU, comme `CarteRestaurantService` de l'API.

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
jamais dans la migration. La correspondance rôle → compte (`ComptesSyscohada`)
est confrontée par PHP à celle du serveur : ses numéros sont les DÉFAUTS d'une
correspondance modifiable (voir « Correspondance des comptes » plus bas). Les
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

## Canaux de réservation, composition provisoire, remise du panier (21/10/2026, « tout au complet »)

- **Canaux** : `canaux_reservation_local` (schéma v35), écrivain unique `CanauxReservationDao` (ajout, renommage, désactivation/réactivation, jamais de suppression ; refus aux phrases du serveur, relues par PHP). Un poste vierge reçoit le jeu initial sous des UUID v5 stables (le serveur exige un UUID pour pousser) ; les réservations d'avant la v35 (`can-…`) sont réécrites vers l'id du canal de même NOM, sans rien envoyer. La fiche, la réservation rapide et le filtre des annulations lisent la TABLE (`CanalReservation` n'est plus une énumération). Sync : `canaux_reservation` (création par le nom ; modification = état entier + `ancien_nom` pour retrouver un canal aligné par son nom) ; descente AVANT les réservations, lecture libre. Plus aucun jeton `blade-refuse` pour l'onglet.
- **Composition provisoire** : colonne lue/écrite ; descend avec la fiche ; levée en réenregistrant la composition (la modification part avec `lignes` même inchangées, sinon le serveur garderait la marque). Compteur, badge, bandeau, marque « P » du comptoir sont alimentés.
- **Remise** : `paniers_local.remise_type/remise_valeur_centiemes`, formule répliquée en centimes (`pos/domain/remise_panier.dart`), jugée à la saisie ET à l'encaissement ; pièce VTE sur le net (`ventilerAuNet`, dernier module = écart), `montantCloture` = net arrondi au franc (écart nommé : les centimes ne vivent que dans la pièce), vente envoyée avec type + valeur seulement si une remise existe, facture avec lignes négatives par module. Confronté au serveur dans `ventes_contre_serveur_test.dart` et `charges_contre_serveur_test.dart`.
- Piège : le comparateur de ventes lit le NET de la pièce (débit), pas `montantCloture`.

## Correspondance des comptes — les comptes SE MODIFIENT (26/10/2026, décision du PO)

« ON PEUT IMPÉRATIVEMENT MODIFIER LES COMPTES SUR POSTE ET LE WEB. » Les comptes
7073 (Locations, M8), 7061 (services vendus, circuits M9) et 4432 (TVA sur
prestations) sont **validés par le PO le 26/10/2026** ; le comptable peut encore
changer n'importe quel rôle à l'écran.

- **Les constantes de `ComptesSyscohada` sont des DÉFAUTS.** Quinze RÔLES sont
  modifiables (`RolesCorrespondance`, relu du serveur par
  `correspondance_comptes_contre_serveur_test`) : produits restaurant / bar /
  location / circuits (`PRODUIT_CIRCUITS` est NEUF : M9 ne partage plus M4), TVA
  facturée biens et prestations, TVA récupérable, caisse / banque / Mobile
  Money, clients, fournisseurs, avances clients, résultat bénéfice / perte. Les
  cinq comptes de CHARGE (achats, électricité, eau, location, téléphone) n'en
  sont PAS : le compte d'une charge se choisit ligne par ligne à la saisie d'une
  dépense, un réglage sans lecteur serait l'indicateur qui affirme sans vérifier.
- **Stockage : aucun schéma.** Un rôle = un paramètre `compte_<rôle en
  minuscules>` de `parametres_systeme_local` (registre fermé, groupe `comptes`,
  quinze clés de plus : 46 en tout, côté serveur comme côté poste). Dernier
  écrit gagnant, clé par clé, par le chemin des autres paramètres : le poste
  enfile UN enregistrement (le Journal d'Audit du poste le relit), le serveur le
  passe par `EnregistrerParametreService` (audit avec l'ancienne valeur), la
  descente le pose sans rien renvoyer. Vide / absent = le défaut.
- **Une règle de validation, DEUX endroits, les mêmes phrases** : format
  `RegleNumeroCompte` (`PlanComptableService::NUMERO_COMPTE_FORMAT`), compte
  existant au plan, classe cohérente avec le rôle (produit : 7, TVA collectée :
  443, TVA récupérable : 445, trésorerie : 5, clients : 411, fournisseurs : 401,
  avances : 419, résultat : 13), compte imputable (pas une division). Au serveur
  la validation vit DANS `EnregistrerParametreService` (donc l'écran ET la
  synchronisation d'un poste) ; au poste dans `EnregistrerParametres`
  (`verifierCompte`, fermé par défaut : sans vérificateur, une clé de rôle est
  refusée). `rejouer_correspondance.php` rejoue 1 185 opérations contre le vrai
  service.
- **Le moteur lit au moment de passer la pièce.** `LigneDemandee(role: …)` : le
  moteur résout le rôle (`ComptabiliteDao.compteDuRole`) dans la transaction de
  la pièce ; une ligne sans rôle garde son numéro. Serveur : `CorrespondanceComptesService`
  injecté dans VenteService (M4/M5/M8/M9, TVA, clients, trésorerie),
  ReservationService, AnnulationReservationService, EncaissementFactureService,
  ReglementFournisseurService, DepenseService, ClotureExerciceService. Un compte
  choisi sans centre par défaut au plan ne bloque pas la pièce : la ligne qui
  nomme son rôle retombe sur le centre du compte PAR DÉFAUT du rôle (jamais un
  centre inventé).
- **RG-11 : une pièce déjà passée n'est JAMAIS réécrite.** L'écran le DIT en
  tête. Les états qui relisent un compte sur une période (déclaration de TVA)
  lisent le compte choisi ET le défaut (`comptesLus`) ; les valeurs
  intermédiaires d'un rôle changé plusieurs fois ne sont retrouvées que dans le
  journal d'audit (écart assumé). Le bilan lit tout le groupe 13
  (`RESULTAT_REPORTE = ['13']`, serveur et poste) : un résultat reporté sur un
  autre compte de la classe 13 ne le déséquilibre pas.
- **Écran** : « Correspondance des comptes », lien de l'onglet Plan du hub
  (`/pwa/comptabilite/correspondance-comptes`, poste
  `/comptabilite/correspondance-comptes`) ; vue Blade
  `correspondance-comptes.blade.php`, libellés de `lang/fr/comptes_correspondance.php`
  repris au mot (les mots de la MODALE sont des littéraux de l'écran : le
  comparateur ne cherche une modale que dans les fichiers qui portent la vue ;
  un test les égale à la langue). Droit : M10 (lecture pour voir, écriture
  pour modifier : administrateurs, gérant, comptable). Les clés `compte_*` ne se
  montrent PAS dans l'écran Paramètres.
- **Écart assumé** : TVA récupérable, résultat bénéfice et perte n'ont aucun
  lecteur sur le POSTE (déclaration de TVA et clôture sont au serveur) : leur
  ligne le dit (`serveurSeul`), et le registre local les déclare sans lecteur.
- **Parité prouvée contre le VRAI PHP** (un scénario `_scenarioCorrespondance`
  par flux, mêmes ops des deux côtés) : ventes (`ventes_contre_serveur_test`),
  règlement fournisseur, encaissement de facture, acompte et remboursement,
  dépense. Les cinq outils `tool/*/rejouer_*.php` ont une opération `parametre`.

## Tourisme et location au comptoir (22/10/2026)

> **RETIRÉS DE LA SÉLECTION (26/10/2026, directive du PO)** : « il faut enlever
> cette catégorie de la sélection dans le poste de vente et dans le POS clients
> (hébergés) ». Ni le POS au comptant ni celui des hébergés (web ET poste) ne
> proposent plus « Tourisme » / « Location » : ni famille, ni pastille, ni carte,
> ni carte grisée (`prestationRefusee`, `CategorieHeberges.prestations` et les
> clés de langue `famille_tourisme` / `famille_location` n'existent plus). Poste :
> `rayonsProvider` ne rend que `modulesProposesAuPos` (M4, M5) ; le dépôt de
> catalogue (`CatalogueDao.rayons`) garde M8/M9, la fiche de réservation en
> a besoin. Le DOMAINE reste défensif et INCHANGÉ : `PanierDao`, `VenteService`,
> la pièce (7073 / 7061 / 4432) et la synchronisation acceptent une vente M8/M9
> déjà faite — ce que prouvent encore `VenteTourismeLocationTest` (PHP),
> `cloture_vente_piece_test` et `vente_prestations_journal_test`. L'ABSENCE à la
> sélection se prouve dans `PosComptantPrestationsTest`, `PosPwaTest` et
> `ecrans_pos_test.dart` (mutation : ne plus filtrer `rayonsProvider` les fait
> rougir). Le reste de cette section décrit le domaine, pas l'interface.

Directive du PO : « TOURISME et LOCATION sont encaissables au COMPTOIR (POS), au
poste comme au web. » Le serveur les REFUSAIT aussi (`VenteService::MODULES_ENCAISSABLES
= ['M4','M5']`) : il a été porté en même temps que le poste.

- **Modules et comptes** (poste `piece_de_la_vente.dart`, serveur `VenteService`,
  confrontés par `ventes_contre_serveur_test` / `rejouer_ventes.php`) : M8
  (location de véhicules, `vehicules.tarif_jour`) crédite **7073** « Locations »
  (nouveau rôle `PRODUIT_LOCATIONS` / `produitLocations`, présent au plan du PO),
  centre « Véhicules » ; M9 (tourisme, `circuits.prix`) crédite **7061** « services
  vendus » (le plan du PO n'a pas de compte dédié aux circuits), centre
  « Tourisme » ; la TVA des deux va sur **4432** (prestations). Ordre de la pièce :
  M4, M5, M8, M9. Comptes 7073, 7061 et 4432 **validés par le PO le 26/10/2026**
  (et modifiables : voir « Correspondance des comptes »).
- **Quantité** : un nombre de places (circuit) ou de jours (véhicule), au prix
  du catalogue local. Aucune sortie de stock (ni au poste ni au serveur) ;
  `annuler()` du serveur n'exige plus le point « bar » s'il n'y a pas de boisson.
- **Vente LIBRE de prestation** : ni `ventes` ni `lignes_vente` n'ont de colonne
  pour un contrat de location ou une réservation de circuit. Le comptoir ne crée
  donc, ne règle et ne lie rien : un contrat / une réservation déjà saisi ailleurs
  se règle par SA facture (M2), jamais ici — l'opérateur ne doit pas encaisser
  deux fois. Un lien exigerait une colonne `contrat_location_id` /
  `reservation_tour_id` sur `ventes` (schéma serveur ET poste) : non fait.
- **Séjour** : le panier d'une note de chambre ne porte toujours que M4 et M5
  (`modulesEncaissablesAuSejour`, `PosHeberges::MODULES_DU_SEJOUR`) ; la phrase
  `prestationRefusee` dit désormais « ne se portent pas sur la note de chambre ».
- **Droits** : le web exige M8 / M9 en écriture EN PLUS de M5 (`encaissementReel`,
  `GestionnaireVentes::modulesRequis`) ; le poste refuse dès l'ajout au panier
  plutôt que d'encaisser une vente que la synchronisation rejetterait
  (`MessagesVentes.moduleSansDroit`, RETIRÉ le 26/10/2026 avec les cartes : plus
  aucun écran n'ajoute M8/M9).

## Lien au stock des boissons, écrit sur le poste (26/10/2026)

Le PO ne parvenait ni à ENREGISTRER une boisson ni à la LIER AU STOCK. Deux
causes, une par couche : « Nouvelle boisson » n'offrait aucun sélecteur
d'article (la boisson naissait sans lien, que le serveur rejetait à l'envoi :
`article_id` requis) et `BoissonsApi.lierAuStock` refusait TOUJOURS
(`lienSansColonne`) alors que `cartes_boisson_local.unites_vendables` existe
depuis la v30.

- **Écriture** : « Nouvelle boisson » (Carte du bar), le formulaire « Ajouter
  boisson » du catalogue (création) et « Lier au stock » / « Modifier le lien »
  écrivent l'article ET son conditionnement (`BoissonsApi` -> `CatalogueDao`,
  seul écrivain, qui enfile `creation` ou `modification` avec `article_id` et
  `unites_vendables_par_unite_stock`). Les articles proposés viennent de
  `articles_local` (suivi permanent, non archivés) : `SelecteurArticleStock`.
  Les modales EXIGENT article et conditionnement ; l'API admet un article sans
  conditionnement (import, comme `CarteBoissonService::creer`), jamais un
  conditionnement sans article. Le conditionnement est un TEXTE décimal
  normalisé (`24`, `66.5`) ; `BoissonDistante.unitesVendables` n'est jamais
  effacé par une écriture qui ne le connaît pas (`Value.absentIfNull`).
- **Serveur** : `GestionnaireCartesBoisson` accepte désormais le
  conditionnement (création ET modification, règle de `LierBoissonAuStockRequest`
  : `numeric`, `gt:0`). Avant, il était ignoré et le serveur gardait le défaut
  du schéma (1) : un casier de 24 sortait entier à chaque bouteille vendue.
  La descente (`AligneurCatalogue._boisson`) le reprenait déjà.
- **Historique des ventes** : le journal `autoDispose` dépendant de
  `paniersProvider` est prouvé par `journal_apres_cloture_test.dart` (mutation :
  retirer l'un ou l'autre rougit) et de bout en bout par
  `parcours_boisson_vente_test.dart` (carte -> POS -> historique -> « −X en
  attente d'envoi »). Les autres causes (filtre de date par défaut, poste,
  session close, vente annulée, veille, fuseau) sont écartées par des cas.

## « Actualiser » : clic droit, F5, Ctrl+R (26/10/2026)

Demande du PO : sur les écrans du poste, le clic droit ouvre un menu à un item,
« Actualiser », qui relit l'écran courant depuis la base locale. Un seul endroit :
`core/navigation/actualisation_ecran.dart`, branché dans `CoquilleApplication`
(`ZoneActualisation` autour de la page ; l'écran de connexion/démarrage n'a pas le menu).

- **Action** : `actualisationEcranProvider.notifier.actualiser()` invalide les
  lectures (`invaliderLesLectures`) puis incrémente un compteur qui sert de
  `ValueKey` à la page (`KeyedSubtree`) : l'écran est reconstruit.
- **Critère des providers invalidés** : tout `FutureProvider` / `StreamProvider`
  VIVANT du conteneur (famille et `autoDispose` compris), hors `lecturesConservees`
  (`aucunCompteProvider`, `liberationBauxSyncProvider`). Aucune liste à tenir : un
  provider de lecture ajouté demain est couvert. Session, base, droit, thème,
  filtres (`Notifier`) ne sont jamais touchés ; l'utilisateur reste connecté.
  Le parcours des providers vivants passe par `getAllProviderElements`, interne
  à Riverpod (import `src/internals.dart`, avertissements levés en ligne) : le test
  rougit si une montée de version le retire.
- **Ce qui est perdu** : seule la saisie non enregistrée tenue en mémoire par la
  page. Une modale ouverte n'est jamais fermée et le menu comme F5 n'agissent
  pas tant qu'elle est ouverte (`ModalRoute.isCurrent`). Sur un champ de saisie,
  le clic droit reste celui du champ (détecté par `RenderEditable` sous le curseur).
- **Preuves** : `test/core/navigation/actualisation_ecran_test.dart` ; une ligne
  est écrite en base SANS invalider, puis « Actualiser » la fait apparaître.
  Mutation éprouvée : retirer `invaliderLesLectures` fait rougir 3 cas.

## Journaux de synchronisation du serveur : Réception et Envoi (26/10/2026)

L'écran web « Postes & Appairage » a trois onglets : Postes, **Réception** (ce que
le serveur a reçu de chaque poste par `POST /sync`) et **Envoi** (ce qu'il a mis à
disposition par `GET /referentiels`). Tables serveur : `journal_reception_synchronisation`
(une ligne par `uuid_operation` : issue acceptée / fusionnée / déjà reçue / signalée /
conservée / conflit / rejetée / erreur, motif structuré, cause en français, tentatives,
charge reçue, prise en charge ; purge à 90 jours, 365 s'il attend une correction, par
`NettoyerDeduplicationSyncJob`) et `journal_envoi_synchronisation` (livré par poste et
par table, tables non livrées faute de droit) ; `etats_postes_synchronisation` gagne le
dernier curseur rendu, la redescente demandée et le compte des 409 « génération périmée ».
Contrat pour le poste, rétro-compatible : un résultat `rejete` de `/sync` porte en plus
`code_motif` (`droit_manquant`, `compte_inactif`, `donnees_invalides`, `chevauchement`,
`entite_inconnue`, `entite_existante`, `regle_metier`, `stock_insuffisant`…) ; le poste peut
l'ignorer. « Redescendre depuis le début » pose une demande que `/referentiels` consomme
au prochain passage du poste : le curseur présenté est ignoré, le poste repart du début.
Corriger / Relancer rejouent l'opération par `SynchronisationService` sous un nouvel
`uuid_operation`, avec l'horodatage de saisie d'origine ; la version du poste n'est pas modifiée.

## Le poste est plus privilégié que le serveur (26/10/2026)

Décision du PO : tous les modules fonctionnent sur le poste, synchronisation active ou non. Audit complet, module par module, avec ce qui reste impossible hors ligne : `../docs/AUDIT_POSTE_AUTONOME.md`.

- **Interrupteur « Synchronisation activée »** (Paramètres → Synchronisation, Administrateurs) : clé `synchronisation_activee` de `poste.json` (absente = activée ; PAR POSTE, hors base, survit à la réinitialisation). Éteint, AUCUNE requête : `SyncManager` (envoi, descente, suivi de la demande du serveur), `ControleCoherence`, `ServiceAppairage`, `ServiceSuiviPostes` relisent le fichier avant chaque passage ; la file se remplit, partira dans l'ordre à la réactivation (qui lance un passage). Voyant gris « Synchronisation désactivée ». Preuve : `synchronisation_desactivee_test.dart` (transport qui lève). Un nouveau chemin réseau DOIT appeler `LecteurConfigurationPoste.synchronisationActivee()`. L'envoi SMTP n'est pas de la synchronisation et n'est PAS coupé par l'interrupteur (le courriel part directement du poste au relais SMTP ; hors réseau il reste dans la boîte d'envoi, voir « Envoi réel d'e-mails » plus bas) — testé : `boite_envoi_emails_test.dart`.
- **Source des états comptables** (`sourceEtatsFinanciersProvider`) : miroir du serveur si la synchronisation est active ET qu'il a reçu des écritures, sinon les écritures validées de CE poste. Jamais mêlées. Compte de résultat, bilan, six indicateurs du hub, Dépenses cumulées et série mensuelle du tableau de bord, Résultat net du pilotage, balance de M14, TAFIRE et notes annexes en dépendent. Grand livre et analytique se lisent toujours sur les pièces du poste. Confrontés au vrai serveur : `grand_livre_analytique_contre_serveur_test`, `etats_financiers_contre_serveur_test` (TAFIRE, notes), `depenses_cumulees_contre_serveur_test`.
- **Piège Riverpod** : `ref.read(fournisseurAutoDispose.future)` depuis un lecteur qui n'est pas lui-même `autoDispose` libère le `Ref` pendant l'attente (« Cannot use the Ref … after it has been disposed »). Les lecteurs (`lireDonneesEtats`, `lireSourceEtats`, `lireDonneesComptabilite`, `lireChargesDatees`) sont donc des FONCTIONS appelables hors fournisseur.
- **Piège de banc** : sous `flutter test`, `getApplicationSupportDirectory` ne se termine jamais (horloge simulée) ; `cheminConfigurationPoste()` rend un chemin temporaire quand `FLUTTER_TEST=true`, et `poste.json` se lit en E/S synchrones.
- **Numéro de compte** : UNE règle, `RegleNumeroCompte` (2 à 4 chiffres, `6056`), relue du serveur (`PlanComptableService::NUMERO_COMPTE_FORMAT`) par `creation_compte_hub_test`. Attention : 6056 existe déjà au plan du PO (invite, pas exemple libre).

## Le poste fait comme le web : prix, annulation de contrat, auteur, N° V- (26/10/2026, schéma v38)

Décision du PO : quatre manques de l'audit (`../docs/AUDIT_POSTE_AUTONOME.md`) sont portés. Schéma **v38**, 74 tables :
une table neuve (`historique_prix_carte_local`) et six colonnes NULLABLES, migration conditionnelle
(`PRAGMA table_info`, piège 3), curseur de descente oublié, fixture `_ajoutsParVersion[38]`,
`tablesAjouteesEnV38`, `migration_v38_poste_comme_le_web_test.dart` sur fichier réel.

- **Historique des prix** (bar ET restaurant) : la trace est un miroir de `historique_prix_carte`. Écrivains :
  `CatalogueDao.enregistrerBoisson` et `RestaurantDao` (`_enfilerPlat`, `modifierPrix`) via
  `HistoriquePrixCarteDao.tracer` (exige une transaction). Ce qui se trace (champs `prix_vente`,
  `prix_corrige_main`, ordre) est la fonction pure `changementsDePrix`, CONFRONTÉE au vrai serveur
  (`tool/carte/rejouer_historique_prix.php`, observateurs `CarteBoissonObserver`/`PlatObserver`). Le serveur
  est l'unique auteur de la trace : le poste ne la pousse PAS ; la trace locale (`recu_du_serveur = false`)
  est ADOPTÉE par la trace serveur équivalente à la descente (jamais doublée). Serveur : `historique_prix_carte`
  dans `CatalogueDescendantService::COLONNES`, `par` en login, restreint aux modules lisibles.
  Écran restaurant « Prix » (`modale_prix_plat.dart`) et « Historique des prix » : jetons `blade-refuse` levés.
  La réinitialisation « comme neuve » vide la table (testé, mutation éprouvée).
- **Annulation d'un contrat** : `contrats_location_local.statut` (null = actif). Écrivain unique
  `VehiculeDao.annulerContrat` (refus aux phrases du serveur, relues par PHP) ; part en
  `modification {statut: annule}` si le serveur détient le contrat (`GestionnaireContratsLocation::modifier`,
  rejeu accepté, tout autre champ refusé) ; la descente ne va que vers l'avant, et une annulation locale en
  file n'est jamais écrasée. Un contrat annulé libère RG-08 (défaut SERVEUR corrigé en chemin :
  `STATUTS_INACTIFS`), l'archivage d'un client et celui d'un véhicule. Pas de restriction Q3 (la PWA n'en a
  pas). KPI de la vue : calculés sur l'ensemble FILTRÉ par statut, répliqué tel quel (« 0 annulé(s) » avec le
  filtre par défaut). Signalé, non touché : l'état M14 « Locations » du serveur liste tous les contrats.
- **Utilisateur et poste du journal d'audit** : `operations_sync_local.auteur_login` / `poste_nom`, posés à
  l'enfilement par `AppDatabase.auteurEcriture` (câblé sur la session dans `baseLocaleProvider`) et recopiés par
  `renvoyer`. Poste = nom de la machine (la vue serveur montre une adresse IP : écart nommé). Avant la v38 : « — ».
- **N° `V-` et auteur d'une vente** : `paniers_local.numero_vente` / `auteur_login`. Le poste n'invente jamais
  un numéro (séquence du serveur) : il le pose à l'accusé du `POST /sync` (`SyncManager`,
  `PanierDao.regulariserNumeroVente`) ou à la descente de la vente ; avant, « — ». L'auteur est le login connecté
  à la clôture, ou le `par` du serveur. Le repli « numéro de facture » des ventes du rayon est supprimé.
- **Pièges** : l'aligneur CONSERVE un panier dont une opération attend (un test de descente doit marquer
  l'opération `synchronise`) ; une trace locale adoptée se prouve avec une date serveur ANTÉRIEURE, sinon le
  filtre `recuDuServeur` ne mord pas ; les libellés d'une modale se mesurent dans les fichiers qui CITENT la vue
  (les deux modales du bar citent aussi la vue du restaurant).

## Envoi réel d'e-mails (schéma v39, 26/10/2026)

Décision du PO du 26/10/2026 : « l'envoi réel d'e-mails DOIT ÊTRE IMPLÉMENTÉ EN POSTE ET WEB ». Détail et limites : `docs/AUDIT_POSTE_AUTONOME.md` §4 point 2.

- **Table `boite_envoi_emails_local`** (v39, neuve, migration conditionnelle, fixture `_ajoutsParVersion[39]`, `migration_v39_boite_envoi_emails_test.dart` sur fichier réel). **Écrivain unique : `BoiteEnvoiEmailsDao`** (aucune suppression). Clé d'idempotence UNIQUE `notification:<id du message>` ; statuts `en_attente` / `envoye` / `echec` (30 tentatives automatiques, repli ×2 de 5 min à 6 h, la MÊME politique que « Contactez l'éditeur ») / `annule` (message transmis à la main ou abandonné : ne part JAMAIS). `tentatives` ne compte que les connexions réellement tentées ; une configuration absente note la raison sans compter.
- **Expéditeur unique : `ServiceBoiteEnvoiEmails`** (`mailer`, transport injectable `TransportSmtp`, une instance partagée par le geste et la relance : `serviceBoiteEnvoiEmailsProvider`, relance `relanceBoiteEmailsProvider` démarrée par `main.dart`, pas par `main_demo.dart`). La configuration se lit à CHAQUE envoi par `LecteurSmtp` (clés SMTP de Paramètres + mot de passe de `poste.json`, jamais en base ni dans une cause d'échec : `expurgerSecret`). `envoye` n'est écrit QU'APRÈS l'accusé SMTP, dans la MÊME transaction que le passage du message M12 à « Envoyé par le système » (`NotificationsDao.marquerEnvoyeParLeSysteme`, seul chemin vers ce statut : le test « aucun geste de l'écran ne produit envoyé » reste vrai).
- **M12** : `NotificationsDao.detecter(emailsClients: …)` met le message ET son e-mail en boîte dans la même transaction (canal e-mail, adresse de `clients_local.email` valide, client non archivé) ; une détection ultérieure RATTRAPE les messages composés sans e-mail en boîte. « Envoyer » / « Renvoyer » (`envoyerMessageNotificationProvider`) résout l'adresse au geste, met en boîte puis tente tout de suite. Le canal e-mail est « branché » (`transportsLocauxProvider`) quand la configuration SMTP est COMPLÈTE (dérivé, relu), jamais écrit en dur. L'écran dit l'état vrai : « Tentatives d'envoi : n · Dernière erreur : … · Relances automatiques épuisées » (mots de la vue).
- **Piège rencontré** : `insertOrIgnore` de Drift rend le dernier identifiant inséré MÊME quand la ligne est ignorée — il ne dit pas si la clé existait ; lire l'existence avant d'insérer. Piège de test : une lecture de `poste.json` dans un `testWidgets` n'avance que par `tester.runAsync` + `pump` répétés (`laisserLesEntreesSorties`).
- **Serveur SMTP d'essai** : `test/features/transverse/support/serveur_smtp_essai.dart`, un vrai petit serveur sur socket locale (AUTH PLAIN/LOGIN, DATA, refus 535/554) — le moyen d'éprouver `mailer` de bout en bout sans réseau.
- **Hors périmètre, dit** : WhatsApp, Android et SMS ne partent pas (aucun contrat) ; seuls les déclencheurs détectés sur le poste (séjour demain, départ) ont une adresse.

## Clôture annuelle SYSCOHADA sur le poste (26/10/2026, schéma v40)

Décision du PO : « la clôture annuelle DOIT ÊTRE IMPLÉMENTÉE EN POSTE ET WEB ». Détail : `docs/AUDIT_POSTE_AUTONOME.md` §4 point 3, `docs/CLOTURE_EXERCICE_SYSCOHADA.md`.

- **Table `clotures_exercices_local`** (v40, 76 tables, migration conditionnelle, fixture `_ajoutsParVersion[40]`, `migration_v40_clotures_exercices_test.dart`). **Seul écrivain : `ClotureExerciceLocale`** (`comptabilite/data/`) : démarrer, reprendre la saisie, clôturer, rouvrir (comptable seul, motif >= 10 caractères). Les pièces `CL` et `AN` passent par `MoteurComptable` (jamais d'écriture directe, RG-11) ; comptes 131/139 via `compteDuRole`. Les journaux `AN`/`CL` sont masqués à la saisie manuelle.
- **Contrat de synchronisation (D246)** : le poste n'envoie aucune pièce. Chaque geste enfile, dans sa transaction, une demande `demandes_cloture_exercice` (création seule) ; le serveur (`GestionnaireDemandesCloture`, M10) rejoue `ClotureExerciceService` et passe SES pièces. Demande déjà satisfaite = acceptée. `AligneurCatalogue` garde la clôture locale tant que la dernière demande de l'année n'est pas acceptée.
- **Archive légale** (`ArchiveClotureLocale`) : `ecritures.csv`, `balance.csv`, `etats-cloture.pdf`, `manifeste.json` (empreinte SHA-256 du manifeste), ZIP « stored » en pur Dart (`core/fichiers/zip_stocke.dart`), CSV quoté comme `fputcsv` PHP. Dans `archives/` à côté de `poste.json`.
- **Preuves** : `cloture_contre_serveur_test` (vrai service, `tool/comptabilite/rejouer_cloture.php`), `demandes_cloture_contre_serveur_test` (vrai `SynchronisationService`, `valider_demandes_cloture.php`) ; ces scripts acceptent `TATACORA_BASE_ESSAI=tatacora_<x>_test`. 25 mutations éprouvées.
- **Écarts nommés** : résultat de clôture = pièces du poste seules (le serveur peut refuser, refus lu dans « À traiter ») ; pas de relevés bancaires ; PDF par le gabarit tabulaire commun ; archives hors sauvegarde de base ; lien « six étapes » non porté.
- **Pièges** : après une clôture, l'exercice par défaut devient N+1 — l'onglet épingle l'exercice consulté (`exerciceChoisiProvider`) ; un exercice sans pièce est « connu » par `anneesAvecClotureActive` ; une note « Sur ce poste » dans un littéral affiché est refusée par la garde (« Ici », ou une phrase métier).

## Les champs du web portés : véhicule, contrat, plat, guide (27/10/2026, schéma v41)

Décisions du PO D1 et D2 (« convertir en CRUD, même logique que le web ; le poste fait ce que le web fait + la synchronisation »). Détail : `../docs/INVENTAIRE_POSTE_LECTURE_SEULE.md` (A6, A7, A8, A10). Schéma **v41**, **76 tables** (aucune table neuve) : DIX colonnes NULLABLES, migration conditionnelle (`PRAGMA table_info`, piège 3), curseur de descente oublié, fixture `_ajoutsParVersion[41]`, `migration_v41_champs_du_web_test.dart` sur fichier réel depuis les versions 40, 38, 36, 30, 26 et 14.

- **Véhicule** (`vehicules_local`) : `annee`, `capacite` (les « Places »), `transmission`. Écrivain unique `VehiculeDao.enregistrerVehicule` (bornes et PHRASES du serveur : année de 1950 à l'an prochain, places de 1 à 99, transmission 255 caractères ; un paramètre `null` laisse la colonne, une transmission vide l'efface) ; part en création, ou en modification avec les seuls champs CHANGÉS. Serveur : `GestionnaireVehicules::modifier` accepte les trois champs (le web les saisit à l'édition).
- **Contrat** (`contrats_location_local`) : `numero` (`LOC-…`), `remise`, `acompte`, `montant`. **Le montant est FIGÉ à la signature** : tarif du jour × jours − remise, écrit une fois par `VehiculeDao.creerContrat`, JAMAIS recalculé au tarif courant ; le reste dû est la différence montant − acompte (jamais une colonne). Refus dans l'ordre du serveur (dates, véhicule, client, remise > brut, acompte > net, puis louable, pièce, permis, chevauchement), aux phrases `lte` de la vue. Le N° est celui de la séquence du serveur : `NULL` jusqu'à l'accusé (`SyncManager` → `VehiculeDao.regulariserNumero`) ou la descente — le poste n'en invente aucun. La remise n'est pas gardée par le serveur (ni par le web : il ne range que le montant net) : un contrat reçu d'ailleurs n'en a pas. **Anciens contrats : les quatre colonnes restent nulles, « — », jamais un chiffre déduit du tarif courant** ; la descente les comble avec les chiffres du serveur (là où la colonne est nulle seulement : le montant figé du poste n'est jamais réécrit). Écran Contrats : N° / Montant / Acompte / Reste dû (rouge si positif, « Soldé » si nul, « — » si inconnu) et ligne TOTAL à trois sommes (`null` si UN contrat actif est inconnu : une somme amputée est plausible et fausse) ; KPI « Reste à encaisser » calculé, « — » avec sa raison s'il manque un chiffre. L'état M14 « Locations » du poste somme le montant figé et NOMME les contrats sans montant.
- **Plat** (`plats_local.categorie`) : l'une des dix clés de `CategorieCarte` (registre relu de `CarteRestaurant::CATEGORIES`, clés ET libellés, par `champs_location_contre_serveur_test`). Saisie dans « Nouveau plat » (2e champ, comme la vue), colonne et filtre « Toutes les catégories » du CATALOGUE (la catégorie du plat, plus le type du menu), import M4 (colonne « Catégorie »). **Serveur** : `EnregistrerPlatRequest::CHAMPS_REFUSES` garde `categorie` pour l'API ; seul le chemin de synchronisation (`GestionnairePlats`) l'accepte, validée contre le registre fermé, toutes les autres validations gardées. ⚠ **Écart assumé** : la CARTE du restaurant (filtre, couverture, impressions) classe encore par type de menu, comme l'API ; la vue PWA la classe par la catégorie du plat — à porter séparément (les parités contre `CarteRestaurantService` sont à reprendre avec elle).
- **Guide** (`guides_local`) : `certification`, `tarif_jour` (francs entiers). Ils partaient déjà au serveur sans être rangés ; `TourismeDao.enregistrerGuide` les écrit, la descente les redonne (un tarif à fraction de franc se range inconnu, le guide n'est pas refusé).
- **Import** : M8 gagne « Année » (obligatoire), « Nombre de places », « Transmission » ; M4 gagne « Catégorie » (liste fermée) — les colonnes du modèle du serveur.
- **Descente** : `CatalogueDescendantService::COLONNES` gagne `plats.categorie` et `contrats_location.acompte` (véhicules et guides y avaient déjà leurs champs). `AligneurDocuments._vehicule` range une année `0` (poste d'avant, signalée au serveur) à `null`. Aucun aligneur n'enfile (balayage de la file dans `descente_champs_location_test`).
- **Preuves contre le VRAI serveur** : `tool/vehicules/rejouer_champs_location.php` (modèle de `rejouer_annulation_contrat.php`, `TATACORA_BASE_ESSAI=tatacora_<x>_test` accepté) pousse des documents hors bornes au vrai `SynchronisationService` et rend les phrases ; `champs_location_contre_serveur_test` confronte bornes, phrases, ORDRE des refus, montant net / acompte / reste dû et registre des catégories, puis pousse la FILE du poste (véhicule complet, contrat remisé, plat catégorisé, guide certifié) à `valider_charge.php` et relit ce que le serveur a rangé. Côté PHP : `VehiculesSynchronisationTest`, `CatalogueRestaurantSynchronisationTest`, `TourismeSynchronisationTest`, `ChampsPosteDescendantsTest`.
- **Pièges** : la descente rend `annee` et `capacite` en CHAÎNES (« 2022 »), à lire par `entierDepuisDecimal` ; `ClientsLocal` n'est pas synchronisé par `insert` direct : un test qui pousse une file doit AUSSI enfiler la création du client, sinon le serveur répond « client inconnu ».

## Le reçu en image d'une dépense (lot L4, 27/10/2026, schéma v42)

Décision D4 du PO (« convertir en CRUD, même logique que le web » ; un transport de fichier est accepté dans la synchronisation). La dépense joint un reçu comme l'écran web, et le fichier voyage.

- **Règle du web, mêmes phrases** : image reconnue à son CONTENU (jpg, png, gif, bmp, webp ; svg refusé), 400 Ko pile (`max:400`), « Le champ photo recu doit être une image. » / « Le fichier photo recu ne peut pas peser plus de 400 kilo-octets. ». Poste : `verifierRecu` (`depenses/domain/recu_depense.dart`) ; serveur : `RecuDepenseService::controler` (le validateur Laravel lui-même). `depenses_recu_contre_serveur_test` juge un corpus de 17 fichiers (dont PNG sans IHDR, « BM » + texte) par le VRAI PHP (`tool/depenses/rejouer_recus.php`) : mêmes verdicts, même empreinte.
- **Stockage** : jamais le blob dans Drift. Fichier dans `recus_depenses/<id>.<ext>` à côté de `poste.json` (`RecusDepensesLocaux`, écriture atomique `.tmp` + renommage, un nom ne sort pas du dossier). **v42** : six colonnes NULLABLES sur `depenses_local` (`recu_nom`, `recu_sha256`, `recu_taille`, `recu_type`, `recu_statut`, `recu_cause`), migration conditionnelle, fixture `_ajoutsParVersion[42]`, `migration_v42_recus_depenses_test` sur fichier réel. Le dossier est hors de la sauvegarde de la base.
- **Écrivain unique** : `DepenseDao` (`enregistrer(recu:)`, `accuserRecu`, `refuserRecu`, `retenirReferenceRecu`, `retenirFichierTelecharge`) + le miroir `aligneur_documents.dart` (qui ne fait qu'appeler le DAO). Un fichier dont la dépense n'est pas écrite (pièce refusée, panne) est retiré.
- **État vrai** (`StatutRecu`) : `en_attente` à la saisie ; `envoye` UNIQUEMENT sur l'accusé du serveur (200 du dépôt) ou la référence redescendue avec la MÊME empreinte ; `refuse` + cause (phrase du serveur) ; `du_serveur` (référence d'un autre poste, fichier non téléchargé). L'écran dit « en attente d'envoi » / « envoyé » / « refusé » (infobulle = cause).
- **Transport** : interface `TransportFichiers` à part (`/sync` reste du JSON ; les faux transports de la file ne changent pas). `EnvoiRecusDepenses` est branché sur le passage de `SyncManager` (après la file, avant la descente) : même interrupteur `synchronisationActivee()`, même génération, mêmes 401/403/409 consignés. Un reçu ne part qu'après l'accusé de la CRÉATION de sa dépense ; 404 `depense_inconnue`, 5xx, injoignable = il attend ; tout autre refus de fond est définitif. Rejeu : même fichier, même empreinte, le serveur répond `rejeu` et c'est un accusé.
- **Serveur** : `PUT /api/v1/sync/depenses/{depense}/recu?poste_id=` (corps = fichier brut, `X-Recu-Sha256`), `GET` du même chemin (à la demande, jamais en masse). Droits de la dépense : écriture M10 pour déposer, lecture pour télécharger ; poste du jeton ; la dépense doit venir du même poste (ou, trace purgée, du même compte) ; taille annoncée refusée avant lecture (413) ; idempotent par SHA-256 ; un autre fichier sur une dépense qui a déjà un reçu = 409. Journal de réception : table `recus_depenses`, cause lisible (`synchronisation_journal.motifs.recu_*`), sans « à traiter » (rien à rejouer côté serveur). Migration `2026_10_27_100000` : `recu_sha256`, `recu_taille`, `recu_type` NULLABLES (l'écran web les pose aussi ; un reçu web d'avant garde `null`, l'empreinte est alors calculée au téléchargement). La descente porte `donnees.recu` = `{sha256, taille, type}`, jamais le chemin.
- **Téléchargement** : `TelechargementRecuDepense`, au clic sur « reçu » seulement ; fichier du poste d'abord, sinon requête (interrupteur relu, démonstration/non appairé/refusé/autre serveur = une phrase, aucune requête) ; vérifie image, 5 Mo, empreinte de la référence ET de l'en-tête avant de ranger.
- **Écart nommé (piège 13)** : l'aide de la vue (`champ_recu_aide`, « L'image est réduite avant enregistrement… une douzaine… ») promet une réduction que rien ne fait (la vue le dit elle-même en commentaire). Remplacée par la phrase vraie (400 Ko, rangé sur le poste puis envoyé) ; test source (rougit si la vue est corrigée) + test du code rendu. L'export CSV/PDF n'a pas la colonne « Pièces », comme celui du serveur.
- **Pièges** : `corps?['code']` dans une garde `when` ou un ternaire est lu comme `? :` (calculer avant) ; `Request::call` de Laravel ignore `withToken` (passer `HTTP_AUTHORIZATION`) et le garde Sanctum mémorise l'utilisateur d'un test (`forgetGuards()`) ; l'aligneur CONSERVE la ligne d'une dépense tant qu'une opération l'attend (accuser la création avant de tester la descente) ; ne jamais `dart format` un dossier partagé.
- **Non fait / assumé** : pas de réduction d'image ; pas d'essai Dart ↔ `artisan serve` de bout en bout (le transport HTTP réel du poste est éprouvé contre `MockClient`/faux, le contrôleur contre le vrai Laravel en PHP) ; reçu non joignable après coup (la dépense est immuable, comme au web).


## Lots L0-L2 : verrou, bulletin A4, modales d'ouverture, restauration d'archives (27/10/2026, sans schéma)

Détail : `../docs/INVENTAIRE_POSTE_LECTURE_SEULE.md` §9. Décision du PO : « convertir en CRUD, même logique que le web ».

- **A11** : l'archivage des employés passe par `core/rbac/regle_archivage.dart` (administrateur / super_admin OU bascule), relue à chaque geste (D272).
- **A1 Verrou de session** : `features/auth/domain/verrou_session.dart` + `voile_verrou_session.dart`, minuteur d'inactivité, limiteur d'essais rejoué contre `VerrouSession` (`tool/session/rejouer_verrou.php`). Horloge, stockage et vérificateur injectables ; un test de widget démonte l'arbre avant la vérification des minuteurs.
- **A3 Bulletin de paie A4** : `features/rh/impression/bulletin_paie_a4.dart` (gabarit commun `entete_a4.dart`, `texteTicket`) ; « Imprimer » / « PDF » sont des actions injectables. Classé dans `documentsClient` de `pdf_directive_test` (document REMIS, pas de visas).
- **A2 Modales d'ouverture** : `features/alertes/{domain,presentation}/modales_ouverture.dart`, `HoteModalesOuverture` dans la coquille, déclenché par `ouvertureEnAttenteProvider` (posé à la connexion). Stock critique, puis départs et créances ; check-out via `SejourDao.checkoutDuSejour`, relance tracée ; droits M1/M3. Preuve : `tool/alertes/rejouer_modales_ouverture.php`. Piège : `etapesOuvertureProvider` n'est PAS autoDispose (libéré pendant `.future`).
- **A4 Restaurer** : `features/transverse/{domain/registre_archives,data/archives_poste}.dart`. Registre DÉRIVÉ (unités `actif=false`, véhicules `hors_service`), « archivé le/par » lu de `operations_sync_local`, aucune table d'archives. Restaurées = restauration précédée d'un archivage connu, plafond 100. Preuve : `tool/transverse/rejouer_archives.php`. Écarts : archives d'un autre poste absentes ; « — » sans opération locale. A5 (purge) : voir « Purge définitive » plus bas.
- **Pièges** : basenames identiques (domaine/présentation) = sauvegardes de mutation écrasées ; ne pas lancer `dart format` sur de larges dossiers.

## Comptes du plan et pièces saisies à la main : D246 ROUVERT (28/10/2026, schéma v44)

Décision du PO du 28/10/2026 : « OUI » pour rouvrir D246 sur deux points (le poste fait ce que le web fait + synchronisation). Détail : `../docs/INVENTAIRE_POSTE_LECTURE_SEULE.md` §10 (A12, B4, D6). D246 reste vrai pour tout le reste : le poste n'envoie jamais la pièce d'un module (vente, dépense, règlement, clôture) ni une pièce descendue ; le serveur est le seul à passer ces pièces-là.

- **Compte** : `MoteurComptable.creerCompte` enfile (dans sa transaction) une `creation` `plan_comptable` (`chargeCompte` : numéro, libellé, nature). Serveur `GestionnairePlanComptable` (M10, création seule) rejoue `PlanComptableService::creerCompte` (nouveau paramètre `id` optionnel) : même identifiant = rejeu ; numéro déjà pris avec MÊME libellé et MÊME nature = fusion (`fusionne_avec`), sinon refus « Le compte … existe déjà » (À traiter). Le web n'a aucune modification de compte : création seule. Descente `TableDescendue.planComptable` (après `exercicesComptables`, avant `ecrituresComptables`) : `AligneurCatalogue._compteDuPlan` ajoute un compte absent (clé = numéro), n'en réécrit JAMAIS un (`ComptabiliteDao.insererCompteDescendu`, insert-or-ignore), n'enfile rien ; classe ≠ 1er chiffre, nature hors registre, numéro mal formé = refus.
- **Pièce** : `MoteurComptable.saisirPiece(demande, valider:)` (appelé par la seule modale « Nouvelle écriture ») passe la pièce, l'inscrit dans `pieces_saisie_local` (écrivain unique, identifiant d'origine) et enfile la SOURCE `pieces_saisie` (`chargePieceSaisie` : journal, date, libellé, statut `brouillon|validee`, lignes en centimes, centre par son LIBELLÉ — les identifiants de centre du poste ne sont pas ceux du serveur). `passer` / `passerEtValider` restent ceux des modules et n'enfilent rien. Serveur `GestionnairePiecesSaisie` (M10, création seule, table `pieces_saisie` = document source) rejoue `PasserEcritureService` aux règles de `Hub::enregistrerPiece` (mêmes noms de champ donc mêmes phrases : journal connu et non réservé CL/AN, date, libellé, ≥ 2 lignes, compte du plan, débit XOR crédit, équilibre, exercice ouvert ou en clôture, RG-12) et passe SA pièce ; `ecritures_comptables.piece_origine_id` (migration `2026_10_28_100000`) porte l'identifiant du poste sur chaque ligne (idempotence + reconnaissance).
- **Pas de double comptage** : les états lisent UNE source (miroir `ecritures_serveur_local` si reçu, sinon les pièces du poste — voir `AUDIT` §2), jamais les deux. La pièce redescendue arrive dans le miroir avec `piece_origine_id` ; `ComptabiliteDao.piecesSaisiesNonReprises` (NOT EXISTS sur l'origine) la reconnaît. Le poste ne renvoie jamais une pièce descendue : celles-ci n'entrent que dans le miroir.
- **Ordre** : file du poste = ordre d'écriture (le compte est enfilé avant la pièce qui le cite) ; registre serveur `plan_comptable`, `pieces_saisie` avant `immobilisations` ; descente plan avant écritures (tests `plan_pieces_saisie_poste_test`, `RegistreGestionnairesSynchronisationTest`, `EcrituresDescendantesTest`).
- **Preuves** : `plan_pieces_contre_serveur_test.dart` (vrai PHP par `tool/comptabilite/rejouer_plan_et_pieces.php`, `TATACORA_BASE_ESSAI` : pièce identique au centime, numéros, origine, redescente), `PlanEtPiecesSaisieSynchronisationTest`, `migration_v44_pieces_saisie_test.dart` (fichier réel, `_ajoutsParVersion[44]`). Mutations tuées : saisirPiece sans enfilage / sans validation / sans marquage, rôle admis, aligneur qui réécrit, reconnaissance d'origine, validation serveur, origine non posée, journal réservé, fusion sans nature, doublon fondu, identifiant du poste perdu.
- **Écarts assumés** : une pièce saisie avant la v44 n'est ni marquée ni envoyée ; un brouillon du poste reste brouillon au serveur (aucune validation différée nulle part) ; une pièce validée non encore reprise n'est dans aucun état synchronisé (le bandeau de provenance compte l'opération en attente) ; interrupteur « Synchronisation activée » éteint : rien n'est enfilé (`enfiler` rend `null`). Les 3 écarts du comparateur Blade (`import-export` restaurer/purge) viennent du lot A5, pas de ce lot : aucun libellé n'a bougé ici.
- **Pièges** : `SynchronisationService` lit chaque table du registre sous son nom et son `id` : un gestionnaire sans table physique (`pieces_saisie`) plante à la lecture. La fixture `_ajoutsParVersion` exige une entrée par version (43 est celle d'A5). Dans un arbre partagé, ne jamais écrire `open(p,'w').write(f(open(p).read()))` (tronque avant de lire).

## Purge définitive d'une unité ou d'un véhicule archivé : A5 (lot L5-A5, 28/10/2026, schéma v43)

Décision D5 du PO (« OUI »). Détail : `../docs/INVENTAIRE_POSTE_LECTURE_SEULE.md` §11.

- **Protocole** : `TypeOperationSync.suppression`, REGISTRE FERMÉ (`TableSynchronisee.accepteSuppression` : `unites_hebergement`, `vehicules`) ; un test relit les gestionnaires PHP (`accepteSuppression()`). `OperationsSyncDao.enfiler` refuse toute autre table et un corps vide (le serveur exige un tableau non vide : `{libelle}`). Serveur : `SynchronisationService::traiterSuppression` (super_admin puis écriture PARAM, idempotent, `deja_supprime`), `GestionnaireUnitesHebergement/Vehicules::supprimer` -> `purger` des services de parc.
- **Écrivains uniques** : `ParcDao.purger` / `VehiculeDao.purger` (verrous dans l'ordre et aux phrases du serveur, `delete` + `enfiler` dans UNE transaction) ; descente : `retirerUnitePurgeeAilleurs` / `retirerVehiculePurgeAilleurs` (rendent `false` si une saisie locale cite l'élément ; n'enfilent rien). `AligneurCatalogue._suppression` : opération en attente ou saisie rattachée -> `ConserveLocalement` (dit au journal de réception), sinon retrait. `ElementCatalogue.supprime` (JSON `supprime: true`, `donnees` vide ou `[]`) n'est admis que pour ces deux tables.
- **Serveur, descente** : `suppressions_synchronisation` (écrite par les DEUX `purger`, donc aussi par l'écran web), curseur `suppressions` de `CatalogueDescendantService`, lue seulement pour les tables dont le poste lit le module.
- **Écran** : corbeille `ie-archive-purger-<id>` (super_admin seul, `estSuperAdmin` de `regle_archivage.dart`), `_ModalePurge` (`ie-modale-purge`, refus affiché DANS la modale), `purgerArchiveProvider` (rôle, puis droit PARAM, relus au geste). Jeton `#modale:import_export.purge_titre` levé, `classification-exemptions.json` et dette Blade resserrées (`--figer-dette` : progrès réel).
- **v43** : `elargirTypesOperationsSync` (`lib/core/database/`), conditionnel, copie avant abandon, `seq` reporté, index recréés ; fixture `_ajoutsParVersion[43]` + `_retrecirTypesOperations` (la migration travaille dans chaque fixture qui la traverse) ; `migration_v43_suppression_operations_test`. Piège : ne jamais recréer `operations_sync_local` autrement (donnée non synchronisée = seule copie).
- **Preuves** : `tool/transverse/rejouer_purge.php` (vrai composant `ImportExport` + `RegistreArchivesService`, 16 éléments, mêmes verdicts et phrases), `tool/sync/valider_charge.php` (paramètre `role`) pour la file du poste, `PurgeSynchronisationTest` (serveur), `archives_purger_test`, `purge_descente_test`. Mutations tuées : verrou « cité », « fin aujourd'hui », super_admin, bouton, libellé, conservation de la saisie locale, registre fermé, report de `seq`, index.
- **Écart assumé** : purge refusée par le serveur après l'effacement local -> l'élément reste effacé ici jusqu'à « Redescendre depuis le début » ; la ligne rejetée est dans « À traiter ».
- **Tests d'écran** (même lot) : `modales_champs_location_test` (Places / Année / Transmission, Remise / Acompte / Reste), `modale_plat_categorie_test`, `import_categorie_plat_test` (M4 contre le vrai `ControleImportService`, `rejouer_import_m4.php`).

## Pièces saisies à la main : états, refus, anciennes pièces (lots A1, A2, A3, 28/10/2026, sans schéma)

- **A1** : quand le miroir `ecritures_serveur_local` est la source, `lireDonneesEtats` (compte de résultat, bilan, six indicateurs, équilibre, M14, pilotage) et `lireChargesDatees` (tableau de bord) y AJOUTENT les écritures VALIDÉES des pièces saisies à la main non reprises (`ComptabiliteDao.ecrituresPiecesManuellesNonReprises` / `chargesPiecesManuellesNonReprises`). Source des numéros : pièces marquées dont l'identifiant d'origine n'est pas dans le miroir (NOT EXISTS) ∪ anciennes pièces non marquées. La pièce redescendue est reconnue par son origine : jamais deux fois. Les pièces des modules ne s'ajoutent pas. Bandeau (`compta-etats-pieces-manuelles`) : combien de pièces locales sont comptées en attendant le serveur.
- **A2** : une pièce refusée (`operations_sync_local` rejetée, table `pieces_saisie`) n'est pas dans le miroir, donc reste comptée ; le bandeau (`compta-etats-piece-refusee-N`) donne le libellé, le motif et dit « validée, immuable et COMPTÉE » ; « À traiter » ajoute `notePieceSaisieRefusee`.
- **A3** : aucun schéma. La MARQUE est la ligne de `pieces_saisie_local` (écrivain unique : `MoteurComptable.envoyerAnciennesPieces`, une transaction, marque + enfile ; interrupteur éteint = marque et enfile, rien ne part). Sont proposées les pièces des journaux hors `VTE/CAI/BQ` (modules) et `CL/AN`, non marquées, ≥ 2 lignes, équilibrées, un seul journal/exercice/statut/date, sans contre-passation (ni subie), non citées par une dépense ou une réservation, exercice non clôturé ; au moindre doute elle n'est PAS proposée (reste comptée au poste). Libellé de la pièce = celui de sa première ligne (le poste n'a pas gardé le libellé de pièce). Geste dans l'onglet « Passer écriture » du hub (administrateur, super_admin, comptable), confirmation avec nombre et total.
- **Preuves** : `pieces_manuelles_non_reprises_test.dart` ; mutations tuées : ajout au miroir retiré, reconnaissance d'origine inversée, `VTE` retiré des journaux de modules, exercice clôturé non écarté. Piège : le fixture `etats_financiers_autonomes_test` passait une pièce « Achat » en journal `ACH` par `passerEtValider` ; `ACH` n'est écrit par aucun module, la pièce serait vue comme ancienne saisie manuelle : fixture passée en `CAI`.
- **Limites assumées** : contre-passer une pièce saisie à la main déjà envoyée n'est pas envoyé (comme avant) ; le test de parité PHP des anciennes pièces réutilise la même charge `pieces_saisie` que `plan_pieces_contre_serveur_test`.


## Locations sans annulés, archivage du jour de restitution, carte par catégorie du plat (lots B1, B2, C1, 28/10/2026, sans schéma)

Décision du PO : « OUI, appliquer les deux corrections du PRD et porter la catégorie du plat jusqu'à la carte du restaurant ».

- **B1** : `EtatLocations` (serveur) exclut `statut = annule` des lignes, du nombre et du montant ; son commentaire périmé (« NI statut ») est corrigé. `apercuLocations` (poste) fait de même et dit « N contrat(s) annulé(s) exclu(s) de l'état. » (R5). La case « Inclure les contrats annulés » + colonne Statut (P1/R4) n'est PAS faite : elle changerait les colonnes de l'état, donc la vue et le comparateur. Gardes : `EtatLocationsAnnulesTest` (PHP) ; côté Dart la parité ci-dessous.
- **B2** : règle unique `date_fin >= aujourd'hui` ET `statut != annule` (le jour de restitution engage encore). `VehiculeDao.archiverVehicule` passe de `isAfter(jour)` à `!jourDe(fin).isBefore(jour)`, message de refus inchangé. Le test `vehicule_dao_test` « un contrat passé n'empêche plus d'archiver » encodait l'ancienne règle (archivage le 15 pour une fin le 15) : il refuse maintenant le 15 et accepte le 16.
- **Parité contre le vrai PHP** : `tool/vehicules/rejouer_archivage_et_locations.php` (modèle de `rejouer_annulation_contrat.php`, horloge au 21/10/2026, quatre véhicules : fin hier / aujourd'hui / demain / annulé) rend `ParcVehiculeService::contratsEngages` et `EtatLocations` ; `archivage_et_locations_contre_serveur_test.dart` confronte l'archivage (refus et phrase) et l'aperçu (nombre, montant, lignes). Mutations tuées : `isAfter` rétabli, filtre des annulés retiré.
- **C1** : la carte du restaurant (filtre « Toutes les catégories », couverture, colonne Catégorie, CSV, PDF, fiche des prix) classe par `plats.categorie` (les dix de `CategorieCarte`), plus par `menus.type`. `PlatCalcule.menuType` devient `categorie` (nullable) ; `LigneCarteRestaurant.categorieBrute` vaut la clé du plat, `''` sans catégorie ; le filtre et son fournisseur portent `CategorieCarte`. **Couverture** comme `EcranDeCarte::couverture` : les dix catégories du registre dans son ordre, MÊME VIDES (taux `null`, « — » : un taux de zéro serait une mesure inventée, écart avec le web qui écrit 0 %), puis les clés hors registre triées. **Fiche des prix** (`EtatCarteRestaurant.groupesDeLaFiche`) : ordre du registre, puis hors registre, une catégorie sans plat tarifé n'est pas imprimée. **Plat sans catégorie** : groupe « Autres » (`libelleSansCategorie`) ; le web le range sous la clé vide à l'intitulé VIDE, une cellule sans mot ne se lit pas, et ce mot était déjà celui de la fiche des prix. Jamais une des dix devinée.
- **Parité C1** (`carte_contre_serveur_test`) : l'API (`CarteRestaurantService`) classe toujours par type de menu. Le test donne au script un menu par catégorie de plat (`type` = `plats.categorie`, vide si absente) : ce que le serveur range sous « type » EST alors la catégorie du plat, et les comptes par catégorie présente, le filtre et la somme des groupes sont confrontés ; l'ordre du registre est vérifié côté poste (le registre lui-même est relu du serveur par `champs_location_contre_serveur_test`). Les plats du balayage portent une catégorie sur quatre sur cinq, une sur cinq n'en a pas. Mutations tuées : registre retiré de la couverture, rang du groupe de la fiche des prix.
- **Cliquet d'emplacement** `restaurant/carte` figé 42 -> 52 : progrès réel (les dix options de la liste de catégories sont celles de la vue). `--figer-dette` du comparateur non touché (PASS inchangé).
- **Écarts restants** : la modale de détail d'un plat (`modale_detail_plat`) et la colonne « Menu » du catalogue lisent encore le type du menu porteur (hors périmètre carte) ; l'API du serveur n'est pas modifiée (l'écart « elle classe par type de menu » reste vrai de son côté).


## Démarrage résilient (lots E1, E2, E3, 28/10/2026, sans schéma)

- **E1 (R1)** : `lib/core/demarrage/` (`journal_demarrage.dart`, `demarrage_resilient.dart`, `textes_demarrage.dart`) ; mesures dans `core/theme/mesures_ecran_panne.dart` (l'écran n'emploie aucune taille de texte : thème Material, donc rien à classer dans `echelle_contenu_test`). `main()` = `runZonedGuarded` + `FlutterError.onError` + `PlatformDispatcher.onError`, fenêtre d'attente tout de suite, puis `ouvrirBaseDuPoste` (force `SELECT 1` : la migration n'est plus paresseuse) et seulement ensuite l'application, avec la base passée par `baseDemarrageProvider` (null ailleurs : tests et démo inchangés, `main_demo.dart` non touché). Une erreur après l'ouverture est journalisée sans remplacer l'application. Piège : le journal est écrit en SYNCHRONE avec `flush`, sinon un processus tué garde un journal vide. Tests : `test/core/demarrage/` ; mutations tuées : délai de 45 s, affichage de la panne, expurgation.
- **E2 (R2)** : `lib/core/database/reconcilier_schema.dart` (`reconcilierSchema`, `ecartRapide`), appelée en dernier dans `onUpgrade` et, dans `beforeOpen`, quand la version est courante mais que `ecartRapide` (noms de tables, index, déclencheurs, nombre de colonnes par table, en une requête chacun) trouve un écart. Placée AVANT `PRAGMA foreign_keys = ON` (un `ADD COLUMN ... REFERENCES` est refusé clés actives). Colonne `NOT NULL` sans défaut : `DEFAULT` explicite (`''`, `x''` ou `0`) ajouté à la définition générée. Jamais destructive : table et colonne en trop laissées, journalisées (« LAISSÉS »). Piège : `ecartRapide` appelé sur une base fichier non encore ouverte rend `false`, car son premier accès déclenche l'ouverture, donc la réconciliation ; le test du contrôle rapide travaille sur une base déjà ouverte. Test : `test/core/database/reconciliation_schema_test.dart` ; mutations tuées : appel dans `onUpgrade`, appel dans `beforeOpen`, journal, `creerDeclencheursComptables`.
- **E3 (R3)** : `tool/migration/extraire_schemas_anciens.dart` (git log -S sur `schemaVersion`, `git archive` de `lib/core/database` + `environnement.dart` dans un dossier temporaire hors dépôt, `build_runner`, dump de `sqlite_master` ; ~1 min 45 par version, `dart run tool/migration/extraire_schemas_anciens.dart [versions]`). Dumps réels dans `test/fixtures/schemas_anciens/v24..v40, v42, v44.sql` (19 fichiers, ~530 Ko). **Le dépôt est né le 14/10/2026 à la v24** : v10, v14, v20 n'ont aucun commit, et aucun commit n'a porté v41 ni v43 (40 -> 42, 42 -> 44) : exceptions NOMMÉES et datées dans le test, qui échoue si un dump apparaît sans que l'exception soit retirée. Test `migration_depuis_anciens_schemas_test.dart` : reconstruit un fichier depuis chaque dump, sème des lignes typées (plus deux opérations de file d'envoi réalistes), ouvre avec le code courant, compare tables/colonnes (nom, type, NOT NULL, défaut, clé)/CHECK/index/déclencheurs à une base neuve, et compte les lignes. **Écart RÉEL trouvé** : la base réelle v44 (commit 9696788, avant que la copie de la v43 existe) gardait l'ancien `CHECK (type IN ('creation','modification'))` de `operations_sync_local` — `from < 43` ne rejoue jamais pour elle, et `suppression` aurait été refusé. Correction : `reconcilierSchema` rejoue `elargirTypesOperationsSync` (conditionnel, copie intégrale) et `ecartRapide` le détecte. Les CHECK n'étant pas dans `table_info`, la comparaison lit aussi le SQL des tables. Mutations tuées : migration `from < 30`, appel de la réconciliation, `elargirTypesOperationsSync` dans la réconciliation. Les paliers sautés (v26 -> courant) et la copie de v43 (depuis v42 et v44 réelles) sont couverts. Piège : `.g.dart` n'est pas versionné, d'où `build_runner` dans l'extraction.

## Case « Inclure les contrats annulés » (R4/R5) et reçu de dépense réduit au lieu d'être refusé (28/10/2026, sans schéma)

Deux décisions du PO ; le schéma Drift ne change pas (v44 inchangée par ce lot).

- **R4/R5, état M14 « Locations »** : filtre `inclure_annules` (web : propriété `EtatsStudio::$inclureAnnules` liée à la case, `#[Url(as: 'annules')]`, pas une action Livewire ; poste : `inclureAnnulesEtatsProvider`, case dans l'en-tête d'aperçu, état « Locations » seul). **Décochée (défaut) : annulés exclus, état inchangé** (6 colonnes). **Cochée** : colonne « Statut » (`Actif`/`Annulé`, `vehicules.pwa.contrat_*`), les annulés sont listés **À PART, après tous les actifs**, avec une cellule « Montant » **vide** (« — ») : un annulé n'entre JAMAIS dans « Contrats » ni « Montant total » (totaux identiques case cochée ou non). La **période dit** « contrats annulés exclus » / « contrats annulés inclus, non comptés dans les totaux » (`etats_m14.locations.annules_*`, la dernière clé du corps de `periode()` reste `periode_toutes` pour `exporter_registre.php`). Libellés : `pwa.etats.inclure_annules`, `etats_m14.locations.col_statut`. Preuves : `EtatLocationsAnnulesTest`, `EtatsPwaTest` (case seulement sur « Locations »), parité contre le vrai PHP `rejouer_archivage_et_locations.php` (cas décoché ET coché, cellule par cellule, base privée `tatacora_recu_test` créée puis DROP). Le poste n'a toujours **aucun export d'état M14** (aperçu seul, directive du 31/08/2026) : « aperçu/export » = aperçu.
- **Reçu de dépense** : une image de plus de 400 Ko est **réduite, jamais refusée pour son poids**, à la saisie web (`RecuDepenseService::preparer`, GD natif ; Intervention absent) comme sur le poste (`reduction_recu.dart`, package `image` déjà dans l'arbre via `pdf`, déclaré direct dans `pubspec.yaml`, isolat). **Règle commune** (constantes confrontées au PHP) : ≤ 400 Ko = octets d'origine gardés ; sinon décodage, orientation EXIF, fond blanc, grand côté ≤ 2048 px, JPEG à la 1re qualité de `[85,75,65,55,45,35]` qui tient, sinon dimensions × 0,8 jusqu'à 64 px. Reste refusé : vide, non-image (phrase du validateur), **illisible** (`depenses.recu_illisible`). La **porte de dépôt** (`PUT /sync/.../recu`, `controler`, `verifierRecu`) garde sa borne de 400 Ko : le poste dépose l'image déjà réduite, donc ≤ limite serveur. PDF : non concerné (le reçu de dépense n'accepte que des images). Les octets diffèrent d'un encodeur à l'autre ; décision, type, borne et dimensions (plafond) sont confrontés par `depenses_recu_contre_serveur_test`.
- **Aide du champ** : `champ_recu_aide` devient vraie (« L'image est réduite automatiquement avant enregistrement si elle pèse plus de 400 Ko. ») ; la 2e phrase du prototype (« une douzaine ») est retirée. L'ancien écart du lot L4 (piège 13) est soldé, son test remplacé. Comparateur Blade : progrès réel, `plancher-taux.json` 91,33 -> 91,34.
- **Tests qui épinglaient le refus, réécrits** : `recu_depense_ecran_test` (fichier lourd réduit et rangé), `ecran_depenses_test` (aide), `depenses_recu_contre_serveur_test` ; ajoutés : `reduction_recu_test`, `recu_depense_dao_test` (réduit / illisible), `RecuDepenseReductionTest`, `DepensesEcritureTest`.
- **Limites** : transport web (Livewire 12 Mo, `upload_max_filesize`) non relevé ; orientation EXIF éprouvée sur JPEG synthétiques ; WebP animé : première image.


## E-mail facultatif des employés et des comptes (28/10/2026, schéma v45)

Décision du PO : un champ « E-mail » FACULTATIF dans la fiche employé (RH) et dans le compte, au web et au poste, puis les notifications e-mail existantes vers ces adresses.

- **Serveur** : migration `2026_10_28_200000_ajouter_email_aux_employes_et_utilisateurs` (`employes.email`, `utilisateurs.email`, NULLABLES, conditionnelle, sans index ni unicité). Règle unique `App\Shared\Mail\Support\AdresseEmailFacultative` (trim + minuscules, `nullable|email:filter|max:255` + `not_regex` guillemets/crochets) ; `EmployeService` normalise ; `GestionnaireEmployes` (création et modification) la rejoue, une charge SANS la clé conserve l'adresse, `null` l'efface ; `CatalogueDescendantService::COLONNES['employes']` descend `email`.
- **Web** : fiche employé de `Rh\Paie` (champ « Email » = `pwa.profil.email`, sous Poste/Service) ; « Mon profil » : le champ « Email » devient éditable et « Enregistrer les informations » (`pwa.profil.enregistrer_infos`) est rendu (`MonProfil::enregistrerInformations`, compte courant seul, hors module : inscrite dans `PwaActionsReluesTest` et `PwaEcritureAutoriseeTest`). Il n'existe AUCUN écran web de création de compte : « Mon profil » est le seul formulaire de compte. `TransversePwaTest` admet `emailSaisi` sur `mon-profil` (liste fermée relue). Phrases dans `rh_pwa.php` (`email_invalide`, `email_enregistre`) : `pwa.php` non touché.
- **Poste v45** : `employes_local.email` et `utilisateurs_local.email` (NULLABLES, `from < 45` conditionnelle sur `PRAGMA table_info`, curseur de descente oublié, `_ajoutsParVersion[45]`, 77 tables inchangé). `AdresseEmailFacultative` (Dart, `core/format`) rejoue la règle ; l'e-mail employé part dans `chargeEmploye` (toujours présent, `null` = effacé) et descend par l'aligneur (qui n'enfile pas) ; l'e-mail du compte reste LOCAL (les comptes ne se synchronisent pas). UI : fiche employé (`modales_paie`), « Nouveau compte » (`modales_comptes`), « Mon profil » (champ + bouton, `ComptesUtilisateursDao.enregistrerEmail`).
- **Notifications** : `bulletin_disponible` vise l'e-mail du salarié (`BulletinDisponibleDetecteur`) ; `echeance_vps` vise le premier compte `comptable` ACTIF, par identifiant, qui a une adresse (`EcheanceVpsDetecteur`, une seule adresse par message). Sans adresse : message composé, aucun envoi, aucune erreur. Les autres déclencheurs (séjours, restitution) restent adressés aux clients. Le poste ne détecte toujours que `sejour_demain`/`sejour_depart` : l'adresse d'un employé monte au serveur, qui compose et envoie (SMTP du serveur).
- **Preuves** : `EmailFacultatifTest` (PHP : écran, Mon profil, synchronisation, détecteurs, file) ; `email_facultatif_contre_serveur_test` + `tool/rh/rejouer_email_facultatif.php` (39 adresses jugées par le vrai Laravel, phrases relues du fichier de langue) ; `charges_contre_serveur_test` (l'adresse normalisée est écrite par le vrai serveur) ; `migration_v45_email_test` (fichier réel, v44 et v40, rejeu) ; `rh_synchronisation_poste_test`, `email_facultatif_comptes_test`, `email_facultatif_employe_ecran_test`. Mutations tuées : écriture de l'adresse à la création, ligne de l'aligneur, rejet d'un domaine à étiquette numérique, e-mail du détecteur. Pièges : `email:filter` accepte `"a"@b.bj` et `a@[1.2.3.4]` (écartés des deux côtés par `not_regex`) et refuse `a@b.123` ; la limite de 255 est inatteignable avant « invalide » (une seule phrase).
- **Fixture de retour arrière** (`_ajoutsParVersion[45]`) : retire `employes_local.email` mais CONSERVE `utilisateurs_local.email` — des DAO joignent toute la table des comptes et les tests v13/v14 sèment par les DAO d'aujourd'hui sur la forme ancienne (sans la colonne, quatre tests ne lisaient plus) ; le retrait côté comptes est éprouvé par `migration_v45_email_test` et la vraie base v44.
- **Limites** : un compte créé avant la v45 n'a d'adresse que si son titulaire la saisit dans « Mon profil » (pas de modale administrateur) ; le poste ne compose pas `bulletin_disponible` ; la dette Blade (`--figer-dette`) n'est pas touchée.


## Reçu de location imprimable (28/10/2026, web + poste, schéma inchangé)

Demande du PO : un reçu PDF par contrat de location (M8), même contenu au web et au poste.

- **Web** : bouton « Reçu » (`vehicules.pwa.recu`) sur chaque ligne de l'onglet Contrats (annulés compris) ; action Livewire `Locations::imprimerRecu` (LECTURE, inscrite dans `METHODES_DE_LECTURE` et `PwaActionsReluesTest`), gabarit `pdf/location-recu.blade.php` sous l'en-tête RG-19 (`entete-rapport`), ni visa ni pied de rapport (classé « document client » dans `PdfExportConformiteTest`). Données de plus : `ContratLocationService::donneesRecu`. Libellés `vehicules.pwa.recu_*`.
- **Poste** : `vehicules/impression/recu_location.dart` (classé `documentsClient` de `pdf_directive_test`), bouton « Reçu » (`imprimerRecuLocationProvider`, `Printing.layoutPdf` : imprimer ou enregistrer en PDF), tout en local, aucune synchronisation requise, aucun numéro alloué.
- **Contenu** : N° du contrat (tiret s'il n'en a pas), client, véhicule, période, durée, tarif journalier, montant total, acompte, reste dû (ou « Soldé »), statut, émis le / par ; mention « ne vaut pas facture ». **Annulé** : bandeau « ANNULÉ », phrase « aucun montant n'est dû », AUCUNE ligne de montant. Le **tarif n'est écrit que s'il explique le montant figé** (tarif du véhicule x jours = montant), sinon tiret : le montant est figé à la signature, le tarif du véhicule a pu changer.
- **Preuves** : `RecuLocationTest` (PHP, mutation `@unless` tuée), `recu_location_test` (libellés relus du fichier de langue, Latin-1), `ecran_vehicules_test` (bouton en lecture seule et sur annulé). Comparateur Blade : PASS, dette inchangée (33, non refigée). Limite : le web écrit le client en « prénom nom », le poste en `clientNom` tel que stocké.

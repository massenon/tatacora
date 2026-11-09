# Passage d'année et clôture d'exercice (SYSCOHADA révisé)

Décisions du Product Owner du 20/10/2026 : clôture **annuelle** ;
réouverture réservée **au comptable** ; archive au format **SYSCOHADA révisé
/ DGI Bénin**.

## 1. Le passage à N+1 : rien ne s'arrête, rien ne se perd

- **L'exercice N+1 s'ouvre tout seul**, sur le serveur et sur chaque poste :
  - la tâche planifiée `tatacora:ouvrir-exercices` (chaque jour à 00:05)
    ouvre l'année en cours et, en décembre, l'année suivante ;
  - la première pièce datée du 1er janvier ouvre l'année si elle manque
    (serveur et poste, tracé au journal d'audit).
- **Les exercices descendent vers les postes** avec leur statut : un poste
  sait qu'un exercice est en clôture ou clôturé sans redémarrer.
- **Les données des modules restent enregistrées** : rien n'est déplacé ni
  effacé (RG-11). Une pièce va dans l'exercice de **sa date** :
  - N reste **ouvert** tant que sa clôture n'a pas commencé : les écritures
    tardives de décembre s'y passent encore, pendant que janvier s'écrit dans
    N+1 (deux exercices ouverts en même temps) ;
  - quand N est **en clôture**, les modules ne peuvent plus y écrire. Seules
    les écritures d'inventaire du comptable y passent ;
  - quand N est **clôturé**, il ne se consulte plus qu'en lecture.
- **À-nouveaux provisoires** : tant que N n'est pas clôturé, la balance de
  N+1 (et donc son bilan) inclut les soldes des comptes de bilan de N.
  Ceux-ci sont **calculés à la volée, jamais écrits**, et le résultat de N
  apparaît en 131/139. La balance le signale (« à-nouveaux provisoires de
  N »).

## 1 bis. Consulter N, N−1, N+1 (lot 3)

Dans la PWA, hub Comptabilité :

- **Navigation entre exercices** : sous l'en-tête, « ← Exercice N−1 » et
  « Exercice N+1 → » (en plus du sélecteur), sur l'onglet affiché.
- **Statut de l'exercice consulté** : un bandeau le dit.
  - En clôture : les modules n'y écrivent plus ; le comptable y passe ses
    écritures d'inventaire.
  - Clôturé : lecture seule ; seule la réouverture par le comptable permet
    d'y corriger.
- **Comparatif N / N−1** : le compte de résultat et le bilan ont une colonne
  « Exercice N−1 » quand l'exercice précédent existe. Elle reprend le même
  poste (même ligne de la cascade, même poste du bilan, mêmes totaux) avec le
  même filtre de statut.
- **À-nouveaux provisoires** : la balance de N+1 affiche un encadré quand
  elle les inclut.
- **Saisie d'inventaire en clôture** : « Passer écriture » accepte un
  exercice en clôture (ouvert ou en clôture : oui ; clôturé : non). Les
  journaux CL et AN ne s'y choisissent pas, car seule la clôture les écrit.

Sur le poste (Windows) :

- Les mêmes boutons de navigation et le même bandeau de statut, aux mêmes
  mots.
- Un exercice ouvert OU en clôture offre « Nouvelle écriture » (le comptable y
  passe ses écritures d'inventaire) ; un exercice clôturé ne l'offre pas.
- Le compte de résultat, le bilan et le comparatif se calculent sur le poste
  (depuis le 21/10/2026) ; la clôture annuelle elle-même s'y mène aussi (§ 5).

## 1 ter. Soldes d'ouverture et alerte avant clôture

- **Grand livre** : sous le tableau d'un compte, le *solde d'ouverture* et le
  *solde de clôture*. Pour un compte de bilan, l'ouverture est l'à-nouveau :
  écrit au journal AN si l'exercice précédent est clôturé, **provisoire**
  (calculé, et dit tel) sinon. Les comptes de gestion (6 à 9) repartent de
  zéro. Si l'exercice précédent a été clôturé sans pièce d'à-nouveaux
  (avant la clôture SYSCOHADA), l'ouverture reste « inconnue », jamais zéro.
- **Notes annexes 2 et 3** (immobilisations, amortissements) : chaque compte
  porte son ouverture et la variation de l'exercice.
- **Avant « Démarrer la clôture »** : l'onglet Clôtures liste les postes
  appairés qui ont des opérations à envoyer, ou dont l'état est inconnu (rien
  reçu, ou plus de nouvelles depuis 24 h). C'est un avertissement, il ne
  bloque pas : une fois N en clôture, le serveur refuse leurs pièces datées de
  N. Faites d'abord « Synchroniser les postes ».

## 2. La clôture, onglet « Clôtures » de la Comptabilité (PWA)

| Étape | Bouton | Effet |
|---|---|---|
| ouvert → **en clôture** | « Démarrer la clôture » | Les modules ne peuvent plus écrire dans N. Seules les écritures d'inventaire du comptable y passent. |
| en clôture → ouvert | « Reprendre la saisie » | Retour en arrière tant que rien n'est clôturé. |
| en clôture → **clôturé** | « Clôturer définitivement » | Voir ci-dessous. |
| clôturé → en clôture | « Rouvrir » (**comptable seul**, motif ≥ 10 caractères) | Contre-passe la pièce de clôture et la pièce d'à-nouveaux (rien ne s'efface), et trace le motif. |

La clôture définitive est refusée tant que la liste de contrôle n'est pas
réunie : aucune écriture en brouillon, balance équilibrée, et exercice N−1
clôturé. Elle refuse aussi si l'exercice N+1 est déjà clôturé.

Quand elle passe, elle produit, dans l'ordre :

1. **La pièce de clôture**, datée du 31/12/N au **journal CL**. Elle solde
   les comptes de gestion (classes 6, 7 et 8) centre par centre. La
   contrepartie va en **131** (bénéfice) ou en **139** (perte), centre
   « Structure ».
2. **La pièce d'à-nouveaux**, datée du 01/01/N+1 au **journal AN**. Elle
   reporte les soldes des classes 1 à 5 de N, résultat compris. Les
   à-nouveaux deviennent alors définitifs.
3. **Le verrou** : l'exercice N passe au statut « clôturé ».
4. **L'archive légale** (section 3).

Les états de N (balance, compte de résultat, bilan) restent ceux **d'avant**
la clôture, parce que le journal CL en est exclu. Le compte de résultat
montre donc le résultat de l'année, pas zéro.

## 3. L'archive légale

Elle est générée à chaque clôture, dans
`storage/app/private/archives/exercices/<année>/<id de la clôture>/` :

| Fichier | Contenu |
|---|---|
| `ecritures.csv` | Le fichier des écritures de l'exercice, une ligne par ligne d'écriture, y compris la clôture et les contre-passations. Il est en UTF-8 avec BOM, séparateur `;`, dates AAAAMMJJ et montants à virgule. Colonnes : `JournalCode;JournalLib;EcritureNum;EcritureDate;CompteNum;CompteLib;CentreCout;EcritureLib;Debit;Credit;Statut;EcritureContrepassee;DateSaisie;SaisiPar` |
| `balance.csv` | La balance générale de clôture. |
| `etats-cloture.pdf` | La clôture (pièces, résultat), la balance, le compte de résultat, le bilan, et les visas. |
| `manifeste.json` | L'empreinte SHA-256 et la taille de chaque fichier. |

- **L'empreinte de l'archive** est le SHA-256 du manifeste. Elle est
  affichée dans l'onglet « Clôtures ». **Notez-la**, sur le registre ou sur
  le PV de clôture : elle prouvera plus tard qu'aucun fichier n'a changé.
- « Télécharger l'archive (ZIP) » **vérifie** l'archive avant de la
  délivrer. Si un fichier a été modifié ou supprimé, le téléchargement est
  refusé.
- L'archive est **immuable** : elle n'est jamais régénérée. Si l'exercice est
  rouvert puis clôturé à nouveau, la nouvelle clôture produit une **nouvelle**
  archive, et l'ancienne reste.
- Si la génération échoue après la clôture, la clôture tient quand même.
  L'onglet propose alors « Générer l'archive ».
- **Sauvegarde** : copiez `storage/app/private/archives/` avec les
  sauvegardes du serveur (le dump SQL ne contient pas ces fichiers).

> ⚠ **À confirmer avec l'expert-comptable ou la DGI Bénin** : le format exact
> attendu du fichier des écritures (colonnes, encodage, nom du fichier).
> Les colonnes sont regroupées dans `ArchiveClotureService::COLONNES_ECRITURES`,
> si bien qu'un ajustement ne touche qu'un seul endroit.

## 4 bis. Le résultat reporté de chaque exercice clôturé

La colonne « Résultat reporté » de l'onglet Clôtures porte, pour chaque
exercice **clôturé**, le résultat que sa clôture a écrit en 131/139 (lu sur
`clotures_exercices.resultat`, jamais recalculé). L'exercice consulté non
clôturé porte son résultat calculé ; les autres, un tiret. Une clôture rouverte
n'est plus « active » : son exercice retrouve le tiret.

## 4 ter. L'affectation du résultat (09/11/2026)

La clôture de N-1 laisse son résultat en 131 (bénéfice) ou 139 (perte), reporté dans N par l'à-nouveau. L'assemblée qui approuve les comptes le ventile ; la **carte « Affectation du résultat de l'exercice N-1 »** de l'onglet « Clôtures » (web et poste) passe cette décision.

- **La pièce** : journal OD, datée de la date d'approbation, dans l'exercice N **ouvert**, validée donc immuable ; on la corrige par **contre-passation** (comptable seul, motif de 10 caractères au moins).
- **Bénéfice** : débit 131 ; crédit réserve légale (111), autres réserves (1181), dividendes à payer (465), report à nouveau créditeur (121). **Perte** : crédit 139 ; débit report à nouveau débiteur (1291), ou imputation sur les autres réserves (1181) / le report à nouveau créditeur (121), dans la limite de leur solde. Les comptes sont ceux de la correspondance des comptes (modifiables), pas des numéros figés.
- **Contrôles** : exercice N-1 clôturé ; résultat non nul, lu sur la clôture active (jamais recalculé) ; **une seule affectation active** ; date dans N ; aucun montant négatif ; **somme des ventilations = résultat exactement** ; pas de dividende ni de réserve légale sur une perte. Réserve légale **proposée** à 10 % du bénéfice tant qu'elle n'atteint pas 20 % du capital (compte 101x) ; modifiable ; rien n'est proposé si le capital n'est pas déterminable.
- **Effets** : 131/139 de N soldé, « Résultat reporté » du bilan de N à zéro, bilan équilibré (réserves, report à nouveau et dividendes à payer sont rangés au bilan). La clôture de N reporte ensuite réserves et report à nouveau. **Rouvrir N-1 est refusé tant que l'affectation est active.**
- **Poste** : la pièce part comme une pièce saisie à la main avec sa ventilation ; le serveur la passe par son service (mêmes refus, mêmes phrases) et refuse une pièce qui ne correspond pas à la sienne. La contre-passation part comme une demande `annuler_affectation`.
- **Une affectation passée au web (ou par un autre poste) apparaît sur chaque poste (09/11/2026, schéma poste v53)** : le serveur DESCEND l'entité `affectations_resultat` dans la réponse des référentiels (`CatalogueDescendantService::COLONNES`, après les écritures qu'elle cite ; lue sous le droit de lecture de la comptabilité M10) — active ET contre-passée (`contrepassee_le`), avec l'année de l'exercice, le montant signé du résultat, la ventilation, le numéro de pièce du serveur, le LOGIN de l'auteur, la date de passation et `piece_origine_id` (l'identifiant de la pièce du poste d'où elle vient, vide pour le web). Le poste l'inscrit dans `affectations_resultat_local` (écrivain unique `AffectationsRecuesDao`, appelé par l'aligneur du catalogue, qui n'enfile jamais). La carte du poste affiche alors « Affectation passée le … par … (pièce n° …) » avec les montants, **remplace** « Passer l'affectation » (l'unicité est connue du poste, le serveur reste juge) et, pour une affectation passée ailleurs, dit qu'elle se contre-passe là où elle a été passée puis redescend. **Contre-passée au web, elle redescend datée** : la carte offre de nouveau « Passer l'affectation ». **Sans double** : une ligne reçue dont `piece_origine_id` est l'identifiant d'une pièce de CE poste (`pieces_saisie_local.id`) EST cette pièce — lue du journal du poste, jamais affichée deux fois ; si le serveur la dit contre-passée, elle n'est plus active ici même si les lignes du journal n'ont pas bougé. **Clôture faite ailleurs** : un poste qui n'a pas fait la clôture n'a pas sa clôture locale ; le résultat est alors lu sur la ligne reçue — l'ACTIVE (la réouverture est refusée tant qu'elle l'est), ou la contre-passée seulement si elle date de la clôture en cours (date de clôture de l'exercice ≤ date de passation) ; sinon pas de carte. Pourquoi une table et non le miroir des écritures : celui-ci ne porte ni auteur, ni date de passation, ni ventilation par poste, ni statut « contre-passée » de l'affectation, et reconnaître une affectation à son libellé aurait pris pour affectation une pièce saisie à la main du même nom. Preuve : `AffectationsDescendantesTest` (serveur), `affectation_recue_du_serveur_test`, `hub_affectation_du_web_test`, `affectation_du_web_contre_serveur_test` (script `rejouer_affectation.php`, événement `flux_affectations` : le vrai `CatalogueDescendantService` exécuté), `migration_v53_affectations_test`, `ecrivains_affectations_recues_test`.

## 5. Le poste clôture aussi — et le contrat de synchronisation d'exercice

Décision du Product Owner du 26/10/2026 : « la clôture annuelle SYSCOHADA DOIT
ÊTRE IMPLÉMENTÉE EN POSTE ET WEB ».

**Sur le poste** (onglet « Clôtures » du hub comptable, schéma local v40) : les
mêmes quatre gestes, la même liste de contrôle, les mêmes pièces CL et AN, la
même réouverture contre-passée, la même archive légale et son empreinte
SHA-256 — sur **les écritures passées par ce poste**, par le moteur comptable
(écrivain unique, RG-11, RG-12). Les phrases sont celles du serveur, relues par
des tests qui EXÉCUTENT `ClotureExerciceService`.

**Le serveur reste le seul comptable (D246).** Le poste ne lui envoie jamais une
pièce : chaque geste enfile une **demande** (document source), table
`demandes_cloture_exercice` du registre de synchronisation, module M10, création
seule :

| Champ | Valeur |
|---|---|
| `annee` | l'année de l'exercice (2000 à 2100) |
| `action` | `demarrer`, `reprendre_saisie`, `cloturer`, `rouvrir` |
| `motif` | pour `rouvrir` : dix caractères au moins |

`GestionnaireDemandesCloture` rejoue `ClotureExerciceService` **comme le fait
l'onglet de la PWA**, avec les droits du compte appairé : mêmes refus, mêmes
phrases (ordre des exercices, brouillons, balance, rôle du comptable pour la
réouverture, motif). La demande acceptée est consignée (`demandes_cloture_exercice` :
issue, pièces, résultat, empreinte de l'archive que le SERVEUR a produite) et
l'archive légale suit la clôture, comme à l'écran. Un refus annule tout : le poste
lit la phrase du serveur dans « À traiter » de son écran de synchronisation.

- **Une demande déjà satisfaite est acceptée sans rien réécrire**
  (`deja_dans_cet_etat`) : démarrer un exercice déjà en clôture, clôturer un
  exercice déjà clôturé, reprendre la saisie d'un exercice ouvert, rouvrir un
  exercice qui n'est pas clôturé. C'est la seule tolérance.
- **Le statut redescend** (déjà le cas depuis le 20/10/2026) et les pièces CL/AN
  du serveur descendent dans le miroir de lecture du poste.
- **Tant que la dernière demande de l'année n'est pas acceptée** (en file,
  refusée, bloquée), le statut du serveur ne défait pas la clôture locale :
  sinon un exercice « ouvert » redescendu rouvrirait l'écriture dans un
  exercice dont les pièces de clôture existent déjà ici.

**Écarts nommés.** (1) Le résultat d'une clôture du poste est celui de SES
pièces, pas de l'établissement : la clôture légale est celle du serveur. Si le
serveur refuse (un brouillon d'un autre poste, un exercice précédent non clôturé
chez lui…), la clôture locale demeure et le refus se lit à l'écran de
synchronisation. (2) Pas de relevés bancaires sur le poste : l'avertissement
« relevés non rapprochés » n'y existe pas. (3) Le PDF de l'archive du poste est
composé avec le gabarit tabulaire commun du poste (mêmes sections, mêmes mots,
mêmes montants), pas par DomPDF ; `ecritures.csv` et `balance.csv` sont, eux,
**les mêmes octets** que ceux du serveur (hors date et login de saisie). (4) Les
archives du poste vivent dans `archives/` à côté de `poste.json` : la sauvegarde
de la base ne les contient pas, comme le dump SQL ne contient pas celles du
serveur. (5) Les comptes qui reçoivent le résultat suivent la correspondance des
comptes (`compte_resultat_benefice` / `compte_resultat_perte`, 131 et 139 par
défaut) sur le poste comme au serveur.

## 5 bis. Les états financiers après l'avis de l'expert-comptable (10/11/2026)

Le Gîte est une **entreprise individuelle**. Avis de l'expert-comptable SYSCOHADA révisé, appliqué **au web et au poste, au mot et au centime près** (`TafireService`, `BilanService`, `RubriquesSyscohada`, `RubriquesTafire` ; leurs miroirs Dart `tafire_notes.dart`, `etats_financiers.dart`, relus du serveur par des tests qui EXÉCUTENT le vrai PHP).

**Le TAFIRE, définition finale** (aussi en tête de `TafireService`) :

| | |
|---|---|
| **CAFG** | résultat net de N seul **+ dotations** (681, 687, 691, 697, 85) **− reprises** (781, 787, 791, 797, 798, 86) + valeur comptable des cessions (81) − produits des cessions (82) **− quote-part des subventions d'investissement virée au résultat** (799, produit non encaissé) |
| **Exploitation** | CAFG − variation du BFR (stocks + créances − dettes circulantes ; le 465 n'y est pas) |
| **Investissement** | produits des cessions − acquisitions ; acquisitions = variation des immobilisations nettes + dotations aux **amortissements** (681, 852) + VNC cédées − reprises sur immobilisations (781, 787, 798, 862) |
| **Financement** | apports (101, 102, 103, 105, 106, 109, et les subventions d'investissement **reçues** : variation du 14 + quote-part 799) + **emprunts = comptes 16 et 17** + dettes liées à des participations et comptes de liaison (18, ligne distincte, non affichée quand elle est nulle) − dividendes versés et prélèvements de l'exploitant |
| **Contrôle** | variation de trésorerie par les flux = variation constatée aux comptes de classe 5 |

- **Le compte 19 est une provision financière pour risques et charges, pas un emprunt** : il n'entre dans aucun flux de financement ; sa variation passe par les dotations et reprises de la CAFG. Même règle pour le 15 (provisions réglementées : 851 / 861). Une dotation aux **provisions** est réintégrée à la CAFG mais n'entre pas dans les acquisitions (elle n'a pas de contrepartie d'actif) ; seules les dotations aux amortissements et les reprises sur immobilisations s'y compensent. Un mouvement de 19 qui ne passerait par aucune dotation ni reprise laisse un **écart** que le contrôle de cohérence signale.
- **Le compte de l'exploitant (104)** est un compte de capitaux propres (bilan, PHP et Dart). Un bénéfice affecté au 104 (D 131 / C 104) se compense : rien ne sort. Un prélèvement personnel (D 104 / C 5xx) est lu avec les dividendes : la ligne s'appelle « Dividendes versés et prélèvements de l'exploitant ». Un apport en compte (D 5xx / C 104) la fait baisser (le 104 n'est plus un « apport de capital »).
- **Le compte 465 (dividendes à payer) est au passif circulant du bilan**, en « autres dettes », avec une ligne « dont dividendes à payer » (web : page du bilan, onglet Bilan du hub, états financiers ; poste : onglet Bilan). Le « dont » est déjà compté dans le poste : il ne s'additionne jamais. Le TAFIRE, lui, garde le 465 **hors du BFR** : les dividendes versés = dividendes décidés − variation du 465, comme avant. La note annexe 4 le porte une seule fois et son total égale le passif circulant du bilan.
- **Le bilan range maintenant** : capital 101 à 109 (104 compris), subventions d'investissement (14) et provisions réglementées (15) en capitaux propres ; un poste « **Dettes financières et ressources assimilées** » (16, 17, 18, 19) entre les capitaux propres et le passif circulant. Avant, ces comptes étaient « hors nomenclature » et déséquilibraient le bilan.
- **Le compte de résultat** (cascade des SIG) capte désormais 687 (dotations aux amortissements à caractère financier, rubrique RN), 797 (reprises financières, nouvelle rubrique TL) et 799 (reprises de subventions d'investissement, rubrique TJ) : ils manquaient au résultat.
- **Comparatif N / N-1, archive légale, état de clôture** : le comparatif reprend le poste par son code (le « dont » et le nouveau poste y suivent). Une archive déjà générée n'est jamais régénérée ; une nouvelle archive porte le nouveau poste du passif.

**Ce que le plan comptable du dépôt dit, et ce que l'avis supposait** : le **777** est « Gains sur cessions de titres de placement » (un produit encaissé), pas la quote-part des subventions : celle-ci est le **799** « Reprises de subventions d'investissement ». Les reprises d'amortissements sont au **798** (absent de l'avis, ajouté : sans lui une reprise d'amortissement déséquilibre le tableau). Le **781** et le **787** sont des « transferts de charges » ; ils sont rangés avec les reprises comme l'avis le demande, en supposant que leur contrepartie est une immobilisation (un transfert dont la contrepartie serait une créance fausserait le tableau : à confirmer avec le comptable). **Écart nommé** : le TAFIRE n'a pas de ligne « subventions d'investissement reçues » : elles restent dans « Augmentation de capital ».

## 6. Après `git pull` sur le serveur

```bash
php artisan migrate   # tables clotures_exercices et demandes_cloture_exercice, journaux CL et AN
```

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

## 6. Après `git pull` sur le serveur

```bash
php artisan migrate   # tables clotures_exercices et demandes_cloture_exercice, journaux CL et AN
```

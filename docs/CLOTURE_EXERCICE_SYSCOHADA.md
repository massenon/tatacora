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
- Un exercice qui n'est pas ouvert n'offre pas « Nouvelle écriture ».
- Le poste ne connaît que ses propres écritures : le compte de résultat, le
  bilan et le comparatif ne s'y calculent pas. Ils se consultent dans la PWA.

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

## 4. Après `git pull` sur le serveur

```bash
php artisan migrate   # table clotures_exercices, journaux CL et AN
```

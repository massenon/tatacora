# PRD — Deux corrections du module Véhicules & Locations (M8)

> Statut : **à valider par le Product Owner** (rédigé le 27/10/2026, rien n'est
> encore corrigé). Origine : deux écarts relevés pendant la livraison de
> l'annulation d'un contrat de location (schéma poste v38,
> [`AUDIT_POSTE_AUTONOME.md`](AUDIT_POSTE_AUTONOME.md)). Ils touchent le
> **serveur** ; le poste est déjà aligné sur la règle voulue, sauf là où c'est dit.

## 1. Énoncé du problème

Depuis le 26/10/2026, un contrat de location peut être **annulé** (colonne
`contrats_location.statut`, service `ContratLocationService::annuler`). Deux
endroits n'ont pas suivi :

1. **L'état M14 « Locations »** (`EtatLocations`) liste **tous** les contrats,
   annulés compris, et additionne leur montant. Un contrat annulé gonfle le
   nombre de locations et le chiffre d'affaires de l'état imprimé ou exporté.
   Son commentaire affirme encore que `contrats_location` « ne porte NI
   `statut` », ce qui est devenu faux.
2. **L'archivage d'un véhicule** n'applique pas la même règle de date côté
   serveur et côté poste : le serveur teste `date_fin >= aujourd'hui`
   (`ParcVehiculeService::contratsEngages`), le poste teste
   `dateFin.isAfter(aujourd'hui)` (`VehiculeDao`). Un véhicule dont le contrat
   se **termine aujourd'hui** est donc bloqué au serveur et archivable au poste.

Le gérant lit un chiffre d'affaires faux sur l'état ; le même geste donne deux
réponses selon la machine.

## 2. Objectifs

- G1. Le chiffre d'affaires et le nombre de locations de l'état M14 ne comptent
  **aucun contrat annulé**.
- G2. L'archivage d'un véhicule donne **la même réponse** sur le serveur et sur
  le poste pour toute date de fin de contrat, y compris le jour même.
- G3. Une garde de test empêche le retour de chacun des deux écarts.

## 3. Hors périmètre

- Changer la règle métier RG-08 (chevauchement des contrats) : inchangée.
- Ajouter d'autres statuts de contrat (« en retard », « clôturé »).
- Corriger les KPI de l'écran « Locations » (filtrés par statut à dessein, comme
  la vue web).
- Réécrire des états déjà exportés ou archivés : ils restent tels qu'émis.

## 4. Récits utilisateur

- En tant que **gérant**, je veux que l'état « Locations » ne compte pas les
  contrats annulés, pour que le chiffre d'affaires affiché soit celui que
  j'encaisse.
- En tant que **gérant**, je veux voir qu'un contrat est annulé quand je choisis
  de l'inclure, pour expliquer un écart avec l'ancien état.
- En tant qu'**administrateur**, je veux que « Archiver » un véhicule réponde
  pareil sur le poste de la réception et sur le web, pour ne pas découvrir à la
  synchronisation qu'un archivage accepté ici est refusé là-bas.

## 5. Exigences

### Indispensables (P0)

**R1 — L'état « Locations » exclut les contrats annulés.**
- Étant donné un contrat annulé dans la période, quand l'état est calculé, alors
  il n'apparaît ni dans les lignes, ni dans « nombre », ni dans « montant ».
- Le commentaire de `EtatLocations` est corrigé (le statut existe).
- Le montant total est identique à celui de l'écran « Locations » filtré sur les
  contrats non annulés pour la même période.

**R2 — Une seule règle de date pour l'archivage d'un véhicule.**
- Règle retenue : un contrat **engage** le véhicule tant que
  `date_fin >= aujourd'hui` et que son statut n'est pas `annule`. Le jour de
  restitution engage encore (le véhicule est rendu dans la journée).
- Le poste (`VehiculeDao`) passe de `isAfter(jour)` à « fin >= jour ». Le message
  de refus (`archivageVerrouille`) est inchangé.
- Étant donné un contrat qui se termine aujourd'hui, quand on archive le
  véhicule, alors le refus est identique au serveur et au poste.

**R3 — Gardes.** Un test PHP et un test Dart couvrent les trois jours
significatifs : fin hier (archivable), fin aujourd'hui (refusé), fin demain
(refusé), plus le cas du contrat annulé (archivable). Le test Dart confronte
le poste à `ParcVehiculeService` exécuté par PHP, comme les autres parités.

### Souhaitables (P1)

- **R4 — Case « Inclure les contrats annulés »** sur l'état « Locations »
  (décochée par défaut), avec une colonne « Statut ». Le poste l'offre aussi.
- **R5 — Libellé de l'aperçu poste** : l'encadré « Sur ce poste » de l'aperçu de
  l'état dit si les annulés sont exclus.

### Pour plus tard (P2)

- Un statut « terminé » dérivé de la date de fin, si le gérant veut distinguer
  les locations en cours des locations passées.

## 6. Décision à prendre

| Question | Recommandation | Qui |
|---|---|---|
| Le jour de restitution doit-il bloquer l'archivage ? | **Oui** (règle du serveur, plus prudente : le véhicule peut encore être dehors) | Product Owner |
| Faut-il corriger R4 dans le même lot ? | Oui si le gérant exporte l'état pour la comptabilité ; sinon plus tard | Product Owner |

Aucune question technique bloquante : le correctif est local à deux services et
à un DAO.

## 7. Indicateurs de réussite

- **Immédiats** : l'état « Locations » d'une période contenant un contrat annulé
  donne le même total que l'écran « Locations » (écart 0 FCFA) ; les deux gardes
  de test passent.
- **À un mois** : aucun archivage de véhicule accepté au poste puis refusé au
  serveur dans « À traiter » (le journal de réception de la synchronisation le
  montre).

## 8. Plan de livraison

Un seul lot, sans migration : `EtatLocations` (+ test), `VehiculeDao` (+ test de
parité), commentaire de `ContratLocationService`, mise à jour de
`AUDIT_POSTE_AUTONOME.md` et du `CLAUDE.md` du poste. Le client Flutter se met à
jour en même temps que le serveur pour que la règle du jour de restitution soit
la même partout.

# Spécification — Facture proforma (PO, 07/11/2026)

Document commercial **NON FISCAL**, web (PWA) et poste (hors ligne), même rendu A4.
Modèle papier : « FACTURE PROFORMA », réf. `N°0045 FP-GCN/2026`.

## 1. Numéro
- Format : `N°` + rang sur 4 chiffres + ` FP-` + RÉFÉRENCE FACTURE + `/` + année. Ex. `N°0045 FP-GCN/2026`.
- La RÉFÉRENCE FACTURE (`facture_reference`, défaut `GCN`) est un réglage (Paramètres > Identité & Légal).
  Elle est COPIÉE sur la proforma à l'émission : changer le réglage ne renumérote rien.
- Séquence continue par année (`proformas.annee`, `proformas.rang`, index unique `(annee, rang)`), repart à 1
  le 1er janvier. Allouée par le SERVEUR sous verrou (`SequenceProformaService`), sans trou ni doublon.
- Un brouillon n'a pas de numéro : le rang naît à l'ÉMISSION (donc aucun trou par brouillon abandonné).
  Une proforma annulée garde son numéro.
- Poste hors ligne : numéro PROVISOIRE `PROV-FP-AAAA-NNNNN` (même mécanisme que les factures `PROV-…`),
  remplacé à l'accusé de synchronisation par le numéro définitif rendu par le serveur. Jamais deux définitifs.
- Les numéros des FACTURES (`F-AAAA-NNNNN`) ne changent pas : elles n'ont pas de préfixe « référence ».

## 2. Cycle de vie
`brouillon` -> `emise` -> `convertie` ; `annulee` (motif obligatoire) depuis brouillon ou émise.
`expiree` est DÉRIVÉ (émise, `valide_jusqu_au` dépassée), jamais stocké ; la conversion reste possible,
avec confirmation. Modifiable tant que non convertie ni annulée ; chaque modification est auditée.
Aucune écriture comptable, aucun mouvement de stock, jamais de numéro MECeF / QR / mention de
normalisation, quel que soit le mode de facturation.

## 3. Lignes et montants
Désignation libre, quantité entière, prix unitaire TTC en FCFA entiers, montant = quantité x prix.
Total = somme. Pas de TVA affichée sur la proforma (le document du modèle n'en porte pas).

## 4. Validité
Réglages `proforma_validite_affichee` (Oui/Non, défaut Non) et `proforma_validite_jours` (défaut 30).
Oui à l'émission : `valide_jusqu_au = date d'émission + jours`, ENREGISTRÉ sur la proforma ; le PDF porte
« Valable jusqu'au <date> ». Un changement ultérieur du réglage ne touche pas les proformas émises.
Les factures n'ont PAS de date de validité (l'interrupteur ne vise que les proformas).

## 5. Signature et cachet
Réglages : `signataire_nom`, `signataire_fonction`, images `signature` et `cachet` (<= 400 Ko, réduites
automatiquement par la règle des reçus de dépense), interrupteur `facture_signature_affichee` (Oui/Non).
S'applique aux PROFORMAS et aux FACTURES (PDF A4 serveur et poste ; ticket exclu).
Non = aucun bloc. Oui sans image = nom et fonction seulement.

## 6. Conversion en facture
« Convertir en facture » : `ProformaService::convertir` crée une VRAIE facture par `EmissionFactureService`
(`emettreVide` + `ajouterLigne` + `figerEmission`, comme la synchronisation des factures du poste), même client,
IFU, lignes et montants ; `proformas.facture_id` et `factures.proforma_id` se répondent ; la proforma passe
à `convertie` (immuable). Idempotent : un rejeu rend la même facture. Le mode de facturation décide ensuite
(désactivé : facture simple ; e-MECeF / boîtier : « en attente de normalisation » + bouton Normaliser, jamais auto).

## 7. Montant en lettres
`App\Pwa\Support\MontantEnLettres::francsCfa(int)` (PHP) et `montant_en_lettres.dart` (Dart), mêmes règles :
« quatre-vingts » (s) seulement s'il termine le nombre ; « cent » prend un s s'il est multiplié et terminal ;
« mille » invariable ; « un million ». Majuscules, suffixe « FRANCS CFA » (« FRANC CFA » pour 0 ou 1).
Table de cas partagée `tool/proforma/cas_montant_en_lettres.json`, rejouée par `rejouer_proforma.php`.

## 8. Flux prérempli
Écran Facturation (« Nouvelle facture proforma », saisie libre) et bouton « Créer une proforma » dans
location (contrat), tourisme (réservation de circuit), hébergement (réservation), restauration événement
quand l'objet existe ; sinon proforma vide avec le client prérempli. Lignes toujours modifiables.

## 9. Synchronisation
Montée : table `proformas` (+ lignes dans la charge), identifiant né au poste, gestionnaire idempotent
(`GestionnaireProformas`, module M2), journal d'audit. Descente : aux autres postes et à la PWA.
Poste : schéma v52, tables `proformas_local`, `lignes_proforma_local`.

## 10. Tests
Numérotation (séquence, année, rejeu), montant en lettres (table + parité), PDF (contenu, jamais MECeF/QR/NIM/DEMO),
conversion (une fois, mêmes montants, idempotente), expiration, droits, synchronisation, mutations.

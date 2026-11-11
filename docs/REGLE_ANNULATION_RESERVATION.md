# Règle d'annulation d'une réservation (web et poste)

Mis à jour le 11/11/2026 (relu en entier et confronté à `AnnulationReservationService`, `RegistreParametres` et `annulation_reservation.dart`). Décision du PO du 09/11/2026 — identique au serveur (`AnnulationReservationService`) et au poste
(`annulation_reservation.dart`).

## 1. Le taux dépend du DÉLAI (grille paramétrable)

Délai = heures entre l'annulation et le début du jour d'arrivée.

| Délai | Taux appliqué | Paramètre (Paramètres → groupe Exploitation, web ET poste, synchronisé) |
|---|---|---|
| < seuil d'heures | taux « moins de 24 h » (référence **50 %**) | `hebergement_taux_annulation_moins_24h` |
| ≥ seuil d'heures | taux « au-delà du seuil » (**0 %** par défaut) | `hebergement_annulation_taux_au_dela` |
| seuil | **24 h** par défaut | `hebergement_annulation_seuil_heures` |

Le taux est appliqué **automatiquement** à l'ouverture du formulaire (web et poste) ; l'opérateur
peut le corriger au cas par cas. Une arrivée déjà passée est « sous le seuil ».

## 2. Commission et remboursement

* **Commission = taux × TOTAL de la réservation** (le « montant initial » est le total).
* **Payé** = l'acompte versé sur la réservation.
* **Remboursé PROPOSÉ = max(0, payé − commission)** : c'est la valeur pré-remplie à l'ouverture du
  formulaire (en % du payé). L'opérateur saisit ensuite le remboursé réel, en % du payé OU en FCFA ;
  **il ne peut jamais dépasser le payé** (une saisie plus haute est REFUSÉE, elle n'est pas rognée).
  * Payée en totalité → proposé = total − commission.
  * Acompte partiel → proposé = payé − commission ; si le payé ne couvre pas la commission,
    proposé = 0 et le client ne doit rien de plus.
  * Rien payé → rien à rembourser, aucune pièce.
* La commission se calcule sur le total et se retient sur le montant déjà payé (aide du réglage).

## 3. Ce qui est enregistré

Taux, total, commission, remboursé, mode de saisie, date, auteur et poste sont **figés** sur la
réservation (onglet Annulations, historique) ; la grille ne modifie jamais une annulation passée.
Un remboursé > 0 passe sa pièce comptable (Dr 4191 / Cr 5711) dans la même transaction ; le
remboursé de 0 n'écrit rien.

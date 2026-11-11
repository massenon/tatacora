<div align="center">

<img src="docs/readme/social-preview.png" alt="LogiReStock — Gestion intégrée du Gîte Chez Noël" width="100%">

# LogiReStock

**Le logiciel de gestion d'un gîte-restaurant, de la réservation jusqu'au bilan comptable.**

Hébergement · Restaurant et bar · Stocks · Facturation normalisée e-MECeF · Comptabilité SYSCOHADA · RH et paie

</div>

---

## Le projet

LogiReStock est un projet personnel : un système de gestion intégrée conçu pour le **Gîte Chez Noël** (Natitingou, Bénin).

Il remplace les cahiers, les tableurs et les calculs à la main. On y enregistre chaque réservation, chaque vente au bar ou au restaurant, chaque achat et chaque paie, et le logiciel en déduit **les stocks, les factures, les écritures comptables et les états de gestion**, sans ressaisie.

Il s'utilise de deux façons :

- **sur le web**, dans un navigateur, pour le bureau, la comptabilité et l'administration ;
- **sur un poste Windows**, installé à la réception, au bar et au restaurant.

La connexion Internet tombe parfois, donc le poste fonctionne **entièrement hors ligne** et se synchronise tout seul, **toutes les minutes**, dès que le réseau est là. Plusieurs postes travaillent en même temps et se retrouvent cohérents.

---

## Fonctionnalités principales

### 📊 Tableau de bord

Chiffre d'affaires, trésorerie, dépenses, résultat, créances clients, dettes fournisseurs et stock critique, d'un seul coup d'œil, avec les alertes en tête.

<img src="docs/readme/tableau-de-bord.jpg" alt="Tableau de bord" width="100%">

### 🛏️ Hébergement et réservations

Plan des chambres, bungalows et tentes, calendrier d'occupation, check-in et check-out, règle anti-double réservation par chambre. Une réservation peut porter **une ou plusieurs chambres**, avec services inclus (restauration, bar, tourisme, véhicule), remise et acompte. Les **annulations** suivent une règle paramétrable selon le délai (par exemple 50 % de commission sous 24 heures), avec remboursement calculé et historique complet.

<img src="docs/readme/m1-hebergement.jpg" alt="Hébergement" width="100%">

### 🍽️ Restaurant, bar et point de vente

Caisse avec salle et tables, panier, remises, encaissement en espèces, Mobile Money, virement ou crédit. La **carte du Gîte** (plats, boissons, tarifs) garde l'historique de ses prix. Les plats sont toujours vendables ; les boissons décrémentent leur stock et passent en rupture à zéro. Point de vente dédié aux **clients hébergés**, avec une note unique pour le séjour.

<img src="docs/readme/pos.jpg" alt="Point de vente" width="100%">

### 📦 Stocks et achats

Stock calculé depuis les mouvements (jamais saisi à la main), valorisé au **coût moyen pondéré**, alertes de seuil, inventaires par magasin, approvisionnement, réception des commandes, règlement des fournisseurs, et **import Excel** avec modèles fournis.

<img src="docs/readme/m6-stocks.jpg" alt="Stocks" width="100%">

### 🧾 Facturation

Factures A4 et tickets, avoirs, registre des factures et **factures proforma** (devis convertibles en facture, montant en lettres, signature et cachet). Trois modes de facturation normalisée : **désactivée** (facture simple), **e-MECeF** (DGI Bénin) ou **boîtier CC300**. Une facture normalisée est verrouillée : on la corrige par un avoir.

<img src="docs/readme/pwa-proformas-liste.jpg" alt="Factures proforma" width="100%">

### 👥 Clients et créances

Fiches clients, historique, soldes calculés, recouvrement et relances.

### 🧭 Tourisme, véhicules et locations

Circuits et départs, réservations de places, parc de véhicules, contrats de location, entretiens, reçu de location imprimable.

### 📒 Comptabilité SYSCOHADA

Chaque opération génère ses écritures au plan comptable SYSCOHADA : journaux, grand livre, balance, compte de résultat, bilan, flux de trésorerie, **TAFIRE**, notes annexes, immobilisations, analytique. **Sélecteur d'exercice** (N / N-1), **clôture annuelle** avec archive légale à empreinte SHA-256, et **affectation du résultat** selon la forme juridique de l'entreprise. Une pièce validée est immuable : on corrige par contre-passation.

### 🧑‍💼 Ressources humaines et paie

Fiches du personnel, bulletins de paie, congés et plannings.

### ⚙️ Et aussi

- **Droits d'accès par rôle**, modifiables par l'administrateur et appliqués à tous les postes sans redémarrage.
- **Notifications** par e-mail, états et rapports PDF, sauvegardes et journal d'audit.
- **Heure du Bénin** à l'écran, **prix toutes taxes comprises**, vocabulaire du métier.
- **Un manuel d'utilisation** illustré.

---

## Le poste Windows

- **Il travaille sans serveur** : toutes les lectures viennent de sa base locale.
- **Il se synchronise** avec le serveur : envoi des saisies dans l'ordre, réception des nouveautés des autres postes, écran des opérations à traiter avec leurs causes et leurs corrections.
- **Aucune opération ne bloque la synchronisation** : un refus ne retient que son élément, et le reste passe.
- **Installateur Windows** avec mise à jour sur place (les données sont conservées).
- **Démarrage résilient** : une base abîmée ou une migration qui échoue affichent un écran clair, jamais un blocage muet.

<img src="docs/readme/login.jpg" alt="Écran de connexion" width="100%">

---

## Sous le capot

| | |
|---|---|
| **Serveur web** | Laravel 12, Livewire 4, Tailwind, MySQL |
| **Poste** | Flutter (Windows), base locale SQLite (Drift) |
| **Synchronisation** | Hors ligne d'abord, envoi ordonné par file, aucune saisie perdue ni écrasée |
| **Qualité** | Environ 2 700 tests côté serveur et 5 831 côté poste (+ 24 ignorés) |
| **Langue** | Tout le logiciel est en français |

---

## Contact et usage commercial

Ce projet est **privé et personnel**. Tous droits réservés.

Pour toute utilisation commerciale, une démonstration ou une collaboration, écrivez à :

📧 **[rarhodes06@gmail.com](mailto:rarhodes06@gmail.com)**

---

<sub>© Tous droits réservés. Le code source n'est ni libre de droits ni ouvert à la réutilisation sans accord écrit de l'éditeur.</sub>

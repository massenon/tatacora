# Captures à prendre ou à reprendre — chapitres 7 à 14 et annexes

Les figures ci-dessous sont **laissées en place** dans `src/part-06.html` à `part-09.html` (aucune image n'a été inventée).
Leur légende a été rendue neutre quand elle affirmait quelque chose de périmé. À reprendre sur la version web en service
(`/pwa/...`, compte administrateur, données de démonstration) avec `capturer.js` / `annoter.js`, puis `rm -rf src/img`.

Colonne « État » : **périmée** = l'écran a changé, la capture contredit le texte ; **à vérifier** = probablement proche, à confronter.

## A. Captures existantes à reprendre

| Fichier attendu | Figure | Écran | Étapes | État |
|---|---|---|---|---|
| `a-inventaire-ouvrir.png` | 7.1 | Inventaires & Fiches ➔ Inventaire physique | Ouvrir l'onglet sans inventaire en cours : le panneau « Cycle d'inventaire par magasin » avec un bouton « Lancer l'inventaire » par ligne (repères : la ligne du magasin, le bouton). Il n'y a plus de liste déroulante ni de « Tous les points ». | périmée |
| `a-inventaire-compter.png` | 7.2 | Inventaire en cours | Lancer un inventaire, cliquer « à compter » sur un article (fenêtre « Enregistrer le comptage », champ « Compté »), puis montrer le tableau avec les boutons de comptage, l'écart et « Clôturer et régulariser ». | périmée |
| `m6-inventaires.png` | 7.3 | Onglet Fiche de stock | Choisir un article, période 30 jours ; vérifier la présence de « Tous les articles » dans la liste et du bouton « Exporter ». | à vérifier |
| `m7-approvisionnement.png` | 7.4 | Approvisionnement, onglet Besoins | Vérifier cinq indicateurs, quatre onglets, bouton « Commander la sélection ». | à vérifier |
| `m8-locations.png` | 8.1 | Véhicules & Locations, onglet Parc & disponibilité | Colonnes « Montant période », boutons Louer / Éditer / Archiver ; boutons « + Véhicule », « + Contrat », « Immobiliser » en tête. | à vérifier |
| `m9-tourisme-departs.png` | 8.2 | Tourisme, onglet Départs planifiés | Boutons « + Réservation » et « + Prestation » (plus de « + Départ » ni de colonne véhicule) ; bandeau « durée indéterminée » s'il y a lieu. | périmée |
| `a-depense-modale.png` | 9.1 | Dépense courante ➔ Nouvelle Dépense | Fenêtre avec lignes, « Montant décaissé » calculé, compte de trésorerie, **Centre de coût**, catégorie de dépenses, reçu (aide « réduite automatiquement… 400 Ko »). Refaire les repères 1 à 5. | périmée |
| `depenses.png` | 9.2 | Dépense courante | Avec une dépense « non comptabilisée » et son bouton « Comptabiliser » ; sélecteur « Exercice » dans la barre supérieure. | à vérifier |
| `m10-syscohada.png` | 9.3 | Comptabilité (hub) | Sélecteur « Exercice » en barre supérieure, six indicateurs, **dix onglets** (dont Immobilisations), puis les onze tuiles. | périmée |
| `m10-comptabilite.png` | 9.4 | Comptabilité (hub), bas de page | Les onze tuiles de pilotage financier (dont « Clôture Périodique » et « États Financiers »). | à vérifier |
| `m10-cloture.png` | 9.5 | Comptabilité ➔ tuile « Clôture Périodique » (`/pwa/comptabilite/cloture`) | Les six groupes de contrôles avec leurs états Conforme / Bloqué / Non vérifiable / Non atteint, **sans** point de blocage « taux d'IS ». | périmée |
| `m13-paie.png` | 10.1 | Personnel & Paie | Bandeau ambre « Charge patronale incomplète », indicateurs, onglets, boutons Excel / PDF. | à vérifier |
| `a-etats.png` | 11.1 | États & Rapports | Barre supérieure avec le sélecteur « Exercice » ; catalogue, pastilles de module, zone d'aperçu (pas de boutons Imprimer / Excel / PDF). | à vérifier |
| `m14-etats.png` | 11.2 | États, Rapports & Exports (`/pwa/etats/bibliotheque`) | Bandeau « Écran remplacé » et historique des éditions. | à vérifier |
| `m12-notifications-hub.png` | 12.1 | Notifications | Bandeau « Seul l'e-mail peut réellement partir, et sous conditions », six compteurs, file avec boutons « Envoyer » / « Transmis à la main » / « Abandonner » et les raisons « Aucune adresse e-mail connue » / « Aucun relais SMTP réel configuré ». | périmée |
| `roles-permissions.png` | 13.2 | Rôles & Permissions | Cartes de rôle (badge « Conforme au socle du CdCF » ou « Matrice amendée »), section « Profil » de la matrice, boutons « + Nouveau rôle » et « Rétablir le socle du CdCF ». | périmée |
| `parametres.png` | 13.3 | Paramètres | Les sept onglets ; montrer l'onglet « Activation & Sécurité » avec **trois** bascules et les rubriques « Charges sociales » et « Exploitation ». | périmée |
| `a-import.png` | 13.1 | Import & Export, onglet Importer | Modèle Excel (.xlsx), bouton « Carte du Gîte Chez Noël (exemple) », formats acceptés, « Valider et contrôler le fichier ». Reprendre les repères 1 à 3. | à vérifier |
| `journal-audit.png` | 13.4 | Journal d'Audit | Six colonnes, détail « type d'élément + libellé », mention de lecture seule. | à vérifier |
| `aide-a-propos.png` | 13.5 | Aide & À propos | Quatorze cartes de module (grisées si sans accès) et la FAQ avec sa recherche. | à vérifier |

## B. Nouvelles captures utiles (aucune figure n'existe encore)

| Nom proposé | À placer | Écran | Étapes |
|---|---|---|---|
| `x-selecteur-exercice.png` | §9.2 | Barre supérieure, sélecteur « Exercice » | Ouvrir la liste (« 2026 — ouvert », « 2025 — clôturé »), en choisir une ancienne : montrer la pastille « Vous consultez 2025 (clôturé) » et le lien « Revenir à 2026 ». |
| `x-compta-clotures.png` | §9.4 | Comptabilité ➔ onglet Clôtures | Liste des exercices avec boutons (Démarrer la clôture, Reprendre la saisie, Clôturer définitivement, Rouvrir), l'avertissement « Des postes n'ont peut-être pas tout envoyé », puis, sur un exercice clôturé d'essai, l'empreinte SHA-256 et « Télécharger l'archive (ZIP) ». |
| `x-compta-immobilisations.png` | §9.2 | Comptabilité ➔ onglet Immobilisations | Tableau et fenêtre « Nouvelle immobilisation » (aucune durée pré-remplie), puis la fenêtre « Plan ». |
| `x-compta-correspondance.png` | §9.2 | Comptabilité ➔ Plan comptable ➔ « Correspondance des comptes » | Les groupes (Produits des ventes, TVA, Trésoreries, Tiers, Résultat) et la fenêtre « Modifier le compte du rôle ». |
| `x-compta-bilan-n1.png` | §9.3 | Comptabilité ➔ onglet Bilan (ou Compte de résultat) | Avec la colonne « Exercice N−1 » et le bandeau de statut de l'exercice. |
| `x-appro-reception.png` | §7.4 | Approvisionnement ➔ Commandes ➔ Réceptionner | La fenêtre avec Commandé / Déjà reçu / Reçu maintenant et le point de stockage. |
| `x-appro-reglement.png` | §7.4 | Approvisionnement ➔ Dettes fournisseurs ➔ Régler | La fenêtre « Régler » (montant, trésorerie). |
| `x-location-contrat.png` | §8.1 | Véhicules & Locations ➔ « + Contrat » | La fenêtre avec l'aperçu « jours × tarif », remise, acompte, reste à payer. |
| `x-location-recu.png` | §8.1 | Onglet Contrats ➔ « Reçu » | Le reçu de location produit (PDF) d'un contrat actif. |
| `x-tourisme-reservation.png` | §8.2 | Tourisme ➔ « + Réservation » | La fenêtre avec Capacité / Déjà vendues / Restantes, le guide et le bouton « Ajouter ». |
| `x-conges-plannings.png` | §10.2 | Congés & Plannings | Onglet Congés avec une demande en attente (Valider / Refuser), puis la fenêtre « Planifier un créneau ». |
| `x-notifications-envoyer.png` | §12.1 | Notifications ➔ File d'attente | Un message e-mail avec « Envoyer », les tentatives et la dernière erreur. |
| `x-parametres-email.png` | §13.2 | Paramètres ➔ Email (SMTP) | Serveur, port, sécurité, utilisateur, mot de passe (valeur masquée, « jamais réaffiché »), « Envoyer un email de test ». |
| `x-parametres-mecef.png` | §13.2 | Paramètres ➔ Identité & Légal, rubrique Facturation normalisée | Le mode « Désactivé » (par défaut), les réglages, le jeton (valeur masquée), « Tester la connexion ». |
| `x-sauvegardes.png` | §13.4 | Import & Export ➔ Sauvegardes de la base | Les quatre indicateurs (rythme « Quotidien (02h00) »), le bandeau « Sauvegarde générée », la liste. |
| `x-reinitialiser.png` | §13.4 | Import & Export ➔ Réinitialiser les données de test | Sur une installation en phase d'essais : les deux listes (vidé / conservé) et la fenêtre où l'on saisit « VIDER ». |
| `x-poste-comptage-inventaire.png` | §7.3 | Poste Windows ➔ Inventaire physique | La phrase « Le comptage n'est écrit qu'à la clôture… » sous la feuille de comptage. |
| `x-poste-compta-bandeaux.png` | §9.3 | Poste Windows ➔ Comptabilité ➔ Compte de résultat | Les bandeaux « pièce(s) saisie(s) à la main comptée(s) en attendant que le serveur la reprenne » et, si possible, « Pièce refusée par le serveur… ». |

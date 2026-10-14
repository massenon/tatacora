<?php

declare(strict_types=1);

/**
 * Messages du registre des ventes encaissées (point de vente, multi-modules).
 *
 * Fichier neuf : `bar.php` sert `VenteBarService`, qui ne connaît que des
 * boissons. Ces messages-ci s'adressent au registre commun, qui mêle plusieurs
 * modules sur un même ticket ; les loger dans `bar.php` aurait laissé croire
 * qu'ils ne concernent que M5.
 */
return [

    'panier_vide' => "Le panier est vide : il n'y a rien à encaisser.",

    'quantite_minimale' => 'La quantité vendue doit être au moins de 1. '
        ."Une quantité à zéro n'est pas une ligne à zéro franc, c'est une ligne qui ne devrait "
        .'pas exister.',

    'mode_paiement_inconnu' => 'Mode de paiement inconnu : :mode.',

    'reference_inconnue' => "L'article :reference est introuvable au catalogue. "
        ."Le prix et le libellé d'une vente sont figés depuis le catalogue, jamais saisis : "
        .'sans référence, il n\'y a rien à figer.',

    'module_non_encaissable' => ':module ne dispose pas encore de catalogue encaissable au comptoir. '
        ."Accepter la ligne obligerait l'écran à transmettre un prix au clavier — c'est l'anti-patron "
        .'que le prototype porte et que ce dépôt refuse.',

    'deja_annulee' => 'La vente :numero est déjà annulée.',

    'motif_sortie_stock' => 'Vente :numero — :article',

    'motif_annulation_stock' => 'Annulation vente :numero',

    'stock_deja_sorti_commande' => 'Stock déjà sorti à la transmission en cuisine '
        .'(commande :commande) : la vente ne le déduit pas une seconde fois.',

    // =====================================================================
    // La pièce comptable — règle du 31/08/2026 : tout mouvement d'argent
    // produit son écriture, dans la même transaction. Chaque refus dit ce
    // qu'il faut configurer, sinon il se lit comme une panne.
    // =====================================================================

    'libelle_ecriture' => 'Vente :numero',

    'libelle_contrepassation' => 'Annulation vente :numero',

    // `tva_sans_compte_collecte` supprimée le 01/09/2026 : la lacune qu'elle
    // nommait est comblée (compte 4431 au plan, décision PO — la vente
    // ventile HT/TVA au lieu de refuser). Une clé morte finit citée comme si
    // elle vivait.

    'compte_produit_absent' => 'Aucun compte de produits n\'est déclaré pour :module. '
        ."La vente est refusée : créditer un compte choisi au plus proche imputerait le chiffre "
        .'d\'affaires au mauvais poste, sur une pièce immuable.',

    'contrepartie_absente' => 'Aucune contrepartie comptable n\'est déclarée pour le mode de '
        .'paiement « :mode ». Tant qu\'on ne sait pas où va l\'argent, la vente n\'est pas '
        .'enregistrée : l\'imputer à la caisse par défaut ferait un fond de caisse faux.',

    'ligne_contrepartie_absente' => "La pièce comptable de cette vente ne porte aucun débit. "
        .'La vente n\'est pas enregistrée : la rattacher à une ligne de produits ferait pointer '
        .'le registre des ventes vers la mauvaise écriture.',

    'piece_introuvable' => 'La pièce comptable de la vente :numero est introuvable ou incomplète : '
        .'son annulation est refusée. Contre-passer une pièce à moitié laisserait le grand livre '
        .'faux du reste, sans que rien ne le signale.',

    'comptabilisation_sur_annulee' => 'La vente :numero est annulée : sa pièce ne peut plus être '
        .'passée. Elle créditerait un compte de produits pour un chiffre d\'affaires qui n\'a pas '
        .'eu lieu, et la contre-passation qui devait l\'équilibrer est derrière nous.',

    // =====================================================================
    // Le PANIER — PA-161. Chaque refus dit ce qu'il protège : un refus qui ne
    // dit pas pourquoi se lit comme une panne.
    // =====================================================================

    'article_sans_prix' => '« :article » n\'a pas de prix à la carte. '
        .'Renseignez-le avant de le porter au panier : un prix saisi au comptoir serait '
        .'un montant que personne n\'a décidé.',

    'sejour_inconnu' => "Ce séjour n'existe pas au registre : un panier appartient à un séjour, "
        .'jamais au poste.',

    'panier_cloture_immuable' => 'Ce panier est clôturé : plus aucune consommation ne peut y entrer '
        .'ni en sortir. La correction passe par l\'annulation de la vente, jamais par le panier — '
        .'sans quoi le panier deviendrait le chemin par lequel on modifie une facture émise.',

    'panier_indestructible' => "Un panier ne se supprime pas. Un panier abandonné reste la trace "
        .'qu\'une table a été ouverte puis quittée ; l\'effacer la rendrait indiscernable '
        .'d\'une table jamais servie.',

    // =====================================================================
    // La REMISE du panier — directive PO du 02/09/2026 (% ou FCFA, net en
    // bcmath, jamais un net négatif). Les refus viennent de l'auteur unique
    // `Panier::remiseSur()`.
    // =====================================================================

    'remise_type_inconnu' => 'Type de remise inconnu. Une remise se dit en pourcentage ou en '
        .'francs — rien d\'autre.',

    'remise_valeur_invalide' => 'La valeur de la remise doit être un nombre positif ou nul.',

    'remise_pourcentage_hors_bornes' => 'Une remise en pourcentage vit entre 0 et 100. Au-delà, '
        .'le total deviendrait négatif : ce n\'est plus une remise, c\'est un montant que '
        .'personne n\'a décidé.',

    'remise_superieure_au_total' => 'La remise dépasse le total du panier : le net serait négatif. '
        .'Réduisez-la, ou retirez-la avant d\'encaisser.',

    'remise_ligne_facture' => 'Remise sur consommations',

    // =====================================================================
    // Les TABLES DE SALLE — `TableSalleService` (02/09/2026), les refus du
    // maître (`tables-engine.js`) avec leur raison.
    // =====================================================================

    'table_espace_inconnu' => 'Espace inconnu : « :espace ». Les espaces sont un registre fermé — '
        .'en ajouter un change la convention de nommage et l\'organisation du service.',

    'table_comptoir_sans_table' => 'Le comptoir ne comporte pas de table : une vente au comptoir '
        .'n\'en exige aucune, lui en inventer une créerait une table à ouvrir et fermer qui ne '
        .'correspond à rien dans la salle.',

    'table_numero_invalide' => 'Le numéro de table doit être un entier positif.',

    'table_existe_deja' => 'La table :libelle existe déjà.',

    'table_introuvable' => 'Table introuvable.',

    'table_panier_ouvert' => 'La table :libelle porte un panier ouvert. Encaissez l\'addition avant '
        .'de la désactiver : les consommations servies n\'auraient plus de table pour les porter '
        .'jusqu\'à l\'addition.',

    'table_jeu_initial_paniers_ouverts' => 'Impossible de rétablir le jeu initial : un panier est '
        .'ouvert sur :libelles. Encaissez ou clôturez d\'abord — rétablir la salle à moitié la '
        .'laisserait dans un état que personne n\'a demandé.',

];

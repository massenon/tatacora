<?php

declare(strict_types=1);

/*
 * Conversion CARTE -> STOCK, partagee par le bar (M5) et le restaurant (M4).
 *
 * ## Pourquoi un fichier a part
 *
 * `CarteBoisson::stockConsommePour()` et
 * `Plat::stockConsommePour()` levent les MEMES refus sur la MEME
 * grandeur : le nombre d'unites vendables par unite de stock. Les repartir
 * entre `bar.php` et `restaurant.php` ferait deux formulations d'une seule
 * erreur, et la premiere divergence passerait inapercue — c'est ce que le
 * depot appelle « deux listes qui finissent par diverger ».
 *
 * Les deux cles etaient APPELEES par le code et n'existaient nulle part :
 * `MessagesUtilisateurTest` echouait dessus, et un RuntimeException leve en
 * production aurait affiche la cle brute « carte.conversion_invalide » a un
 * barman (creees le 31/08/2026).
 *
 * ## Ce que ces refus disent, et pourquoi ils ne se replient pas
 *
 * Un facteur de conversion nul ou absent ne se remplace pas par 1 « pour que
 * ca passe » : le mouvement de stock serait faux d'un facteur inconnu, sur une
 * table financiere, et rien ne le signalerait. Le refus est le livrable — meme
 * discipline que PA-53 sur la paie et PA-19 sur le taux d'IS.
 */

return [
    /*
     * Le schema pose NOT NULL DEFAULT 1 et le service refuse zero : ce cas ne
     * peut venir que d'une ecriture directe en base. Le message le dit, pour
     * que personne ne cherche l'erreur dans l'ecran.
     */
    'conversion_invalide' => 'La conversion vers le stock de « :article » est invalide : le nombre '
        . 'd\'unités vendables par unité de stock doit être strictement positif. '
        . 'Corrigez la fiche article avant toute vente — un mouvement de stock calculé sur '
        . 'cette valeur serait faux sans que rien ne le signale.',

    'conversion_absente' => '« :article » n\'a aucun lien direct au stock : sa consommation ne peut '
        . 'pas être calculée. Reliez-le à un article de stock, ou décrivez-le par une recette.',

    /*
     * Poser le lien SANS son conditionnement laisserait la décrémentation
     * deviner combien sortir. La modale « Lier au stock » pose déjà la
     * question en champ obligatoire ; le service la fait respecter.
     */
    'conversion_requise_avec_lien' => '« :article » est rattaché à un article de stock : le nombre '
        . 'd\'unités vendables par unité de stock devient obligatoire. Sans lui, la vente ne '
        . 'saurait pas quelle fraction d\'unité de stock sortir.',

    'conversion_sans_lien' => '« :article » n\'est rattaché à aucun article de stock : un '
        . 'conditionnement y serait sans objet, et laisserait croire à une décrémentation qui '
        . 'n\'aura pas lieu.',

    'article_stock_inconnu' => 'L\'article de stock :article est introuvable : le lien est refusé ici '
        . 'plutôt que rejeté plus tard par une contrainte, dont le message SQL n\'aiderait '
        . 'personne au comptoir.',

    // --- Disponibilité du jour (M4 et M5) --------------------------------
    //
    // Les codes de motif sont ceux du maître (`carte-engine.js` l.51-55) :
    // `rupture`, `saison`, `retire`. La PWA en écrivait trois autres pour des
    // libellés identiques — divergence invisible à l'écran.

    'motif_inconnu' => 'Motif d\'indisponibilité inconnu : :motif. Les motifs admis sont '
        . '« rupture », « saison » et « retire ».',

    'rayon_inconnu' => 'Rayon de carte inconnu : :rayon.',

    'deja_indisponible' => '« :article » est déjà retiré de la carte (:motif). Remettez-le à la '
        . 'carte avant de poser un autre motif — deux motifs simultanés rendraient le retour '
        . 'ambigu.',

    'pas_indisponible' => '« :article » est déjà à la carte : il n\'y a rien à lever. Le dire plutôt '
        . 'que de confirmer une action qui n\'a pas eu lieu.',

    'decision_non_imputable' => 'Retirer un article de la carte est une décision de gestion : elle '
        . 'doit être imputable à un utilisateur identifié.',
];

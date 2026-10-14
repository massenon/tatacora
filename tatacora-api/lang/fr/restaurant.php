<?php

declare(strict_types=1);

/*
 * Messages du domaine Restaurant (M4).
 */

return [
    'recette_manquante' => 'Le plat « :plat » n\'a pas de fiche technique : sa vente ne pourrait '
        // Article 8 (02/09/2026) : la reference RG-05 vit ici, jamais a l'ecran.
        . 'décrémenter aucun stock. Renseignez sa recette avant de le mettre à la carte.',
    'commande_vide' => 'Une commande doit comporter au moins une ligne.',
    'deja_transmise' => 'Cette commande a déjà été transmise en cuisine.',
    'annulee_non_transmissible' => 'Une commande annulée ne peut pas être transmise.',
    'annulation_apres_transmission' => 'Cette commande est déjà en cuisine : les ingrédients sont engagés. '
        . 'Enregistrez une perte de stock plutôt qu\'une simple annulation.',
    'service_avant_transmission' => 'Une commande non transmise en cuisine ne peut pas être servie.',
    'motif_vente' => 'Vente restaurant — :plat ×:quantite',

    /*
     * Éléments du maître que l'API ne rend PAS, et pourquoi. Le client les
     * affiche à la place d'un chiffre : « — » et « 0 » ne disent pas la même
     * chose, et un indicateur qui affirme un état qu'il n'a pas vérifié est le
     * défaut nommé en PA-59/60/61.
     */
    'absent' => [
        'disponibilite' => 'La disponibilité du jour n\'est portée par aucune colonne du schéma : '
            . 'ni un plat retiré de la carte, ni son motif ne peuvent être enregistrés. '
            . 'Arbitrage en attente ; aucun chiffre n\'est produit d\'ici là.',
        // `prix_provisoire` a été RETIRÉ le 02/09/2026 : la colonne existe
        // (migration `2026_09_02_200000`), l'indicateur se compte, et laisser
        // ici le motif de son refus le ferait vieillir en oubli (PA-144).
    ],

    /*
     * Validation de l'API M4. Chaque message dit CE QUI est refusé et POURQUOI :
     * un refus muet renvoie l'utilisateur essayer exactement la même chose.
     */
    'validation' => [
        'libelle_obligatoire' => 'Le libellé est obligatoire.',
        'categorie_obligatoire' => 'La catégorie est obligatoire.',
        'categorie_inconnue' => 'Catégorie inconnue. Le registre est fermé : local, europeen, special. '
            . 'Un filtre incompris serait ignoré, et la carte entière s\'afficherait sous un '
            . 'intitulé qui promet le contraire.',
        'categorie_du_menu' => 'La catégorie ne se saisit pas sur un plat : elle est celle de son menu. '
            . 'La porter aussi sur le plat créerait une seconde vérité, qui divergerait au premier '
            . 'reclassement de menu.',
        'menu_obligatoire' => 'Un plat appartient obligatoirement à un menu : c\'est le menu qui porte '
            . 'sa catégorie et sa période de validité.',
        'menu_inexistant' => 'Menu inconnu. Un menu se choisit dans la liste, il ne se saisit pas en '
            . 'texte libre.',
        'recette_obligatoire' => 'Un plat porte obligatoirement une fiche technique : sans elle, sa vente '
            // Article 8 (02/09/2026) : la reference RG-05 vit ici, jamais a l'ecran.
            . 'ne décrémenterait aucun stock.',
        'recette_inexistante' => 'Fiche technique inconnue du référentiel.',
        'prix_obligatoire' => 'Le prix de vente est obligatoire.',
        'prix_negatif' => 'Le prix de vente ne peut pas être négatif.',
        'saison_inversee' => 'La fin de validité précède son début : ce menu ne rendrait jamais aucun '
            . 'plat, et la carte s\'afficherait vide sans dire pourquoi.',
        'periode_inversee' => 'La fin de période précède son début.',
        'page_trop_grande' => 'Taille de page trop grande : :max éléments au maximum.',

        'ingredients_texte_libre' => 'Les ingrédients ne se saisissent pas en texte libre. Une chaîne de '
            . 'caractères ne se rattache à aucun article, donc ne décrémente aucun stock, et la fiche '
            // Article 8 (02/09/2026) : la reference PA-23 vit ici, jamais a l'ecran.
            . 'technique ne sert à rien. Utilisez la composition de la recette : de vrais '
            . 'articles avec leurs quantités.',
        'disponibilite_sans_schema' => 'Aucune colonne du schéma ne porte cette information. L\'accepter '
            . 'sans la stocker laisserait croire qu\'elle a été enregistrée, et un plat resterait à la '
            . 'carte — ou en serait retiré — sans que personne ne sache pourquoi.',
        'etat_sans_schema' => 'Ce filtre porte sur une information qu\'aucune colonne du schéma ne '
            . 'contient. L\'ignorer rendrait la carte ENTIÈRE sous un intitulé qui promet le contraire.',
        'etat_inconnu' => 'Filtre d\'état inconnu. Le registre est fermé : lie, sans_lien, rupture_stock, '
            . 'provisoire.',
        'valeur_calculee' => 'Cette valeur est calculée : elle s\'affiche, elle ne se saisit pas. La '
            . 'soumettre n\'aurait aucun effet et laisserait croire qu\'elle a été prise en compte.',
        'cout_matiere_calcule' => 'Le coût matière se calcule depuis la composition de la recette et le '
            . 'coût moyen pondéré de chaque article : il ne se saisit pas. Une valeur soumise ici '
            . 'divergerait de sa composition dès le premier ingrédient ajouté.',

        'composition_absente' => 'La composition est obligatoire. Un tableau vide est accepté — c\'est le '
            . 'seul moyen de vider une fiche erronée — mais il doit être envoyé explicitement.',
        'article_obligatoire' => 'Chaque ligne de composition désigne un article du référentiel.',
        'article_inexistant' => 'Article inconnu du référentiel. Un ingrédient se choisit dans la liste, '
            . 'il ne se saisit pas en texte libre : la déduction de stock suppose une relation exacte.',
        'ingredient_en_double' => 'Cet article figure deux fois dans la composition. Les quantités sont '
            . 'relues article par article : la seconde ligne écraserait la première, et le plat '
            . 'consommerait moins que sa fiche ne l\'indique.',
        'quantite_recette_obligatoire' => 'La quantité unitaire est obligatoire.',
        'quantite_recette_positive' => 'La quantité unitaire doit être strictement positive : un '
            . 'ingrédient à zéro n\'est pas un ingrédient, c\'est une ligne à retirer.',

        'plat_obligatoire' => 'Chaque ligne de commande désigne un plat de la carte.',
        'plat_inexistant' => 'Plat inconnu de la carte.',
        'client_inexistant' => 'Client inconnu du référentiel.',
        'quantite_obligatoire' => 'La quantité est obligatoire.',
        'quantite_positive' => 'La quantité doit être strictement positive : une saisie à zéro n\'est pas '
            . 'une ligne de commande, et elle serait pourtant transmise en cuisine.',
        'statut_non_saisissable' => 'Le statut ne se saisit pas : il résulte de la prise de commande, de '
            . 'la transmission en cuisine et du service, chacune ayant ses propres conséquences sur le '
            . 'stock.',
        'statut_inconnu' => 'Statut de commande inconnu. Un filtre incompris serait ignoré, et le '
            . 'registre entier s\'afficherait sous un intitulé qui promet le contraire — un écran '
            . '« transmises » qui montre tout ferait préparer des commandes annulées.',
        'montant_sans_schema' => 'Une commande restaurant ne transporte aucun montant : ses lignes ne '
            . 'figent aucun prix unitaire au schéma, et un total recalculé au tarif du jour serait faux '
            . 'pour toute commande antérieure à un changement de carte.',
        'identifiant_non_accepte' => 'Une commande restaurant ne reçoit pas d\'identifiant du client : '
            . 'cette table n\'est pas synchronisable et aucun mécanisme de rejeu n\'existe. En accepter '
            . 'un laisserait croire à une idempotence qui n\'a pas lieu.',
        'identifiant_non_modifiable' => 'L\'identifiant ne se modifie pas.',
    ],
];

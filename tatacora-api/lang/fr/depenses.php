<?php

declare(strict_types=1);

/**
 * Messages des dépenses courantes et du passage d'écriture (M10).
 *
 * Fichier neuf : `comptabilite.php` existe déjà et sert les états et les
 * écritures. Ces messages-ci s'adressent à un opérateur au comptoir, pas au
 * Comptable, et ils nomment ce qui bloque la SAISIE — les mélanger aurait
 * rendu les deux registres illisibles.
 *
 * Aucun de ces messages ne décrit un repli. Chacun décrit un refus, et dit où
 * le corriger : une dépense refusée n'est pas enregistrée du tout, et c'est
 * délibéré (voir le bloc de tête de `DepenseService`).
 */
return [

    // --- Saisie ----------------------------------------------------------

    'sans_ligne' => 'Une dépense doit porter au moins une ligne de ventilation : '
        ."sans compte de charge, il n'y a rien à imputer.",

    'montant_nul' => 'Le montant total de la dépense est nul : une pièce à zéro est équilibrée '
        ."mais n'enregistre rien.",

    'tresorerie_inconnue' => 'Trésorerie inconnue : :code. Les trésoreries admises sont '
        .'« caisse », « momo » et « banque ».',

    'libelle_par_defaut' => "Dépense d'exploitation",

    'nature_par_defaut' => 'Autre',

    'famille_par_defaut' => 'Services',

    'libelle_ecriture' => 'Dépense — :libelle',

    // --- Passage de l'écriture -------------------------------------------

    'journal_inconnu' => 'Journal comptable inconnu : :code. Le référentiel des journaux doit être '
        ."renseigné avant toute saisie — l'écriture est refusée plutôt qu'imputée à un journal "
        .'choisi au hasard.',

    'compte_inconnu' => 'Compte comptable inconnu : :numero. Le plan comptable ne le contient pas. '
        ."Choisissez un compte du plan plutôt qu'un numéro saisi de mémoire : une imputation "
        .'erronée sur une pièce validée ne se corrige que par contre-passation.',

    'exercice_absent' => 'Aucun exercice comptable ne couvre la date :date. Créez-le avant de saisir : '
        ."une écriture hors exercice n'apparaîtrait dans aucun état.",

    'exercice_clos' => "L'exercice :annee est :statut : aucune écriture ne peut plus y être ajoutée. "
        .'Datez la pièce sur un exercice ouvert, ou faites rouvrir celui-ci.',

    'centre_absent' => 'Le compte :numero ne porte aucun centre de coût par défaut, et aucun centre '
        ."n'a été précisé. RG-12 rend le centre de coût obligatoire : sans lui, la comptabilité "
        ."analytique serait fausse sans qu'aucun total ne bouge.",

    'ligne_tresorerie_absente' => "La pièce ne porte aucune contrepartie de trésorerie sur le compte "
        .':compte : la dépense ne peut pas être rattachée à son écriture.',

];

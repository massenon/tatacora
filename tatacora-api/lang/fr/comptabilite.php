<?php

declare(strict_types=1);

/*
 * Messages du domaine Comptabilite (M10) — TVA incluse.
 */

return [
    'convention_inconnue' => 'Convention de prix inconnue : « :convention ». '
        . 'Valeurs admises : « ht » ou « ttc » (paramètre « :cle »).',
    'taux_absent' => 'Le taux de TVA n\'est pas paramétré (:cle). '
        . 'Aucun montant de taxe ne peut être calculé tant qu\'un Administrateur ne l\'a pas renseigné.',
    'compte_absent' => 'Le compte :compte est absent du plan comptable. '
        . 'La déclaration de TVA ne peut pas être établie : un solde à zéro serait interprété '
        . 'comme une absence d\'opérations, non comme un compte manquant.',
    'plan_fichier_illisible' => 'Le fichier du plan comptable est introuvable ou illisible.',
    'plan_fichier_ligne_invalide' => 'Le fichier du plan comptable est invalide à la ligne :ligne.',
    'compte_division' => 'Le compte :numero est une division du plan comptable : il ne reçoit aucun mouvement. Choisissez un de ses sous-comptes.',
    'periode_invalide' => 'La période de déclaration doit être un mois au format AAAA-MM.',
    'periode_deja_declaree' => 'La période :periode a déjà fait l\'objet d\'une déclaration.',
    'declaration_verrouillee' => 'Cette déclaration est validée : elle ne peut plus être recalculée. '
        . 'Corrigez par une déclaration rectificative.',

    /*
     * Ecritures comptables — RG-11 (immutabilite / contre-passation), RG-12.
     */
    // Article 8 (02/09/2026) : la reference RG-11 vit ici, jamais a l'ecran.
    'ecriture_immuable' => 'Cette écriture est validée : elle ne peut plus être modifiée. '
        . 'La seule correction admise est la contre-passation, qui conserve la trace des deux mouvements.',
    'ecriture_suppression_interdite' => "Une écriture comptable ne se supprime jamais, même en brouillon : "
        . "un trou dans la séquence est précisément ce qu'un contrôle fiscal recherche. "
        . 'Utilisez la contre-passation.',
    'exercice_clos' => 'Cet exercice est clôturé : aucune écriture ne peut plus y être ajoutée ni modifiée.',
    'ecriture_deja_validee' => 'Cette écriture est déjà validée.',
    'contrepassation_sur_brouillon' => 'Une écriture en brouillon se corrige directement : '
        . 'la contre-passer ajouterait deux lignes inutiles au grand livre.',
    'deja_contrepassee' => 'Cette écriture a déjà été contre-passée. '
        . "Une seconde contre-passation rétablirait l'écriture d'origine "
        . 'tout en laissant croire à une annulation.',
    'libelle_contrepassation' => 'Contre-passation — :libelle',
    'piece_vide' => 'Une pièce comptable doit comporter au moins une ligne.',
    'piece_sans_montant' => "Une pièce à zéro est équilibrée mais n'enregistre rien.",
    'piece_desequilibree' => 'Pièce déséquilibrée : :debit au débit contre :credit au crédit '
        . "(écart de :ecart). Une écriture non équilibrée fausse le bilan sans qu'aucun compte "
        . 'pris isolément ne le montre.',

    /*
     * Etats fondateurs — Journal General, Grand Livre, Balance Generale
     * (EF-M10-06). Le refus de volume nomme le geste qui debloque : sans lui,
     * l'utilisateur ne saurait pas quoi faire de l'echec.
     */
    'etat_trop_volumineux' => 'Cet état compte :lignes lignes, au-delà des :maximum '
        . "qu'il peut restituer d'un seul bloc. Ses totaux et son contrôle d'équilibre portent sur "
        . "l'ensemble affiché : les tronquer produirait un déséquilibre qui n'existe pas. "
        . 'Filtrez par journal pour réduire la période consultée.',

    /*
     * Notes Annexes — MODULE_COMPTABILITE_COMPLET_PART4.md §1.1.
     *
     * La note 1 est le SEUL contenu statique versionne des sept notes : le
     * referentiel applique et les deux methodes d'evaluation retenues. Elle
     * vit ici et non dans le service, pour la meme raison que toute chaine
     * visible du depot — un texte francais en dur dans du PHP echappe a la
     * relecture de qui tient la langue, et `MessagesUtilisateurTest` refuse
     * d'ailleurs toute chaine accentuee dans un message technique.
     *
     * Les deux methodes citees ne sont pas decoratives : le cout moyen pondere
     * est celui de `03_DATABASE_ENGINEERING.md` §7, l'amortissement lineaire
     * celui d'`ATELIER_PLAN_COMPTABLE.md` §5.4. Changer l'une des deux dans le
     * code SANS changer cette note ferait signer au Comptable des etats
     * financiers qui decrivent une methode qui n'est plus appliquee.
     */
    'notes' => [
        'regles_et_methodes' => 'Comptabilité tenue conformément au référentiel SYSCOHADA '
            . 'révisé, Système Normal. Évaluation des stocks au coût moyen pondéré. '
            . "Amortissement linéaire sur la durée d'usage estimée de chaque catégorie "
            . "d'immobilisation.",
    ],

    'validation' => [
        'exercice_requis' => "L'exercice comptable est obligatoire : un état « toutes années "
            . "confondues » n'aurait pas de sens comptable.",
        'exercice_inexistant' => "Cet exercice comptable n'existe pas.",
        'compte_requis' => 'Le compte est obligatoire pour consulter un grand livre.',
        'compte_inexistant' => "Ce compte est absent du plan comptable.",
        'journal_inexistant' => "Ce journal comptable n'existe pas.",
        'classe_inconnue' => 'Classe comptable inconnue. Valeurs admises : :valeurs.',
        'statut_inconnu' => "Filtre de statut inconnu. Valeurs admises : :valeurs.",
    ],

    /*
     * Plan comptable — création d'un compte (Vague E, 01/09/2026),
     * `PlanComptableService::creerCompte()`.
     */
    'compte_numero_invalide' => 'Numéro de compte invalide : « :numero ». '
        . 'Un compte du plan comptable porte de deux à quatre chiffres, le premier de 1 à 9.',
    'compte_libelle_requis' => "L'intitulé du compte est obligatoire.",
    'compte_nature_invalide' => 'Nature de compte inconnue : « :nature ». '
        . 'Valeurs admises : actif, passif, charge, produit.',
    'compte_deja_existant' => 'Le compte :numero existe déjà au plan comptable.',
    'compte_inconnu' => 'Compte comptable inconnu : :numero. Le plan comptable ne le contient pas.',

    /*
     * Immobilisations — `ImmobilisationService::creer()` (Vague E, 01/09/2026).
     */
    'immobilisation_libelle_requis' => "Le libellé de l'immobilisation est obligatoire.",
    'immobilisation_valeur_invalide' => "La valeur d'origine doit être strictement positive.",
    'immobilisation_duree_requise' => "La durée d'utilité (en années) est obligatoire : c'est une "
        . "estimation propre à l'entité (AUDCIF art. 45), jamais un barème déduit du type de bien.",
    'immobilisation_date_invalide' => 'La date de mise en service est obligatoire et doit être une date valide.',

    /*
     * Exercices comptables — ouverture et clôture (Vague E, 01/09/2026),
     * `ExerciceComptableService`. Périmètre volontairement minimal : voir le
     * docblock de la classe.
     */
    'exercice_annee_invalide' => "L'année de l'exercice doit être comprise entre 2000 et 2100.",
    'exercice_deja_existant' => "L'exercice :annee existe déjà.",
    'exercice_deja_cloture' => "L'exercice :annee est déjà clôturé.",
    'cloture_brouillons_restants' => "L'exercice :annee ne peut pas être clôturé : :nombre écriture(s) "
        . "en brouillon y subsistent encore. Validez-les ou contre-passez-les avant de clôturer — "
        . "une pièce en brouillon n'est pas opposable, la clôturer verrouillerait l'exercice sur "
        . "un état que personne n'a confirmé.",

    /*
     * Clôture SYSCOHADA annuelle (lot 2, décisions du PO du 20/10/2026 :
     * clôture ANNUELLE, réouverture par LE COMPTABLE) — `ClotureExerciceService`.
     */
    'cloture_demarrage_impossible' => "La clôture de l'exercice :annee ne peut pas démarrer : il est :statut (seul un exercice ouvert peut entrer en clôture).",
    'cloture_reprise_impossible' => "La saisie de l'exercice :annee ne peut pas reprendre : il est :statut.",
    'cloture_exige_en_cloture' => "L'exercice :annee doit d'abord entrer en clôture (« Démarrer la clôture ») : les modules n'y passent alors plus de pièce, seules les écritures d'inventaire du comptable y entrent.",
    'cloture_ordre' => "L'exercice :annee ne peut pas être clôturé avant l'exercice :precedent : les exercices se clôturent dans l'ordre (ses à-nouveaux en dépendent).",
    'cloture_conditions_non_reunies' => "L'exercice :annee ne peut pas être clôturé : :blocages",
    'cloture_suivant_clos' => "L'exercice :annee est déjà clôturé : les à-nouveaux ne peuvent pas y être reportés.",
    'libelle_piece_cloture' => 'Clôture :annee — solde des comptes de gestion',
    'libelle_piece_a_nouveaux' => 'À-nouveaux de l\'exercice :annee',
    'libelle_reouverture' => 'Réouverture de l\'exercice :annee — :motif',
    'reouverture_reservee' => 'Seul le comptable peut rouvrir un exercice clôturé.',
    'reouverture_non_cloture' => "L'exercice :annee n'est pas clôturé : il n'y a rien à rouvrir.",
    'reouverture_motif' => 'Le motif de la réouverture est obligatoire (:min caractères au moins) : il est écrit au journal d\'audit et sur les contre-passations.',
    'reouverture_suivant_clos' => "L'exercice :annee ne peut pas être rouvert : l'exercice :suivant, qui porte ses à-nouveaux, est déjà clôturé. Rouvrez d'abord :suivant.",

    // --- Archive légale de clôture (lot 4, 20/10/2026) ----------------------
    'archive_cloture_rouverte' => 'Cette clôture a été rouverte : son archive n\'est plus celle de l\'exercice.',
    'archive_sans_cloture' => "Cet exercice n'a pas de clôture active : il n'y a pas d'archive.",
    'archive_alteree' => "L'archive de clôture ne correspond plus à son empreinte : un fichier a été modifié ou supprimé. Elle n'est pas délivrée.",
];

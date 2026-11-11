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
    'reouverture_reservee' => 'Seul le comptable ou le gérant peut rouvrir un exercice clôturé.',
    'reouverture_non_cloture' => "L'exercice :annee n'est pas clôturé : il n'y a rien à rouvrir.",
    'reouverture_motif' => 'Le motif de la réouverture est obligatoire (:min caractères au moins) : il est écrit au journal d\'audit et sur les contre-passations.',
    'reouverture_suivant_clos' => "L'exercice :annee ne peut pas être rouvert : l'exercice :suivant, qui porte ses à-nouveaux, est déjà clôturé. Rouvrez d'abord :suivant.",

    // --- Archive légale de clôture (lot 4, 20/10/2026) ----------------------
    'archive_cloture_rouverte' => 'Cette clôture a été rouverte : son archive n\'est plus celle de l\'exercice.',
    'archive_sans_cloture' => "Cet exercice n'a pas de clôture active : il n'y a pas d'archive.",
    'archive_alteree' => "L'archive de clôture ne correspond plus à son empreinte : un fichier a été modifié ou supprimé. Elle n'est pas délivrée.",

    // --- Demandes de clôture envoyées par un poste (26/10/2026) ---------------
    'demande_cloture_exercice_inconnu' => "L'exercice :annee n'existe pas sur le serveur : la demande de clôture ne peut pas être exécutée.",
    'demande_cloture_action_inconnue' => 'Action de clôture inconnue : « :action ». Valeurs admises : :admises.',

    // --- Affectation du résultat d'un exercice clôturé (09/11/2026) ------------
    // `AffectationResultatService`. Le poste Windows reprend ces phrases AU MOT
    // (`messages_affectation.dart`), confrontées au vrai PHP par un test.
    'affectation_reservee' => "Seul le comptable ou le gérant peut passer ou contre-passer l'affectation du résultat.",
    'affectation_exige_cloture' => "L'exercice :annee n'est pas clôturé : son résultat ne peut pas être affecté avant sa clôture.",
    'affectation_resultat_nul' => "Le résultat de l'exercice :annee est nul : il n'y a rien à affecter.",
    'affectation_deja_passee' => "Le résultat de l'exercice :annee est déjà affecté (pièce :piece). Contre-passez cette affectation avant d'en passer une autre.",
    'affectation_date_invalide' => "La date de l'approbation des comptes ou de la décision de l'exploitant « :date » n'est pas une date valide.",
    'affectation_date_hors_exercice' => "La date de l'approbation des comptes ou de la décision de l'exploitant (:date) doit tomber dans l'exercice :annee, celui qui suit l'exercice clôturé.",
    'affectation_exercice_non_ouvert' => "L'exercice :annee est :statut : l'affectation du résultat ne peut être passée que dans un exercice ouvert.",
    'affectation_montant_illisible' => "Le montant de « :poste » n'est pas lisible (« :valeur ») : saisissez un nombre positif, deux décimales au plus.",
    'affectation_montant_negatif' => "Le montant de « :poste » ne peut pas être négatif.",
    'affectation_dividende_sur_perte' => "Aucun dividende ne se verse sur une perte : le résultat à affecter est une perte.",
    'affectation_reserve_legale_sur_perte' => "Une perte ne s'affecte pas à la réserve légale : elle se reporte à nouveau ou s'impute sur les réserves.",
    'affectation_imputation_sur_benefice' => "L'imputation sur le report à nouveau créditeur ne vaut que pour une perte.",
    'affectation_somme_differente' => "La ventilation totalise :somme alors que le résultat à affecter est de :resultat (écart :ecart) : elle doit l'égaler exactement.",
    'affectation_imputation_excessive' => "L'imputation sur « :poste » (:montant) dépasse son solde créditeur (:solde).",
    'affectation_centre_absent' => "Le centre de coût « :centre » est introuvable : l'affectation du résultat ne peut pas être passée.",
    'affectation_motif' => "Le motif de la contre-passation est obligatoire (:min caractères au moins) : il est écrit au journal d'audit et sur les contre-passations.",
    'affectation_aucune' => "Le résultat de l'exercice :annee n'a aucune affectation active : il n'y a rien à contre-passer.",
    'affectation_contrepassation_exercice_clos' => "L'affectation du résultat de l'exercice :annee ne peut pas être contre-passée : l'exercice :suivant, qui la porte, est clôturé. Rouvrez d'abord :suivant.",
    'affectation_piece_divergente' => "La pièce d'affectation envoyée par le poste ne correspond pas à celle que le serveur passerait pour cette ventilation : vérifiez la correspondance des comptes des deux côtés.",
    'affectation_poste_reserve_legale' => 'Réserve légale',
    'affectation_poste_autres_reserves' => 'Autres réserves',
    'affectation_poste_dividendes' => 'Dividendes',
    'affectation_poste_report_a_nouveau' => 'Report à nouveau',
    'affectation_poste_imputation_report_crediteur' => 'Imputation sur le report à nouveau créditeur',
    'affectation_poste_compte_exploitant' => "Compte de l'exploitant",
    // Forme juridique (09/11/2026) : entreprise individuelle (défaut du Gîte), SARL, SA.
    'forme_juridique_entreprise_individuelle' => 'Entreprise individuelle',
    'forme_juridique_sarl' => 'SARL',
    'forme_juridique_sa' => 'SA',
    'affectation_ei_reserve_legale' => "Une entreprise individuelle n'a pas de réserve légale : le montant de la réserve légale doit être nul. Ventilez entre le compte de l'exploitant, le report à nouveau et les autres réserves.",
    'affectation_ei_dividende' => "Une entreprise individuelle ne verse pas de dividendes (compte 465) : le bénéfice revient à l'exploitant. Portez-le au compte de l'exploitant, au report à nouveau ou aux autres réserves.",
    'affectation_societe_compte_exploitant' => "Le compte de l'exploitant n'existe que dans une entreprise individuelle : la forme juridique de l'établissement est « :forme ». Ventilez entre les postes d'une société.",
    'affectation_reserve_legale_insuffisante' => "La réserve légale est obligatoire : elle doit recevoir au moins :minimum (10 % de :base, le bénéfice net des pertes antérieures de :pertes), tant qu'elle n'atteint pas 20 % du capital (:capital) ; la ventilation en prévoit :saisi.",
    'affectation_dividende_capitaux_propres' => "La distribution de :dividendes ferait passer les capitaux propres à :apres, sous le capital augmenté des réserves non distribuables (:plancher) : un dividende ne peut pas entamer le capital ni les réserves que la loi interdit de distribuer.",
    'affectation_avertissement_capital_indetermine' => "Le capital n'est pas déterminable (aucun solde créditeur au compte 101) : la réserve légale obligatoire ne peut pas être contrôlée et aucune n'est proposée. À vérifier avec le comptable avant de passer l'affectation.",
    'affectation_alerte_moitie_capital' => "ALERTE : après cette perte, les capitaux propres (:propres) sont inférieurs à la moitié du capital (:capital). L'assemblée doit se prononcer dans les quatre mois sur la poursuite de l'activité (Acte uniforme, art. 664 : à faire confirmer par le comptable).",
    'affectation_contrepassation_exercice_non_ouvert' => "L'affectation du résultat de l'exercice :annee ne peut pas être contre-passée : l'exercice :suivant, qui la porte, est :statut. La contre-passation ne se passe que dans un exercice ouvert.",
    'affectation_contrepassation_date_hors_exercice' => "La contre-passation se date du jour de la correction (:date) : elle doit tomber dans l'exercice :suivant, qui porte l'affectation.",
    'affectation_contrepassation_anterieure' => "La contre-passation (:date) ne peut pas être datée avant la pièce d'affectation (:origine).",
    'affectation_dividende_regle' => "L'affectation du résultat de l'exercice :annee ne peut pas être contre-passée : un dividende est déjà réglé en tout ou partie (:regle réglé sur :dividendes). Annulez d'abord le règlement du dividende, puis contre-passez l'affectation.",
    'affectation_reference_trop_longue' => 'La référence de la décision est limitée à :max caractères.',
    'libelle_affectation_resultat' => "Affectation du résultat de l'exercice :annee",
    'libelle_contrepassation_affectation' => "Contre-passation de l'affectation du résultat :annee — :motif",
    'reouverture_affectation_active' => "L'exercice :annee ne peut pas être rouvert : son résultat est affecté (pièce :piece). Contre-passez d'abord l'affectation du résultat.",
];

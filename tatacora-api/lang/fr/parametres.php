<?php

declare(strict_types=1);

/*
| Ecran Parametres — messages destines a l'utilisateur.
|
| Aucune chaine accentuee ne doit vivre dans un `throw` ou un `abort()`
| (MessagesUtilisateurTest) : les refus du service d'ecriture passent tous par
| ces cles.
*/

return [
    'cle_inconnue' => 'Le paramètre « :cle » n’existe pas. Aucun paramètre n’est '
        . 'créé depuis cet écran : une clé que rien ne lit donnerait l’illusion '
        . 'd’un réglage sans effet.',

    'tva_sans_taux' => 'La TVA ne peut pas être active sans taux. Renseignez '
        . '« :cle_taux » dans le même enregistrement, ou désactivez « :cle_active » : '
        . 'sinon l’émission de la facture serait refusée au comptoir, devant le client.',

    'convention_invalide' => 'Convention de prix « :convention » inconnue. '
        . 'Les seules valeurs admises sont « ht » (la TVA s’ajoute aux tarifs) '
        . 'et « ttc » (elle en est extraite).',

    /*
    | Facturation normalisée (MECeF) — docs/SPEC_FACTURATION_NORMALISEE_MECEF.md.
    | Aucun message ne cite le jeton.
    */
    'mecef_manque_ifu' => 'L’IFU de l’entreprise doit compter 13 chiffres (Identité & Légal).',
    'mecef_manque_https' => 'L’adresse de l’API de la DGI doit commencer par https://.',
    'mecef_manque_operateur' => 'L’identifiant et le nom de l’opérateur sont obligatoires.',
    'mecef_manque_jeton' => 'Le jeton e-MECeF n’est pas enregistré.',
    'mecef_ifu_invalide' => 'L’IFU doit compter exactement 13 chiffres.',
    'mecef_mode_refuse' => 'Le mode « :mode » ne peut pas être choisi : :manques',
    'forme_juridique_inconnue' => 'La forme juridique « :valeur » n’existe pas : choisissez parmi :admises.',
    'forme_juridique_reservee_administrateur' => 'La forme juridique est réservée aux Administrateurs.',
    'forme_juridique_affectation_active' => 'La forme juridique ne peut pas être changée tant qu’une affectation du résultat est active : contre-passez d’abord l’affectation (onglet Clôtures de la Comptabilité), puis changez la forme.',
    'mecef_reserve_administrateur' => 'Le mode de facturation normalisée et ses réglages sont réservés aux Administrateurs.',
    'mecef_jeton_illisible' => 'Ce texte n’a pas la forme d’un jeton JWT (trois parties séparées par des points, sans espace).',
    'mecef_jeton_requis' => 'Le mode e-MECeF est actif : changez d’abord de mode avant d’effacer le jeton.',
    'mecef_test_sans_jeton' => 'Aucun jeton enregistré : saisissez d’abord le jeton e-MECeF.',
    'mecef_test_injoignable' => 'La DGI est injoignable (réseau ou adresse). Rien n’a été modifié.',
    'mecef_test_jeton_refuse' => 'La DGI a refusé le jeton : vérifiez-le, ou remplacez-le.',
    'mecef_test_jeton_perime' => 'La DGI répond, mais le jeton est périmé : saisissez un nouveau jeton.',
    'mecef_test_limite' => 'La DGI limite le nombre de requêtes : réessayez dans une minute.',
    'mecef_test_code' => 'La DGI a répondu avec le code :code : vérifiez l’adresse de l’API.',
    'mecef_test_ifu_different' => 'Le jeton appartient à l’IFU :compte, et l’IFU de l’entreprise est :reglage.',
    'mecef_test_ok' => 'Connexion réussie : la DGI répond et accepte le jeton.',

    /*
    | La FORME d'une valeur arrivée d'un poste (09/11/2026, `ControleValeurParametre`) :
    | les mêmes phrases que le poste (`normaliser`), confrontées par un test.
    */
    'valeur_trop_longue' => '« :libelle » ne peut pas dépasser :max caractères.',
    'valeur_https' => '« :libelle » doit commencer par https:// et ne contenir aucun espace.',
    'valeur_alphanumerique' => '« :libelle » n’accepte que des lettres et des chiffres.',
    'valeur_choix_inconnu' => '« :libelle » : la valeur « :valeur » n’est pas admise.',
    'valeur_entier' => '« :libelle » doit être un nombre entier, sans signe ni décimale.',
    'valeur_entre' => '« :libelle » doit être compris entre :min et :max.',
    'valeur_au_moins' => '« :libelle » doit être au moins :min.',
    'valeur_au_plus' => '« :libelle » doit être au plus :max.',
    'valeur_booleen' => '« :libelle » est un interrupteur : choisissez Oui ou Non, il ne se vide pas.',

    'enregistre' => 'Paramètres enregistrés.',
    'aucun_changement' => 'Aucune valeur modifiée.',

    /*
    | Gestion des canaux de réservation — CanalReservationService (01/09/2026).
    | Même contrat que les refus ci-dessus : RuntimeException traduite,
    | attrapée par le composant et affichée sous le champ concerné.
    */
    'canal_nom_requis' => 'Le nom du canal est obligatoire.',
    'canal_nom_deja_utilise' => 'Un canal nommé « :nom » existe déjà. Renommez-le plutôt que d’en créer un '
        . 'second : deux canaux du même nom rendraient l’analyse par canal ambiguë.',
    'canal_introuvable' => 'Ce canal n’existe plus.',
    'canal_enregistre' => 'Canal enregistré.',
    'canal_bascule' => 'État du canal mis à jour.',

    'etats' => [
        'tva' => [
            'inactive' => 'TVA inactive — aucune taxe n’est ajoutée aux factures.',
            'activee_sans_taux' => 'TVA activée SANS TAUX — l’émission de facture est refusée.',
            'activee_convention_invalide' => 'TVA activée, mais la convention de prix est illisible.',
            'active' => 'TVA active.',
        ],
        'mecef' => [
            // Reprise le 02/09/2026 (passage navigateur) : depuis le passage
            // au réel du 01/09/2026, les documents ne portent plus de mention
            // « démonstration » — ils disent l'attente d'inscription DGI.
            'non_configuree' => 'MECeF non configurée — les factures mentionnent que la certification '
                . 'électronique est en attente d\'inscription auprès de la DGI.',
            'configuration_partielle' => 'Numéro contribuable renseigné, clé d’API absente en configuration serveur.',
            // Article 8 + reprise du 02/09/2026 (la reference PA-17 vit ici,
            // jamais a l'ecran ; « en démonstration » avait cessé d'être vrai
            // au passage au réel du 01/09).
            'en_attente_implementation' => 'Configuration complète, mais le client MECeF réel n’est pas '
                . 'encore implémenté : les factures mentionnent l’attente d’inscription auprès de la DGI.',
            'active' => 'Certification MECeF active.',
            // Facturation normalisée (07/11/2026) : l'état dérive du MODE choisi
            // et de ce qui est réellement en place, jamais de l'intention.
            'emecef_incomplet' => 'Mode e-MECeF choisi, mais la configuration est incomplète : les factures restent en attente de normalisation.',
            'emecef_actif' => 'Mode e-MECeF : le serveur certifie par l’API de la DGI.',
            'boitier_au_poste' => 'Mode boîtier CC300 : la normalisation se fait sur le poste de la réception ; le serveur ne certifie pas.',
        ],
    ],
];

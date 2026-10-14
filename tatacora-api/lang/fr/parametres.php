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
        ],
    ],
];

<?php

declare(strict_types=1);

/*
 * Pages d'erreur (`resources/views/errors/*.blade.php`, gabarit commun
 * `errors/layout.blade.php`).
 *
 * Aucun équivalent au maître : `prototype_v2/` ne maquette pas d'écran
 * d'erreur. Chaque code porte : un titre, un message humain, une liste « Que
 * faire ? » à l'usage du personnel du gîte (non technique) — et RIEN de
 * technique : aucun message d'exception, chemin ou requête n'est jamais
 * affiché. Les vues ne contiennent aucune chaîne en dur
 * (`ErreursPwaVuesTest`).
 *
 * Un code sans entrée ci-dessous retombe sur `generique_4xx` / `generique_5xx`
 * (vues `errors/4xx.blade.php` et `errors/5xx.blade.php`).
 */
return [

    'titre_page' => ':titre — LogiReStock — TATACORA AFRIQUE',
    'code_libelle' => 'Code d\'erreur :code',
    'que_faire' => 'Que faire ?',
    'incident_libelle' => 'Identifiant d\'incident à communiquer au support',
    'delai' => 'Vous pourrez réessayer dans :secondes seconde(s).',
    'rafraichissement' => 'Cette page se rafraîchit toute seule : vous n\'avez rien à faire.',
    'marque' => 'LogiReStock',

    'actions' => [
        'accueil_connecte' => 'Retour au tableau de bord',
        'accueil_invite' => 'Retour à l\'accueil',
        'reessayer' => 'Réessayer',
        'recharger' => 'Recharger la page',
        'connexion' => 'Se connecter',
        'reconnexion' => 'Retour à la connexion',
    ],

    '400' => [
        'titre' => 'Demande incomprise',
        'message' => 'Le serveur n\'a pas pu comprendre cette demande. Rien n\'a été enregistré.',
        'aide' => [
            'Revenez à la page précédente et recommencez la saisie.',
            'Si vous avez collé un lien, vérifiez qu\'il est complet.',
        ],
    ],
    '401' => [
        'titre' => 'Connexion nécessaire',
        'message' => 'Cette page est réservée aux personnes connectées. Identifiez-vous pour continuer.',
        'aide' => [
            'Cliquez sur « Se connecter » et saisissez votre identifiant.',
            'Si vous avez oublié votre mot de passe, demandez à l\'administrateur de le réinitialiser.',
        ],
    ],
    '402' => [
        'titre' => 'Accès suspendu',
        'message' => 'Cette fonction n\'est pas disponible pour le moment sur votre abonnement.',
        'aide' => [
            'Prévenez l\'administrateur du gîte : il saura la rétablir.',
            'Vos autres écrans restent utilisables normalement.',
        ],
    ],
    '403' => [
        'titre' => 'Accès non autorisé',
        'message' => 'Votre profil n\'a pas le droit d\'ouvrir cette page. Ce n\'est pas une panne.',
        'aide' => [
            'Retournez au tableau de bord : les modules qui vous sont ouverts s\'y trouvent.',
            'Si vous pensez devoir y accéder, demandez à l\'administrateur d\'ajuster vos droits.',
        ],
    ],
    '404' => [
        'titre' => 'Page introuvable',
        'message' => 'Cette adresse ne correspond à aucune page de TATACORA AFRIQUE : elle a peut-être '
            . 'été déplacée, ou son lien était incorrect.',
        'aide' => [
            'Utilisez le menu pour retrouver l\'écran cherché.',
            'Si un lien enregistré ne marche plus, supprimez-le et créez-en un nouveau depuis le menu.',
        ],
    ],
    '405' => [
        'titre' => 'Action non permise ici',
        'message' => 'Cette page ne peut pas être ouverte de cette façon. Rien n\'a été modifié.',
        'aide' => [
            'Revenez au tableau de bord et passez par le menu.',
            'Évitez de rouvrir un ancien formulaire déjà envoyé.',
        ],
    ],
    '408' => [
        'titre' => 'Délai dépassé',
        'message' => 'La demande a mis trop de temps à arriver au serveur, souvent à cause d\'une connexion faible.',
        'aide' => [
            'Vérifiez votre connexion Internet, puis réessayez.',
            'Votre saisie n\'a pas été enregistrée : refaites-la si besoin.',
        ],
    ],
    '409' => [
        'titre' => 'Conflit de modification',
        'message' => 'Cette fiche vient d\'être modifiée par quelqu\'un d\'autre ou depuis un autre écran.',
        'aide' => [
            'Rechargez la page pour voir la version la plus récente.',
            'Refaites ensuite votre modification si elle est toujours utile.',
        ],
    ],
    '410' => [
        'titre' => 'Page supprimée',
        'message' => 'Cette page n\'existe plus et ne reviendra pas.',
        'aide' => [
            'Utilisez le menu pour trouver l\'écran qui la remplace.',
            'Mettez à jour vos favoris si vous l\'aviez enregistrée.',
        ],
    ],
    '413' => [
        'titre' => 'Fichier trop volumineux',
        'message' => 'Le fichier envoyé dépasse la taille acceptée par le serveur. Il n\'a pas été reçu.',
        'aide' => [
            'Réduisez la taille du fichier (photo plus légère, PDF compressé) puis renvoyez-le.',
            'Si le fichier doit rester tel quel, prévenez l\'administrateur.',
        ],
    ],
    '419' => [
        'titre' => 'Votre session a expiré',
        'message' => 'Par sécurité, votre session s\'est fermée après un temps d\'inactivité. '
            . 'Rechargez la page pour continuer.',
        'aide' => [
            'Cliquez sur « Recharger la page » : vous retrouverez votre écran.',
            'Si la page ne s\'ouvre pas, revenez à la connexion et identifiez-vous de nouveau.',
            'La dernière saisie non validée peut être à refaire.',
        ],
    ],
    '422' => [
        'titre' => 'Informations non valides',
        'message' => 'Certaines informations envoyées sont incomplètes ou incorrectes. Rien n\'a été enregistré.',
        'aide' => [
            'Revenez en arrière et vérifiez chaque champ obligatoire.',
            'Corrigez puis validez de nouveau.',
        ],
    ],
    '429' => [
        'titre' => 'Trop de demandes',
        'message' => 'Vous avez envoyé beaucoup de demandes en peu de temps. Patientez un instant avant de continuer.',
        'aide' => [
            'Attendez quelques instants sans cliquer à nouveau.',
            'Puis cliquez sur « Réessayer ». Inutile d\'actualiser la page à répétition.',
        ],
    ],
    '500' => [
        'titre' => 'Une erreur est survenue',
        'message' => 'Un incident est survenu de notre côté. Vos données déjà enregistrées ne sont pas perdues.',
        'aide' => [
            'Patientez une minute, puis cliquez sur « Réessayer ».',
            'Si cela se reproduit, prévenez l\'administrateur en lui donnant l\'identifiant d\'incident ci-dessous.',
        ],
    ],
    '502' => [
        'titre' => 'Service momentanément injoignable',
        'message' => 'Un des services dont dépend l\'application ne répond pas pour le moment. '
            . 'Ce n\'est pas de votre fait.',
        'aide' => [
            'Patientez une à deux minutes, puis réessayez.',
            'Si l\'incident dure, prévenez l\'administrateur avec l\'identifiant ci-dessous.',
        ],
    ],
    '503' => [
        'titre' => 'Maintenance en cours',
        'message' => 'LogiReStock est en cours de mise à jour. Le service sera de retour dans quelques instants.',
        'aide' => [
            'Vos données déjà enregistrées sont conservées.',
            'Notez sur papier les ventes ou arrivées à enregistrer, et saisissez-les au retour du service.',
        ],
    ],
    '504' => [
        'titre' => 'Le serveur met trop de temps',
        'message' => 'Le serveur n\'a pas répondu à temps. L\'opération a pu aboutir ou non : vérifiez avant de recommencer.',
        'aide' => [
            'Ouvrez la liste concernée pour contrôler si votre saisie y figure déjà.',
            'Sinon, réessayez dans une minute ; en cas d\'échec répété, prévenez l\'administrateur.',
        ],
    ],

    'generique_4xx' => [
        'titre' => 'Demande impossible',
        'message' => 'Cette demande n\'a pas pu être traitée. Rien n\'a été modifié.',
        'aide' => [
            'Retournez à l\'écran précédent et recommencez.',
            'Si le problème persiste, prévenez l\'administrateur.',
        ],
    ],
    'generique_5xx' => [
        'titre' => 'Service indisponible',
        'message' => 'Un incident empêche le service de répondre pour le moment. Vos données ne sont pas perdues.',
        'aide' => [
            'Patientez une minute, puis réessayez.',
            'Si cela dure, prévenez l\'administrateur avec l\'identifiant ci-dessous.',
        ],
    ],
];

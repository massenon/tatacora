<?php

declare(strict_types=1);

/*
| Correspondance des comptes — écran « rôle -> compte comptable » (26/10/2026)
| et refus de sa validation.
|
| Aucune chaîne accentuée ne vit dans un `throw` ou un `abort()`
| (MessagesUtilisateurTest) : les refus passent par ces clés. Le poste Windows
| reprend ces phrases AU MOT (`messages_correspondance.dart`).
*/

return [
    // --- Refus de la validation (CorrespondanceComptesService::verifier).
    'compte_absent' => 'Le compte :numero n’existe pas au plan comptable. '
        . 'Choisissez un compte du plan : un numéro saisi de mémoire imputerait '
        . 'les pièces futures sur un compte que le plan ne connaît pas.',
    'compte_incoherent' => 'Le compte :numero ne convient pas au rôle « :role » : '
        . 'le numéro attendu :attendu.',
    'attendu_classe' => 'est de la classe :classe',
    'attendu_prefixe' => 'commence par :prefixe',
    'attendu_ou' => ' ou ',

    // --- Écran.
    'titre' => 'Correspondance des comptes',
    'titre_page' => 'Correspondance des comptes — TATACORA AFRIQUE',
    'sous_titre' => 'Le compte que chaque pièce automatique utilise pour chaque rôle',
    'avertissement' => 'Un changement vaut pour les pièces futures. Une pièce déjà '
        . 'passée n’est jamais réécrite : elle reste sur le compte où elle a été passée.',

    'colonne_role' => 'Rôle',
    'colonne_compte' => 'Compte actuel',
    'colonne_defaut' => 'Par défaut',
    'colonne_action' => 'Action',

    'groupe_produits' => 'Produits des ventes',
    'groupe_tva' => 'TVA',
    'groupe_tresorerie' => 'Trésoreries',
    'groupe_tiers' => 'Tiers',
    'groupe_resultat' => 'Résultat de l’exercice',

    'modifier' => 'Modifier',
    'etat_defaut' => 'Défaut',
    'etat_modifie' => 'Modifié',
    'libelle_inconnu' => 'Compte absent du plan',

    'modale_titre' => 'Modifier le compte du rôle',
    'champ_compte' => 'Numéro de compte',
    'champ_compte_requis' => 'Saisissez un numéro de compte, ou rétablissez le défaut.',
    'champ_compte_aide' => 'De deux à quatre chiffres, un compte du plan comptable.',
    'role_attendu' => 'Numéro attendu : :attendu.',
    'defaut_rappel' => 'Compte par défaut : :defaut.',
    'retablir' => 'Rétablir le défaut',
    'enregistrer' => 'Enregistrer',
    'annuler' => 'Annuler',
    'enregistre' => 'Correspondance enregistrée : les pièces futures utiliseront le compte :numero.',
    'retabli' => 'Défaut rétabli : les pièces futures utiliseront le compte :numero.',
    'aucun_changement' => 'Aucune valeur modifiée.',
    'lecture_seule' => 'Vous pouvez consulter cette correspondance, pas la modifier.',

    // --- Lien depuis le hub de la comptabilité.
    'lien_hub' => 'Correspondance des comptes',
];

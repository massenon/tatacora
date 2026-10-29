<?php

declare(strict_types=1);

/*
|---------------------------------------------------------------------------
| Authentification
|---------------------------------------------------------------------------
| `MessagesUtilisateurTest` echoue sur toute chaine accentuee ecrite en dur
| dans un `throw`, un `abort()` ou un `addError()` : tout message visible
| passe par ce fichier.
|
| Les DEUX canaux partagent ces cles — l'API JSON du client Flutter (guard
| `sanctum`) et la PWA de consultation (guard `web`). C'est deliberatement
| un seul jeu de messages : un meme refus doit se dire de la meme facon,
| sans quoi le meme utilisateur lit deux formulations differentes selon le
| poste et croit a deux causes distinctes.
|
| Ces quatre cles — `failed`, `compte_desactive`, `requise`, `module_refuse` —
| etaient appelees par la PWA, le middleware RBAC et le moteur d'etats alors
| qu'aucun fichier `auth.php` n'existait : elles s'affichaient telles quelles
| a l'utilisateur. Corrige le 18/08/2026 avec l'ouverture de l'API.
*/

return [
    // Noms de champs, utilises par les messages de validation.
    'identifiant' => 'identifiant',
    'mot_de_passe' => 'mot de passe',

    // Message UNIQUE pour un login inconnu comme pour un mot de passe faux :
    // les distinguer indiquerait a un attaquant quels comptes existent.
    'failed' => 'Identifiant ou mot de passe incorrect.',

    // Refus prononce APRES validation du mot de passe : le prononcer avant
    // revelerait l'existence du compte a qui ignore le mot de passe.
    'compte_desactive' => 'Ce compte est desactive. Contactez un administrateur.',

    // Mot de passe temporaire posé par un administrateur (29/10/2026) : l'API
    // n'émet aucun jeton tant que le titulaire n'a pas défini le sien, sur
    // l'application web.
    'changement_requis' => 'Votre mot de passe a ete reinitialise : definissez-en un nouveau sur l\'application web avant de vous connecter ici.',

    'trop_de_tentatives' => 'Trop de tentatives de connexion. Reessayez dans :secondes secondes.',

    'deconnecte' => 'Vous etes deconnecte.',

    // Absence de jeton ou de session valide (401).
    'requise' => 'Authentification requise.',

    // Jeton valide mais droit absent sur le module demande (403) — RG-16.
    'module_refuse' => 'Vous n avez pas acces a ce module.',
];

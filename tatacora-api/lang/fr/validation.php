<?php

declare(strict_types=1);

/*
 * Messages de validation en francais.
 *
 * 06_DEVELOPMENT_STANDARDS.md §4.1 : tout contenu visible par l'utilisateur
 * final est en francais. Sans ce fichier, Laravel renvoyait la CLE brute
 * (« validation.required ») a l'utilisateur : ni francais, ni anglais.
 */

return [

    'accepted' => "Le champ :attribute doit être accepté.",
    'accepted_if' => "Le champ :attribute doit être accepté quand :other vaut :value.",
    'active_url' => "Le champ :attribute n'est pas une URL valide.",
    'after' => "Le champ :attribute doit être une date postérieure au :date.",
    'after_or_equal' => "Le champ :attribute doit être une date postérieure ou égale au :date.",
    'alpha' => "Le champ :attribute ne peut contenir que des lettres.",
    'alpha_dash' => "Le champ :attribute ne peut contenir que des lettres, chiffres, tirets et underscores.",
    'alpha_num' => "Le champ :attribute ne peut contenir que des lettres et des chiffres.",
    'array' => "Le champ :attribute doit être un tableau.",
    'ascii' => "Le champ :attribute ne peut contenir que des caractères alphanumériques et des symboles sur un octet.",
    'before' => "Le champ :attribute doit être une date antérieure au :date.",
    'before_or_equal' => "Le champ :attribute doit être une date antérieure ou égale au :date.",
    'boolean' => "Le champ :attribute doit être vrai ou faux.",
    'confirmed' => "Le champ de confirmation :attribute ne correspond pas.",
    'current_password' => "Le mot de passe est incorrect.",
    'date' => "Le champ :attribute n'est pas une date valide.",
    'date_equals' => "Le champ :attribute doit être une date égale à :date.",
    'date_format' => "Le champ :attribute ne correspond pas au format :format.",
    'decimal' => "Le champ :attribute doit avoir :decimal décimales.",
    'declined' => "Le champ :attribute doit être refusé.",
    'different' => "Les champs :attribute et :other doivent être différents.",
    'digits' => "Le champ :attribute doit contenir :digits chiffres.",
    'digits_between' => "Le champ :attribute doit contenir entre :min et :max chiffres.",
    'dimensions' => "La taille de l'image :attribute n'est pas conforme.",
    'distinct' => "Le champ :attribute contient une valeur en double.",
    'doesnt_end_with' => "Le champ :attribute ne doit pas se terminer par un des éléments suivants : :values.",
    'doesnt_start_with' => "Le champ :attribute ne doit pas commencer par un des éléments suivants : :values.",
    'email' => "Le champ :attribute doit être une adresse email valide.",
    'ends_with' => "Le champ :attribute doit se terminer par une des valeurs suivantes : :values.",
    'enum' => "La valeur du champ :attribute est invalide.",
    'exists' => "La valeur sélectionnée pour :attribute est invalide.",
    'filled' => "Le champ :attribute doit avoir une valeur.",
    'image' => "Le champ :attribute doit être une image.",
    'in' => "La valeur sélectionnée pour :attribute est invalide.",
    'integer' => "Le champ :attribute doit être un entier.",
    'ip' => "Le champ :attribute doit être une adresse IP valide.",
    'json' => "Le champ :attribute doit être un document JSON valide.",
    'lowercase' => "Le champ :attribute doit être en minuscules.",
    'lte' => [
        'array' => "Le champ :attribute doit contenir au plus :value élément(s).",
        'file' => "Le champ :attribute doit peser au plus :value kilo-octets.",
        'numeric' => "Le champ :attribute doit être inférieur ou égal à :value.",
        'string' => "Le champ :attribute doit compter au plus :value caractères.",
    ],
    'mac_address' => "Le champ :attribute doit être une adresse MAC valide.",
    'not_in' => "La valeur sélectionnée pour :attribute est invalide.",
    'not_regex' => "Le format du champ :attribute est invalide.",
    'numeric' => "Le champ :attribute doit être un nombre.",
    'present' => "Le champ :attribute doit être présent.",
    'prohibited' => "Le champ :attribute est interdit.",
    'regex' => "Le format du champ :attribute est invalide.",
    'required' => "Le champ :attribute est obligatoire.",
    'required_if' => "Le champ :attribute est obligatoire quand :other vaut :value.",
    'required_with' => "Le champ :attribute est obligatoire quand :values est présent.",
    'required_without' => "Le champ :attribute est obligatoire quand :values n'est pas présent.",
    'same' => "Les champs :attribute et :other doivent être identiques.",
    'starts_with' => "Le champ :attribute doit commencer par une des valeurs suivantes : :values.",
    'string' => "Le champ :attribute doit être une chaîne de caractères.",
    'timezone' => "Le champ :attribute doit être un fuseau horaire valide.",
    'unique' => "La valeur du champ :attribute est déjà utilisée.",
    'uploaded' => "Le fichier :attribute n'a pas pu être téléversé.",
    'uppercase' => "Le champ :attribute doit être en majuscules.",
    'url' => "Le champ :attribute doit être une URL valide.",
    'uuid' => "Le champ :attribute doit être un UUID valide.",

    'min' => [
        'array' => 'Le champ :attribute doit contenir au moins :min elements.',
        'file' => 'Le fichier :attribute doit peser au moins :min kilo-octets.',
        'numeric' => 'Le champ :attribute doit etre au minimum de :min.',
        'string' => 'Le champ :attribute doit contenir au moins :min caracteres.',
    ],

    'max' => [
        'array' => 'Le champ :attribute ne peut pas contenir plus de :max elements.',
        'file' => 'Le fichier :attribute ne peut pas peser plus de :max kilo-octets.',
        'numeric' => 'Le champ :attribute ne peut pas etre superieur a :max.',
        'string' => 'Le champ :attribute ne peut pas contenir plus de :max caracteres.',
    ],

    'between' => [
        'array' => 'Le champ :attribute doit contenir entre :min et :max elements.',
        'file' => 'Le fichier :attribute doit peser entre :min et :max kilo-octets.',
        'numeric' => 'Le champ :attribute doit etre compris entre :min et :max.',
        'string' => 'Le champ :attribute doit contenir entre :min et :max caracteres.',
    ],

    'size' => [
        'array' => 'Le champ :attribute doit contenir :size elements.',
        'file' => 'Le fichier :attribute doit peser :size kilo-octets.',
        'numeric' => 'Le champ :attribute doit valoir :size.',
        'string' => 'Le champ :attribute doit contenir :size caracteres.',
    ],

    'custom' => [],

    /*
     * Noms de champs. Sans cette table, un message générique affichait
     * « Le champ date_depart... » : le nom technique de la colonne, tel quel.
     */
    'attributes' => [
        'article_id' => 'article',
        'boisson_id' => 'boisson',
        'categorie' => 'catégorie',
        'client_id' => 'client',
        'cout_unitaire' => 'coût unitaire',
        'date_arrivee' => "date d'arrivée",
        'date_depart' => 'date de départ',
        'date_debut' => 'date de début',
        'date_fin' => 'date de fin',
        'debut' => 'date de début',
        'email' => 'adresse email',
        'etat' => 'état',
        'fin' => 'date de fin',
        'libelle' => 'libellé',
        'login' => 'identifiant',
        'mot_de_passe' => 'mot de passe',
        'motif' => 'motif',
        'nom' => 'nom',
        'operations' => 'opérations',
        'par_page' => 'nombre par page',
        'piece_identite' => "pièce d'identité",
        'plat_id' => 'plat',
        'point_id' => 'point de stockage',
        'poste_id' => 'poste',
        'prenom' => 'prénom',
        'prix_vente' => 'prix de vente',
        'quantite' => 'quantité',
        'recherche' => 'recherche',
        'seuil_alerte' => "seuil d'alerte",
        'seuil_reappro' => 'seuil de réapprovisionnement',
        'sous_seuil' => 'sous seuil',
        'telephone' => 'téléphone',
        'type_client' => 'type de client',
        'type_mouvement' => 'type de mouvement',
        'unite_id' => "unité d'hébergement",
        'unite_mesure' => 'unité de mesure',
        'validation_rupture' => 'validation de rupture',
    ],

];

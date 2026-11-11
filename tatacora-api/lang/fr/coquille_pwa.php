<?php

declare(strict_types=1);

/*
|--------------------------------------------------------------------------
| Coquille de la PWA — les textes qui ne peuvent pas vivre dans `pwa.php`
|--------------------------------------------------------------------------
|
| Ce fichier ne double PAS `lang/fr/pwa.php`. Il ne porte que les chaînes qui
| s'écartent délibérément d'une clé existante, avec la raison de l'écart : une
| clé corrigée en silence effacerait la décision qui l'a produite.
|
*/

return [
    /*
     * ÉCART DÉLIBÉRÉ ET MESURÉ — `prototype_v2/pages/splash.html` l.5
     *
     * Le maître : « TATACORA AFRIQUE — Démarrage ».
     * Ici       : « Démarrage — TATACORA AFRIQUE ».
     *
     * Raison : le maître lui-même écrit l'autre sens sur ses QUARANTE-NEUF
     * autres pages — « Connexion — TATACORA AFRIQUE », « Tableau de bord —
     * TATACORA AFRIQUE », « Clients & Créances — TATACORA AFRIQUE ». Le
     * splash est la seule exception, et c'est une inadvertance de maquette,
     * pas une intention : la règle G3 de `DIRECTIVE_CONFORMITE_100.md` veut
     * que l'onglet du navigateur nomme L'ÉCRAN d'abord, faute de quoi quinze
     * onglets ouverts affichent tous le même mot. Recopier l'exception ferait
     * du démarrage le seul écran que l'utilisateur ne peut pas retrouver dans
     * sa barre d'onglets.
     *
     * ⚠ La clé `pwa.demarrage.titre_page` de `lang/fr/pwa.php` porte encore
     * l'ancienne chaîne et N'A PLUS AUCUN APPELANT depuis le 31/08/2026 : elle
     * est à retirer par qui a la main sur ce fichier. Une clé que plus
     * personne ne lit est du code mort qui a l'air d'une spécification — le
     * fichier `pwa.php` le dit lui-même en tête.
     */
    'demarrage_titre_page' => 'Démarrage — LogiReStock — TATACORA AFRIQUE',
];

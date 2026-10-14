<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Pwa\Livewire\PageMetier;

/**
 * Socle des pages TRANSVERSES de la PWA — celles du maitre qui ne relevent
 * d'aucun module metier : aide, contact, journal d'audit, profil, roles,
 * parametres, import-export.
 *
 * ## AUCUNE METHODE PUBLIQUE ICI, ET C'EST STRUCTUREL
 *
 * Meme raison qu'en `PageComptabilite`, et elle vaut d'etre repetee plutot que
 * referencee : Livewire expose comme ACTION toute methode publique d'un
 * composant, y compris celles qu'il HERITE. Une methode publique posee sur
 * cette classe deviendrait une action sur toutes ses descendantes a la fois,
 * par le chemin meme que `ForcerLectureSeule` ne couvre pas (PA-67) — la route
 * dediee de Livewire, hors du groupe `/pwa`.
 *
 * `PwaActionsReluesTest` releve les methodes publiques HERITEES autant que
 * declarees (PA-152). Tous les auxiliaires de ce fichier sont donc `protected`,
 * et les filtres des ecrans sont des PROPRIETES Livewire, jamais des methodes.
 *
 * @see LARAVEL_PWA.md §1 (lecture seule stricte), §3 (appeler le Service de domaine)
 * @see DIRECTIVE_CONFORMITE_100.md Article 6, Article 8
 */
abstract class PageTransverse extends PageMetier
{
    /**
     * Rien de plus que le socle commun.
     *
     * `socle()` et la deconnexion vivaient ici ; ils ont ete leves dans
     * `PageMetier` le 27/08/2026, quand neuf pages metier en auraient fait une
     * TROISIEME copie (Article 10 — « deux listes decrivant la meme chose
     * divergeront ; ce n'est qu'une question de temps »).
     *
     * Cette classe subsiste parce qu'elle NOMME une famille : les sept pages
     * du maitre qui ne relevent d'aucun module metier. La supprimer ferait
     * perdre cette distinction, qui commande le `data-module` de chaque route
     * — et les trois pages qui n'en portent aucun.
     */
}

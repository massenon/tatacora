<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

/**
 * Une note annexe — numerotee « 1. » a « 7. » dans son titre chez le maitre
 * (`m10-notes-annexes.html` l.64-99).
 *
 * `postes` porte les lignes chiffrees (libelle + montant). Il est VIDE quand
 * `etat` vaut `indisponible` ou `non_saisie` : y mettre des zeros ferait lire
 * « aucune immobilisation » la ou il faut lire « on ne sait pas ».
 *
 * `texte` porte le contenu narratif des notes qui n'en ont pas d'autre — la
 * note 1 (regles et methodes) est un texte fixe versionne, la note 7 une saisie
 * libre du Comptable.
 *
 * `motif` est un CODE FERME, jamais une phrase : la traduction appartient au
 * client, comme pour `GrandLivre::MOTIF_REPORT_ABSENT`.
 */
final readonly class Note
{
    /**
     * @param  list<array{libelle: string, montant: string, prefixes?: list<string>, ouverture?: string, variation?: string}>  $postes
     */
    public function __construct(
        public int $numero,
        public string $titre,
        public string $etat,
        public array $postes = [],
        public ?string $texte = null,
        public ?string $motif = null,
    ) {
    }
}

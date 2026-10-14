<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

/**
 * Les Notes Annexes d'un exercice — `m10-notes-annexes.html`,
 * `MODULE_COMPTABILITE_COMPLET_PART4.md` §1.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 *
 * « Sans les Notes Annexes, les etats financiers sont INCOMPLETS au sens
 * SYSCOHADA, pas de simples tableaux isoles » (§1). C'est pourquoi les sept
 * notes descendent TOUTES, y compris celles qu'on ne sait pas remplir : une
 * note absente se lirait comme une note sans objet.
 *
 * ## Chaque note porte son etat, et « indisponible » n'est pas « vide »
 *
 * - `disponible` : la note est calculee.
 * - `indisponible` : la donnee vit dans un domaine que M10 ne peut pas lire
 *   depuis ici (`motif` le nomme). Elle n'est PAS a zero.
 * - `non_saisie` : la note attend une saisie humaine qui n'a pas eu lieu.
 *
 * Un « 0 F » sur le tableau des amortissements et un « non calculable » ne
 * disent pas la meme chose au comptable qui signe les etats (Article 7).
 */
final readonly class NotesAnnexes
{
    public const ETAT_DISPONIBLE = 'disponible';

    public const ETAT_INDISPONIBLE = 'indisponible';

    public const ETAT_NON_SAISIE = 'non_saisie';

    /**
     * @param  list<Note>  $notes
     * @param  array{statut: string}  $filtresAppliques
     */
    public function __construct(
        public string $exerciceId,
        public array $notes,
        public RepartitionStatuts $statuts,
        public array $filtresAppliques,
    ) {
    }
}

<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

use App\Domain\Comptabilite\Models\EcritureComptable;
use Illuminate\Support\Collection;

/**
 * Le Journal General d'un exercice — `m10-journal.html`.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 * @see RG-11 Les ecritures restituees ici ne sont jamais modifiables
 *
 * ## Ce que `equilibre` affirme, et ce qu'il n'affirme PAS
 *
 * Il affirme que, sur l'ensemble affiche, la somme des debits egale la somme
 * des credits — c'est mot pour mot le bandeau du maitre (l.103 : « Journal
 * equilibre — Total Debit = Total Credit »).
 *
 * Il **n'affirme rien sur l'equilibre de chaque piece**. `ecritures_comptables`
 * ne porte aucun identifiant de piece (PA-52) : rien ne dit quelles lignes
 * forment un meme ensemble, donc l'equilibre par piece n'est pas verifiable a
 * posteriori. `EcritureComptableService::enregistrerPiece()` le garantit **a
 * l'ecriture**, ce qui est une garantie de flux et non une garantie d'etat :
 * elle tombe au premier import ou a la premiere reprise de donnees. Deux pieces
 * fausses en sens contraire produiraient ici un `equilibre` a `true`.
 */
final readonly class JournalGeneral
{
    /**
     * @param  Collection<int, EcritureComptable>  $lignes
     * @param  array{journal_id: string|null, statut: string}  $filtresAppliques
     */
    public function __construct(
        public string $exerciceId,
        public Collection $lignes,
        public string $totalDebit,
        public string $totalCredit,
        public bool $equilibre,
        public RepartitionStatuts $statuts,
        public array $filtresAppliques,
    ) {
    }
}

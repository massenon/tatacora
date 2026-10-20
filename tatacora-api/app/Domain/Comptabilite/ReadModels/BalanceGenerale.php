<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

/**
 * La Balance Generale d'un exercice — `m10-balance.html`.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 *
 * ## `equilibree` porte sur DEUX egalites, pas une
 *
 * `MODULE_COMPTABILITE_COMPLET.md` §4 : total debit = total credit **et** total
 * solde debiteur = total solde crediteur. Les deux, en `bccomp` — jamais une
 * egalite flottante, `03_DATABASE_ENGINEERING.md` §11 imposant `DECIMAL(15,2)`
 * partout et `==` sur des `float` PHP etant le piege d'arrondi classique.
 *
 * Ne verifier que la premiere laisserait passer une erreur de repartition des
 * soldes ; ne verifier que la seconde laisserait passer une erreur de cumul.
 *
 * ## Ce que `equilibree` ne dit PAS
 *
 * Rien sur l'equilibre de chaque piece : `ecritures_comptables` n'a aucun
 * identifiant de piece (PA-52), donc aucune pièce n'est reconstituable a
 * posteriori. Une balance equilibree globalement peut contenir deux pieces
 * fausses qui se compensent.
 *
 * `MODULE_COMPTABILITE_COMPLET.md` §4 en fait la condition sine qua non de la
 * cloture. Cette API ne cloture rien : elle rend le constat, elle ne le fait
 * pas appliquer — le verrou de cloture vit en Partie 4, non implementee.
 */
final readonly class BalanceGenerale
{
    /**
     * @param  list<LigneBalance>  $lignes
     * @param  array{statut: string}  $filtresAppliques
     */
    public function __construct(
        public string $exerciceId,
        public array $lignes,
        public string $totalDebit,
        public string $totalCredit,
        public string $totalSoldeDebiteur,
        public string $totalSoldeCrediteur,
        public bool $equilibree,
        public RepartitionStatuts $statuts,
        public array $filtresAppliques,
        // Lot 2 (20/10/2026) : l'année dont les À-NOUVEAUX PROVISOIRES sont
        // compris dans cette balance (exercice précédent sans clôture
        // active), ou `null`. Calculés, jamais écrits.
        public ?int $aNouveauxProvisoiresDe = null,
    ) {
    }
}

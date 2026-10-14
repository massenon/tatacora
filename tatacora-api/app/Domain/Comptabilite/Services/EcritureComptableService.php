<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Exceptions\EcritureImmuableException;
use App\Domain\Comptabilite\Models\EcritureComptable;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Enregistrement, validation et contre-passation des écritures — RG-11, RG-12.
 *
 * @see RG-11 Immutabilité et contre-passation
 * @see RG-12 Centre de coût obligatoire
 *
 * ## L'immutabilité n'est PAS ici
 *
 * Elle est dans `EcritureComptableObserver`, qui couvre tous les chemins
 * d'écriture. Ce service fournit les opérations **légitimes** : écrire une
 * pièce équilibrée, la valider, la corriger par contre-passation.
 *
 * ## Il n'existe aucun identifiant de pièce au schéma — PA-52
 *
 * `ecritures_comptables` porte un `journal_id` mais **aucune colonne groupant
 * les lignes d'une même écriture** (pièce, lot, folio). Conséquence directe :
 * l'équilibre débit = crédit **ne peut pas être vérifié a posteriori** sur une
 * pièce, puisque rien ne dit quelles lignes en font partie.
 *
 * Le contournement retenu — le seul possible sans migration — est de garantir
 * l'équilibre **à l'écriture** : `enregistrerPiece()` refuse un ensemble de
 * lignes déséquilibré et les écrit dans une seule transaction. Une pièce
 * écrite par ce service est donc équilibrée par construction. Une pièce écrite
 * autrement échappe à cette garantie, ce qui est exactement la raison pour
 * laquelle PA-52 demande un identifiant de pièce.
 */
class EcritureComptableService
{
    private const PRECISION = 2;

    /**
     * Écrit une pièce comptable équilibrée — plusieurs lignes, une transaction.
     *
     * @param  list<array{compte_id: string, centre_id: string, debit?: string, credit?: string, libelle?: string}>  $lignes
     * @param  array{exercice_id: string, journal_id: string, date_ecriture: string, libelle: string, numero_piece?: string|null}  $entete
     * @return Collection<int, EcritureComptable>
     *
     * @throws RuntimeException si la pièce est déséquilibrée ou vide
     */
    public function enregistrerPiece(array $entete, array $lignes): Collection
    {
        if ($lignes === []) {
            throw new RuntimeException(__('comptabilite.piece_vide'));
        }

        $this->verifierEquilibre($lignes);

        return DB::transaction(function () use ($entete, $lignes): Collection {
            $ecrites = new Collection();

            foreach ($lignes as $ligne) {
                $ecrites->push(EcritureComptable::create([
                    'exercice_id' => $entete['exercice_id'],
                    'journal_id' => $entete['journal_id'],
                    'date_ecriture' => $entete['date_ecriture'],
                    'libelle' => $ligne['libelle'] ?? $entete['libelle'],
                    'compte_id' => $ligne['compte_id'],
                    // RG-12 — NOT NULL au schéma : une écriture sans centre de
                    // coût est impossible, pas seulement déconseillée.
                    'centre_id' => $ligne['centre_id'],
                    'debit' => $ligne['debit'] ?? '0.00',
                    'credit' => $ligne['credit'] ?? '0.00',
                    // Toute pièce naît en brouillon : la validation est un
                    // acte distinct, qui rend l'écriture immuable (RG-11).
                    'statut' => 'brouillon',
                    // PA-52, partiellement refermée (Vague E, 01/09/2026) —
                    // voir la migration `ajouter_numero_piece_aux_ecritures`.
                    // Absente de l'entête (appelants antérieurs à ce lot), la
                    // clé rend `null` : une pièce sans numéro allocué reste
                    // sans numéro, jamais un numéro inventé après coup.
                    'numero_piece' => $entete['numero_piece'] ?? null,
                ]));
            }

            return $ecrites;
        });
    }

    /**
     * Validation d'une pièce — le point de non-retour de RG-11.
     *
     * @param  Collection<int, EcritureComptable>  $piece
     * @return Collection<int, EcritureComptable>
     */
    public function valider(Collection $piece): Collection
    {
        return DB::transaction(function () use ($piece): Collection {
            foreach ($piece as $ecriture) {
                if ($ecriture->statut === 'validee') {
                    throw new RuntimeException(__('comptabilite.ecriture_deja_validee'));
                }

                $ecriture->update(['statut' => 'validee']);
            }

            return $piece->map(fn (EcritureComptable $e): EcritureComptable => $e->refresh());
        });
    }

    /**
     * Contre-passation — **la seule correction admise** par RG-11.
     *
     * L'écriture d'origine n'est jamais touchée : une écriture inverse est
     * ajoutée, et le lien `ecriture_contrepassee_id` conserve la traçabilité
     * exigée par SYSCOHADA. Le grand livre montre alors les deux mouvements,
     * ce qui est le comportement attendu d'un audit — une correction qui
     * effacerait la trace serait indétectable.
     *
     * @throws EcritureImmuableException si l'écriture n'est pas validée, ou déjà contre-passée
     */
    public function contrepasser(EcritureComptable $ecriture, ?string $motif = null): EcritureComptable
    {
        if ($ecriture->statut !== 'validee') {
            // Une écriture en brouillon se corrige directement : la
            // contre-passer produirait deux lignes inutiles au grand livre.
            throw new EcritureImmuableException(
                $ecriture->id,
                [],
                __('comptabilite.contrepassation_sur_brouillon'),
            );
        }

        if ($this->dejaContrepassee($ecriture)) {
            // Une double contre-passation rétablirait l'écriture d'origine
            // tout en laissant croire à une annulation.
            throw new EcritureImmuableException(
                $ecriture->id,
                [],
                __('comptabilite.deja_contrepassee'),
            );
        }

        return DB::transaction(fn (): EcritureComptable => EcritureComptable::create([
            'exercice_id' => $ecriture->exercice_id,
            'journal_id' => $ecriture->journal_id,
            'compte_id' => $ecriture->compte_id,
            'centre_id' => $ecriture->centre_id,
            'date_ecriture' => now()->toDateString(),
            'libelle' => $motif ?? __('comptabilite.libelle_contrepassation', [
                'libelle' => $ecriture->libelle,
            ]),
            // Débit et crédit inversés : c'est toute la contre-passation.
            'debit' => $ecriture->credit,
            'credit' => $ecriture->debit,
            'ecriture_contrepassee_id' => $ecriture->id,
            // Validée d'emblée : une contre-passation en brouillon laisserait
            // le grand livre faux jusqu'à sa validation.
            'statut' => 'validee',
        ])->refresh());
    }

    public function dejaContrepassee(EcritureComptable $ecriture): bool
    {
        return EcritureComptable::where('ecriture_contrepassee_id', $ecriture->id)->exists();
    }

    /**
     * Solde d'un compte sur une période — écritures **validées** seulement.
     *
     * Un brouillon n'est pas opposable : l'inclure ferait varier un solde
     * comptable au gré de saisies non confirmées.
     */
    public function soldeCompte(string $compteId, string $debut, string $fin): string
    {
        $solde = EcritureComptable::query()
            ->where('compte_id', $compteId)
            ->where('statut', 'validee')
            ->whereBetween('date_ecriture', [$debut, $fin])
            ->selectRaw('COALESCE(SUM(debit) - SUM(credit), 0) AS solde')
            ->value('solde');

        return bcadd((string) ($solde ?? '0'), '0', self::PRECISION);
    }

    /**
     * Débit total = crédit total, en `bccomp` — jamais une égalité flottante.
     *
     * @param  list<array{debit?: string, credit?: string}>  $lignes
     */
    private function verifierEquilibre(array $lignes): void
    {
        $debit = '0.00';
        $credit = '0.00';

        foreach ($lignes as $ligne) {
            $debit = bcadd($debit, $ligne['debit'] ?? '0.00', self::PRECISION);
            $credit = bcadd($credit, $ligne['credit'] ?? '0.00', self::PRECISION);
        }

        if (bccomp($debit, $credit, self::PRECISION) !== 0) {
            throw new RuntimeException(__('comptabilite.piece_desequilibree', [
                'debit' => $debit,
                'credit' => $credit,
                'ecart' => bcsub($debit, $credit, self::PRECISION),
            ]));
        }

        if (bccomp($debit, '0.00', self::PRECISION) === 0) {
            // Une pièce à zéro est équilibrée mais ne veut rien dire : elle
            // encombrerait le grand livre sans rien enregistrer.
            throw new RuntimeException(__('comptabilite.piece_sans_montant'));
        }
    }
}

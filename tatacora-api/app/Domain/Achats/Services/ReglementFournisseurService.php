<?php

declare(strict_types=1);

namespace App\Domain\Achats\Services;

use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\ReglementFournisseur;
use App\Domain\Comptabilite\Services\CorrespondanceComptesService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Domain\Depenses\Services\DepenseService;
use Carbon\CarbonInterface;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Règlement d'une dette fournisseur (M7) — PA-165, unique writer de
 * `reglements_fournisseur` et de `commandes_achat.montant_regle`.
 *
 * ## La règle comptable du Product Owner, côté décaissement
 *
 * Un règlement fournisseur est un mouvement d'argent : sa pièce part dans la
 * MÊME transaction — DÉBIT `4011` Fournisseurs (la dette diminue), CRÉDIT
 * la trésorerie qui décaisse ({@see DepenseService::TRESORERIES}, seuls
 * comptes qui font foi), au journal de la trésorerie. Un refus n'écrit rien.
 *
 * ## `montant_regle` : recalculé, jamais incrémenté
 *
 * La colonne existe au schéma depuis l'origine (arbitrage PA-161 (d),
 * « différé à PA-21 ») : elle est posée à la SOMME des règlements après
 * chaque écriture — le motif `recalculerTotaux()` de la facturation. Un
 * cumul incrémenté aurait divergé de ses lignes au premier incident.
 *
 * ## Le sur-règlement REFUSE
 *
 * Payer plus que le reste dû créerait un avoir fournisseur qu'aucune table
 * ne modélise — même raisonnement que le sur-encaissement client
 * (`EncaissementFactureService`).
 *
 * @see EF-M7-04 Dettes fournisseurs
 * @see docs/PLAN_ACTION_SEQUENCE_POST_AUDIT.md PA-161 (d), PA-162, PA-165
 */
class ReglementFournisseurService
{
    private const PRECISION = 2;

    public function __construct(
        private readonly PasserEcritureService $ecritures,
        private readonly CorrespondanceComptesService $comptes,
    ) {
    }

    /**
     * @throws RuntimeException refus local : trésorerie inconnue, montant
     *                          invalide ou supérieur au reste dû
     */
    public function regler(
        CommandeAchat $commande,
        string $montant,
        string $tresorerieCode,
        ?string $id = null,
        ?CarbonInterface $quand = null,
    ): ReglementFournisseur {
        // Audit de couverture (18/10/2026), pour la seule synchronisation :
        // l'UUID du poste (un rejeu rend le règlement déjà écrit) et la date
        // du geste (D246). Aucun appelant en ligne ne les passe.
        if ($id !== null && ($existant = ReglementFournisseur::find($id)) !== null) {
            return $existant;
        }

        if (! array_key_exists($tresorerieCode, DepenseService::TRESORERIES)) {
            throw new RuntimeException(__('achats.reglement_tresorerie_inconnue', ['code' => $tresorerieCode]));
        }

        if (! is_numeric($montant) || bccomp($montant, '0', self::PRECISION) <= 0) {
            throw new RuntimeException(__('achats.reglement_montant_invalide'));
        }

        $resteDu = $this->resteDu($commande);

        if (bccomp($montant, $resteDu, self::PRECISION) > 0) {
            throw new RuntimeException(__('achats.reglement_superieur_au_reste', ['reste' => $resteDu]));
        }

        $tresorerie = DepenseService::TRESORERIES[$tresorerieCode];

        $jour = ($quand ?? now())->toDateString();

        return DB::transaction(function () use ($commande, $montant, $tresorerieCode, $tresorerie, $id, $jour): ReglementFournisseur {
            $reglement = ReglementFournisseur::create([
                ...($id !== null ? ['id' => $id] : []),
                'commande_id' => $commande->id,
                'montant' => bcadd($montant, '0', self::PRECISION),
                'tresorerie' => $tresorerieCode,
                'date_reglement' => $jour,
            ]);

            // RECALCULÉ depuis les lignes — jamais `montant_regle + montant`,
            // qui divergerait de ses règlements au premier incident.
            $commande->update([
                'montant_regle' => $this->totalRegle($commande),
            ]);

            $libelle = sprintf(
                'Règlement fournisseur %s — %s',
                (string) $commande->fournisseur->raison_sociale,
                $reglement->id,
            );

            $this->ecritures->passerEtValider([
                'journal' => $tresorerie['journal'],
                'date' => $jour,
                'libelle' => $libelle,
                'lignes' => [
                    ['compte' => $this->comptes->compte('FOURNISSEURS'), 'role' => 'FOURNISSEURS', 'debit' => $montant, 'credit' => '0'],
                    ['compte' => $this->comptes->compteDeTresorerie($tresorerieCode), 'role' => CorrespondanceComptesService::roleDeTresorerie($tresorerieCode), 'debit' => '0', 'credit' => $montant],
                ],
            ]);

            return $reglement->refresh();
        });
    }

    public function totalRegle(CommandeAchat $commande): string
    {
        // Un règlement ANNULÉ (PA-168) ne compte plus : sa pièce est
        // contre-passée, et `montant_regle` — recalculé d'ici — le suit.
        return bcadd(
            (string) (ReglementFournisseur::query()
                ->where('commande_id', $commande->id)
                ->where('statut', 'actif')
                ->sum('montant') ?: '0'),
            '0',
            self::PRECISION,
        );
    }

    public function resteDu(CommandeAchat $commande): string
    {
        $reste = bcsub((string) $commande->montant_total, $this->totalRegle($commande), self::PRECISION);

        return bccomp($reste, '0.00', self::PRECISION) < 0 ? '0.00' : $reste;
    }

    /**
     * Annulation d'un règlement erroné — PA-168, symétrique de
     * `EncaissementFactureService::annuler()` : état tracé jamais supprimé
     * (RG-15), contre-passation de la pièce ENTIÈRE retrouvée par libellé
     * unique et VÉRIFIÉE équilibrée (PA-52), `montant_regle` recalculé — le
     * tout dans la même transaction.
     *
     * @throws RuntimeException déjà annulé, motif vide ou pièce introuvable
     */
    public function annuler(ReglementFournisseur $reglement, string $motif): ReglementFournisseur
    {
        if ($reglement->statut === 'annule') {
            throw new RuntimeException(__('achats.reglement_deja_annule'));
        }

        if (trim($motif) === '') {
            throw new RuntimeException(__('achats.reglement_motif_requis'));
        }

        $commande = $reglement->commande;

        $libelle = sprintf(
            'Règlement fournisseur %s — %s',
            (string) $commande->fournisseur->raison_sociale,
            $reglement->id,
        );

        $piece = \App\Domain\Comptabilite\Models\EcritureComptable::query()
            ->where('libelle', $libelle)
            ->get();

        $debit = '0.00';
        $credit = '0.00';

        foreach ($piece as $ligne) {
            $debit = bcadd($debit, (string) $ligne->debit, self::PRECISION);
            $credit = bcadd($credit, (string) $ligne->credit, self::PRECISION);
        }

        if ($piece->count() < 2
            || bccomp($debit, $credit, self::PRECISION) !== 0
            || bccomp($debit, (string) $reglement->montant, self::PRECISION) !== 0) {
            throw new RuntimeException(__('achats.reglement_piece_introuvable', ['libelle' => $libelle]));
        }

        return DB::transaction(function () use ($reglement, $commande, $motif, $piece): ReglementFournisseur {
            $this->ecritures->contrepasserPiece($piece, $motif);

            $reglement->update([
                'statut' => 'annule',
                'motif_annulation' => $motif,
                'annule_par_id' => auth()->id(),
                'date_annulation' => now(),
            ]);

            $commande->update([
                'montant_regle' => $this->totalRegle($commande),
            ]);

            return $reglement->refresh();
        });
    }
}

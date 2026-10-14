<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Services;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Domain\Comptabilite\Support\ComptesSyscohada;
use App\Domain\Depenses\Services\DepenseService;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\Paiement;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Encaissement d'une facture — le PREMIER writer de `paiements` (PA-165,
 * 01/09/2026), et l'unique chemin d'écriture de cette table.
 *
 * ## La règle comptable du Product Owner s'applique en entier
 *
 * Tout mouvement d'argent produit son écriture réelle, côté domaine, dans la
 * MÊME transaction — et si la pièce est refusée, RIEN n'est écrit. La pièce :
 * un DÉBIT sur la trésorerie du mode de paiement — les comptes font foi chez
 * {@see DepenseService::TRESORERIES} et nulle part ailleurs — et un CRÉDIT sur
 * `4111` Clients, au journal de la trésorerie (CAI/BQ). Aucune TVA : un
 * encaissement de créance ne touche pas les produits, la taxe a été traitée
 * (ou refusée) à l'émission de la facture.
 *
 * ## Trois refus, tous locaux et corrigibles
 *
 * Facture non figée (une créance ne naît que d'une pièce opposable, RG-03) ;
 * aucune session de caisse ouverte (`paiements.session_id` NOT NULL : l'argent
 * entre dans un tiroir identifié) ; montant nul, négatif ou supérieur au reste
 * dû — un sur-encaissement créerait un avoir client qu'aucune table ne
 * modélise, il se REFUSE au lieu d'être absorbé en silence.
 *
 * ## PA-52 mord ici comme sur les ventes
 *
 * `paiements` n'a pas de colonne `ecriture_id` et `ecritures_comptables`
 * aucune colonne de pièce : le libellé « Encaissement <n°> — <uuid> » est le
 * lien, unique par l'UUID du paiement — même convention que les ventes
 * (PA-162), vérifiable par recherche de libellé.
 *
 * @see EF-M2-03 Encaissement des factures
 * @see docs/PLAN_ACTION_SEQUENCE_POST_AUDIT.md PA-21, PA-162, PA-165
 */
class EncaissementFactureService
{
    private const PRECISION = 2;

    /**
     * Mode de paiement (registre du schéma) → trésorerie de
     * {@see DepenseService::TRESORERIES}. « carte » entre en banque : le TPE
     * crédite le compte bancaire, jamais le tiroir.
     *
     * @var array<string, string>
     */
    public const TRESORERIE_PAR_MODE = [
        'especes' => 'caisse',
        'mobile_money' => 'momo',
        'carte' => 'banque',
        'virement' => 'banque',
    ];

    public function __construct(
        private readonly PasserEcritureService $ecritures,
    ) {
    }

    /**
     * @throws RuntimeException refus local : facture non figée, caisse fermée,
     *                          montant invalide ou supérieur au reste dû
     */
    public function encaisser(Facture $facture, string $montant, string $modePaiement): Paiement
    {
        if (! $facture->estFigee()) {
            throw new RuntimeException(__('facturation.encaissement_facture_non_figee'));
        }

        if (! array_key_exists($modePaiement, self::TRESORERIE_PAR_MODE)) {
            throw new RuntimeException(__('facturation.encaissement_mode_inconnu', ['mode' => $modePaiement]));
        }

        if (! is_numeric($montant) || bccomp($montant, '0', self::PRECISION) <= 0) {
            throw new RuntimeException(__('facturation.encaissement_montant_invalide'));
        }

        $resteDu = $facture->resteDu();

        if (bccomp($montant, $resteDu, self::PRECISION) > 0) {
            throw new RuntimeException(__('facturation.encaissement_superieur_au_reste', ['reste' => $resteDu]));
        }

        // Le tiroir OUVERT — pas « le dernier connu » : un encaissement hors
        // session fausserait la clôture de caisse de tout le monde.
        $session = SessionCaisse::query()
            ->whereNull('date_cloture')
            ->orderByDesc('date_ouverture')
            ->first();

        if ($session === null) {
            throw new RuntimeException(__('facturation.encaissement_caisse_fermee'));
        }

        $tresorerie = DepenseService::TRESORERIES[self::TRESORERIE_PAR_MODE[$modePaiement]];

        return DB::transaction(function () use ($facture, $montant, $modePaiement, $session, $tresorerie): Paiement {
            $paiement = Paiement::create([
                'facture_id' => $facture->id,
                'session_id' => $session->id,
                'mode_paiement' => $modePaiement,
                'montant' => bcadd($montant, '0', self::PRECISION),
                'date_paiement' => now(),
            ]);

            $libelle = sprintf('Encaissement %s — %s', (string) $facture->numero_mecef, $paiement->id);

            $this->ecritures->passerEtValider([
                'journal' => $tresorerie['journal'],
                'date' => now()->toDateString(),
                'libelle' => $libelle,
                'lignes' => [
                    ['compte' => $tresorerie['compte'], 'debit' => $montant, 'credit' => '0'],
                    ['compte' => ComptesSyscohada::CLIENTS, 'debit' => '0', 'credit' => $montant],
                ],
            ]);

            return $paiement->refresh();
        });
    }

    /**
     * Annulation d'un encaissement erroné — PA-168 (décision PO du
     * 01/09/2026, statut au schéma).
     *
     * L'annulation est un ÉTAT tracé (qui, quand, pourquoi), jamais une
     * suppression (RG-15) ; la correction comptable est la CONTRE-PASSATION
     * de la pièce ENTIÈRE (RG-11), retrouvée par son libellé unique — l'UUID
     * du paiement le rend sans collision (PA-52) — et VÉRIFIÉE équilibrée
     * avant inversion : une pièce à moitié retrouvée serait contre-passée à
     * moitié, en silence. Tout dans la même transaction : si la
     * contre-passation échoue, le paiement reste actif.
     *
     * @throws RuntimeException déjà annulé, motif vide ou pièce introuvable
     */
    public function annuler(Paiement $paiement, string $motif): Paiement
    {
        if ($paiement->statut === 'annule') {
            throw new RuntimeException(__('facturation.paiement_deja_annule'));
        }

        if (trim($motif) === '') {
            throw new RuntimeException(__('facturation.paiement_motif_requis'));
        }

        $libelle = sprintf(
            'Encaissement %s — %s',
            (string) $paiement->facture?->numero_mecef,
            $paiement->id,
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
            || bccomp($debit, (string) $paiement->montant, self::PRECISION) !== 0) {
            throw new RuntimeException(__('facturation.paiement_piece_introuvable', ['libelle' => $libelle]));
        }

        return DB::transaction(function () use ($paiement, $motif, $piece): Paiement {
            $this->ecritures->contrepasserPiece($piece, $motif);

            $paiement->update([
                'statut' => 'annule',
                'motif_annulation' => $motif,
                'annule_par_id' => auth()->id(),
                'date_annulation' => now(),
            ]);

            return $paiement->refresh();
        });
    }
}

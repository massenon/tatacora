<?php

declare(strict_types=1);

namespace App\Domain\Achats\Services;

use App\Domain\Achats\Models\CommandeAchat;
use Illuminate\Support\Facades\DB;

/**
 * Rapprochement à trois voies — EF-M7-04.
 *
 * Confronte **commande / réception / facture fournisseur**. C'est le contrôle
 * qui empêche de payer une facture pour des marchandises jamais reçues, ou
 * reçues en quantité moindre — la fraude fournisseur la plus banale.
 *
 * ## Ce que ce service peut et ne peut pas faire aujourd'hui
 *
 * - **Commande** : lisible directement (`lignes_commande_achat`).
 * - **Réception** : reconstituée depuis les `mouvements_stock` d'entrée
 *   rattachés aux bons de la commande, faute de table de lignes de réception
 *   (PA-39). C'est fonctionnel mais fragile : une entrée de stock saisie
 *   manuellement avec un motif ressemblant serait comptée comme une réception.
 * - **Facture fournisseur** : **aucune table ne l'accueille**. Le schéma n'a ni
 *   `factures_fournisseur` ni équivalent — `factures` est la facturation
 *   CLIENT (M2), de nature opposée. Les montants facturés sont donc passés en
 *   paramètre par l'appelant, sans persistance.
 *
 * Le troisième volet est donc **incomplet par manque de schéma**, pas par
 * manque d'implémentation. Tant qu'il n'existe pas, ce service compare
 * réellement deux voies sur trois et signale explicitement la troisième comme
 * non vérifiable — il ne prétend jamais avoir rapproché ce qu'il n'a pas vu.
 */
class ControleTroisVoiesService
{
    private const PRECISION = 2;

    /**
     * @param  array<string, string>|null  $montantsFactures  article_id => montant facturé, ou null si la facture n'est pas fournie
     * @return array{
     *     commande_id: string,
     *     lignes: list<array{article_id: string, commandee: string, recue: string, ecart: string, concordance: string}>,
     *     concordance_globale: string,
     *     facture_verifiable: bool,
     *     avertissements: list<string>
     * }
     */
    public function rapprocher(CommandeAchat $commande, ?array $montantsFactures = null): array
    {
        $recues = $this->quantitesRecues($commande);
        $lignes = [];
        $avertissements = [];
        $toutConcordant = true;

        foreach ($commande->lignes()->get() as $ligne) {
            $commandee = (string) $ligne->quantite_commandee;
            $recue = $recues[$ligne->article_id] ?? '0.00';
            $ecart = bcsub($recue, $commandee, self::PRECISION);
            $comparaison = bccomp($ecart, '0.00', self::PRECISION);

            $concordance = match (true) {
                $comparaison === 0 => 'conforme',
                $comparaison < 0 => 'manquant',
                default => 'excedent',
            };

            if ($concordance !== 'conforme') {
                $toutConcordant = false;
            }

            $lignes[] = [
                'article_id' => (string) $ligne->article_id,
                'commandee' => $commandee,
                'recue' => $recue,
                'ecart' => $ecart,
                'concordance' => $concordance,
            ];
        }

        if ($montantsFactures === null) {
            // Dire explicitement que la troisième voie n'a pas été vérifiée.
            // Un rapprochement présenté comme complet alors qu'il ne porte que
            // sur deux voies est pire que pas de rapprochement du tout : il
            // donne une assurance qu'il n'a pas.
            // Article 8 + i18n (02/09/2026) : la phrase vit dans
            // `lang/fr/achats.php`, l'auteur unique — elle etait ecrite EN
            // DUR ici avec sa reference PA-40, et le retrait des codes des
            // textes affiches l'a fait diverger de la cle sans qu'aucun
            // test ne le voie avant la certification.
            $avertissements[] = __('achats.rapprochement.facture_absente');
        }

        $avertissements[] = __('achats.rapprochement.reconstitution');

        return [
            'commande_id' => $commande->id,
            'lignes' => $lignes,
            'concordance_globale' => $toutConcordant ? 'conforme' : 'ecart_constate',
            'facture_verifiable' => $montantsFactures !== null,
            'avertissements' => $avertissements,
        ];
    }

    /**
     * Quantités reçues, reconstituées depuis les entrées de stock générées par
     * les bons de réception de cette commande.
     *
     * @return array<string, string> article_id => quantité
     */
    public function quantitesRecues(CommandeAchat $commande): array
    {
        $bonsIds = $commande->receptions()->pluck('id')->all();

        if ($bonsIds === []) {
            return [];
        }

        $mouvements = DB::table('mouvements_stock')
            ->where('type_mouvement', 'entree')
            ->where(function ($requete) use ($bonsIds) {
                foreach ($bonsIds as $bonId) {
                    $requete->orWhere('motif', 'like', '%bon ' . $bonId . '%');
                }
            })
            ->get(['article_id', 'quantite']);

        $totaux = [];

        foreach ($mouvements as $mouvement) {
            $articleId = (string) $mouvement->article_id;
            $totaux[$articleId] = bcadd(
                $totaux[$articleId] ?? '0.00',
                number_format((float) $mouvement->quantite, self::PRECISION, '.', ''),
                self::PRECISION,
            );
        }

        return $totaux;
    }
}

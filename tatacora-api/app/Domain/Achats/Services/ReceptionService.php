<?php

declare(strict_types=1);

namespace App\Domain\Achats\Services;

use App\Domain\Achats\Models\BonReception;
use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Shared\Parametres\Services\ParametreSystemeService;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Réception de commande d'achat — EF-M7-03, RG-10.
 *
 * ## Ce que fait ce service
 *
 * Enregistre un bon de réception, génère les **entrées de stock**
 * correspondantes, et détermine la conformité par rapport aux quantités
 * commandées, sous une tolérance paramétrable.
 *
 * « EF-M7-03 déclenche `mouvements_stock` (entrée) — **jamais de double-saisie
 * manuelle du stock après réception** » (05_MODULE_SPECIFICATIONS.md §M7).
 * Une saisie manuelle en plus de la réception doublerait le stock reçu.
 *
 * ## RG-10 — tolérance paramétrable, jamais codée en dur
 *
 * « Une commande ne peut être clôturée que si la quantité réceptionnée
 * correspond, dans une tolérance paramétrable, à la quantité commandée. »
 * Le pourcentage vit dans `parametres_systeme` (`tolerance_reception_pct`) :
 * un fournisseur qui livre 99,5 % d'un sac de riz de 50 kg n'est pas en défaut,
 * et le seuil acceptable est une décision de gestion, pas de développement.
 *
 * ## Limite structurelle assumée — PA-39
 *
 * `bons_reception` n'a **aucune table de lignes** : le schéma ne prévoit pas de
 * stocker la quantité reçue par article. Les quantités passées ici sont donc
 * matérialisées uniquement par les `mouvements_stock` d'entrée qu'elles
 * génèrent. Conséquence directe : le rapprochement à trois voies (EF-M7-04) ne
 * peut reconstituer le reçu qu'en relisant le journal de stock, ce qui est
 * moins robuste qu'une ligne de réception dédiée. Signalé à l'Architecte.
 */
class ReceptionService
{
    public const CLE_TOLERANCE = 'tolerance_reception_pct';

    /**
     * Écart conventionnel quand la quantité commandée est nulle : aucune
     * tolérance configurable ne peut l'absorber, la ligne est non conforme.
     */
    public const ECART_INCALCULABLE = '99999.99';

    private const PRECISION = 2;

    public function __construct(
        private readonly MouvementStockService $mouvements,
        private readonly ParametreSystemeService $parametres,
    ) {
    }

    /**
     * Enregistre une réception.
     *
     * @param  array<string, string>  $quantitesRecues  article_id => quantité reçue
     */
    public function receptionner(
        CommandeAchat $commande,
        array $quantitesRecues,
        string $pointStockageId,
        ?string $dateReception = null,
    ): BonReception {
        if ($commande->estCloturee()) {
            throw new RuntimeException(__('achats.commande_cloturee'));
        }

        if ($quantitesRecues === []) {
            throw new RuntimeException(__('achats.reception_vide'));
        }

        $this->verifierPointStockage($pointStockageId);

        return DB::transaction(function () use ($commande, $quantitesRecues, $pointStockageId, $dateReception) {
            $conformite = $this->evaluerConformite($commande, $quantitesRecues);

            $bon = BonReception::create([
                'commande_id' => $commande->id,
                'date_reception' => $dateReception ?? now()->toDateString(),
                'utilisateur_id' => auth()->id(),
                'conformite' => $conformite,
            ]);

            foreach ($quantitesRecues as $articleId => $quantite) {
                if (bccomp($quantite, '0.00', self::PRECISION) <= 0) {
                    continue;
                }

                // Entrée de stock générée par la réception — jamais saisie à la
                // main en plus (05_MODULE_SPECIFICATIONS.md §M7).
                $this->mouvements->entree(
                    articleId: $articleId,
                    pointId: $pointStockageId,
                    quantite: $quantite,
                    motif: __('achats.motif_reception', ['commande' => $commande->id, 'bon' => $bon->id]),
                );
            }

            $commande->update([
                'statut' => $conformite === 'totale' ? 'receptionnee' : 'receptionnee_partiellement',
            ]);

            return $bon->refresh();
        });
    }

    /**
     * Conformité d'une réception au regard de RG-10.
     *
     * - `totale` : chaque article reçu est dans la tolérance ;
     * - `partielle` : au moins un article est en deçà ;
     * - `non_conforme` : un article reçu ne figure pas dans la commande, ou un
     *   excédent dépasse la tolérance — recevoir plus que commandé n'est pas
     *   une bonne nouvelle, c'est une facture plus élevée que prévu.
     *
     * @param  array<string, string>  $quantitesRecues
     * @return 'totale'|'partielle'|'non_conforme'
     */
    public function evaluerConformite(CommandeAchat $commande, array $quantitesRecues): string
    {
        $tolerance = $this->tolerancePourcentage();
        $commandees = $commande->lignes()->pluck('quantite_commandee', 'article_id');

        foreach (array_keys($quantitesRecues) as $articleId) {
            if (! $commandees->has($articleId)) {
                return 'non_conforme';
            }
        }

        $conformite = 'totale';

        foreach ($commandees as $articleId => $quantiteCommandee) {
            $verdict = $this->conformiteLigne(
                $quantitesRecues[$articleId] ?? '0.00',
                (string) $quantiteCommandee,
                $tolerance,
            );

            if ($verdict === 'non_conforme') {
                return 'non_conforme';
            }

            if ($verdict === 'partielle') {
                $conformite = 'partielle';
            }
        }

        return $conformite;
    }

    /**
     * Verdict RG-10 pour **une** ligne — arithmétique pure, sans base.
     *
     * Extraite de `evaluerConformite()` pour être testable directement : c'est
     * ce calcul qui décide si une livraison est acceptée ou si une créance sur
     * le fournisseur est constatée, et ses cas de bord (pile sur la tolérance,
     * excédent, quantité commandée nulle) ne se laissent pas atteindre
     * commodément à travers un modèle Eloquent.
     *
     * @return 'totale'|'partielle'|'non_conforme'
     */
    public function conformiteLigne(string $recue, string $commandee, string $tolerancePct): string
    {
        $ecartPct = $this->ecartPourcentage($recue, $commandee);

        // Excédent au-delà de la tolérance : recevoir plus que commandé n'est
        // pas une bonne nouvelle, c'est une facture plus élevée que prévu.
        if (bccomp($ecartPct, $tolerancePct, self::PRECISION) > 0) {
            return 'non_conforme';
        }

        if (bccomp($ecartPct, bcmul($tolerancePct, '-1', self::PRECISION), self::PRECISION) < 0) {
            return 'partielle';
        }

        return 'totale';
    }

    /**
     * Écart reçu/commandé en pourcentage de la quantité commandée.
     *
     * Négatif = manquant, positif = excédent.
     *
     * **Cas de la quantité commandée nulle** : aucun pourcentage n'a de sens
     * (division par zéro). Tout reçu non nul en face est traité comme un
     * excédent infini, donc `non_conforme` — une ligne commandée à 0 qui
     * recevrait de la marchandise entrerait sinon en stock sans commande en
     * face, exactement ce que `receptionner()` refuse par ailleurs.
     */
    public function ecartPourcentage(string $recue, string $commandee): string
    {
        if (bccomp($commandee, '0.00', self::PRECISION) === 0) {
            return bccomp($recue, '0.00', self::PRECISION) === 0
                ? '0.00'
                : self::ECART_INCALCULABLE;
        }

        return bcdiv(bcmul(bcsub($recue, $commandee, self::PRECISION), '100', 4), $commandee, self::PRECISION);
    }

    /**
     * RG-10 — une commande ne se clôture que si la réception est dans la
     * tolérance. Une clôture forcée sur une livraison incomplète ferait perdre
     * la créance sur le fournisseur.
     */
    public function cloturer(CommandeAchat $commande): CommandeAchat
    {
        if ($commande->statut !== 'receptionnee') {
            throw new RuntimeException(__('achats.cloture_impossible'));
        }

        $commande->update(['statut' => 'cloturee']);

        return $commande->refresh();
    }

    /**
     * Tolérance en pourcentage. Refus explicite si non configurée — même
     * discipline que le taux de TVA et le taux d'IS : une tolérance devinée
     * ferait accepter ou refuser des livraisons sur un critère arbitraire.
     */
    public function tolerancePourcentage(): string
    {
        $valeur = $this->parametres->get(self::CLE_TOLERANCE);

        if (blank($valeur)) {
            throw new RuntimeException(__('achats.tolerance_absente', ['cle' => self::CLE_TOLERANCE]));
        }

        return $valeur;
    }

    private function verifierPointStockage(string $pointStockageId): void
    {
        if (! PointStockage::whereKey($pointStockageId)->exists()) {
            throw new RuntimeException(__('stocks.point_introuvable'));
        }
    }
}

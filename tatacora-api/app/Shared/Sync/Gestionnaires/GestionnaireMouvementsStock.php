<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\MouvementStock;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Shared\Sync\Models\AnomalieSynchronisation;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use RuntimeException;

/**
 * Les mouvements de stock SAISIS sur un poste — entrée (stock d'ouverture,
 * retour, transfert reçu), sortie, perte — lot 10f (audit de couverture du
 * 18/10/2026). Ceux qu'un document produit (réception, vente) ne passent pas
 * ici : le serveur les écrit lui-même en appliquant le document.
 *
 * Par `MouvementStockService`, et lui seul (CMP, prix d'achat, RG-07), sous
 * l'UUID du poste. Le mouvement est PHYSIQUE : une sortie que le stock du
 * serveur ne couvre pas est enregistrée quand même (rupture tracée au
 * journal d'audit, RG-06), et signalée si le poste ne l'avait pas forcée.
 * Création seule. Quantité en centièmes, coût en dix-millièmes (le poste).
 */
final class GestionnaireMouvementsStock extends GestionnaireDocumentAbstrait
{
    public function __construct(
        private readonly MouvementStockService $mouvements,
        private readonly StockTheoriqueService $stock,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'mouvements_stock';
    }

    public function module(): string
    {
        return 'M6';
    }

    public function serviceDomaine(): string
    {
        return MouvementStockService::class;
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        MouvementStock::query()->findOrFail($entiteId);

        return new EcritureSynchronisee($entiteId);
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $d = $this->validerForme($payload, [
            'article_id' => ['required', 'string'],
            'point_id' => ['required', 'string'],
            'type_mouvement' => ['required', 'in:entree,sortie,perte'],
            'quantite' => ['required', 'integer', 'min:1'],
            'motif' => ['required', 'string', 'max:255'],
            'cout_unitaire' => ['nullable', 'integer', 'min:0', 'prohibited_unless:type_mouvement,entree'],
            'rupture_forcee' => ['sometimes', 'boolean'],
            'date_mouvement' => ['nullable', 'string'],
        ]);

        $article = Article::query()->find($this->resoudre('articles', $d['article_id']));
        $point = PointStockage::query()->find($this->resoudre('points_stockage', $d['point_id']));

        if ($article === null || $point === null) {
            throw new RuntimeException(__('sync.stocks.reference_inconnue'));
        }

        $quantite = $this->centiemes((int) $d['quantite']);
        $le = $this->dateDuDocument($d['date_mouvement'] ?? null, $contexte);

        if ($d['type_mouvement'] === 'entree') {
            $this->mouvements->entree(
                (string) $article->id,
                (string) $point->id,
                $quantite,
                (string) $d['motif'],
                isset($d['cout_unitaire']) ? bcdiv((string) $d['cout_unitaire'], '10000', 4) : null,
                $le,
                $entiteId,
            );

            return $this->resultat($entiteId);
        }

        $disponible = $this->stock->stock((string) $article->id, (string) $point->id);

        if (bccomp($disponible, $quantite, 2) < 0 && ! ($d['rupture_forcee'] ?? false)) {
            $this->anomalies->signaler(
                $contexte,
                'mouvements_stock',
                $entiteId,
                AnomalieSynchronisation::MOUVEMENT_RUPTURE_SERVEUR,
                (string) $article->libelle,
                $quantite,
                $disponible,
            );
        }

        $this->mouvements->sortie(
            (string) $article->id,
            (string) $point->id,
            $quantite,
            (string) $d['motif'],
            validationRupture: true,
            type: (string) $d['type_mouvement'],
            dateMouvement: $le,
            id: $entiteId,
        );

        return $this->resultat($entiteId);
    }
}

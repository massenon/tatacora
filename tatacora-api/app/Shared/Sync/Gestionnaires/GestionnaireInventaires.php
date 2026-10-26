<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\Inventaire;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\InventaireService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use RuntimeException;

/**
 * Un inventaire physique CLÔTURÉ sur un poste (M6, EF-M6-05) — 21/10/2026,
 * « tout au complet » : ouvrir, compter et clôturer se font hors connexion.
 *
 * ## Un document COMPLET, atomique
 *
 * Le poste ne pousse l'inventaire qu'à sa clôture : l'en-tête (point, jour) ET
 * toutes ses lignes (article, théorique figé au comptage, constaté, écart)
 * arrivent dans UNE opération, écrite dans UNE transaction. Deux tables
 * séparées (`inventaires` puis `lignes_inventaire`) auraient permis qu'une
 * ligne arrive sans son inventaire, ou l'inverse : un inventaire sans ses
 * lignes se lit « rien n'a été compté », ce qui est faux.
 *
 * ## Rien n'est recalculé
 *
 * Le théorique est celui que le poste avait sous les yeux au moment de
 * compter ; celui du serveur, à l'instant de l'envoi, est autre (des ventes
 * ont pu arriver). Les valeurs du poste sont donc écrites telles quelles, et
 * l'écart n'est vérifié que contre lui-même (constaté − théorique).
 *
 * ## La régularisation n'est PAS ici
 *
 * Elle arrive comme tout mouvement saisi (`GestionnaireMouvementsStock` :
 * l'excédent en `inventaire`, le manquant en `perte`), sous l'UUID du poste.
 * Dans la file, l'inventaire précède ses mouvements.
 *
 * Création seule : un inventaire clôturé ne se rouvre pas (le schéma serveur
 * ne porte d'ailleurs aucun statut, PA-150). Le rejeu d'un même identifiant ne
 * double rien. Quantités en centièmes.
 */
final class GestionnaireInventaires extends GestionnaireDocumentAbstrait
{
    public function __construct(
        private readonly InventaireService $inventaires,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'inventaires';
    }

    public function module(): string
    {
        return 'M6';
    }

    public function serviceDomaine(): string
    {
        return InventaireService::class;
    }

    public function reprendreExistant(string $entiteId, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        return Inventaire::query()->whereKey($entiteId)->exists() ? $this->resultat($entiteId) : null;
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        return new EcritureSynchronisee($entiteId);
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $d = $this->validerForme($payload, [
            'point_id' => ['required', 'string'],
            'date_inventaire' => ['required', 'date_format:Y-m-d'],
            'lignes' => ['present', 'array'],
            'lignes.*.id' => ['nullable', 'string'],
            'lignes.*.article_id' => ['required', 'string'],
            'lignes.*.quantite_theorique' => ['required', 'integer'],
            'lignes.*.quantite_constatee' => ['required', 'integer', 'min:0'],
            'lignes.*.ecart' => ['required', 'integer'],
        ]);

        $point = PointStockage::query()->find($this->resoudre('points_stockage', $d['point_id']));

        if ($point === null) {
            throw new RuntimeException(__('sync.stocks.inventaire_point_inconnu'));
        }

        $lignes = [];
        $vus = [];

        foreach ($d['lignes'] as $ligne) {
            $article = Article::query()->find($this->resoudre('articles', $ligne['article_id']));

            if ($article === null) {
                throw new RuntimeException(__('sync.stocks.inventaire_article_inconnu', ['article' => $ligne['article_id']]));
            }

            if (isset($vus[$article->id])) {
                throw new RuntimeException(__('sync.stocks.inventaire_article_double', ['article' => (string) $article->libelle]));
            }

            $vus[$article->id] = true;

            // L'écart est la différence constaté − théorique, au centième
            // près : un écart qui s'en écarte est une ligne corrompue, pas un
            // arrondi — refusée avec l'inventaire entier.
            if ((int) $ligne['ecart'] !== (int) $ligne['quantite_constatee'] - (int) $ligne['quantite_theorique']) {
                throw new RuntimeException(__('sync.stocks.inventaire_ecart_incoherent', ['article' => (string) $article->libelle]));
            }

            $lignes[] = [
                'id' => $ligne['id'] ?? null,
                'article_id' => (string) $article->id,
                'quantite_theorique' => $this->centiemes((int) $ligne['quantite_theorique']),
                'quantite_constatee' => $this->centiemes((int) $ligne['quantite_constatee']),
                'ecart' => $this->centiemes((int) $ligne['ecart']),
            ];
        }

        $this->inventaires->enregistrerCloture(
            $entiteId,
            $point,
            (string) $d['date_inventaire'],
            (string) $contexte->utilisateur->id,
            $lignes,
        );

        return $this->resultat($entiteId);
    }
}

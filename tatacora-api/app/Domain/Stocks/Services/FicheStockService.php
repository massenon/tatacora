<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Services;

use App\Domain\Stocks\Models\Article;
use Illuminate\Support\Facades\DB;

/**
 * Fiche de stock d'un article sur une période — EF-M6-04.
 *
 * @see EF-M6-04 Historique des mouvements
 *
 * ## Ce que produit une fiche de stock, et pourquoi c'est un document distinct
 *
 * L'état des stocks (`EtatStocks`) donne une **photographie** : ce qu'il y a
 * en rayon aujourd'hui. La fiche de stock donne un **flux** sur une plage de
 * dates, et c'est le seul document qui permette de justifier un solde :
 *
 *     Stock initial (à la veille du début)
 *   + Entrées de la période
 *   − Sorties de la période
 *   − Pertes de la période
 *   ± Régularisations d'inventaire
 *   ─────────────────────────────────
 *   = Stock théorique en fin de période
 *
 * Cette égalité est **vérifiée** par le service, pas seulement affichée : si
 * elle tombe en défaut, c'est qu'un mouvement a été écrit hors du service
 * dédié, et le document le signale au lieu de présenter un total plausible.
 *
 * ## Stock initial = solde à la veille, jamais un champ saisi
 *
 * Le stock initial d'une période est le cumul de **tous** les mouvements
 * antérieurs à son début. Le saisir en dur — comme le fait le prototype avec
 * son champ `quantite_stock` éditable — transformerait un solde en
 * déclaration : plus rien ne serait rapprochable.
 */
class FicheStockService
{
    private const PRECISION = 2;

    /** Mouvements qui augmentent le stock. */
    private const ENTRANTS = ['entree', 'inventaire'];

    public function __construct(
        private readonly ValorisationStockService $valorisation,
    ) {
    }

    /**
     * La fiche CONSOLIDEE de tous les articles — demande du Product Owner du
     * 06/09/2026 : l'option « Tous les articles » du filtre.
     *
     * ## Ce qui est totalise, et ce qui ne peut pas l'etre
     *
     * Chaque article garde SA fiche, calculee par `pourArticle()` — jamais une
     * seconde requete ni une seconde formule : le solde progressif, le controle
     * de coherence et les cumuls restent ceux d'une fiche unitaire, et le jour
     * ou l'un changera, la vue consolidee suivra.
     *
     * ⚠ LES QUANTITES NE SE TOTALISENT PAS. Additionner 3 kg de riz, 2 casiers
     * de biere et 12 portions donnerait « 17 » de rien du tout — un chiffre
     * faux mais plausible, exactement ce que ce depot refuse. Seule la VALEUR
     * (en francs) est additionnable, parce qu'elle a une unite commune. La vue
     * affiche donc un nombre d'articles, un nombre de mouvements et une valeur
     * totale, jamais un cumul de quantites.
     *
     * Les articles SANS mouvement sur la periode sont ecartes du detail (leur
     * fiche n'aurait aucune ligne) mais comptes au stock valorise : un article
     * dormant a bien une valeur en magasin.
     *
     * @return array{
     *     articles: int,
     *     articles_avec_mouvement: int,
     *     mouvements: int,
     *     valeur_stock_theorique: string,
     *     incoherents: list<string>,
     *     lignes: list<array{date: string, type: string, motif: string, entree: string, sortie: string, solde: string, article: string, unite: string}>
     * }
     */
    public function pourTousLesArticles(string $debut, string $fin, ?string $pointId = null): array
    {
        $lignes = [];
        $valeur = '0.00';
        $articles = 0;
        $avecMouvement = 0;
        $incoherents = [];

        foreach (Article::query()->orderBy('libelle')->get() as $article) {
            $fiche = $this->pourArticle($article, $debut, $fin, $pointId);
            $articles++;
            $valeur = bcadd($valeur, $fiche['valeur_stock_theorique'], self::PRECISION);

            if (! $fiche['coherent']) {
                // Un ecart signale un mouvement ecrit hors du service : il est
                // NOMME, pas noye dans un compteur.
                $incoherents[] = $article->libelle;
            }

            if ($fiche['lignes'] === []) {
                continue;
            }

            $avecMouvement++;

            foreach ($fiche['lignes'] as $ligne) {
                // Le solde progressif reste celui de SON article : consolider
                // les soldes de plusieurs articles dans une seule colonne
                // n'aurait aucun sens, et la colonne « Article » est ce qui
                // rend la ligne lisible.
                $ligne['article'] = $article->libelle;
                $ligne['unite'] = (string) $article->unite_mesure;
                $lignes[] = $ligne;
            }
        }

        // Tri chronologique GLOBAL : la question que pose « tous les articles »
        // est « que s'est-il passe ce jour-la ? », pas « article par article ».
        usort($lignes, static fn (array $a, array $b): int => [$a['date'], $a['article']] <=> [$b['date'], $b['article']]);

        return [
            'articles' => $articles,
            'articles_avec_mouvement' => $avecMouvement,
            'mouvements' => count($lignes),
            'valeur_stock_theorique' => $valeur,
            'incoherents' => $incoherents,
            'lignes' => $lignes,
        ];
    }

    /**
     * @param  string|null  $pointId  restreint à un point de stockage, ou tous
     * @return array{
     *     article: array{id: string, libelle: string, unite: string, cmp: string},
     *     periode: array{debut: string, fin: string},
     *     stock_initial: string,
     *     entrees: string,
     *     sorties: string,
     *     pertes: string,
     *     regularisations: string,
     *     stock_theorique: string,
     *     valeur_stock_theorique: string,
     *     coherent: bool,
     *     lignes: list<array{date: string, type: string, motif: string, entree: string, sortie: string, solde: string}>
     * }
     */
    public function pourArticle(Article $article, string $debut, string $fin, ?string $pointId = null): array
    {
        $initial = $this->soldeAvant($article->id, $debut, $pointId);

        $mouvements = DB::table('mouvements_stock')
            ->where('article_id', $article->id)
            ->when($pointId !== null, fn ($q) => $q->where('point_id', $pointId))
            ->whereBetween('date_mouvement', [$debut . ' 00:00:00', $fin . ' 23:59:59'])
            ->orderBy('date_mouvement')
            ->orderBy('id')
            ->get();

        $cumuls = ['entree' => '0.00', 'sortie' => '0.00', 'perte' => '0.00', 'inventaire' => '0.00'];
        $solde = $initial;
        $lignes = [];

        foreach ($mouvements as $mouvement) {
            $quantite = bcadd((string) $mouvement->quantite, '0', self::PRECISION);
            $type = (string) $mouvement->type_mouvement;
            $entrant = in_array($type, self::ENTRANTS, true);

            $cumuls[$type] = bcadd($cumuls[$type], $quantite, self::PRECISION);
            $solde = $entrant
                ? bcadd($solde, $quantite, self::PRECISION)
                : bcsub($solde, $quantite, self::PRECISION);

            $lignes[] = [
                'date' => (string) $mouvement->date_mouvement,
                'type' => $type,
                'motif' => (string) $mouvement->motif,
                'entree' => $entrant ? $quantite : '0.00',
                'sortie' => $entrant ? '0.00' : $quantite,
                // Solde progressif : c'est ce qui rend la fiche vérifiable
                // ligne à ligne, comme un relevé bancaire.
                'solde' => $solde,
            ];
        }

        $theorique = $this->soldeAvant($article->id, $this->lendemain($fin), $pointId);

        return [
            'article' => [
                'id' => $article->id,
                'libelle' => $article->libelle,
                'unite' => $article->unite_mesure,
                'cmp' => $this->valorisation->cmp($article),
            ],
            'periode' => ['debut' => $debut, 'fin' => $fin],
            'stock_initial' => $initial,
            'entrees' => $cumuls['entree'],
            'sorties' => $cumuls['sortie'],
            'pertes' => $cumuls['perte'],
            'regularisations' => $cumuls['inventaire'],
            'stock_theorique' => $theorique,
            'valeur_stock_theorique' => $this->valorisation->valoriser($article, $theorique),
            // L'égalité est VÉRIFIÉE, pas supposée : un écart signale un
            // mouvement écrit hors de MouvementStockService.
            'coherent' => bccomp($solde, $theorique, self::PRECISION) === 0,
            'lignes' => $lignes,
        ];
    }

    /**
     * Solde à la veille d'une date — le stock initial de la période.
     *
     * Requête d'agrégat unique plutôt qu'un parcours des mouvements : sur un
     * article mouvementé depuis un an, la fiche du mois de décembre relirait
     * autrement toute l'année.
     */
    public function soldeAvant(string $articleId, string $date, ?string $pointId = null): string
    {
        $solde = DB::table('mouvements_stock')
            ->where('article_id', $articleId)
            ->when($pointId !== null, fn ($q) => $q->where('point_id', $pointId))
            ->where('date_mouvement', '<', $date . ' 00:00:00')
            ->selectRaw(StockTheoriqueService::EXPRESSION_SOLDE . ' AS solde')
            ->value('solde');

        return bcadd((string) ($solde ?? '0'), '0', self::PRECISION);
    }

    private function lendemain(string $date): string
    {
        return \Illuminate\Support\Carbon::parse($date)->addDay()->toDateString();
    }
}

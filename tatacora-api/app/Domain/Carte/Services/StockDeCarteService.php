<?php

declare(strict_types=1);

namespace App\Domain\Carte\Services;

use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\StockTheoriqueService;
use Throwable;

/**
 * Le STOCK D'UN ARTICLE DE CARTE (bar M5, restaurant M4) — lecture seule,
 * AUTEUR UNIQUE du chiffre que l'écran de carte et l'API rendent.
 *
 * ## Pourquoi un service, et pourquoi le 11/09/2026 (PA-199)
 *
 * Le calcul vivait dans le trait Livewire `EcranDeCarte::lignesDeLaCarte()`,
 * et l'API (`BoissonResource`) en écrivait une SECONDE version, fausse de
 * trois façons, mesurées :
 *
 *  1. elle rendait le solde en unités de STOCK (casiers) là où la carte rend
 *     des unités VENDABLES (bouteilles, solde × conditionnement) : pour un
 *     casier de 24, l'API disait « 2 » quand la PWA disait « 48 » ;
 *  2. elle prenait le point `bar` par `first()` SANS `ORDER BY` — l'ordre de
 *     MySQL n'est pas garanti, et avec deux points de bar elle pouvait lire
 *     l'autre (le piège que `CLAUDE.md` nomme pour les seeders) ;
 *  3. un échec de lecture la faisait lever, là où la carte dit « non
 *     consulté ».
 *
 * Aucun test ne le voyait : `VenteBarTest` emploie le conditionnement par
 * défaut, 1, où les deux unités se confondent.
 *
 * ## Trois états, jamais deux (PA-129)
 *
 * `stock` vaut `null` (aucun lien de stock), `['non_consulte' => true]` (point
 * absent ou lecture impossible) ou le détail chiffré. Replier les deux derniers
 * sur zéro afficherait une rupture là où il n'y a qu'une absence de réponse.
 *
 * Une instance MÉMOÏSE ses lectures : une carte de 80 boissons partageant 20
 * articles ne lit que 20 soldes. Prendre une instance neuve par écran rendu.
 *
 * @see EF-M5-02 Carte des boissons — RG-05 (décrémentation par le lien)
 */
final class StockDeCarteService
{
    private const PRECISION_STOCK = 2;

    private const PRECISION_CONVERSION = 4;

    /** @var array<string, string|null> solde au point, par article */
    private array $soldes = [];

    /** @var array<string, string|null> stock tous points, par article */
    private array $totaux = [];

    /** @var list<string> les articles dont la lecture a ÉCHOUÉ */
    private array $echecs = [];

    public function __construct(private readonly StockTheoriqueService $stocks)
    {
    }

    /**
     * Le point de vente du BAR — trié par libellé : sans `ORDER BY`, MySQL
     * rend l'ordre qui l'arrange, et deux points de bar liraient au hasard.
     */
    public function pointDuBar(): ?PointStockage
    {
        return PointStockage::query()
            ->where('type', 'bar')
            ->orderBy('libelle')
            ->first();
    }

    /**
     * Le point CUISINE, jamais tous points confondus — ce qui dort au magasin
     * n'est pas servi en salle. `restaurant` est accepté comme second libellé
     * de type : le schéma laisse la colonne libre, et les deux mots désignent
     * le même endroit au Gîte.
     */
    public function pointDeLaCuisine(): ?PointStockage
    {
        return PointStockage::query()
            ->whereIn('type', ['cuisine', 'restaurant'])
            ->orderBy('libelle')
            ->first();
    }

    /**
     * Le stock vendable d'un article de carte, et sa réserve.
     *
     * La RÉSERVE est le stock détenu AILLEURS qu'au point de vente — ce qui
     * dort au magasin —, en unités vendables comme le stock : total tous points
     * moins le point. Elle n'existe que quand le solde du point a pu être lu :
     * sans lui, `null`, jamais un zéro plausible.
     *
     * @return array{stock: array<string, mixed>|null, reserve: string|null}
     */
    public function etat(?Article $articleStock, ?string $conversion, ?PointStockage $point): array
    {
        if ($articleStock === null || $conversion === null) {
            return ['stock' => null, 'reserve' => null];
        }

        $identifiant = (string) $articleStock->id;

        if (! array_key_exists($identifiant, $this->soldes)) {
            $this->soldes[$identifiant] = $point === null
                ? null
                : $this->solde($identifiant, (string) $point->id);
        }

        $solde = $this->soldes[$identifiant];

        if ($solde === null) {
            return ['stock' => ['non_consulte' => true], 'reserve' => null];
        }

        $stock = [
            'non_consulte' => false,
            'article' => $articleStock,
            'solde' => $solde,
            'unites_vendables' => self::unitesVendables($solde, $conversion),
            'sous_seuil' => bccomp($solde, (string) ($articleStock->seuil_alerte ?? '0'), self::PRECISION_STOCK) <= 0,
            'rupture' => bccomp($solde, '0', self::PRECISION_STOCK) <= 0,
        ];

        if (! array_key_exists($identifiant, $this->totaux)) {
            try {
                $this->totaux[$identifiant] = $this->stocks->stockTousPoints($identifiant);
            } catch (Throwable $echec) {
                report($echec);

                $this->totaux[$identifiant] = null;
            }
        }

        $reserve = $this->totaux[$identifiant] === null
            ? null
            : self::unitesVendables(
                bcsub($this->totaux[$identifiant], $solde, self::PRECISION_STOCK),
                $conversion,
            );

        return ['stock' => $stock, 'reserve' => $reserve];
    }

    /**
     * Les articles dont la lecture du solde a ÉCHOUÉ — l'écran les compte et
     * le DIT (« non consulté »), distinctement d'un point de vente absent.
     *
     * @return list<string>
     */
    public function echecsDeLecture(): array
    {
        return $this->echecs;
    }

    /**
     * Le stock en unités VENDABLES — « il reste 47 bouteilles », pas « il
     * reste 1,96 casier ». Une seule multiplication sur le solde total : passer
     * par le facteur unitaire puis multiplier laisserait un résidu.
     */
    public static function unitesVendables(string $solde, string $conversion): string
    {
        if (bccomp($conversion, '0', self::PRECISION_CONVERSION) <= 0) {
            return '0';
        }

        return bcmul($solde, $conversion, 0);
    }

    /**
     * Le conditionnement d'un lien, en clair — « 24 par casier » se lit bien,
     * « 1/24 de casier » se lit mal (maître, `carte-module.js` l.135-143).
     *
     * Déplacé du trait Livewire `EcranDeCarte` le 11/09/2026 (PA-200) : la
     * colonne « Article de stock » du client Flutter rend la même phrase, et
     * une seconde écriture de cette règle en Dart aurait fini par diverger.
     */
    public static function conversionLisible(string $conversion, string $unite): string
    {
        $entier = rtrim(rtrim(number_format((float) $conversion, self::PRECISION_CONVERSION, '.', ''), '0'), '.');

        if (bccomp($conversion, '1', self::PRECISION_CONVERSION) > 0) {
            return __('carte_pwa.commun.conversion_par_unite', [
                'nombre' => $entier,
                'unite' => $unite,
            ]);
        }

        if (bccomp($conversion, '1', self::PRECISION_CONVERSION) === 0) {
            return __('carte_pwa.commun.conversion_par_vente', ['nombre' => '1', 'unite' => $unite]);
        }

        // Moins d'une unité vendable par unité de stock : une vente en
        // consomme plusieurs. Le maître rend alors `1 / quantite`.
        return __('carte_pwa.commun.conversion_par_vente', [
            'nombre' => rtrim(rtrim(bcdiv('1', $conversion, self::PRECISION_CONVERSION), '0'), '.'),
            'unite' => $unite,
        ]);
    }

    /**
     * Le solde, ou `null` quand il n'a PAS pu être lu — jamais `'0'` : une
     * panne de lecture passerait pour une rupture de stock.
     */
    private function solde(string $articleId, string $pointId): ?string
    {
        try {
            return $this->stocks->stock($articleId, $pointId);
        } catch (Throwable $echec) {
            $this->echecs[] = $articleId;

            report($echec);

            return null;
        }
    }
}

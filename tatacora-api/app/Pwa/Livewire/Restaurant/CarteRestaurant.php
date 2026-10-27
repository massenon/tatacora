<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Restaurant;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Carte\Services\StockDeCarteService;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Services\CartePlatMenuService;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Exports\CarteRestaurantExport;
use App\Pwa\Livewire\Concerns\EcranDeCarte;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\PageMetier;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Support\Collection;
use Illuminate\View\View;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Maatwebsite\Excel\Facades\Excel;
use Symfony\Component\HttpFoundation\Response;

/**
 * Carte du restaurant (M4) — disponibilité du jour et lien au stock.
 *
 * Maître : `prototype_v2/pages/m4-restaurant-carte.html`, dont le corps est
 * rendu par `prototype_v2/pages/carte-module.js` — le MÊME fichier que la
 * carte du bar. Le comportement partagé vit dans `EcranDeCarte` ; il ne reste
 * ici que ce qui distingue réellement le rayon.
 *
 * ## Deux chemins de décrémentation, et l'écran doit les distinguer
 *
 * Le chemin normal est la **fiche technique** (EF-M4-02) : un « Poulet DG »
 * n'est pas un article de stock, c'est une recette. Le second est le **lien
 * direct** (`article_id` + `unites_vendables_par_unite_stock`), pour ce qui se
 * revend en l'état — une bouteille d'eau servie à table, que le maître cite
 * nommément (`carte-engine.js` l.22-26).
 *
 * ⚠ `plats.article_id` était déclaré sur le modèle depuis longtemps et la
 * colonne n'existait dans AUCUNE migration : Eloquent lit un attribut absent
 * comme `null`, la relation ne ramenait jamais rien, et l'écran affichait un
 * tiret sur tout le monde sans que personne ne le voie. Elle existe depuis le
 * 31/08/2026 et cet écran l'exploite réellement — c'est elle que la modale
 * « Lier au stock » écrit, avec sa conversion.
 *
 * ## « Ne décrémentent rien » ne compte PAS les plats à fiche technique
 *
 * Un plat dont la recette porte au moins un ingrédient décrémente bel et bien
 * (`DeductionStockCuisineService`). Le compter dans la dette de couverture
 * afficherait un écart qui n'existe pas, sur l'indicateur même qui sert à le
 * résorber — voir `decremente()`.
 *
 * ## Ce que cet écran REFUSE, avec sa raison
 *
 * - **« Rapprocher automatiquement »** : le maître ne pose ce bouton que sur
 *   la carte du bar, et rapprocher un plat par libellé rattacherait
 *   « Poulet DG » à un article de stock, sortant une unité par assiette.
 * - **« Prix provisoires »** : `plats` ne porte aucune colonne le portant.
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M4-02 Fiches techniques (recettes)
 * @see RG-05 Sortie de stock automatique
 * @see LARAVEL_PWA.md §3, §5
 * @see DIRECTIVE_CONFORMITE_100.md Articles 3.3, 4.6
 */
#[Layout('layouts.pwa')]
#[Title('Carte du restaurant — LogiReStock — TATACORA AFRIQUE')]
class CarteRestaurant extends PageMetier
{
    use EcranDeCarte;
    use FormulaireModal;

    /** Le module RBAC de l'écran — `data-module="M4"` au maître. */
    public const MODULE = 'M4';

    /**
     * Les catégories de la carte, dans l'ordre du service.
     *
     * `plats.categorie` est un `varchar` libre au schéma : ce registre est la
     * seule liste fermée qui existe, et il est partagé avec le catalogue des
     * plats (`Restauration::CATEGORIES`), qui le reprend plutôt que d'en tenir
     * un second — deux listes finissent par diverger.
     *
     * @var array<string, string>
     */
    public const CATEGORIES = [
        'entrees' => 'Entrées',
        'plats' => 'Plats complets',
        'sauces' => 'Nos sauces',
        'garnitures' => 'Garnitures',
        'accompagnements' => 'Accompagnements',
        'sandwicherie' => 'Sandwicherie',
        'pizzas' => 'Pizzas',
        'desserts' => 'Nos desserts',
        'boissons_maison' => 'Jus maison & cafés',
        // 04/09/2026 — L'ARDOISE de la carte réelle : les formules « plat +
        // accompagnement » et les deux brochettes. Onze préparations que la
        // carte imprimée ne porte pas, et qui n'existaient nulle part.
        'formules' => 'Formules & brochettes',
    ];

    /** @var Collection<int, Plat>|null */
    protected ?Collection $cacheDesPlats = null;

    protected ?PointStockage $cacheDuPoint = null;

    public function render(): View
    {
        // `data-module` du `<body>` : celui de la PAGE DU MAÎTRE, jamais une
        // constante. La coquille se rabat sur M11 quand la vue ne le donne
        // pas — un écran M5 s'annoncerait alors page de tableau de bord.
        return view('pwa.restaurant.carte', array_merge(
            $this->socle(),
            $this->socleDeLaCarte(),
        ))->layout('layouts.pwa', ['module' => self::MODULE]);
    }

    // =====================================================================
    // « Délier » — il n'existe QU'ICI, et c'est une contrainte de schéma
    // =====================================================================

    /**
     * Ouvre la confirmation de retrait du lien direct.
     *
     * Ce geste n'a pas d'équivalent au bar : `cartes_boisson.article_id` y est
     * NOT NULL, le lien s'y remplace au lieu de se retirer. Sur un plat, le
     * lien direct est l'EXCEPTION — le retirer rend le plat à sa fiche
     * technique, ce qui est son état normal.
     */
    public function ouvrirRetraitDuLien(string $platId): void
    {
        $this->ouvrirFormulaire('delier');

        $plat = $this->trouverArticleDeCarte($platId);

        if (! $plat instanceof Plat) {
            abort(404);
        }

        if (! $plat->aUnLienDirectAuStock()) {
            // Le bouton n'est pas rendu dans cet état : y arriver signifie que
            // l'identifiant a été forcé depuis le navigateur.
            abort(403);
        }

        $this->articleCibleId = $platId;
    }

    /**
     * Retire le lien direct — les DEUX colonnes partent ensemble.
     *
     * `CartePlatMenuService::delierDuStock()` efface `article_id` ET
     * `unites_vendables_par_unite_stock` : laisser la conversion derrière
     * afficherait un taux sur un plat qui ne décrémente plus rien par ce
     * chemin.
     */
    public function confirmerRetraitDuLien(): void
    {
        $this->exigerEcriture(self::MODULE);

        $plat = $this->articleCibleId === null
            ? null
            : $this->trouverArticleDeCarte($this->articleCibleId);

        if (! $plat instanceof Plat) {
            abort(404);
        }

        app(CartePlatMenuService::class)->delierDuStock($plat);

        $this->cacheDesPlats = null;

        $this->terminerFormulaire(__('carte_pwa.commun.toast_lien_retire'));
    }

    /**
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        // Le registre commun est REPRIS, jamais recopié (Article 10).
        return array_merge($this->formulairesDeLaCarte(), [
            'delier' => ['articleCibleId'],
        ]);
    }

    // =====================================================================
    // Les crochets d'`EcranDeCarte`
    // =====================================================================

    protected function rayon(): string
    {
        return 'plat';
    }

    /**
     * Le point CUISINE, jamais tous points confondus.
     *
     * Même raison qu'au bar : ce qui dort au magasin n'est pas servi en salle.
     * `restaurant` est accepté comme second libellé de type parce que le
     * schéma laisse la colonne libre (`varchar`) et que les deux mots
     * désignent le même endroit au Gîte. `null` quand rien n'est déclaré.
     */
    protected function pointDeStockage(): ?PointStockage
    {
        // Un seul auteur (PA-199) — voir `StockDeCarteService::pointDeLaCuisine()`.
        return $this->cacheDuPoint ??= app(StockDeCarteService::class)->pointDeLaCuisine();
    }

    /**
     * @return array<string, string>
     */
    protected function categoriesDeLaCarte(): array
    {
        return self::CATEGORIES;
    }

    /**
     * @return Collection<int, Plat>
     */
    protected function articlesDeLaCarte(): Collection
    {
        // `recette.ingredients` est chargé parce que la colonne « Article de
        // stock » nomme la fiche technique et son nombre d'ingrédients : le
        // compter ligne par ligne ferait N+1 sur toute la carte.
        return $this->cacheDesPlats ??= Plat::query()
            ->with(['article', 'recette.ingredients'])
            ->orderBy('categorie')
            ->orderBy('libelle')
            ->get();
    }

    /** @param  Plat  $article */
    protected function modifierPrixDeLArticle(\App\Domain\Bar\Models\CarteBoisson|\App\Domain\Restaurant\Models\Plat $article, string $prix): void
    {
        if (! $article instanceof Plat) {
            // Le trait est partage par les deux cartes ; chaque ecran ne
            // modifie que SA famille — l'autre branche est une erreur d'appel.
            abort(404);
        }

        app(\App\Domain\Restaurant\Services\CartePlatMenuService::class)->modifierPlat($article, ['prix_vente' => $prix]);
    }

    protected function trouverArticleDeCarte(string $id): ?Plat
    {
        return Plat::query()->with(['article', 'recette.ingredients'])->find($id);
    }

    protected function rattacherAuStock(
        CarteBoisson|Plat $article,
        string $articleStockId,
        string $unitesVendablesParUniteStock,
    ): void {
        if (! $article instanceof Plat) {
            abort(404);
        }

        app(CartePlatMenuService::class)->lierAuStock(
            $article,
            $articleStockId,
            $unitesVendablesParUniteStock,
        );

        $this->cacheDesPlats = null;
    }

    protected function articleStockDe(CarteBoisson|Plat $article): ?Article
    {
        return $article->article instanceof Article ? $article->article : null;
    }

    protected function conversionDe(CarteBoisson|Plat $article): ?string
    {
        $conversion = $article->unites_vendables_par_unite_stock;

        return $conversion === null ? null : (string) $conversion;
    }

    /**
     * Un plat décrémente par son lien DIRECT ou par sa FICHE TECHNIQUE.
     *
     * Une recette sans aucun ingrédient ne décrémente rien, elle : elle porte
     * un nom et rien d'autre. La compter comme couverte masquerait exactement
     * la dette que l'onglet Couverture existe pour montrer.
     */
    protected function decremente(CarteBoisson|Plat $article): bool
    {
        if (! $article instanceof Plat) {
            // Impossible sur cet écran : le crochet est typé sur l'union des
            // deux rayons parce qu'il est déclaré dans le trait partagé.
            return false;
        }

        if ($article->aUnLienDirectAuStock()) {
            return true;
        }

        return $article->recette !== null
            && $article->recette->ingredients->isNotEmpty();
    }

    /**
     * @return array{libelle: string, detail: string, accent: bool}|null
     */
    protected function lienAffiche(CarteBoisson|Plat $article, ?Article $articleStock, ?string $conversion): ?array
    {
        $direct = $this->lienDirectAffiche($articleStock, $conversion);

        if ($direct !== null) {
            return $direct;
        }

        if (! $article instanceof Plat || $article->recette === null) {
            return null;
        }

        return [
            'libelle' => (string) $article->recette->libelle,
            'detail' => __('carte_pwa.restaurant.fiche_technique', [
                'nombre' => $article->recette->ingredients->count(),
            ]),
            'accent' => true,
        ];
    }

    protected function motifSansLien(): string
    {
        return __('carte_pwa.commun.sans_lien_restaurant');
    }

    /**
     * Le titre du document de ventes — LA CLÉ DE L'ONGLET, pas une seconde.
     *
     * Voir `CarteBar::libelleDesVentes()` : l'onglet, l'en-tête du PDF,
     * l'onglet du classeur et le titre de la modale d'export nomment le rayon
     * de la même façon parce qu'ils lisent la même clé.
     */
    protected function libelleDesVentes(): string
    {
        return __('carte_pwa.restaurant.onglet_ventes');
    }

    protected function nomDeFichierDesVentes(): string
    {
        return 'ventes_du_restaurant';
    }

    // =====================================================================
    // Documents
    // =====================================================================

    /**
     * @param  list<array<string, mixed>>  $lignes
     */
    protected function documentExport(string $format, array $lignes): Response
    {
        $horodatage = now()->format('Ymd_His');
        $entetes = $this->entetesExport();
        $matrice = $this->matriceExport($lignes);
        $filtre = $this->descriptionDuFiltre();

        if ($format === 'excel') {
            return Excel::download(
                new CarteRestaurantExport($entetes, $matrice, $filtre),
                'carte_du_restaurant_'.$horodatage.'.xlsx',
            );
        }

        $auteurCarte = auth()->user();

        $pdf = Pdf::loadView('pdf.carte', [
            // Identite par `ReportHeaderService`, jamais recopiee dans le
            // gabarit (03/09/2026 — non-conformite n° 1 de
            // `RESPECT_TABLEAU_RAPPORT.md` §4, corrigee).
            'entete' => app(\App\Shared\ReportEngine\Services\ReportHeaderService::class)->genererEnTete(
                __('carte_pwa.restaurant.titre'),
                $filtre,
                $auteurCarte instanceof \App\Models\User ? $auteurCarte : null,
            ),
            'titre' => __('carte_pwa.restaurant.titre'),
            'filtre' => $filtre,
            'entetes' => $entetes,
            'lignes' => $matrice,
            'indicateurs' => $this->indicateurs($this->lignesDeLaCarte()),
            'quand' => now()->format('d/m/Y à H:i'),
        ])->setPaper('a4', 'portrait');

        return response()->streamDownload(
            static fn () => print ($pdf->output()),
            'carte_du_restaurant_'.$horodatage.'.pdf',
        );
    }

    /**
     * @param  list<array{cle: string, libelle: string, articles: list<CarteBoisson|Plat>}>  $groupes
     */
    protected function documentFichePrix(array $groupes, int $sansPrix): Response
    {
        $pdf = Pdf::loadView('pdf.fiche-prix', [
            // L'identité seulement : la fiche garde sa propre mise en page.
            'entete' => $this->enTeteRapport(__('carte_pwa.fiche_prix_titre_restaurant'), now()->format('d/m/Y')),
            'titre' => __('carte_pwa.fiche_prix_titre_restaurant'),
            'groupes' => $groupes,
            'total' => array_sum(array_map(
                static fn (array $groupe): int => count($groupe['articles']),
                $groupes,
            )),
            'sansPrix' => $sansPrix,
            'quand' => now()->format('d/m/Y à H:i'),
        ])->setPaper('a4', 'portrait');

        return response()->streamDownload(
            static fn () => print ($pdf->output()),
            'fiche_des_prix_restaurant_'.now()->format('Ymd_His').'.pdf',
        );
    }
}

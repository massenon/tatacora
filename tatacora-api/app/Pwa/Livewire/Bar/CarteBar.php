<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Bar;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Bar\Services\CarteBoissonService;
use App\Domain\Carte\Services\StockDeCarteService;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Exports\CarteBarExport;
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
 * Carte du bar (M5) — disponibilité du jour et lien au stock.
 *
 * Maître : `prototype_v2/pages/m5-bar-carte.html`, dont le corps est rendu par
 * `prototype_v2/pages/carte-module.js` (le même fichier que la carte du
 * restaurant : le comportement partagé vit dans `EcranDeCarte`).
 *
 * ## Deux défauts bloquants fermés ici, et ils étaient invisibles
 *
 * 1. **Le taux de conversion était saisi, prévisualisé, puis JETÉ.** La modale
 *    « Lier au stock » demande « Combien de X dans une unité de stock ? » en
 *    champ obligatoire, avec un aperçu en direct — et le composant n'écrivait
 *    que `article_id`, la colonne n'existant pas. Un casier de 24 et une
 *    bouteille à l'unité produisaient le même enregistrement, donc la même
 *    décrémentation. `unites_vendables_par_unite_stock` la conserve désormais,
 *    et c'est `CarteBoissonService::lierAuStock()` qui l'écrit.
 * 2. **Aucun contrôle RBAC d'écriture.** Un rôle sans droit M5 rattachait une
 *    boisson au stock depuis son navigateur, alors que l'API le lui refuse en
 *    403 : une action Livewire ne passe pas par `ForcerLectureSeule` (PA-67).
 *
 * ## Ce que cet écran REFUSE, avec sa raison — deux refus, tous nommés
 *
 * - **« Délier »** : `cartes_boisson.article_id` est NOT NULL. Le lien se
 *   REMPLACE, il ne se retire pas, et `CarteBoissonService` n'expose aucun
 *   `delierDuStock()`. Rendre le bouton ferait échouer l'écriture sur la
 *   contrainte, message SQL à l'appui. L'arbitrage — rendre la colonne
 *   nullable — demande une migration et n'appartient pas à cet écran.
 * - **« Rapprocher automatiquement »** : inerte par construction, pour la même
 *   raison. Aucune boisson ne peut être sans lien.
 *
 * Un troisième refus, « Prix provisoires » (« aucune colonne au schéma »), est
 * LEVÉ depuis PA-161 (b) : la colonne existe, le filtre, l'indicateur et la
 * marque sont rendus. Le motif figurait encore ici le 11/09/2026 (PA-144 :
 * un motif périmé qu'on laisse en place ferme la question).
 *
 * @see EF-M5-02 Carte des boissons
 * @see RG-05 Sortie de stock automatique
 * @see LARAVEL_PWA.md §3, §5
 * @see DIRECTIVE_CONFORMITE_100.md Articles 3.3, 4.6
 */
#[Layout('layouts.pwa')]
#[Title('Carte du bar — LogiReStock — TATACORA AFRIQUE')]
class CarteBar extends PageMetier
{
    use EcranDeCarte;
    use FormulaireModal;

    /** Le module RBAC de l'écran — `data-module="M5"` au maître. */
    public const MODULE = 'M5';

    /**
     * Les catégories, dans l'ordre de l'`enum` de `cartes_boisson.categorie`.
     *
     * Registre fermé lu de la BASE, pas du prototype : une catégorie inventée
     * ici serait refusée à l'écriture par MySQL. Alias de
     * `CarteBoisson::CATEGORIES` — SOURCE UNIQUE, partagée avec le point de
     * vente (`ComposePanier`) depuis le 02/09/2026 : les deux écrans
     * rendaient chacun leur propre traduction du code brut de l'enum, deux
     * listes qui n'auraient pas tardé à diverger.
     *
     * @var array<string, string>
     */
    public const CATEGORIES = CarteBoisson::CATEGORIES;

    /** @var Collection<int, CarteBoisson>|null */
    protected ?Collection $cacheDesBoissons = null;

    protected ?PointStockage $cacheDuPoint = null;

    public function render(): View
    {
        // `data-module` du `<body>` : celui de la PAGE DU MAÎTRE, jamais une
        // constante. La coquille se rabat sur M11 quand la vue ne le donne
        // pas — un écran M5 s'annoncerait alors page de tableau de bord.
        return view('pwa.bar.carte', array_merge(
            $this->socle(),
            $this->socleDeLaCarte(),
        ))->layout('layouts.pwa', ['module' => self::MODULE]);
    }

    // =====================================================================
    // Les crochets d'`EcranDeCarte`
    // =====================================================================

    protected function rayon(): string
    {
        return 'boisson';
    }

    /**
     * Le POINT BAR, jamais tous points confondus.
     *
     * 24 bouteilles au bar et 100 au magasin font 24 vendables au comptoir.
     * Un stock tous points confondus rendrait 124 — vendable ce qui dort au
     * magasin. Le point est retrouvé par son `type`, la seule donnée que le
     * schéma porte ; `null` quand il n'est pas déclaré, et l'écran le DIT.
     */
    protected function pointDeStockage(): ?PointStockage
    {
        // Un seul auteur du point de vente du bar : l'API lit le même
        // (`StockDeCarteService::pointDuBar()`, PA-199).
        return $this->cacheDuPoint ??= app(StockDeCarteService::class)->pointDuBar();
    }

    /**
     * @return array<string, string>
     */
    protected function categoriesDeLaCarte(): array
    {
        return self::CATEGORIES;
    }

    /**
     * @return Collection<int, CarteBoisson>
     */
    protected function articlesDeLaCarte(): Collection
    {
        // Mémoïsé pour le temps de la requête : `render()` et `genererExport()`
        // parcourent la même carte, et `with('article')` évite le N+1 que la
        // colonne d'article de stock produirait ligne par ligne.
        return $this->cacheDesBoissons ??= CarteBoisson::query()
            ->with('article')
            ->orderBy('categorie')
            ->orderBy('libelle')
            ->get();
    }

    /** @param  CarteBoisson  $article */
    /** Saisie de la modale « Nouvelle boisson » (PO 03/09/2026). */
    public string $libelleSaisi = '';

    /** Saisie de la modale « Nouvelle boisson » (PO 03/09/2026). */
    public string $categorieSaisie = '';

    /**
     * Le registre des formulaires de CET ecran : ceux de la carte, plus la
     * creation de boisson, propre au bar (le restaurant cree ses plats sur
     * son ecran « Plats & menus »).
     *
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return array_merge($this->formulairesDeLaCarte(), [
            'boisson' => ['libelleSaisi', 'articleStockId', 'categorieSaisie', 'prixSaisi', 'rechercheArticleStock'],
            'modificationBoisson' => ['articleCibleId', 'libelleSaisi', 'categorieSaisie'],
        ]);
    }

    /**
     * Ouvre « Nouvelle boisson » — directive PO du 03/09/2026.
     *
     * ⚠ Ce geste MANQUAIT ENTIEREMENT a la PWA : `CarteBoissonService::creer()`
     * n'avait que deux appelants, l'API REST et l'import CSV. Sur un poste au
     * comptoir, ajouter une boisson exigeait donc un fichier ou un client
     * HTTP — le bar est pourtant le rayon ou le catalogue bouge le plus.
     * Le restaurant, lui, avait deja son ecran de creation de plat.
     */
    public function ouvrirCreationBoisson(): void
    {
        $this->ouvrirFormulaire('boisson');
        // Le registre n'est jamais vide (constante de `CarteBoisson`) : un
        // repli `?? ''` serait du code mort, et phpstan le dit.
        $this->categorieSaisie = (string) array_key_first(self::CATEGORIES);
    }

    /**
     * Enregistre la boisson — par le SERVICE de domaine, jamais un
     * `CarteBoisson::create()` local.
     *
     * Les regles sont celles de l'API (`EnregistrerBoissonRequest`), a la
     * lettre : deux canaux qui valideraient differemment finiraient par
     * accepter au navigateur ce que le serveur refuse, ou l'inverse.
     * `article_id` est une VRAIE cle etrangere (NOT NULL au schema) : sans
     * elle, aucune vente ne pourrait decrementer quoi que ce soit — c'est
     * pourquoi le champ est un selecteur d'articles de stock, jamais du
     * texte libre.
     */
    public function enregistrerCreationBoisson(): void
    {
        $valide = $this->validerEcriture([
            'libelleSaisi' => ['required', 'string', 'max:255'],
            'articleStockId' => ['required', 'string', 'exists:articles,id'],
            'categorieSaisie' => ['required', 'string', 'in:'.implode(',', array_keys(self::CATEGORIES))],
            'prixSaisi' => ['required', 'numeric', 'min:0'],
        ]);

        $boisson = app(CarteBoissonService::class)->creer([
            'libelle' => trim((string) $valide['libelleSaisi']),
            'article_id' => (string) $valide['articleStockId'],
            'categorie' => (string) $valide['categorieSaisie'],
            'prix_vente' => (string) $valide['prixSaisi'],
            // Un prix pose a la main EST une correction manuelle (PA-161 b) :
            // la marque suit le geste, elle n'est pas une case a cocher.
            'prix_corrige_main' => true,
        ]);

        $this->terminerFormulaire(__('carte_pwa.commun.toast_boisson_creee', [
            'article' => $boisson->libelle,
        ]));
    }

    /**
     * Ouvre « Modifier la boisson » - directive PO du 08/10/2026.
     *
     * Ce geste MANQUAIT : la carte ne modifiait que le prix, le lien au stock
     * et le retrait. Renommer une boisson ou la reclasser (locale, maison,
     * importee) exigeait l'API REST. Le formulaire est celui de « Nouvelle
     * boisson » SANS le prix (qui a sa modale tracee) ni l'article de stock
     * (qui a « Lier au stock ») : deux chemins d'ecriture pour un meme champ
     * divergeraient.
     *
     * @see EF-M5-02 Carte des boissons
     */
    public function ouvrirModificationBoisson(string $articleId): void
    {
        $boisson = $this->trouverArticleDeCarte($articleId);

        if ($boisson === null) {
            abort(404);
        }

        $this->ouvrirFormulaire('modificationBoisson');
        $this->articleCibleId = $articleId;
        $this->libelleSaisi = (string) $boisson->libelle;
        $this->categorieSaisie = (string) $boisson->categorie;
    }

    /**
     * Enregistre le libelle et la categorie - par le SERVICE de domaine, comme
     * le prix : `modifier()` ne recoit que ces deux cles, donc le prix, ses
     * marques (PA-161 b) et le lien au stock ne bougent pas. Regles identiques
     * a `EnregistrerBoissonRequest` (libelle, categorie).
     */
    public function enregistrerModificationBoisson(): void
    {
        $valide = $this->validerEcriture([
            'libelleSaisi' => ['required', 'string', 'max:255'],
            'categorieSaisie' => ['required', 'string', 'in:'.implode(',', array_keys(self::CATEGORIES))],
        ]);

        $boisson = $this->trouverArticleDeCarte((string) $this->articleCibleId);

        if ($boisson === null) {
            abort(404);
        }

        app(CarteBoissonService::class)->modifier($boisson, [
            'libelle' => trim((string) $valide['libelleSaisi']),
            'categorie' => (string) $valide['categorieSaisie'],
        ]);

        $this->terminerFormulaire(__('carte_pwa.commun.toast_boisson_modifiee', [
            'article' => trim((string) $valide['libelleSaisi']),
        ]));
    }

    protected function modifierPrixDeLArticle(\App\Domain\Bar\Models\CarteBoisson|\App\Domain\Restaurant\Models\Plat $article, string $prix): void
    {
        if (! $article instanceof CarteBoisson) {
            // Le trait est partage par les deux cartes ; chaque ecran ne
            // modifie que SA famille — l'autre branche est une erreur d'appel.
            abort(404);
        }

        app(CarteBoissonService::class)->modifier($article, ['prix_vente' => $prix]);
    }

    protected function trouverArticleDeCarte(string $id): ?CarteBoisson
    {
        return CarteBoisson::query()->with('article')->find($id);
    }

    protected function rattacherAuStock(
        CarteBoisson|Plat $article,
        string $articleStockId,
        string $unitesVendablesParUniteStock,
    ): void {
        if (! $article instanceof CarteBoisson) {
            abort(404);
        }

        app(CarteBoissonService::class)->lierAuStock(
            $article,
            $articleStockId,
            $unitesVendablesParUniteStock,
        );

        $this->cacheDesBoissons = null;
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

    protected function motifSansLien(): string
    {
        return __('carte_pwa.commun.sans_lien_bar');
    }

    /**
     * Le titre du document de ventes — LA CLÉ DE L'ONGLET, pas une seconde.
     *
     * `pwa/bar/carte.blade.php` passe la même à `$page['onglet_ventes']` :
     * l'onglet, l'en-tête du PDF, l'onglet du classeur et le titre de la
     * modale d'export nomment ainsi tous le rayon de la même façon.
     */
    protected function libelleDesVentes(): string
    {
        return __('carte_pwa.bar.onglet_ventes');
    }

    protected function nomDeFichierDesVentes(): string
    {
        return 'ventes_du_bar';
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
                new CarteBarExport($entetes, $matrice, $filtre),
                'carte_du_bar_'.$horodatage.'.xlsx',
            );
        }

        $auteurCarte = auth()->user();

        $pdf = Pdf::loadView('pdf.carte', [
            // Identite par `ReportHeaderService`, jamais recopiee dans le
            // gabarit (03/09/2026 — non-conformite n° 1 de
            // `RESPECT_TABLEAU_RAPPORT.md` §4, corrigee).
            'entete' => app(\App\Shared\ReportEngine\Services\ReportHeaderService::class)->genererEnTete(
                __('carte_pwa.bar.titre'),
                $filtre,
                $auteurCarte instanceof \App\Models\User ? $auteurCarte : null,
            ),
            'titre' => __('carte_pwa.bar.titre'),
            'filtre' => $filtre,
            'entetes' => $entetes,
            'lignes' => $matrice,
            'indicateurs' => $this->indicateurs($this->lignesDeLaCarte()),
            'quand' => now()->format('d/m/Y à H:i'),
        ])->setPaper('a4', 'portrait');

        return response()->streamDownload(
            static fn () => print ($pdf->output()),
            'carte_du_bar_'.$horodatage.'.pdf',
        );
    }

    /**
     * @param  list<array{cle: string, libelle: string, articles: list<CarteBoisson|Plat>}>  $groupes
     */
    protected function documentFichePrix(array $groupes, int $sansPrix): Response
    {
        $pdf = Pdf::loadView('pdf.fiche-prix', [
            // L'identité seulement : la fiche garde sa propre mise en page.
            'entete' => $this->enTeteRapport(__('carte_pwa.fiche_prix_titre_bar'), now()->format('d/m/Y')),
            'titre' => __('carte_pwa.fiche_prix_titre_bar'),
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
            'fiche_des_prix_bar_'.now()->format('Ymd_His').'.pdf',
        );
    }
}

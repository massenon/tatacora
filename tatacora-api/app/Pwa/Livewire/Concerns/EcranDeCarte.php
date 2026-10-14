<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Concerns;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Carte\Models\HistoriquePrixCarte;
use App\Domain\Carte\Models\IndisponibiliteCarte;
use App\Domain\Carte\Services\DisponibiliteCarteService;
use App\Domain\Carte\Services\StockDeCarteService;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\ConsultationStockService;
use App\Domain\Ventes\Models\LigneVente;
use App\Domain\Ventes\Models\Vente;
use App\Domain\Ventes\Services\LignesVenteDuRayonService;
use App\Exports\VentesDuRayonExport;
use App\Models\User;
use App\Pwa\Support\MontantFcfa;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;
use Livewire\Attributes\Url;
use Maatwebsite\Excel\Facades\Excel;
use RuntimeException;

/**
 * L'ÉCRAN DE CARTE — un seul comportement pour le bar (M5) et le restaurant (M4).
 *
 * Maîtres : `prototype_v2/pages/m5-bar-carte.html`,
 * `prototype_v2/pages/m4-restaurant-carte.html` et le fichier qui porte le
 * corps des deux, `prototype_v2/pages/carte-module.js`.
 *
 * ## Pourquoi UN trait plutôt que deux écrans
 *
 * `carte-module.js` s'annonce lui-même « ÉCRAN DE CARTE — partagé par le
 * Restaurant (M4) et le Bar (M5) », et sa raison est écrite en toutes lettres
 * l.7 : « Deux écrans jumeaux finiraient par diverger au premier ajustement ».
 * La PWA en avait déjà deux, et ils avaient déjà divergé — la carte du bar
 * affichait le sous-titre du restaurant, et l'onglet Couverture du bar n'avait
 * pas la ligne TOTAL que celui du restaurant n'avait pas non plus.
 *
 * Ce qui change entre les deux tient dans le module RBAC, le modèle, le rayon
 * et le bandeau — exactement les quatre crochets abstraits ci-dessous.
 *
 * ## `use FormulaireModal` est DANS ce trait, et la classe le reprend
 *
 * `PwaEcritureAutoriseeTest::traitsDe()` remonte les traits de la classe et
 * **un seul niveau** de traits de traits. Sans `use FormulaireModal` sur la
 * classe elle-même, `AutoriseEcriture` se trouverait à trois niveaux et la
 * garde annoncerait « la classe ne porte pas le trait » sur un composant qui
 * le porte réellement. PHP accepte qu'un trait soit repris par la classe et
 * par un trait qu'elle utilise : l'aplatissement ne produit pas de collision.
 *
 * ## Ce que ce trait N'EXPOSE PAS, et pourquoi
 *
 * - **`rapprocherAutomatiquement`** n'existe nulle part. Au bar, il serait
 *   inerte par construction : `cartes_boisson.article_id` est NOT NULL, aucune
 *   boisson ne peut être sans lien, et le bouton répondrait toujours « aucun
 *   rapprochement possible ». Au restaurant, le maître ne le pose pas — et
 *   rapprocher un plat par libellé rattacherait « Poulet DG » à un article de
 *   stock. Les deux refus sont NOMMÉS à l'écran.
 * - **`fermerModales`** n'existe pas : la fermeture passe par
 *   `$set('etatFormulaire', null)`, action du CADRE Livewire. Une méthode
 *   publique de plus serait une action de plus sur le chemin que
 *   `ForcerLectureSeule` ne couvre pas (PA-67), pour un geste qui n'écrit rien.
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M5-02 Carte des boissons
 * @see RG-05 Sortie de stock automatique — la conversion saisie ici la pilote
 * @see LARAVEL_PWA.md §3 (un composant appelle le Service de domaine)
 * @see DIRECTIVE_CONFORMITE_100.md Articles 3.3, 4.6, 10
 */
trait EcranDeCarte
{
    use FormulaireModal;

    /** Précision des conversions — celle de la colonne `DECIMAL(15,4)`. */
    private const PRECISION_CONVERSION = 4;

    /** Précision des montants — celle de `DECIMAL(15,2)`. */
    private const PRECISION_MONTANT = 2;

    /**
     * 10 lignes par page — motif G6 du dépôt, la valeur du moteur du maître
     * (`crud-engine.js` l.21, `lignesParPage = 10`). Recopiée à l'identique de
     * `Facturation::PAR_PAGE` : deux écrans qui paginent différemment finissent
     * par diverger.
     */
    public const PAR_PAGE = 10;

    #[Url(as: 'onglet')]
    public string $onglet = 'carte';

    #[Url(as: 'q')]
    public string $recherche = '';

    #[Url(as: 'categorie')]
    public string $categorie = '';

    #[Url(as: 'etat')]
    public string $etat = '';

    // ---- Onglet « Ventes du rayon » (Product Owner, 03/09/2026) ---------
    //
    // Les filtres de cet onglet portent leurs PROPRES clés d'URL : `q`,
    // `categorie` et `etat` filtrent la CARTE, jamais les ventes. Partager
    // une clé ferait qu'un terme saisi sur un onglet viderait l'autre sans
    // que rien ne le dise — et l'URL, qui doit rester partageable, ne dirait
    // plus lequel des deux tableaux elle décrit.

    #[Url(as: 'qv')]
    public string $rechercheVentes = '';

    /** Une valeur de `Vente::STATUTS`, ou `''` pour « toutes ». */
    #[Url(as: 'vstatut')]
    public string $statutVente = '';

    /** Borne BASSE de la plage, incluse — `AAAA-MM-JJ`. */
    #[Url(as: 'du')]
    public string $debutVentes = '';

    /** Borne HAUTE de la plage, incluse — voir `requeteDesVentes()`. */
    #[Url(as: 'au')]
    public string $finVentes = '';

    /**
     * La page courante — motif G6 : propriété `#[Url]` passée EXPLICITEMENT
     * en quatrième argument de `paginate()`, jamais le trait
     * `WithPagination` (sept actions Livewire de plus sur le chemin que
     * `ForcerLectureSeule` ne couvre pas, PA-67).
     */
    #[Url(as: 'page')]
    public int $pageCourante = 1;

    /** L'article de carte visé par la modale ouverte. */
    public ?string $articleCibleId = null;

    /** Saisie de la modale « Modifier le prix » (PO 02/09/2026). */
    public string $prixSaisi = '';

    // ---- Modale « Lier au stock » ---------------------------------------

    public ?string $articleStockId = null;

    /**
     * Le nombre d'unités VENDABLES contenues dans une unité de stock.
     *
     * ⚠ Le sens est porté par le nom, et l'inverser vide le stock 24 fois trop
     * vite — le maître le dit lui-même (`carte-module.js` l.119-126). La
     * déduction vaut `quantité vendue / cette valeur`.
     *
     * Chaîne, jamais flottant : c'est un facteur de mouvement de stock, soumis
     * à la même règle que les montants (`bccomp`, jamais `==`).
     */
    public string $unitesVendablesParUniteStock = '1';

    /**
     * Le terme de recherche du sélecteur d'article de stock.
     *
     * Le maître pose `data-recherche data-placeholder="Rechercher un article
     * de stock…"` (`carte-module.js` l.236-237) parce que la liste dépasse la
     * trentaine de références : sur un `<select>` natif, choisir demande de
     * défiler à l'aveugle. La PWA n'a pas de composant `SelectRecherche` ; le
     * filtre est fait au serveur et le `<select>` ne rend que ce qui reste.
     */
    public string $rechercheArticleStock = '';

    // ---- Modale « Retirer de la carte du jour » --------------------------

    public string $motifIndisponibilite = 'rupture';

    public string $commentaireIndisponibilite = '';

    // ---- Modale d'export -------------------------------------------------

    public string $formatExport = 'pdf';

    /**
     * Les articles de stock lisibles dont le solde n'a PAS pu être lu.
     *
     * Un échec de lecture se nomme à l'écran ; il ne se replie ni sur zéro ni
     * sur une collection vide. « 0 » se lirait comme une rupture, c'est-à-dire
     * comme un fait (PA-129).
     *
     * @var list<string>
     */
    protected array $stocksNonConsultes = [];

    /**
     * Vrai quand le point de stockage du rayon n'est pas déclaré.
     *
     * L'écran le NOMME et ne rend aucun chiffre de stock : replier sur le
     * stock tous points confondus rendrait vendable ce qui dort au magasin,
     * et replier sur zéro afficherait une rupture générale.
     */
    protected bool $pointDeStockageAbsent = false;

    // =====================================================================
    // Les quatre crochets — tout ce qui distingue les deux rayons
    // =====================================================================

    /** `boisson` ou `plat` — la clé de `DisponibiliteCarteService`. */
    abstract protected function rayon(): string;

    /**
     * Le point de stockage DEPUIS LEQUEL on vend — jamais tous points confondus.
     *
     * ⚠ C'est une décision déjà relue de ce dépôt, et elle s'écarte du maître.
     * `carte-engine.js` l.173 lit `StockEngine.stockTousPoints()` parce que son
     * prototype n'a pas de points de stockage. Ici il y en a : 24 bouteilles au
     * bar et 100 au magasin font 24 vendables au comptoir, pas 124. Un stock
     * tous points confondus rendrait vendable ce qui dort au magasin.
     *
     * Rend `null` quand le point n'est pas déclaré : l'écran le DIT et
     * n'affiche aucun chiffre, plutôt que d'en inventer un.
     */
    abstract protected function pointDeStockage(): ?PointStockage;

    /**
     * Les catégories de l'écran, dans l'ordre du maître.
     *
     * @return array<string, string>
     */
    abstract protected function categoriesDeLaCarte(): array;

    /**
     * Tous les articles de la carte, article de stock déjà chargé.
     *
     * ⚠ `iterable` et non `Collection` : la carte du bar rend une collection
     * de `CarteBoisson`, celle du restaurant une collection de `Plat`, et
     * `Collection<T>` est INVARIANT — aucune des deux ne serait acceptée pour
     * `Collection<CarteBoisson|Plat>`. Le trait ne fait que la parcourir.
     *
     * @return iterable<CarteBoisson|Plat>
     */
    abstract protected function articlesDeLaCarte(): iterable;

    abstract protected function trouverArticleDeCarte(string $id): CarteBoisson|Plat|null;

    /**
     * Rattache l'article au stock — en appelant le Service de son domaine.
     *
     * Chaque écran l'implémente avec SON service typé plutôt que de recevoir
     * ici un objet quelconque : c'est ce qui garde l'appel vérifiable par
     * PHPStan et par la garde d'écriture, qui reconnaît les écritures de
     * Service par leur nom.
     *
     * @throws RuntimeException article inconnu ou conversion non positive
     */
    abstract protected function rattacherAuStock(
        CarteBoisson|Plat $article,
        string $articleStockId,
        string $unitesVendablesParUniteStock,
    ): void;

    /** Le libellé de l'article de stock lié, ou `null` s'il n'y en a pas. */
    abstract protected function articleStockDe(CarteBoisson|Plat $article): ?Article;

    /** La conversion enregistrée, ou `null` quand l'article n'est pas lié. */
    abstract protected function conversionDe(CarteBoisson|Plat $article): ?string;

    /**
     * L'article DÉCRÉMENTE-T-IL réellement un stock à la vente ?
     *
     * Ce n'est pas la même question que « a-t-il un article de stock ». Au
     * bar, les deux coïncident. Au restaurant, un plat décrémente normalement
     * par sa FICHE TECHNIQUE (EF-M4-02), sans le moindre `article_id` : le
     * compter « ne décrémente rien » afficherait une dette de couverture qui
     * n'existe pas, sur l'indicateur même qui sert à la résorber.
     *
     * Le défaut par défaut est le lien direct — c'est le cas du bar, et c'est
     * la mesure du maître.
     */
    protected function decremente(CarteBoisson|Plat $article): bool
    {
        return $this->articleStockDe($article) !== null;
    }

    /**
     * La ligne d'explication rendue sous l'article de stock quand il n'y en a
     * pas — elle n'a pas le même sens des deux côtés.
     */
    abstract protected function motifSansLien(): string;

    /**
     * Ce que la colonne « Article de stock » affiche pour cette ligne.
     *
     * Au bar, c'est l'article et son conditionnement, et rien d'autre. Au
     * restaurant, un plat sans lien direct peut porter une FICHE TECHNIQUE —
     * la nommer est la seule façon de distinguer « ce plat se décrémente
     * autrement » de « ce plat ne décrémente rien », deux états que le tiret
     * du maître confond.
     *
     * @return array{libelle: string, detail: string, accent: bool}|null
     */
    protected function lienAffiche(CarteBoisson|Plat $article, ?Article $articleStock, ?string $conversion): ?array
    {
        return $this->lienDirectAffiche($articleStock, $conversion);
    }

    /**
     * Le lien DIRECT, rendu identiquement des deux côtés.
     *
     * Méthode à part parce qu'un écran qui redéfinit `lienAffiche()` ne peut
     * pas appeler la version du trait : PHP l'a remplacée, il n'y a pas de
     * `parent::` pour un trait. La recopier dans l'écran ferait deux rendus
     * d'une seule information (Article 10).
     *
     * @return array{libelle: string, detail: string, accent: bool}|null
     */
    final protected function lienDirectAffiche(?Article $articleStock, ?string $conversion): ?array
    {
        if ($articleStock === null || $conversion === null) {
            return null;
        }

        return [
            'libelle' => (string) $articleStock->libelle,
            'detail' => $this->conversionLisible(
                $conversion,
                (string) ($articleStock->unite_mesure ?? __('carte_pwa.commun.unite_defaut')),
            ),
            'accent' => false,
        ];
    }

    // =====================================================================
    // Actions — chaque écriture exige le droit, à l'ouverture ET à l'écriture
    // =====================================================================

    /**
     * Ouvre « Lier au stock » — le lien se crée ou se remplace.
     *
     * Le droit est exigé par `ouvrirFormulaire()` : présenter un formulaire à
     * quelqu'un qui ne pourra pas le soumettre lui fait perdre sa saisie.
     */
    public function ouvrirLienAuStock(string $articleId): void
    {
        $this->ouvrirFormulaire('lien');

        $article = $this->trouverArticleDeCarte($articleId);

        if ($article === null) {
            abort(404);
        }

        $this->articleCibleId = $articleId;
        $this->articleStockId = $this->articleStockDe($article)?->id;

        // La valeur proposée est CELLE QUI EST ENREGISTRÉE, jamais 1 par
        // défaut : rouvrir la modale d'un casier de 24 pour corriger l'article
        // et repartir avec 1 diviserait la déduction par vingt-quatre.
        $this->unitesVendablesParUniteStock = $this->conversionDe($article)
            ?? '1';
    }

    /**
     * Enregistre le lien ET sa conversion.
     *
     * ⚠ C'est le défaut que cet écran existe pour fermer : la modale demandait
     * déjà la conversion, en champ OBLIGATOIRE, avec un aperçu en direct — et
     * le composant n'écrivait que `article_id`. Un casier de 24 et une
     * bouteille à l'unité produisaient le même enregistrement.
     */
    public function enregistrerLienAuStock(): void
    {
        $valide = $this->validerEcriture([
            'articleStockId' => ['required', 'string', 'exists:articles,id'],
            'unitesVendablesParUniteStock' => ['required', 'numeric', 'gt:0'],
        ]);

        $article = $this->trouverArticleDeCarte((string) $this->articleCibleId);

        if ($article === null) {
            abort(404);
        }

        try {
            $this->rattacherAuStock(
                $article,
                (string) $valide['articleStockId'],
                (string) $valide['unitesVendablesParUniteStock'],
            );
        } catch (RuntimeException $refus) {
            // Le refus du domaine est AFFICHÉ tel quel : il nomme la donnée en
            // cause. L'avaler et annoncer « enregistré avec avertissement »
            // laissait croire qu'une conversion avait été retenue.
            $this->addError('unitesVendablesParUniteStock', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('carte_pwa.commun.toast_lien_enregistre', [
            'article' => $article->libelle,
        ]));
    }

    /**
     * Ouvre « Retirer de la carte du jour ».
     *
     * Le maître bascule sans modale quand l'article est DÉJÀ retiré
     * (`carte-module.js` l.311-316) : c'est `remettreALaCarte()` qui porte ce
     * sens-là, et la vue rend le bouton « Remettre » à sa place.
     */
    public function ouvrirRetraitDeLaCarte(string $articleId): void
    {
        $this->ouvrirFormulaire('retrait');

        $article = $this->trouverArticleDeCarte($articleId);

        if ($article === null) {
            abort(404);
        }

        $this->articleCibleId = $articleId;
        // Le premier motif du registre du maître — `rupture`. Il est LU du
        // registre plutôt qu'écrit ici : un motif retiré demain ne doit pas
        // laisser un défaut de formulaire pointant sur une clé absente.
        $this->motifIndisponibilite = (string) array_key_first(IndisponibiliteCarte::MOTIFS);
    }

    /**
     * Persiste le retrait — en base, jamais en session.
     *
     * ⚠ `CarteBar::enregistrerDispo()` faisait `Session::put(...)`. Un plat
     * retiré revenait tout seul à l'expiration de la session, aucun autre
     * poste ne le voyait retiré, et la décision n'était imputable à personne.
     * Les codes divergeaient de surcroît (`hors_saison` / `retrait` là où le
     * maître écrit `saison` / `retire`) sans que rien ne se voie à l'écran.
     */
    public function enregistrerRetraitDeLaCarte(): void
    {
        $valide = $this->validerEcriture([
            'motifIndisponibilite' => ['required', 'string', 'in:'.implode(',', array_keys(IndisponibiliteCarte::MOTIFS))],
            'commentaireIndisponibilite' => ['nullable', 'string', 'max:255'],
        ]);

        $article = $this->trouverArticleDeCarte((string) $this->articleCibleId);

        if ($article === null) {
            abort(404);
        }

        try {
            app(DisponibiliteCarteService::class)->rendreIndisponible(
                $article,
                (string) $valide['motifIndisponibilite'],
                (string) $valide['commentaireIndisponibilite'],
            );
        } catch (RuntimeException $refus) {
            $this->addError('motifIndisponibilite', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('carte_pwa.commun.toast_retire', [
            'article' => $article->libelle,
        ]));
    }

    /**
     * Remet l'article à la carte — l'indisponibilité est LEVÉE, pas effacée.
     *
     * `DisponibiliteCarteService::rendreDisponible()` renseigne
     * `date_retour_disponibilite` : effacer la ligne effacerait l'historique
     * des ruptures, qui est précisément ce sur quoi se décide un
     * réapprovisionnement.
     */
    public function remettreALaCarte(string $articleId): void
    {
        $this->exigerEcriture(static::MODULE);

        $article = $this->trouverArticleDeCarte($articleId);

        if ($article === null) {
            abort(404);
        }

        try {
            app(DisponibiliteCarteService::class)->rendreDisponible($article);
        } catch (RuntimeException $refus) {
            $this->addError('etat', $refus->getMessage());

            return;
        }

        session()->flash('pwa-succes', __('carte_pwa.commun.toast_remis', [
            'article' => $article->libelle,
        ]));
    }

    /**
     * Ouvre « Historique des prix » — demande du Product Owner du 01/09/2026 :
     * « on doit retracer les changements de prix » (M4/M5).
     *
     * ⚠ AUCUN droit d'écriture n'est exigé, comme `genererExport()` juste
     * après : consulter une trace n'écrit rien, même famille que
     * `ClientsCreances::ouvrirHistoriqueClient()` (M3, PA-165). Un `barman` en
     * `L` sur M5 doit pouvoir vérifier depuis quand un tarif a changé sans
     * avoir le droit de le modifier.
     */
    /**
     * Ouvre « Modifier le prix » — directive PO du 02/09/2026, second volet
     * de « on doit retracer les changements de prix » (01/09/2026) : la
     * TRACE existait (`HistoriquePrixCarte`, ecrite par les Observers),
     * le GESTE manquait — l'historique documentait des changements
     * qu'aucun ecran ne permettait de faire.
     */
    public function ouvrirModificationPrix(string $articleId): void
    {
        $article = $this->trouverArticleDeCarte($articleId);

        if ($article === null) {
            abort(404);
        }

        $this->ouvrirFormulaire('prix');
        $this->articleCibleId = $articleId;
        $this->prixSaisi = (string) $article->prix_vente;
    }

    /**
     * Enregistre le nouveau prix — par le SERVICE de domaine de chaque
     * carte (`CarteBoissonService::modifier()` /
     * `CartePlatMenuService::modifierPlat()`), jamais un `update()` local :
     * c'est la que vivent les marques de prix (PA-161 b), et l'Observer y
     * consigne la trace pour l'historique.
     *
     * `gt:0` et non `gte:0` : un prix a zero rendrait l'article invendable
     * sans un mot — retirer un article de la vente est le geste « Retirer
     * de la carte », qui porte son motif.
     */
    public function enregistrerModificationPrix(): void
    {
        $valide = $this->validerEcriture([
            'prixSaisi' => ['required', 'numeric', 'gt:0'],
        ]);

        $article = $this->trouverArticleDeCarte((string) $this->articleCibleId);

        if ($article === null) {
            abort(404);
        }

        $this->modifierPrixDeLArticle($article, (string) $valide['prixSaisi']);

        $this->terminerFormulaire(__('carte_pwa.commun.toast_prix_modifie', [
            'article' => $article->libelle,
        ]));
    }

    /** Le chemin d'ecriture du prix — le service de domaine de CHAQUE carte. */
    abstract protected function modifierPrixDeLArticle(CarteBoisson|Plat $article, string $prix): void;

    /**
     * Ferme la modale ouverte — nom CANONIQUE du depot, celui que le chassis
     * `<x-pwa.modale>` et le partial `modale-export` appellent par defaut.
     *
     * Il manquait aux deux ecrans de carte (03/09/2026) : la croix du
     * chassis ET le bouton « Annuler » de la modale d'export levaient une
     * MethodNotFoundException — un 500 sur un simple clic de fermeture, que
     * seule une garde de conformite pouvait voir (aucun test fonctionnel ne
     * clique une croix). Lecture pure : aucune ecriture, aucun droit exige.
     */
    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->resetValidation();
    }

    public function ouvrirHistoriquePrix(string $articleId): void
    {
        if ($this->trouverArticleDeCarte($articleId) === null) {
            abort(404);
        }

        $this->articleCibleId = $articleId;
        $this->etatFormulaire = 'historiquePrix';
    }

    /**
     * Exporte CE QUI EST AFFICHÉ, et le document DIT son filtre (PA-119).
     *
     * ⚠ AUCUN droit d'écriture n'est exigé, et c'est délibéré : un export ne
     * produit rien de neuf, il rend sur un autre papier ce que l'écran affiche
     * déjà. `genererExport` et `imprimerFichePrix` sont inscrites dans les
     * méthodes de LECTURE de `PwaEcritureAutoriseeTest` (31/08/2026) — un
     * `barman` en `L` sur M5 doit pouvoir sortir sa fiche des prix.
     *
     * La note antérieure, reprise de M8, disait l'inverse et affirmait que la
     * liste des lectures « ne peut pas être étendue depuis un composant » :
     * c'était vrai à l'écriture, et faux depuis. Elle est retirée plutôt que
     * laissée à vieillir (PA-144).
     *
     * ## L'export porte sur l'ONGLET COURANT (Product Owner, 03/09/2026)
     *
     * Un seul bouton « Exporter », une seule modale, et le document suit ce
     * que l'écran montre AU MOMENT du clic. Rendre la carte à quelqu'un qui
     * regarde le tableau des ventes serait la moitié de PA-119 : le périmètre
     * du document ne serait pas celui qu'il croit avoir vérifié — et le
     * défaut serait muet, puisque le fichier téléchargé est parfaitement
     * valide, simplement pas celui qu'on regardait.
     *
     * L'onglet Couverture n'a pas de branche : il rend une SYNTHÈSE de la
     * carte, calculée sur les mêmes lignes, et son export est l'état de la
     * carte — celui que la branche par défaut produit déjà.
     *
     * @return \Symfony\Component\HttpFoundation\Response|null
     */
    public function genererExport()
    {
        $format = $this->formatExport === 'excel' ? 'excel' : 'pdf';

        if ($this->ongletValide() === 'ventes') {
            return $this->exportDesVentes($format);
        }

        $lignes = $this->lignesFiltrees($this->lignesDeLaCarte());

        if ($lignes === []) {
            // PA-119 : une liste vide se REFUSE. Une page blanche que l'on
            // croirait complète est pire que pas de document du tout.
            $this->addError('formatExport', __('carte_pwa.export_vide'));

            return null;
        }

        $this->etatFormulaire = null;

        return $this->documentExport($format, $lignes);
    }

    /**
     * La fiche des prix — le document REMIS AU CLIENT, groupé par catégorie.
     *
     * Elle écarte les articles non tarifés et le DIT : un tarif absent devient
     * négociable au comptoir (maître, `m5-bar-carte.html` l.113-118). Elle se
     * refuse entièrement quand il ne reste rien — une fiche des prix sans
     * aucun prix n'est qu'une page d'en-tête.
     *
     * Comme l'export, elle N'EXIGE AUCUN droit d'écriture : c'est le document
     * remis au client, et un rôle en lecture doit pouvoir l'imprimer.
     *
     * @return \Symfony\Component\HttpFoundation\Response|null
     */
    public function imprimerFichePrix()
    {
        $tarifes = [];
        $sansPrix = 0;

        foreach ($this->articlesDeLaCarte() as $article) {
            if (bccomp((string) $article->prix_vente, '0.00', 2) > 0) {
                $tarifes[] = $article;

                continue;
            }

            $sansPrix++;
        }

        if ($tarifes === []) {
            $this->addError('formatExport', __('carte_pwa.fiche_prix_vide'));

            return null;
        }

        $this->etatFormulaire = null;

        if ($sansPrix > 0) {
            session()->flash('pwa-avertissement', __('carte_pwa.fiche_prix_sans_prix', [
                'nombre' => $sansPrix,
            ]));
        }

        return $this->documentFichePrix($this->grouperParCategorie($tarifes), $sansPrix);
    }

    // =====================================================================
    // Ce que chaque écran fournit pour ses documents
    // =====================================================================

    /**
     * @param  list<array<string, mixed>>  $lignes
     * @return \Symfony\Component\HttpFoundation\Response
     */
    abstract protected function documentExport(string $format, array $lignes);

    /**
     * @param  list<array{cle: string, libelle: string, articles: list<CarteBoisson|Plat>}>  $groupes
     * @return \Symfony\Component\HttpFoundation\Response
     */
    abstract protected function documentFichePrix(array $groupes, int $sansPrix);

    // =====================================================================
    // Lecture — une requête par famille, jamais une par ligne
    // =====================================================================

    /**
     * Les formulaires communs aux deux cartes.
     *
     * `CarteRestaurant` en ajoute un (« Délier ») en reprenant cette liste :
     * la recopier ferait deux registres qui divergeraient (Article 10).
     *
     * @return array<string, list<string>>
     */
    protected function formulairesDeLaCarte(): array
    {
        return [
            'lien' => [
                'articleCibleId',
                'articleStockId',
                'unitesVendablesParUniteStock',
                'rechercheArticleStock',
            ],
            'retrait' => [
                'articleCibleId',
                'motifIndisponibilite',
                'commentaireIndisponibilite',
            ],
            'prix' => ['articleCibleId', 'prixSaisi'],
            'export' => ['formatExport'],
        ];
    }

    /**
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return $this->formulairesDeLaCarte();
    }

    /**
     * Le registre FERMÉ des onglets de l'écran.
     *
     * `ventes` est un AJOUT au maître (Product Owner, 03/09/2026) : ni
     * `m5-bar-carte.html` ni `m4-restaurant-carte.html` n'ont d'onglet de
     * ventes. Le code le nomme neutralement — le libellé, lui, diffère d'un
     * rayon à l'autre (« Ventes du Bar » / « Ventes du Restaurant ») et vient
     * du `$page` de chaque vue, comme le titre et le bandeau.
     *
     * Un onglet hors registre retombe sur `carte` : une valeur forcée dans
     * l'URL ne doit pas rendre une page sans aucun panneau.
     */
    protected function ongletValide(): string
    {
        return in_array($this->onglet, ['carte', 'couverture', 'ventes'], true) ? $this->onglet : 'carte';
    }

    protected function categorieValide(): ?string
    {
        return array_key_exists($this->categorie, $this->categoriesDeLaCarte())
            ? $this->categorie
            : null;
    }

    /**
     * Toutes les lignes de la carte, enrichies — UNE requête d'indisponibilité
     * pour tout l'écran, et un solde de stock par article de stock DISTINCT.
     *
     * `indisponibilitesEnCours()` est appelée une fois : demander
     * `indisponibilite()` par ligne ferait N+1 sur une carte de cinquante
     * articles. Le solde, lui, passe par `StockTheoriqueService` — le
     * ré-agréger ici dupliquerait la seule source de vérité du niveau de stock.
     *
     * @return list<array<string, mixed>>
     */
    protected function lignesDeLaCarte(): array
    {
        $indisponibilites = app(DisponibiliteCarteService::class)
            ->indisponibilitesEnCours($this->rayon());

        // L'auteur unique du stock de carte (PA-199) — l'API le lit aussi. Une
        // instance NEUVE par rendu : elle mémoïse les soldes de cette carte.
        $stocks = app(StockDeCarteService::class);
        $point = $this->pointDeStockage();
        $this->stocksNonConsultes = [];
        $this->pointDeStockageAbsent = $point === null;

        $lignes = [];

        foreach ($this->articlesDeLaCarte() as $article) {
            $articleStock = $this->articleStockDe($article);
            $conversion = $this->conversionDe($article);
            $indisponibilite = $indisponibilites->get($article->getKey());

            // Trois états, jamais deux, et la réserve (colonne du maître,
            // `carte-module.js` l.408) : voir `StockDeCarteService::etat()`.
            ['stock' => $stock, 'reserve' => $reserve] = $stocks->etat($articleStock, $conversion, $point);

            $lignes[] = [
                'modele' => $article,
                'id' => (string) $article->getKey(),
                'nom' => (string) $article->libelle,
                'categorie_cle' => (string) ($article->categorie ?? ''),
                'categorie' => $this->categoriesDeLaCarte()[$article->categorie ?? ''] ?? (string) ($article->categorie ?? ''),
                'prix' => MontantFcfa::format((string) $article->prix_vente),
                // PA-161 (b) — les deux marques du maitre, rendues SOUS le
                // prix (`carte-module.js` l.108-109). Elles etaient refusees
                // faute de colonne ; les colonnes existent depuis le
                // 02/09/2026, et le refus est leve avec son motif.
                'prix_provisoire' => $article->prix_provisoire === true,
                'prix_corrige_main' => $article->prix_corrige_main === true,
                'disponible' => $indisponibilite === null,
                'indisponibilite' => $indisponibilite,
                'article_stock' => $articleStock,
                'decremente' => $this->decremente($article),
                'lien_affiche' => $this->lienAffiche($article, $articleStock, $conversion),
                'conversion' => $conversion,
                'stock' => $stock,
                'reserve' => $reserve,
            ];
        }

        // Les lectures qui ont ÉCHOUÉ, que l'écran compte et DIT — un point
        // de vente absent, lui, est dit par `pointDeStockageAbsent`.
        $this->stocksNonConsultes = $stocks->echecsDeLecture();

        return $lignes;
    }

    /**
     * « 24 par casier » se lit bien ; « 1/24 de casier » se lit mal.
     *
     * Le maître présente la conversion à l'endroit (`carte-module.js`
     * l.135-143), et c'est aussi le sens dans lequel la colonne est stockée :
     * il n'y a plus rien à inverser à l'affichage.
     */
    protected function conversionLisible(string $conversion, string $unite): string
    {
        // Un seul auteur de la phrase (PA-200) : l'API rend la même.
        return StockDeCarteService::conversionLisible($conversion, $unite);
    }

    /**
     * Les filtres de l'écran, appliqués aux lignes déjà enrichies.
     *
     * @param  list<array<string, mixed>>  $lignes
     * @return list<array<string, mixed>>
     */
    protected function lignesFiltrees(array $lignes): array
    {
        $categorie = $this->categorieValide();
        $terme = trim($this->recherche);

        return array_values(array_filter($lignes, function (array $ligne) use ($categorie, $terme): bool {
            if ($categorie !== null && $ligne['categorie_cle'] !== $categorie) {
                return false;
            }

            if ($terme !== '' && mb_stripos((string) $ligne['nom'], $terme) === false) {
                return false;
            }

            return match ($this->etat) {
                'indisponible' => $ligne['disponible'] === false,
                'lie' => $ligne['decremente'] === true,
                'sans_lien' => $ligne['decremente'] === false,
                'rupture_stock' => is_array($ligne['stock']) && ($ligne['stock']['rupture'] ?? false) === true,
                // maitre — `carte-module.js` l.227 : `if (f.etat ===
                // 'provisoire') return i.prix_provisoire;`
                'provisoire' => $ligne['prix_provisoire'] === true,
                default => true,
            };
        }));
    }

    /**
     * La couverture, catégorie par catégorie, plus la ligne TOTAL du maître.
     *
     * @param  list<array<string, mixed>>  $lignes
     * @return array{categories: list<array<string, mixed>>, total: array<string, mixed>}
     */
    protected function couverture(array $lignes): array
    {
        $parCategorie = [];

        foreach ($this->categoriesDeLaCarte() as $cle => $libelle) {
            $parCategorie[$cle] = [
                'cle' => $cle,
                'libelle' => $libelle,
                'total' => 0,
                'lies' => 0,
                'sans_lien' => 0,
                'indisponibles' => 0,
                'provisoires' => 0,
                'taux' => 0.0,
            ];
        }

        foreach ($lignes as $ligne) {
            $cle = $ligne['categorie_cle'];

            if (! array_key_exists($cle, $parCategorie)) {
                // Une catégorie hors registre est RENDUE, pas jetée : la
                // taire ferait un total qui ne correspond pas à la somme des
                // lignes, sans que rien ne l'explique.
                $parCategorie[$cle] = [
                    'cle' => $cle,
                    'libelle' => $ligne['categorie'],
                    'total' => 0,
                    'lies' => 0,
                    'sans_lien' => 0,
                    'indisponibles' => 0,
                    'provisoires' => 0,
                    'taux' => 0.0,
                ];
            }

            $parCategorie[$cle]['total']++;

            if ($ligne['decremente'] === true) {
                $parCategorie[$cle]['lies']++;
            } else {
                $parCategorie[$cle]['sans_lien']++;
            }

            if ($ligne['disponible'] === false) {
                $parCategorie[$cle]['indisponibles']++;
            }

            if ($ligne['prix_provisoire'] === true) {
                $parCategorie[$cle]['provisoires']++;
            }
        }

        foreach ($parCategorie as $cle => $categorie) {
            $parCategorie[$cle]['taux'] = $categorie['total'] > 0
                ? round(($categorie['lies'] / $categorie['total']) * 100, 1)
                : 0.0;
        }

        return [
            'categories' => array_values($parCategorie),
            'total' => $this->indicateurs($lignes),
        ];
    }

    /**
     * Les indicateurs du bandeau de KPI — ceux du maître, moins celui qui
     * n'est pas dérivable.
     *
     * ⚠ « Prix provisoires » a longtemps rendu « — », faute de colonne : le
     * dériver de `prix_vente <= 0` sur deux colonnes NOT NULL affichait zéro
     * en permanence, c'est-à-dire « aucun prix provisoire » sans l'avoir
     * vérifié (PA-59/60/61). PA-161 (b) a créé la colonne ; le compteur lit
     * désormais la donnée, et le refus est levé avec son motif (PA-144).
     *
     * @param  list<array<string, mixed>>  $lignes
     * @return array<string, int|float>
     */
    protected function indicateurs(array $lignes): array
    {
        $total = count($lignes);
        $indisponibles = 0;
        $lies = 0;
        $rupture = 0;
        $sousSeuil = 0;
        $provisoires = 0;

        foreach ($lignes as $ligne) {
            if ($ligne['disponible'] === false) {
                $indisponibles++;
            }

            if ($ligne['prix_provisoire'] === true) {
                $provisoires++;
            }

            if ($ligne['decremente'] === true) {
                $lies++;
            }

            if (is_array($ligne['stock']) && ($ligne['stock']['non_consulte'] ?? false) === false) {
                if ($ligne['stock']['rupture'] === true) {
                    $rupture++;
                } elseif ($ligne['stock']['sous_seuil'] === true) {
                    $sousSeuil++;
                }
            }
        }

        return [
            'articles' => $total,
            'disponibles' => $total - $indisponibles,
            'indisponibles' => $indisponibles,
            'lies' => $lies,
            'sans_lien' => $total - $lies,
            'taux_couverture' => $total > 0 ? round(($lies / $total) * 100, 1) : 0.0,
            'en_rupture_stock' => $rupture,
            'sous_seuil' => $sousSeuil,
            // maitre — `carte-module.js` l.277 et l.395 : le nombre de tarifs
            // poses faute de releve, ceux qui restent a confronter a la carte.
            'prix_provisoires' => $provisoires,
        ];
    }

    /**
     * Les articles de stock proposés par la modale, filtrés par la recherche.
     *
     * ⚠ Restreints au SUIVI PERMANENT — c'est la phrase du maître, et elle est
     * désormais appliquée : « un article en achat journalier n'est pas suivi,
     * le rattacher ne décrémenterait rien » (`carte-module.js` l.240-243). La
     * modale l'annonçait jusqu'ici sous une réserve disant que le schéma ne
     * distinguait pas les deux ; `articles.suivi` existe depuis PA-161 (a), et
     * un filtre annoncé mais non appliqué est pire que pas de filtre du tout :
     * le lecteur croit la liste réduite.
     *
     * @return Collection<int, Article>
     */
    protected function articlesDeStock(): Collection
    {
        $terme = trim($this->rechercheArticleStock);

        return Article::query()
            ->where('suivi', ConsultationStockService::SUIVI_AVEC_STOCK)
            ->when($terme !== '', fn ($requete) => $requete->where('libelle', 'like', '%'.$terme.'%'))
            ->orderBy('libelle')
            ->limit(200)
            ->get();
    }

    /**
     * L'aperçu de la modale — ce qui sera RÉELLEMENT enregistré.
     *
     * Il ne se calcule pas à partir d'une valeur par défaut : quand la saisie
     * n'est pas exploitable, il n'y a pas d'aperçu, exactement comme au maître
     * (`carte-module.js` l.272 : `if (!a || !Number.isFinite(par) || par <= 0)
     * { … return; }`). Afficher un aperçu bâti sur 1 laisserait croire que la
     * saisie vide vaut « une pour une ».
     *
     * @return array{article: Article, solde: ?string, vendables: ?string, decrement: string}|null
     */
    protected function apercuDuLien(): ?array
    {
        if ($this->articleStockId === null || ! is_numeric($this->unitesVendablesParUniteStock)) {
            return null;
        }

        if (bccomp($this->unitesVendablesParUniteStock, '0', self::PRECISION_CONVERSION) <= 0) {
            return null;
        }

        $article = Article::find($this->articleStockId);

        if (! $article instanceof Article) {
            return null;
        }

        // Le même auteur que la colonne de stock (PA-199), avec la conversion
        // SAISIE : l'aperçu dit ce que la carte affichera une fois enregistré.
        ['stock' => $stock] = app(StockDeCarteService::class)->etat(
            $article,
            $this->unitesVendablesParUniteStock,
            $this->pointDeStockage(),
        );
        $chiffre = is_array($stock) && ($stock['non_consulte'] ?? true) === false;

        return [
            'article' => $article,
            'solde' => $chiffre ? (string) $stock['solde'] : null,
            'vendables' => $chiffre ? (string) $stock['unites_vendables'] : null,
            // Ce que chaque vente retirera du stock : `1 / conversion`, rendu
            // au dix-millième comme la colonne, zéros de fin retirés.
            'decrement' => rtrim(rtrim(
                bcdiv('1', $this->unitesVendablesParUniteStock, self::PRECISION_CONVERSION),
                '0',
            ), '.'),
        ];
    }

    /**
     * Le filtre RÉELLEMENT appliqué, en clair, pour que l'export le DISE.
     *
     * PA-119 : quelqu'un qui filtre puis exporte attend son filtre ; lui
     * rendre le registre entier lui ferait envoyer au comptable un document
     * qu'il croit avoir vérifié.
     */
    protected function descriptionDuFiltre(): string
    {
        $morceaux = [];
        $categorie = $this->categorieValide();

        if ($categorie !== null) {
            $morceaux[] = __('carte_pwa.filtre_categorie', [
                'categorie' => $this->categoriesDeLaCarte()[$categorie],
            ]);
        }

        if (trim($this->recherche) !== '') {
            $morceaux[] = __('carte_pwa.filtre_terme', ['terme' => trim($this->recherche)]);
        }

        // Le registre des états est FERMÉ, et il est écrit ici plutôt que
        // construit par concaténation : `'etat_'.$this->etat` produirait une
        // clé de langue inexistante pour `rupture_stock`, et Laravel rendrait
        // la clé brute au comptable, dans le document.
        $etat = match ($this->etat) {
            'indisponible' => __('carte_pwa.commun.etat_indisponible'),
            'lie' => __('carte_pwa.commun.etat_lie'),
            'sans_lien' => __('carte_pwa.commun.etat_sans_lien'),
            'rupture_stock' => __('carte_pwa.commun.etat_rupture'),
            'provisoire' => __('carte_pwa.commun.etat_provisoire'),
            default => null,
        };

        if ($etat !== null) {
            $morceaux[] = __('carte_pwa.filtre_etat', ['etat' => $etat]);
        }

        return $morceaux === []
            ? __('carte_pwa.filtre_aucun')
            : implode(' · ', $morceaux);
    }

    /**
     * Les entêtes du document exporté — celles du maître (`carte-module.js`
     * l.397), au mot près.
     *
     * @return list<string>
     */
    protected function entetesExport(): array
    {
        return [
            __('carte_pwa.commun.col_article'),
            __('carte_pwa.commun.col_categorie'),
            __('carte_pwa.commun.col_prix'),
            __('carte_pwa.commun.export_col_disponible'),
            __('carte_pwa.commun.col_article_stock'),
            __('carte_pwa.commun.col_stock_vendable'),
            __('carte_pwa.commun.export_col_reserve'),
        ];
    }

    /**
     * Le tableau exporté, construit depuis les lignes DÉJÀ FILTRÉES.
     *
     * PA-119 : l'export porte sur ce qui est affiché. Le recalculer sans le
     * filtre rendrait au comptable un document plus large que celui qu'il
     * croit avoir vérifié.
     *
     * @param  list<array<string, mixed>>  $lignes
     * @return list<list<string>>
     */
    protected function matriceExport(array $lignes): array
    {
        $tiret = MontantFcfa::TIRET;

        return array_map(function (array $ligne) use ($tiret): array {
            $stock = $ligne['stock'];

            return [
                (string) $ligne['nom'],
                (string) $ligne['categorie'],
                (string) $ligne['prix'],
                $ligne['disponible'] === true
                    ? __('carte_pwa.commun.export_oui')
                    : __('carte_pwa.commun.export_non'),
                $ligne['article_stock'] instanceof Article
                    ? (string) $ligne['article_stock']->libelle
                    : $tiret,
                is_array($stock) && ($stock['non_consulte'] ?? true) === false
                    ? (string) $stock['unites_vendables']
                    : $tiret,
                // maitre — `carte-module.js` l.413-414 : la colonne
                // « Reserve » porte les DEUX mentions, separees par un point
                // median, et la marque de prix vient en premier.
                implode(' · ', array_filter([
                    $ligne['prix_provisoire'] === true
                        ? __('carte_pwa.commun.export_prix_provisoire')
                        : '',
                    $ligne['decremente'] === false
                        ? __('carte_pwa.commun.export_sans_lien')
                        : '',
                ])),
            ];
        }, $lignes);
    }

    /**
     * Groupe les articles tarifés par catégorie, dans l'ordre du registre.
     *
     * @param  list<CarteBoisson|Plat>  $articles
     * @return list<array{cle: string, libelle: string, articles: list<CarteBoisson|Plat>}>
     */
    protected function grouperParCategorie(array $articles): array
    {
        $groupes = [];

        foreach ($this->categoriesDeLaCarte() as $cle => $libelle) {
            $groupes[$cle] = ['cle' => $cle, 'libelle' => $libelle, 'articles' => []];
        }

        foreach ($articles as $article) {
            $cle = (string) ($article->categorie ?? '');

            if (! array_key_exists($cle, $groupes)) {
                $groupes[$cle] = ['cle' => $cle, 'libelle' => $cle, 'articles' => []];
            }

            $groupes[$cle]['articles'][] = $article;
        }

        // Une catégorie sans article tarifé n'est pas imprimée : un intitulé
        // seul sur la fiche remise au client laisserait croire à un oubli.
        return array_values(array_filter(
            $groupes,
            static fn (array $groupe): bool => $groupe['articles'] !== [],
        ));
    }

    // =====================================================================
    // ONGLET « Ventes du rayon » — AJOUT (Product Owner, 03/09/2026)
    // =====================================================================

    /**
     * Un filtre de l'onglet Ventes qui change remet la pagination à 1.
     *
     * Sans cela, quelqu'un qui restreint sa plage de dates depuis la page 4
     * verrait une liste vide sous un filtre qui retient des lignes — le même
     * défaut que `Facturation::updated()` ferme sur son registre.
     *
     * ⚠ Point d'entrée du CADRE Livewire, jamais un bouton : il n'écrit que
     * l'état d'affichage. La garde d'écriture exempte le préfixe `updated`
     * pour cette raison, et il reste inscrit dans `PwaActionsReluesTest`.
     */
    public function updated(string $propriete, mixed $valeur): void
    {
        if (in_array($propriete, ['rechercheVentes', 'statutVente', 'debutVentes', 'finVentes'], true)) {
            $this->pageCourante = 1;
        }
    }

    /**
     * Une date de filtre RÉELLEMENT exploitable, ou `null`.
     *
     * `#[Url]` accepte n'importe quelle chaîne depuis la barre d'adresse, et
     * `whereDate()` la passe telle quelle à MySQL : `?du=hier` produirait une
     * comparaison sur une date nulle, donc un tableau vide qui ressemblerait
     * à « aucune vente ce jour-là ». Une borne illisible est IGNORÉE, jamais
     * appliquée à moitié.
     */
    private function dateDeFiltre(string $saisie): ?string
    {
        return LignesVenteDuRayonService::dateLisible($saisie);
    }

    /**
     * Les LIGNES de vente du rayon de cet écran, filtres appliqués.
     *
     * ⚠ LE FILTRE DE MODULE EST LA SUBSTANCE DE CETTE MÉTHODE. Une vente est
     * multi-modules par nature — le même ticket porte une bière (M5) et un
     * poulet (M4) —, et c'est la LIGNE qui porte son module, jamais la vente
     * (`Vente`, docblock : « le module est estampillé sur la LIGNE, jamais
     * déduit après coup de sa catégorie »). Filtrer sur la vente afficherait
     * au bar les plats du même ticket.
     *
     * Le tri passe par une JOINTURE plutôt que par une sous-requête : c'est
     * `ventes.created_at` qui ordonne le journal, et `lignes_vente` n'a
     * aucune colonne de date métier.
     *
     * @return Builder<LigneVente>
     */
    protected function requeteDesVentes(): Builder
    {
        // L'auteur unique est le service de domaine (PA-197) : l'écran, son
        // export et la route d'API `GET /bar/ventes` lisent la même requête.
        return app(LignesVenteDuRayonService::class)->requete(
            static::MODULE,
            $this->rechercheVentes,
            $this->statutVente,
            $this->debutVentes,
            $this->finVentes,
        );
    }

    /**
     * Le panneau « Ventes » entier — lignes de la page, compteurs du filtre.
     *
     * ## Le stock affiché est celui d'AUJOURD'HUI, et la colonne le dit
     *
     * Il vient de `lignesDeLaCarte()`, le SEUL auteur du stock vendable de cet
     * écran (point de vente, unités vendables, trois états). Aucune requête
     * n'est réécrite ici : une seconde lecture du stock aurait fini par
     * diverger de la colonne voisine de l'onglet Carte.
     *
     * ⚠ Ce n'est PAS le stock au moment de la vente : `lignes_vente` n'en
     * garde aucune trace, et `mouvements_stock` ne permet pas de le
     * reconstituer par article de carte. L'entête dit donc « Stock actuel ».
     * Rendre le stock du jour sous un entête « Stock » laisserait croire à un
     * relevé historique — un chiffre faux mais plausible, exactement ce que
     * PA-59/60/61 nomment.
     *
     * Une ligne dont l'article n'est PLUS à la carte rend « — » : elle n'a pas
     * un stock de zéro, elle n'a plus d'article où le lire. « 0 » se lirait
     * comme une rupture, c'est-à-dire comme un fait (PA-129).
     *
     * @param  list<array<string, mixed>>  $lignesDeCarte
     * @return array<string, mixed>
     */
    protected function socleDesVentes(array $lignesDeCarte): array
    {
        $stockParArticle = $this->stockParArticleDeCarte($lignesDeCarte);
        $requete = $this->requeteDesVentes();

        $page = (clone $requete)
            ->with(['vente', 'vente.utilisateur'])
            ->paginate(self::PAR_PAGE, ['*'], 'page', max(1, $this->pageCourante));

        $totaux = $this->totauxDesVentes($requete);

        $rendues = [];
        $totalPage = '0.00';
        $annuleesPage = 0;

        foreach ($page->getCollection() as $ligne) {
            $rendue = $this->venteRendue($ligne, $stockParArticle);

            if ($rendue['annulee'] === true) {
                $annuleesPage++;
            } else {
                $totalPage = bcadd($totalPage, (string) $ligne->montant, self::PRECISION_MONTANT);
            }

            $rendues[] = $rendue;
        }

        return [
            'page' => $page,
            'lignes' => $rendues,
            'total_page' => MontantFcfa::format($totalPage),
            'annulees_page' => $annuleesPage,
            'total_filtre' => MontantFcfa::format($totaux['total']),
            'annulees_filtre' => $totaux['annulees'],
            'lignes_filtre' => $totaux['lignes'],
            'statuts' => Vente::STATUTS,
        ];
    }

    /**
     * Le stock du jour, indexé par le CODE que porte la ligne de vente.
     *
     * `lignes_vente.code` est l'identifiant de l'article de carte figé à la
     * vente : c'est par lui, et par lui seul, qu'une ligne de journal retrouve
     * son article — le libellé est figé lui aussi et un article renommé ne se
     * rattacherait plus.
     *
     * @param  list<array<string, mixed>>  $lignesDeCarte
     * @return array<string, mixed>
     */
    private function stockParArticleDeCarte(array $lignesDeCarte): array
    {
        $stockParArticle = [];

        foreach ($lignesDeCarte as $ligne) {
            $stockParArticle[(string) $ligne['id']] = $ligne['stock'];
        }

        return $stockParArticle;
    }

    /**
     * Les compteurs du JEU FILTRÉ ENTIER — L'AUTEUR UNIQUE du total du rayon.
     *
     * Ils portent sur le jeu filtré entier, jamais sur la page : un total qui
     * changerait en tournant les pages dirait deux vérités sur le même filtre
     * (même arbitrage que `Facturation`). Le total N'ADDITIONNE QUE LES LIGNES
     * VALIDÉES : une vente annulée reste au registre (RG-02) mais son montant
     * n'est pas de l'argent — l'additionner gonflerait le chiffre du rayon.
     *
     * ⚠ MÉTHODE À PART, et c'est la substance du lot du 03/09/2026 : l'écran
     * ET le document exporté l'appellent tous les deux. Une seconde somme
     * écrite dans le document — un `sum('montant')` en SQL, par exemple —
     * serait plus courte et dupliquerait le prédicat « hors annulations » : le
     * jour où l'un changerait, le papier remis au client et l'écran depuis
     * lequel il a été édité afficheraient deux chiffres différents, et c'est
     * le papier que personne ne pourrait plus rattraper.
     *
     * @param  Builder<LigneVente>  $requete
     * @return array{total: string, annulees: int, lignes: int}
     */
    protected function totauxDesVentes(Builder $requete): array
    {
        return app(LignesVenteDuRayonService::class)->totaux($requete);
    }

    /**
     * UNE ligne de vente rendue — l'écran et le document lisent la même.
     *
     * Extraite le 03/09/2026 pour l'export : recopier ce mappage dans le
     * document aurait produit deux rendus d'une même ligne (Article 10), et
     * c'est exactement ainsi que l'entête « Stock actuel » aurait fini par
     * dire une chose à l'écran et une autre sur le papier.
     *
     * @param  array<string, mixed>  $stockParArticle
     * @return array<string, mixed>
     */
    private function venteRendue(LigneVente $ligne, array $stockParArticle): array
    {
        $vente = $ligne->vente;
        $auteur = $vente?->utilisateur;
        $annulee = $vente !== null && $vente->estAnnulee();
        $code = (string) ($ligne->code ?? '');

        return [
            'id' => (string) $ligne->id,
            'nom' => (string) $ligne->nom,
            'numero' => (string) ($vente->numero ?? MontantFcfa::TIRET),
            'quand' => $vente?->created_at?->format('d/m/Y H:i') ?? MontantFcfa::TIRET,
            'prix_unitaire' => MontantFcfa::format((string) $ligne->prix_unitaire),
            'quantite' => (int) $ligne->quantite,
            'montant' => MontantFcfa::format((string) $ligne->montant),
            'annulee' => $annulee,
            'motif_annulation' => $annulee ? (string) ($vente->motif_annulation ?? '') : '',
            // RG-15 — l'imputation est une vraie clé étrangère. Une vente
            // sans utilisateur rend le tiret : inventer « système » lui
            // attribuerait un auteur qu'aucune colonne ne porte.
            //
            // ⚠ `instanceof` et non `?->login` : `ventes.utilisateur_id`
            // est NULLABLE au schéma (les ventes antérieures à la reprise
            // en UUID n'en portent aucun), mais la relation est typée
            // non-nullable et l'analyse statique refuse le nullsafe. Le
            // `instanceof` dit les deux vérités à la fois — même idiome,
            // et même raison, que `HistoriqueVentes::auteur()`.
            'utilisateur' => $auteur instanceof User ? $auteur->login : MontantFcfa::TIRET,
            // Trois états du stock, plus un quatrième propre à cet onglet :
            // l'article n'est plus à la carte, donc son stock ne se lit
            // nulle part.
            'article_a_la_carte' => $code !== '' && array_key_exists($code, $stockParArticle),
            'stock' => $stockParArticle[$code] ?? null,
        ];
    }

    // ---- L'export de l'onglet Ventes (Product Owner, 03/09/2026) ---------

    /**
     * Le libellé du RAYON tel qu'il titre l'onglet — « Ventes du Bar ».
     *
     * Crochet plutôt qu'un `match` sur `static::MODULE` dans le trait : un
     * registre caché ici serait un second endroit où le nom des deux écrans
     * s'écrit, et il divergerait du libellé d'onglet au premier ajustement.
     * Chaque écran rend SA clé de langue, celle-là même que sa vue passe en
     * `$page['onglet_ventes']`.
     */
    abstract protected function libelleDesVentes(): string;

    /** Le préfixe du fichier téléchargé — `ventes_du_bar`, sans horodatage. */
    abstract protected function nomDeFichierDesVentes(): string;

    /**
     * Le document des VENTES DU RAYON — le jeu FILTRÉ entier, jamais la page.
     *
     * ## Il porte le filtre courant, et il le DIT (PA-119)
     *
     * Les lignes viennent de `requeteDesVentes()`, la MÊME requête que le
     * tableau : la recherche, le statut et les deux bornes de dates s'y
     * appliquent une seule fois, à un seul endroit. Réécrire le filtrage ici
     * aurait donné deux lectures, donc deux vérités — et le document, lui, ne
     * peut plus être corrigé une fois remis.
     *
     * ## Le jeu FILTRÉ, pas la page affichée
     *
     * Le compteur de tête (« N ligne(s) · Total validé : X ») porte déjà sur
     * le jeu filtré entier : c'est LUI que l'utilisateur lit avant d'exporter.
     * Rendre les dix lignes de la page courante produirait un document plus
     * étroit que le chiffre affiché juste au-dessus du bouton.
     *
     * ## Une liste vide se REFUSE
     *
     * Et le refus est prononcé AVANT toute lecture de la carte : produire un
     * document d'en-tête sans une ligne laisserait croire que le rayon n'a
     * rien vendu, alors que c'est le filtre qui ne retient rien.
     *
     * @return \Symfony\Component\HttpFoundation\Response|null
     */
    private function exportDesVentes(string $format)
    {
        $requete = $this->requeteDesVentes();
        $totaux = $this->totauxDesVentes($requete);

        if ($totaux['lignes'] === 0) {
            $this->addError('formatExport', __('carte_pwa.export_ventes_vide'));

            return null;
        }

        $this->etatFormulaire = null;

        $titre = $this->libelleDesVentes();
        $filtre = $this->descriptionDuFiltreVentes();
        $entetes = $this->entetesExportVentes();
        $matrice = $this->matriceExportVentes(
            $this->lignesDeVenteDuDocument($this->lignesDeLaCarte()),
        );

        // Le résumé du document est la PHRASE DE L'ÉCRAN, clé de langue
        // comprise, alimentée par les compteurs de `totauxDesVentes()`.
        $resume = __('carte_pwa.commun.ventes_compteur', [
            'nombre' => $totaux['lignes'],
            'total' => MontantFcfa::format($totaux['total']),
        ]);

        if ($totaux['annulees'] > 0) {
            $resume .= ' — '.__('carte_pwa.commun.ventes_compteur_annulees', [
                'nombre' => $totaux['annulees'],
            ]);
        }

        $fichier = $this->nomDeFichierDesVentes().'_'.now()->format('Ymd_His');

        if ($format === 'excel') {
            return Excel::download(
                new VentesDuRayonExport($entetes, $matrice, $filtre, $resume, $titre),
                $fichier.'.xlsx',
            );
        }

        $auteur = auth()->user();

        $pdf = Pdf::loadView('pdf.carte-ventes', [
            // L'identité de l'établissement vient de `ReportHeaderService`,
            // jamais recopiée dans le gabarit (RG-19,
            // `RESPECT_TABLEAU_RAPPORT.md` §4, non-conformité n° 1).
            'entete' => app(ReportHeaderService::class)->genererEnTete(
                $titre,
                $this->periodeDesVentes(),
                $auteur instanceof User ? $auteur : null,
            ),
            'titre' => $titre,
            'periode' => $this->periodeDesVentes(),
            'filtre' => $filtre,
            'resume' => $resume,
            'entetes' => $entetes,
            'lignes' => $matrice,
            // Le stock imprimé est celui du jour de l'ÉDITION : le document le
            // dit avec les mots mêmes de l'écran, sinon un lecteur du fichier
            // la semaine suivante y verrait un relevé du jour de la vente.
            'aideStock' => __('carte_pwa.commun.ventes_stock_aide'),
            'quand' => now()->format('d/m/Y à H:i'),
            // PAYSAGE, contrairement à l'état de la carte : neuf colonnes dont
            // un horodatage, un numéro de ticket et deux libellés. En portrait,
            // les noms d'article se replient sur trois lignes et le tableau
            // devient illisible sur le papier remis.
        ])->setPaper('a4', 'landscape');

        return response()->streamDownload(
            static fn () => print ($pdf->output()),
            $fichier.'.pdf',
        );
    }

    /**
     * Les lignes de vente du DOCUMENT — rendues par `venteRendue()`, comme
     * celles de l'écran, à partir de la MÊME requête filtrée.
     *
     * @param  list<array<string, mixed>>  $lignesDeCarte
     * @return list<array<string, mixed>>
     */
    private function lignesDeVenteDuDocument(array $lignesDeCarte): array
    {
        $stockParArticle = $this->stockParArticleDeCarte($lignesDeCarte);
        $rendues = [];

        foreach ($this->requeteDesVentes()->with(['vente', 'vente.utilisateur'])->get() as $ligne) {
            $rendues[] = $this->venteRendue($ligne, $stockParArticle);
        }

        return $rendues;
    }

    /**
     * Les entêtes du document de ventes — CELLES DU TABLEAU, clés comprises.
     *
     * Les recopier en clair ferait deux registres de colonnes : « Stock
     * actuel » redeviendrait « Stock » sur le papier, et l'avertissement que
     * ce mot porte (le stock n'est pas celui du jour de la vente) disparaîtrait
     * du seul document qui survit à l'écran.
     *
     * @return list<string>
     */
    protected function entetesExportVentes(): array
    {
        return [
            __('carte_pwa.commun.ventes_col_date'),
            __('carte_pwa.commun.ventes_col_ticket'),
            __('carte_pwa.commun.ventes_col_article'),
            __('carte_pwa.commun.ventes_col_stock'),
            __('carte_pwa.commun.ventes_col_prix'),
            __('carte_pwa.commun.ventes_col_quantite'),
            __('carte_pwa.commun.ventes_col_montant'),
            __('carte_pwa.commun.ventes_col_statut'),
            __('carte_pwa.commun.ventes_col_utilisateur'),
        ];
    }

    /**
     * Le tableau exporté, construit depuis les lignes DÉJÀ rendues.
     *
     * Les montants sont ceux de `MontantFcfa::format()`, jamais `number_format`
     * — un seul auteur pour l'écran, le PDF et le tableur (le séparateur de
     * milliers est U+00A0 depuis le 02/09/2026 : U+202F n'a aucun glyphe dans
     * les polices PDF et sortait « ? » sur le papier remis).
     *
     * @param  list<array<string, mixed>>  $lignes
     * @return list<list<string>>
     */
    protected function matriceExportVentes(array $lignes): array
    {
        return array_map(static function (array $ligne): array {
            $stock = $ligne['stock'];

            return [
                (string) $ligne['quand'],
                (string) $ligne['numero'],
                (string) $ligne['nom'],
                // Les quatre états de la colonne, réduits au chiffre ou au
                // tiret : un article hors carte, un solde non consulté et
                // une absence de lien de stock ne sont pas « 0 », qui se
                // lirait comme une rupture, c'est-à-dire comme un fait
                // (PA-129).
                $ligne['article_a_la_carte'] === true
                    && is_array($stock)
                    && ($stock['non_consulte'] ?? true) === false
                        ? (string) $stock['unites_vendables']
                        : MontantFcfa::TIRET,
                (string) $ligne['prix_unitaire'],
                (string) $ligne['quantite'],
                (string) $ligne['montant'],
                $ligne['annulee'] === true
                    ? __('carte_pwa.commun.ventes_statut_annulee')
                    : __('carte_pwa.commun.ventes_statut_validee'),
                (string) $ligne['utilisateur'],
            ];
        }, $lignes);
    }

    /**
     * Le filtre RÉELLEMENT appliqué au tableau des ventes, en clair (PA-119).
     *
     * ⚠ La période vient TOUJOURS en tête, et elle est écrite même sans borne
     * (« Toutes les dates ») : un journal de ventes sans période affichée
     * laisserait supposer le mois courant, et c'est le premier chiffre qu'un
     * comptable rapproche.
     */
    protected function descriptionDuFiltreVentes(): string
    {
        $morceaux = [__('carte_pwa.filtre_periode', ['periode' => $this->periodeDesVentes()])];

        // Registre FERMÉ, écrit ici plutôt que construit par concaténation :
        // `'ventes_statut_'.$this->statutVente` rendrait la clé brute au
        // comptable, DANS le document, le jour où `Vente::STATUTS` s'élargit.
        $statut = match ($this->statutVente) {
            'validee' => __('carte_pwa.commun.ventes_statut_validee'),
            'annulee' => __('carte_pwa.commun.ventes_statut_annulee'),
            default => null,
        };

        if ($statut !== null) {
            $morceaux[] = __('carte_pwa.filtre_statut', ['statut' => $statut]);
        }

        if (trim($this->rechercheVentes) !== '') {
            $morceaux[] = __('carte_pwa.filtre_terme', ['terme' => trim($this->rechercheVentes)]);
        }

        return implode(' · ', $morceaux);
    }

    /**
     * La période retenue, en clair — les deux bornes INCLUSES.
     *
     * Elle est dérivée de `dateDeFiltre()`, la même méthode que la requête :
     * une borne illisible (`?du=hier`) est ignorée par les deux, et le
     * document annonce alors la période qu'il porte réellement. La décrire
     * depuis la saisie brute écrirait « Du hier au … » sur un document dont
     * les lignes n'ont, elles, subi aucune borne.
     */
    protected function periodeDesVentes(): string
    {
        $debut = $this->dateDeFiltre($this->debutVentes);
        $fin = $this->dateDeFiltre($this->finVentes);

        $lisible = static fn (string $jour): string => implode('/', array_reverse(explode('-', $jour)));

        return match (true) {
            $debut !== null && $fin !== null => __('carte_pwa.periode_du_au', [
                'debut' => $lisible($debut),
                'fin' => $lisible($fin),
            ]),
            $debut !== null => __('carte_pwa.periode_depuis', ['debut' => $lisible($debut)]),
            $fin !== null => __('carte_pwa.periode_jusqu_au', ['fin' => $lisible($fin)]),
            default => __('carte_pwa.periode_toutes'),
        };
    }

    /**
     * Le socle que les deux vues attendent — construit une seule fois.
     *
     * @return array<string, mixed>
     */
    protected function socleDeLaCarte(): array
    {
        $lignes = $this->lignesDeLaCarte();
        $filtrees = $this->lignesFiltrees($lignes);

        $articleCible = $this->articleCibleId === null
            ? null
            : $this->trouverArticleDeCarte($this->articleCibleId);

        return [
            'onglet' => $this->ongletValide(),
            'lignes' => $filtrees,
            'indicateurs' => $this->indicateurs($lignes),
            'couverture' => $this->couverture($lignes),
            'categories' => $this->categoriesDeLaCarte(),
            'motifs' => IndisponibiliteCarte::MOTIFS,
            'motifSansLien' => $this->motifSansLien(),
            'articlesDeStock' => $this->articlesDeStock(),
            'apercuDuLien' => $this->apercuDuLien(),
            'articleCible' => $articleCible,
            'historiquePrix' => $this->etatFormulaire === 'historiquePrix' && $articleCible !== null
                ? $this->historiquePrixDe($articleCible)
                : collect(),
            'stocksNonConsultes' => count($this->stocksNonConsultes),
            'pointDeStockageAbsent' => $this->pointDeStockageAbsent,
            'descriptionDuFiltre' => $this->descriptionDuFiltre(),
            /*
             * Le panneau « Ventes » n'est construit QUE lorsqu'il est ouvert,
             * contrairement aux deux autres.
             *
             * Ce n'est pas une optimisation : les colonnes des onglets Carte
             * et Couverture sont CELLES DU MAÎTRE, et la garde G5
             * (`ColonnesDesTableauxPwaTest`) exige de les retrouver dans le
             * HTML du premier GET — d'où les deux panneaux rendus, l'inactif
             * caché. Celles de l'onglet Ventes n'existent dans aucun tableau
             * du maître : les rendre au premier GET les ferait compter comme
             * des colonnes INVENTÉES par la seconde moitié de la même garde.
             * Les deux lectures sont justes ; l'écart entre elles est ce
             * paragraphe. Effet de bord bienvenu : la requête de ventes ne
             * tourne pas quand personne ne regarde ce tableau.
             */
            'ventes' => $this->ongletValide() === 'ventes'
                ? $this->socleDesVentes($lignes)
                : null,
        ];
    }

    /**
     * L'historique des prix d'UN article, du plus récent au plus ancien.
     *
     * `source` est dérivée du TYPE de l'article plutôt que d'un second crochet
     * abstrait — `CarteBoissonObserver` et `PlatObserver` écrivent déjà l'un
     * des deux codes de `HistoriquePrixCarte::SOURCE_*`, une troisième source
     * de vérité aurait fini par diverger (Article 10).
     *
     * @return Collection<int, HistoriquePrixCarte>
     */
    private function historiquePrixDe(CarteBoisson|Plat $article): Collection
    {
        return HistoriquePrixCarte::query()
            ->where('source', $article instanceof CarteBoisson
                ? HistoriquePrixCarte::SOURCE_BOISSON
                : HistoriquePrixCarte::SOURCE_PLAT)
            ->where('source_id', $article->getKey())
            ->with('utilisateurCreation')
            ->orderByDesc('created_at')
            ->get();
    }
}

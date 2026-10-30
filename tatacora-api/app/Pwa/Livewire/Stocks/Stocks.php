<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Stocks;

use App\Domain\Stocks\Exceptions\RuptureStockException;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\ConsultationStockService;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Stocks\Services\ReferentielArticleService;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Domain\Stocks\Services\ValorisationStockService;
use App\Exports\StocksExport;
use App\Models\User;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\PageMetier;
use App\Pwa\Support\AutoriseArchivage;
use App\Pwa\Support\MontantFcfa;
use App\Shared\ImportExport\Data\ReferentielsImport;
use App\Shared\ImportExport\Services\TableurService;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rule;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Livewire\WithFileUploads;
use Livewire\WithPagination;
use Maatwebsite\Excel\Facades\Excel;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Écran « Gestion des Stocks » (M6) — maître : `prototype_v2/pages/m6-stocks.html`.
 *
 * ## Ce que cet écran a remplacé
 *
 * `resources/views/pwa/stocks/stocks.blade.php` était une COPIE de
 * `inventaires.blade.php` : `diff` ne rendait que trois blocs de CSS
 * d'impression. La vue appelait `lancerInventaire`, `cloturerEtRegulariser`,
 * `definirPeriode`, `definirPeriodicite`, `imprimerRapportInventairePdf` et
 * `sauvegarderComptage` — six méthodes qui n'ont jamais existé sur ce
 * composant. `GET /pwa/stocks` répondait **500**, et les sept actions
 * déclarées ici n'étaient câblées nulle part. Un module entier hors service,
 * sur un dépôt dont la suite était verte : aucun test n'avait jamais demandé
 * cette URL (garde posée depuis — `ChargementDesEcransPwaTest`).
 *
 * ## Le stock ne se saisit JAMAIS, il se calcule
 *
 * `articles` ne porte aucune colonne de stock, et il ne faut jamais en
 * ajouter : `ConsultationStockService` agrège `mouvements_stock` en une seule
 * requête. Toute écriture de stock passe par `MouvementStockService`, unique
 * point d'entrée — une insertion directe contournerait le verrou pessimiste de
 * RG-06 et la vérification de seuil de RG-07 sans lever d'erreur. Le coût
 * moyen pondéré, lui, est recalculé par `ValorisationStockService` : le
 * formulaire ne l'écrit pas, il fournit le coût d'achat de l'entrée qui le
 * fait bouger.
 *
 * ## Les trois colonnes du maître sont ALIMENTÉES depuis le 02/09/2026
 *
 * ⚠ Cet écran a longtemps rendu « — » sur « Point », « Suivi » et « Valeur
 * d'achat », avec trois motifs affichés disant que le schéma ne les portait
 * pas. C'était exact à l'écriture ; PA-161 (a) a tranché et les trois colonnes
 * existent. Les motifs sont donc RETIRÉS, pas laissés à vieillir : un motif de
 * refus qui a cessé d'être vrai transforme une décision en oubli (PA-144).
 *
 * Trois précautions demeurent, et elles ne sont pas des refus :
 *
 * - `point_stockage_id` est un RATTACHEMENT, jamais la portée du stock. Le
 *   filtre « Tous les points » continue de porter sur les mouvements, pas sur
 *   cette colonne — « 10 au bar et 0 au magasin » n'est pas « 0 au bar et 10
 *   au magasin ».
 * - un article sans point ni prix d'achat rend « — » AVEC sa raison
 *   (« jamais réceptionné »), jamais un zéro plausible.
 * - `prix_achat` ne se saisit pas en modification : il est posé par l'entrée
 *   de stock, seul geste qui l'établit. Y offrir un champ laisserait croire
 *   qu'on peut réécrire un prix d'achat après coup.
 *
 * ## Un article journalier REFUSE le mouvement de stock
 *
 * Le maître le fait à l'ouverture de la fenêtre (`m6-stocks.html` l.380-383,
 * « son stock n'est pas suivi »), et le refus est porté ICI, à l'écran, et non
 * dans `MouvementStockService` : la déduction automatique RG-05 passe par ce
 * même service, et un refus au niveau du domaine ferait échouer une vente au
 * comptoir sur un article de carte mal rattaché. Le geste manuel se refuse ;
 * la vente, elle, doit toujours pouvoir s'encaisser.
 *
 * @see EF-M6-01 Référentiel articles multi-catégories
 * @see EF-M6-03 Valorisation au coût moyen pondéré
 * @see RG-06 Blocage au-delà du disponible, avec échappatoire contrôlée
 * @see RG-07 Alerte de seuil
 * @see RG-19 Export PDF/CSV
 * @see docs/DIRECTIVE_CONFORMITE_100.md Articles 3.3, 4.6, 7, 8
 */
#[Title('Gestion des Stocks — LogiReStock — TATACORA AFRIQUE')]
class Stocks extends PageMetier
{
    use AutoriseArchivage;
    use FormulaireModal;
    use WithFileUploads;
    use WithPagination;

    /** Le module RBAC de l'écran — jamais un littéral dans les appels. */
    public const MODULE = 'M6';

    public const PAR_PAGE = 25;

    /** Registre FERMÉ des types qu'un mouvement saisi à la main peut porter. */
    public const TYPES_MOUVEMENT = ['entree', 'sortie', 'perte'];

    /** maître — `m6-stocks.html` l.117. */
    public const CATEGORIES = ['Denrées', 'Boissons', 'Fournitures', 'Pièces véhicules'];

    /** maître — `m6-stocks.html` l.119. */
    public const UNITES = ['kg', 'L', 'unité', 'sac', 'carton', 'casier', 'pack', 'bidon', 'bouteille'];

    /**
     * L'en-tête du modèle d'import, dans l'ordre.
     *
     * ⚠ C'est EXACTEMENT `COLONNES_IMPORT` du maître (l.477). `suivi` en avait
     * été retiré, faute de colonne au schéma ; PA-161 (a) l'a créée, et la
     * note qui justifiait ce retrait a cessé d'être vraie (PA-144). Une
     * colonne d'import absente de ce modèle est une colonne que l'utilisateur
     * remplit pour rien.
     */
    public const COLONNES_IMPORT = [
        'nom', 'categorie', 'unite_mesure', 'prix_achat',
        'seuil_alerte', 'point_stockage', 'suivi', 'stock_initial',
    ];

    #[Url(as: 'q')]
    public string $recherche = '';

    #[Url(as: 'categorie')]
    public string $categorie = '';

    #[Url(as: 'point')]
    public string $point = '';

    #[Url(as: 'etat')]
    public string $etat = '';

    /** maître — le filtre « Tous les suivis » (`m6-stocks.html` l.52-56). */
    #[Url(as: 'suivi')]
    public string $suivi = '';

    // --- Formulaire « Nouvel article » / « Modifier l'article » -------------

    public ?string $articleId = null;

    public string $libelle = '';

    public string $categorieSaisie = '';

    public string $uniteSaisie = '';

    public string $seuilAlerte = '';

    public string $pointOuverture = '';

    /** maître — « Mode de suivi » (l.312-315). Registre fermé `Article::SUIVIS`. */
    public string $suiviSaisi = 'permanent';

    public string $valeurAchat = '';

    public string $stockOuverture = '';

    /*
    |---------------------------------------------------------------------------
    | ENTRÉE DE STOCK DEPUIS LA FICHE ARTICLE — directive PO du 06/09/2026
    |---------------------------------------------------------------------------
    |
    | « Niveau stock, permettre de modifier le stock dans le modal Modifier
    | l'article. » Jusqu'ici, `enregistrerArticle()` posait le stock d'ouverture
    | à la CRÉATION seulement : en édition il rendait la main AVANT le bloc de
    | mouvement, et les deux champs disparaissaient de la modale. Corriger un
    | stock exigeait donc de fermer la fiche et de rouvrir « Mouvement ».
    |
    | ⚠ CE N'EST PAS UN CHAMP « stock ». Le stock reste l'agrégation des
    | mouvements (03_DATABASE_ENGINEERING.md §7) et le récapitulatif de la
    | modale le rend en LECTURE SEULE, comme avant. Ce qui se saisit ici est une
    | ENTRÉE — une quantité qui s'ajoute, avec son point et son coût — écrite
    | par `MouvementStockService::entree()`, exactement comme le stock
    | d'ouverture. Un champ qui écraserait le stock serait la deuxième des sept
    | règles sans exception du projet, prise à revers.
    */

    /** La quantité à faire ENTRER — vide : la fiche est enregistrée sans mouvement. */
    public string $entreeQuantite = '';

    /**
     * Le point qui reçoit la marchandise.
     *
     * Distinct de `pointOuverture`, qui est le RATTACHEMENT principal de
     * l'article : une livraison peut atterrir ailleurs, et confondre les deux
     * créditerait un point que personne n'a choisi (PA-161 (a) — le
     * rattachement n'est jamais la portée du stock).
     */
    public string $entreePoint = '';

    /** Le coût unitaire de CETTE entrée — il traverse la valorisation, jamais le CMP en direct. */
    public string $entreeCout = '';

    // --- Formulaire « Mouvement de stock » ---------------------------------

    public ?string $mvtArticleId = null;

    public string $mvtType = 'entree';

    public string $mvtPoint = '';

    public string $mvtQuantite = '';

    public string $mvtCout = '';

    public string $mvtMotif = '';

    /**
     * Le message de RG-06 en attente de confirmation — `null` : aucune rupture.
     *
     * Il porte le refus du domaine tel quel : c'est lui qui chiffre le
     * disponible et le demandé, et le reformuler ici ferait diverger deux
     * phrases pour un même refus.
     */
    public ?string $mvtRupture = null;

    /**
     * Le refus de mouvement sur un article journalier — `null` : aucun refus.
     *
     * Il n'est PAS un état de formulaire : aucune fenêtre ne s'ouvre, le
     * maître se contente d'un bandeau (`Toast.alerte`, l.381). Le porter comme
     * une modale forcerait un clic pour fermer ce qui n'a jamais été ouvert.
     */
    public ?string $mvtRefusJournalier = null;

    // --- Formulaire « Importer des articles » ------------------------------

    /** @var \Livewire\Features\SupportFileUploads\TemporaryUploadedFile|null */
    public $fichierImport = null;

    /** @var list<string> */
    public array $lignesRefusees = [];

    // --- Modale d'export partagée ------------------------------------------

    public string $formatExport = 'pdf';

    // --- Archivage du référentiel (directive PO du 03/09/2026) ------------
    //
    // « Supprimer = archiver » : le geste passe `articles.actif` à `false` par
    // `ReferentielArticleService::archiver()` — jamais un `delete()`
    // (`mouvements_stock.article_id` est `restrictOnDelete`, et effacer
    // l'article rendrait le journal de stock illisible). Cet écran n'avait
    // AUCUNE case à cocher : la sélection est ajoutée avec le geste, et elle
    // ne sert qu'à lui.

    /** @var list<string> Les identifiants cochés dans le tableau. */
    public array $selection = [];

    /** La case « tout sélectionner » de l'entête. */
    public bool $toutSelectionne = false;

    /** @var list<string> Les articles retenus par la modale de confirmation. */
    public array $articlesAArchiver = [];

    /** @var list<string> Les motifs de blocage affichés dans la modale. */
    public array $verrousArchivage = [];

    /** Vrai quand TOUT le lot est engagé : le bouton de confirmation disparaît. */
    public bool $archivageBloque = false;

    /** Nombre d'éléments qui resteront (état PARTIEL du maître). */
    public int $conservesArchivage = 0;

    /** Le nom de l'élément visé quand le lot n'en compte qu'un. */
    public string $libelleArchivage = '';

    /**
     * Le registre FERMÉ des formulaires de l'écran — motif `FormulaireModal`.
     *
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'archivage' => [
                'articlesAArchiver', 'verrousArchivage', 'archivageBloque',
                'conservesArchivage', 'libelleArchivage',
            ],
            'article' => [
                'articleId', 'libelle', 'categorieSaisie', 'uniteSaisie',
                'seuilAlerte', 'pointOuverture', 'suiviSaisi', 'valeurAchat',
                'stockOuverture',
                // L'entrée de stock depuis la fiche (PO 06/09/2026) : elle est
                // remise à zéro comme le reste, sans quoi rouvrir une autre
                // fiche reproposerait une quantité déjà saisie — qu'on
                // enregistrerait sans la relire.
                'entreeQuantite', 'entreePoint', 'entreeCout',
            ],
            'mouvement' => [
                'mvtArticleId', 'mvtType', 'mvtPoint', 'mvtQuantite',
                'mvtCout', 'mvtMotif', 'mvtRupture', 'mvtRefusJournalier',
            ],
            'import' => ['fichierImport', 'lignesRefusees'],
            'export' => ['formatExport'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'libelle.required' => __('stocks.validation.libelle_obligatoire'),
            'uniteSaisie.required' => __('stocks.validation.unite_obligatoire'),
            'seuilAlerte.required' => __('stocks.validation.seuil_obligatoire'),
            'mvtQuantite.gt' => __('stocks.validation.quantite_positive'),
            'mvtMotif.required' => __('stocks.validation.motif_obligatoire'),
            'mvtType.in' => __('stocks.validation.type_inconnu'),
            'mvtArticleId.exists' => __('stocks.validation.article_inexistant'),
            'mvtPoint.exists' => __('stocks.validation.point_inexistant'),
            'pointOuverture.exists' => __('stocks.validation.point_inexistant'),
            'suiviSaisi.in' => __('stocks.validation.suivi_inconnu'),
        ];
    }

    // ======================================================================
    // Référentiel article — EF-M6-01
    // ======================================================================

    public function nouvelArticle(): void
    {
        $this->ouvrirFormulaire('article');

        $this->categorieSaisie = self::CATEGORIES[0];
        $this->uniteSaisie = self::UNITES[2];
        $this->pointOuverture = (string) (PointStockage::query()->orderBy('libelle')->value('id') ?? '');
        // maître l.312 : « permanent » est le défaut, et il décrit le
        // comportement en vigueur — tout article existant est suivi en stock.
        $this->suiviSaisi = ConsultationStockService::SUIVI_AVEC_STOCK;
    }

    public function editerArticle(string $article): void
    {
        $this->ouvrirFormulaire('article');

        $existant = Article::find($article);

        if (! $existant instanceof Article) {
            $this->addError('libelle', __('stocks_pwa.article.introuvable'));

            return;
        }

        $this->articleId = $existant->id;
        $this->libelle = $existant->libelle;
        $this->categorieSaisie = (string) $existant->categorie;
        $this->uniteSaisie = $existant->unite_mesure;
        $this->seuilAlerte = (string) $existant->seuil_alerte;
        // maître l.304 et l.312 : le point de rattachement et le mode de suivi
        // sont proposés en CRÉATION comme en MODIFICATION. Ne les offrir qu'à
        // la création rendrait un article mal classé incorrigible.
        $this->pointOuverture = (string) ($existant->point_stockage_id ?? '');
        $this->suiviSaisi = (string) $existant->suivi;

        // Le point PROPOSÉ pour une entrée est celui de rattachement — c'est
        // là que la marchandise arrive le plus souvent. Même choix qu'à
        // l'ouverture du mouvement : un défaut faux se valide sans se lire.
        $this->entreePoint = (string) ($existant->point_stockage_id
            ?? PointStockage::query()->orderBy('libelle')->value('id')
            ?? '');
    }

    /**
     * Qui peut faire ENTRER du stock depuis la fiche article — PO 06/09/2026.
     *
     * ## Pourquoi ce geste est plus étroit que « Mouvement »
     *
     * Le bouton « Mouvement » de la ligne reste ouvert à tout rôle en `C` sur
     * M6 : c'est le chemin quotidien du magasinier, avec son motif obligatoire
     * et son arbitrage de rupture (RG-06). Le raccourci de la fiche article,
     * lui, est un geste d'ADMINISTRATION — il valorise l'entrée et déplace
     * donc le coût moyen pondéré, qui alimente le poste de stocks au bilan.
     * La directive le réserve à l'administrateur, et ce prédicat est le seul
     * endroit qui le dit.
     *
     * Ne lève jamais : c'est ce que `render()` passe à la vue pour décider si
     * le bloc est RENDU (Article 3.3 — une action indisponible est retirée,
     * jamais grisée). Le refus serveur est `exigerAjustementDeStock()`.
     */
    protected function peutAjusterLeStock(): bool
    {
        $utilisateur = auth()->user();

        return $utilisateur instanceof User
            && $utilisateur->estActif()
            && $utilisateur->estAdministrateur()
            // Le rôle ne dispense JAMAIS du droit sur le module : il s'y
            // ajoute. Même source que `VerifierAccesModule`, jamais un calcul
            // réécrit ici.
            && $utilisateur->niveauSurModule(self::MODULE) === 'C';
    }

    /**
     * Le refus SERVEUR de l'entrée depuis la fiche article.
     *
     * Le bloc n'est pas rendu sans le droit, mais l'ouverture ne protège
     * rien : `entreeQuantite` est une propriété Livewire, posée depuis le
     * navigateur. `exigerEcriture()` passe d'abord — il trace le refus au
     * journal de sécurité et distingue 401 de 403.
     */
    protected function exigerAjustementDeStock(): void
    {
        $this->exigerEcriture(self::MODULE);

        if (! $this->peutAjusterLeStock()) {
            abort(403, __('stocks_pwa.article.entree_refus_role'));
        }
    }

    /**
     * Crée ou met à jour l'article — et pose son stock d'ouverture comme un
     * MOUVEMENT, jamais comme une colonne.
     *
     * Le coût d'achat saisi n'écrit pas `cout_moyen_pondere` : il est passé à
     * `MouvementStockService::entree()`, qui le fait traverser
     * `ValorisationStockService`. Écrire le CMP directement — ce que faisait la
     * version précédente — figerait une valeur qui alimente le poste de stocks
     * au bilan et la variation de stock au résultat, et
     * `EnregistrerArticleRequest` l'interdit déjà côté API.
     */
    public function enregistrerArticle(
        ReferentielArticleService $referentiel,
        MouvementStockService $mouvements,
    ): void {
        $edition = $this->articleId !== null;
        $journalier = $this->suiviSaisi === 'journalier';

        $this->validerEcriture([
            'libelle' => ['required', 'string', 'max:255'],
            'categorieSaisie' => ['required', 'string', 'max:255'],
            'uniteSaisie' => ['required', 'string', 'max:255'],
            // maître l.358 : en suivi journalier, le seuil ne se saisit pas —
            // il n'y a pas de stock à comparer. Le champ disparaît, donc
            // l'exiger refuserait un formulaire que l'écran ne montre plus.
            'seuilAlerte' => [$journalier ? 'nullable' : 'required', 'numeric', 'min:0'],
            'pointOuverture' => [$edition ? 'nullable' : 'required', 'exists:points_stockage,id'],
            'suiviSaisi' => ['required', Rule::in(Article::SUIVIS)],
            'valeurAchat' => ['nullable', 'numeric', 'min:0'],
            'stockOuverture' => ['nullable', 'numeric', 'min:0'],
            // L'entrée depuis la fiche (PO 06/09/2026). `gt:0` plutôt que
            // `min:0` : une quantité saisie à zéro n'est pas une entrée, et
            // l'écrire comme telle poserait un mouvement qui ne bouge rien.
            'entreeQuantite' => ['nullable', 'numeric', 'gt:0'],
            'entreePoint' => ['nullable', 'exists:points_stockage,id'],
            'entreeCout' => ['nullable', 'numeric', 'min:0'],
        ]);

        $champs = [
            'libelle' => $this->libelle,
            'categorie' => $this->categorieSaisie,
            'unite_mesure' => $this->uniteSaisie,
            // maître l.358 : `seuil_alerte` retombe à 0 en suivi journalier.
            // La colonne est NOT NULL — la laisser vide ferait échouer
            // l'insertion sur un message SQL.
            'seuil_alerte' => $journalier ? '0' : $this->seuilAlerte,
            'suivi' => $this->suiviSaisi,
            // Le RATTACHEMENT principal de l'article, distinct du point
            // d'imputation du mouvement d'ouverture ci-dessous — ils sont le
            // même choix à la création, et le maître n'en pose qu'un (l.304).
            'point_stockage_id' => $this->pointOuverture === '' ? null : $this->pointOuverture,
        ];

        if ($edition) {
            $existant = Article::find($this->articleId);

            if (! $existant instanceof Article) {
                $this->addError('libelle', __('stocks_pwa.article.introuvable'));

                return;
            }

            $referentiel->modifier($existant, $champs);

            $message = $this->faireEntrerLeStock($existant, $mouvements, $journalier);

            $this->terminerFormulaire($message ?? __('stocks_pwa.article.modifie', [
                'libelle' => $this->libelle,
            ]));

            return;
        }

        $article = $referentiel->creer($champs);

        // maître l.365-366 : un article journalier n'a pas de stock
        // d'ouverture. Lui en poser un écrirait un mouvement sur une
        // marchandise dont personne ne tient le compte.
        if (! $journalier
            && bccomp($this->stockOuverture === '' ? '0' : $this->stockOuverture, '0', 2) > 0) {
            $mouvements->entree(
                articleId: $article->id,
                pointId: $this->pointOuverture,
                quantite: $mouvements->arrondirQuantite($this->stockOuverture),
                motif: __('stocks_pwa.article.stock_ouverture_motif'),
                coutUnitaire: $this->valeurAchat === '' ? null : $this->valeurAchat,
            );
        }

        $this->terminerFormulaire(__('stocks_pwa.article.cree', ['libelle' => $this->libelle]));
    }

    /**
     * L'ENTRÉE saisie depuis la fiche article — PO 06/09/2026.
     *
     * Rend le message de succès quand un mouvement a réellement eu lieu, et
     * `null` quand la fiche a été enregistrée sans toucher au stock : annoncer
     * une entrée qui n'a pas eu lieu serait un indicateur qui affirme un état
     * qu'il n'a pas vérifié (PA-59/60/61).
     *
     * ## Trois refus, et chacun a sa raison
     *
     * 1. **Le droit** — geste d'administration, voir `peutAjusterLeStock()`.
     *    Exigé même si le bloc n'est pas rendu : l'ouverture ne protège rien.
     * 2. **Le suivi journalier** — un article acheté au marché chaque matin
     *    n'a pas de stock à tenir. Lui poser une entrée écrirait un solde
     *    théorique qui ne correspond à rien de compté, et le stock du Gîte est
     *    précisément ce que l'inventaire vient rapprocher.
     * 3. **Le point** — `entree()` l'exige, et une quantité sans destination
     *    n'est pas une livraison.
     *
     * ⚠ Le coût passe par `entree()`, jamais par la colonne : c'est
     * `ValorisationStockService` qui fait le coût moyen pondéré. L'écrire
     * directement figerait une valeur qui alimente le poste de stocks au bilan
     * et la variation de stock au résultat (`EnregistrerArticleRequest`
     * l'interdit déjà côté API).
     */
    protected function faireEntrerLeStock(
        Article $article,
        MouvementStockService $mouvements,
        bool $journalier,
    ): ?string {
        $quantite = trim($this->entreeQuantite);

        if ($quantite === '' || bccomp($quantite, '0', 2) <= 0) {
            return null;
        }

        $this->exigerAjustementDeStock();

        if ($journalier) {
            // Le bloc n'est pas rendu dans cet état : y arriver signifie que la
            // propriété a été forcée depuis le navigateur.
            $this->addError('entreeQuantite', __('stocks_pwa.article.entree_refus_journalier', [
                'article' => $article->libelle,
            ]));

            return null;
        }

        if ($this->entreePoint === '') {
            $this->addError('entreePoint', __('stocks_pwa.article.entree_point_requis'));

            return null;
        }

        $mouvements->entree(
            articleId: $article->id,
            pointId: $this->entreePoint,
            quantite: $mouvements->arrondirQuantite($quantite),
            motif: __('stocks_pwa.article.entree_motif'),
            // `null` reste `null` : sans coût saisi, l'entrée ne valorise rien
            // — un zéro se lirait « reçu gratuitement » et écraserait le CMP.
            coutUnitaire: trim($this->entreeCout) === '' ? null : trim($this->entreeCout),
        );

        return __('stocks_pwa.article.entree_enregistree', [
            'libelle' => $article->libelle,
            'quantite' => $quantite,
            'unite' => $article->unite_mesure,
        ]);
    }

    // ======================================================================
    // Mouvement de stock — RG-06
    // ======================================================================

    public function ouvrirMouvement(string $article): void
    {
        $this->ouvrirFormulaire('mouvement');

        $existant = Article::find($article);

        if (! $existant instanceof Article) {
            $this->addError('mvtQuantite', __('stocks_pwa.article.introuvable'));

            return;
        }

        // maître l.380-383 — un article en suivi journalier n'a pas de stock à
        // mouvementer. La fenêtre ne s'ouvre pas, et le refus NOMME l'article :
        // « son stock n'est pas suivi » sans dire lequel obligerait à deviner.
        if (! $existant->estSuiviEnStock()) {
            $this->etatFormulaire = null;
            $this->mvtRefusJournalier = __('stocks_pwa.mouvement.refus_journalier', [
                'article' => $existant->libelle,
            ]);

            return;
        }

        $this->mvtRefusJournalier = null;
        $this->mvtArticleId = $existant->id;
        // maître l.396 : le point PROPOSÉ est celui de rattachement de
        // l'article, pas le premier de la liste — c'est là que la marchandise
        // se trouve le plus souvent, et un défaut faux se valide sans se lire.
        $this->mvtPoint = (string) ($existant->point_stockage_id
            ?? PointStockage::query()->orderBy('libelle')->value('id')
            ?? '');
        $this->mvtCout = (string) $existant->cout_moyen_pondere;
    }

    /**
     * Enregistre le mouvement — ou demande la confirmation de RG-06.
     *
     * Une rupture n'est pas une erreur définitive : c'est une décision de
     * gestion, autorisée si elle est ASSUMÉE par quelqu'un. Le refus du domaine
     * est donc converti en question, pas en échec — et le chemin de forçage
     * laisse une trace dans `journal_audit`, posée par le Service.
     */
    public function enregistrerMouvement(MouvementStockService $mouvements): void
    {
        $this->validerEcriture([
            'mvtArticleId' => ['required', 'exists:articles,id'],
            'mvtType' => ['required', Rule::in(self::TYPES_MOUVEMENT)],
            'mvtPoint' => ['required', 'exists:points_stockage,id'],
            'mvtQuantite' => ['required', 'numeric', 'gt:0'],
            'mvtCout' => ['nullable', 'numeric', 'min:0'],
            'mvtMotif' => ['required', 'string', 'max:255'],
        ]);

        try {
            $this->deposerMouvement($mouvements, false);
        } catch (RuptureStockException $rupture) {
            // RG-06 — le message du domaine est repris TEL QUEL : il chiffre le
            // disponible et le demandé, et le reformuler ici ferait diverger
            // deux phrases pour un même refus.
            $this->mvtRupture = $rupture->getMessage();
            $this->etatFormulaire = 'rupture';

            return;
        }

        $this->terminerFormulaire(__('stocks_pwa.mouvement.enregistre'));
    }

    /**
     * La rupture, assumée — le second geste de RG-06.
     *
     * Il est PUBLIC et distinct du premier à dessein : forcer un stock négatif
     * doit être un clic identifiable, jamais un effet de bord d'un
     * enregistrement ordinaire.
     */
    public function forcerMouvement(MouvementStockService $mouvements): void
    {
        $this->exigerEcriture(self::MODULE);

        $this->deposerMouvement($mouvements, true);

        $this->terminerFormulaire(__('stocks_pwa.mouvement.rupture_enregistree'));
    }

    /**
     * Le seul chemin d'écriture de mouvement de cet écran.
     *
     * `protected` : la réflexion rapporterait une méthode publique comme une
     * action Livewire de plus à relire, pour un geste qui n'est jamais déclenché
     * directement depuis la vue.
     *
     * @throws RuptureStockException
     */
    protected function deposerMouvement(MouvementStockService $mouvements, bool $forcer): void
    {
        $quantite = $mouvements->arrondirQuantite($this->mvtQuantite);

        if ($this->mvtType === 'entree') {
            $mouvements->entree(
                articleId: (string) $this->mvtArticleId,
                pointId: $this->mvtPoint,
                quantite: $quantite,
                motif: $this->mvtMotif,
                // Une entrée SANS coût est un transfert entre points : déplacer
                // une marchandise ne change pas son coût d'acquisition, et lui
                // réappliquer un CMP la revaloriserait sans achat.
                coutUnitaire: $this->mvtCout === '' ? null : $this->mvtCout,
            );

            return;
        }

        if ($this->mvtType === 'perte') {
            $mouvements->perte(
                articleId: (string) $this->mvtArticleId,
                pointId: $this->mvtPoint,
                quantite: $quantite,
                motif: $this->mvtMotif,
                validationRupture: $forcer,
            );

            return;
        }

        $mouvements->sortie(
            articleId: (string) $this->mvtArticleId,
            pointId: $this->mvtPoint,
            quantite: $quantite,
            motif: $this->mvtMotif,
            validationRupture: $forcer,
        );
    }

    // ======================================================================
    // Import CSV
    // ======================================================================

    public function ouvrirImport(): void
    {
        $this->ouvrirFormulaire('import');
    }

    /**
     * Le modèle d'import — un VRAI classeur `.xlsx` (30/10/2026). Le CSV au
     * point-virgule qui le précédait s'ouvrait en une seule colonne dans un
     * Excel réglé sur la virgule. Feuilles « Modèle » (en-têtes en gras, une
     * ligne d'exemple marquée « (exemple) », jamais importée) et « Aide ».
     */
    public function telechargerModele(TableurService $tableur): StreamedResponse
    {
        $this->exigerEcriture(self::MODULE);

        $octets = $tableur->ecrireClasseur(
            __('stocks_pwa.import.titre'),
            __('stocks_pwa.import.sous_titre'),
            ReferentielsImport::colonnesArticlesEcranStocks(),
        );

        return response()->streamDownload(
            static function () use ($octets): void {
                echo $octets;
            },
            'modele_import_articles.xlsx',
            ['Content-Type' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'],
        );
    }

    /**
     * Importe le fichier — une ligne fautive n'annule pas l'import, elle est
     * NOMMÉE.
     *
     * C'est la règle du maître (l.487-490) : refuser le lot entier obligerait à
     * tout refaire pour une coquille sur une ligne, et l'utilisateur ne saurait
     * même pas laquelle.
     */
    public function lancerImport(
        ReferentielArticleService $referentiel,
        MouvementStockService $mouvements,
        TableurService $tableur,
    ): void {
        $this->validerEcriture([
            'fichierImport' => ['required', 'file', 'mimes:xlsx,csv,txt', 'max:2048'],
        ]);

        try {
            $tableau = $tableur->lire(
                (string) $this->fichierImport?->getRealPath(),
                (string) $this->fichierImport?->getClientOriginalName(),
            );
        } catch (\RuntimeException $refus) {
            $this->addError('fichierImport', $refus->getMessage());

            return;
        }

        // Les en-têtes se lisent PAR NOM : une colonne déplacée ou ajoutée ne
        // décale plus rien. `nom` et `unite_mesure` sont indispensables ; les
        // autres, absentes, retombent sur leur défaut.
        $index = $tableur->indexerEntetes($tableau[0] ?? [], ReferentielsImport::colonnesArticlesEcranStocks());
        $absentes = array_values(array_filter(
            ['nom', 'unite_mesure'],
            static fn (string $champ): bool => ! isset($index[$champ]),
        ));

        if ($absentes !== []) {
            $this->addError('fichierImport', __('stocks_pwa.import.entete_absente', [
                'colonnes' => implode(', ', $absentes),
                'trouvees' => implode(' ; ', array_filter(array_map('trim', $tableau[0] ?? []), static fn (string $v): bool => $v !== '')),
            ]));

            return;
        }

        $points = PointStockage::query()->pluck('id', 'libelle');
        $crees = 0;
        $refuses = [];

        foreach (array_slice($tableau, 1) as $position => $brute) {
            // Comme Excel : l'en-tête est la ligne 1.
            $numero = $position + 2;

            $cellule = static fn (string $champ): string => isset($index[$champ]) ? trim((string) ($brute[$index[$champ]] ?? '')) : '';

            if (array_filter($brute, static fn ($v): bool => trim((string) $v) !== '') === []) {
                continue;   // ligne vide : ce n'est pas une erreur, c'est un blanc.
            }

            // La ligne d'exemple du modèle (« (exemple) … ») n'est pas une donnée.
            if ($tableur->estLigneExemple($brute)) {
                continue;
            }

            $nom = $cellule('nom');

            try {
                $pointId = $points->get($cellule('point_stockage'));

                // Un mode de suivi hors registre retombe sur « permanent »
                // plutôt que de faire échouer la ligne : c'est le défaut du
                // schéma, il décrit le comportement habituel, et refuser la
                // ligne entière pour une colonne facultative ferait perdre
                // l'article. La valeur est cependant relue telle quelle — rien
                // n'est deviné à partir d'autre chose.
                $suiviLu = $cellule('suivi');
                $suivi = in_array($suiviLu, Article::SUIVIS, true)
                    ? $suiviLu
                    : ConsultationStockService::SUIVI_AVEC_STOCK;
                $journalier = $suivi !== ConsultationStockService::SUIVI_AVEC_STOCK;

                $article = $referentiel->creer([
                    'libelle' => $nom,
                    'categorie' => $cellule('categorie'),
                    'unite_mesure' => $cellule('unite_mesure'),
                    'seuil_alerte' => $journalier || ! isset($index['seuil_alerte']) ? '0' : $cellule('seuil_alerte'),
                    'suivi' => $suivi,
                    'point_stockage_id' => is_string($pointId) ? $pointId : null,
                ]);

                $ouverture = $cellule('stock_initial') === '' ? '0' : $cellule('stock_initial');

                if (! $journalier && is_string($pointId) && is_numeric($ouverture) && bccomp($ouverture, '0', 2) > 0) {
                    $mouvements->entree(
                        articleId: $article->id,
                        pointId: $pointId,
                        quantite: $mouvements->arrondirQuantite($ouverture),
                        motif: __('stocks_pwa.article.stock_ouverture_motif'),
                        coutUnitaire: is_numeric($cellule('prix_achat')) ? $cellule('prix_achat') : null,
                    );
                }

                $crees++;
            } catch (\Throwable $echec) {
                $refuses[] = __('stocks_pwa.import.ligne_refusee', [
                    'numero' => (string) $numero,
                    'nom' => $nom === '' ? '?' : $nom,
                    'raison' => $echec->getMessage(),
                ]);
            }
        }

        $this->lignesRefusees = $refuses;

        if ($refuses !== []) {
            // Le bilan reste AFFICHÉ : refermer la modale sur un import partiel
            // ferait disparaître la liste des lignes à corriger.
            $this->addError('fichierImport', __('stocks_pwa.import.bilan_partiel', [
                'crees' => (string) $crees,
                'refuses' => (string) count($refuses),
            ]));

            return;
        }

        $this->terminerFormulaire(__('stocks_pwa.import.bilan', ['crees' => (string) $crees]));
    }

    // ======================================================================
    // Export — RG-19
    // ======================================================================

    /**
     * Deux boutons, un seul formulaire — comme le hub Comptabilité et
     * l'Accueil (`Accueil::ouvrirExport()`). Le maître (`m6-stocks.html`)
     * rend « Excel » à côté de « PDF » ; le bouton unique labellisé « PDF »
     * qui ouvrait ce formulaire ne rendait pas ce second bouton, alors que la
     * modale offrait déjà les deux formats (audit navigateur du 01/09/2026).
     */
    public function ouvrirExport(string $format = 'pdf'): void
    {
        // ⚠ ORDRE — `ouvrirFormulaire()` appelle `$this->reset(['formatExport'])`
        // (son contrat, `FormulaireModal::ouvrirFormulaire()` l.104) : le
        // poser AVANT le fait réécraser aussitôt par la valeur par défaut. Le
        // bouton « Excel » ouvrait donc la modale sur « PDF » coché — trouvé
        // à l'essai réel du 01/09/2026, pas à la lecture.
        $this->ouvrirFormulaire('export');
        $this->formatExport = in_array($format, ['pdf', 'excel'], true) ? $format : 'pdf';
    }

    /**
     * PA-119 — un export porte sur CE QUI EST AFFICHÉ, et il DIT son filtre.
     *
     * Une liste vide se refuse : produire un document vide ferait croire à un
     * référentiel vide, et il partirait au comptable comme un constat.
     */
    public function genererExport(ConsultationStockService $consultation): mixed
    {
        $this->exigerEcriture(self::MODULE);

        $lignes = $this->lignesFiltrees($consultation);

        if ($lignes->isEmpty()) {
            $this->addError('formatExport', __('stocks_pwa.export.liste_vide'));

            return null;
        }

        $this->etatFormulaire = null;

        return $this->formatExport === 'excel'
            ? $this->exporterTableur()
            : $this->exporterPdf($consultation, $lignes);
    }

    /**
     * @param  \Illuminate\Support\Collection<int, \App\Domain\Stocks\ReadModels\LigneStockArticle>  $lignes
     */
    protected function exporterPdf(ConsultationStockService $consultation, $lignes): StreamedResponse
    {
        $pdf = Pdf::loadView('pdf.stocks-etat', [
            // PA-119 : l'en-tête DIT le filtre — un document partiel ne doit
            // pas pouvoir passer pour l'état complet.
            'entete' => $this->enTeteRapport(__('stocks_pwa.export.document_stocks'), $this->libelleDesFiltres()),
            'lignes' => $lignes,
            'consolide' => $consultation->etatConsolide($this->pointFiltre(), false, $this->suiviFiltre()),
            'filtres' => $this->libelleDesFiltres(),
            'auteur' => (string) Auth::user()?->login,
        ])->setPaper('a4', 'portrait');

        return response()->streamDownload(
            static function () use ($pdf): void {
                echo $pdf->output();
            },
            'etat_des_stocks_'.now()->format('Ymd_His').'.pdf',
        );
    }

    /**
     * Le « Excel » du maître est servi en XLSX par `StocksExport`, qui porte
     * déjà l'en-tête, les alignements et le format monétaire.
     */
    protected function exporterTableur(): mixed
    {
        return Excel::download(
            new StocksExport(
                $this->pointFiltre(),
                $this->categorie === '' ? null : $this->categorie,
                $this->suiviFiltre(),
            ),
            'etat_des_stocks_'.now()->format('Ymd_His').'.xlsx',
        );
    }

    /**
     * Ferme la modale ouverte.
     *
     * ⚠ Elle exige le droit d'écriture, comme toute action publique de la PWA
     * (`PwaEcritureAutoriseeTest` présume l'écriture). C'est sans conséquence
     * fonctionnelle : aucune modale ne peut être ouverte sans ce même droit.
     */
    public function fermerModales(): void
    {
        $this->exigerEcriture(self::MODULE);

        $this->etatFormulaire = null;
        $this->mvtRefusJournalier = null;
        $this->resetValidation();
    }

    // ======================================================================
    // Archivage du référentiel — « supprimer = archiver » (PO, 03/09/2026)
    // ======================================================================

    /**
     * Ouvre la confirmation d'archivage — une ligne, ou la sélection entière.
     *
     * Le droit d'ARCHIVER est exigé DÈS l'ouverture, en plus du droit
     * d'écriture posé par `ouvrirFormulaire()` : sans lui, un `magasinier`
     * bascule fermée ouvrirait une modale que l'exécution refuserait en 403.
     */
    public function confirmerArchivageArticle(?string $article = null): void
    {
        $this->exigerArchivage();

        // La sélection porte sur CE QUI EST AFFICHÉ (même règle que l'export,
        // PA-119) : cocher toute une page puis changer de filtre ne doit pas
        // archiver des articles que l'écran ne montre plus.
        $ids = $article !== null
            ? [$article]
            : array_values(array_intersect($this->selection, $this->identifiantsAffiches()));

        if ($ids === []) {
            return;
        }

        $this->ouvrirFormulaire('archivage');

        $referentiel = app(ReferentielArticleService::class);
        $lot = $this->composerLotArchivage(
            Article::query()->whereIn('id', $ids)->where('actif', true)->orderBy('libelle')->get(),
            static fn (Article $a): array => $referentiel->verrous($a),
            static fn (Article $a): string => (string) $a->libelle,
        );

        $this->articlesAArchiver = $lot['ids'];
        $this->verrousArchivage = $lot['motifs'];
        $this->archivageBloque = $lot['bloque'];
        $this->conservesArchivage = $lot['conserves'];
        $this->libelleArchivage = $lot['libelle'];
    }

    /**
     * Archive le lot confirmé — par le SERVICE, jamais un `update()` écrit ici.
     *
     * Un refus du service (une entrée de stock née entre l'ouverture et le
     * clic) s'affiche et n'empêche PAS les autres archivages du lot.
     */
    public function archiverArticles(ReferentielArticleService $referentiel): void
    {
        $this->exigerArchivage();

        if ($this->articlesAArchiver === []) {
            return;
        }

        $archives = 0;

        foreach (Article::query()->whereIn('id', $this->articlesAArchiver)->get() as $article) {
            try {
                $referentiel->archiver($article);
                $archives++;
            } catch (\RuntimeException $refus) {
                $this->addError('archivage', $refus->getMessage());
            }
        }

        $this->articlesAArchiver = [];
        $this->viderSelection();
        $this->etatFormulaire = null;

        if ($archives > 0) {
            session()->flash('pwa-succes', trans_choice('stocks_pwa.archivage.succes', $archives, [
                'nombre' => $archives,
            ]));
        }
    }

    /**
     * Le pendant de l'archivage.
     *
     * ⚠ Il n'est PAS derrière `exigerArchivage()`, délibérément : restaurer
     * n'est pas supprimer — fermer la bascule pendant qu'un article est aux
     * archives ne doit jamais l'y enfermer (PA-59/60/61). Même arbitrage que
     * `Hebergement::restaurerUnite()`.
     */
    public function restaurerArticle(string $article, ReferentielArticleService $referentiel): void
    {
        $this->exigerEcriture(self::MODULE);

        $modele = Article::findOrFail($article);
        $referentiel->restaurer($modele);

        session()->flash('pwa-succes', __('stocks_pwa.archivage.restaure', [
            'libelle' => (string) $modele->libelle,
        ]));
    }

    /**
     * Les identifiants de la PAGE affichée — c'est ce que « tout
     * sélectionner » sélectionne au maître, jamais le référentiel entier.
     *
     * @return list<string>
     */
    private function identifiantsAffiches(): array
    {
        $lignes = app(ConsultationStockService::class)->listerArticles(
            recherche: $this->recherche === '' ? null : $this->recherche,
            categorie: $this->categorie === '' ? null : $this->categorie,
            pointId: $this->pointFiltre(),
            etat: $this->etatFiltre(),
            suivi: $this->suiviFiltre(),
            parPage: self::PAR_PAGE,
        );

        /** @var list<string> $ids */
        $ids = array_map(
            static fn ($ligne): string => (string) $ligne->article->id,
            $lignes->items(),
        );

        return $ids;
    }

    private function viderSelection(): void
    {
        $this->selection = [];
        $this->toutSelectionne = false;
    }

    // ======================================================================
    // Filtres et rendu
    // ======================================================================

    public function updatedRecherche(): void
    {
        // Un filtre qui change remet la SELECTION à zéro : sans cela, des
        // cases cochées sous un filtre précédent survivraient, invisibles, et
        // « Supprimer » porterait sur des lignes que l'écran ne montre plus —
        // le défaut que PA-119 nomme pour l'export, transposé à un geste
        // destructeur.
        $this->viderSelection();
        $this->resetPage();
    }

    /**
     * La case « tout sélectionner » de l'entête (`crud-ui.js` l.66).
     *
     * `updated*` est un point d'entrée du cadre Livewire : il n'écrit rien
     * d'autre que l'état d'affichage du composant.
     */
    public function updatedToutSelectionne(bool $valeur): void
    {
        $this->selection = $valeur ? $this->identifiantsAffiches() : [];
    }

    public function updatedCategorie(): void
    {
        $this->viderSelection();
        $this->resetPage();
    }

    public function updatedPoint(): void
    {
        $this->viderSelection();
        $this->resetPage();
    }

    public function updatedEtat(): void
    {
        $this->viderSelection();
        $this->resetPage();
    }

    /*
     * ⚠ AUCUN `updatedSuivi()`, ET C'EST DELIBERE.
     *
     * Les quatre hameçons ci-dessus sont des ACTIONS LIVEWIRE publiques, donc
     * de la surface que `PwaActionsReluesTest` tient fermée : en ajouter une
     * cinquième pour un `resetPage()` ferait grossir la liste relue d'une
     * méthode qui ne fait rien d'autre. Le filtre de suivi est rattrapé par
     * `clampPage()` dans `render()`, qui couvre EN PLUS le cas qu'aucun de ces
     * quatre hameçons ne couvre : un `?page=99` tapé à la main.
     */

    /**
     * Le filtre d'état est un registre FERMÉ.
     *
     * Une valeur inconnue retombe sur « tous les états » plutôt que de vider la
     * liste : une liste vide sous un intitulé qui promet le contraire se lit
     * comme « il n'y a rien », pas comme « le filtre n'a pas été compris ».
     */
    protected function etatFiltre(): ?string
    {
        return in_array($this->etat, ConsultationStockService::ETATS, true) ? $this->etat : null;
    }

    protected function pointFiltre(): ?string
    {
        return $this->point === '' ? null : $this->point;
    }

    /**
     * Le filtre de suivi est un registre FERMÉ, comme celui d'état.
     *
     * Une valeur inconnue retombe sur « tous les suivis » : une liste vide
     * sous un intitulé qui promet le contraire se lit « il n'y a rien », pas
     * « le filtre n'a pas été compris ».
     */
    protected function suiviFiltre(): ?string
    {
        return in_array($this->suivi, Article::SUIVIS, true) ? $this->suivi : null;
    }

    /**
     * Les lignes RÉELLEMENT affichées — la même projection que l'écran, sans
     * pagination : PA-119 exige qu'un export porte sur ce qui est à l'écran.
     *
     * @return \Illuminate\Support\Collection<int, \App\Domain\Stocks\ReadModels\LigneStockArticle>
     */
    protected function lignesFiltrees(ConsultationStockService $consultation): \Illuminate\Support\Collection
    {
        return collect($consultation->listerArticles(
            recherche: $this->recherche === '' ? null : $this->recherche,
            categorie: $this->categorie === '' ? null : $this->categorie,
            pointId: $this->pointFiltre(),
            etat: $this->etatFiltre(),
            suivi: $this->suiviFiltre(),
            parPage: ConsultationStockService::PAR_PAGE_MAX,
        )->items());
    }

    /**
     * Les filtres appliqués, en clair — un export qui ne dit pas son filtre
     * laisse croire qu'il porte sur tout (PA-119).
     */
    protected function libelleDesFiltres(): string
    {
        $filtres = [];

        if ($this->recherche !== '') {
            $filtres[] = __('stocks_pwa.liste.rechercher').' « '.$this->recherche.' »';
        }

        if ($this->categorie !== '') {
            $filtres[] = __('stocks_pwa.liste.col_categorie').' : '.$this->categorie;
        }

        if ($this->point !== '') {
            $filtres[] = __('stocks_pwa.liste.col_point').' : '
                .(PointStockage::query()->whereKey($this->point)->value('libelle') ?? $this->point);
        }

        $suivi = $this->suiviFiltre();

        if ($suivi !== null) {
            $filtres[] = $suivi === 'journalier'
                ? __('stocks_pwa.liste.suivi_journalier')
                : __('stocks_pwa.liste.suivi_permanent');
        }

        $etat = $this->etatFiltre();

        if ($etat !== null) {
            $filtres[] = $etat === 'rupture'
                ? __('stocks_pwa.liste.etat_rupture')
                : __('stocks_pwa.liste.etat_sous_seuil');
        }

        return $filtres === [] ? __('stocks_pwa.export.filtre_aucun') : implode(' · ', $filtres);
    }

    /**
     * Un flux CSV avec BOM UTF-8 et séparateur point-virgule — convention
     * serveur RG-19, celle qu'Excel francophone ouvre sans boîte de dialogue.
     *
     * @param  callable(resource): void  $ecrire
     */
    protected function fluxCsv(string $nom, callable $ecrire): StreamedResponse
    {
        return response()->streamDownload(
            static function () use ($ecrire): void {
                $sortie = fopen('php://output', 'w');

                if ($sortie === false) {
                    return;
                }

                fwrite($sortie, "\xEF\xBB\xBF");
                $ecrire($sortie);
                fclose($sortie);
            },
            $nom,
            ['Content-Type' => 'text/csv; charset=UTF-8'],
        );
    }

    public function render(
        ConsultationStockService $consultation,
        StockTheoriqueService $stocks,
        ValorisationStockService $valorisation,
    ): View {
        $lignes = $consultation->listerArticles(
            recherche: $this->recherche === '' ? null : $this->recherche,
            categorie: $this->categorie === '' ? null : $this->categorie,
            pointId: $this->pointFiltre(),
            etat: $this->etatFiltre(),
            suivi: $this->suiviFiltre(),
            parPage: self::PAR_PAGE,
        );

        // Une page VIDE sous un total non nul n'est pas un resultat : c'est
        // une pagination perimee. Elle se produit des qu'un filtre reduit la
        // liste alors qu'on est en page 2 — et l'ecran afficherait « Aucun
        // resultat » sous un filtre qui, lui, ramene des lignes. Le rattrapage
        // est ici plutot que dans un cinquieme hamecon `updatedSuivi()` :
        // celui-la n'aurait rien dit d'un `?page=99` tape a la main.
        if ($lignes->isEmpty() && $lignes->total() > 0) {
            $this->resetPage();

            $lignes = $consultation->listerArticles(
                recherche: $this->recherche === '' ? null : $this->recherche,
                categorie: $this->categorie === '' ? null : $this->categorie,
                pointId: $this->pointFiltre(),
                etat: $this->etatFiltre(),
                suivi: $this->suiviFiltre(),
                parPage: self::PAR_PAGE,
            );
        }

        // Le récapitulatif de la modale d'édition : les trois chiffres que le
        // maître affiche en lecture seule, calculés — jamais des colonnes.
        $recapitulatif = null;
        $articleOuvert = $this->etatFormulaire === 'article' && $this->articleId !== null
            ? Article::find($this->articleId)
            : null;

        if ($articleOuvert instanceof Article) {
            $stock = $stocks->stockTousPoints($articleOuvert->id);

            $recapitulatif = [
                'stock' => $stock,
                'unite' => $articleOuvert->unite_mesure,
                'cmp' => MontantFcfa::format($valorisation->cmp($articleOuvert)),
                'valeur' => MontantFcfa::format($valorisation->valoriser($articleOuvert, $stock)),
                // La valeur d'achat en LECTURE SEULE : elle est posée par
                // l'entrée de stock, jamais réécrite après coup. `null` quand
                // l'article n'a jamais été réceptionné — « 0 F » se lirait
                // « acheté gratuitement ».
                'prix_achat' => $articleOuvert->prix_achat === null
                    ? null
                    : MontantFcfa::format((string) $articleOuvert->prix_achat),
            ];
        }

        $articleMouvemente = $this->etatFormulaire === 'mouvement' && $this->mvtArticleId !== null
            ? Article::find($this->mvtArticleId)
            : null;

        return view('pwa.stocks.stocks', array_merge($this->socle(), [
            'lignes' => $lignes,
            'consolide' => $consultation->etatConsolide($this->pointFiltre(), false, $this->suiviFiltre()),
            'points' => PointStockage::query()->orderBy('libelle')->get(),
            'categories' => self::CATEGORIES,
            'unites' => self::UNITES,
            // Le registre FERMÉ des modes de suivi, avec les libellés du
            // maître (l.312-314) : la vue ne les écrit pas en dur, sans quoi
            // un mode ajouté au schéma resterait invisible.
            'suivis' => [
                // Cles du groupe `article` : ces libelles vivent la ou le
                // formulaire d'article les a poses. Le composant les citait
                // sous `liste.` — cles inexistantes, la vue rendait la cle
                // brute (attrape par la garde i18n le 31/08/2026).
                'permanent' => __('stocks_pwa.article.suivi_permanent_option'),
                'journalier' => __('stocks_pwa.article.suivi_journalier_option'),
            ],
            'recapitulatif' => $recapitulatif,
            // PA-119 — l'export DIT son filtre, et la phrase est construite ici
            // parce qu'une vue n'atteint pas une méthode `protected`.
            'filtresAffiches' => $this->libelleDesFiltres(),
            // La vue ne rejoue JAMAIS la règle d'archivage : elle la reçoit
            // (voir `AutoriseArchivage` — un seul auteur, deux lecteurs).
            'peutArchiver' => $this->peutArchiver(),
            // PO 06/09/2026 — le bloc d'entrée de stock de la fiche article
            // n'est RENDU que pour les rôles d'administration (Article 3.3 :
            // une action indisponible est retirée, jamais grisée).
            'peutAjusterLeStock' => $this->peutAjusterLeStock(),
            'articleMouvemente' => $articleMouvemente,
            'stockMouvemente' => $articleMouvemente instanceof Article
                ? $stocks->stockTousPoints($articleMouvemente->id)
                : null,
        ]))->layout('layouts.pwa', ['module' => self::MODULE]);
    }
}

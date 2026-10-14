<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Stocks;

use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\Inventaire;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\ConsultationStockService;
use App\Domain\Stocks\Services\FicheStockService;
use App\Domain\Stocks\Services\InventaireService;
use App\Domain\Stocks\Services\ValorisationStockService;
use App\Exports\InventairesExport;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\PageMetier;
use Barryvdh\DomPDF\Facade\Pdf;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Maatwebsite\Excel\Facades\Excel;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Écran « Inventaires & Fiches de stock » (M6) — maître :
 * `prototype_v2/pages/m6-inventaires.html`.
 *
 * ## Trois onglets, trois questions distinctes
 *
 * - **Fiche de stock** : le FLUX d'un article sur une période. Seul document
 *   qui justifie un solde — stock initial, entrées, sorties, pertes,
 *   régularisations, stock théorique. `FicheStockService` VÉRIFIE l'égalité au
 *   lieu de l'afficher : un écart signale un mouvement écrit hors du moteur, et
 *   le bandeau le dit avant les chiffres.
 * - **Inventaire physique** : le comptage, et sa clôture régularisante.
 * - **Inventaires clôturés** : l'historique.
 *
 * ## Aucune règle d'inventaire n'est réécrite ici
 *
 * Ouvrir, compter et clôturer passent par `InventaireService` — la version
 * précédente de ce composant recréait les trois à la main (`Inventaire::create`
 * puis une `LigneInventaire` par article, un `update()` de comptage, une boucle
 * d'entrées/sorties à la clôture). Trois conséquences réelles :
 * elle créait des lignes à l'ouverture alors que `quantite_constatee` est NOT
 * NULL — un article oublié devenait indiscernable d'un article compté conforme,
 * ce qu'un inventaire existe précisément pour révéler ; elle constatait les
 * manquants en `sortie` et non en `perte` ; et elle clôturait un comptage
 * incomplet sans le dire.
 *
 * ## PA-150 — le schéma ne porte AUCUN statut d'inventaire
 *
 * Le docblock du modèle `Inventaire` l'écrit : un inventaire clôturé ne se
 * distingue pas d'un inventaire ouvert au niveau de la table. L'onglet
 * « Inventaires clôturés » montre donc TOUS les inventaires et le dit ; ses
 * colonnes « Manquants » et « Excédents » rendent « — », parce que seule la
 * clôture les produit et que rien ici n'atteste qu'elle a eu lieu.
 *
 * @see EF-M6-04 Historique des mouvements
 * @see EF-M6-05 Inventaire physique avec écarts
 * @see RG-19 Export PDF/CSV
 * @see docs/DIRECTIVE_CONFORMITE_100.md Articles 4.5, 4.6, 6, 7, 8
 */
#[Title('Inventaires & Fiches de stock — TATACORA AFRIQUE')]
class Inventaires extends PageMetier
{
    use FormulaireModal;

    public const MODULE = 'M6';

    /** Registre FERMÉ des onglets — maître l.37-45. */
    public const ONGLETS = ['fiche', 'inventaire', 'historique'];

    /** Plafond de l'historique : au-delà, il devient illisible et lent. */
    public const PLAFOND_HISTORIQUE = 50;

    #[Url(as: 'onglet')]
    public string $onglet = 'fiche';

    #[Url(as: 'article')]
    public string $articleId = '';

    #[Url(as: 'point')]
    public string $point = '';

    #[Url(as: 'du')]
    public string $debut = '';

    #[Url(as: 'au')]
    public string $fin = '';

    /** Point sur lequel ouvrir le prochain inventaire. */
    public string $pointInventaire = '';

    // --- Formulaire de comptage --------------------------------------------

    public ?string $comptageArticleId = null;

    public string $quantiteComptee = '';

    // --- Modale d'export partagée ------------------------------------------

    public string $formatExport = 'pdf';

    /**
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'comptage' => ['comptageArticleId', 'quantiteComptee'],
            'cloture' => [],
            'export' => ['formatExport'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'quantiteComptee.required' => __('stocks.validation.quantite_positive'),
            'quantiteComptee.min' => __('stocks.quantite_negative'),
        ];
    }

    /**
     * La période par défaut couvre TRENTE jours, bornes comprises.
     *
     * PA-135 : le maître recule de 30 × 86 400 000 ms, ce qui fait trente et un
     * jours une fois les deux bornes incluses. Le cumul contredirait alors le
     * libellé du bouton, sur un document dont l'objet est de justifier un solde.
     */
    public function mount(): void
    {
        if ($this->fin === '') {
            $this->fin = CarbonImmutable::today()->toDateString();
        }

        if ($this->debut === '') {
            $this->debut = CarbonImmutable::today()->subDays(29)->toDateString();
        }

        // ⚠ PLUS DE PRESELECTION (PO 06/09/2026) : la chaine vide est
        // desormais l'option « Tous les articles », pas une absence de choix.
        // Poser ici le premier article du referentiel ferait ouvrir l'ecran
        // sur une fiche unitaire alors que le filtre annonce « tous ».

        $this->pointInventaire = (string) (PointStockage::query()->orderBy('libelle')->value('id') ?? '');
    }

    // ======================================================================
    // Inventaire physique — EF-M6-05
    // ======================================================================

    /**
     * Ouvre un inventaire sur le point choisi.
     *
     * AUCUNE ligne n'est créée ici, et c'est une contrainte de schéma :
     * `lignes_inventaire.quantite_constatee` est NOT NULL, donc une ligne posée
     * à l'ouverture porterait une valeur d'attente — et un article oublié
     * deviendrait indiscernable d'un article compté conforme.
     *
     * `$pointId` — ÉTAPE 1 du maître (01/09/2026) : le tableau « Cycle
     * d'inventaire par magasin » porte un bouton « Lancer l'inventaire » PAR
     * LIGNE, qui vise directement le point de cette ligne. Passer l'identifiant
     * en paramètre évite un second geste (choisir dans le `<select>` PUIS
     * cliquer) : le clic sur la ligne EST le choix. `null` conserve l'ancien
     * chemin — le `<select>` lié à `pointInventaire` — pour tout appelant qui
     * ne le fournit pas.
     */
    public function ouvrirInventaire(InventaireService $inventaires, ?string $pointId = null): void
    {
        $this->exigerEcriture(self::MODULE);

        if ($pointId !== null) {
            $this->pointInventaire = $pointId;
        }

        $lieu = PointStockage::find($this->pointInventaire);

        if (! $lieu instanceof PointStockage) {
            $this->addError('pointInventaire', __('stocks_pwa.inventaires.aucun_point_defini'));

            return;
        }

        $ouvert = $inventaires->ouvrir($lieu);

        session()->flash('pwa-succes', __('stocks_pwa.inventaires.lance', [
            'nombre' => (string) $inventaires->articlesNonComptes($ouvert)->count(),
        ]));
    }

    public function ouvrirComptage(string $article): void
    {
        $this->ouvrirFormulaire('comptage');

        $this->comptageArticleId = $article;
    }

    public function enregistrerComptage(InventaireService $inventaires): void
    {
        $this->validerEcriture([
            'comptageArticleId' => ['required', 'exists:articles,id'],
            'quantiteComptee' => ['required', 'numeric', 'min:0'],
        ]);

        $encours = $this->inventaireCourant();
        $article = Article::find($this->comptageArticleId);

        if (! $encours instanceof Inventaire || ! $article instanceof Article) {
            $this->addError('quantiteComptee', __('stocks_pwa.article.introuvable'));

            return;
        }

        $inventaires->compter($encours, $article, $this->quantiteComptee);

        $this->terminerFormulaire(__('stocks_pwa.inventaires.comptage_enregistre', [
            'article' => $article->libelle,
        ]));
    }

    public function demanderCloture(): void
    {
        $this->ouvrirFormulaire('cloture');
    }

    /**
     * Clôture et régularise — en PARTIEL assumé.
     *
     * La modale annonce AVANT le clic combien d'articles n'ont pas été comptés
     * et ce qu'il advient d'eux. Le service refuserait une clôture incomplète
     * sans ce drapeau ; l'accorder en silence régulariserait une partie du stock
     * en laissant le reste intact, sans que rien ne le signale par la suite.
     */
    public function cloturer(InventaireService $inventaires): void
    {
        $this->exigerEcriture(self::MODULE);

        $encours = $this->inventaireCourant();

        if (! $encours instanceof Inventaire) {
            $this->etatFormulaire = null;

            return;
        }

        $bilan = $inventaires->cloturer($encours, partielAutorise: true);

        $this->etatFormulaire = null;

        session()->flash('pwa-succes', __('stocks_pwa.inventaires.cloture', [
            'nombre' => (string) $bilan['lignes_regularisees'],
            'impact' => \App\Pwa\Support\MontantFcfa::format($bilan['ecart_valorise']),
        ]));
    }

    // ======================================================================
    // Export — RG-19
    // ======================================================================

    /**
     * Deux boutons, un seul formulaire — voir `Stocks::ouvrirExport()`. Le
     * bouton unique de cet écran était labellisé « PDF » et n'exposait aucun
     * bouton « Excel », alors que la modale d'export offre déjà les deux
     * formats (audit navigateur du 01/09/2026).
     */
    public function ouvrirExport(string $format = 'pdf'): void
    {
        // ⚠ ORDRE — voir `Stocks::ouvrirExport()` : `ouvrirFormulaire()`
        // réinitialise `formatExport` à sa valeur par défaut, le poser AVANT
        // le fait réécraser.
        $this->ouvrirFormulaire('export');
        $this->formatExport = in_array($format, ['pdf', 'excel'], true) ? $format : 'pdf';
    }

    /**
     * PA-119 — l'export porte sur l'ONGLET affiché et sur ses filtres.
     *
     * Un seul bouton qui rendrait toujours la fiche de stock ferait envoyer au
     * comptable un document que personne n'a regardé.
     */
    public function genererExport(FicheStockService $fiches, InventaireService $inventaires): mixed
    {
        $this->exigerEcriture(self::MODULE);

        if ($this->ongletValide() === 'fiche') {
            return $this->exporterFiche($fiches);
        }

        return $this->exporterInventaire($inventaires);
    }

    protected function exporterFiche(FicheStockService $fiches): mixed
    {
        $article = Article::find($this->articleId);

        if (! $article instanceof Article) {
            // Sous « Tous les articles » (PO 06/09/2026), le refus NOMME sa
            // raison : le document de fiche de stock est ecrit pour UN
            // article — son en-tete, ses cumuls et son unite le sont. En
            // produire un « consolide » sans revoir le gabarit rendrait des
            // quantites d'unites differentes additionnees, c'est-a-dire un
            // chiffre faux sur un document imprime.
            $this->addError(
                'formatExport',
                $this->articleId === ''
                    ? __('stocks_pwa.export.fiche_tous_articles')
                    : __('stocks_pwa.export.fiche_absente'),
            );

            return null;
        }

        $this->etatFormulaire = null;

        if ($this->formatExport === 'excel') {
            return Excel::download(
                new InventairesExport($article->id, $this->debut, $this->fin, $this->pointFiltre()),
                'fiche_de_stock_'.now()->format('Ymd_His').'.xlsx',
            );
        }

        $pdf = Pdf::loadView('pdf.fiche-stock', [
            'entete' => $this->enTeteRapport(
                __('stocks_pwa.export.document_fiche', ['article' => $article->libelle]),
                $this->libellePeriode(),
            ),
            'article' => $article,
            'fiche' => $fiches->pourArticle($article, $this->debut, $this->fin, $this->pointFiltre()),
            'auteur' => (string) Auth::user()?->login,
        ])->setPaper('a4', 'portrait');

        return $this->fluxPdf($pdf, 'fiche_de_stock_'.now()->format('Ymd_His').'.pdf');
    }

    protected function exporterInventaire(InventaireService $inventaires): mixed
    {
        $encours = $this->inventaireCourant();

        if (! $encours instanceof Inventaire) {
            $this->addError('formatExport', __('stocks_pwa.export.liste_vide'));

            return null;
        }

        $this->etatFormulaire = null;

        // La synthèse VALORISÉE vient du Service : la recalculer ici ferait
        // diverger le papier et l'écran au premier changement de convention.
        $synthese = $inventaires->synthese($encours);

        $encours->load(['point', 'lignes.article']);

        $pdf = Pdf::loadView('pdf.inventaire-rapport', [
            'entete' => $this->enTeteRapport(
                __('stocks_pwa.export.document_inventaire'),
                __('stocks_pwa.export.periode_inventaire', [
                    'point' => $encours->point->libelle ?? __('stocks_pwa.export.tous_points'),
                    'date' => \Carbon\Carbon::parse($encours->date_inventaire)->format('d/m/Y'),
                ]),
            ),
            'inventaire' => $encours,
            'nbEcarts' => $synthese['nb_ecarts'],
            'impactNet' => $synthese['ecart_valorise'],
            'auteur' => (string) Auth::user()?->login,
        ])->setPaper('a4', 'portrait');

        return $this->fluxPdf($pdf, 'rapport_inventaire_'.now()->format('Ymd_His').'.pdf');
    }

    /**
     * La période de la fiche, telle que les deux bornes du filtre la disent :
     * une borne vide n'est pas une date, elle ouvre la période de ce côté.
     */
    private function libellePeriode(): string
    {
        $date = static fn (string $jour): string => \Carbon\Carbon::parse($jour)->format('d/m/Y');

        return match (true) {
            $this->debut !== '' && $this->fin !== '' => __('rapports.periode.du_au', ['debut' => $date($this->debut), 'fin' => $date($this->fin)]),
            $this->debut !== '' => __('rapports.periode.a_compter_du', ['debut' => $date($this->debut)]),
            $this->fin !== '' => __('rapports.periode.jusqu_au', ['fin' => $date($this->fin)]),
            default => __('rapports.periode.toutes'),
        };
    }

    protected function fluxPdf(\Barryvdh\DomPDF\PDF $pdf, string $nom): StreamedResponse
    {
        return response()->streamDownload(
            static function () use ($pdf): void {
                echo $pdf->output();
            },
            $nom,
        );
    }

    public function fermerModales(): void
    {
        $this->exigerEcriture(self::MODULE);

        $this->etatFormulaire = null;
        $this->resetValidation();
    }

    // ======================================================================
    // Lectures
    // ======================================================================

    /**
     * L'onglet est un registre FERMÉ : une valeur inconnue retombe sur le
     * premier, jamais sur une page blanche.
     */
    protected function ongletValide(): string
    {
        return in_array($this->onglet, self::ONGLETS, true) ? $this->onglet : self::ONGLETS[0];
    }

    protected function pointFiltre(): ?string
    {
        return $this->point === '' ? null : $this->point;
    }

    /**
     * L'inventaire le plus récent — faute de colonne de statut au schéma
     * (PA-150), c'est la seule définition possible de « celui en cours ».
     */
    protected function inventaireCourant(): ?Inventaire
    {
        return Inventaire::query()
            ->with(['point', 'lignes.article'])
            ->orderByDesc('date_inventaire')
            ->orderByDesc('id')
            ->first();
    }

    /**
     * Les raccourcis de période, en LIENS — `du` et `au` restent dans l'URL,
     * ce qui rend une fiche partageable et rechargeable telle quelle.
     *
     * ⚠ « 7 jours » couvre SEPT jours, aujourd'hui compris (PA-135) : le maître
     * recule de 7 × 86 400 000 ms, ce qui en fait huit une fois les deux bornes
     * incluses.
     *
     * @return list<array{libelle: string, du: string, au: string}>
     */
    protected function raccourcisDePeriode(): array
    {
        $aujourdhui = CarbonImmutable::today();
        $raccourcis = [];

        foreach ([7, 30, 90] as $jours) {
            $raccourcis[] = [
                // Cle LITTERALE par branche : le registre des periodes est ferme
                // (7/30/90/mois) et une cle concatenee serait invisible a la
                // garde i18n — elle ne pourrait plus prouver son existence.
                'libelle' => __(match ($jours) {
                    7 => 'stocks_pwa.inventaires.periode_7',
                    30 => 'stocks_pwa.inventaires.periode_30',
                    90 => 'stocks_pwa.inventaires.periode_90',
                }),
                'du' => $aujourdhui->subDays($jours - 1)->toDateString(),
                'au' => $aujourdhui->toDateString(),
            ];
        }

        $raccourcis[] = [
            'libelle' => __('stocks_pwa.inventaires.periode_mois'),
            'du' => $aujourdhui->startOfMonth()->toDateString(),
            'au' => $aujourdhui->toDateString(),
        ];

        return $raccourcis;
    }

    /**
     * La feuille de comptage : un article par ligne, compté ou non.
     *
     * Le théorique d'une ligne DÉJÀ comptée est celui qui a été figé au
     * comptage — le recalculer donnerait un écart faux dès qu'un mouvement
     * survient pendant la matinée. Celui d'une ligne non comptée vient de la
     * projection groupée de `ConsultationStockService` : une boucle d'appels
     * unitaires ferait une requête par article sur un écran rafraîchi à chaque
     * saisie.
     *
     * @return list<array{article: Article, theorique: string, comptee: string|null, ecart: string|null, valorise: string|null}>
     */
    protected function feuilleDeComptage(
        Inventaire $encours,
        ConsultationStockService $consultation,
        ValorisationStockService $valorisation,
    ): array {
        $comptees = $encours->lignes->keyBy('article_id');
        $feuille = [];

        $projection = $consultation->listerArticles(
            pointId: $encours->point_id,
            parPage: ConsultationStockService::PAR_PAGE_MAX,
        );

        foreach ($projection as $ligne) {
            $comptee = $comptees->get($ligne->article->id);

            $feuille[] = [
                'article' => $ligne->article,
                'theorique' => $comptee === null
                    ? $ligne->stock
                    : (string) $comptee->quantite_theorique,
                'comptee' => $comptee === null ? null : (string) $comptee->quantite_constatee,
                'ecart' => $comptee === null ? null : (string) $comptee->ecart,
                'valorise' => $comptee === null
                    ? null
                    : $valorisation->valoriser($ligne->article, (string) $comptee->ecart),
            ];
        }

        return $feuille;
    }

    /**
     * Le DERNIER inventaire de chaque point, tous statuts confondus — étape 1
     * du maître (`m6-inventaires.html` l.337-376, `rendrePeriodicite()`), le
     * tableau « Cycle d'inventaire par magasin ».
     *
     * ⚠ PAS « le dernier CLÔTURÉ », comme le calcule le maître
     * (`stock-engine.js` l.448 : « L'échéance se calcule depuis le dernier
     * inventaire CLÔTURÉ »). Le schéma serveur ne porte AUCUN statut
     * d'inventaire (PA-150, voir le docblock de cette classe) : rien ne
     * distingue ici un inventaire clos d'un comptage abandonné en cours de
     * route. La colonne du tableau est donc étiquetée « Dernier inventaire
     * RÉEL », pas « clôturé » — reprendre le mot du maître affirmerait une
     * garantie que la donnée ne tient pas.
     *
     * @return array<string, Inventaire> point_id => inventaire le plus récent
     */
    private function dernierInventaireParPoint(): array
    {
        $parPoint = [];

        foreach (Inventaire::query()->orderByDesc('date_inventaire')->orderByDesc('id')->get() as $inventaire) {
            $cle = (string) $inventaire->point_id;

            if (! isset($parPoint[$cle])) {
                $parPoint[$cle] = $inventaire;
            }
        }

        return $parPoint;
    }

    public function render(
        FicheStockService $fiches,
        ConsultationStockService $consultation,
        ValorisationStockService $valorisation,
    ): View {
        $onglet = $this->ongletValide();
        $articles = Article::query()->orderBy('libelle')->get();

        // `articleId` vide = « Tous les articles » (PO 06/09/2026). Aucun
        // repli sur le premier article : il rendrait une fiche unitaire sous
        // un filtre qui annonce l'ensemble.
        $tousLesArticles = $this->articleId === '';
        $article = $tousLesArticles ? null : $articles->firstWhere('id', $this->articleId);

        // 02/09/2026 — les trois panneaux d'onglet sont rendus a chaque GET
        // (l'inactif porte `hidden`, garde G5) : leurs donnees se calculent
        // donc toujours, plus seulement pour l'onglet actif.
        $fiche = $article instanceof Article
            ? $fiches->pourArticle($article, $this->debut, $this->fin, $this->pointFiltre())
            : null;

        $ficheConsolidee = $tousLesArticles
            ? $fiches->pourTousLesArticles($this->debut, $this->fin, $this->pointFiltre())
            : null;

        $encours = $this->inventaireCourant();

        $feuille = $encours instanceof Inventaire
            ? $this->feuilleDeComptage($encours, $consultation, $valorisation)
            : [];

        return view('pwa.stocks.inventaires', array_merge($this->socle(), [
            'onglet' => $onglet,
            'articles' => $articles,
            'articleSelectionne' => $article,
            'tousLesArticles' => $tousLesArticles,
            'ficheConsolidee' => $ficheConsolidee,
            'points' => PointStockage::query()->orderBy('libelle')->get(),
            'fiche' => $fiche,
            'raccourcis' => $this->raccourcisDePeriode(),
            'inventaireEnCours' => $encours,
            'dernierInventaireParPoint' => $encours === null
                ? $this->dernierInventaireParPoint()
                : [],
            'feuille' => $feuille,
            'nonComptes' => count(array_filter(
                $feuille,
                static fn (array $ligne): bool => $ligne['comptee'] === null,
            )),
            'historique' => Inventaire::query()
                ->with(['point', 'lignes', 'utilisateur'])
                ->orderByDesc('date_inventaire')
                ->orderByDesc('id')
                ->limit(self::PLAFOND_HISTORIQUE)
                ->get(),
        ]))->layout('layouts.pwa', ['module' => self::MODULE]);
    }
}

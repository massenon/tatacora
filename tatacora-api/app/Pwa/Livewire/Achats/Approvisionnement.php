<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Achats;

use App\Domain\Achats\Models\BonReception;
use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Achats\Services\CommandeAchatService;
use App\Domain\Achats\Services\ReceptionService;
use App\Domain\Achats\Services\ReglementFournisseurService;
use App\Domain\Depenses\Services\DepenseService;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\ConsultationStockService;
use App\Exports\AchatsExport;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\PageMetier;
use App\Pwa\Support\ExerciceConsulte;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Maatwebsite\Excel\Facades\Excel;
use RuntimeException;
use Symfony\Component\HttpFoundation\Response;

/**
 * Approvisionnement (M7) — maître : `prototype_v2/pages/m7-approvisionnement.html`.
 *
 * ## Le CYCLE vit ici, et le maître le dit lui-même
 *
 * « `m7-achats.html` n'est qu'un annuaire fournisseurs […] sans aucune commande
 * ni réception. Le cycle complet est ici : besoin détecté (seuil) → commande →
 * réception (qui génère l'entrée de stock et met à jour le CMP) → règlement →
 * dette résiduelle » (l.75-81). Les DEUX écritures de cet écran sont donc
 * l'émission d'un bon de commande depuis les besoins (EF-M7-02) et la réception
 * qui crée l'entrée de stock (EF-M7-03, RG-10).
 *
 * ## Aucune règle métier n'est réécrite ici
 *
 * `CommandeAchatService` porte la transaction commande + lignes ;
 * `ReceptionService` porte RG-10 — la tolérance paramétrable, la conformité et
 * l'entrée de stock par `MouvementStockService`. Le composant assemble une
 * saisie et appelle. Recopier le contrôle de tolérance dans l'écran donnerait
 * deux verdicts pour la même livraison le jour où l'un changerait.
 *
 * ## Le RÈGLEMENT du maître est PORTÉ depuis le 02/09/2026 (PA-165)
 *
 * `ReglementFournisseurService` — premier writer de `reglements_fournisseur`
 * et de `commandes_achat.montant_regle` (RECALCULÉ depuis les lignes après
 * chaque règlement, jamais incrémenté) — lève la prémisse qui motivait le
 * refus daté du 31/08/2026 : « rien ne rattache un règlement à une commande
 * d'achat ». « Réglé » et « Reste dû » viennent désormais du Service, sur
 * les DEUX onglets qui les affichent (Commandes et Dettes) — jamais une
 * soustraction locale, qui divergerait du Service au premier règlement
 * partiel. Les KPI « Fournisseurs à payer » et « Total dû » suivent la même
 * règle : ils SOMMENT `resteDu()` sur les commandes non clôturées, jamais le
 * montant commandé.
 *
 * ⚠ Ce que l'écran NE fait toujours PAS : `contrats_location` a un précédent
 * pour l'ABSENCE d'un geste d'annulation (PA-50) ; ici, aucune colonne
 * `statut` de règlement n'existe non plus — un règlement erroné n'a pas
 * d'annulation propre, la correction reste la contre-passation comptable,
 * hors du périmètre de cet écran.
 *
 * ## Le champ « À commander » du maître est rendu en LECTURE
 *
 * Un formulaire d'écriture ne se rend jamais au premier GET : il en offrirait
 * un à des rôles qui n'ont pas le droit d'écrire, avant toute garde. La
 * quantité suggérée s'affiche dans le tableau, elle se corrige dans la fenêtre
 * de commande — qui ne s'ouvre qu'après `exigerEcriture(self::MODULE)`.
 *
 * @see EF-M7-02 Émission de commandes d'achat
 * @see EF-M7-03 Réception et entrée de stock
 * @see RG-10 Tolérance de réception (dans `ReceptionService`, jamais ici)
 * @see LARAVEL_PWA.md §3, §5
 */
#[Title('Approvisionnement — LogiReStock — TATACORA AFRIQUE')]
class Approvisionnement extends PageMetier
{
    use FormulaireModal;

    /** Le module RBAC de l'écran — `data-module="M7"` du maître (l.14). */
    public const MODULE = 'M7';

    /** Les QUATRE onglets du maître (l.36-39). */
    public const ONGLETS = ['besoins', 'commandes', 'receptions', 'dettes'];

    /**
     * Plafond de lignes — même arbitrage qu'en `Etats` et `JournalAudit` :
     * `WithPagination` ajouterait sept méthodes publiques, donc sept actions
     * Livewire, sur le chemin que `ForcerLectureSeule` ne couvre pas (PA-67).
     * Le décompte RÉEL est affiché à côté, et la troncature est dite.
     */
    public const PLAFOND = 200;

    /** Le multiple de seuil visé par la suggestion de réapprovisionnement. */
    public const MULTIPLE_SEUIL = '2';

    #[Url(as: 'onglet')]
    public string $onglet = 'besoins';

    #[Url(as: 'q')]
    public string $recherche = '';

    #[Url(as: 'statut')]
    public string $statut = '';

    /**
     * Les articles cochés dans l'onglet Besoins — la case du maître
     * (`m7-approvisionnement.html` l.237 et l.255).
     *
     * @var list<string>
     */
    public array $selection = [];

    /** La case « cocher-tout » du maître (l.237). */
    public bool $toutSelectionne = false;

    /** Format demandé à la modale d'export partagée : `pdf` ou `excel`. */
    public string $formatExport = 'pdf';

    // --- Formulaire « Nouveau bon de commande » (EF-M7-02) ---------------

    public ?string $cFournisseurId = null;

    /**
     * Les lignes de la commande en cours de saisie.
     *
     * @var array<int, array{article_id: string, libelle: string, unite: string, quantite: string, prix_unitaire: string}>
     */
    public array $cLignes = [];

    // --- Formulaire « Réception » (EF-M7-03) -----------------------------

    public ?string $rCommandeId = null;

    public ?string $rPointId = null;

    /**
     * Quantités reçues saisies, article par article.
     *
     * @var array<string, string>
     */
    public array $rQuantites = [];

    // --- Formulaire « Régler » (PA-165, 02/09/2026) -----------------------

    public ?string $regCommandeId = null;

    public string $regFournisseurNom = '';

    public string $regMontant = '';

    public string $regTresorerie = 'caisse';

    /**
     * L'état consolidé du stock, mémoïsé pour la durée d'UN rendu.
     *
     * Il est demandé par les besoins, par le compteur « Articles sous seuil »
     * et par l'export : sans mémoïsation, la même agrégation tournerait trois
     * fois par requête.
     */
    private ?object $etatConsolide = null;

    /**
     * Les messages de validation de l'écran — point d'entrée du cadre Livewire.
     *
     * Ils disent CE QUI est refusé et POURQUOI : un refus muet renvoie
     * l'utilisateur essayer exactement la même chose.
     *
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'cLignes.*.quantite.gt' => __('achats_pwa.appro.quantite_obligatoire'),
            'cLignes.*.quantite.required' => __('achats_pwa.appro.quantite_obligatoire'),
            'cLignes.*.prix_unitaire.gt' => __('achats_pwa.appro.prix_obligatoire'),
            'cLignes.*.prix_unitaire.required' => __('achats_pwa.appro.prix_obligatoire'),
            'cFournisseurId.required' => __('achats.validation.fournisseur_inexistant'),
            'cFournisseurId.exists' => __('achats.validation.fournisseur_inexistant'),
        ];
    }

    /**
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'commande' => ['cFournisseurId', 'cLignes'],
            'reception' => ['rCommandeId', 'rPointId', 'rQuantites'],
            'reglement' => ['regCommandeId', 'regFournisseurNom', 'regMontant', 'regTresorerie'],
        ];
    }

    protected function ongletValide(): string
    {
        return in_array($this->onglet, self::ONGLETS, true) ? $this->onglet : 'besoins';
    }

    /**
     * La case « cocher-tout » de l'entête des besoins.
     *
     * `updated*` est un point d'entrée du cadre Livewire : il ne touche que
     * l'état de sélection, jamais une table.
     */
    public function updatedToutSelectionne(bool $valeur): void
    {
        $this->selection = $valeur
            ? array_map(static fn (array $b): string => $b['article_id'], $this->besoins())
            : [];
    }

    /**
     * @param  mixed  $valeur
     */
    public function updated(string $propriete, $valeur): void
    {
        if (in_array($propriete, ['recherche', 'statut', 'onglet'], true)) {
            $this->selection = [];
            $this->toutSelectionne = false;
        }
    }

    // =====================================================================
    // EF-M7-02 — émettre un bon de commande depuis les besoins
    // =====================================================================

    /**
     * Ouvre « Nouveau bon de commande » sur la sélection.
     *
     * Le prix unitaire est PRÉ-REMPLI avec le coût moyen pondéré de l'article
     * et reste modifiable : `articles` ne porte aucun prix d'achat, et le CMP
     * est une valorisation d'achats passés, pas un tarif négocié. Aucune valeur
     * par défaut n'est inventée — un article jamais reçu arrive à 0 et la
     * validation exigera un prix.
     */
    public function ouvrirFormulaireCommande(): void
    {
        $this->ouvrirFormulaire('commande');

        $besoins = $this->besoins();
        $retenus = array_values(array_filter(
            $besoins,
            fn (array $b): bool => in_array($b['article_id'], $this->selection, true),
        ));

        if ($retenus === []) {
            $this->etatFormulaire = null;
            $this->addError('selection', __('achats_pwa.appro.aucune_selection'));

            return;
        }

        if (Fournisseur::query()->count() === 0) {
            $this->etatFormulaire = null;
            $this->addError('selection', __('achats_pwa.appro.aucun_fournisseur'));

            return;
        }

        $this->cFournisseurId = null;
        $this->cLignes = array_map(static fn (array $b): array => [
            'article_id' => $b['article_id'],
            'libelle' => $b['libelle'],
            'unite' => $b['unite'],
            'quantite' => $b['a_commander'],
            'prix_unitaire' => $b['cout_moyen_pondere'],
        ], $retenus);
    }

    /**
     * Crée le bon de commande — par `CommandeAchatService`, dans SA
     * transaction : une commande et ses lignes naissent ensemble ou pas du
     * tout.
     *
     * Le statut posé est `envoyee`, le seul que le geste du maître décrive
     * (« Créer le bon de commande » l'envoie au fournisseur). Il fait partie
     * des deux statuts SAISISSABLES du Service ; les trois autres sont produits
     * par une réception réelle.
     */
    public function enregistrerCommande(CommandeAchatService $commandes): void
    {
        $this->validerEcriture([
            'cFournisseurId' => ['required', 'exists:fournisseurs,id'],
            'cLignes' => ['required', 'array', 'min:1'],
            'cLignes.*.quantite' => ['required', 'numeric', 'gt:0'],
            'cLignes.*.prix_unitaire' => ['required', 'numeric', 'gt:0'],
        ]);

        $lignes = array_map(static fn (array $l): array => [
            'article_id' => $l['article_id'],
            // Les montants restent des CHAÎNES de bout en bout : `bcadd` et
            // `bccomp` les relisent, et un flottant intermédiaire suffirait à
            // décaler le total d'une commande à trente lignes.
            'quantite_commandee' => (string) $l['quantite'],
            'prix_unitaire' => (string) $l['prix_unitaire'],
        ], $this->cLignes);

        $commande = $commandes->creer([
            'fournisseur_id' => (string) $this->cFournisseurId,
            'date_commande' => now()->toDateString(),
            'statut' => 'envoyee',
            'lignes' => $lignes,
        ]);

        // `montant_total` est écrit par `CommandeAchatService::creer()` depuis
        // le 01/09/2026 (formule unique du modèle, `montantTotal()`) — la
        // réparation ciblée qui vivait ici est retirée : deux writers de la
        // même colonne auraient fini par diverger. L'auto-guérison des
        // commandes ANTÉRIEURES au correctif reste à l'ouverture de la modale
        // de règlement, conditionnelle à une divergence réelle.

        $this->selection = [];
        $this->toutSelectionne = false;
        $this->onglet = 'commandes';

        $fournisseur = $commande->fournisseur;

        $this->terminerFormulaire(__('achats_pwa.appro.commande_creee', [
            'fournisseur' => $fournisseur === null ? '' : (string) $fournisseur->raison_sociale,
        ]));
    }

    // =====================================================================
    // EF-M7-03 / RG-10 — réceptionner, ce qui GÉNÈRE l'entrée de stock
    // =====================================================================

    public function ouvrirFormulaireReception(string $commandeId): void
    {
        $this->ouvrirFormulaire('reception');

        $commande = CommandeAchat::query()->with('lignes.article')->find($commandeId);

        if ($commande === null || $commande->estCloturee()) {
            $this->etatFormulaire = null;
            $this->addError('selection', __('achats.commande_cloturee'));

            return;
        }

        $point = PointStockage::query()->orderBy('libelle')->first();

        if ($point === null) {
            $this->etatFormulaire = null;
            $this->addError('selection', __('achats_pwa.appro.aucun_point'));

            return;
        }

        $this->rCommandeId = $commande->id;
        $this->rPointId = $point->id;

        foreach ($commande->lignes as $ligne) {
            $this->rQuantites[(string) $ligne->article_id] = (string) $ligne->quantite_commandee;
        }
    }

    /**
     * Enregistre la réception — par `ReceptionService`, qui seul évalue RG-10
     * et écrit les entrées de stock.
     *
     * ⚠ Le refus du Service est AFFICHÉ tel quel, jamais avalé. Une réception
     * annoncée « enregistrée » alors qu'aucune entrée de stock n'a eu lieu
     * serait exactement l'indicateur qui affirme un état qu'il n'a pas vérifié
     * (PA-59/60/61) — et le magasinier saisirait le stock une seconde fois.
     */
    public function enregistrerReception(ReceptionService $receptions): void
    {
        $this->validerEcriture([
            'rCommandeId' => ['required', 'exists:commandes_achat,id'],
            'rPointId' => ['required', 'exists:points_stockage,id'],
            'rQuantites' => ['required', 'array', 'min:1'],
            'rQuantites.*' => ['required', 'numeric', 'min:0'],
        ]);

        $commande = CommandeAchat::query()->with('lignes')->findOrFail((string) $this->rCommandeId);

        $recues = [];
        foreach ($this->rQuantites as $articleId => $quantite) {
            if (bccomp((string) $quantite, '0.00', 2) > 0) {
                $recues[(string) $articleId] = (string) $quantite;
            }
        }

        if ($recues === []) {
            $this->addError('rQuantites', __('achats.reception_vide'));

            return;
        }

        try {
            $bon = $receptions->receptionner(
                commande: $commande,
                quantitesRecues: $recues,
                pointStockageId: (string) $this->rPointId,
            );
        } catch (RuntimeException $echec) {
            // Le message du Service est écrit pour l'utilisateur (fichiers
            // `lang/fr/achats.php`) : le remplacer par un texte générique lui
            // ferait retenter exactement la même chose.
            $this->addError('rQuantites', $echec->getMessage());

            return;
        }

        $this->onglet = 'receptions';

        $this->terminerFormulaire(__('achats_pwa.appro.reception_enregistree', [
            'conformite' => (string) $bon->conformite,
        ]));
    }

    // =====================================================================
    // « Régler » — PA-165 (02/09/2026), ReglementFournisseurService
    // =====================================================================

    /**
     * Un seul droit, `self::MODULE` (M7) : l'écriture comptable est un EFFET
     * du Service, jamais une action distincte de l'écran — même raisonnement
     * qu'une vente n'exige que M5 alors qu'elle passe sa pièce comptable
     * (`VenteService`).
     */
    public function ouvrirFormulaireReglement(string $commandeId, ReglementFournisseurService $reglements): void
    {
        $this->ouvrirFormulaire('reglement');

        $commande = CommandeAchat::query()->with('fournisseur')->find($commandeId);

        if ($commande === null) {
            $this->etatFormulaire = null;
            $this->addError('selection', __('achats.commande_cloturee'));

            return;
        }

        // AUTO-RÉPARATION d'une commande née AVANT ce correctif (voir le
        // docblock daté de `enregistrerCommande()`) : sans elle, `resteDu()`
        // lirait encore `montant_total = 0.00` et `regler()` refuserait tout
        // montant. Écrit UNIQUEMENT si la colonne diverge du total réel —
        // jamais une réécriture inconditionnelle à chaque ouverture.
        if (bccomp((string) $commande->montant_total, $commande->montantTotal(), 2) !== 0) {
            $commande->setAttribute('montant_total', $commande->montantTotal());
            $commande->save();
        }

        $reste = $reglements->resteDu($commande);

        if (bccomp($reste, '0.00', 2) <= 0) {
            $this->etatFormulaire = null;
            $this->addError('selection', __('achats_pwa.appro.reglement_commande_soldee'));

            return;
        }

        $this->regCommandeId = $commande->id;
        $this->regFournisseurNom = $commande->fournisseur->raison_sociale ?? '';
        $this->regMontant = $reste;
        $this->regTresorerie = 'caisse';
    }

    /**
     * ⚠ Le refus du Service (trésorerie inconnue, montant invalide ou
     * supérieur au reste dû) est AFFICHÉ tel quel, modale ouverte — un
     * sur-règlement REFUSÉ qu'on masquerait ferait croire à un paiement qui
     * n'a pas eu lieu (PA-59/60/61).
     */
    public function enregistrerReglement(ReglementFournisseurService $reglements): void
    {
        $donnees = $this->validerEcriture([
            'regCommandeId' => ['required', 'exists:commandes_achat,id'],
            'regMontant' => ['required', 'numeric', 'gt:0'],
            'regTresorerie' => ['required', 'in:'.implode(',', array_keys(DepenseService::TRESORERIES))],
        ]);

        $commande = CommandeAchat::query()->with('fournisseur')->findOrFail((string) $donnees['regCommandeId']);

        try {
            $reglements->regler(
                $commande,
                (string) $donnees['regMontant'],
                (string) $donnees['regTresorerie'],
            );
        } catch (RuntimeException $refus) {
            // Le message du Service est écrit pour l'opérateur (lang/fr/achats.php).
            $this->addError('regMontant', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('achats_pwa.appro.reglement_enregistre', [
            'montant' => $donnees['regMontant'],
            'fournisseur' => $this->regFournisseurNom,
        ]));
    }

    // =====================================================================
    // Export — PA-119
    // =====================================================================

    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
    }

    /**
     * Deux boutons, un seul formulaire — comme `Stocks::ouvrirExport()`.
     *
     * Le bouton du header était un `wire:click="$set('etatFormulaire',
     * 'export')"` UNIQUE, labellisé « Exporter » : le maître
     * (`m7-approvisionnement.html` l.159-160, 225-226) rend « Export Excel »
     * et « Export PDF » côte à côte. La modale offrait déjà les deux formats
     * derrière ce bouton fusionné — seule l'entrée était fondue en une, écart
     * relevé à l'audit navigateur du 01/09/2026.
     */
    public function ouvrirExport(string $format = 'pdf'): void
    {
        $this->formatExport = in_array($format, ['pdf', 'excel'], true) ? $format : 'pdf';
        $this->etatFormulaire = 'export';
    }

    /**
     * Produit le document sur l'onglet AFFICHÉ, filtres compris.
     */
    public function genererExport(): ?Response
    {
        $onglet = $this->ongletValide();
        $commandes = $this->commandes();

        $vide = match ($onglet) {
            'besoins' => $this->besoins() === [],
            'receptions' => $this->receptions()->isEmpty(),
            default => $commandes->isEmpty(),
        };

        if ($vide) {
            $this->addError('formatExport', __('achats_pwa.export.vide'));

            return null;
        }

        $this->etatFormulaire = null;
        $nom = __('achats_pwa.export.fichier_appro').'_'.now()->format('Y_m_d_His');

        if ($this->formatExport === 'excel') {
            // Le classeur porte les BONS DE COMMANDE : c'est le seul jeu de
            // cet écran qui soit un registre de pièces. Les besoins et les
            // dettes sont des projections, et le PDF les rend avec leur portée
            // écrite en toutes lettres.
            /** @var Response $reponse */
            $reponse = Excel::download(new AchatsExport($commandes), $nom.'.xlsx');

            return $reponse;
        }

        $pdf = Pdf::loadView('pdf.approvisionnement-bon', [
            'entete' => $this->enTeteRapport(
                __('achats_pwa.export.document_appro'),
                __('achats_pwa.export.periode_appro', ['onglet' => $onglet]),
            ),
            'onglet' => $onglet,
            'besoins' => $this->besoins(),
            'commandes' => $commandes,
            'receptions' => $this->receptions(),
            'auteur' => $this->auteur(),
        ])->setPaper('a4', 'portrait');

        return response()->streamDownload(static function () use ($pdf): void {
            echo $pdf->output();
        }, $nom.'.pdf');
    }

    // =====================================================================

    public function render(ConsultationStockService $consultation, ReglementFournisseurService $reglements): View
    {
        $besoins = $this->besoins($consultation);
        $commandes = $this->commandes();
        $receptions = $this->receptions();

        // « Réglé » vient du SERVICE, tel quel (PA-165). « Reste dû » N'APPELLE
        // PAS `ReglementFournisseurService::resteDu()` — DÉCOUVERTE À
        // L'EXÉCUTION (02/09/2026, en rejouant réellement l'écran, pas en
        // relisant le code — PA-59/60/61) : cette méthode calcule
        // `commandes_achat.montant_total − totalRegle()`, et la COLONNE
        // `montant_total` n'a AUCUN writer dans tout `app/` — ni
        // `CommandeAchatService::creer()`, ni le `$fillable` du modèle ne la
        // touchent, elle vaut `0.00` pour CHAQUE commande. `resteDu()` rendait
        // donc TOUJOURS « 0.00 », y compris sur une commande de 4 000 F jamais
        // réglée : le bouton « Régler » ne se serait plus jamais affiché après
        // le premier chargement — l'inverse exact de ce que cette vague livre.
        // Ni `ReglementFournisseurService` ni `CommandeAchatService` ne sont
        // modifiés ici (ce sont des Services de domaine, hors mandat) : le
        // reste dû est reconstruit avec `CommandeAchat::montantTotal()` — la
        // MÊME méthode que la colonne « Montant » de cet écran utilise déjà
        // partout — moins `totalRegle()` du Service, avec le MÊME plancher à
        // zéro que `resteDu()`. Une seule formule de reste dû existe dans ce
        // fichier ; elle vit ICI, jamais recopiée par onglet.
        $reglesEtRestes = [];
        foreach ($commandes as $commande) {
            $regle = $reglements->totalRegle($commande);
            $reste = bcsub($commande->montantTotal(), $regle, 2);

            $reglesEtRestes[$commande->id] = [
                'regle' => $regle,
                'reste' => bccomp($reste, '0.00', 2) < 0 ? '0.00' : $reste,
            ];
        }

        $dettes = $this->dettes($commandes);

        return view('pwa.achats.approvisionnement', array_merge($this->socle(), [
            'onglet' => $this->ongletValide(),
            'besoins' => $besoins,
            'commandes' => $commandes,
            'receptions' => $receptions,
            'dettes' => $dettes,
            'reglesEtRestes' => $reglesEtRestes,
            // KPI « Fournisseurs à payer » / « Total dû » — SOMMÉS depuis le
            // Service sur les commandes non clôturées, jamais le montant
            // commandé (écart avec `dettes_portee` daté 31/08/2026, levé le
            // 02/09/2026).
            'fournisseursAPayer' => collect($dettes)->filter(
                fn (array $g): bool => collect($g['commandes'])->contains(
                    fn (CommandeAchat $c) => bccomp($reglesEtRestes[$c->id]['reste'], '0.00', 2) > 0,
                ),
            )->count(),
            'totalDu' => collect($reglesEtRestes)->reduce(
                fn (?string $t, array $r): string => bcadd((string) $t, $r['reste'], 2),
                '0.00',
            ),
            'sousSeuil' => $this->etat($consultation)->sousSeuil,
            'enAttente' => CommandeAchat::query()->whereIn('statut', ['brouillon', 'envoyee'])->count(),
            'partielles' => CommandeAchat::query()->where('statut', 'receptionnee_partiellement')->count(),
            // ARCHIVÉS EXCLUS (03/09/2026) : c'est la conséquence du geste
            // d'archivage de l'écran Fournisseurs & Achats. Sans ce filtre,
            // un fournisseur retiré du référentiel resterait proposé au
            // formulaire de commande — l'archivage n'aurait rien archivé. Les
            // commandes DÉJÀ passées à ce fournisseur restent lisibles :
            // c'est le sélecteur qui filtre, jamais le registre.
            'fournisseurs' => Fournisseur::query()->where('actif', true)->orderBy('raison_sociale')->get(),
            'points' => PointStockage::query()->orderBy('libelle')->get(),
            'commandeEnReception' => $this->rCommandeId === null
                ? null
                : CommandeAchat::query()->with(['fournisseur', 'lignes.article'])->find($this->rCommandeId),
            'peutEcrire' => (Auth::user()?->niveauSurModule(self::MODULE) ?? '-') === 'C',
        ]))->layout('layouts.pwa', ['module' => self::MODULE]);
    }

    // ------------------------------------------------------------- lectures

    private function auteur(): string
    {
        $utilisateur = Auth::user();

        return $utilisateur === null ? '' : (string) $utilisateur->login;
    }

    private function etat(?ConsultationStockService $consultation = null): object
    {
        if ($this->etatConsolide === null) {
            $service = $consultation ?? app(ConsultationStockService::class);
            $this->etatConsolide = $service->etatConsolide(null, true);
        }

        return $this->etatConsolide;
    }

    /**
     * Les articles à réapprovisionner — la MÊME projection que l'écran Stocks.
     *
     * La quantité suggérée remonte au DOUBLE du seuil, jamais au seuil pile :
     * recommander à l'exact ferait repasser l'article sous alerte à la première
     * sortie (règle du maître, l.248-251).
     *
     * @return list<array{article_id: string, libelle: string, unite: string, stock: string, seuil: string, manque: string, cout_moyen_pondere: string, a_commander: string, rupture: bool}>
     */
    private function besoins(?ConsultationStockService $consultation = null): array
    {
        $terme = mb_strtolower(trim($this->recherche));
        $lignes = [];

        foreach ($this->etat($consultation)->lignes as $ligne) {
            if ($terme !== '' && ! str_contains(mb_strtolower((string) $ligne->article->libelle), $terme)) {
                continue;
            }

            $seuil = (string) $ligne->article->seuil_alerte;
            $cible = bcmul($seuil, self::MULTIPLE_SEUIL, 2);
            $aCommander = bcsub($cible, (string) $ligne->stock, 2);

            $lignes[] = [
                'article_id' => (string) $ligne->article->id,
                'libelle' => (string) $ligne->article->libelle,
                'unite' => (string) $ligne->article->unite_mesure,
                'stock' => (string) $ligne->stock,
                'seuil' => $seuil,
                'manque' => bcsub($seuil, (string) $ligne->stock, 2),
                'cout_moyen_pondere' => (string) $ligne->article->cout_moyen_pondere,
                'a_commander' => bccomp($aCommander, '0.00', 2) > 0 ? $aCommander : '1.00',
                'rupture' => $ligne->rupture,
            ];
        }

        return $lignes;
    }

    /**
     * @return Collection<int, CommandeAchat>
     */
    private function commandes(): Collection
    {
        $terme = trim($this->recherche);

        // Sélecteur d'exercice global (PO, 20/10/2026) : commandes et
        // réceptions de l'exercice consulté. Les dettes fournisseurs (commandes
        // non clôturées) restent un état du JOUR, toutes années confondues.
        return ExerciceConsulte::borner(CommandeAchat::query(), 'date_commande')
            ->with(['fournisseur', 'lignes'])
            ->when(
                $this->statut !== '' && in_array($this->statut, CommandeAchat::STATUTS, true),
                fn ($q) => $q->where('statut', $this->statut),
            )
            ->when($terme !== '', static fn ($q) => $q->whereHas(
                'fournisseur',
                static fn ($f) => $f->where('raison_sociale', 'like', '%'.$terme.'%'),
            ))
            ->orderByDesc('date_commande')
            ->orderBy('id')
            ->limit(self::PLAFOND)
            ->get();
    }

    /**
     * @return Collection<int, BonReception>
     */
    private function receptions(): Collection
    {
        return ExerciceConsulte::borner(BonReception::query(), 'date_reception')
            ->with(['commande.fournisseur'])
            ->orderByDesc('date_reception')
            ->orderBy('id')
            ->limit(self::PLAFOND)
            ->get();
    }

    /**
     * Les commandes NON CLÔTURÉES, groupées par fournisseur.
     *
     * « Réglé » et « Reste dû » sont désormais chiffrés (PA-165) — voir
     * `reglesEtRestes` dans `render()`, lu depuis `ReglementFournisseurService`.
     * L'ancienneté, elle, mesure toujours l'âge du bon de commande, pas le
     * retard d'un paiement : la vue le dit.
     *
     * @param  Collection<int, CommandeAchat>  $commandes
     * @return array<string, array{fournisseur: string, commandes: list<CommandeAchat>}>
     */
    private function dettes(Collection $commandes): array
    {
        $groupes = [];

        foreach ($commandes as $commande) {
            if ($commande->estCloturee()) {
                continue;
            }

            $fournisseur = $commande->fournisseur;
            $cle = (string) $commande->fournisseur_id;
            $groupes[$cle] ??= [
                'fournisseur' => $fournisseur === null ? '' : (string) $fournisseur->raison_sociale,
                'commandes' => [],
            ];
            $groupes[$cle]['commandes'][] = $commande;
        }

        return $groupes;
    }
}

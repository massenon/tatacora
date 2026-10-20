<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Comptabilite;

use App\Domain\Comptabilite\Exceptions\EtatTropVolumineuxException;
use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\Immobilisation;
use App\Domain\Comptabilite\Services\AnalytiqueService;
use App\Domain\Comptabilite\Services\ArchiveClotureService;
use App\Domain\Comptabilite\Services\BalanceGeneraleService;
use App\Domain\Comptabilite\Services\BilanService;
use App\Domain\Comptabilite\Services\ClotureExerciceService;
use App\Domain\Comptabilite\Services\CompteResultatService;
use App\Domain\Comptabilite\Services\EtatClotureService;
use App\Domain\Comptabilite\Services\ExerciceComptableService;
use App\Domain\Comptabilite\Services\GrandLivreService;
use App\Domain\Comptabilite\Services\ImmobilisationService;
use App\Domain\Comptabilite\Services\IndicateursComptablesService;
use App\Domain\Comptabilite\Services\JournalGeneralService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Domain\Comptabilite\Services\PlanComptableService;
use App\Exports\ComptabiliteJournalExport;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Maatwebsite\Excel\Facades\Excel;
use RuntimeException;
use Symfony\Component\HttpFoundation\BinaryFileResponse;
use Symfony\Component\HttpFoundation\Response;
use Throwable;

/**
 * Hub Comptabilite SYSCOHADA — `prototype_v2/pages/m10-syscohada.html`.
 *
 * Il sert AUSSI de page d'atterrissage M10 : `prototype_v2/pages/m10-comptabilite.html`
 * (voir « La page d'atterrissage du maitre » plus bas).
 *
 * Le maitre pose un bandeau de six indicateurs, une barre de dix onglets, une
 * barre de filtres et une zone de contenu. Les six indicateurs viennent
 * d'`IndicateursComptablesService`, jamais d'une agregation ecrite ici
 * (`LARAVEL_PWA.md` §3, et PA-121 : deux formules pour la meme grandeur
 * finissent par afficher deux verites sur le meme ecran).
 *
 * ## VAGUE E (01/09/2026) — TROIS DES CINQ ECARTS CI-DESSOUS SONT REFERMES
 *
 * Le lot precedent avait omis l'onglet « Passer ecriture », l'onglet
 * « Immobilisations » et les trois modales d'ecriture du hub, chacun motive
 * par un texte daté que la section suivante conserve **barré plutôt que
 * supprimé** — la regle du depot (voir PA-102, PA-118…) est qu'une decision
 * revenue en arriere doit rester lisible, pas disparaitre comme si elle
 * n'avait jamais existe. Trois choses ont rendu le refus caduc, toutes
 * commandees par le Product Owner (Vague E) :
 *
 *  1. La liste FERMEE de `PwaActionsReluesTest` n'est plus un obstacle : elle
 *     se met a jour AVEC ce lot (`Hub::class => [...]` ci-dessous porte
 *     desormais dix-sept methodes), pas apres.
 *  2. `numero_piece` existe desormais sur `ecritures_comptables`
 *     (migration `ajouter_numero_piece_aux_ecritures`) — PA-52 partiellement
 *     refermee.
 *  3. La table `immobilisations` existe desormais (migration
 *     `create_immobilisations`) et `ImmobilisationService` calcule son plan
 *     d'amortissement a la demande.
 *
 * ## Ce qui n'est TOUJOURS PAS porte, et pourquoi — Article 8
 *
 * ### 1. ~~L'onglet « Passer ecriture » — OMIS~~ PORTE le 01/09/2026
 *
 * Le formulaire du maitre (`m10-syscohada.js` `vueSaisie()`) est transcrit,
 * mais PAS comme un bloc toujours visible : la doctrine `RefuseLaSaisie`
 * interdit qu'un `<form>` se rende au premier GET, et l'onglet redevient
 * l'onglet par defaut (voir n. 2). L'ecart de MECANISME est explicitement
 * accepte par le Product Owner (brief de vague, §« Dérogations actées ») :
 * l'onglet ouvre sur une introduction et un bouton « Nouvelle écriture », qui
 * ouvre la modale portant le formulaire complet — Journal, Date, Libellé,
 * lignes dynamiques Compte/Libellé/Centre/Débit/Crédit, équilibre affiché en
 * lecture, deux boutons (brouillon / valider). Les quatre actions publiques
 * que l'ancien motif annoncait comme le vrai obstacle sont ci-dessous :
 * `ouvrirFormulairePiece`, `ajouterLignePiece`, `retirerLignePiece`,
 * `enregistrerPieceBrouillon`, `enregistrerPieceValidee` (une de plus que
 * prevu : brouillon et validation sont deux actions distinctes, comme
 * `PasserEcritureService::passer()`/`passerEtValider()`).
 *
 * ### 2. L'onglet actif par defaut redevient « saisie »
 *
 * ~~ECART DELIBERE — l'onglet du maitre n'existait pas ici, journal ouvrait
 * a sa place.~~ Caduc : l'onglet existe desormais, `ONGLET_DEFAUT` reprend la
 * valeur du maitre (`m10-syscohada-init.js` l.234). Consequence a garder en
 * tete : l'ancien `exporterExcel()` visait `ONGLET_DEFAUT` pour reconnaitre l'onglet
 * Journal — les deux notions divergent maintenant, une constante dediee
 * (`ONGLET_EXPORT_EXCEL`) les separe.
 *
 * ### 3. ~~L'onglet « Immobilisations » — OMIS~~ PORTE le 01/09/2026
 *
 * La table `immobilisations` existe (migration `create_immobilisations`,
 * Vague E) et `ImmobilisationService` calcule le plan d'amortissement lineaire
 * a la demande, jamais stocke. Deux ecarts au maitre restent, nommes dans le
 * docblock d'`ImmobilisationService` : aucun centre d'affectation (colonne
 * absente du schema commande pour ce lot) et aucune ecriture de dotation
 * (comptes 681/28x non verifies).
 *
 * ### 4. Trois filtres de la barre — TOUJOURS OMIS
 *
 * ECART DELIBERE — `m10-syscohada.html` l.86-94
 * Le maitre : une recherche libre, un intervalle de dates (`du` / `au`) et un
 * selecteur de centre analytique.
 * Ici : ces trois controles ne sont pas rendus.
 * Raison : aucun Service de M10 n'accepte de date, de terme ni de centre —
 * `PorteeEcrituresService::requete()` ne prend qu'un exercice, des statuts et
 * un journal. Les appliquer ici reviendrait a REECRIRE la portee des ecritures
 * dans un composant Livewire, ce que `LARAVEL_PWA.md` §3 interdit nommement,
 * et les totaux affiches ne seraient plus ceux que le Service a calcules.
 * Refus declare : maitre-refuse:m10-syscohada.html#filtres
 *
 * ### 5. ~~Le bouton « Excel » PORTE, « PDF » REFUSE~~ LES DEUX PORTES le
 * 01/09/2026 — SEPT ONGLETS SUR HUIT TOUJOURS REFUSES
 *
 * ECART DELIBERE — `m10-syscohada.html` l.47-48
 * Le maitre : deux boutons qui exportent l'onglet courant, dix onglets.
 * Ici : UN bouton « Exporter », ouvrant la modale unifiee (PDF/Excel), qui
 * exporte l'onglet Journal SEUL (`ONGLET_EXPORT_EXCEL`, dissocie
 * d'`ONGLET_DEFAUT` depuis ce lot — voir n. 2). Les sept autres onglets
 * restent NON PORTES : construire sept gabarits PDF/Excel de plus, un par
 * `ReadModel` de forme differente, dans le meme lot que la saisie, le plan
 * comptable et les immobilisations aurait sacrifie la qualite de chacun.
 * Refus declare : maitre-refuse:m10-syscohada.html#export-autres-onglets
 *
 * ### 6. ~~Les TROIS modales du hub — REFUSEES~~ PORTEES le 01/09/2026
 *
 * `modale-compte` (« Créer un compte ») appelle desormais
 * `PlanComptableService::creerCompte()`, qui n'existait pas au lot precedent —
 * voir son propre docblock pour la levee datee du refus. `modale-immo`
 * (« Nouvelle immobilisation ») et le detail « Plan » de chaque ligne
 * appellent `ImmobilisationService`. Un ecart de MECANISME commun aux trois :
 * elles se rendent derriere `@if($etatFormulaire === '…')`, jamais
 * toujours-dans-le-DOM comme au maitre (doctrine `RefuseLaSaisie`).
 *
 * ## LA PAGE D'ATTERRISSAGE DU MAITRE — `prototype_v2/pages/m10-comptabilite.html`
 *
 * Mesure du 31/08/2026, bloc par bloc, avant toute decision :
 *
 * | Bloc du maitre                         | Servi ici                        |
 * |----------------------------------------|----------------------------------|
 * | `<h1>` « Comptabilité » + sous-titre    | oui — le hub porte les deux mots |
 * | Bandeau « Ecran remplace »              | sans objet : c'est CETTE page    |
 * | Encadre d'erreur de chargement de `.js` | sans objet : rien n'est charge   |
 * | 4 KPI (l.71 `grille-kpi-compta`)        | REFUSE — voir ci-dessous         |
 * | 11 tuiles de navigation (l.74)          | OUI — `TUILES`, portees ici      |
 * | Pied « Donnees de demonstration »       | sans objet : donnees reelles     |
 *
 * Cette page se DECLARE elle-meme remplacee (l.19-24 : « Ecran remplace. […]
 * la version fonctionnelle est Comptabilité SYSCOHADA ») — meme dispositif que
 * `m3-crm.html`, `m4-restaurant.html`, `m14-etats.html` et `m11-pilotage.html`.
 * Elle n'a donc PAS de route propre : la version fonctionnelle qu'elle designe
 * est `/pwa/comptabilite`, servi par ce composant.
 *
 * ECART DELIBERE — `m10-comptabilite.html` l.71 (`grille-kpi-compta`)
 * Le maitre : quatre indicateurs — TOTAL ACTIF (BILAN), RECETTES DU MOIS,
 * MARGE NETTE (ANALYTIQUE), TRESORERIE DISPONIBLE.
 * Ici : ils ne sont pas rendus.
 * Raison : le hub porte deja les SIX indicateurs d'`IndicateursComptablesService`,
 * qui couvrent le total du bilan et la tresorerie. Les deux autres n'existent
 * pas au serveur.
 * Refus declare : maitre-refuse:m10-comptabilite.html#page
 *
 * ECART DELIBERE — les cinq modales de `assets/js/crud-ui.js`
 * Le maitre : la page charge le moteur CRUD generique, qui pose cinq modales
 * generiques (formulaire, detail, suppression, export, import).
 * Ici : aucune n'est portee — code mort herite d'une balise `<script>` commune,
 * verifie le 27/08/2026 (`grep -c` rend zero sur les six pages M10).
 * Refus declares :
 *   maitre-refuse:m10-comptabilite.html#modale-formulaire
 *   maitre-refuse:m10-comptabilite.html#modale-detail
 *   maitre-refuse:m10-comptabilite.html#modale-suppression
 *   maitre-refuse:m10-comptabilite.html#modale-export
 *   maitre-refuse:m10-comptabilite.html#modale-import
 *
 * @see EF-M10-06
 * @see LARAVEL_PWA.md §1, §3
 * @see DIRECTIVE_CONFORMITE_100.md Articles 3.3, 6, 8
 */
#[Title('Comptabilité — SYSCOHADA révisé — TATACORA AFRIQUE')]
class Hub extends PageComptabilite
{
    use FormulaireModal;

    /** Le module RBAC de l'écran — `data-module="M10"` du maître. */
    public const MODULE = 'M10';

    /**
     * Les onglets REELLEMENT servis, dans l'ordre du maitre
     * (`m10-syscohada.html` l.63-72) — DIX depuis le 01/09/2026 (Vague E),
     * « saisie » et « immo » desormais compris.
     *
     * @var array<string, string>
     */
    public const ONGLETS = [
        'saisie' => 'Passer écriture',
        'journal' => 'Journal',
        'grandlivre' => 'Grand livre',
        'balance' => 'Balance générale',
        'resultat' => 'Compte de résultat',
        'bilan' => 'Bilan',
        'analytique' => 'Analytique',
        'immo' => 'Immobilisations',
        'plan' => 'Plan comptable',
        'clotures' => 'Clôtures',
    ];

    /**
     * Les onze tuiles de navigation de `prototype_v2/pages/m10-comptabilite.html`
     * (l.74-105), dans SON ordre, avec SES titres et SES descriptions.
     *
     * @var array<int, array{0: string, 1: string, 2: string}>
     */
    public const TUILES = [
        ['Plan Comptable', 'Comptes SYSCOHADA (Classes 1 à 7)', 'pwa.comptabilite.plan-comptable'],
        ['Journal Comptable', 'Écritures Débit/Crédit, saisie manuelle', 'pwa.comptabilite.journal'],
        ["Bilan de l'Entreprise", 'Actif / Passif, équilibre comptable', 'pwa.comptabilite.bilan'],
        ['Compte de Résultat', "Produits, charges et résultat net de l'exercice", 'pwa.comptabilite.compte-resultat'],
        ['Tableau des Flux de Trésorerie', 'TAFIRE — variation de trésorerie sur la période', 'pwa.comptabilite.flux-tresorerie'],
        ['Notes Annexes', "Compléments d'information au Bilan et au Compte de Résultat", 'pwa.comptabilite.notes-annexes'],
        ['Clôture Périodique', "Bascule d'exercice fiscal, report à nouveau", 'pwa.comptabilite.cloture'],
        ['Comptabilité Analytique', 'Marges réelles par filière (Hébergement, Restauration, Bar, Tourisme, Véhicules)', 'pwa.comptabilite.analytique'],
        ['Grand Livre', 'Écritures par compte, solde progressif', 'pwa.comptabilite.grand-livre'],
        ['Balance Générale', 'Soldes de tous les comptes', 'pwa.comptabilite.balance'],
        ['États Financiers', 'Vue consolidée — Bilan, Résultat, Flux, Notes Annexes en un export unique', 'pwa.comptabilite.etats-financiers'],
    ];

    /** Onglet ouvert par defaut — comme le maitre, depuis le 01/09/2026 (voir n. 2 de l'entete). */
    public const ONGLET_DEFAUT = 'saisie';

    /**
     * Onglet exporte par « Excel » — DISSOCIE de `ONGLET_DEFAUT` depuis que
     * celui-ci vaut « saisie » : le bouton continue d'exporter le Journal.
     */
    public const ONGLET_EXPORT_EXCEL = 'journal';

    /** Ligne vierge d'une pièce en cours de saisie — un seul endroit. */
    private const LIGNE_PIECE_VIDE = [
        'compte' => '', 'libelle' => '', 'centre_id' => '', 'debit' => '', 'credit' => '',
    ];

    #[Url(as: 'onglet')]
    public string $onglet = self::ONGLET_DEFAUT;

    /** Compte consulte par l'onglet Grand livre. */
    #[Url(as: 'compte')]
    public string $compteId = '';

    /** Journal retenu par le filtre — vide pour « Tous les journaux ». */
    #[Url(as: 'journal')]
    public string $journalId = '';

    /**
     * Recherche de l'onglet « Plan comptable » (décision du Product Owner,
     * 01/09/2026) — numéro de compte ou libellé. Sans effet sur les autres
     * onglets du hub (Journal, Balance, Grand Livre, Analytique) : voir
     * `App\Pwa\Livewire\Comptabilite\Balance` sur pourquoi une recherche
     * texte y casserait les totaux affichés.
     */
    #[Url(as: 'plan_q')]
    public string $planRecherche = '';

    /**
     * Recherche de l'onglet « Immobilisations » (PO, 01/09/2026) — code ou
     * libellé. Sûre : les totaux du pied de tableau sont une somme des
     * lignes affichées, pas un équilibre ni un cumul séquentiel.
     */
    #[Url(as: 'immo_q')]
    public string $immoRecherche = '';

    // --- Modale « Passer écriture » (maître l.68-137 de m10-syscohada.js) ---

    public string $journalCode = '';

    public string $dateEcriture = '';

    public string $libellePiece = '';

    /** @var array<int, array<string, string>> */
    public array $lignesPiece = [];

    // --- Modale « Créer un compte » -----------------------------------

    public string $numeroCompte = '';

    public string $libelleCompte = '';

    public string $natureCompte = '';

    // --- Modale « Nouvelle immobilisation » -----------------------------

    public string $libelleImmo = '';

    public string $compteImmo = '';

    public string $valeurOrigineImmo = '';

    public string $dateMiseServiceImmo = '';

    public string $dureeAnneesImmo = '';

    /** L'immobilisation dont le plan d'amortissement est consulté — LECTURE. */
    public ?string $immobilisationConsulteeId = null;

    // --- Modale « Ouvrir un exercice » -----------------------------------

    public string $anneeOuverture = '';

    /** Le motif de la réouverture d'un exercice clôturé (lot 2, 20/10/2026). */
    public string $motifReouverture = '';

    // --- Modale d'export unifiée (`pwa.partials.modale-export`) ----------

    public string $formatExport = 'pdf';

    /**
     * Le registre FERMÉ des formulaires de l'écran — `FormulaireModal`.
     *
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'piece' => ['journalCode', 'dateEcriture', 'libellePiece', 'lignesPiece'],
            'compte' => ['numeroCompte', 'libelleCompte', 'natureCompte'],
            'immo' => ['libelleImmo', 'compteImmo', 'valeurOrigineImmo', 'dateMiseServiceImmo', 'dureeAnneesImmo'],
            'exercice' => ['anneeOuverture'],
            'export' => ['formatExport'],
        ];
    }

    /**
     * « Excel » et « PDF » (`m10-syscohada.html` l.47-48) — PORTÉS le
     * 01/09/2026 via la modale d'export UNIFIÉE (dérogation PO, voir
     * `App\Pwa\Support\DerogationsMaquette`), sur l'onglet Journal SEUL.
     *
     * ~~« Excel » était un téléchargement direct, sans modale.~~ Remplacé :
     * le choix PDF/Excel commande le format, comme sur les onze autres écrans
     * qui ouvrent cette même modale — deux mécanismes d'export sur le même
     * hub auraient été la première divergence.
     */
    public function ouvrirExport(): void
    {
        $this->ouvrirFormulaire('export');
    }

    /**
     * Produit le document sur l'onglet Journal SEUL — les sept autres restent
     * refusés (voir le docblock de classe, n. 5). PA-119 : mêmes filtres que
     * l'écran (exercice, statuts, journal), et refuse une liste vide plutôt
     * qu'un document sans lignes.
     */
    public function genererExport(): ?Response
    {
        // Un export est une LECTURE (PA-119, inscrit dans
        // METHODES_DE_LECTURE) : la route garde déjà `M10, L`, et exiger un
        // droit d'ÉCRITURE ici fermait l'export au comptable en lecture —
        // contradiction relevée par le test du rôle `rh` (01/09/2026).
        if ($this->ongletValide() !== self::ONGLET_EXPORT_EXCEL) {
            $this->addError('export', __('pwa.comptabilite.export_onglet_refuse'));

            return null;
        }

        $exercice = $this->exercice();

        if ($exercice === null) {
            $this->addError('export', __('pwa.comptabilite.export_vide'));

            return null;
        }

        try {
            $journal = app(JournalGeneralService::class)->genererPourExercice(
                $exercice->id,
                $this->statuts(),
                $this->journalId === '' ? null : $this->journalId,
                $this->filtreStatutValide(),
            );
        } catch (EtatTropVolumineuxException $exception) {
            $this->addError('export', $exception->getMessage());

            return null;
        }

        if ($journal->lignes->isEmpty()) {
            $this->addError('export', __('pwa.comptabilite.export_vide'));

            return null;
        }

        $this->etatFormulaire = null;
        $nom = 'journal_comptable_'.now()->format('Ymd_His');

        if ($this->formatExport === 'excel') {
            /** @var Response $reponse */
            $reponse = Excel::download(new ComptabiliteJournalExport($journal->lignes), $nom.'.xlsx');

            return $reponse;
        }

        $pdf = Pdf::loadView('pdf.comptabilite-journal-rapport', [
            'entete' => $this->enTeteRapport(
                __('comptabilite_pwa.export_journal_titre'),
                __('rapports.periode.exercice', ['annee' => $exercice->annee]),
            ),
            'lignes' => $journal->lignes,
            'exercice' => $exercice,
            'totalDebit' => $journal->totalDebit,
            'totalCredit' => $journal->totalCredit,
            'auteur' => (string) auth()->user()?->login,
        ])->setPaper('a4', 'landscape');

        return response()->streamDownload(static function () use ($pdf): void {
            echo $pdf->output();
        }, $nom.'.pdf');
    }

    // =========================================================================
    // « Passer écriture » — EF-M10-02
    // =========================================================================

    public function ouvrirFormulairePiece(): void
    {
        $this->ouvrirFormulaire('piece');

        $exercice = $this->exercice();
        $aujourdhui = now()->toDateString();

        $this->dateEcriture = $exercice !== null
            && $aujourdhui >= $exercice->date_debut->toDateString()
            && $aujourdhui <= $exercice->date_fin->toDateString()
                ? $aujourdhui
                : (string) ($exercice?->date_debut?->toDateString() ?? $aujourdhui);

        // DEUX lignes vierges, jamais zéro ni une seule : une pièce à moins
        // de deux lignes ne peut de toute façon jamais être équilibrée.
        $this->lignesPiece = [self::LIGNE_PIECE_VIDE, self::LIGNE_PIECE_VIDE];
    }

    /**
     * ⚠ Ne persiste rien — état du formulaire seulement — et exige pourtant
     * le droit d'écriture, comme `Depenses::ajouterLigneDepense()` : une
     * méthode publique de composant est atteignable par la route Livewire.
     */
    public function ajouterLignePiece(): void
    {
        $this->exigerEcriture(self::MODULE);

        $this->lignesPiece[] = self::LIGNE_PIECE_VIDE;
    }

    public function retirerLignePiece(int $index): void
    {
        $this->exigerEcriture(self::MODULE);

        if (count($this->lignesPiece) <= 2) {
            // Une pièce comporte au moins deux lignes (maître, m10-syscohada.js
            // l.217) : sans ce refus, un appel direct de l'action viderait la
            // saisie sous le minimum que le débit = crédit exige de toute façon.
            return;
        }

        unset($this->lignesPiece[$index]);
        $this->lignesPiece = array_values($this->lignesPiece);
        $this->resetValidation();
    }

    public function enregistrerPieceBrouillon(PasserEcritureService $service): void
    {
        // Appel DIRECT exigé par `PwaEcritureAutoriseeTest` — `validerEcriture()`
        // l'appelle déjà à l'intérieur d'`enregistrerPiece()`, mais la garde ne
        // relit que le corps LITTÉRAL de chaque méthode publique, jamais ce
        // qu'appelle un délégué privé. Redondant avec l'appel interne, jamais
        // en trop : `exigerEcriture()` est sans effet de bord au-delà du refus.
        $this->exigerEcriture(self::MODULE);
        $this->enregistrerPiece($service, valider: false);
    }

    public function enregistrerPieceValidee(PasserEcritureService $service): void
    {
        $this->exigerEcriture(self::MODULE);
        $this->enregistrerPiece($service, valider: true);
    }

    /**
     * Enregistre la pièce — brouillon ou validée selon l'appelant. Le refus
     * s'AFFICHE, il ne se range pas dans une colonne : seul `RuntimeException`
     * est repris (celle que `PasserEcritureService` emploie pour ses refus),
     * une autre erreur repart telle quelle.
     */
    private function enregistrerPiece(PasserEcritureService $service, bool $valider): void
    {
        $valide = $this->validerEcriture([
            'journalCode' => ['required', 'string', 'exists:journaux_comptables,code'],
            'dateEcriture' => ['required', 'date'],
            'libellePiece' => ['required', 'string', 'max:255'],
            'lignesPiece' => ['required', 'array', 'min:2'],
            'lignesPiece.*.compte' => ['required', 'string', 'exists:plan_comptable,numero_compte'],
            'lignesPiece.*.libelle' => ['nullable', 'string', 'max:255'],
            'lignesPiece.*.centre_id' => ['nullable', 'string', 'exists:centres_cout,id'],
            'lignesPiece.*.debit' => ['nullable', 'numeric', 'min:0'],
            'lignesPiece.*.credit' => ['nullable', 'numeric', 'min:0'],
        ]);

        $lignes = [];

        foreach ($valide['lignesPiece'] as $position => $ligne) {
            $ligne = (array) $ligne;
            $debit = bcadd((string) ($ligne['debit'] ?? '0'), '0', 2);
            $credit = bcadd((string) ($ligne['credit'] ?? '0'), '0', 2);

            if (bccomp($debit, '0', 2) > 0 && bccomp($credit, '0', 2) > 0) {
                $this->addError('piece', __('comptabilite_pwa.ligne_debit_et_credit', ['position' => $position + 1]));

                return;
            }

            if (bccomp($debit, '0', 2) <= 0 && bccomp($credit, '0', 2) <= 0) {
                $this->addError('piece', __('comptabilite_pwa.ligne_montant_requis', ['position' => $position + 1]));

                return;
            }

            $libelleLigne = isset($ligne['libelle']) ? trim((string) $ligne['libelle']) : '';

            $lignes[] = [
                'compte' => (string) $ligne['compte'],
                'libelle' => $libelleLigne === '' ? null : $libelleLigne,
                'centre_id' => isset($ligne['centre_id']) && $ligne['centre_id'] !== '' ? (string) $ligne['centre_id'] : null,
                'debit' => $debit,
                'credit' => $credit,
            ];
        }

        $donnees = [
            'journal' => (string) $valide['journalCode'],
            'date' => (string) $valide['dateEcriture'],
            'libelle' => trim((string) $valide['libellePiece']),
            'lignes' => $lignes,
        ];

        try {
            $valider ? $service->passerEtValider($donnees) : $service->passer($donnees);
        } catch (RuntimeException $refus) {
            $this->addError('piece', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire($valider
            ? __('comptabilite_pwa.piece_validee_enregistree')
            : __('comptabilite_pwa.piece_brouillon_enregistree'));
    }

    // =========================================================================
    // Plan comptable — « + Créer un compte »
    // =========================================================================

    public function ouvrirNouveauCompte(): void
    {
        $this->ouvrirFormulaire('compte');
    }

    public function enregistrerCompte(PlanComptableService $service): void
    {
        $valide = $this->validerEcriture([
            'numeroCompte' => ['required', 'string', 'regex:/^[1-9][0-9]{5}$/'],
            'libelleCompte' => ['required', 'string', 'max:255'],
            'natureCompte' => ['required', 'string', 'in:'.implode(',', PlanComptableService::NATURES)],
        ]);

        try {
            $compte = $service->creerCompte(
                (string) $valide['numeroCompte'],
                (string) $valide['libelleCompte'],
                (string) $valide['natureCompte'],
            );
        } catch (RuntimeException $refus) {
            $this->addError('compte', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('comptabilite_pwa.compte_cree', ['numero' => $compte->numero_compte]));
    }

    // =========================================================================
    // Immobilisations
    // =========================================================================

    public function ouvrirNouvelleImmo(): void
    {
        $this->ouvrirFormulaire('immo');
    }

    public function enregistrerImmo(ImmobilisationService $service): void
    {
        $valide = $this->validerEcriture([
            'libelleImmo' => ['required', 'string', 'max:255'],
            'compteImmo' => ['nullable', 'string', 'exists:plan_comptable,numero_compte'],
            'valeurOrigineImmo' => ['required', 'numeric', 'min:1'],
            'dateMiseServiceImmo' => ['required', 'date'],
            'dureeAnneesImmo' => ['required', 'integer', 'min:1', 'max:60'],
        ]);

        try {
            $immobilisation = $service->creer([
                'libelle' => (string) $valide['libelleImmo'],
                'compte_immobilisation' => $valide['compteImmo'] !== '' && $valide['compteImmo'] !== null
                    ? (string) $valide['compteImmo'] : null,
                'valeur_origine' => (string) $valide['valeurOrigineImmo'],
                'date_mise_service' => (string) $valide['dateMiseServiceImmo'],
                'duree_annees' => (int) $valide['dureeAnneesImmo'],
            ]);
        } catch (RuntimeException $refus) {
            $this->addError('immo', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('comptabilite_pwa.immo_enregistree', ['code' => $immobilisation->code]));
    }

    /**
     * Ouvre la modale « Plan » d'une immobilisation — LECTURE seule : elle ne
     * fait que recalculer, sur un autre onglet, un plan déjà déductible des
     * colonnes affichées (même famille qu'`ouvrirHistoriqueClient`).
     */
    public function ouvrirPlanAmortissement(string $immobilisationId): void
    {
        $this->immobilisationConsulteeId = Immobilisation::query()->findOrFail($immobilisationId)->id;
        $this->etatFormulaire = 'planAmortissement';
    }

    // =========================================================================
    // Clôtures — commande du Product Owner (Vague E), périmètre minimal
    // =========================================================================

    public function ouvrirFormulaireExercice(): void
    {
        $this->ouvrirFormulaire('exercice');

        $dernier = $this->exercices()->first();
        $this->anneeOuverture = (string) ($dernier !== null ? $dernier->annee + 1 : (int) now()->format('Y'));
    }

    public function enregistrerExercice(ExerciceComptableService $service): void
    {
        $valide = $this->validerEcriture([
            'anneeOuverture' => ['required', 'integer', 'min:2000', 'max:2100'],
        ]);

        try {
            $exercice = $service->ouvrir((int) $valide['anneeOuverture']);
        } catch (RuntimeException $refus) {
            $this->addError('exercice', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('comptabilite_pwa.exercice_ouvert', ['annee' => (string) $exercice->annee]));
    }

    /**
     * La clôture SYSCOHADA annuelle de l'exercice CONSULTÉ (lot 2,
     * 20/10/2026) — `ClotureExerciceService` : démarrer (ouvert → en
     * clôture), reprendre la saisie, clôturer définitivement (solde des
     * comptes de gestion en 131/139, à-nouveaux au journal AN, verrou), et
     * rouvrir (le comptable seul, motif obligatoire).
     */
    public function demarrerCloture(ClotureExerciceService $service): void
    {
        $this->gesteDeCloture(fn ($exercice, $utilisateur) => $service->demarrer($exercice, $utilisateur), 'comptabilite_pwa.cloture_demarree');
    }

    public function reprendreSaisie(ClotureExerciceService $service): void
    {
        $this->gesteDeCloture(fn ($exercice, $utilisateur) => $service->reprendreSaisie($exercice, $utilisateur), 'comptabilite_pwa.saisie_reprise');
    }

    public function cloturerExercice(ClotureExerciceService $service, ArchiveClotureService $archives): void
    {
        // L'archive légale (lot 4) suit la clôture, HORS de sa transaction :
        // un PDF qui échouerait ne défait pas une clôture passée — l'écran
        // propose alors de générer l'archive (`genererArchive`).
        $this->gesteDeCloture(function ($exercice, $utilisateur) use ($service, $archives) {
            $cloture = $service->cloturer($exercice, $utilisateur);

            try {
                $archives->archiver($cloture, $utilisateur);
            } catch (Throwable $echec) {
                report($echec);
            }
        }, 'comptabilite_pwa.exercice_cloture');
    }

    /**
     * L'archive légale d'une clôture passée qui n'en a pas encore (la
     * génération a échoué après la clôture). Une archive existante n'est
     * jamais réécrite.
     */
    public function genererArchive(ClotureExerciceService $service, ArchiveClotureService $archives): void
    {
        $this->gesteDeCloture(function ($exercice, $utilisateur) use ($service, $archives) {
            $cloture = $service->clotureActive($exercice->id)
                ?? throw new RuntimeException(__('comptabilite.archive_sans_cloture'));
            $archives->archiver($cloture, $utilisateur);
        }, 'comptabilite_pwa.archive_generee');
    }

    /**
     * Télécharge l'archive légale (ZIP : écritures, balance, états PDF,
     * manifeste). Une LECTURE : l'archive est vérifiée, jamais réécrite.
     */
    public function telechargerArchive(ClotureExerciceService $service, ArchiveClotureService $archives): ?BinaryFileResponse
    {
        $exercice = $this->exercice();
        $cloture = $exercice === null ? null : $service->clotureActive($exercice->id);

        if ($exercice === null || $cloture === null || $cloture->archive_empreinte === null) {
            $this->addError('cloture', __('comptabilite.archive_sans_cloture'));

            return null;
        }

        try {
            $zip = $archives->zip($cloture);
        } catch (RuntimeException $refus) {
            $this->addError('cloture', $refus->getMessage());

            return null;
        }

        return response()->download($zip, 'archive_exercice_'.$exercice->annee.'.zip')->deleteFileAfterSend();
    }

    public function rouvrirExercice(ClotureExerciceService $service): void
    {
        $this->gesteDeCloture(function ($exercice, $utilisateur) use ($service) {
            $service->rouvrir($exercice, $utilisateur, $this->motifReouverture);
            $this->motifReouverture = '';
        }, 'comptabilite_pwa.exercice_rouvert');
    }

    /**
     * @param  callable(\App\Domain\Comptabilite\Models\ExerciceComptable, \App\Models\User): mixed  $geste
     */
    private function gesteDeCloture(callable $geste, string $succes): void
    {
        $utilisateur = $this->exigerEcriture(self::MODULE);
        $exercice = $this->exercice();

        if ($exercice === null) {
            // Appel direct sans exercice consulté : erreur d'appel du
            // composant, pas une saisie utilisateur.
            return;
        }

        try {
            $geste($exercice, $utilisateur);
        } catch (RuntimeException $refus) {
            $this->addError('cloture', $refus->getMessage());

            return;
        }

        $this->resetErrorBag('cloture');
        session()->flash('pwa-succes', __($succes, ['annee' => (string) $exercice->annee]));
    }

    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->resetValidation();
    }

    /**
     * L'onglet REQUÊTÉ, validé — même garde que `render()`
     * (`array_key_exists($this->onglet, self::ONGLETS)`), extraite pour être
     * appelée aussi par `genererExport()` sans dupliquer la règle.
     */
    protected function ongletValide(): string
    {
        return array_key_exists($this->onglet, self::ONGLETS) ? $this->onglet : self::ONGLET_DEFAUT;
    }

    public function render(): View
    {
        $socle = $this->socle();
        $exercice = $socle['exercice'];

        $ongletActif = $this->ongletValide();

        $immobilisationConsultee = $this->immobilisationConsulteeId === null
            ? null
            : Immobilisation::find($this->immobilisationConsulteeId);

        return view('pwa.comptabilite.hub', array_merge($socle, [
            'ongletActif' => $ongletActif,
            'journalId' => $this->journalId,
            'compteId' => $this->compteId,
            'planRecherche' => $this->planRecherche,
            'immoRecherche' => $this->immoRecherche,
            'journaux' => $exercice === null ? collect() : $this->journaux(),
            'indicateurs' => $exercice === null ? null : app(IndicateursComptablesService::class)
                ->genererPourExercice($exercice, $this->statuts(), $this->filtreStatutValide()),
            'contenu' => $exercice === null ? null : $this->contenu($ongletActif, $exercice->id),

            // Référentiels des trois modales d'écriture — une seule requête
            // chacun, jamais reconstruits dans la vue.
            'comptesDuPlan' => app(PlanComptableService::class)->consulter()->comptes,
            'centresDeCout' => CentreCout::query()->orderBy('libelle')->get(),
            'naturesDeCompte' => PlanComptableService::NATURES,

            // Le total de la SAISIE en cours — calculé, donc en lecture seule
            // (règle n° 2 du dépôt), recalculé à chaque frappe via
            // `wire:model.live`. Il ne fait PAS foi : `PasserEcritureService`
            // revérifie l'équilibre à l'enregistrement.
            'totauxPiece' => $this->totauxPiece(),

            'immobilisationConsultee' => $immobilisationConsultee,
            'planAmortissementConsulte' => $immobilisationConsultee === null
                ? null
                : app(ImmobilisationService::class)->planAmortissement($immobilisationConsultee),
        ]))->layout('layouts.pwa');
    }

    /**
     * L'etat du seul onglet affiche.
     *
     * @return array<string, mixed>
     */
    private function contenu(string $onglet, string $exerciceId): array
    {
        $statuts = $this->statuts();
        $filtre = $this->filtreStatutValide();

        try {
            return match ($onglet) {
                'saisie' => [],
                'journal' => ['journal' => app(JournalGeneralService::class)->genererPourExercice(
                    $exerciceId,
                    $statuts,
                    $this->journalId === '' ? null : $this->journalId,
                    $filtre,
                )],
                'grandlivre' => $this->grandLivre($exerciceId, $statuts, $filtre),
                'balance' => ['balance' => app(BalanceGeneraleService::class)
                    ->genererPourExercice($exerciceId, $statuts, $filtre)],
                'resultat' => ['resultat' => app(CompteResultatService::class)
                    ->genererPourExercice($exerciceId, $statuts, $filtre)],
                'bilan' => ['bilan' => app(BilanService::class)
                    ->genererPourExercice($exerciceId, $statuts, $filtre)],
                'analytique' => ['analytique' => app(AnalytiqueService::class)
                    ->genererPourExercice($exerciceId, $statuts, $filtre)],
                'immo' => ['tableauImmobilisations' => app(ImmobilisationService::class)
                    ->tableauPourExercice($this->anneeDeLExerciceConsulte(), $this->immoRecherche)],
                'plan' => ['plan' => app(PlanComptableService::class)->consulter(null, $this->planRecherche)],
                'clotures' => $this->clotures($exerciceId, $statuts, $filtre),
                default => [],
            };
        } catch (EtatTropVolumineuxException $exception) {
            return ['refusDeVolume' => $exception->getMessage()];
        }
    }

    /**
     * L'année de l'exercice consulté — l'année courante si, par un chemin
     * d'appel qui ne devrait pas exister, aucun exercice n'est résolu.
     */
    private function anneeDeLExerciceConsulte(): int
    {
        $exercice = $this->exercice();

        return $exercice === null ? (int) now()->format('Y') : $exercice->annee;
    }

    /**
     * @param  list<string>  $statuts
     * @return array<string, mixed>
     */
    private function grandLivre(string $exerciceId, array $statuts, string $filtre): array
    {
        $service = app(GrandLivreService::class);
        $comptes = $service->comptesMouvementes($exerciceId, $statuts);

        $compte = $this->compteId === ''
            ? $comptes->first()
            : $comptes->firstWhere('id', $this->compteId);

        return [
            'comptesMouvementes' => $comptes,
            'grandLivre' => $compte instanceof CompteComptable
                ? $service->genererPourCompte($exerciceId, $compte, $statuts, $filtre)
                : null,
        ];
    }

    /**
     * @param  list<string>  $statuts
     * @return array<string, mixed>
     */
    private function clotures(string $exerciceId, array $statuts, string $filtre): array
    {
        $exercice = $this->exercice();

        return [
            'tousExercices' => $this->exercices(),
            'cloture' => $exercice === null ? null : app(EtatClotureService::class)
                ->genererPourExercice($exercice, $statuts, $filtre),
            'exerciceIdConsulte' => $exerciceId,
            // Lot 2 : la clôture active (pièces passées) et le droit de rouvrir.
            'clotureActive' => $exercice === null ? null : app(ClotureExerciceService::class)->clotureActive($exercice->id),
            'peutRouvrir' => auth()->user()?->role?->libelle === ClotureExerciceService::ROLE_REOUVERTURE,
        ];
    }

    /**
     * Les totaux de la pièce en cours de saisie — somme `bcadd`, une ligne
     * mi-tapée est ignorée plutôt que fatale (même raisonnement que
     * `Depenses::totalDesLignes()`).
     *
     * @return array{debit: string, credit: string, equilibre: bool}
     */
    private function totauxPiece(): array
    {
        $debit = '0.00';
        $credit = '0.00';

        foreach ($this->lignesPiece as $ligne) {
            $d = trim((string) ($ligne['debit'] ?? ''));
            $c = trim((string) ($ligne['credit'] ?? ''));

            if (is_numeric($d)) {
                $debit = bcadd($debit, bcadd($d, '0', 2), 2);
            }

            if (is_numeric($c)) {
                $credit = bcadd($credit, bcadd($c, '0', 2), 2);
            }
        }

        return ['debit' => $debit, 'credit' => $credit, 'equilibre' => bccomp($debit, $credit, 2) === 0];
    }
}

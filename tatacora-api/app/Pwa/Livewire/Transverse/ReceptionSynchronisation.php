<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Models\User;
use App\Shared\Sync\Exceptions\RefusSynchronisationException;
use App\Shared\Sync\Models\JournalReceptionSynchronisation as Journal;
use App\Shared\Sync\Services\CorrectionReceptionService;
use App\Shared\Sync\Services\JournalReceptionService;
use Illuminate\Contracts\View\View;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Livewire\Component;
use RuntimeException;
use Throwable;

/**
 * L'onglet « Réception » de « Postes & Appairage » — ce que le serveur a REÇU
 * des postes (demande du PO du 26/10/2026) : compteurs, liste filtrable,
 * détail avec la CAUSE de chaque échec, et trois gestes pour un rejet ou un
 * signalement : « Corriger » (formulaire pré-rempli par la charge reçue),
 * « Relancer » (rejeu par le chemin de la synchronisation) et « Marquer comme
 * traité » (motif tracé).
 *
 * ## Composant imbriqué, droits à deux niveaux
 *
 * Monté dans la page (`@livewire('pwa.reception-synchronisation')`), comme la
 * cloche de la barre supérieure. La lecture est réservée aux Administrateurs
 * et au Comptable (le Comptable ne voit que les données de ses modules) ; chaque
 * geste exige en plus le niveau d'écriture sur le module de la donnée
 * (`CorrectionReceptionService`), et un refus se traduit en 403. Les trois
 * gestes sont des écritures HORS MODULE au sens de `PwaEcritureAutoriseeTest` :
 * leur module est celui de la DONNÉE, connu à l'exécution, jamais celui de
 * l'écran.
 *
 * Aucune méthode publique n'est un simple calcul : les filtres sont des
 * propriétés, la pagination une propriété (`limite`).
 */
class ReceptionSynchronisation extends Component
{
    public string $filtrePoste = '';

    public string $filtreTable = '';

    public string $filtreIssue = '';

    public string $filtrePeriode = '7j';

    public bool $filtreATraiter = false;

    /** Nombre de lignes affichées (« Afficher plus »). */
    public int $limite = 25;

    /** L'opération dont le détail est ouvert. */
    public ?string $detailId = null;

    /** L'opération en cours de correction, et la saisie (index du champ → texte). */
    public ?string $correctionId = null;

    /** @var array<int, string> */
    public array $saisie = [];

    public ?string $retourCorrection = null;

    public ?string $ignorerId = null;

    public string $motifIgnorer = '';

    public ?string $retourIgnorer = null;

    public ?string $confirmation = null;

    public ?string $refus = null;

    /** Relit le journal : rien n'est écrit, le rendu suivant l'interroge. */
    public function actualiser(): void
    {
        $this->confirmation = null;
        $this->refus = null;
    }

    public function ouvrirOperation(string $id): void
    {
        $this->exigerLecture();
        $this->detailId = $this->visible($id) ? $id : null;
    }

    public function fermerOperation(): void
    {
        $this->detailId = null;
    }

    /** Ouvre le formulaire pré-rempli par la charge reçue. N'écrit rien. */
    public function ouvrirCorrection(string $id): void
    {
        $this->exigerLecture();
        $entree = $this->entreeVisible($id);
        $service = app(CorrectionReceptionService::class);

        if ($entree === null || ! $service->peutCorriger($entree)) {
            return;
        }

        $this->retourCorrection = null;
        $this->correctionId = $id;
        $this->saisie = [];

        foreach ($service->champs($entree->payload_corrige ?? $entree->payload ?? []) as $indice => $champ) {
            $this->saisie[$indice] = $champ['valeur'] === null ? '' : (string) $champ['valeur'];
        }
    }

    public function fermerCorrection(): void
    {
        $this->correctionId = null;
        $this->saisie = [];
        $this->retourCorrection = null;
    }

    /**
     * « Vérifier et enregistrer » : la correction est vérifiée par les règles
     * de gestion du module concerné AVANT d'être retenue, puis tracée à votre
     * nom. Elle n'est appliquée qu'à « Relancer ».
     */
    public function enregistrerCorrection(CorrectionReceptionService $corrections): void
    {
        $auteur = $this->auteur();
        $entree = $this->correctionId !== null ? Journal::query()->find($this->correctionId) : null;

        if ($entree === null) {
            return;
        }

        [$charge, $modifies] = $corrections->appliquerSaisie($entree->payload_corrige ?? $entree->payload ?? [], $this->saisie);

        if ($modifies === []) {
            $this->retourCorrection = __('synchronisation_journal.ecran.corriger_aucun_champ');

            return;
        }

        try {
            $verdict = $corrections->corriger($entree->id, $charge, $auteur);
        } catch (RefusSynchronisationException) {
            abort(403);
        } catch (RuntimeException $e) {
            $this->retourCorrection = $e->getMessage();

            return;
        }

        if (! $verdict['ok']) {
            $this->retourCorrection = __('synchronisation_journal.ecran.corriger_refusee', ['motif' => $verdict['motif']]);

            return;
        }

        $this->correctionId = null;
        $this->saisie = [];
        $this->retourCorrection = null;
        $this->refus = null;
        $this->confirmation = __('synchronisation_journal.ecran.corriger_valide');
    }

    /** Rejoue l'opération (charge corrigée, à défaut charge reçue). */
    public function relancer(string $id, CorrectionReceptionService $corrections): void
    {
        $auteur = $this->auteur();
        $this->confirmation = null;
        $this->refus = null;

        try {
            $bilan = $corrections->relancer($id, $auteur);
        } catch (RefusSynchronisationException) {
            abort(403);
        } catch (RuntimeException $e) {
            $this->refus = $e->getMessage();

            return;
        } catch (Throwable $e) {
            report($e);
            $this->refus = __('synchronisation_journal.motifs.erreur_serveur.cause');

            return;
        }

        if ($bilan['ok']) {
            $this->confirmation = __('synchronisation_journal.ecran.relance_reussie', [
                'issue' => mb_strtolower(__('synchronisation_journal.issues.' . $bilan['issue'])),
            ]);
        } else {
            $this->refus = __('synchronisation_journal.ecran.relance_echouee', ['motif' => $bilan['motif']]);
        }
    }

    public function ouvrirIgnorer(string $id): void
    {
        $this->exigerLecture();
        $entree = $this->entreeVisible($id);

        if ($entree === null || ! app(CorrectionReceptionService::class)->peutIgnorer($entree)) {
            return;
        }

        $this->ignorerId = $id;
        $this->motifIgnorer = '';
        $this->retourIgnorer = null;
    }

    public function fermerIgnorer(): void
    {
        $this->ignorerId = null;
        $this->motifIgnorer = '';
        $this->retourIgnorer = null;
    }

    /** « Marquer comme traité » : le motif est exigé, conservé avec votre nom. */
    public function ignorer(CorrectionReceptionService $corrections): void
    {
        $auteur = $this->auteur();

        if ($this->ignorerId === null) {
            return;
        }

        try {
            $corrections->ignorer($this->ignorerId, $this->motifIgnorer, $auteur);
        } catch (RefusSynchronisationException) {
            abort(403);
        } catch (RuntimeException $e) {
            $this->retourIgnorer = $e->getMessage();

            return;
        }

        $this->fermerIgnorer();
        $this->refus = null;
        $this->confirmation = __('synchronisation_journal.ecran.ignorer_fait');
    }

    private function exigerLecture(): User
    {
        $utilisateur = Auth::user();
        abort_unless($utilisateur instanceof User && app(CorrectionReceptionService::class)->estAutorise($utilisateur), 403);

        return $utilisateur;
    }

    private function auteur(): User
    {
        return $this->exigerLecture();
    }

    private function visible(string $id): bool
    {
        return $this->entreeVisible($id) !== null;
    }

    private function entreeVisible(string $id): ?Journal
    {
        $utilisateur = Auth::user();

        if (! $utilisateur instanceof User) {
            return null;
        }

        $tables = app(CorrectionReceptionService::class)->tablesVisibles($utilisateur);

        return Journal::query()
            ->when($tables !== null, static fn ($q) => $q->whereIn('table_concernee', $tables))
            ->find($id);
    }

    public function render(JournalReceptionService $journal, CorrectionReceptionService $corrections): View
    {
        $utilisateur = Auth::user();

        if (! $utilisateur instanceof User || ! $corrections->estAutorise($utilisateur)) {
            return view('pwa.transverse.reception-synchronisation', ['autorise' => false]);
        }

        $tablesVisibles = $corrections->tablesVisibles($utilisateur);
        $filtres = [
            'poste' => $this->filtrePoste,
            'table' => $this->filtreTable,
            'issue' => $this->filtreIssue,
            'periode' => $this->filtrePeriode,
            'a_traiter' => $this->filtreATraiter,
            'tables' => $tablesVisibles,
        ];

        $total = $journal->requete($filtres)->count();
        $lignes = $journal->requete($filtres)
            ->with(['utilisateur:id,login'])
            ->orderByDesc('recu_le')
            ->limit(max(25, $this->limite))
            ->get();

        $detail = $this->detailId !== null ? $this->entreeVisible($this->detailId) : null;
        $correction = $this->correctionId !== null ? $this->entreeVisible($this->correctionId) : null;
        $ignorer = $this->ignorerId !== null ? $this->entreeVisible($this->ignorerId) : null;

        $postes = DB::table('journal_reception_synchronisation')->distinct()->orderBy('poste_id')->pluck('poste_id')->all();
        $tables = DB::table('journal_reception_synchronisation')->distinct()->orderBy('table_concernee')->pluck('table_concernee')->all();
        $tables = $tablesVisibles === null ? $tables : array_values(array_intersect($tables, $tablesVisibles));

        return view('pwa.transverse.reception-synchronisation', [
            'autorise' => true,
            'compteurs' => $journal->compteurs([
                'poste' => $this->filtrePoste,
                'table' => $this->filtreTable,
                'periode' => $this->filtrePeriode,
                'tables' => $tablesVisibles,
            ]),
            'lignes' => $lignes,
            'total' => $total,
            'postes' => $postes,
            'tables' => $tables,
            'issues' => array_keys(__('synchronisation_journal.issues')),
            'detail' => $detail,
            'correction' => $correction,
            'champs' => $correction !== null ? $corrections->champs($correction->payload_corrige ?? $correction->payload ?? []) : [],
            'ignorer' => $ignorer,
            'journal' => $journal,
            'corrections' => $corrections,
            'auteurCourant' => $utilisateur,
            'champsDetail' => $detail !== null ? $corrections->champs($detail->payload_corrige ?? $detail->payload ?? []) : [],
        ]);
    }
}

<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Shared\Sync\Services\SuiviPostesService;
use Illuminate\Contracts\View\View;
use Illuminate\Support\Facades\Auth;
use Livewire\Component;

/**
 * L'icône de SYNCHRONISATION de la barre supérieure et sa modale — demande du
 * Product Owner du 03/11/2026 (« je ne vois plus l'icône de synchronisation et
 * l'appel de son modal dans la barre supérieure »).
 *
 * ## Historique (git log -S) : elle n'a jamais existé au web
 *
 * Le lot F3b (29e7562, 17/10/2026) a posé l'icône dans la barre du POSTE
 * (`BoutonSynchronisation`). Le web n'a reçu, le 18/10/2026 (523734a), que
 * l'entrée « Synchroniser les postes » du menu de compte : aucune icône n'a été
 * retirée, elle n'avait jamais été posée. Ce composant la crée, entre « Vente »
 * et la cloche, avec le tracé de `TracesCoquille.synchronisation` du poste.
 *
 * ## Ne duplique rien
 *
 * L'état des postes, la dernière demande, la demande elle-même et la règle du
 * voyant viennent de `SuiviPostesService` (`etats()`, `derniereDemande()`,
 * `demander()`, `voyant()`), les mêmes appels que l'écran « Postes &
 * Appairage ». Même droit que cet écran : la demande est ouverte à tout compte
 * connecté (décision du PO du 18/10/2026) — elle n'écrit qu'une demande
 * horodatée, aucune donnée métier (voir `ECRITURES_HORS_MODULE`).
 * La révocation reste sur l'écran, réservée aux Administrateurs.
 */
class SynchronisationBarre extends Component
{
    public bool $ouvert = false;

    /** La phrase de succès après « Demander la synchronisation des postes ». */
    public ?string $confirmation = null;

    /** Ouvre la modale ; n'écrit rien. */
    public function ouvrir(): void
    {
        $this->confirmation = null;
        $this->ouvert = true;
    }

    /** Ferme la modale (bouton, voile, Échap) ; n'écrit rien. */
    public function fermer(): void
    {
        $this->ouvert = false;
        $this->confirmation = null;
    }

    /** Même action que `SynchronisationPostes::synchroniser`, même service. */
    public function demander(SuiviPostesService $suivi): void
    {
        $utilisateur = Auth::user();
        abort_if($utilisateur === null, 403);

        $demande = $suivi->demander($utilisateur);
        $this->confirmation = __('pwa.synchronisation_postes.demande_faite', [
            'date' => \App\Shared\Support\HeureLocale::formater($demande->demandee_le, 'd/m/Y H:i:s'),
        ]);
    }

    public function render(SuiviPostesService $suivi): View
    {
        $postes = $suivi->etats();

        return view('pwa.transverse.synchronisation-barre', [
            'voyant' => $suivi->voyant($postes),
            'postes' => $this->ouvert ? $postes : [],
            'demande' => $this->ouvert ? $suivi->derniereDemande() : null,
            'retardMinutes' => SuiviPostesService::RETARD_MAX_MINUTES,
        ]);
    }
}

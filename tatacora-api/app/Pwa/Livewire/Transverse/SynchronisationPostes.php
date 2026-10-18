<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Shared\Sync\Services\SuiviPostesService;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;
use Livewire\Attributes\Title;

/**
 * Le bouton « Synchroniser » du serveur — décision du Product Owner du
 * 18/10/2026 (« le serveur doit avoir aussi le bouton synchroniser, pour
 * envoyer les données en local si le serveur a été utilisé pour enregistrer
 * des données ; appliquer à tous les modules »).
 *
 * Le serveur n'atteint pas les postes (ils l'appellent) : le bouton
 * ENREGISTRE une demande (`SuiviPostesService::demander`), que chaque poste
 * lit dans les 30 s et suit aussitôt — envoi de sa file, puis réception de
 * tout ce que le serveur détient, tous modules. L'écran dit, poste par
 * poste, ce que le serveur en sait : dernier envoi, dernière réception, file
 * déclarée, demande lue ou non. Ouvert à tout compte : la demande ne modifie
 * aucune donnée.
 */
#[Title('Synchroniser les postes — TATACORA AFRIQUE')]
class SynchronisationPostes extends PageTransverse
{
    public ?string $confirmation = null;

    public function synchroniser(SuiviPostesService $suivi): void
    {
        $demande = $suivi->demander(Auth::user());
        $this->confirmation = __('pwa.synchronisation_postes.demande_faite', [
            'date' => $demande->demandee_le->format('d/m/Y H:i:s'),
        ]);
    }

    public function render(SuiviPostesService $suivi): View
    {
        return view('pwa.transverse.synchronisation-postes', array_merge($this->socle(), [
            'demande' => $suivi->derniereDemande(),
            'postes' => $suivi->etats(),
        ]))->layout('layouts.pwa', ['title' => __('pwa.synchronisation_postes.titre_page')]);
    }
}

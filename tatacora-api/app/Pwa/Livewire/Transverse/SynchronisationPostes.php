<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Shared\Sync\Services\CorrectionReceptionService;
use App\Shared\Sync\Services\SuiviPostesService;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use RuntimeException;

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
 *
 * Depuis le 19/10/2026 (décision du PO : gérer l'appairage « dans le poste
 * et le web »), l'écran dit aussi si chaque poste est APPAIRÉ, et un
 * Administrateur peut RÉVOQUER l'appairage d'un poste (perdu, remplacé) —
 * confirmation par la modale du dépôt, jamais `wire:confirm`. Le poste
 * révoqué garde sa file intacte et le dit jusqu'au réappairage.
 */
#[Title('Postes & Appairage — TATACORA AFRIQUE')]
class SynchronisationPostes extends PageTransverse
{
    /** Les onglets de l'écran : `postes`, `reception`, `envoi` (26/10/2026). */
    #[Url(as: 'onglet')]
    public string $onglet = 'postes';

    public ?string $confirmation = null;

    /** Le poste dont la révocation attend confirmation — modale. */
    public ?string $posteARevoquer = null;

    public ?string $refusRevocation = null;

    /**
     * Change d'onglet. « Réception » et « Envoi » sont réservés aux
     * Administrateurs et au Comptable : un autre onglet demandé retombe sur
     * « Postes ». N'écrit rien.
     */
    public function changerOnglet(string $onglet): void
    {
        $this->onglet = $this->ongletPermis($onglet);
    }

    private function ongletPermis(string $onglet): string
    {
        if ($onglet === 'postes' || ! in_array($onglet, ['reception', 'envoi'], true)) {
            return 'postes';
        }

        return app(CorrectionReceptionService::class)->estAutorise(Auth::user()) ? $onglet : 'postes';
    }

    /**
     * « Actualiser » : relit l'état des postes. Rien n'est écrit — le rendu
     * suivant interroge `SuiviPostesService::etats()`.
     */
    public function actualiser(): void
    {
        $this->confirmation = null;
        $this->refusRevocation = null;
    }

    public function synchroniser(SuiviPostesService $suivi): void
    {
        $demande = $suivi->demander(Auth::user());
        $this->confirmation = __('pwa.synchronisation_postes.demande_faite', [
            'date' => $demande->demandee_le->format('d/m/Y H:i:s'),
        ]);
    }

    /** Ouvre la confirmation ; n'écrit rien. Réservé aux Administrateurs. */
    public function demanderRevocation(string $poste): void
    {
        $this->exigerAdministration();
        $this->refusRevocation = null;
        $this->posteARevoquer = $poste;
    }

    public function annulerRevocation(): void
    {
        $this->posteARevoquer = null;
    }

    public function revoquer(SuiviPostesService $suivi): void
    {
        $this->exigerAdministration();
        $poste = $this->posteARevoquer;
        $this->posteARevoquer = null;

        if ($poste === null) {
            return;
        }

        try {
            $suivi->revoquer($poste, Auth::user());
        } catch (RuntimeException $refus) {
            $this->refusRevocation = $refus->getMessage();

            return;
        }

        $this->confirmation = __('pwa.synchronisation_postes.revocation_faite', ['poste' => $poste]);
    }

    private function exigerAdministration(): void
    {
        abort_unless(Auth::user()?->estAdministrateur() ?? false, 403);
    }

    public function render(SuiviPostesService $suivi): View
    {
        return view('pwa.transverse.synchronisation-postes', array_merge($this->socle(), [
            'demande' => $suivi->derniereDemande(),
            'postes' => $suivi->etats(),
            'peutRevoquer' => Auth::user()?->estAdministrateur() ?? false,
            'peutVoirJournaux' => app(CorrectionReceptionService::class)->estAutorise(Auth::user()),
            'ongletActif' => $this->ongletPermis($this->onglet),
        ]))->layout('layouts.pwa', ['title' => __('pwa.synchronisation_postes.titre_page')]);
    }
}

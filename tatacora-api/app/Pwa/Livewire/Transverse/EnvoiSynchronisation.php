<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Models\User;
use App\Shared\Sync\Services\CatalogueDescendantService;
use App\Shared\Sync\Services\CorrectionReceptionService;
use App\Shared\Sync\Services\JournalEnvoiService;
use App\Shared\Sync\Services\SuiviPostesService;
use Illuminate\Contracts\View\View;
use Illuminate\Support\Facades\Auth;
use Livewire\Component;
use RuntimeException;

/**
 * L'onglet « Envoi » de « Postes & Appairage » — ce que le serveur a mis à
 * disposition des postes (demande du PO du 26/10/2026) : par poste, le dernier
 * passage, l'état du téléchargement, ce qui a été livré table par table, ce
 * qui reste à livrer, ce qui n'est pas livré faute de droit, les refus
 * « données réinitialisées ».
 *
 * « Redescendre depuis le début » — réservé aux Administrateurs — pose une
 * demande que le serveur consomme au prochain passage du poste : il ignore
 * alors le curseur du poste et le fait repartir du début. La demande de
 * synchronisation existante (`SuiviPostesService::demander`) l'invite à passer
 * dans la minute.
 *
 * Composant imbriqué (voir `ReceptionSynchronisation`) ; lecture réservée aux
 * Administrateurs et au Comptable.
 */
class EnvoiSynchronisation extends Component
{
    /** Le poste dont le détail est ouvert. */
    public ?string $detailPoste = null;

    /** Le poste dont la redescente attend confirmation. */
    public ?string $posteARedescendre = null;

    public ?string $confirmation = null;

    public ?string $refus = null;

    public function actualiser(): void
    {
        $this->confirmation = null;
        $this->refus = null;
    }

    public function voirPoste(string $poste): void
    {
        $this->exigerLecture();
        $this->detailPoste = $poste;
    }

    public function fermerPoste(): void
    {
        $this->detailPoste = null;
    }

    /** Ouvre la confirmation ; n'écrit rien. Réservé aux Administrateurs. */
    public function demanderRedescente(string $poste): void
    {
        $this->exigerAdministration();
        $this->refus = null;
        $this->posteARedescendre = $poste;
    }

    public function annulerRedescente(): void
    {
        $this->posteARedescendre = null;
    }

    public function redescendre(JournalEnvoiService $envoi, SuiviPostesService $suivi): void
    {
        $auteur = $this->exigerAdministration();
        $poste = $this->posteARedescendre;
        $this->posteARedescendre = null;

        if ($poste === null) {
            return;
        }

        try {
            $nouvelle = $envoi->demanderRedescente($poste, $auteur);
        } catch (RuntimeException $e) {
            $this->refus = $e->getMessage();

            return;
        }

        if (! $nouvelle) {
            $this->confirmation = __('synchronisation_journal.ecran.redescendre_deja', ['poste' => $poste]);

            return;
        }

        // Invite les postes à passer dans la minute (demande existante).
        $suivi->demander($auteur);
        $this->confirmation = __('synchronisation_journal.ecran.redescendre_fait', ['poste' => $poste]);
    }

    private function exigerLecture(): User
    {
        $utilisateur = Auth::user();
        abort_unless($utilisateur instanceof User && app(CorrectionReceptionService::class)->estAutorise($utilisateur), 403);

        return $utilisateur;
    }

    private function exigerAdministration(): User
    {
        $utilisateur = Auth::user();
        abort_unless($utilisateur instanceof User && $utilisateur->estAdministrateur(), 403);

        return $utilisateur;
    }

    public function render(JournalEnvoiService $envoi, CorrectionReceptionService $corrections, CatalogueDescendantService $catalogue): View
    {
        $utilisateur = Auth::user();

        if (! $utilisateur instanceof User || ! $corrections->estAutorise($utilisateur)) {
            return view('pwa.transverse.envoi-synchronisation', ['autorise' => false]);
        }

        return view('pwa.transverse.envoi-synchronisation', [
            'autorise' => true,
            'postes' => $envoi->resume(),
            'detail' => $this->detailPoste !== null ? $envoi->detail($this->detailPoste, $catalogue) : null,
            'peutRedescendre' => $utilisateur->estAdministrateur(),
        ]);
    }
}

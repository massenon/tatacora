<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Models\User;
use App\Shared\Sync\Models\JournalReceptionSynchronisation as Journal;
use App\Shared\Sync\Services\CorrectionReceptionService;
use App\Shared\Sync\Services\JournalReceptionService;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;

/**
 * « Synchronisation » — l'ÉTAT de la synchronisation : ce que les postes
 * envoient au serveur (journal de RÉCEPTION : accepté, rejeté, en conflit, avec
 * la cause, la correction et la relance) et ce que le serveur met à leur
 * disposition (journal d'ENVOI). Décision du PO du 09/11/2026 : l'entrée de
 * menu « Synchronisation » est visible de TOUS les rôles par défaut (droit
 * transverse `SYNCHRO`, lecture), au web comme au poste (`/synchronisation`).
 *
 * ## Pourquoi une page à part (et pas l'onglet de « Appairage Postes »)
 *
 * Les deux journaux vivaient en onglets de la page des postes appairés. Ce sont
 * deux sujets : l'APPAIRAGE (quels postes, révocation, demande de
 * synchronisation) et l'ÉTAT (ce qui est passé, ce qui a échoué, pourquoi). Le
 * poste les sépare depuis le 15/10/2026 (`/synchronisation` et
 * `/synchronisation-postes`) ; le web les sépare à son tour, les onglets
 * « Réception » et « Envoi » changent de page SANS changer de composant.
 *
 * ## Ce que voit chaque rôle
 *
 * - Administrateurs et Comptable : les deux journaux, comme avant (lecture,
 *   corrections, relances, redescente réservée aux administrateurs — gardes
 *   des composants imbriqués, inchangées).
 * - Tout autre rôle : la page, en LECTURE, et SES PROPRES échecs (les
 *   opérations rejetées, en conflit ou en erreur reçues sous son compte), sans
 *   aucun bouton d'action : ni correction, ni relance, ni redescente.
 */
#[Title('Synchronisation — LogiReStock — TATACORA AFRIQUE')]
class Synchronisation extends PageTransverse
{
    /** Les onglets des journaux : `reception`, `envoi`. */
    #[Url(as: 'onglet')]
    public string $onglet = 'reception';

    /** Combien d'échecs personnels la page montre au plus. */
    public const ECHECS_PERSONNELS_MAX = 25;

    /**
     * « Actualiser » : relit les journaux. Rien n'est écrit — le rendu suivant
     * interroge les services. Le bouton vit dans les composants imbriqués
     * (« Réception », « Envoi »), mais le DOM de la page les porte aussi :
     * la méthode existe donc ici, comme dans la page des postes.
     */
    public function actualiser(): void
    {
    }

    public function changerOnglet(string $onglet): void
    {
        $this->onglet = $this->ongletPermis($onglet);
    }

    private function ongletPermis(string $onglet): string
    {
        return $onglet === 'envoi' && $this->peutVoirJournaux() ? 'envoi' : 'reception';
    }

    /** Les journaux complets : administrateurs et comptable (règle du service). */
    private function peutVoirJournaux(): bool
    {
        return app(CorrectionReceptionService::class)->estAutorise(Auth::user());
    }

    public function render(JournalReceptionService $journal): View
    {
        $utilisateur = Auth::user();
        $journaux = $this->peutVoirJournaux();

        return view('pwa.transverse.synchronisation', array_merge($this->socle(), [
            'peutVoirJournaux' => $journaux,
            'ongletActif' => $this->ongletPermis($this->onglet),
            'mesEchecs' => $journaux || ! $utilisateur instanceof User
                ? collect()
                : Journal::query()
                    ->where('utilisateur_id', $utilisateur->id)
                    ->whereIn('issue', [Journal::REJETEE, Journal::CONFLIT, Journal::ERREUR])
                    ->orderByDesc('recu_le')
                    ->limit(self::ECHECS_PERSONNELS_MAX)
                    ->get(),
            'journal' => $journal,
            'libellesIssues' => (array) __('synchronisation_journal.issues'),
        ]))->layout('layouts.pwa', ['title' => __('pwa.synchronisation_page.titre_page')]);
    }
}

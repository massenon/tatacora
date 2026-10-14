<?php

declare(strict_types=1);

namespace App\Pwa\Http\Controllers;

use App\Domain\Ventes\Models\Vente;
use App\Http\Controllers\Controller;
use App\Models\User;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use Illuminate\Contracts\View\View;
use Illuminate\Support\Facades\Auth;

/**
 * TICKET DE CAISSE 80 mm — le TROISIÈME papier de la même pièce (PA-101).
 *
 * `05_MODULE_SPECIFICATIONS.md` §M14 : ticket et facture sont DEUX documents.
 * Ce module en ajoute un troisième RENDU de la même pièce — la vente — sur un
 * troisième papier (le rouleau du point de vente), jamais un troisième
 * modèle : mêmes lignes figées, même total, même mode de règlement que
 * `pdf.facture-ticket` (A4). Décision du Product Owner du 01/09/2026, en
 * attendant la validation de l'API MECeF par la Direction des impôts.
 *
 * ## Pourquoi un CONTRÔLEUR plutôt qu'un composant Livewire
 *
 * Toutes les pages PWA sont des composants Livewire — sauf celle-ci,
 * délibérément. Une fenêtre d'impression thermique n'a besoin d'aucune
 * interactivité après son premier rendu (`window.print()` suffit) : un
 * composant Livewire y ajouterait la coquille par défaut de
 * `SupportPageComponents` (une configuration `livewire.component_layout`
 * absente de ce dépôt lève `MissingLayoutException` si le composant
 * n'appelle pas `->layout()`) pour ne servir, au mieux, qu'un passe-plat.
 * Une route classique, protégée par le MÊME RBAC que le reste du module
 * (`module:M5,L`) et par `ForcerLectureSeule` (GET uniquement, déjà vrai
 * ici), est plus simple et n'introduit aucune action Livewire à inscrire
 * dans `PwaActionsReluesTest`/`PwaEcritureAutoriseeTest` — cette page ne
 * PERSISTE rien.
 *
 * ## Aucun cachet fiscal n'est inventé, comme les deux autres papiers
 *
 * Le format du QR MECeF n'est pas public (`MECEF_INTEGRATION_SPEC.md` §5).
 * La vue réserve et NOMME l'emplacement, sans rien de scannable. IFU et RCCM
 * viennent de `ReportHeaderService` (RG-19) — absents tant qu'ils ne sont pas
 * renseignés dans `parametres_systeme`, jamais un exemple de format.
 *
 * @see EF-M2-01 Émission de facture normalisée (le document A4, papier voisin)
 * @see docs/PLAN_ACTION_SEQUENCE_POST_AUDIT.md PA-101, PA-113
 */
class TicketThermiqueController extends Controller
{
    public function __invoke(string $vente, ReportHeaderService $entetes): View
    {
        $piece = Vente::query()->with('lignes')->findOrFail($vente);

        /** @var User|null $utilisateur */
        $utilisateur = Auth::user();

        return view('pwa.pos.ticket-thermique', [
            'vente' => $piece,
            'quand' => $piece->created_at?->format('d/m/Y H:i') ?? now()->format('d/m/Y H:i'),
            // En-tête établissement — même source (RG-19) que les deux
            // autres papiers, jamais recopiée en dur.
            'entete' => $entetes->genererEnTete(
                typeRapport: __('pos_pwa.document.ticket_titre'),
                periode: '',
                auteur: $utilisateur,
            ),
        ]);
    }
}

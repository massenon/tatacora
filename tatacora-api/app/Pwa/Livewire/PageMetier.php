<?php

declare(strict_types=1);

namespace App\Pwa\Livewire;

use App\Models\User;
use App\Pwa\Support\BanniereEcriture;
use App\Pwa\Support\FermeSession;
use App\Pwa\Support\IndicateurCaisse;
use App\Pwa\Support\MenuLateral;
use App\Shared\ReportEngine\Data\EnTeteRapport;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use Illuminate\Support\Facades\Auth;
use Livewire\Component;

/**
 * Socle commun à l'ensemble des composants de l'application Tatacora LogiRestock.
 */
abstract class PageMetier extends Component
{
    use FermeSession;

    /**
     * Données de socle fournies à la coquille et aux vues.
     *
     * @return array{
     *     utilisateur: User|null,
     *     menu: array<int, array<string, mixed>>,
     *     banniere: array{etat: string, module: string|null}
     * }
     */
    protected function socle(): array
    {
        /** @var User|null $utilisateur */
        $utilisateur = Auth::user();

        return [
            'utilisateur' => $utilisateur,
            'menu' => MenuLateral::pour($utilisateur),
            'banniere' => BanniereEcriture::pour($utilisateur, static::class),
            'caisse' => IndicateurCaisse::pour($utilisateur),
        ];
    }

    /**
     * L'en-tête RG-19 d'un document édité par cet écran — par le SEUL
     * `ReportHeaderService`, pour l'utilisateur RÉELLEMENT connecté.
     *
     * Ajouté le 11/09/2026 pour la mise en conformité des PDF d'export
     * (PA-192) : dix-neuf gabarits portaient une identité écrite à la main.
     * Un point d'appel unique évite qu'un écran recompose l'auteur ou la date
     * à sa façon — la dérive même que `RESPECT_TABLEAU_RAPPORT.md` §4 recense.
     *
     * @param  string  $typeRapport  le libellé exact du document, jamais un nom de route
     * @param  string  $periode      la période ou le filtre RÉELLEMENT appliqués (PA-119)
     */
    protected function enTeteRapport(string $typeRapport, string $periode): EnTeteRapport
    {
        $utilisateur = Auth::user();

        return app(ReportHeaderService::class)->genererEnTete(
            $typeRapport,
            $periode,
            // Sans utilisateur, le service écrit « Auteur non identifié » :
            // aucun nom n'est fabriqué.
            $utilisateur instanceof User ? $utilisateur : null,
        );
    }
}

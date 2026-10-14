<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Models\User;
use App\Pwa\Support\MenuLateral;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;

/**
 * ## PLUS AUCUNE SECTION DE REFUS N'EST AFFICHEE (directive du 31/08/2026)
 *
 * Cet ecran portait un panneau qui enumerait, pour l'utilisateur, ce qu'il ne
 * fait pas. Le Product Owner l'a retire : un ecran ne catalogue pas ses
 * absences. Les motifs eux-memes n'ont pas bouge de place ; les jetons
 * ci-dessous les rendent MESURABLES par `t-trois-sources.js`, ce qui est la
 * seule chose qui distingue une decision d'un oubli.
 *
 * ⚠ Rien n'est rendu inerte a la place : ce qui n'est pas porte est ABSENT,
 * pas grise (Article 3.3).
 *
 * Refus declares :
 *   maitre-refuse:aide-a-propos.html#alertes
 *   maitre-refuse:aide-a-propos.html#modeles-import
 */
#[Title('Aide & À propos — TATACORA AFRIQUE')]
class AideAPropos extends PageTransverse
{
    public const MODULES = [
        ['code' => 'M1', 'icone' => 'hebergement'],
        ['code' => 'M2', 'icone' => 'facturation'],
        ['code' => 'M3', 'icone' => 'crm'],
        ['code' => 'M4', 'icone' => 'restaurant'],
        ['code' => 'M5', 'icone' => 'bar'],
        ['code' => 'M6', 'icone' => 'stocks'],
        ['code' => 'M7', 'icone' => 'achats'],
        ['code' => 'M8', 'icone' => 'vehicules'],
        ['code' => 'M9', 'icone' => 'tourisme'],
        ['code' => 'M10', 'icone' => 'comptabilite'],
        ['code' => 'M11', 'icone' => 'dashboard'],
        ['code' => 'M12', 'icone' => 'notifications'],
        ['code' => 'M13', 'icone' => 'rh'],
        ['code' => 'M14', 'icone' => 'etats'],
        ['code' => 'ROLES', 'icone' => 'roles'],
        ['code' => 'PARAM', 'icone' => 'parametres'],
    ];

    public const ROUTES_MODULES = [
        'M1' => 'pwa.hebergement',
        'M2' => 'pwa.facturation',
        'M3' => 'pwa.clients',
        'M4' => 'pwa.restaurant.carte',
        'M5' => 'pwa.bar.carte',
        'M6' => 'pwa.stocks.liste',
        'M7' => 'pwa.achats.liste',
        'M8' => 'pwa.vehicules',
        'M9' => 'pwa.tourisme',
        'M10' => 'pwa.comptabilite.hub',
        'M11' => 'pwa.accueil',
        'M14' => 'pwa.etats.studio',
        'ROLES' => 'pwa.roles-permissions',
        'PARAM' => 'pwa.parametres',
    ];

    #[Url(as: 'q')]
    public string $recherche = '';

    /*
     * ⚠ `rejouerAlertes()` A ÉTÉ SUPPRIMÉE LE 31/08/2026, ET ELLE AFFIRMAIT.
     *
     * Elle ne faisait qu'un `session()->flash('succes', 'Alertes rafraîchies :
     * Aucun stock critique à déclarer.')` — une phrase écrite en dur, en
     * français, hors de `lang/`, qui déclarait un état de stock SANS AVOIR RIEN
     * LU. Sur un poste où trois articles étaient sous leur seuil, elle
     * répondait « aucun stock critique ». C'est PA-59/60/61 dans sa forme la
     * plus courte : un bouton qui dit que tout va bien pendant que rien n'a
     * lieu.
     *
     * Elle était de surcroît sans appelant : la vue ne la lie à aucun bouton,
     * et `pwa.aide.refus_alertes` dit déjà à l'écran pourquoi « Revoir mes
     * alertes » n'est pas proposé — aucune source d'alerte n'existe côté
     * serveur tant que M12 n'est pas contracté. Le code mort contredisait le
     * refus affiché à trois lignes de là.
     *
     * Son retour suppose une source réelle d'alertes, pas un message.
     */

    public function render(): View
    {
        $cartes = $this->cartes();

        return view('pwa.transverse.aide-a-propos', array_merge($this->socle(), [
            'titrePage' => 'Aide & À propos',
            'cartes' => $cartes,
            'accessibles' => count(array_filter($cartes, static fn (array $c): bool => $c['niveau'] !== '-')),
            'faq' => $this->faq(),
        ]))->layout('layouts.pwa', ['title' => 'Aide & À propos — TATACORA AFRIQUE']);
    }

    /** @return array<string, list<array{categorie: string, question: string, reponse: string}>> */
    protected function faq(): array
    {
        $entrees = (array) __('pwa.aide.faq');
        $terme = mb_strtolower($this->recherche);
        $groupes = [];

        foreach ($entrees as $entree) {
            if ($terme !== '' && ! str_contains(mb_strtolower($entree['question']), $terme) && ! str_contains(mb_strtolower($entree['reponse']), $terme)) {
                continue;
            }
            $groupes[$entree['categorie']][] = $entree;
        }

        return $groupes;
    }

    /** @return list<array{code: string, icone: string, nom: string, description: string, niveau: string, url: string|null}> */
    protected function cartes(): array
    {
        /** @var User|null $utilisateur */
        $utilisateur = Auth::user();
        $cartes = [];

        foreach (self::MODULES as $module) {
            $niveau = $utilisateur === null || ! $utilisateur->estActif()
                ? '-'
                : $utilisateur->niveauSurModule($module['code']);

            $route = self::ROUTES_MODULES[$module['code']] ?? null;

            $cartes[] = [
                'code' => $module['code'],
                'icone' => MenuLateral::ICONES[$module['icone']],
                'nom' => (string) __('pwa.aide.modules.'.$module['code'].'.nom'),
                'description' => (string) __('pwa.aide.modules.'.$module['code'].'.description'),
                'niveau' => $niveau,
                'url' => $route === null || $niveau === '-' ? null : route($route),
            ];
        }

        return $cartes;
    }
}

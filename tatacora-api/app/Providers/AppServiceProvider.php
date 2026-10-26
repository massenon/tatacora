<?php

declare(strict_types=1);

namespace App\Providers;

use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        // Lot F4 (17/10/2026) : le poste d'origine des documents, retenu
        // pendant qu'une opération de synchronisation est appliquée. Une
        // instance par requête ou par tâche (`scoped`) : une portée oubliée ne
        // déborde jamais sur la requête suivante.
        $this->app->scoped(\App\Shared\Sync\Support\OrigineDocuments::class);
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // La pagination du maitre, PARTOUT (02/09/2026, passage navigateur) :
        // la vue par defaut de Laravel rendait « Showing 1 to 10 of 83
        // results » — de l'anglais, en doublon de la ligne « Affichage de
        // X-Y sur Z » que chaque ecran pose deja. Voir le docblock de la vue.
        \Illuminate\Pagination\Paginator::defaultView('vendor.pagination.tatacora');
        \Illuminate\Pagination\Paginator::defaultSimpleView('vendor.pagination.tatacora');

        /*
         * « Suivant » MENE A LA PAGE SUIVANTE, pas au point d'entree de
         * Livewire — defaut signale par le Product Owner le 04/09/2026 :
         *
         *   MethodNotAllowedHttpException — The GET method is not supported
         *   for route `livewire-5f1c3da4/update`. Supported methods: POST.
         *
         * ## La racine
         *
         * Ce depot pagine SANS le trait `WithPagination` (PA-67) : la page
         * courante est une propriete `#[Url]` passee en quatrieme argument de
         * `paginate()`, et la vue rend de VRAIS liens `<a href>`. L'URL de ces
         * liens vient de `Paginator::resolveCurrentPath()`, dont le resolveur
         * par defaut de Laravel est `url()->current()`.
         *
         * Or la « page courante » d'un rendu Livewire n'est pas la page : c'est
         * `POST /livewire/update`. Tant qu'un ecran est rendu par son GET
         * initial les liens sont justes ; des qu'un rendu passe par Livewire —
         * un filtre tape, un onglet clique, une modale fermee — la pagination
         * se reecrit en `href="/livewire-xxxx/update?page=2"`, et le clic
         * suivant part en GET sur une route qui n'accepte que POST.
         *
         * ## Pourquoi ICI, et pas dans les vues
         *
         * Le defaut touche les SIX rendus de `->links()` du depot (Achats x2,
         * Facturation, Hebergement, Carte, Restauration). Le corriger vue par
         * vue avec un `->withPath(...)` aurait produit six ecritures qui
         * auraient fini par diverger, et le septieme ecran pagine serait ne
         * casse. Un seul auteur, a cote de la vue de pagination qu'il sert.
         *
         * `Livewire::originalUrl()` rend l'URL REELLE de la page pendant un
         * rendu Livewire (lue au memo de l'instantane) et retombe sur
         * `url()->current()` partout ailleurs — donc exactement sur le
         * comportement de Laravel hors Livewire.
         *
         * ⚠ Personne ne l'avait vu parce qu'il faut DEUX gestes pour
         * l'atteindre : provoquer un rendu Livewire, PUIS cliquer « Suivant ».
         * Tenu par `PaginationApresRenduLivewireTest`, qui rend sous une vraie
         * requete `X-Livewire` — un rendu de test ordinaire ne reproduit rien.
         */
        \Illuminate\Pagination\Paginator::currentPathResolver(
            static fn (): string => \Livewire\Livewire::originalUrl(),
        );

        // Les deux widgets IMBRIQUÉS de la barre supérieure (audit PO du
        // 01/09/2026). Les composants de PAGE sont montés par leurs routes
        // (`routes/web.php`) et n'ont pas besoin d'alias ; un composant
        // imbriqué dans un partial, si — le namespace par défaut de Livewire
        // (`App\Livewire`) ne couvre pas `App\Pwa\Livewire`.
        \Livewire\Livewire::component(
            'pwa.cloche-notifications',
            \App\Pwa\Livewire\Transverse\ClocheNotifications::class,
        );
        \Livewire\Livewire::component(
            'pwa.alertes-ouverture-modales',
            \App\Pwa\Livewire\Transverse\AlertesOuvertureModales::class,
        );
        \Livewire\Livewire::component(
            'pwa.recherche-globale',
            \App\Pwa\Livewire\Transverse\RechercheGlobale::class,
        );
        \Livewire\Livewire::component(
            'pwa.selecteur-exercice',
            \App\Pwa\Livewire\Transverse\SelecteurExercice::class,
        );
        // « Postes & Appairage » (26/10/2026) : les onglets Réception et Envoi.
        \Livewire\Livewire::component(
            'pwa.reception-synchronisation',
            \App\Pwa\Livewire\Transverse\ReceptionSynchronisation::class,
        );
        \Livewire\Livewire::component(
            'pwa.envoi-synchronisation',
            \App\Pwa\Livewire\Transverse\EnvoiSynchronisation::class,
        );
    }
}

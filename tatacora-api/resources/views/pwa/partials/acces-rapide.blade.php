{{--
    ACCÈS RAPIDE — bouton flottant + panneau offcanvas droit.

    Transcription de `prototype_v2/assets/js/acces-rapide.js`
    (`construirePanneau()`), Article 3.2 de `docs/DIRECTIVE_CONFORMITE_100.md`.

    ## Ce que cette réécriture répare (audit navigateur du 01/09/2026)

    Deux écarts au maître :

    1. Le bouton était `lg:hidden` — invisible au-delà de 1024 px. Le maître
       (l.256-264) ne le masque JAMAIS : « ne plus dépendre de la sidebar
       pour naviguer » (l.6-7) vaut precisement sur desktop, ou la sidebar
       est deja visible en permanence — c'est l'ecran mobile qui la
       remplacerait par un menu escamotable, pas l'inverse.
    2. Le tiroir rendait SIX raccourcis fixes, identiques sur les 39 ecrans
       servis. Le maître construit DEUX sections qui dependent de la page où
       l'on se trouve — « Sur cette page » (`ACTIONS_PAR_PAGE`) et « Aller à »
       (`RACCOURCIS_UNIVERSELS`, la page courante exclue) — voir
       `App\Pwa\Support\AccesRapide`, qui porte le detail des ecarts nommes
       (filtres de stock, formulaires d'approvisionnement, eclatement de
       m10-syscohada.html en plusieurs routes PWA).

    Le RBAC de niveau 1 (masquage d'interface) reste la MÊME règle partout —
    `MenuLateral::moduleAccessible()`, celle que `pour()` applique à la barre
    latérale et `peutVoirRoute()` à la barre supérieure et au menu de compte.
--}}
@php
    $utilisateurAccesRapide = Auth::user();
    $routeActuelleAccesRapide = \Illuminate\Support\Facades\Route::currentRouteName();
    $contextuellesAccesRapide = \App\Pwa\Support\AccesRapide::actionsContextuelles($utilisateurAccesRapide, $routeActuelleAccesRapide);
    $universellesAccesRapide = \App\Pwa\Support\AccesRapide::raccourcisUniversels($utilisateurAccesRapide, $routeActuelleAccesRapide);
    $sousTitreAccesRapide = \App\Pwa\Support\AccesRapide::libelleRoute($utilisateurAccesRapide, $routeActuelleAccesRapide);
@endphp
<div x-data="{ openDrawer: false }"
     @keydown.window.alt.a="openDrawer = !openDrawer"
     @keydown.escape.window="openDrawer = false">

  {{-- BOUTON FLOTTANT BAS-DROITE (Alt+A) — maquette l.257-264. Visible en
       desktop COMME au maître : aucune classe `lg:hidden` ici. --}}
  <button @click="openDrawer = !openDrawer"
          title="Accès Rapides (Alt+A)"
          aria-label="Accès Rapides"
          aria-expanded="false"
          :aria-expanded="openDrawer ? 'true' : 'false'"
          class="fixed bottom-6 right-6 z-40 w-14 h-14 rounded-full bg-[var(--navy)] text-white shadow-xl hover:bg-[var(--gold)] hover:scale-105 active:scale-95 transition-all flex items-center justify-center no-print">
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M13 2L3 14h9l-1 8 10-12h-9z"/></svg>
  </button>

  {{-- OVERLAY SOMBRE --}}
  <div x-show="openDrawer"
       x-transition.opacity
       class="fixed inset-0 bg-black/40 z-50 no-print"
       @click="openDrawer = false"
       style="display: none;"></div>

  {{-- PANNEAU OFFCANVAS DROIT — maquette l.268-296. --}}
  <aside x-show="openDrawer"
         x-transition:enter="transition transform duration-200"
         x-transition:enter-start="translate-x-full"
         x-transition:enter-end="translate-x-0"
         x-transition:leave="transition transform duration-200"
         x-transition:leave-start="translate-x-0"
         x-transition:leave-end="translate-x-full"
         class="fixed top-0 right-0 h-full w-[320px] max-w-[88vw] bg-white z-50 shadow-2xl flex flex-col no-print"
         style="display: none;">

    <header class="flex items-center justify-between px-4 py-3.5 border-b border-slate-200 shrink-0">
      <div>
        <h2 class="text-sm font-bold" style="color:var(--navy)">Accès rapides</h2>
        <p class="text-[11px] text-slate-400">{{ $sousTitreAccesRapide !== '' ? $sousTitreAccesRapide : __('pwa.marque') }}</p>
      </div>
      <button @click="openDrawer = false" aria-label="Fermer" class="p-1.5 rounded-lg hover:bg-slate-100 text-slate-400 hover:text-slate-700 transition-colors">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M18 6L6 18M6 6l12 12"/></svg>
      </button>
    </header>

    <div class="flex-1 overflow-y-auto py-3 px-2">
      @if ($contextuellesAccesRapide === [] && $universellesAccesRapide === [])
        <p class="px-3 py-8 text-center text-[13px] text-slate-400">Aucun accès rapide disponible pour votre rôle.</p>
      @else
        @if ($contextuellesAccesRapide !== [])
          <div class="mb-5">
            <p class="px-3 mb-1.5 text-[10px] font-bold uppercase tracking-wider text-slate-400">Sur cette page</p>
            <div class="space-y-0.5">
              @foreach ($contextuellesAccesRapide as $entree)
                <a href="{{ \App\Pwa\Support\AccesRapide::url($entree) }}" wire:navigate
                   class="acces-rapide-item w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-left text-[13px] text-slate-700 hover:bg-[var(--navy)] hover:text-white transition-colors">
                  <span class="shrink-0 text-[var(--gold)] group-hover:text-white">
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">{!! \App\Pwa\Support\AccesRapide::ICONES[$entree['icone']] !!}</svg>
                  </span>
                  <span class="flex-1">{{ $entree['libelle'] }}</span>
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="opacity-30"><path d="M9 18l6-6-6-6"/></svg>
                </a>
              @endforeach
            </div>
          </div>
        @endif

        @if ($universellesAccesRapide !== [])
          <div class="mb-5">
            <p class="px-3 mb-1.5 text-[10px] font-bold uppercase tracking-wider text-slate-400">Aller à</p>
            <div class="space-y-0.5">
              @foreach ($universellesAccesRapide as $entree)
                <a href="{{ \App\Pwa\Support\AccesRapide::url($entree) }}" wire:navigate
                   class="acces-rapide-item w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-left text-[13px] text-slate-700 hover:bg-[var(--navy)] hover:text-white transition-colors">
                  <span class="shrink-0 text-[var(--gold)] group-hover:text-white">
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">{!! \App\Pwa\Support\AccesRapide::ICONES[$entree['icone']] !!}</svg>
                  </span>
                  <span class="flex-1">{{ $entree['libelle'] }}</span>
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="opacity-30"><path d="M9 18l6-6-6-6"/></svg>
                </a>
              @endforeach
            </div>
          </div>
        @endif
      @endif
    </div>

    <footer class="px-4 py-2.5 border-t border-slate-200 shrink-0">
      <p class="text-[10px] text-slate-400 text-center">
        <kbd class="px-1.5 py-0.5 bg-slate-100 rounded font-sans">Alt</kbd> +
        <kbd class="px-1.5 py-0.5 bg-slate-100 rounded font-sans">A</kbd> pour ouvrir ·
        <kbd class="px-1.5 py-0.5 bg-slate-100 rounded font-sans">Échap</kbd> pour fermer
      </p>
    </footer>
  </aside>
</div>

{{--
    Pagination du maître — `crud-engine.js` `renderPagination()` (l.251-263),
    transcrite au pixel : « ← Précédent », « Page x / y », « Suivant → »,
    boutons `px-3 py-1.5 text-xs rounded-lg border border-slate-200`,
    inactifs à 40 % d'opacité.

    Créée le 02/09/2026 (passage navigateur) : la vue par défaut de Laravel
    rendait « Showing 1 to 10 of 83 results » — de l'ANGLAIS, en doublon de
    la ligne « Affichage de X-Y sur Z » que chaque écran pose déjà à gauche.
    `Paginator::defaultView()` la remplace PARTOUT (un seul auteur).

    La partie « Affichage de … » n'est PAS ici : chaque écran la rend déjà
    avec sa clé de langue, à la place exacte du maître.
--}}
@if ($paginator->hasPages())
  <nav role="navigation" aria-label="{{ __('pwa.pagination.navigation') }}" class="flex items-center gap-2">
    @if ($paginator->onFirstPage())
      <span class="px-3 py-1.5 text-xs rounded-lg border border-slate-200 text-slate-400 opacity-40 select-none">{{ __('pwa.pagination.precedent') }}</span>
    @else
      <a href="{{ $paginator->previousPageUrl() }}" rel="prev"
         class="px-3 py-1.5 text-xs rounded-lg border border-slate-200 text-slate-600 hover:bg-slate-50">{{ __('pwa.pagination.precedent') }}</a>
    @endif

    <span class="text-xs text-slate-600 px-2">{{ __('pwa.pagination.page_sur', ['page' => $paginator->currentPage(), 'pages' => $paginator->lastPage()]) }}</span>

    @if ($paginator->hasMorePages())
      <a href="{{ $paginator->nextPageUrl() }}" rel="next"
         class="px-3 py-1.5 text-xs rounded-lg border border-slate-200 text-slate-600 hover:bg-slate-50">{{ __('pwa.pagination.suivant') }}</a>
    @else
      <span class="px-3 py-1.5 text-xs rounded-lg border border-slate-200 text-slate-400 opacity-40 select-none">{{ __('pwa.pagination.suivant') }}</span>
    @endif
  </nav>
@endif

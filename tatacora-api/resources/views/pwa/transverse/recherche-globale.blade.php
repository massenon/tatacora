{{--
    Recherche globale — AJOUT à la maquette (audit PO du 01/09/2026), voir le
    docblock du composant. Le style reprend le vocabulaire de la barre du
    maître (fond `white/10`, texte blanc, arrondi `rounded-lg`) pour que
    l'ajout ne détonne pas dans une barre dont tout le reste est transcrit.
--}}
<div class="relative hidden md:block mr-3" x-data="{ ouvert: false }" @click.outside="ouvert = false">
  <div class="flex items-center gap-2 bg-white/10 border border-white/15 rounded-lg px-3 py-1.5 w-[125px] focus-within:border-white/40">
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="text-white/50 shrink-0"><circle cx="11" cy="11" r="8"/><path stroke-linecap="round" d="M21 21l-4.35-4.35"/></svg>
    <input type="search" wire:model.live.debounce.250ms="terme" @focus="ouvert = true" @input="ouvert = true"
           placeholder="{{ __('pwa.recherche_globale.invite') }}"
           class="bg-transparent text-xs text-white placeholder-white/40 outline-none w-full min-w-0 text-ellipsis"
           aria-label="{{ __('pwa.recherche_globale.invite') }}">
  </div>

  <div x-show="ouvert" x-cloak
       class="absolute left-0 top-11 w-[420px] max-w-[90vw] bg-white rounded-xl shadow-2xl border border-slate-100 z-50 overflow-hidden"
       @if (trim($terme) === '') style="display:none" @endif>
    @if (mb_strlen(trim($terme)) < 2)
      <p class="px-4 py-5 text-center text-[12px] text-slate-400">{{ __('pwa.recherche_globale.trop_court') }}</p>
    @elseif ($resultats['pages'] === [] && $resultats['donnees'] === [])
      <p class="px-4 py-5 text-center text-[12px] text-slate-400">{{ __('pwa.recherche_globale.aucun') }}</p>
    @else
      <div class="max-h-96 overflow-y-auto py-1.5">
        @if ($resultats['pages'] !== [])
          <p class="px-4 pt-2 pb-1 text-[10px] font-bold tracking-wider text-slate-400 uppercase">{{ __('pwa.recherche_globale.famille_pages') }}</p>
          @foreach ($resultats['pages'] as $page)
            <a href="{{ $page['url'] }}" wire:navigate class="flex items-center gap-2.5 px-4 py-2 text-xs text-slate-700 hover:bg-slate-50">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="text-slate-400 shrink-0"><path stroke-linecap="round" stroke-linejoin="round" d="M5 12h14M12 5l7 7-7 7"/></svg>
              <span class="font-semibold">{{ $page['libelle'] }}</span>
            </a>
          @endforeach
        @endif
        @foreach ($resultats['donnees'] as $famille => $lignes)
          @php
            // Clés LITTÉRALES via match — jamais une clé concaténée, que
            // `MessagesUtilisateurTest` ne saurait plus relier au fichier.
            $titreFamille = match ($famille) {
                'clients' => __('pwa.recherche_globale.famille_clients'),
                'articles' => __('pwa.recherche_globale.famille_articles'),
                'plats' => __('pwa.recherche_globale.famille_plats'),
                'carte_bar' => __('pwa.recherche_globale.famille_carte_bar'),
                'factures' => __('pwa.recherche_globale.famille_factures'),
                'fournisseurs' => __('pwa.recherche_globale.famille_fournisseurs'),
                'vehicules' => __('pwa.recherche_globale.famille_vehicules'),
                'circuits' => __('pwa.recherche_globale.famille_circuits'),
                default => $famille,
            };
          @endphp
          <p class="px-4 pt-2 pb-1 text-[10px] font-bold tracking-wider text-slate-400 uppercase">{{ $titreFamille }}</p>
          @foreach ($lignes as $ligne)
            <a href="{{ $ligne['url'] }}" wire:navigate class="block px-4 py-2 text-xs text-slate-700 hover:bg-slate-50">
              {{ $ligne['libelle'] }}
            </a>
          @endforeach
        @endforeach
      </div>
    @endif
  </div>
</div>

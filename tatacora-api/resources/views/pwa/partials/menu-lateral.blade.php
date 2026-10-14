<div id="shell-sidebar">
  <aside id="sidebar" class="w-[264px] bg-[var(--navy)] shrink-0 flex flex-col h-full fixed lg:static inset-y-0 left-0 z-40 -translate-x-full lg:translate-x-0 transition-transform duration-200">
    <nav class="flex-1 overflow-y-auto pb-3 pt-2 sidebar-nav">
      @foreach ($menu as $section)
        @if ($section['epingle'])
          @foreach ($section['items'] as $item)
            <div class="epingle">
              @include('pwa.partials.entree-menu', ['item' => $item])
            </div>
          @endforeach
        @else
          <p class="px-4 pt-3 pb-1 text-[10.5px] font-bold tracking-wider text-white/45">{{ \Illuminate\Support\Str::upper($section['groupe']) }}</p>
          @foreach ($section['items'] as $item)
            @include('pwa.partials.entree-menu', ['item' => $item])
          @endforeach
        @endif
      @endforeach
    </nav>
    <div class="border-t border-white/10 px-4 py-3">
      <div class="flex items-center gap-2.5 mb-2.5">
        <div class="w-8 h-8 rounded-full bg-[var(--gold)] flex items-center justify-center text-[var(--navy)] font-bold text-xs shrink-0">{{ \App\Pwa\Support\MenuLateral::initiales($utilisateur) }}</div>
        <div class="min-w-0">
          <p class="text-white text-xs font-semibold truncate">{{ $utilisateur?->login }}</p>
          <p class="text-white/40 text-[10px] truncate">{{ \Illuminate\Support\Str::ucfirst($utilisateur?->role?->libelle ?? '') }}</p>
        </div>
      </div>
      {{-- Fond ROUGE — directive PO du 03/09/2026 : ecart au maitre
           (shell.js pose bg-white/10) DECIDE et declare a la garde des
           classes de la barre laterale. --}}
      <button id="bouton-deconnexion-sidebar" type="button" wire:click="seDeconnecter" class="w-full flex items-center justify-center gap-2 bg-[var(--erreur)] hover:brightness-110 text-white text-xs font-semibold rounded-lg py-2 transition-colors">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M9 21H5a2 2 0 01-2-2V5a2 2 0 012-2h4M16 17l5-5-5-5M21 12H9"/></svg>
        {{ __('pwa.accueil.deconnexion') }}
      </button>
      <p class="text-white/25 text-[10px] mt-2.5 text-center">{{ __('pwa.mention_pied_menu') }}</p>
    </div>
  </aside>
  <div id="overlay-sidebar-mobile" class="fixed inset-0 bg-black/40 z-30 hidden lg:hidden"></div>
</div>

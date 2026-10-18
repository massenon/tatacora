<div class="contents">

  @include('pwa.partials.barre-superieure')

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8" wire:poll.15s>

        <div class="mb-5 flex flex-col lg:flex-row lg:items-end gap-4">
          <div class="flex-1">
            <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('pwa.synchronisation_postes.titre') }}</h1>
            <p class="text-[15px] text-slate-500 mt-1.5">{{ __('pwa.synchronisation_postes.sous_titre') }}</p>
          </div>
          <button id="bouton-synchroniser-postes" type="button" wire:click="synchroniser" wire:loading.attr="disabled"
                  class="bouton-primaire rounded-lg px-5 py-2.5 text-sm font-semibold text-white bg-[var(--navy)] hover:opacity-90">
            {{ __('pwa.synchronisation_postes.bouton') }}
          </button>
        </div>

        @if ($confirmation)
          <div id="confirmation-synchronisation" class="mb-4 rounded-lg border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-800">{{ $confirmation }}</div>
        @endif

        <p id="derniere-demande" class="mb-4 text-sm text-slate-600">
          @if ($demande)
            {{ __('pwa.synchronisation_postes.derniere_demande', ['date' => $demande->demandee_le->format('d/m/Y H:i:s')]) }}
          @else
            {{ __('pwa.synchronisation_postes.aucune_demande') }}
          @endif
        </p>

        <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead class="bg-[var(--navy)]">
                <tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
                  <th class="px-5 py-3">{{ __('pwa.synchronisation_postes.col_poste') }}</th>
                  <th class="px-5 py-3">{{ __('pwa.synchronisation_postes.col_compte') }}</th>
                  <th class="px-5 py-3">{{ __('pwa.synchronisation_postes.col_montee') }}</th>
                  <th class="px-5 py-3">{{ __('pwa.synchronisation_postes.col_descente') }}</th>
                  <th class="px-5 py-3">{{ __('pwa.synchronisation_postes.col_attente') }}</th>
                  <th class="px-5 py-3">{{ __('pwa.synchronisation_postes.col_demande') }}</th>
                </tr>
              </thead>
              <tbody id="corps-postes">
                @forelse ($postes as $poste)
                  <tr class="border-t border-slate-100">
                    <td class="px-5 py-3 font-medium text-slate-700">{{ $poste['poste_id'] }}</td>
                    <td class="px-5 py-3 text-slate-600">{{ $poste['utilisateur'] ?? __('pwa.synchronisation_postes.jamais') }}</td>
                    <td class="px-5 py-3 text-slate-600">{{ $poste['derniere_montee']?->format('d/m/Y H:i') ?? __('pwa.synchronisation_postes.jamais') }}</td>
                    <td class="px-5 py-3 text-slate-600">{{ $poste['derniere_descente']?->format('d/m/Y H:i') ?? __('pwa.synchronisation_postes.jamais') }}</td>
                    <td class="px-5 py-3 text-slate-600">{{ $poste['en_attente'] ?? __('pwa.synchronisation_postes.jamais') }}</td>
                    <td class="px-5 py-3 {{ $poste['demande_suivie'] ? 'text-emerald-700' : 'text-amber-700' }}">
                      {{ $poste['demande_suivie'] ? __('pwa.synchronisation_postes.demande_suivie') : __('pwa.synchronisation_postes.demande_non_suivie') }}
                    </td>
                  </tr>
                @empty
                  <tr><td colspan="6" class="px-5 py-6 text-center text-slate-500">{{ __('pwa.synchronisation_postes.aucun_poste') }}</td></tr>
                @endforelse
              </tbody>
            </table>
          </div>
        </div>

        <p class="mt-4 text-[13px] text-slate-500">{{ __('pwa.synchronisation_postes.note') }}</p>
      </div>
    </main>
  </div>
</div>

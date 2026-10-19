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

        @if ($refusRevocation)
          <div id="refus-revocation" class="mb-4 rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">{{ $refusRevocation }}</div>
        @endif

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
                  <th class="px-5 py-3">{{ __('pwa.synchronisation_postes.col_appairage') }}</th>
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
                    <td class="px-5 py-3">
                      <div class="flex items-center gap-3">
                        <span class="{{ $poste['appaire'] ? 'text-emerald-700' : 'text-slate-500' }}">
                          @if ($poste['appaire'])
                            {{ $poste['jeton_utilise_le'] ? __('pwa.synchronisation_postes.appaire_utilise', ['date' => $poste['jeton_utilise_le']->format('d/m/Y H:i')]) : __('pwa.synchronisation_postes.appaire') }}
                          @else
                            {{ __('pwa.synchronisation_postes.revoque') }}
                          @endif
                        </span>
                        @if ($peutRevoquer && $poste['appaire'])
                          <button type="button" wire:click="demanderRevocation(@js($poste['poste_id']))"
                                  class="text-[13px] px-3 py-1.5 rounded-lg border border-red-200 text-red-700 hover:bg-red-50">{{ __('pwa.synchronisation_postes.bouton_revoquer') }}</button>
                        @endif
                      </div>
                    </td>
                  </tr>
                @empty
                  <tr><td colspan="7" class="px-5 py-6 text-center text-slate-500">{{ __('pwa.synchronisation_postes.aucun_poste') }}</td></tr>
                @endforelse
              </tbody>
            </table>
          </div>
        </div>

        <p class="mt-4 text-[13px] text-slate-500">{{ __('pwa.synchronisation_postes.note') }}</p>
      </div>
    </main>
  </div>

  {{-- Confirmation de révocation — derrière `@if`, jamais `wire:confirm`. --}}
  @if ($posteARevoquer !== null)
    <x-pwa.modale :titre="__('pwa.synchronisation_postes.revocation_titre', ['poste' => $posteARevoquer])" largeur="480px" fermer="annulerRevocation">
      <p class="text-sm text-slate-600">{{ __('pwa.synchronisation_postes.revocation_texte') }}</p>
      <x-slot:pied>
        <button type="button" wire:click="annulerRevocation" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button id="confirmer-revocation" type="button" wire:click="revoquer" class="text-[13px] px-4 py-2 rounded-lg bg-red-600 text-white font-semibold">{{ __('pwa.synchronisation_postes.revocation_confirmer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif
</div>

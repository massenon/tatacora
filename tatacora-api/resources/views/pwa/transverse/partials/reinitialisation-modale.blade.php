  {{-- ============== MODALE — RÉINITIALISATION (markup du maître, l.313-339).
       Rendue derrière la condition d'état : un formulaire d'écriture ne se
       rend jamais au premier GET (doctrine RefuseLaSaisie). Le bouton reste
       inerte tant que la phrase n'est pas tapée — la garde d'interface du
       maître (l.864-866) ; le serveur revalide la phrase ET les deux verrous. --}}
  @if ($etatFormulaire === 'reinitialisation')
    <div class="overlay-modale no-print" style="display:flex" wire:keydown.escape.window="fermerReinitialisation"
         x-data="{ saisie: '' }">
      <div class="absolute inset-0" wire:click="fermerReinitialisation"></div>
      <div class="boite-modale relative max-w-lg">
        <div class="flex items-start gap-3 px-6 pt-6 pb-4">
          <div class="w-10 h-10 rounded-full flex items-center justify-center shrink-0" style="background:#FDECEC">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--erreur)" stroke-width="2.2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/></svg>
          </div>
          <div class="min-w-0">
            <h2 class="text-base font-bold" style="color:var(--erreur)">{{ __('pwa.import_export.seeders_modale_titre') }}</h2>
            <p class="text-[15px] text-slate-600 mt-1.5 leading-relaxed">
              <strong>{{ __('pwa.import_export.seeders_modale_texte_avant', ['nombre' => count($tablesEffacables)]) }}</strong>
              {{ __('pwa.import_export.seeders_modale_texte_1') }}<br><br>
              {{ __('pwa.import_export.seeders_modale_texte_2') }}
              <strong>{{ __('pwa.import_export.seeders_modale_texte_2_fort') }}</strong>{{ __('pwa.import_export.seeders_modale_texte_2_fin') }}
            </p>
          </div>
        </div>
        <div class="px-6 pb-2">
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">
            {{ __('pwa.import_export.seeders_confirmation_avant') }}
            <span class="font-mono-tatacora px-1.5 py-0.5 rounded bg-slate-100" style="color:var(--erreur)">{{ __('pwa.import_export.seeders_phrase_confirmation') }}</span>
          </label>
          <input type="text" autocomplete="off" placeholder="{{ __('pwa.import_export.seeders_phrase_confirmation') }}"
                 wire:model="phraseConfirmationReset" x-on:input="saisie = $event.target.value"
                 class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm font-mono-tatacora">
          <p class="text-[12px] text-slate-400 mt-1.5">{{ __('pwa.import_export.seeders_confirmation_aide') }}</p>
          @error('phraseConfirmationReset') <p class="text-[12px] text-red-600 mt-1.5">{{ $message }}</p> @enderror
        </div>
        <div class="flex justify-end gap-3 px-6 py-5">
          <button type="button" wire:click="fermerReinitialisation"
                  class="btn px-5 py-2.5 rounded-lg border border-slate-200 bg-white text-sm font-semibold text-slate-600">{{ __('pwa.modale.annuler') }}</button>
          <button type="button" wire:click="reinitialiserDonneesTest" wire:loading.attr="disabled"
                  :disabled="saisie.trim().toUpperCase() !== '{{ __('pwa.import_export.seeders_phrase_confirmation') }}'"
                  class="btn px-5 py-2.5 rounded-lg text-white text-sm font-semibold disabled:opacity-50" style="background:var(--erreur)">{{ __('pwa.import_export.seeders_confirmer') }}</button>
        </div>
      </div>
    </div>
  @endif


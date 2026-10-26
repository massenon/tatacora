<div class="contents">

  @include('pwa.partials.barre-superieure')


  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        <div class="mb-6">
          <div class="flex items-center gap-2.5">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M4 4h16a2 2 0 012 2v12a2 2 0 01-2 2H4a2 2 0 01-2-2V6a2 2 0 012-2z"/><path stroke-linecap="round" stroke-linejoin="round" d="M22 6l-10 7L2 6"/></svg>
            <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('pwa.contact.titre') }}</h1>
          </div>
          <p class="text-[15px] text-slate-500 mt-1.5">{{ __('pwa.contact.sous_titre') }}</p>
        </div>

        @include('pwa.partials.toast-succes')

        <div class="rounded-xl border p-4 mb-6 flex flex-col sm:flex-row sm:items-center gap-3" style="background:#FFFBEB;border-color:#FDE68A">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--gold)" stroke-width="2.2" class="shrink-0"><path stroke-linecap="round" stroke-linejoin="round" d="M9 18h6M10 22h4M12 2a7 7 0 00-4 12.7V17h8v-2.3A7 7 0 0012 2z"/></svg>
          <div class="min-w-0">
            <p class="text-[15px] font-bold" style="color:#7C5E12">{{ __('pwa.contact.avant_titre') }}</p>
            <p class="text-[13px] mt-0.5" style="color:#7C5E12">
              {{ __('pwa.contact.avant_detail_avant') }}<a href="{{ route('pwa.aide-a-propos') }}" wire:navigate class="underline font-semibold">{{ __('pwa.contact.avant_lien') }}</a>{{ __('pwa.contact.avant_detail_apres') }}
            </p>
          </div>
          <a href="{{ route('pwa.aide-a-propos') }}" wire:navigate class="btn sm:ml-auto shrink-0 px-4 py-2 rounded-lg text-[13px] font-semibold text-white" style="background:var(--gold)">{{ __('pwa.contact.avant_bouton') }}</a>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-5">

          {{-- ======================= Colonne formulaires ======================= --}}
          <div class="lg:col-span-2 space-y-5">

            {{-- Onglets — RESTENT deux boutons, mais ouvrent une modale au lieu
                 de découvrir un panneau déjà présent dans le DOM
                 (`RefuseLaSaisie` : aucun formulaire au premier GET). --}}
            <div class="flex gap-2">
              <button type="button" wire:click="ouvrirFormulaireMessage"
                      class="flex items-center gap-2 px-4 py-2.5 rounded-lg text-[15px] font-semibold bg-[var(--navy)] text-white">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M22 2L11 13M22 2l-7 20-4-9-9-4 20-7z"/></svg>
                {{ __('pwa.contact.onglet_message') }}
              </button>
              <button type="button" wire:click="ouvrirFormulaireBug"
                      class="flex items-center gap-2 px-4 py-2.5 rounded-lg text-[15px] font-semibold border border-slate-200 bg-white text-slate-500">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="8" y="6" width="8" height="14" rx="4"/><path stroke-linecap="round" d="M19 8l-3 2M5 8l3 2M19 16l-3-2M5 16l3-2M12 6V4M9 4h6"/></svg>
                {{ __('pwa.contact.onglet_bug') }}
              </button>
            </div>

            {{-- ------------------------ Historique des envois ----------------- --}}
            <section class="bg-white rounded-xl border border-slate-200 overflow-hidden">
              <div class="px-5 py-3.5 border-b border-slate-100">
                <h2 class="text-sm font-bold text-slate-700">{{ __('pwa.contact.envois_titre') }}</h2>
                <p class="text-[12px] text-slate-500 mt-0.5">{{ __('pwa.contact.envois_sous_titre') }}</p>
              </div>
              <div class="divide-y divide-slate-100">
                @forelse ($envois as $envoi)
                  <div class="px-5 py-3.5">
                    <div class="flex items-start gap-2.5">
                      <span class="mt-1 shrink-0 text-[10px] font-bold rounded px-1.5 py-0.5"
                            style="background:{{ $envoi->type === 'bug' ? '#FDECEC' : '#E8EEFD' }};color:{{ $envoi->type === 'bug' ? 'var(--erreur)' : 'var(--info)' }}">
                        {{ $envoi->type === 'bug' ? 'BUG' : 'MESSAGE' }}
                      </span>
                      <div class="min-w-0 flex-1">
                        <p class="text-[15px] font-semibold text-slate-700">{{ $envoi->objet }}</p>
                        <p class="text-[13px] text-slate-500 mt-0.5 leading-relaxed">{{ \Illuminate\Support\Str::limit($envoi->corps, 180) }}</p>
                        <p class="text-[12px] text-slate-400 mt-1">
                          {{ $envoi->date_creation?->format('d/m/Y H:i') }}
                          @if ($envoi->capture_nom)
                            · {{ __('pwa.contact.envois_capture') }}
                          @endif
                          · <span style="color:{{ $envoi->estTransmis() ? 'var(--succes)' : 'var(--alerte)' }}">{{ $envoi->estTransmis() ? __('pwa.contact.envois_statut_transmis') : __('pwa.contact.envois_statut_a_transmettre') }}</span>
                        </p>
                        @if (! $envoi->estTransmis() && $envoi->derniere_erreur)
                          <p class="text-[12px] mt-1" style="color:var(--erreur)">{{ __('pwa.contact.envois_derniere_erreur', ['erreur' => $envoi->derniere_erreur]) }}</p>
                        @endif
                      </div>
                    </div>
                  </div>
                @empty
                  <p class="px-5 py-8 text-center text-[13px] text-slate-400">{{ __('pwa.contact.envois_vide') }}</p>
                @endforelse
              </div>
            </section>
          </div>

          {{-- ====================== Colonne coordonnées ======================== --}}
          <aside class="space-y-5">
            <section class="bg-white rounded-xl border border-slate-200 p-5">
              <h2 class="text-sm font-bold text-slate-700 mb-3.5">{{ __('pwa.contact.coordonnees_titre') }}</h2>
              <div class="flex items-center gap-3 mb-4">
                <div class="w-11 h-11 rounded-full flex items-center justify-center text-white font-bold text-sm shrink-0" style="background:var(--navy)">{{ __('pwa.contact.editeur_initiales') }}</div>
                <div class="min-w-0">
                  <p class="text-[15px] font-bold text-slate-800">{{ __('pwa.contact.editeur_nom') }}</p>
                  <p class="text-[13px] text-slate-500">{{ __('pwa.contact.editeur_fonction') }}</p>
                </div>
              </div>
              <div class="space-y-3">
                <div class="flex items-start gap-2.5">
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--gold)" stroke-width="2" class="shrink-0 mt-0.5"><path stroke-linecap="round" stroke-linejoin="round" d="M4 4h16a2 2 0 012 2v12a2 2 0 01-2 2H4a2 2 0 01-2-2V6a2 2 0 012-2z"/><path stroke-linecap="round" stroke-linejoin="round" d="M22 6l-10 7L2 6"/></svg>
                  <div class="min-w-0">
                    <a href="mailto:{{ __('pwa.contact.editeur_email_1') }}" class="block text-[13px] text-slate-700 hover:underline break-all">{{ __('pwa.contact.editeur_email_1') }}</a>
                    <a href="mailto:{{ __('pwa.contact.editeur_email_2') }}" class="block text-[13px] text-slate-700 hover:underline break-all">{{ __('pwa.contact.editeur_email_2') }}</a>
                  </div>
                </div>
                <div class="flex items-center gap-2.5">
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--gold)" stroke-width="2" class="shrink-0"><path stroke-linecap="round" stroke-linejoin="round" d="M22 16.92v3a2 2 0 01-2.18 2 19.79 19.79 0 01-8.63-3.07 19.5 19.5 0 01-6-6A19.79 19.79 0 012.12 4.18 2 2 0 014.11 2h3a2 2 0 012 1.72c.13.96.36 1.9.7 2.81a2 2 0 01-.45 2.11L8.09 9.91a16 16 0 006 6l1.27-1.27a2 2 0 012.11-.45c.9.34 1.85.57 2.81.7A2 2 0 0122 16.92z"/></svg>
                  <a href="tel:+2290151335040" class="text-[13px] text-slate-700 hover:underline">{{ __('pwa.contact.editeur_telephone') }}</a>
                </div>
                <div class="flex items-center gap-2.5">
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--gold)" stroke-width="2" class="shrink-0"><circle cx="12" cy="12" r="10"/><path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6l4 2"/></svg>
                  <span class="text-[13px] text-slate-700">{{ __('pwa.contact.editeur_horaires') }}</span>
                </div>
              </div>
            </section>
            {{-- Les deux encarts « Sur cette maquette » / « Ce qui accompagne
                 votre envoi » du maître ne sont pas rendus : leurs deux
                 phrases sont devenues fausses (voir le docblock de
                 `ContactEditeur`), et une phrase qui décrit la maquette
                 mentirait sur cet écran. --}}
          </aside>
        </div>

      </div>
    </main>
  </div>

  {{-- ============================== Modale « Envoyer un message » ========= --}}
  @if ($etatFormulaire === 'message')
    <x-pwa.modale :titre="__('pwa.contact.onglet_message')" :sousTitre="__('pwa.contact.message_sous_titre')" largeur="560px">
      <div class="groupe-champ">
        <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.contact.message_objet') }}</label>
        <input type="text" wire:model="objetMessage" placeholder="{{ __('pwa.contact.message_objet_invite') }}"
               class="w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
        @error('objetMessage')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
      </div>
      <div class="groupe-champ">
        <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.contact.message_corps') }}</label>
        <textarea wire:model="corpsMessage" rows="6" placeholder="{{ __('pwa.contact.message_corps_invite') }}"
                  class="w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm"></textarea>
        @error('corpsMessage')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
      </div>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="envoyerMessage"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('pwa.contact.message_bouton') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ============================== Modale « Signaler un bug » ============ --}}
  @if ($etatFormulaire === 'bug')
    <x-pwa.modale :titre="__('pwa.contact.onglet_bug')" :sousTitre="__('pwa.contact.bug_sous_titre')" largeur="560px">
      <div class="groupe-champ">
        <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.contact.bug_module') }}</label>
        <select wire:model="moduleBug" class="w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
          <option value="">{{ __('pwa.contact.bug_module_invite') }}</option>
          @foreach (\App\Pwa\Livewire\Transverse\ContactEditeur::MODULES as $module)
            <option value="{{ $module }}">{{ $module }}</option>
          @endforeach
        </select>
        @error('moduleBug')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
      </div>
      <div class="groupe-champ">
        <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.contact.bug_description') }}</label>
        <textarea wire:model="descriptionBug" rows="4" placeholder="{{ __('pwa.contact.bug_description_invite') }}"
                  class="w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm"></textarea>
        @error('descriptionBug')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
      </div>
      <div class="groupe-champ">
        <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.contact.bug_etapes') }}</label>
        <textarea wire:model="etapesBug" rows="3" placeholder="{{ __('pwa.contact.bug_etapes_invite') }}"
                  class="w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm"></textarea>
        <p class="text-[12px] text-slate-400 mt-1.5">{{ __('pwa.contact.bug_etapes_note') }}</p>
        @error('etapesBug')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
      </div>
      <div>
        <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.contact.bug_capture') }}</label>
        <input type="file" wire:model="captureBug" accept="image/png,image/jpeg"
               class="w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
        <p class="text-[12px] text-slate-400 mt-1.5">{{ __('pwa.contact.bug_capture_invite') }}</p>
        @error('captureBug')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
      </div>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="signalerBug"
                class="text-[13px] px-4 py-2 rounded-lg text-white font-semibold hover:opacity-90" style="background:var(--erreur)">{{ __('pwa.contact.bug_bouton') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

</div>

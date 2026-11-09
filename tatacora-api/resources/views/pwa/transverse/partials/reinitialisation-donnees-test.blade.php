{{-- RÉINITIALISER LES DONNÉES DE TEST (09/11/2026, PO : « Ramène le bouton … dans
     PARAMÈTRES »). Le panneau de l'ancien onglet d'Import & Export, déplacé tel quel :
     mêmes verrous, mêmes listes, même modale à phrase, bouton marine. --}}
<div id="reinitialisation-donnees-test" class="mt-5 pt-4 border-t border-slate-100">
  <h3 class="text-sm font-bold text-slate-700 mb-1">{{ __('pwa.import_export.onglet_seeders') }}</h3>
          @unless ($reinitialisationAutorisee)
            <div class="rounded-xl p-4 mb-5" style="background:#FEF2F2;border:1px solid #FECACA">
              <p class="text-[13px]" style="color:#7F1D1D">{{ __('pwa.import_export.reset_environnement_production') }}</p>
            </div>
          @endunless

          {{-- Phase d'essais en production (19/10/2026, décision du PO) :
               `TATACORA_PHASE_ESSAIS=true` au `.env`. Dit tant qu'elle dure. --}}
          @if ($reinitialisationPhaseEssais)
            <div id="phase-essais" class="rounded-xl p-4 mb-5" style="background:#FFFBEB;border:1px solid #FDE68A">
              <p class="text-[13px]" style="color:#78350F">{{ __('pwa.import_export.reset_phase_essais') }}</p>
            </div>
          @endif

          @if (! $reinitialisationOuverte)
            {{-- L'état VERROUILLÉ du maître (l.261-273) — la bascule
                 `reinitialisation_seeders` est fermée. --}}
            <div class="bg-white rounded-xl border border-slate-200 p-8 text-center">
              <div class="w-12 h-12 rounded-full mx-auto mb-3 flex items-center justify-center" style="background:#F3F4F6">
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" stroke-width="2"><rect x="3" y="11" width="18" height="11" rx="2"/><path stroke-linecap="round" d="M7 11V7a5 5 0 0110 0v4"/></svg>
              </div>
              <p class="text-sm font-bold text-slate-700">{{ __('pwa.import_export.seeders_verrouille_titre') }}</p>
              <p class="text-[15px] text-slate-500 mt-1.5 max-w-lg mx-auto">{{ __('pwa.import_export.seeders_verrouille_texte') }}</p>
            </div>
          @else
            <div class="rounded-xl border p-4 mb-5 flex items-start gap-3" style="background:#FDECEC;border-color:#F5B5B5">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--erreur)" stroke-width="2.2" class="shrink-0 mt-0.5"><path stroke-linecap="round" stroke-linejoin="round" d="M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/></svg>
              <div class="min-w-0">
                <p class="text-[15px] font-bold" style="color:#8C1D1D">{{ __('pwa.import_export.seeders_bandeau_titre') }}</p>
                <p class="text-[13px] mt-1 leading-relaxed" style="color:#8C1D1D">{{ __('pwa.import_export.seeders_bandeau_texte') }}</p>
              </div>
            </div>

            {{-- Les deux listes du maître (l.287-299), pastilles comprises
                 (rendu de `rendreSeeders`, l.730-742) — DÉRIVÉES du réel :
                 `ReinitialisationDonneesTestService::tablesEffacables()` et
                 `tablesPreservees()`, mesurées sur la base. --}}
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-5">
              <section class="bg-white rounded-xl border border-slate-200 p-5">
                <h2 class="text-sm font-bold mb-1" style="color:var(--erreur)">{{ __('pwa.import_export.seeders_vide_titre') }}</h2>
                <p class="text-[13px] text-slate-500 mb-3">{{ __('pwa.import_export.seeders_vide_texte') }}</p>
                <div class="space-y-1 max-h-72 overflow-y-auto">
                  @forelse ($tablesEffacables as $table)
                    <div class="flex items-center gap-2 px-3 py-1.5 rounded-lg" style="background:#FDECEC">
                      <span class="w-1.5 h-1.5 rounded-full shrink-0" style="background:#8C1D1D"></span>
                      <span class="text-[13px] font-mono-tatacora" style="color:#8C1D1D">{{ $table }}</span>
                    </div>
                  @empty
                    <p class="text-[13px] text-slate-400">{{ __('pwa.import_export.seeders_rien_a_vider') }}</p>
                  @endforelse
                </div>
              </section>

              <section class="bg-white rounded-xl border border-slate-200 p-5">
                <h2 class="text-sm font-bold mb-1" style="color:var(--succes)">{{ __('pwa.import_export.seeders_conserve_titre') }}</h2>
                <p class="text-[13px] text-slate-500 mb-3">{{ __('pwa.import_export.seeders_conserve_texte') }}</p>
                <div class="space-y-1 max-h-72 overflow-y-auto">
                  @foreach ($tablesPreservees as $table)
                    <div class="flex items-center gap-2 px-3 py-1.5 rounded-lg" style="background:#E8F5E9">
                      <span class="w-1.5 h-1.5 rounded-full shrink-0" style="background:#1B5E20"></span>
                      <span class="text-[13px] font-mono-tatacora" style="color:#1B5E20">{{ $table }}</span>
                    </div>
                  @endforeach
                </div>
              </section>
            </div>

            @if ($peutEcrire && $reinitialisationAutorisee && $reinitialisationPermise)
              <button type="button" wire:click="ouvrirReinitialisation"
                      class="btn w-full mt-5 flex items-center justify-center gap-2 px-5 py-3 rounded-lg text-white text-sm font-bold" style="background:var(--erreur)">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path stroke-linecap="round" stroke-linejoin="round" d="M3 6h18M8 6V4a2 2 0 012-2h4a2 2 0 012 2v2m3 0v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6h14z"/></svg>
                {{ __('pwa.import_export.onglet_seeders') }}
              </button>
            @endif
          @endif

</div>

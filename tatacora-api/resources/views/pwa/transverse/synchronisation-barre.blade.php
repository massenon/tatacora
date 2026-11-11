{{--
    L'ICÔNE DE SYNCHRONISATION de la barre supérieure et sa modale — AJOUT à
    la maquette, demande du PO du 03/11/2026. Voir le docblock de
    `App\Pwa\Livewire\Transverse\SynchronisationBarre`.

    Tracé : celui de `TracesCoquille.synchronisation` du poste, 20 px, à la
    taille de la cloche. Le voyant est dérivé à chaque rendu (jamais posé) par
    `SuiviPostesService::voyant()` : gris = aucun poste appairé, vert = tous
    vus depuis moins de :retard minutes, orange = au moins un poste en retard
    ou jamais vu.
--}}
@php
  $teintes = ['gris' => 'bg-slate-400', 'vert' => 'bg-emerald-400', 'orange' => 'bg-amber-400'];
  $phraseVoyant = __('pwa.synchronisation_barre.voyant_'.$voyant, ['minutes' => $retardMinutes]);
@endphp
<div class="relative">
  <button id="bouton-synchronisation" type="button" wire:click="ouvrir"
          class="relative text-white/70 hover:text-white p-2"
          aria-label="{{ __('pwa.synchronisation_barre.etiquette') }}"
          aria-haspopup="dialog" aria-expanded="{{ $ouvert ? 'true' : 'false' }}"
          title="{{ $phraseVoyant }}">
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M3 12a9 9 0 019-9 9.75 9.75 0 016.74 2.74L21 8M21 3v5h-5M21 12a9 9 0 01-9 9 9.75 9.75 0 01-6.74-2.74L3 16M8 16H3v5"/></svg>
    <span id="voyant-synchronisation" data-voyant="{{ $voyant }}" aria-hidden="true"
          class="absolute top-1 right-1 w-2 h-2 rounded-full ring-2 ring-[var(--navy)] {{ $teintes[$voyant] }}"></span>
  </button>

  @if ($ouvert)
    <x-pwa.modale :titre="__('pwa.synchronisation_barre.titre')" :sousTitre="__('pwa.synchronisation_barre.sous_titre')" largeur="720px" fermer="fermer">
      <div role="group" aria-label="{{ __('pwa.synchronisation_barre.titre') }}" wire:poll.15s>
        <p id="voyant-synchronisation-phrase" class="text-sm text-slate-600 flex items-center gap-2">
          <span class="w-2 h-2 rounded-full {{ $teintes[$voyant] }}"></span>{{ $phraseVoyant }}
        </p>

        @if ($confirmation)
          <div id="confirmation-synchronisation-barre" role="status" class="rounded-lg border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-800">{{ $confirmation }}</div>
        @endif

        <p id="derniere-demande-barre" class="text-sm text-slate-600">
          @if ($demande)
            {{ __('pwa.synchronisation_postes.derniere_demande', ['date' => \App\Shared\Support\HeureLocale::formater($demande->demandee_le, 'd/m/Y H:i:s')]) }}
          @else
            {{ __('pwa.synchronisation_postes.aucune_demande') }}
          @endif
        </p>

        <div class="rounded-xl border border-slate-200 overflow-hidden">
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead class="bg-[var(--navy)]">
                <tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
                  <th class="px-4 py-2.5">{{ __('pwa.synchronisation_postes.col_poste') }}</th>
                  <th class="px-4 py-2.5">{{ __('pwa.synchronisation_postes.col_contact') }}</th>
                  <th class="px-4 py-2.5">{{ __('pwa.synchronisation_postes.col_montee') }}</th>
                  <th class="px-4 py-2.5">{{ __('pwa.synchronisation_postes.col_descente') }}</th>
                  <th class="px-4 py-2.5">{{ __('pwa.synchronisation_postes.col_etat') }}</th>
                </tr>
              </thead>
              <tbody id="corps-postes-barre">
                @forelse ($postes as $poste)
                  @php($enRetard = $poste['appaire'] && \App\Shared\Sync\Services\SuiviPostesService::enRetard($poste))
                  <tr class="border-t border-slate-100" wire:key="poste-barre-{{ $poste['poste_id'] }}">
                    <td class="px-4 py-2.5 font-medium text-slate-700">{{ $poste['poste_id'] }}</td>
                    <td class="px-4 py-2.5 text-slate-600">{{ $poste['jeton_utilise_le']?->locale('fr')->diffForHumans() ?? __('pwa.synchronisation_postes.jamais') }}</td>
                    <td class="px-4 py-2.5 text-slate-600">{{ \App\Shared\Support\HeureLocale::formater($poste['derniere_montee'], 'd/m/Y H:i') ?? __('pwa.synchronisation_postes.jamais') }}</td>
                    <td class="px-4 py-2.5 text-slate-600">{{ \App\Shared\Support\HeureLocale::formater($poste['derniere_descente'], 'd/m/Y H:i') ?? __('pwa.synchronisation_postes.jamais') }}</td>
                    <td class="px-4 py-2.5">
                      @if (! $poste['appaire'])
                        <span class="text-[11px] px-1.5 py-0.5 rounded font-semibold bg-red-50 text-red-700">{{ __('pwa.synchronisation_barre.revoque') }}</span>
                      @elseif ($enRetard)
                        <span class="text-[11px] px-1.5 py-0.5 rounded font-semibold bg-amber-50 text-amber-700">{{ __('pwa.synchronisation_barre.en_retard') }}</span>
                      @else
                        <span class="text-[11px] px-1.5 py-0.5 rounded font-semibold bg-emerald-50 text-emerald-700">{{ __('pwa.synchronisation_postes.etat_actif') }}</span>
                      @endif
                      <div class="text-[12px] text-slate-500 mt-1">{{ __('pwa.synchronisation_postes.col_attente') }} : {{ $poste['en_attente'] ?? __('pwa.synchronisation_postes.jamais') }}</div>
                    </td>
                  </tr>
                @empty
                  <tr><td colspan="5" class="px-4 py-5 text-center text-slate-500">{{ __('pwa.synchronisation_postes.aucun_poste') }}</td></tr>
                @endforelse
              </tbody>
            </table>
          </div>
        </div>

        <p class="text-[13px] text-slate-500">
          {{ __('pwa.synchronisation_barre.regle', ['minutes' => $retardMinutes]) }}
          <a href="{{ route('pwa.synchronisation-postes') }}" wire:navigate class="underline" style="color:var(--navy)">{{ __('pwa.synchronisation_barre.voir_detail') }}</a>
        </p>
      </div>
      <x-slot:pied>
        <button type="button" wire:click="fermer" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.fermer') }}</button>
        <button id="bouton-synchroniser-postes-barre" type="button" wire:click="demander" wire:loading.attr="disabled" autofocus
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('pwa.synchronisation_postes.bouton') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif
</div>

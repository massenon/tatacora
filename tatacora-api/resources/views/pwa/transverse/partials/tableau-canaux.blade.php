{{--
    Le tableau des canaux de réservation — maquette `parametres.html`
    l.144-154, UN SEUL AUTEUR (02/09/2026, G5).

    Il est rendu à DEUX endroits par l'écran Paramètres : dans l'onglet
    « Canaux de réservation » (visible), et en ombre `hidden` sur les six
    autres onglets — pour que l'entête du tableau du maître existe dans le
    HTML de chaque GET (`ColonnesDesTableauxPwaTest`), sans que deux copies
    du même tableau puissent diverger.

    Attend : `$canaux` (référentiel réel, toujours chargé par le composant)
    et `$peutEcrire`.
--}}
<div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-5">
  <div class="overflow-x-auto">
    <table class="w-full text-[13px]">
      <thead class="bg-[var(--navy)] text-[11px] uppercase tracking-wide text-white/90 font-semibold"><tr>
        <th class="text-left px-4 py-2.5">{{ __('pwa.parametres.canaux_colonne_canal') }}</th>
        <th class="text-right px-4 py-2.5">{{ __('pwa.parametres.canaux_colonne_reservations') }}</th>
        <th class="text-left px-4 py-2.5">{{ __('pwa.parametres.canaux_colonne_etat') }}</th>
        <th class="text-right px-4 py-2.5">{{ __('pwa.parametres.canaux_colonne_actions') }}</th>
      </tr></thead>
      <tbody>
        @forelse ($canaux as $canal)
          <tr class="border-t border-slate-100">
            <td class="px-4 py-2.5 font-semibold text-slate-700">{{ $canal->nom }}</td>
            <td class="px-4 py-2.5 text-right {{ $canal->reservations_count ? 'font-semibold' : 'text-slate-400' }}">{{ $canal->reservations_count ?: '—' }}</td>
            <td class="px-4 py-2.5">
              @if ($canal->actif)
                <span class="px-2 py-0.5 rounded text-[11px] font-semibold bg-emerald-50 text-emerald-700">{{ __('pwa.parametres.canaux_etat_actif') }}</span>
              @else
                <span class="px-2 py-0.5 rounded text-[11px] font-semibold bg-slate-100 text-slate-600">{{ __('pwa.parametres.canaux_etat_desactive') }}</span>
              @endif
            </td>
            <td class="px-4 py-2.5 text-right whitespace-nowrap">
              @if ($peutEcrire)
                <button type="button" wire:click="ouvrirRenommageCanal('{{ $canal->id }}')"
                        class="text-[12px] font-semibold mr-3" style="color:var(--navy)">{{ __('pwa.parametres.canaux_bouton_renommer') }}</button>
                @if ($canal->actif && $canal->reservations_count)
                  {{-- Confirmation par la MODALE du dépôt (comme le maître :
                       `Dialogue.confirmer`, canaux-engine.js) — jamais
                       `wire:confirm`, boîte native hors charte que
                       `MotifsInterditsPwaTest` refuse. --}}
                  <button type="button" wire:click="demanderDesactivationCanal('{{ $canal->id }}')"
                          class="text-[12px] font-semibold" style="color:var(--gold)">{{ __('pwa.parametres.canaux_bouton_desactiver') }}</button>
                @else
                  <button type="button" wire:click="basculerCanal('{{ $canal->id }}')"
                          class="text-[12px] font-semibold" style="color:var(--gold)">{{ $canal->actif ? __('pwa.parametres.canaux_bouton_desactiver') : __('pwa.parametres.canaux_bouton_reactiver') }}</button>
                @endif
              @else
                <span class="text-slate-300">—</span>
              @endif
            </td>
          </tr>
        @empty
          <tr><td colspan="4" class="px-4 py-6 text-center text-[13px] text-slate-400">{{ __('pwa.parametres.canaux_aucun') }}</td></tr>
        @endforelse
      </tbody>
    </table>
  </div>
</div>

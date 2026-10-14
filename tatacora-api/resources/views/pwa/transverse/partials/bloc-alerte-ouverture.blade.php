{{--
    Un BLOC de modale d'ouverture — `bloc()` du maître
    (`alertes-ouverture.js`) : bandeau teinté (couleur à 12 % d'alpha),
    compteur rond, 10 lignes maximum + « … et N autre(s) », pastille rouge
    sur les lignes critiques, action inline selon le gabarit, lien de pied.

    Attend : titre, sousTitre, couleur, icone (chemins SVG), lignes,
    lien, libelleLien, gabaritAction (null | 'checkout' | 'relance').
--}}
@php $plafond = \App\Pwa\Support\AlertesOuverture::LIGNES_PAR_BLOC; @endphp
<div class="rounded-xl border border-slate-200 overflow-hidden">
  <div class="px-4 py-3 flex items-center gap-2.5" style="background:{{ $couleur }}12">
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="{{ $couleur }}" stroke-width="2.2" class="shrink-0">{!! $icone !!}</svg>
    <div class="min-w-0">
      <p class="text-sm font-bold" style="color:{{ $couleur }}">{{ $titre }}</p>
      <p class="text-[11px] text-slate-500">{{ $sousTitre }}</p>
    </div>
    <span class="ml-auto text-xs font-bold text-white rounded-full px-2.5 py-1 shrink-0" style="background:{{ $couleur }}">{{ count($lignes) }}</span>
  </div>
  <div class="divide-y divide-slate-100 max-h-64 overflow-y-auto">
    @foreach (array_slice($lignes, 0, $plafond) as $ligne)
      @php
        $cleTraitee = $gabaritAction === 'checkout'
            ? 'sejour:' . $ligne['sejour_id']
            : ($gabaritAction === 'relance' ? 'client:' . $ligne['client_id'] : null);
        $traitee = $cleTraitee !== null && in_array($cleTraitee, $traites, true);
      @endphp
      <div class="px-4 py-2.5 flex items-start gap-2 {{ $traitee ? 'opacity-45' : '' }}">
        <span class="w-1.5 h-1.5 rounded-full mt-1.5 shrink-0" style="background:{{ $ligne['critique'] ? 'var(--erreur)' : $couleur }}"></span>
        <div class="min-w-0 flex-1">
          <p class="text-xs font-semibold text-slate-700">{{ $ligne['libelle'] }}</p>
          <p class="text-[11px] text-slate-500">{{ $ligne['detail'] }}</p>
        </div>
        @if ($gabaritAction === 'checkout')
          @if ($traitee)
            <span class="shrink-0 text-[10px] font-semibold text-slate-400">{{ __('pwa.alertes_ouverture.fait') }}</span>
          @else
            <button type="button" wire:click="effectuerCheckOutOuverture('{{ $ligne['sejour_id'] }}')"
                    class="btn shrink-0 px-2.5 py-1 rounded text-white text-[10px] font-bold" style="background:#1D4ED8">{{ __('pwa.alertes_ouverture.checkout') }}</button>
          @endif
        @elseif ($gabaritAction === 'relance')
          @if ($traitee)
            <span class="shrink-0 text-[10px] font-semibold text-slate-400">{{ __('pwa.alertes_ouverture.tracee') }}</span>
          @elseif ($ligne['relance_requise'])
            <span class="flex items-center gap-1 shrink-0">
              <select wire:model="canalRelance" class="border border-slate-200 rounded px-1 py-0.5 text-[10px] bg-white">
                @foreach ($canaux as $canal)
                  @php
                    // Clés LITTÉRALES via match — jamais une clé concaténée.
                    $libelleCanal = match ($canal) {
                        'telephone' => __('pwa.alertes_ouverture.canal_telephone'),
                        'whatsapp' => __('pwa.alertes_ouverture.canal_whatsapp'),
                        'email' => __('pwa.alertes_ouverture.canal_email'),
                        'courrier' => __('pwa.alertes_ouverture.canal_courrier'),
                        'visite' => __('pwa.alertes_ouverture.canal_visite'),
                        default => $canal,
                    };
                  @endphp
                  <option value="{{ $canal }}">{{ $libelleCanal }}</option>
                @endforeach
              </select>
              <button type="button" wire:click="tracerRelanceOuverture('{{ $ligne['client_id'] }}')"
                      class="btn px-2.5 py-1 rounded text-white text-[10px] font-bold" style="background:#ED6C02">{{ __('pwa.alertes_ouverture.relancer') }}</button>
            </span>
          @else
            {{-- Relancé il y a moins de 14 jours : l'encours reste visible,
                 sans bouton inopérant — la phrase du maître. --}}
            <span class="shrink-0 text-[10px] font-semibold text-slate-400">{{ __('pwa.alertes_ouverture.relance_recente') }}</span>
          @endif
        @endif
      </div>
    @endforeach
    @if (count($lignes) > $plafond)
      <p class="px-4 py-2 text-[11px] text-slate-400">{{ __('pwa.alertes_ouverture.et_autres', ['nombre' => count($lignes) - $plafond]) }}</p>
    @endif
  </div>
  <a href="{{ $lien }}" wire:navigate class="block px-4 py-2.5 text-center text-xs font-bold border-t border-slate-100 hover:bg-slate-50" style="color:{{ $couleur }}">{{ $libelleLien }} →</a>
</div>

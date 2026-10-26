@php
    $t = static fn (string $cle, array $p = []): string => __('synchronisation_journal.ecran.' . $cle, $p);
    $libelleTable = static fn (string $table): string => app(\App\Shared\Sync\Services\JournalReceptionService::class)->libelleTable($table);
@endphp
<div class="space-y-4" wire:poll.20s>
  @if (! $autorise)
    <div id="envoi-acces-refuse" class="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800">{{ $t('acces_refuse') }}</div>
  @else
    <div>
      <h2 class="text-base font-bold" style="color:var(--navy)">{{ $t('envoi_titre') }}</h2>
      <p class="text-[14px] text-slate-500 mt-1">{{ $t('envoi_intro') }}</p>
    </div>

    @if ($refus)
      <div id="envoi-refus" class="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">{{ $refus }}</div>
    @endif
    @if ($confirmation)
      <div id="envoi-confirmation" class="rounded-lg border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-800">{{ $confirmation }}</div>
    @endif

    <div class="flex justify-end">
      <button id="bouton-actualiser-envoi" type="button" wire:click="actualiser" wire:loading.attr="disabled"
              class="rounded-lg px-4 py-2.5 text-sm font-semibold border border-slate-300 text-slate-700 hover:bg-white">{{ $t('actualiser') }}</button>
    </div>

    <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
      <div class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead class="bg-[var(--navy)]">
            <tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
              <th class="px-4 py-3">{{ $t('envoi_col_poste') }}</th>
              <th class="px-4 py-3">{{ $t('envoi_col_passage') }}</th>
              <th class="px-4 py-3">{{ $t('envoi_col_etat') }}</th>
              <th class="px-4 py-3 text-right">{{ $t('envoi_col_livres') }}</th>
              <th class="px-4 py-3 text-right">{{ $t('envoi_col_droits') }}</th>
              <th class="px-4 py-3 text-right">{{ $t('envoi_col_refus') }}</th>
              <th class="px-4 py-3 text-right">{{ $t('envoi_col_actions') }}</th>
            </tr>
          </thead>
          <tbody id="corps-envoi">
            @forelse ($postes as $p)
              <tr class="border-t border-slate-100 align-top" wire:key="envoi-{{ $p['poste_id'] }}">
                <td class="px-4 py-3 font-medium text-slate-700">{{ $p['poste_id'] }}
                  <div class="text-[12px] font-normal text-slate-500">{{ $p['utilisateur'] ?? '—' }}</div>
                </td>
                <td class="px-4 py-3 text-slate-600 whitespace-nowrap">{{ $p['derniere_descente']?->format('d/m/Y H:i:s') ?? '—' }}</td>
                <td class="px-4 py-3">
                  <span class="text-[11px] px-1.5 py-0.5 rounded font-semibold {{ $p['complete'] ? 'bg-emerald-50 text-emerald-700' : 'bg-amber-50 text-amber-700' }}">{{ $p['complete'] ? $t('envoi_complet') : $t('envoi_en_cours') }}</span>
                  @if ($p['redescente_demandee_le'])
                    <div class="text-[12px] text-amber-700 mt-1">{{ $t('envoi_redescente_demandee', ['date' => $p['redescente_demandee_le']->format('d/m/Y H:i:s')]) }}</div>
                  @elseif ($p['redescente_faite_le'])
                    <div class="text-[12px] text-slate-500 mt-1">{{ $t('envoi_redescente_faite', ['date' => $p['redescente_faite_le']->format('d/m/Y H:i:s')]) }}</div>
                  @endif
                </td>
                <td class="px-4 py-3 text-right text-slate-700">{{ number_format($p['livres'], 0, ',', ' ') }}</td>
                <td class="px-4 py-3 text-right {{ $p['non_livres_droits'] > 0 ? 'text-amber-700 font-semibold' : 'text-slate-600' }}">{{ number_format($p['non_livres_droits'], 0, ',', ' ') }}</td>
                <td class="px-4 py-3 text-right {{ $p['generation_perimee_nb'] > 0 ? 'text-red-700 font-semibold' : 'text-slate-600' }}">{{ $p['generation_perimee_nb'] }}</td>
                <td class="px-4 py-3 text-right whitespace-nowrap">
                  <button type="button" wire:click="voirPoste(@js($p['poste_id']))" class="text-[13px] px-3 py-1.5 rounded-lg border border-slate-300 text-slate-700 hover:bg-slate-50">{{ $t('envoi_voir') }}</button>
                  @if ($peutRedescendre)
                    <button type="button" wire:click="demanderRedescente(@js($p['poste_id']))" class="text-[13px] px-3 py-1.5 rounded-lg border border-slate-300 text-slate-700 hover:bg-slate-50">{{ $t('redescendre') }}</button>
                  @endif
                </td>
              </tr>
            @empty
              <tr><td colspan="7" class="px-5 py-6 text-center text-slate-500">{{ $t('envoi_aucun_poste') }}</td></tr>
            @endforelse
          </tbody>
        </table>
      </div>
    </div>

    @if ($detail)
      <x-pwa.modale :titre="$t('envoi_detail_titre', ['poste' => $detail['poste_id']])" largeur="820px" fermer="fermerPoste">
        <div id="detail-envoi" class="space-y-3 text-sm">
          <p class="text-[13px] text-slate-500">{{ $detail['curseur'] ? $t('envoi_dernier_curseur', ['curseur' => \Illuminate\Support\Str::limit($detail['curseur'], 40)]) : $t('envoi_aucun_curseur') }}</p>
          @php($etatPoste = collect($postes)->firstWhere('poste_id', $detail['poste_id']))
          <p class="text-[13px] text-slate-600">
            @if ($etatPoste && $etatPoste['generation_perimee_nb'] > 0)
              {{ $t('envoi_perime_le', ['date' => $etatPoste['generation_perimee_le']?->format('d/m/Y H:i:s') ?? '—', 'n' => $etatPoste['generation_perimee_nb']]) }}
            @else
              {{ $t('envoi_aucun_refus') }}
            @endif
          </p>
          @if ($detail['tables'] === [])
            <p class="text-slate-500">{{ $t('envoi_detail_aucune') }}</p>
          @else
            <div class="rounded-lg border border-slate-200 overflow-hidden">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]">
                  <tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
                    <th class="px-3 py-2">{{ $t('envoi_detail_col_donnee') }}</th>
                    <th class="px-3 py-2 text-right">{{ $t('envoi_detail_col_livres') }}</th>
                    <th class="px-3 py-2">{{ $t('envoi_detail_col_dernier') }}</th>
                    <th class="px-3 py-2 text-right">{{ $t('envoi_detail_col_restants') }}</th>
                    <th class="px-3 py-2 text-right">{{ $t('envoi_detail_col_droits') }}</th>
                  </tr>
                </thead>
                <tbody>
                  @foreach ($detail['tables'] as $ligne)
                    <tr class="border-t border-slate-100">
                      <td class="px-3 py-1.5 text-slate-800">{{ $libelleTable($ligne['table']) }}</td>
                      <td class="px-3 py-1.5 text-right">{{ number_format($ligne['livres'], 0, ',', ' ') }}</td>
                      <td class="px-3 py-1.5 text-slate-600">{{ $ligne['derniere']?->format('d/m/Y H:i:s') ?? '—' }}</td>
                      <td class="px-3 py-1.5 text-right {{ $ligne['restants'] > 0 ? 'text-amber-700 font-semibold' : '' }}">{{ number_format($ligne['restants'], 0, ',', ' ') }}</td>
                      <td class="px-3 py-1.5 text-right {{ $ligne['droits'] > 0 ? 'text-amber-700 font-semibold' : '' }}">{{ number_format($ligne['droits'], 0, ',', ' ') }}</td>
                    </tr>
                  @endforeach
                </tbody>
              </table>
            </div>
          @endif
        </div>
        <x-slot:pied>
          <button type="button" wire:click="fermerPoste" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ $t('fermer') }}</button>
        </x-slot:pied>
      </x-pwa.modale>
    @endif

    {{-- Confirmation de la redescente — derrière `@if`, jamais `wire:confirm`. --}}
    @if ($posteARedescendre !== null)
      <x-pwa.modale :titre="$t('redescendre_titre', ['poste' => $posteARedescendre])" largeur="520px" fermer="annulerRedescente">
        <p class="text-sm text-slate-600">{{ $t('redescendre_texte') }}</p>
        <x-slot:pied>
          <button type="button" wire:click="annulerRedescente" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
          <button id="confirmer-redescente" type="button" wire:click="redescendre" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ $t('redescendre_confirmer') }}</button>
        </x-slot:pied>
      </x-pwa.modale>
    @endif
  @endif
</div>

<div class="contents">

  @include('pwa.partials.barre-superieure')

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        <div class="mb-5">
          <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('pwa.synchronisation_page.titre') }}</h1>
          <p class="text-[15px] text-slate-500 mt-1.5">{{ __('pwa.synchronisation_page.sous_titre') }}</p>
        </div>

        @if ($peutVoirJournaux)
          {{-- Onglets : même style partout (`Onglets`). --}}
          <div id="onglets-synchronisation" class="mb-4 flex flex-wrap gap-2">
            @foreach (['reception' => 'synchronisation_journal.ecran.onglet_reception', 'envoi' => 'synchronisation_journal.ecran.onglet_envoi'] as $cleOnglet => $libelleOnglet)
              <button type="button" id="onglet-{{ $cleOnglet }}" wire:click="changerOnglet('{{ $cleOnglet }}')"
                      class="{{ \App\Pwa\Support\Onglets::classes($ongletActif === $cleOnglet) }}">{{ __($libelleOnglet) }}</button>
            @endforeach
          </div>

          @if ($ongletActif === 'reception')
            <livewire:pwa.reception-synchronisation />
          @else
            <livewire:pwa.envoi-synchronisation />
          @endif
        @else
          {{-- Tout autre rôle : la page en LECTURE et SES PROPRES échecs, aucun bouton d'action. --}}
          <h2 class="text-[15px] font-semibold text-slate-700 mb-2">{{ __('pwa.synchronisation_page.a_traiter') }}</h2>
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead class="bg-[var(--navy)]">
                  <tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
                    <th class="px-5 py-3">{{ __('pwa.synchronisation_page.col_date') }}</th>
                    <th class="px-5 py-3">{{ __('pwa.synchronisation_page.col_poste') }}</th>
                    <th class="px-5 py-3">{{ __('pwa.synchronisation_page.col_donnee') }}</th>
                    <th class="px-5 py-3">{{ __('pwa.synchronisation_page.col_issue') }}</th>
                    <th class="px-5 py-3">{{ __('pwa.synchronisation_page.col_cause') }}</th>
                  </tr>
                </thead>
                <tbody id="corps-mes-echecs">
                  @forelse ($mesEchecs as $echec)
                    <tr class="border-t border-slate-100" wire:key="echec-{{ $echec->id }}">
                      <td class="px-5 py-3 text-slate-600">{{ $echec->recu_le?->format('d/m/Y H:i') }}</td>
                      <td class="px-5 py-3 text-slate-700">{{ $echec->poste_id }}</td>
                      <td class="px-5 py-3 text-slate-600">{{ $journal->libelleTable((string) $echec->table_concernee) }}</td>
                      <td class="px-5 py-3 text-slate-600">{{ $libellesIssues[$echec->issue] ?? $echec->issue }}</td>
                      <td class="px-5 py-3 text-slate-600">{{ $echec->cause ?? $echec->motif }}</td>
                    </tr>
                  @empty
                    <tr><td colspan="5" class="px-5 py-6 text-center text-slate-500">{{ __('pwa.synchronisation_page.aucun_echec') }}</td></tr>
                  @endforelse
                </tbody>
              </table>
            </div>
          </div>
        @endif
      </div>
    </main>
  </div>
</div>

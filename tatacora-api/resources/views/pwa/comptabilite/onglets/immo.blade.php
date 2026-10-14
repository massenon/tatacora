{{--
    Onglet « Immobilisations » du hub — maître :
    `prototype_v2/pages/m10-syscohada-etats.js` `vueImmobilisations()` l.204-250.

    Colonnes du maître (l.248) : Code, Immobilisation, Durée, Valeur
    d'origine, Dotation <année>, Amort. cumulés, VNC, + une colonne d'action
    (« Plan »).

    ## Deux écarts au maître — nommés, pas masqués

    ÉCART DÉLIBÉRÉ — `m10-syscohada-etats.js` l.361 (centre d'affectation)
    Le maître pose un sélecteur de centre à la création. `immobilisations`
    (migration `create_immobilisations`, Vague E) n'a pas de colonne de
    centre — périmètre commandé pour ce lot. Absent ici, à la création comme
    à l'affichage.

    ÉCART DÉLIBÉRÉ — terrain non amortissable (`m10-syscohada-etats.js` l.752-753)
    Le maître dispense les comptes de classe 22 (terrains) d'amortissement.
    Le schéma de ce lot rend `duree_annees` obligatoire et strictement
    positif pour TOUTE immobilisation — voir le docblock de la migration et
    d'`ImmobilisationService`. Toutes les immobilisations créées ici sont donc
    amortissables.
--}}
@php
    use App\Pwa\Support\MontantFcfa;
    $annee = $exercice?->annee ?? now()->year;

    // Les colonnes de l'onglet, écrites UNE fois (voir `_entetes`).
    //
    // ÉCART DÉLIBÉRÉ — `m10-syscohada-etats.js` l.248, colonne « Dotation <année> »
    // Le maître : accole l'année à l'entête (« Dotation 2026 ») — et écrit la
    // MÊME colonne « Dotation », sans année, dans l'en-tête de son export
    // (`m10-syscohada-init.js` l.129).
    // Ici : « Dotation » seul ; l'année vit dans le titre du tableau, juste
    // au-dessus (`immo_titre_tableau`, qui la porte déjà).
    // Raison (02/09/2026) : des deux graphies du maître, celle sans année est
    // retenue — l'information n'est pas perdue (le titre la porte), et une
    // entête stable est celle que les gardes de colonnes et les exports
    // peuvent comparer sans réapprendre chaque exercice.
    $colonnesEntete = [
        [__('comptabilite_pwa.col_code'), 'left'],
        [__('comptabilite_pwa.col_immobilisation'), 'left'],
        [__('comptabilite_pwa.col_duree'), 'right'],
        [__('comptabilite_pwa.col_valeur_origine'), 'right'],
        [__('comptabilite_pwa.col_dotation_annuelle'), 'right'],
        [__('comptabilite_pwa.col_amort_cumules'), 'right'],
        [__('comptabilite_pwa.col_vnc'), 'right'],
        ['', 'right'],
    ];
@endphp
@if ($squelette ?? false)
  @include('pwa.comptabilite.onglets._squelette_tableau', ['colonnes' => $colonnesEntete, 'message' => $messageSquelette])
@else

<div class="rounded-xl p-3.5 mb-4" style="background:#F8FAFC;border:1px solid #E2E8F0">
  <p class="text-[13px]" style="color:#334155">
    <strong>{{ __('comptabilite_pwa.immo_duree_titre') }}</strong>
    {{ __('comptabilite_pwa.immo_duree_detail') }}
  </p>
</div>

{{-- Recherche par table (décision du Product Owner, 01/09/2026) — code ou
     libellé, filtrage SERVEUR réel. Sûre ici : les totaux du pied somment les
     lignes affichées (voir le docblock de
     `ImmobilisationService::tableauPourExercice()`). --}}
<div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 mb-3">
  <div class="relative flex-1 max-w-md">
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" stroke-width="2" class="absolute left-3.5 top-1/2 -translate-y-1/2"><circle cx="11" cy="11" r="8"/><path stroke-linecap="round" d="M21 21l-4.35-4.35"/></svg>
    <input type="search" wire:model.live.debounce.300ms="immoRecherche"
           placeholder="{{ __('comptabilite_pwa.immo_recherche') }}"
           class="champ w-full border border-slate-200 rounded-lg pl-10 pr-4 py-2.5 text-sm bg-white">
  </div>
  <button type="button" wire:click="ouvrirNouvelleImmo"
          class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90 shrink-0">
    + {{ __('comptabilite_pwa.immo_ajouter') }}
  </button>
</div>

@if ($tableauImmobilisations->lignes === [])
  <div class="bg-white rounded-xl border border-slate-200 py-14 text-center text-slate-400 text-[13px]">
    {{ $immoRecherche === '' ? __('comptabilite_pwa.immo_aucune') : __('comptabilite_pwa.immo_aucune_filtre') }}
  </div>
@else
  <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
    <div class="px-4 py-3 border-b border-slate-200 flex items-center justify-between">
      <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('comptabilite_pwa.immo_titre_tableau', ['annee' => $annee]) }}</h3>
    </div>
    <div class="overflow-x-auto">
      <table class="w-full text-[13px] compta" style="white-space: nowrap">
        @include('pwa.comptabilite.onglets._entetes', ['colonnes' => $colonnesEntete])
        <tbody>
          @foreach ($tableauImmobilisations->lignes as $ligne)
            <tr class="border-t border-slate-100 hover:bg-slate-50">
              <td class="px-3 py-2 font-mono text-[12px] text-slate-500">{{ $ligne->immobilisation->code }}</td>
              <td class="px-3 py-2 text-left text-slate-700 font-semibold">
                {{ $ligne->immobilisation->libelle }}
                <div class="text-[11px] text-slate-400">
                  {{ $ligne->immobilisation->compte_immobilisation ?? MontantFcfa::TIRET }}
                  · mise en service {{ $ligne->immobilisation->date_mise_service->format('d/m/Y') }}
                </div>
              </td>
              <td class="px-3 py-2 text-right">{{ $ligne->immobilisation->duree_annees }} ans</td>
              <td class="px-3 py-2 text-right">{{ MontantFcfa::format($ligne->brut) }}</td>
              <td class="px-3 py-2 text-right">{{ MontantFcfa::formatOuTiret($ligne->dotation) }}</td>
              <td class="px-3 py-2 text-right text-red-600">{{ MontantFcfa::formatOuTiret($ligne->cumul) }}</td>
              <td class="px-3 py-2 text-right font-semibold">{{ MontantFcfa::format($ligne->vnc) }}</td>
              <td class="px-3 py-2 text-right">
                <button type="button" wire:click="ouvrirPlanAmortissement('{{ $ligne->immobilisation->id }}')"
                        class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white">{{ __('comptabilite_pwa.plan_amortissement') }}</button>
              </td>
            </tr>
          @endforeach
        </tbody>
        <tfoot>
          <tr class="solde-final">
            <td class="px-3 py-2.5" colspan="3">{{ __('comptabilite_pwa.total') }}</td>
            <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($tableauImmobilisations->totalBrut) }}</td>
            <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($tableauImmobilisations->totalDotation) }}</td>
            <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($tableauImmobilisations->totalCumul) }}</td>
            <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($tableauImmobilisations->totalVnc) }}</td>
            <td></td>
          </tr>
        </tfoot>
      </table>
    </div>
  </div>
@endif
@endif

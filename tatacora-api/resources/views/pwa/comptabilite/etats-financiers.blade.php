{{--
    États Financiers — maître : `prototype_v2/pages/m10-etats-financiers.html`.

    Conteneur `max-w-[900px] mx-auto p-5 lg:p-8` (l.18), lien de retour en
    `text-[13px]` (l.21), en-tête (l.20-30), barre d'onglets
    `flex flex-wrap gap-2 mt-4` (l.32) puis la zone de contenu (l.34).

    Les quatre onglets sont ceux du maître, dans son ordre, avec ses libellés et
    son onglet actif par défaut (« Bilan »). Le style d'onglet est celui du
    maître, l.121 : actif `bg-[var(--navy)] text-white`, inactif
    `border border-slate-200 bg-white text-slate-500`, sur
    `px-4 py-2.5 rounded-lg text-[13px] font-semibold`.

    Les écarts — l'export refusé, le renvoi vers les Notes Annexes câblé — sont
    motivés au complet dans `App\Pwa\Livewire\Comptabilite\EtatsFinanciers`.
--}}
@php
    use App\Pwa\Livewire\Comptabilite\EtatsFinanciers;
    use App\Pwa\Support\MontantFcfa;
@endphp
<div class="contents">

  @include('pwa.partials.barre-superieure')
  

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        <div class="mb-5">
          <a href="{{ route('pwa.comptabilite.hub') }}" wire:navigate
             class="text-[13px] font-semibold flex items-center gap-1.5 mb-3" style="color:var(--gold)">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M19 12H5M12 19l-7-7 7-7"/></svg>
            {{ __('pwa.comptabilite.retour_hub') }}
          </a>
          <div class="flex items-center gap-2.5">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><path stroke-linecap="round" stroke-linejoin="round" d="M14 2v6h6"/><path stroke-linecap="round" d="M9 13h6M9 17h6M9 9h1"/></svg>
            <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">États Financiers</h1>
          </div>
          <p class="text-[15px] text-slate-500 mt-1.5">Vue consolidée — Bilan, Résultat, Flux, Notes Annexes</p>

          {{-- La barre d'onglets est DANS l'en-tête au maître (l.32), pas en
               dessous : `mt-4` à l'intérieur du bloc `mb-5`. --}}
          <div class="flex flex-wrap gap-2 mt-4">
            @foreach (EtatsFinanciers::ONGLETS as $cle => $libelle)
              <button type="button" wire:click="$set('onglet', '{{ $cle }}')"
                      class="{{ \App\Pwa\Support\Onglets::classes($cle === $ongletActif) }}">{{ $libelle }}</button>
            @endforeach
          </div>
        </div>

        @include('pwa.comptabilite.partials.socle', [
            'identifiant' => 'f-exercice',
            'repartition' => $etats?->bilan?->statuts,
        ])

        @if ($exercice === null)
          @include('pwa.comptabilite.partials.aucun-exercice')
        @else
          <div>
            @if ($ongletActif === 'bilan')
              @php($bilan = $etats->bilan)
              <div class="rounded-lg px-4 py-3 text-[13px] font-semibold mb-4"
                   style="background:{{ $bilan->equilibre ? '#E8F5E9' : '#FDECEC' }};color:{{ $bilan->equilibre ? '#2E7D32' : '#C62828' }}">
                {{ $bilan->equilibre ? 'Équilibré — Actif = Passif = ' . MontantFcfa::format($bilan->totalActif) : 'Déséquilibré' }}
              </div>
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div class="bg-white rounded-xl border border-slate-200 p-5">
                  <h3 class="text-[15px] font-bold mb-3" style="color:var(--navy)">ACTIF</h3>
                  @foreach ($bilan->actif as $poste)
                    <div class="flex justify-between py-1">
                      <span class="text-slate-600 text-[15px]">{{ $poste->libelle }}</span>
                      <span class="font-mono-tatacora text-[15px] text-slate-600">{{ MontantFcfa::format($poste->net) }}</span>
                    </div>
                  @endforeach
                  <div class="flex justify-between py-1 font-bold pt-2 border-t border-slate-100">
                    <span class="text-slate-800 text-[15px]">TOTAL ACTIF</span>
                    <span class="font-mono-tatacora text-[15px] text-slate-800">{{ MontantFcfa::format($bilan->totalActif) }}</span>
                  </div>
                </div>
                <div class="bg-white rounded-xl border border-slate-200 p-5">
                  <h3 class="text-[15px] font-bold mb-3" style="color:var(--navy)">PASSIF</h3>
                  @foreach ($bilan->passif as $poste)
                    <div class="flex justify-between py-1">
                      <span class="text-slate-600 text-[15px]">{{ $poste->libelle }}</span>
                      <span class="font-mono-tatacora text-[15px] text-slate-600">{{ MontantFcfa::format($poste->net) }}</span>
                    </div>
                  @endforeach
                  <div class="flex justify-between py-1 font-bold pt-2 border-t border-slate-100">
                    <span class="text-slate-800 text-[15px]">TOTAL PASSIF</span>
                    <span class="font-mono-tatacora text-[15px] text-slate-800">{{ MontantFcfa::format($bilan->totalPassif) }}</span>
                  </div>
                </div>
              </div>

            @elseif ($ongletActif === 'resultat')
              @php($cr = $etats->compteResultat)
              @if ($cr->impotNonComptabilise)
                {{-- Le maître écrit ici « Résultat avant IS — taux non fixé
                     (PA-19) » (l.87). Même correction qu'en page Compte de
                     résultat : aucun taux n'existe, PA-151 l'établit. --}}
                <div class="rounded-lg px-4 py-3 text-[13px] font-semibold bg-amber-50 text-amber-700 border border-amber-200 mb-4">
                  {{ __('pwa.comptabilite.resultat_avant_impot') }}
                </div>
              @endif
              <div class="bg-white rounded-xl border border-slate-200 p-5">
                @foreach ($cr->lignes as $ligne)
                  @if ($ligne->estSolde)
                    <div class="flex justify-between py-1 font-bold pt-2 border-t border-slate-100">
                      <span class="text-slate-800 text-[15px]"><span class="font-mono-tatacora text-slate-400 text-[13px]">{{ $ligne->code }}</span> {{ $ligne->libelle }}</span>
                      <span class="font-mono-tatacora text-[15px] text-slate-800">{{ MontantFcfa::format($ligne->montant) }}</span>
                    </div>
                  @endif
                @endforeach
              </div>

            @elseif ($ongletActif === 'flux')
              @php($tafire = $etats->tafire)
              <div class="rounded-lg px-4 py-3 text-[13px] font-semibold mb-4"
                   style="background:{{ $tafire->coherent ? '#E8F5E9' : '#FDECEC' }};color:{{ $tafire->coherent ? '#2E7D32' : '#C62828' }}">
                {{ $tafire->coherent ? 'Cohérent — variation calculée = réelle = ' . MontantFcfa::format($tafire->variationTresorerieCalculee) : 'Incohérence détectée' }}
              </div>
              <div class="bg-white rounded-xl border border-slate-200 p-5">
                @foreach ([
                    ['CAFG', $tafire->capaciteAutofinancementGlobale, false],
                    ['Augmentation de capital', $tafire->augmentationCapital, false],
                    ['TOTAL RESSOURCES', $tafire->totalRessources, true],
                    ['TOTAL EMPLOIS', $tafire->totalEmplois, false],
                    ['Variation du BFR', $tafire->variationBesoinFondsRoulement, false],
                    ['VARIATION DE TRÉSORERIE', $tafire->variationTresorerieCalculee, true],
                ] as [$libelle, $montant, $gras])
                  <div class="flex justify-between py-1 {{ $gras ? 'font-bold pt-2 border-t border-slate-100' : '' }}">
                    <span class="{{ $gras ? 'text-slate-800' : 'text-slate-600' }} text-[15px]">{{ $libelle }}</span>
                    <span class="font-mono-tatacora text-[15px] {{ $gras ? 'text-slate-800' : 'text-slate-600' }}">{{ MontantFcfa::format($montant) }}</span>
                  </div>
                @endforeach
              </div>

            @else
              @php($notes = $etats->notesAnnexes)
              <div class="bg-white rounded-xl border border-slate-200 p-5 space-y-3">
                @foreach ($notes->notes as $note)
                  <div>
                    <p class="text-[15px] font-semibold text-slate-700">{{ $note->numero }}. {{ $note->titre }}</p>
                    @foreach ($note->postes as $poste)
                      <div class="flex justify-between py-1">
                        <span class="text-slate-600 text-[15px]">{{ $poste['libelle'] }}</span>
                        <span class="font-mono-tatacora text-[15px] text-slate-600">{{ MontantFcfa::format($poste['montant']) }}</span>
                      </div>
                    @endforeach
                  </div>
                @endforeach
                {{-- Le maître renvoie ici vers `m10-notes-annexes.html` (l.117).
                     Article 3.3 : la référence NAVIGUE, l'écran cible existe. --}}
                <p class="text-[13px] text-slate-400 italic">
                  Détail complet des 7 rubriques :
                  <a href="{{ route('pwa.comptabilite.notes-annexes', ['exercice' => $exercice->id, 'statut' => $filtreStatut]) }}" wire:navigate
                     class="font-semibold underline" style="color:var(--gold)">Notes Annexes</a>
                </p>
              </div>
            @endif
          </div>
        @endif

      </div>
    </main>
  </div>

</div>

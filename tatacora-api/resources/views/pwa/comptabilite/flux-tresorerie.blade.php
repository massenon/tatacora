{{--
    Tableau des Flux de Trésorerie — maître :
    `prototype_v2/pages/m10-flux-tresorerie.html`.

    Conteneur `max-w-[900px] mx-auto p-5 lg:p-8` (l.18), lien de retour en
    `text-[13px]` (l.21), en-tête (l.20-30), bandeau de cohérence (l.32), la
    grille `grid grid-cols-1 md:grid-cols-2 gap-4` portant « RESSOURCES » et
    « EMPLOIS » (l.34-46), puis les deux cartes « Variation du Besoin en Fonds
    de Roulement (BFR) » (l.48-51) et « Variation de trésorerie nette »
    (l.53-56).

    Les écarts — les deux notes de jeu d'essai retirées, et la ligne des dettes
    renommée pour dire ce qu'elle contient réellement — sont motivés au complet
    dans `App\Pwa\Livewire\Comptabilite\FluxTresorerie`.
--}}
@php
    use App\Pwa\Support\MontantFcfa;
@endphp
<div class="contents">

  @include('pwa.partials.barre-superieure')
  

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[900px] mx-auto p-5 lg:p-8">

        @include('pwa.comptabilite.partials.en-tete', [
            'tailleRetour' => 'text-[13px]',
            'icone' => '<path stroke-linecap="round" stroke-linejoin="round" d="M17 1l4 4-4 4"/><path stroke-linecap="round" stroke-linejoin="round" d="M3 11V9a4 4 0 014-4h14"/><path stroke-linecap="round" stroke-linejoin="round" d="M7 23l-4-4 4-4"/><path stroke-linecap="round" stroke-linejoin="round" d="M21 13v2a4 4 0 01-4 4H3"/>',
            'titre' => 'Tableau des Flux de Trésorerie',
            'sousTitre' => 'TAFIRE — Tableau Financier des Ressources et Emplois',
        ])

        @include('pwa.comptabilite.partials.socle', [
            'identifiant' => 'f-exercice',
            'repartition' => $tafire?->statuts,
        ])

        @if ($exercice === null)
          @include('pwa.comptabilite.partials.aucun-exercice')
        @else

          <div class="mb-4">
            <div class="rounded-lg px-4 py-3 text-[13px] font-semibold flex items-center gap-2"
                 style="background:{{ $tafire->coherent ? '#E8F5E9' : '#FDECEC' }};color:{{ $tafire->coherent ? '#2E7D32' : '#C62828' }}">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                @if ($tafire->coherent)
                  <path stroke-linecap="round" stroke-linejoin="round" d="M20 6L9 17l-5-5"/>
                @else
                  <circle cx="12" cy="12" r="10"/><path stroke-linecap="round" d="M12 8v4M12 16h.01"/>
                @endif
              </svg>
              {{-- Les deux phrases du maître (l.65-67). La seconde porte la
                   règle : un écart n'est pas une « différence normale », c'est
                   un mouvement mal classé. --}}
              {{ $tafire->coherent
                  ? 'Contrôle de cohérence réussi — variation calculée = variation réelle de trésorerie = ' . MontantFcfa::format($tafire->variationTresorerieCalculee)
                  : 'Incohérence détectée — écart entre variation calculée et réelle, signale une erreur de méthode (mouvement mal classé), pas une "différence normale"' }}
            </div>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div class="bg-white rounded-xl border border-slate-200 p-5">
              <h2 class="text-[15px] font-bold mb-3 pb-2 border-b border-slate-100" style="color:var(--navy)">RESSOURCES</h2>
              <div class="space-y-2 text-[15px]">
                <div class="flex justify-between">
                  <span class="text-slate-600">Capacité d'Autofinancement Globale (CAFG)</span>
                  <span class="font-mono-tatacora text-slate-600">{{ MontantFcfa::format($tafire->capaciteAutofinancementGlobale) }}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-slate-600">Augmentation de capital</span>
                  <span class="font-mono-tatacora text-slate-600">{{ MontantFcfa::format($tafire->augmentationCapital) }}</span>
                </div>
                <div class="flex justify-between font-bold pt-2 border-t border-slate-100">
                  <span class="text-slate-800">TOTAL RESSOURCES</span>
                  <span class="font-mono-tatacora text-slate-800">{{ MontantFcfa::format($tafire->totalRessources) }}</span>
                </div>
              </div>
            </div>
            <div class="bg-white rounded-xl border border-slate-200 p-5">
              <h2 class="text-[15px] font-bold mb-3 pb-2 border-b border-slate-100" style="color:var(--navy)">EMPLOIS</h2>
              <div class="space-y-2 text-[15px]">
                <div class="flex justify-between">
                  <span class="text-slate-600">Acquisitions d'immobilisations</span>
                  <span class="font-mono-tatacora text-slate-600">{{ MontantFcfa::format($tafire->acquisitionsImmobilisations) }}</span>
                </div>
                <div class="flex justify-between font-bold pt-2 border-t border-slate-100">
                  <span class="text-slate-800">TOTAL EMPLOIS</span>
                  <span class="font-mono-tatacora text-slate-800">{{ MontantFcfa::format($tafire->totalEmplois) }}</span>
                </div>
              </div>
            </div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-5 mt-4">
            <h2 class="text-[15px] font-bold mb-3 pb-2 border-b border-slate-100" style="color:var(--navy)">Variation du Besoin en Fonds de Roulement (BFR)</h2>
            <div class="space-y-2 text-[15px]">
              <div class="flex justify-between">
                <span class="text-slate-600">Variation des stocks</span>
                <span class="font-mono-tatacora text-slate-600">{{ MontantFcfa::format($tafire->variationStocks) }}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-slate-600">+ Variation des créances</span>
                <span class="font-mono-tatacora text-slate-600">{{ MontantFcfa::format($tafire->variationCreances) }}</span>
              </div>
              <div class="flex justify-between">
                {{-- ⚠ « des dettes », pas « des dettes fournisseurs » : la
                     grandeur couvre aussi le personnel (421), les organismes
                     sociaux (431) et l'État (447). PA-151 a mesuré l'omission
                     du document de référence à 40 000 F. Voir le composant. --}}
                <span class="text-slate-600">− Variation des dettes</span>
                <span class="font-mono-tatacora text-slate-600">{{ MontantFcfa::format($tafire->variationDettes) }}</span>
              </div>
              <div class="flex justify-between font-bold pt-2 border-t border-slate-100">
                <span class="text-slate-800">= VARIATION DU BFR</span>
                <span class="font-mono-tatacora text-slate-800">{{ MontantFcfa::format($tafire->variationBesoinFondsRoulement) }}</span>
              </div>
            </div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-5 mt-4">
            <h2 class="text-[15px] font-bold mb-3 pb-2 border-b border-slate-100" style="color:var(--navy)">Variation de trésorerie nette</h2>
            <div class="space-y-2 text-[15px]">
              <div class="flex justify-between">
                <span class="text-slate-600">Total ressources − Total emplois − Variation BFR</span>
                <span class="font-mono-tatacora text-slate-600">{{ MontantFcfa::format($tafire->variationTresorerieCalculee) }}</span>
              </div>
              <div class="flex justify-between font-bold pt-2 border-t border-slate-100">
                <span class="text-slate-800">Variation réelle des comptes de trésorerie (521/522/571/572/573)</span>
                <span class="font-mono-tatacora text-slate-800">{{ MontantFcfa::format($tafire->variationTresorerieReelle) }}</span>
              </div>
              @unless ($tafire->coherent)
                <div class="flex justify-between">
                  <span class="text-red-600">Écart</span>
                  <span class="font-mono-tatacora text-red-600">{{ MontantFcfa::format($tafire->ecart) }}</span>
                </div>
              @endunless
            </div>
          </div>
        @endif

      </div>
    </main>
  </div>

</div>

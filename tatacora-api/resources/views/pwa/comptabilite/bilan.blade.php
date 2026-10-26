{{--
    Bilan de l'Entreprise — maître : `prototype_v2/pages/m10-bilan.html`.

    Conteneur `max-w-[1200px] mx-auto p-5 lg:p-8` (l.18), en-tête (l.20-30),
    bandeau d'équilibre (l.32), puis la grille
    `grid grid-cols-1 md:grid-cols-2 gap-4` (l.34) portant deux cartes
    `bg-white rounded-xl border border-slate-200 p-5`, « ACTIF » à gauche et
    « PASSIF » à droite, chacune avec son `<h2>` en `text-sm font-bold mb-4
    pb-2 border-b border-slate-100`.

    Chaque ligne est le `flex justify-between` du maître (l.68-71), les totaux
    en gras avec bordure haute.

    Les écarts — le poste « Trésorerie-Passif » ajouté, les comptes hors
    rubrique nommés, la note de jeu d'essai retirée, l'absence de références de
    liasse — sont motivés au complet dans `App\Pwa\Livewire\Comptabilite\Bilan`.
--}}
@php
    use App\Pwa\Support\MontantFcfa;

    // Les libellés descriptifs de ligne du maître (l.75-90), rattachés au code
    // de poste que le Service produit. Ils sont plus parlants que le libellé
    // du poste, qui répète l'intertitre — c'est pour cela que le maître les a
    // écrits, et ils sont repris tels quels.
    $libelleLigne = [
        'actif_immobilise' => 'Total actif immobilisé (net)',
        'actif_circulant' => 'Stocks + Créances clients',
        'tresorerie_actif' => 'Banques, Mobile Money, Caisses',
        'capitaux_propres' => "Capital + Résultat net de l'exercice",
        'passif_circulant' => 'Fournisseurs, avances clients, dettes sociales/fiscales',
        // ⚠ AUCUN équivalent au maître : ce poste n'y figure pas. Voir l'écart
        // nommé dans le composant — le total du passif l'inclut, l'omettre
        // rendrait « TOTAL PASSIF » supérieur à la somme des lignes affichées.
        'tresorerie_passif' => 'Découverts bancaires et concours de trésorerie',
    ];
@endphp
<div class="contents">

  @include('pwa.partials.barre-superieure')
  

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        @include('pwa.comptabilite.partials.en-tete', [
            'tailleRetour' => 'text-[15px]',
            'icone' => '<path stroke-linecap="round" stroke-linejoin="round" d="M21 12V7H5a2 2 0 010-4h14v4"/><path stroke-linecap="round" stroke-linejoin="round" d="M3 5v14a2 2 0 002 2h16v-5"/><path stroke-linecap="round" stroke-linejoin="round" d="M18 12a2 2 0 000 4h4v-4z"/>',
            'titre' => "Bilan de l'Entreprise",
            'sousTitre' => 'Actif / Passif',
        ])

        @include('pwa.comptabilite.partials.socle', [
            'identifiant' => 'f-exercice',
            'repartition' => $bilan?->statuts,
        ])

        @if ($exercice === null)
          @include('pwa.comptabilite.partials.aucun-exercice')
        @else

          <div class="mb-4">
            <div class="rounded-lg px-4 py-3 text-[15px] font-semibold flex items-center gap-2"
                 style="background:{{ $bilan->equilibre ? '#E8F5E9' : '#FDECEC' }};color:{{ $bilan->equilibre ? '#2E7D32' : '#C62828' }}">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                @if ($bilan->equilibre)
                  <path stroke-linecap="round" stroke-linejoin="round" d="M20 6L9 17l-5-5"/>
                @else
                  <circle cx="12" cy="12" r="10"/><path stroke-linecap="round" d="M12 8v4M12 16h.01"/>
                @endif
              </svg>
              {{ $bilan->equilibre
                  ? 'Bilan équilibré — Total Actif = Total Passif = ' . MontantFcfa::format($bilan->totalActif)
                  : 'Bilan déséquilibré — anomalie à investiguer' }}
            </div>
          </div>

          @if ($bilan->impotNonComptabilise)
            <div class="rounded-lg px-4 py-3 text-[13px] font-semibold flex items-start gap-2 bg-amber-50 text-amber-700 border border-amber-200 mb-4">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="shrink-0 mt-0.5"><circle cx="12" cy="12" r="10"/><path stroke-linecap="round" d="M12 8v4M12 16h.01"/></svg>
              <span>{{ __('pwa.comptabilite.resultat_avant_impot') }}</span>
            </div>
          @endif

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div class="bg-white rounded-xl border border-slate-200 p-5">
              <h2 class="text-sm font-bold mb-4 pb-2 border-b border-slate-100" style="color:var(--navy)">ACTIF</h2>
              <div class="space-y-3 text-sm">
                @foreach ($bilan->actif as $poste)
                  <p class="text-[15px] font-bold text-slate-400 uppercase{{ $loop->first ? '' : ' pt-2' }}">{{ $poste->libelle }}</p>
                  <div class="flex justify-between">
                    <span class="text-slate-600">{{ $libelleLigne[$poste->code] ?? $poste->libelle }}</span>
                    <span class="font-mono-tatacora text-slate-600">{{ MontantFcfa::format($poste->net) }}</span>
                  </div>
                @endforeach
                <div class="flex justify-between font-bold pt-2 border-t border-slate-100">
                  <span class="text-slate-800">TOTAL ACTIF</span>
                  <span class="font-mono-tatacora text-slate-800">{{ MontantFcfa::format($bilan->totalActif) }}</span>
                </div>
              </div>
            </div>
            <div class="bg-white rounded-xl border border-slate-200 p-5">
              <h2 class="text-sm font-bold mb-4 pb-2 border-b border-slate-100" style="color:var(--navy)">PASSIF</h2>
              <div class="space-y-3 text-sm">
                @foreach ($bilan->passif as $poste)
                  <p class="text-[15px] font-bold text-slate-400 uppercase{{ $loop->first ? '' : ' pt-2' }}">{{ $poste->libelle }}</p>
                  <div class="flex justify-between">
                    <span class="text-slate-600">{{ $libelleLigne[$poste->code] ?? $poste->libelle }}</span>
                    <span class="font-mono-tatacora text-slate-600">{{ MontantFcfa::format($poste->net) }}</span>
                  </div>
                @endforeach
                <div class="flex justify-between font-bold pt-2 border-t border-slate-100">
                  <span class="text-slate-800">TOTAL PASSIF</span>
                  <span class="font-mono-tatacora text-slate-800">{{ MontantFcfa::format($bilan->totalPassif) }}</span>
                </div>
              </div>
            </div>
          </div>

          @if ($bilan->comptesHorsRubrique !== [])
            {{-- Sans cette liste, un compte ouvert hors nomenclature ne
                 produirait qu'un déséquilibre inexplicable, sur le seul état où
                 l'équilibre EST la garantie. --}}
            <div class="rounded-xl p-3.5 mt-4" style="background:#FEF2F2;border:1px solid #FECACA">
              <p class="text-[13px] font-bold" style="color:#7F1D1D">{{ __('pwa.comptabilite.comptes_hors_rubrique_titre') }}</p>
              <p class="text-[13px] mt-1" style="color:#7F1D1D">{{ __('pwa.comptabilite.comptes_hors_rubrique_detail') }}</p>
              <ul class="list-disc pl-5 mt-1.5">
                @foreach ($bilan->comptesHorsRubrique as $compte)
                  <li class="text-[13px]" style="color:#7F1D1D">
                    <span class="font-mono-tatacora">{{ $compte['numero_compte'] }}</span> — {{ $compte['libelle'] }} :
                    {{ MontantFcfa::format($compte['solde']) }}
                  </li>
                @endforeach
              </ul>
            </div>
          @endif
        @endif

      </div>
    </main>
  </div>

</div>

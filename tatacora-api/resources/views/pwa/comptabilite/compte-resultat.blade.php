{{--
    Compte de Résultat — maître : `prototype_v2/pages/m10-resultat.html`.

    Conteneur `max-w-[900px] mx-auto p-5 lg:p-8` (l.18), lien de retour en
    `text-[13px]` (l.21), en-tête (l.20-30), bandeau (l.32) puis la carte
    `bg-white rounded-xl border border-slate-200 p-6 space-y-1` (l.34) dont
    chaque ligne est un `flex justify-between py-1`, le libellé à gauche et le
    montant à droite en `font-mono-tatacora`.

    Les trois écarts — le bandeau « avant impôt », la cascade réelle à la place
    des onze lignes bricolées, et les deux notes de jeu d'essai — sont motivés
    au complet dans `App\Pwa\Livewire\Comptabilite\CompteResultat`.

    ## Les trois intertitres du maître ne sont pas repris, et ils ne manquent pas

    ÉCART DÉLIBÉRÉ — `m10-resultat.html` l.59, l.63, l.71
    Le maître : trois intertitres en capitales — « Exploitation », « Financier »,
    « Hors Activités Ordinaires (HAO) ».
    Ici : absents.
    Raison : la cascade SYSCOHADA les porte déjà, sous forme de soldes nommés —
    `XE` « RÉSULTAT D'EXPLOITATION », `XF` « RÉSULTAT FINANCIER », `XH`
    « RÉSULTAT HORS ACTIVITÉS ORDINAIRES ». Les rajouter ferait lire deux fois
    le même découpage, une fois comme titre et une fois comme total. Et les
    poser au bon endroit exigerait de classer les rubriques du Service par
    section — une règle comptable qu'aucun champ ne porte, donc à inventer ici,
    ce que `LARAVEL_PWA.md` §3 interdit.
    Refus déclaré : maitre-refuse:m10-resultat.html#page
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
            'icone' => '<path stroke-linecap="round" stroke-linejoin="round" d="M3 3v18h18"/><path stroke-linecap="round" stroke-linejoin="round" d="M18.7 8l-5.1 5.1-2.7-2.7L7 14.3"/>',
            'titre' => 'Compte de Résultat',
            'sousTitre' => 'Produits, charges et résultat net — par nature (SYSCOHADA révisé)',
        ])

        @include('pwa.comptabilite.partials.socle', [
            'identifiant' => 'f-exercice',
            'repartition' => $resultat?->statuts,
        ])

        @if ($exercice === null)
          @include('pwa.comptabilite.partials.aucun-exercice')
        @else

          @if ($resultat->impotNonComptabilise)
            {{-- Le bandeau du maître, à sa place et de sa couleur, mais
                 CONDITIONNEL et sans la phrase sur le taux d'IS : il n'existe
                 aucun taux à configurer (PA-151). Voir le composant. --}}
            <div class="mb-4">
              <div class="rounded-lg px-4 py-3 text-[13px] font-semibold flex items-start gap-2 bg-amber-50 text-amber-700 border border-amber-200">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="shrink-0 mt-0.5"><circle cx="12" cy="12" r="10"/><path stroke-linecap="round" d="M12 8v4M12 16h.01"/></svg>
                <span>{{ __('pwa.comptabilite.resultat_avant_impot') }}</span>
              </div>
            </div>
          @endif

          <div class="bg-white rounded-xl border border-slate-200 p-6 space-y-1">
            @foreach ($resultat->lignes as $ligne)
              @php
                  // Le traitement `gras` du maître (l.36-38) : bordure haute,
                  // texte foncé, sur les seules lignes de solde.
                  $classesTexte = $ligne->estSolde ? 'font-bold text-slate-800' : 'text-slate-500 pl-4';
                  $bordure = $ligne->estSolde ? 'border-t-2 border-slate-200 pt-2 mt-1' : '';
              @endphp
              <div class="flex justify-between py-1 {{ $bordure }}">
                <span class="{{ $classesTexte }} text-[15px]">
                  <span class="font-mono-tatacora text-slate-400 text-[13px]">{{ $ligne->code }}</span>
                  {{ $ligne->libelle }}
                </span>
                <span class="font-mono-tatacora text-[15px] {{ $classesTexte }} {{ ! $ligne->estSolde && $ligne->sens === 'charge' ? 'text-red-600' : '' }}">
                  {{ MontantFcfa::format($ligne->montant) }}
                </span>
              </div>
            @endforeach

            <div class="mt-5 pt-3 border-t-2 border-[var(--navy)]">
              <div class="flex justify-between py-1">
                {{-- Le libellé du maître (l.83), en capitales comme au maître.
                     Il nomme la même grandeur que `XI` ci-dessus quand aucun
                     impôt n'est comptabilisé ; quand il y en a un, c'est
                     `resultatNet` qui est net, et le libellé le dit. --}}
                <span class="font-bold text-slate-800 text-[15px]">
                  {{ $resultat->impotNonComptabilise ? 'RÉSULTAT AVANT IMPÔT SUR LES SOCIÉTÉS' : 'RÉSULTAT NET' }}
                </span>
                <span class="font-mono-tatacora text-[15px] font-bold text-slate-800">{{ MontantFcfa::format($resultat->resultatNet) }}</span>
              </div>
              <div class="flex justify-between py-1">
                <span class="text-slate-500 pl-4 text-[15px]">Impôt sur le résultat comptabilisé (classe 89)</span>
                <span class="font-mono-tatacora text-[15px] text-slate-500">{{ MontantFcfa::format($resultat->impotComptabilise) }}</span>
              </div>
            </div>
          </div>
        @endif

      </div>
    </main>
  </div>

</div>

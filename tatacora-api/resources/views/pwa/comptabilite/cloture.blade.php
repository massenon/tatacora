{{--
    Clôture Périodique — maître : `prototype_v2/pages/m10-cloture.html`.

    Conteneur `max-w-[800px] mx-auto p-5 lg:p-8` (l.18), lien de retour en
    `text-[13px]` (l.21), en-tête (l.20-30), bandeau ambre sur le nom de
    l'écran (l.32-34), puis la pile `space-y-3` (l.36) de cartes
    `bg-white rounded-xl border border-slate-200 p-5`, chacune avec son
    `<h3 class="text-[15px] font-bold text-slate-800 mb-3">` et ses lignes
    `flex items-start gap-2.5` à pastille ronde (l.104-116).

    Les écarts sont motivés au complet dans
    `App\Pwa\Livewire\Comptabilite\Cloture`.
--}}
@php
    use App\Domain\Comptabilite\ReadModels\EtatCloture;
    use App\Pwa\Support\MontantFcfa;

    // Les trois styles d'état du maître (l.94-97), plus un QUATRIÈME.
    //
    // ÉCART DÉLIBÉRÉ — `m10-cloture.html` l.94-97
    // Le maître : trois styles — `ok`, `bloque`, `non_teste`.
    // Ici : quatre, le serveur distinguant `non_verifiable` de `non_atteint`.
    // Raison : le maître écrit « Dépend de l'étape 3, non atteinte » sous un
    // style `bloque` ROUGE (l.79-80). Une étape qui n'a pas encore été tentée
    // n'est pas une anomalie : la peindre en rouge fait chercher un défaut qui
    // n'existe pas. `non_atteint` reprend donc le style neutre de
    // `non_teste`, et `non_verifiable` garde le sien — les deux ne se
    // confondent pas plus qu'un blocage et une limite du domaine.
    $stylesEtat = [
        EtatCloture::ETAT_CONFORME => [
            'icone' => '<path stroke-linecap="round" stroke-linejoin="round" d="M20 6L9 17l-5-5"/>',
            'couleur' => '#2E7D32', 'fond' => '#E8F5E9',
        ],
        EtatCloture::ETAT_BLOQUE => [
            'icone' => '<circle cx="12" cy="12" r="10"/><path stroke-linecap="round" d="M12 8v4M12 16h.01"/>',
            'couleur' => '#C62828', 'fond' => '#FDECEC',
        ],
        EtatCloture::ETAT_NON_VERIFIABLE => [
            'icone' => '<circle cx="12" cy="12" r="10"/><path stroke-linecap="round" d="M12 16v-4M12 8h.01"/>',
            'couleur' => '#6B7280', 'fond' => '#F3F4F6',
        ],
        EtatCloture::ETAT_NON_ATTEINT => [
            'icone' => '<circle cx="12" cy="12" r="10"/><path stroke-linecap="round" d="M12 16v-4M12 8h.01"/>',
            'couleur' => '#6B7280', 'fond' => '#F3F4F6',
        ],
    ];
@endphp
<div class="contents">

  @include('pwa.partials.barre-superieure')
  

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[800px] mx-auto p-5 lg:p-8">

        @include('pwa.comptabilite.partials.en-tete', [
            'tailleRetour' => 'text-[13px]',
            'icone' => '<path stroke-linecap="round" stroke-linejoin="round" d="M21 12a9 9 0 11-9-9c2.52 0 4.93 1 6.74 2.74L21 8"/><path stroke-linecap="round" stroke-linejoin="round" d="M21 3v5h-5"/>',
            'titre' => 'Clôture Périodique',
            'sousTitre' => "Bascule d'exercice fiscal, report à nouveau",
        ])

        {{-- Le bandeau du maître (l.32-34), conservé : PA-28 est TOUJOURS
             ouvert au 27/08/2026 — « Clôture Périodique » (mensuelle, verrou
             léger) et « Clôture d'Exercice » (annuelle, complète) restent deux
             concepts distincts non tranchés. Vérifié avant de m'y fier. --}}
        <div class="rounded-lg px-4 py-3 text-[13px] font-semibold bg-amber-50 text-amber-700 border border-amber-200 mb-5 flex items-start gap-2">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="shrink-0 mt-0.5"><circle cx="12" cy="12" r="10"/><path stroke-linecap="round" d="M12 8v4M12 16h.01"/></svg>
          <span><strong>Note sur le nom de cet écran :</strong> "Clôture Périodique" (mensuelle, verrou léger) et "Clôture d'Exercice" (annuelle, complète) restent deux concepts distincts non encore tranchés — PA-28, <span class="font-mono-tatacora">PLAN_ACTION_SEQUENCE_POST_AUDIT.md</span>. Cet écran affiche la procédure de clôture <strong>annuelle</strong> complète (<span class="font-mono-tatacora">MODULE_COMPTABILITE_COMPLET_PART4.md</span> §2) — le seul mécanisme actuellement spécifié.</span>
        </div>

        @include('pwa.comptabilite.partials.socle', [
            'identifiant' => 'f-exercice',
            'repartition' => $cloture?->statuts,
        ])

        @if ($exercice === null)
          @include('pwa.comptabilite.partials.aucun-exercice')
        @else

          <div class="space-y-3">
            @foreach (collect($cloture->etapes)->groupBy('groupe') as $etapes)
              <div class="bg-white rounded-xl border border-slate-200 p-5">
                <h3 class="text-[15px] font-bold text-slate-800 mb-3">{{ $etapes->first()->groupe }}. {{ $etapes->first()->groupeLibelle }}</h3>
                <div class="space-y-2">
                  @foreach ($etapes as $etape)
                    @php($style = $stylesEtat[$etape->etat])
                    <div class="flex items-start gap-2.5">
                      <div class="w-5 h-5 rounded-full flex items-center justify-center shrink-0 mt-0.5" style="background:{{ $style['fond'] }}">
                        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="{{ $style['couleur'] }}" stroke-width="2.5">{!! $style['icone'] !!}</svg>
                      </div>
                      <div>
                        <p class="text-[15px] text-slate-700">{{ $etape->libelle }}</p>
                        <p class="text-[13px] text-slate-400 mt-0.5">
                          {{-- La note du maître était une phrase sur le jeu
                               d'essai ; ici c'est le CONSTAT du serveur — soit
                               la valeur réellement mesurée, soit le motif à
                               code fermé. Les deux sont exclusifs. --}}
                          @if ($etape->motif !== null)
                            {{ __('pwa.comptabilite.motifs.' . $etape->motif) }}
                          @elseif ($etape->valeur !== null)
                            {{ __('pwa.comptabilite.etats.' . $etape->etat) }} — {{ $etape->valeur }}
                          @else
                            {{ __('pwa.comptabilite.etats.' . $etape->etat) }}
                          @endif
                        </p>
                      </div>
                    </div>
                  @endforeach
                </div>
              </div>
            @endforeach
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-5 mt-3">
            <h3 class="text-[15px] font-bold text-slate-800 mb-3">Résultat à reporter</h3>
            <div class="flex justify-between text-[15px]">
              <span class="text-slate-600">Vers le compte {{ $cloture->compteDeDestination }}</span>
              <span class="font-mono-tatacora font-bold" style="color:{{ MontantFcfa::estNegatif($cloture->resultatAReporter) ? 'var(--erreur)' : 'var(--navy)' }}">{{ MontantFcfa::format($cloture->resultatAReporter) }}</span>
            </div>

            @if ($cloture->limitesNonVerifiables !== [])
              {{-- Ces limites ne SONT PAS des blocages, et les mélanger figerait
                   l'indicateur de conformité à `false` pour toujours — le champ
                   n'apprendrait plus rien (PA-59/60/61 retourné). Le serveur les
                   tient dans une constante séparée ; l'écran les garde séparées. --}}
              <p class="text-[13px] font-bold text-slate-500 mt-4">{{ __('pwa.comptabilite.limites_titre') }}</p>
              <ul class="list-disc pl-5 mt-1.5">
                @foreach ($cloture->limitesNonVerifiables as $limite)
                  <li class="text-[13px] text-slate-400">{{ __('pwa.comptabilite.motifs.' . $limite) }}</li>
                @endforeach
              </ul>
            @endif

          </div>
        @endif

      </div>
    </main>
  </div>

</div>

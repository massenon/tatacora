{{--
    LES HUIT CARTES D'INDICATEUR — anatomie du maître au caractère près.

    Maître : `prototype_v2/pages/tableau-de-bord.html` l.413-421 (et
    `tableau-de-bord.js` l.88-96, qui rend la MÊME carte pour l'accordéon).
    Pastille `w-9 h-9 rounded-lg` sur fond teinté, icône 17 px, valeur
    `text-xl font-bold` navy, libellé `text-[13px] text-slate-500`, note
    `text-[12px] text-slate-400`.

    ## POURQUOI UN PARTIEL, ET PAS DEUX BOUCLES

    Le maître pose DEUX conteneurs pour les mêmes huit indicateurs —
    `#conteneur-kpi` (accordéon sous `lg`) et `#grille-kpi`. Écrire la carte
    deux fois dans la vue ferait diverger les deux bandes au premier retouchage
    d'anatomie : ce sont les mêmes chiffres, ce doit être le même code
    (Article 10). Le partiel vit sous `pwa/livewire/` et non sous
    `pwa/partials/` : il n'appartient qu'à cet écran.

    ## AUCUN CHIFFRE N'EST ÉCRIT ICI

    `$indicateurs === null` rend la bande VIDE en DISANT que rien n'a été
    mesuré. Un repli à 200 000 F s'afficherait exactement comme un vrai chiffre,
    avec la même typographie, sur l'écran où l'on décide — c'est la faute la
    plus grave qu'un tableau de bord puisse commettre, et elle a réellement été
    commise dans ce fichier avant le 31/08/2026.

    ## LA QUATRIÈME LIGNE (« vs période précédente ») EST RETIRÉE — arbitrage
    du Product Owner du 02/09/2026

    La carte portait CINQ blocs (pastille, valeur, libellé, note, variation)
    quand le maître, une fois `tableau-de-bord.js` chargé, n'en pose que
    QUATRE (`l.88-96` : pastille, valeur, libellé, note — la ligne « +8,2 % vs
    mois dernier » de la maquette statique, l.404-411, est un chiffre de
    DÉMONSTRATION écrasé au premier rendu réel, jamais reproduit par le
    calcul). La cinquième ligne rendait donc la carte plus HAUTE que celle du
    maître — un ajout structurel que le mécanisme (Article 3.3) n'autorise
    pas. L'arbitrage : « la conserver UNIQUEMENT si la hauteur de carte reste
    celle du maître, sinon la retirer ». Elle ne pouvait pas rester sans
    ajouter une ligne ; elle est retirée. EF-M11-03 (indicateurs comparatifs)
    reste servie : `variation_pct` et `precedent` restent sur `$indicateurs`,
    lus par `lignesIndicateurs()` pour le rapport « Synthèse » exporté — la
    comparaison existe toujours, elle ne s'affiche plus en permanence sur
    la carte.
--}}
@if ($indicateurs === null)
  <div class="col-span-2 lg:col-span-4 rounded-xl p-4" style="background:#FDECEC;border:1px solid #F5B5B5">
    <p class="text-[13px] font-bold" style="color:#7F1D1D">{{ __('accueil_pwa.non_consulte') }}</p>
    <p class="text-[12px] mt-1" style="color:#7F1D1D">{{ __('accueil_pwa.lecture_impossible') }}</p>
  </div>
@else
  @foreach ($indicateurs as $cle => $kpi)
    @php
        // La clé vient du SERVICE : un indicateur renommé côté domaine perd
        // son icône plutôt que d'en recevoir une fausse. Le gris ardoise est
        // la couleur de « je ne sais pas », pas celle d'une famille.
        [$couleurIcone, $fondIcone, $traceIcone] = $iconesKpi[$cle] ?? ['#64748B', '#F1F5F9', '<circle cx="12" cy="12" r="9"/>'];
    @endphp
    <div class="carte-kpi bg-white rounded-xl border border-slate-200 p-4">
      <div class="w-9 h-9 rounded-lg flex items-center justify-center mb-3" style="background:{{ $fondIcone }}">
        <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="{{ $couleurIcone }}" stroke-width="2">{!! $traceIcone !!}</svg>
      </div>
      <p class="text-xl font-bold" style="color:var(--navy)">{{ $valeurKpi($kpi) }}</p>
      <p class="text-[13px] text-slate-500 mt-0.5">{{ __('accueil_pwa.kpi.' . $cle . '.libelle') }}</p>
      <p class="text-[12px] text-slate-400 mt-1">{{ __('accueil_pwa.kpi.' . $cle . '.note', ['total' => $kpi['precedent']]) }}</p>
    </div>
  @endforeach
@endif

{{--
    Le sélecteur d'exercice et le filtre de statut, communs aux douze pages M10.

    ## ÉCART DÉLIBÉRÉ — un contrôle AJOUTÉ, et la raison n'est pas technique

    `prototype_v2/pages/m10-bilan.html` l.29, `m10-resultat.html` l.29,
    `m10-flux-tresorerie.html` l.29, `m10-notes-annexes.html` l.29,
    `m10-etats-financiers.html` l.29
    Le maître : écrit « exercice 2026 » EN DUR dans le sous-titre, et n'offre
    aucun sélecteur — son jeu de démonstration ne contient qu'un exercice,
    implicite.
    Ici : un sélecteur d'exercice, et l'année réellement consultée dans le
    sous-titre.
    Raison : `MODULE_COMPTABILITE_COMPLET.md` §1 — « Tout écran de M10 filtre
    systématiquement par `exercice_id` — jamais un état "toutes années
    confondues" par défaut, qui n'aurait pas de sens comptable. » L'Article 0
    donne la documentation pour autorité sur les règles de calcul, et celle-ci
    en est une. `RequeteExerciceRequest` explique pourquoi retomber en silence
    sur l'exercice `ouvert` serait un défaut : deux postes ouverts sur la même
    page rendraient deux années différentes le jour d'une bascule, sans que
    rien ne le dise. Sans sélecteur, la page n'aurait aucun moyen de connaître
    un identifiant d'exercice — c'est la forme exacte de PA-128, une donnée
    absente de l'interface est une donnée hors d'atteinte. Et laisser
    « exercice 2026 » écrit en dur au-dessus des chiffres de 2027 serait le
    deuxième interdit de l'Article 6.

    ## Le filtre de statut, lui, EST au maître

    `m10-syscohada.html` l.93 : la case « Inclure les brouillons ». Elle est
    rendue ici en trois états explicites plutôt qu'en case à cocher, parce que
    le serveur en admet trois (`EcritureComptable::FILTRES_STATUT`) et qu'une
    case à cocher n'en dirait que deux : « brouillons seuls » n'aurait aucun
    moyen d'être demandé. Le libellé de la case du maître reste porté sur le
    hub, qui est l'écran où elle figure.

    ## Un état DIT son filtre (PA-119)

    La répartition réelle — combien de validées, combien de brouillons — est
    affichée à côté du sélecteur. Un état qui tait ce qu'il a écarté laisse
    croire que le registre est celui qu'on voit.
--}}
<div class="bg-white rounded-xl border border-slate-200 p-3.5 mb-4">
  <div class="flex flex-wrap gap-2.5 items-center">
    <label for="{{ $identifiant ?? 'f-exercice' }}" class="text-[12px] text-slate-500">{{ __('pwa.comptabilite.exercice') }}</label>
    <select id="{{ $identifiant ?? 'f-exercice' }}" wire:model.live="exerciceId"
            class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
      <option value="">{{ __('pwa.comptabilite.exercice_choisir') }}</option>
      @foreach ($exercices as $unExercice)
        <option value="{{ $unExercice->id }}">{{ $unExercice->annee }}</option>
      @endforeach
    </select>

    <label for="{{ ($identifiant ?? 'f') . '-statut' }}" class="text-[12px] text-slate-500">{{ __('pwa.comptabilite.statut_ecritures') }}</label>
    <select id="{{ ($identifiant ?? 'f') . '-statut' }}" wire:model.live="filtreStatut"
            class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
      <option value="toutes">{{ __('pwa.comptabilite.statut_toutes') }}</option>
      <option value="validee">{{ __('pwa.comptabilite.statut_validee') }}</option>
      <option value="brouillon">{{ __('pwa.comptabilite.statut_brouillon') }}</option>
    </select>

    @isset($repartition)
      <span class="text-[12px] text-slate-400">
        {{ __('pwa.comptabilite.repartition', ['validee' => $repartition->validee, 'brouillon' => $repartition->brouillon]) }}
      </span>
    @endisset

    <span class="ml-auto text-[12px] text-slate-400">{{ __('pwa.comptabilite.lecture_seule') }}</span>
  </div>
</div>

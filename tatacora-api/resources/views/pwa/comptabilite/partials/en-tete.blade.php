{{--
    L'en-tête de page des onze écrans qui descendent du hub M10.

    Sa structure est celle du maître, identique d'une page à l'autre — par
    exemple `prototype_v2/pages/m10-plan-comptable.html` l.20-30 : un lien de
    retour doré, puis une ligne `flex items-center gap-2.5` portant l'icône et
    le `<h1>`, puis le sous-titre `text-[15px] text-slate-500 mt-1.5`.

    ⚠ LA TAILLE DU LIEN DE RETOUR VARIE D'UNE PAGE À L'AUTRE AU MAÎTRE, et ce
    n'est pas une erreur de transcription : `m10-plan-comptable.html`,
    `m10-journal.html`, `m10-grand-livre.html`, `m10-balance.html` et
    `m10-bilan.html` l'écrivent `text-[15px]` ; `m10-resultat.html`,
    `m10-flux-tresorerie.html`, `m10-notes-annexes.html`,
    `m10-etats-financiers.html`, `m10-analytique.html` et `m10-cloture.html`
    l'écrivent `text-[13px]`. C'est une incohérence du maître — Article 8 :
    « une incohérence entre deux pages du prototype se signale au
    commanditaire ; on ne la tranche pas seul, sous peine de créer un troisième
    comportement qui n'existe nulle part ». Elle est donc REPORTÉE telle
    quelle, page par page, via `$tailleRetour`, et signalée au rapport.

    ⚠ `assets/css/app.css` remappe l'échelle typographique à l'intérieur de
    `<main>` : `text-[13px]` y rend 12,5 px. Les valeurs sont donc reprises au
    caractère près, jamais converties.

    Paramètres : $icone (contenu du <svg>), $titre, $sousTitre, $tailleRetour.
--}}
<div class="mb-5">
  <a href="{{ route('pwa.comptabilite.hub') }}" wire:navigate
     class="{{ $tailleRetour }} font-semibold flex items-center gap-1.5 mb-3" style="color:var(--gold)">
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M19 12H5M12 19l-7-7 7-7"/></svg>
    {{ __('pwa.comptabilite.retour_hub') }}
  </a>
  <div class="flex items-center gap-2.5">
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2">{!! $icone !!}</svg>
    <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ $titre }}</h1>
  </div>
  <p class="text-[15px] text-slate-500 mt-1.5">{!! $sousTitre !!}</p>
</div>

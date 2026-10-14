{{--
    L'entête de tableau des onglets du hub M10 — UN SEUL AUTEUR par tableau
    (02/09/2026, G5).

    Chaque onglet définit SES colonnes une seule fois (`$colonnes`, liste de
    couples [libellé, alignement]) et les rend par ce partiel, dans son rendu
    complet COMME dans son squelette (`_squelette_tableau`). Deux `<thead>`
    écrits à la main pour le même tableau auraient divergé au premier
    renommage — la famille de défaut que PA-160/PA-161 documente.

    Les classes sont celles, uniformes, des onglets du hub (`px-3 py-2.5
    text-[11px] uppercase tracking-wide text-white/90 font-semibold` sur fond
    navy) — mesurées sur les neuf onglets avant extraction.
--}}
<thead class="bg-[var(--navy)]"><tr>
  @foreach ($colonnes as [$libelleColonne, $alignementColonne])
    <th class="px-3 py-2.5 text-{{ $alignementColonne }} text-[11px] uppercase tracking-wide text-white/90 font-semibold">{{ $libelleColonne }}</th>
  @endforeach
</tr></thead>

{{--
    LE CONTENU DE LA CELLULE « STOCK VENDABLE » — un seul auteur.

    Extrait le 03/09/2026, quand l'onglet « Ventes du rayon » a eu besoin de
    rendre le même chiffre : deux cellules écrites à deux endroits auraient
    fini par diverger — un état oublié d'un côté, un badge de couleur
    différente de l'autre —, et c'est exactement ce que `carte-module.js`
    refuse l.7 à propos des deux écrans jumeaux.

    ## TROIS états, jamais deux (PA-129)

    Un chiffre, « non suivi » (aucun lien de stock), « non consulté » (la
    lecture a échoué). Replier les deux derniers sur zéro afficherait une
    rupture là où il n'y a qu'une absence d'information, et « 0 » se lit
    comme un fait.

    @param array<string, mixed>|null $stock  la clé `stock` d'une ligne de
           `EcranDeCarte::lignesDeLaCarte()` — son SEUL auteur.
    @param string $motif  la phrase qui explique l'absence de lien.
--}}
@if ($stock === null)
  {{-- Sans lien de stock : le maître écrit « non suivi » et porte
       l'explication en infobulle. --}}
  <span class="text-[11px] text-slate-400" title="{{ $motif }}">{{ __('carte_pwa.commun.badge_non_suivi') }}</span>
@elseif ($stock['non_consulte'])
  <span class="text-[11px] text-amber-700">{{ __('carte_pwa.commun.stock_non_consulte') }}</span>
@elseif ($stock['rupture'])
  <span class="text-[11px] px-1.5 py-0.5 rounded bg-red-50 text-red-700 font-semibold">{{ __('carte_pwa.commun.badge_rupture') }}</span>
@else
  <span class="text-[13px] font-bold {{ $stock['sous_seuil'] ? 'text-amber-600' : '' }}"
        style="{{ $stock['sous_seuil'] ? '' : 'color:var(--navy)' }}">{{ $stock['unites_vendables'] }}</span>
@endif

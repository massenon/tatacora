{{--
    MODALE « RETIRER DE LA CARTE DU JOUR » — bar (M5) et restaurant (M4).

    Maîtres : prototype_v2/pages/m5-bar-carte.html et
    prototype_v2/pages/m4-restaurant-carte.html, dont la modale est construite
    par prototype_v2/pages/carte-module.js l.319-356 (`modale-dispo`).

    ## Le copywriting du maître est EXACT et le reste ; la géométrie ne l'était pas

    Largeur 480 px (`carte-module.js` l.322), en-tête `px-6 py-4`, titre
    `text-base`, sous-titre `text-[12px]`, champs `rounded-lg px-3 py-2.5`,
    boutons `text-[13px] px-4 py-2 rounded-lg`, pied hors du corps. La note
    d'aide est `text-[11px] text-slate-500 bg-slate-50 border border-slate-200
    rounded-lg p-2.5` — la PWA la rendait en `text-[12px] text-slate-600
    bg-slate-50/80 rounded-xl p-3.5`, sans bordure.

    ## Ce que cette modale écrit, et où

    Elle appelait `Session::put('bar_boissons_indisponibles', …)`. Un plat
    retiré revenait tout seul à l'expiration de la session, aucun autre poste
    ne le voyait retiré, et la décision n'était imputable à personne. Elle
    passe désormais par `DisponibiliteCarteService`, qui écrit une ligne
    `indisponibilites_carte` sous verrou.

    ⚠ LES CODES DIVERGEAIENT SANS QUE RIEN NE SE VOIE. La PWA écrivait
    `hors_saison` / `retrait` là où le maître écrit `saison` / `retire`
    (`carte-engine.js` l.51-55), pour des libellés affichés IDENTIQUES. Les
    motifs viennent maintenant du registre fermé `IndisponibiliteCarte::MOTIFS`
    — il n'y a plus de seconde liste à faire diverger.

    ## `temporaire` est une propriété du MOTIF, pas de l'enregistrement

    C'est tout l'objet du paragraphe d'aide du maître : une rupture revient
    d'elle-même au réapprovisionnement, un retrait est une décision
    commerciale. La distinction est RENDUE sur chaque option, pour qu'elle se
    lise au moment du choix et pas seulement dans le paragraphe.

    ## ⚠ Écart déclaré — l'invite de recherche du motif (31/08/2026)

    Le maître pose `data-recherche data-placeholder="Rechercher un motif…"` sur
    ce `<select>` (`carte-module.js` l.334-335), par symétrie avec celui des
    articles de stock. `IndisponibiliteCarte::MOTIFS` est un registre FERMÉ de
    trois entrées : un champ de recherche au-dessus de trois options serait un
    contrôle sans objet, et le rendre ferait chercher à l'utilisateur ce qu'il
    voit déjà en entier. L'invite « Rechercher un motif… » n'est donc pas
    rendue, et son absence est écrite ici plutôt que subie.

    Props :
      nom     — libellé de l'article de carte visé
      motifs  — `IndisponibiliteCarte::MOTIFS`, registre fermé
--}}
@props([
    'nom',
    'motifs',
])
<x-pwa.modale :titre="__('carte_pwa.modale_dispo.titre')"
              :sousTitre="$nom"
              largeur="480px"
              fermer="$set('etatFormulaire', null)">

    {{-- maître — carte-module.js l.330-338 --}}
    <div>
        <label for="dispo-motif" class="block text-[13px] font-semibold text-slate-700 mb-1.5">
            {{ __('carte_pwa.modale_dispo.label_motif') }} <span class="text-red-500">*</span>
        </label>
        <select id="dispo-motif" wire:model="motifIndisponibilite" required
                class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
            @foreach ($motifs as $code => $motif)
                <option value="{{ $code }}">{{ $motif['libelle'] }} — {{ $motif['temporaire'] ? __('carte_pwa.modale_dispo.temporaire') : __('carte_pwa.modale_dispo.definitif') }}</option>
            @endforeach
        </select>

        @error('motifIndisponibilite')
            <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p>
        @enderror
    </div>

    {{-- maître — carte-module.js l.339-343 --}}
    <div>
        <label for="dispo-commentaire" class="block text-[13px] font-semibold text-slate-700 mb-1.5">
            {{ __('carte_pwa.modale_dispo.label_commentaire') }}
        </label>
        <input id="dispo-commentaire" type="text"
               wire:model="commentaireIndisponibilite"
               placeholder="{{ __('carte_pwa.modale_dispo.invite_commentaire') }}"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">

        @error('commentaireIndisponibilite')
            <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p>
        @enderror
    </div>

    {{-- maître — carte-module.js l.344-348 : `text-[11px] text-slate-500
         bg-slate-50 border border-slate-200 rounded-lg p-2.5`. --}}
    <p class="text-[11px] text-slate-500 bg-slate-50 border border-slate-200 rounded-lg p-2.5">
        {!! __('carte_pwa.modale_dispo.aide') !!}
    </p>

    <x-slot:pied>
        <button type="button" wire:click="$set('etatFormulaire', null)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerRetraitDeLaCarte" wire:loading.attr="disabled"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('carte_pwa.modale_dispo.bouton_retirer') }}</button>
    </x-slot:pied>
</x-pwa.modale>

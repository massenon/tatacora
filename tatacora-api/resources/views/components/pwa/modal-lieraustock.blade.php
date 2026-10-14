{{--
    MODALE « LIER AU STOCK » — bar (M5) et restaurant (M4).

    Maîtres : prototype_v2/pages/m5-bar-carte.html et
    prototype_v2/pages/m4-restaurant-carte.html, dont la modale est construite
    par prototype_v2/pages/carte-module.js l.221-262 (`modale-lien`).

    ## Géométrie — la mesure du maître, pas une approximation

    Elle avait dérivé sur SEPT points, et aucun ne se voyait isolément :
    largeur 540 px au lieu de 560, titre `text-lg` au lieu de `text-base`,
    sous-titre `text-[13px]` au lieu de `text-[12px]`, en-tête `py-5` au lieu
    de `py-4`, champs `rounded-xl px-3.5` au lieu de `rounded-lg px-3`, boutons
    `px-5 py-2.5 rounded-xl` au lieu de `px-4 py-2 rounded-lg`, et un pied DANS
    le corps au lieu d'une barre distincte. Le châssis `<x-pwa.modale>` porte
    désormais l'en-tête, le corps et le pied du maître : il n'y a plus qu'un
    endroit où cette géométrie est écrite.

    ⚠ ESPACEMENTS = échelle nommée de Tailwind (`py-2.5` fait 10 px) ;
    TAILLES DE POLICE = valeurs entre crochets. Ne pas généraliser d'une
    famille à l'autre (PA-145).

    ## Le champ qui était jeté

    « Combien de X dans une unité de stock ? » est obligatoire au maître, et
    son aperçu annonce ce que chaque vente décrémentera. Le composant
    n'écrivait que `article_id`. La valeur est désormais liée à
    `unitesVendablesParUniteStock` et part à `lierAuStock()`.

    ## La recherche du maître est RENDUE, pas approchée

    Le maître pose `data-recherche data-placeholder="Rechercher un article de
    stock…"` (`SelectRecherche`) parce que la liste dépasse la trentaine de
    références. La PWA n'a pas ce composant : le filtre est fait au SERVEUR,
    par `wire:model` sur `rechercheArticleStock`, et le `<select>` ne rend que
    ce qui reste. Le geste est le même, l'invite est celle du maître.

    Props :
      nom      — libellé de l'article de carte visé
      prix     — son prix de vente, déjà formaté
      articles — les articles de stock proposés (déjà filtrés)
      apercu   — l'aperçu, ou `null` quand la saisie n'est pas exploitable
--}}
@props([
    'nom',
    'prix',
    'articles',
    'apercu' => null,
])
<x-pwa.modale :titre="__('carte_pwa.modale_lien.titre')"
              :sousTitre="__('carte_pwa.modale_lien.sous_titre', ['article' => $nom, 'prix' => $prix])"
              largeur="560px"
              fermer="$set('etatFormulaire', null)">

    {{-- maître — carte-module.js l.232-244 --}}
    <div>
        <label for="lien-article" class="block text-[13px] font-semibold text-slate-700 mb-1.5">
            {{ __('carte_pwa.modale_lien.label_article') }} <span class="text-red-500">*</span>
        </label>

        <input type="search"
               wire:model.live.debounce.300ms="rechercheArticleStock"
               placeholder="{{ __('carte_pwa.modale_lien.invite_article') }}"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 mb-1.5 focus:border-[var(--gold)] focus:outline-none">

        <select id="lien-article" wire:model.live="articleStockId" required
                class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
            <option value="">{{ __('carte_pwa.modale_lien.invite_article') }}</option>
            @foreach ($articles as $article)
                <option value="{{ $article->id }}">{{ $article->libelle }} — {{ $article->unite_mesure }}</option>
            @endforeach
        </select>

        @if ($articles->isEmpty())
            {{-- Une liste vide se DIT : un `<select>` sans option laisserait
                 croire à un écran cassé plutôt qu'à une recherche trop étroite. --}}
            <p class="text-[11px] text-amber-700 mt-1">{{ __('carte_pwa.modale_lien.aucun_article_stock') }}</p>
        @endif

        <p class="text-[11px] text-slate-400 mt-1">{!! __('carte_pwa.modale_lien.aide_article') !!}</p>

        @error('articleStockId')
            <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p>
        @enderror
    </div>

    {{-- maître — carte-module.js l.245-256 --}}
    <div>
        <label for="lien-conversion" class="block text-[13px] font-semibold text-slate-700 mb-1.5">
            {{ __('carte_pwa.modale_lien.label_conversion', ['article' => $nom]) }} <span class="text-red-500">*</span>
        </label>
        <input id="lien-conversion" type="number" min="0.0001" step="any" required
               wire:model.live.debounce.300ms="unitesVendablesParUniteStock"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
        <p class="text-[11px] text-slate-400 mt-1">{!! __('carte_pwa.modale_lien.aide_conversion') !!}</p>

        @error('unitesVendablesParUniteStock')
            <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p>
        @enderror
    </div>

    {{-- maître — carte-module.js l.276-286 : encadré SANS FOND, `p-3`,
         `text-[12px]`. Il n'apparaît que quand la saisie est exploitable :
         un aperçu bâti sur une valeur par défaut laisserait croire qu'un
         champ vide vaut « une pour une ». --}}
    @if ($apercu !== null)
        <div class="border border-slate-200 rounded-lg p-3 text-[12px]">
            <div class="flex justify-between">
                <span class="text-slate-600">{{ __('carte_pwa.modale_lien.apercu_stock') }}</span>
                @if ($apercu['solde'] === null)
                    {{-- Trois états, jamais deux : un chiffre, « sans lien de
                         stock », « non consulté ». Zéro se lirait comme une
                         rupture (PA-129). --}}
                    <strong class="text-amber-700">{{ __('carte_pwa.commun.stock_non_consulte') }}</strong>
                @else
                    <strong>{{ $apercu['solde'] }} {{ $apercu['article']->unite_mesure }}</strong>
                @endif
            </div>

            <div class="flex justify-between">
                <span class="text-slate-600">{{ __('carte_pwa.modale_lien.apercu_vendables') }}</span>
                @if ($apercu['vendables'] === null)
                    <strong class="text-amber-700">{{ __('carte_pwa.commun.stock_non_consulte') }}</strong>
                @else
                    <strong style="color:var(--navy)">{{ $apercu['vendables'] }} × {{ $nom }}</strong>
                @endif
            </div>

            <div class="flex justify-between mt-1 pt-1 border-t border-slate-100">
                <span class="text-slate-500">{{ __('carte_pwa.modale_lien.apercu_decrement') }}</span>
                <span class="text-slate-500">{{ $apercu['decrement'] }} {{ $apercu['article']->unite_mesure }}</span>
            </div>
        </div>
    @endif

    <x-slot:pied>
        {{-- maître — carte-module.js l.253-255 : `text-[13px] px-4 py-2 rounded-lg`. --}}
        <button type="button" wire:click="$set('etatFormulaire', null)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerLienAuStock" wire:loading.attr="disabled"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('carte_pwa.modale_lien.bouton_enregistrer') }}</button>
    </x-slot:pied>
</x-pwa.modale>

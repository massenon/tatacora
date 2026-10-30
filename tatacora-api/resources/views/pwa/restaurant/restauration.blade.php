{{--
    M4 — RESTAURANT & CUISINE (catalogue des plats).

    Maître : prototype_v2/pages/m4-restauration.html.

    ## Le titre du maître, et pas un autre

    La vue livrée rendait « Catalogue des Plats & Restauration ». Le maître
    écrit `Restaurant & Cuisine` (l.28) : c'est le mot que le client a validé
    des yeux, et le comparateur des trois sources confronte le `<h1>` du maître
    au code qui porte la page.

    ## Les quatre colonnes du maître, et RIEN QUE les siennes

    Maître : `Plat · Catégorie · Prix de vente · Disponible`. La vue livrée
    avait perdu `Disponible` — le sujet même de l'écran de disponibilité — et
    renommé les trois autres (« Plat / Intitulé », « Prix Vente »).

    02/09/2026 — les deux colonnes ajoutées, `Fiche Technique` et
    `Coût Matière`, sont RETIRÉES (garde G5) : elles n'existent dans aucun
    tableau du maître, et une colonne supplémentaire se décide, elle
    n'apparaît pas par copier-coller. L'information reste accessible par la
    modale d'édition du plat, qui porte la fiche technique et son coût
    matière calculé.

    ⚠ La casse est celle du maître : `uppercase` est une règle CSS, qui ne
    s'applique ni au CSV ni au PDF. Une majuscule écrite en dur ressort telle
    quelle sur le document remis au comptable. La colonne d'actions n'a pas
    d'entête.

    ## Il n'y a plus de suppression, ni de boîte native

    `supprimerPlat()` faisait `$plat->delete()` derrière un
    `wire:confirm="Supprimer ce plat ?"`. Le geste est devenu « Retirer de la
    carte » — le motif `retire` du maître —, rendu par la modale d'archivage
    partagée, avec ses trois états et son bouton masqué quand rien n'est
    archivable.

    Déclarations pour la garde des trois sources : AUCUN bloc du maître n'est
    refusé ici. Deux écarts portaient sur des CONTRÔLES, et l'un des deux a
    CESSÉ D'ÊTRE VRAI le 03/09/2026 — datez la raison d'un refus, et vérifiez-la
    avant de vous y fier (PA-144) :

    - « Ingrédients principaux » en texte libre : le maître le porte en
      `textarea`, ce que PA-23 refuse. L'écran ne l'omet plus — il livre le
      REMPLACEMENT que PA-23 réclame, le sous-formulaire de composition en
      vraies clés étrangères vers `articles`, dans la modale « Nouvelle fiche
      technique ». L'écart subsiste sur la FORME, plus sur la fonction ;
    - l'import de masse : toujours absent, et toujours un écart.
--}}
{{--
    ⚠ UNE SEULE FORME DE BLOC PHP DANS TOUT CE FICHIER — la forme à
    directive d'ouverture et de fermeture, jamais la forme en ligne à
    parenthèses. Blade apparie les deux marqueurs en NON-GOURMAND sur le
    fichier entier : une forme en ligne posée après un bloc referme ce
    dernier, et tout ce qui les sépare est restitué NON COMPILÉ. Mesuré
    ici le 31/08/2026 : la page rendait « Undefined variable » sur une
    affectation parfaitement écrite.

    ⚠ ET LE MOT-CLÉ COMPTE MÊME EN COMMENTAIRE. L'extraction des blocs
    bruts passe AVANT le retrait des commentaires : écrire le nom de la
    directive dans un bloc explicatif comme celui-ci suffit à ouvrir un
    bloc fantôme. C'est le second défaut de la même journée, et c'est
    pourquoi cette note ne nomme aucune directive.

    Le contrôle de compilation ne le voit PAS : la vue compile, et c'est
    l'exécution qui échoue. Seul un chargement réel de la page le montre.
--}}
@php
    use App\Pwa\Support\MontantFcfa;

    // `uppercase` est laissé à la feuille de style, comme au maître.
    $entete = static fn (string $libelle, bool $gauche = false): string => '<th class="px-3 py-2.5 '
        . ($gauche ? 'text-left' : 'text-right')
        . ' text-[11px] uppercase tracking-wide text-white/90 font-semibold">'
        . e($libelle) . '</th>';

    // Classes d'onglets : directive PO du 01/09/2026, UN SEUL AUTEUR —
    // voir le docblock de `App\Pwa\Support\Onglets`.
    $classeOnglet = static fn (bool $actif): string => \App\Pwa\Support\Onglets::classes($actif);
@endphp

<div class="contents">

  @include('pwa.partials.barre-superieure')

  @if (session('pwa-succes'))
    <div class="fixed top-5 right-5 z-50 flex items-center gap-3 px-4 py-3 rounded-xl shadow-xl bg-emerald-600 text-white text-[13px] font-medium no-print"
         x-data="{ visible: true }" x-show="visible" x-init="setTimeout(() => visible = false, 5000)">
      <span>{{ session('pwa-succes') }}</span>
      <button type="button" @click="visible = false" class="ml-2 text-white/80 hover:text-white">✕</button>
    </div>
  @endif

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')

    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        {{-- EN-TÊTE — maître l.24-31 --}}
        <div class="mb-5 flex flex-wrap items-start justify-between gap-3">
          <div>
            <div class="flex items-center gap-2.5">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M3 2v7c0 1.1.9 2 2 2h1a2 2 0 002-2V2M7 2v20M17 2a5 5 0 00-5 5v6h5m0-11v20"/></svg>
              <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('carte_pwa.restauration.titre') }}</h1>
            </div>
            <p class="text-[15px] text-slate-500 mt-1.5">{{ __('carte_pwa.restauration.sous_titre') }}</p>
          </div>

          {{-- 03/09/2026 — DEUX BOUTONS S'AJOUTENT AU MAÎTRE, et c'est le
               livrable. `plats.menu_id` et `plats.recette_id` sont NOT NULL,
               et aucun écran de la PWA ne créait ni menu ni recette : sur une
               base neuve, « Nouveau plat » ouvrait un formulaire à deux
               sélecteurs vides dont rien ne permettait de sortir. Le maître
               n'a pas ces gestes parce que son prototype n'a pas de clés
               étrangères — son textarea « Ingrédients principaux » tient lieu
               de fiche technique (PA-23).

               Les trois boutons sont groupés dans un conteneur — sans lui, la
               barre `justify-between` de l'en-tête les écarterait aux deux
               bouts de l'écran. C'est ce conteneur que le comparateur voit :
               structure-ajout:m4-restauration.html#div-b458e26c --}}
          <div class="flex flex-wrap items-center gap-2">
            <button type="button" wire:click="ouvrirCreationMenu"
                    class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-white font-semibold" style="color:var(--navy)">{{ __('carte_pwa.restauration.bouton_nouveau_menu') }}</button>
            <button type="button" wire:click="ouvrirCreationRecette"
                    class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-white font-semibold" style="color:var(--navy)">{{ __('carte_pwa.restauration.bouton_nouvelle_fiche') }}</button>
            <button type="button" wire:click="ouvrirCreationPlat"
                    class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white hover:opacity-90 font-semibold">{{ __('carte_pwa.restauration.bouton_nouveau') }}</button>
          </div>
        </div>

        {{--
            ONGLETS — AJOUT AU MAÎTRE (04/09/2026).

            `m4-restauration.html` n'a AUCUN onglet : son corps entier est
            délégué au moteur CRUD générique, qui rend un tableau et rien
            d'autre. Les deux onglets ajoutés portent les deux référentiels que
            ce tableau EXIGE sans les offrir — `plats.recette_id` et
            `plats.menu_id` sont NOT NULL — et dont l'absence de composition
            bloquait la vente au comptoir : 83 plats, 83 recettes, TROIS lignes
            d'ingrédients en base.

            Le prototype n'a pas ces écrans parce qu'il n'a pas de clés
            étrangères : son textarea « Ingrédients principaux » tient lieu de
            fiche technique (PA-23), et sa « catégorie » de menu.

            ⚠ CETTE BARRE COÛTE UN ÉCART DE SQUELETTE, ET IL EST ASSUMÉ.
            `t-structure.js` apparie les blocs restants par classes communes :
            le maître n'ayant aucune barre d'onglets, sa barre d'outils
            (`flex flex-col gap-3 lg:flex-row lg:items-center`) se retrouve
            appariée à celle-ci sur le seul mot `flex`, et sort en SIGNATURE.
            Ce n'est pas un bloc EN TROP — un jeton `structure-ajout` n'y
            correspondrait donc jamais. La dette de la page est refigée de 11 à
            12 pour cette raison, et pour elle seule.

            Le container garde les classes de TOUTES les autres barres
            d'onglets de la PWA (`flex flex-wrap gap-1.5 mb-4`, neuf écrans) :
            le rendre transparent au comparateur en lui retirant ses classes de
            mise en page ferait rentrer le compte à 11 en écrivant du balisage
            pour plaire à une garde.
        --}}
        <div class="flex flex-wrap gap-1.5 mb-4">
          <button type="button" wire:click="$set('onglet', 'plats')" class="{{ $classeOnglet($onglet === 'plats') }}">{{ __('carte_pwa.restauration.onglet_plats') }}</button>
          <button type="button" wire:click="$set('onglet', 'fiches')" class="{{ $classeOnglet($onglet === 'fiches') }}">{{ __('carte_pwa.restauration.onglet_fiches') }}</button>
          <button type="button" wire:click="$set('onglet', 'menus')" class="{{ $classeOnglet($onglet === 'menus') }}">{{ __('carte_pwa.restauration.onglet_menus') }}</button>
        </div>

        {{--
            ⚠ LES TROIS PANNEAUX SONT CHAÎNÉS, ET UN SEUL EST RENDU — l'inverse
            de `pwa/carte/corps.blade.php`, qui les rend tous et masque les
            inactifs par `hidden`. Deux gardes commandent cette forme.

            1. G5 (`ColonnesDesTableauxPwaTest`) exige que toute entête rendue
               au premier GET existe dans un tableau du maître. Sur la carte,
               les DEUX onglets ont leurs colonnes au maître : les rendre tous
               les deux satisfait les deux sens de la garde. Ici,
               `m4-restauration.html` ne porte QUE les quatre colonnes du
               catalogue — « Fiche technique », « Coût matière », « Saison »
               n'existent dans aucun de ses tableaux. Les rendre en `hidden`
               les ferait compter comme colonnes INVENTÉES, sur l'écran même
               dont le client a validé le rendu.
            2. `t-structure.js` ne garde QUE LA PREMIÈRE BRANCHE d'un
               enchaînement conditionnel. Le catalogue est donc écrit en
               premier — c'est l'onglet nominal, celui que le Product Owner a
               sous les yeux à l'ouverture de la page — et les deux onglets
               ajoutés n'entrent pas dans la comparaison de squelette. Écrire
               les fiches d'abord montrerait au comparateur une page qui n'est
               jamais celle qu'on sert par défaut.
        --}}
        @if ($onglet === 'plats')

        {{-- INDICATEURS --}}
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5">
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('carte_pwa.restauration.kpi_total') }}</div>
            <div class="text-[17px] font-bold mt-1" style="color:var(--navy)">{{ $total }}</div>
          </div>
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('carte_pwa.restauration.kpi_avec_fiche') }}</div>
            <div class="text-[17px] font-bold mt-1 text-emerald-600">{{ $avecFiche }} / {{ $total }}</div>
          </div>
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('carte_pwa.restauration.kpi_sans_fiche') }}</div>
            <div class="text-[17px] font-bold mt-1 {{ $sansFiche > 0 ? 'text-amber-600' : 'text-emerald-600' }}">{{ $sansFiche }}</div>
          </div>
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('carte_pwa.restauration.kpi_retires') }}</div>
            <div class="text-[17px] font-bold mt-1 {{ $retires > 0 ? 'text-amber-600' : 'text-slate-400' }}">{{ $retires }}</div>
          </div>
        </div>

        {{-- FILTRES — maître, config `texteRecherche` et `filtres` --}}
        <div class="bg-white rounded-xl border border-slate-200 p-3.5 mb-4">
          <div class="flex flex-wrap gap-2.5 items-center">
            <div class="relative flex-1 min-w-[200px]">
              <input type="search" wire:model.live.debounce.300ms="recherche"
                     placeholder="{{ __('carte_pwa.restauration.recherche') }}"
                     class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2 focus:border-[var(--gold)] focus:outline-none">
            </div>

            <select wire:model.live="categorie" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <option value="">{{ __('carte_pwa.restauration.toutes_categories') }}</option>
              @foreach ($categories as $cle => $libelle)
                <option value="{{ $cle }}">{{ $libelle }}</option>
              @endforeach
            </select>
          </div>
        </div>

        {{-- TABLEAU --}}
        {{-- Le tableau est TOUJOURS rendu, entêtes comprises — même raison
             qu'en Facturation : des colonnes qu'on ne peut pas prouver sur une
             base vide ne sont pas des colonnes vérifiées, et l'état vide du
             moteur du maître (`crud-ui.js` `#crud-etat-vide`) occupe une ligne
             de corps. --}}
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]">
                  <tr>
                    {{-- La case de sélection du maître (`crud-ui.js` l.66-68,
                         `#crud-case-tout`). Voir le docblock de `selection`
                         dans le composant : ses consommateurs y sont nommés. --}}
                    <th class="px-3 py-2.5 w-10 no-print">
                      <input type="checkbox" wire:model.live="toutSelectionne" class="w-4 h-4 rounded"
                             aria-label="{{ __('carte_pwa.restauration.selection_tout') }}">
                    </th>
                    {!! $entete(__('carte_pwa.restauration.col_plat'), true) !!}
                    {!! $entete(__('carte_pwa.restauration.col_categorie')) !!}
                    {!! $entete(__('carte_pwa.restauration.col_prix')) !!}
                    {!! $entete(__('carte_pwa.restauration.col_disponible')) !!}
                    {{-- 02/09/2026 — « Fiche Technique » et « Coût Matière »
                         retirées (garde G5, aucun tableau du maître ne les
                         porte) : voir l'entête de ce fichier. --}}
                    <th class="px-3 py-2.5"></th>
                  </tr>
                </thead>
                <tbody>
                  @forelse ($lignes as $plat)
                    @php
                        $indisponibilite = $indisponibilites->get($plat->id);
                    @endphp
                    <tr wire:key="plat-{{ $plat->id }}"
                        class="border-t border-slate-100 hover:bg-slate-50 {{ $indisponibilite === null ? '' : 'opacity-55' }}">

                      <td class="px-3 py-2.5 no-print">
                        <input type="checkbox" value="{{ $plat->id }}" wire:model.live="selection" class="w-4 h-4 rounded"
                               aria-label="{{ __('carte_pwa.restauration.selection_ligne') }}">
                      </td>

                      <td class="px-3 py-2.5 text-left font-semibold text-slate-800">{{ $plat->libelle }}
                        @if ($plat->description !== null && $plat->description !== '')
                          <div class="text-[11px] font-normal text-slate-400 whitespace-pre-line">{{ $plat->description }}</div>
                        @endif
                      </td>

                      <td class="px-3 py-2.5 text-right text-slate-500 text-[12px]">{{ $categories[$plat->categorie] ?? $plat->categorie ?? MontantFcfa::TIRET }}</td>

                      <td class="px-3 py-2.5 text-right font-semibold" style="color:var(--gold)">{{ MontantFcfa::format((string) $plat->prix_vente) }}</td>

                      {{-- « Disponible » est RENDUE, et elle ne l'était pas : la
                           disponibilité vit dans `indisponibilites_carte` depuis
                           le 31/08/2026, pour les deux rayons. --}}
                      <td class="px-3 py-2.5 text-right">
                        @if ($indisponibilite === null)
                          <span class="text-[11px] px-1.5 py-0.5 rounded font-semibold" style="background:#E8F5E9;color:#2E7D32">{{ __('carte_pwa.restauration.disponible_oui') }}</span>
                        @else
                          <span class="text-[11px] px-1.5 py-0.5 rounded font-semibold" style="background:#FDECEC;color:#C62828"
                                title="{{ $indisponibilite->libelleMotif() }}">{{ __('carte_pwa.restauration.disponible_non') }}</span>
                        @endif
                      </td>

                      <td class="px-3 py-2.5 text-right whitespace-nowrap">
                        <button type="button" wire:click="ouvrirModificationPlat('{{ $plat->id }}')"
                                class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white">{{ __('carte_pwa.restauration.action_editer') }}</button>
                        <button type="button" wire:click="ouvrirRetraitDuPlat('{{ $plat->id }}')"
                                class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white ml-1">{{ __('carte_pwa.restauration.action_archiver') }}</button>
                      </td>
                    </tr>
                  @empty
                    <tr>
                      {{-- 02/09/2026 — colspan 8 → 6 : deux colonnes retirées
                           (garde G5, voir l'entête de ce fichier). --}}
                      <td colspan="6" class="p-10 text-center text-[13px] text-slate-400">
                        {{-- L'état vide du moteur du maître, toujours rendu ;
                             le message propre à l'écran s'y ajoute quand
                             aucun filtre n'est posé. --}}
                        <span class="font-semibold text-slate-500">{{ __('carte_pwa.restauration.vide_titre') }}</span><br>
                        {{ __('carte_pwa.restauration.vide_detail') }}
                        @if (trim($recherche) === '' && $categorie === '')
                          <br>{{ __('carte_pwa.restauration.vide') }}
                        @endif
                      </td>
                    </tr>
                  @endforelse
                </tbody>
              </table>
            </div>

            {{-- La pagination du maître (`crud-engine.js` `renderPagination`),
                 et le compteur de sélection quand elle existe. --}}
            <div class="flex items-center justify-between px-4 py-3 border-t border-slate-100 no-print">
              <p class="text-xs text-slate-500">
                {!! __('carte_pwa.restauration.affichage', [
                    'debut' => '<strong>' . ($lignes->total() === 0 ? 0 : $lignes->firstItem()) . '</strong>',
                    'fin' => '<strong>' . ($lignes->lastItem() ?? 0) . '</strong>',
                    'total' => '<strong>' . $lignes->total() . '</strong>',
                ]) !!}
                @if ($selection !== [])
                  <span class="ml-2 font-semibold" style="color:var(--navy)">{{ __('carte_pwa.restauration.selectionnes', ['nombre' => count($selection)]) }}</span>
                @endif
              </p>
              {{ $lignes->onEachSide(1)->links() }}
            </div>
          </div>

        {{-- ==================== ONGLET « FICHES TECHNIQUES » =============
             AJOUT AU MAÎTRE — le déblocage du point de vente restaurant
             (04/09/2026, constat du Product Owner). --}}
        @elseif ($onglet === 'fiches' && $fiches !== null)

          {{-- Le bandeau dit ce que l'écran attend, à l'endroit où on peut le
               faire : montrer un blocage sans offrir le geste est ce que la
               Directive interdit (Article 3.3). --}}
          <p class="text-[13px] text-slate-500 mb-4">{{ __('carte_pwa.restauration.fiches_bandeau') }}</p>

          <div class="grid grid-cols-1 lg:grid-cols-3 gap-3 mb-5">
            <div class="bg-white rounded-xl border border-slate-200 p-3.5">
              <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('carte_pwa.restauration.fiches_kpi_total') }}</div>
              <div class="text-[17px] font-bold mt-1" style="color:var(--navy)">{{ $fiches['total'] }}</div>
            </div>
            {{-- Décision du PO du 30/10/2026 (« le stock s'ajoute après ») : ce
                 compteur était ROUGE dès qu'il restait une fiche vide, parce
                 qu'une fiche vide était une vente refusée au comptoir. Le refus
                 est levé : un plat à fiche vide se vend, sans sortie de stock.
                 Le compteur reste un repère de saisie, en gris neutre. --}}
            <div class="bg-white rounded-xl border border-slate-200 p-3.5">
              <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('carte_pwa.restauration.fiches_kpi_vides') }}</div>
              <div class="text-[17px] font-bold mt-1 text-slate-600">{{ $fiches['vides'] }}</div>
            </div>
            <div class="bg-white rounded-xl border border-slate-200 p-3.5">
              <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('carte_pwa.restauration.fiches_kpi_provisoires') }}</div>
              <div class="text-[17px] font-bold mt-1 {{ $fiches['provisoires'] > 0 ? 'text-amber-600' : 'text-emerald-600' }}">{{ $fiches['provisoires'] }}</div>
              <div class="text-[11px] text-slate-400 mt-0.5">{{ __('carte_pwa.restauration.fiches_kpi_provisoires_detail') }}</div>
            </div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-3.5 mb-4">
            <div class="flex flex-wrap gap-2.5 items-center">
              <div class="relative flex-1 min-w-[200px]">
                <input type="search" wire:model.live.debounce.300ms="rechercheFiche"
                       placeholder="{{ __('carte_pwa.restauration.fiches_recherche') }}"
                       class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2 focus:border-[var(--gold)] focus:outline-none">
              </div>

              <label class="flex items-center gap-2 cursor-pointer">
                <input type="checkbox" wire:model.live="videsSeulement" class="w-4 h-4 rounded border-slate-300">
                <span class="text-[13px] font-semibold text-slate-700">{{ __('carte_pwa.restauration.fiches_filtre_vides') }}</span>
                <span class="text-[11px] text-slate-400">{{ __('carte_pwa.restauration.fiches_filtre_vides_aide') }}</span>
              </label>
            </div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]">
                  <tr>
                    {!! $entete(__('carte_pwa.restauration.fiches_col_fiche'), true) !!}
                    {!! $entete(__('carte_pwa.restauration.fiches_col_plat'), true) !!}
                    {!! $entete(__('carte_pwa.restauration.fiches_col_ingredients')) !!}
                    {!! $entete(__('carte_pwa.restauration.fiches_col_cout')) !!}
                    {!! $entete(__('carte_pwa.restauration.fiches_col_etat')) !!}
                    <th class="px-3 py-2.5"></th>
                  </tr>
                </thead>
                <tbody>
                  @forelse ($fiches['page'] as $fiche)
                    @php
                        $cout = $fiches['couts'][(string) $fiche->id] ?? null;
                        $vide = $fiche->ingredients_count === 0;
                    @endphp
                    <tr wire:key="fiche-{{ $fiche->id }}" class="border-t border-slate-100 hover:bg-slate-50">
                      <td class="px-3 py-2.5 text-left font-semibold text-slate-800">{{ $fiche->libelle }}</td>

                      {{-- Le plat NOMMÉ : « Recette à écrire » ne dit rien,
                           « Recette à écrire — Salade nue » dit quelle vente
                           est bloquée. --}}
                      <td class="px-3 py-2.5 text-left text-slate-500 text-[12px]">
                        {{ $fiche->plats->pluck('libelle')->implode(', ') ?: __('carte_pwa.restauration.fiches_sans_plat') }}
                      </td>

                      <td class="px-3 py-2.5 text-right font-semibold {{ $vide ? 'text-red-600' : 'text-slate-700' }}">{{ $fiche->ingredients_count }}</td>

                      {{-- LE COÛT MATIÈRE ET SES TROIS ÉTATS — jamais « 0 F ».
                           Il vient de `CompositionRecetteService`, unique
                           auteur de la formule ; l'écran ne recalcule rien. --}}
                      <td class="px-3 py-2.5 text-right">
                        @if ($cout === null || $cout->compositionVide)
                          <span class="text-[12px] text-slate-400" title="{{ __('carte_pwa.restauration.fiches_cout_vide_infobulle') }}">{{ __('carte_pwa.restauration.fiches_cout_vide') }}</span>
                        @elseif ($cout->incomplet)
                          <span class="text-[12px] text-amber-600 font-semibold"
                                title="{{ __('carte_pwa.restauration.fiches_cout_incomplet_infobulle', ['articles' => implode(', ', $cout->articlesSansCout)]) }}">{{ __('carte_pwa.restauration.fiches_cout_incomplet') }}</span>
                        @else
                          <span class="font-semibold" style="color:var(--gold)">{{ MontantFcfa::format((string) $cout->montant) }}</span>
                        @endif
                      </td>

                      <td class="px-3 py-2.5 text-right whitespace-nowrap">
                        @if ($vide)
                          <span class="text-[11px] px-1.5 py-0.5 rounded font-semibold" style="background:#F1F5F9;color:#475569"
                                title="{{ __('carte_pwa.restauration.fiches_etat_vide_infobulle') }}">{{ __('carte_pwa.restauration.fiches_etat_vide') }}</span>
                        @elseif (! $fiche->decrementeUnStockSuivi())
                          {{-- LE TROISIEME ETAT (04/09/2026) : la fiche est
                               composee et ne decremente RIEN, parce que tous
                               ses ingredients sont suivis au jour le jour
                               (laitue, tomate, oignon...). C'est la verite
                               d'une salade verte, et la vente passe — mais
                               rendu « Composee », cela se lirait comme une
                               fiche qui decremente. --}}
                          <span class="text-[11px] px-1.5 py-0.5 rounded font-semibold" style="background:#E8EEFD;color:#1D4ED8"
                                title="{{ __('carte_pwa.restauration.fiches_etat_sans_suivi_infobulle') }}">{{ __('carte_pwa.restauration.fiches_etat_sans_suivi') }}</span>
                        @else
                          <span class="text-[11px] px-1.5 py-0.5 rounded font-semibold" style="background:#E8F5E9;color:#2E7D32">{{ __('carte_pwa.restauration.fiches_etat_composee') }}</span>
                        @endif

                        {{-- La marque « composition provisoire » (04/09/2026) :
                             les quantités ont été POSÉES pour débloquer le
                             service, jamais pesées. Elle s'affiche À CÔTÉ de
                             l'état, pas à sa place — une fiche provisoire est
                             bel et bien composée, elle décrémente simplement
                             une quantité que personne n'a mesurée. --}}
                        @if ($fiche->composition_provisoire)
                          <span class="text-[11px] px-1.5 py-0.5 rounded font-semibold ml-1" style="background:#FDF3E0;color:#B8891E"
                                title="{{ __('carte_pwa.restauration.fiches_etat_provisoire_infobulle') }}">{{ __('carte_pwa.restauration.fiches_etat_provisoire') }}</span>
                        @endif
                      </td>

                      <td class="px-3 py-2.5 text-right whitespace-nowrap">
                        <button type="button" wire:click="ouvrirModificationRecette('{{ $fiche->id }}')"
                                class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white">{{ __('carte_pwa.restauration.fiches_action_composer') }}</button>
                      </td>
                    </tr>
                  @empty
                    <tr>
                      <td colspan="6" class="p-10 text-center text-[13px] text-slate-400">
                        <span class="font-semibold text-slate-500">{{ __('carte_pwa.restauration.vide_titre') }}</span><br>
                        {{ __('carte_pwa.restauration.vide_detail') }}
                        <br>{{ __('carte_pwa.restauration.fiches_aucune') }}
                      </td>
                    </tr>
                  @endforelse
                </tbody>
              </table>
            </div>

            <div class="flex items-center justify-between px-4 py-3 border-t border-slate-100 no-print">
              <p class="text-xs text-slate-500">
                {!! __('carte_pwa.restauration.affichage', [
                    'debut' => '<strong>' . ($fiches['page']->total() === 0 ? 0 : $fiches['page']->firstItem()) . '</strong>',
                    'fin' => '<strong>' . ($fiches['page']->lastItem() ?? 0) . '</strong>',
                    'total' => '<strong>' . $fiches['page']->total() . '</strong>',
                ]) !!}
              </p>
              {{ $fiches['page']->onEachSide(1)->links() }}
            </div>
          </div>


        {{-- ==================== ONGLET « MENUS » =========================
             AJOUT AU MAÎTRE. `plats.menu_id` est NOT NULL et `menus` n'avait
             qu'une écriture — la création : une saison mal saisie était
             définitive, et la table n'a aucune colonne d'archivage. --}}
        @elseif ($onglet === 'menus' && $menusListe !== null)

          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]">
                  <tr>
                    {!! $entete(__('carte_pwa.restauration.menus_col_menu'), true) !!}
                    {!! $entete(__('carte_pwa.restauration.menus_col_type')) !!}
                    {!! $entete(__('carte_pwa.restauration.menus_col_saison')) !!}
                    {!! $entete(__('carte_pwa.restauration.menus_col_plats')) !!}
                    <th class="px-3 py-2.5"></th>
                  </tr>
                </thead>
                <tbody>
                  @forelse ($menusListe as $carte)
                    <tr wire:key="menu-{{ $carte->id }}" class="border-t border-slate-100 hover:bg-slate-50">
                      <td class="px-3 py-2.5 text-left font-semibold text-slate-800">{{ $carte->libelle }}</td>
                      <td class="px-3 py-2.5 text-right text-slate-500 text-[12px]">{{ $typesMenu[$carte->type] ?? $carte->type }}</td>
                      {{-- Les dates ENCADRENT la saison : un menu permanent
                           n'en a pas, et un tiret se lirait comme une donnée
                           manquante. --}}
                      <td class="px-3 py-2.5 text-right text-slate-500 text-[12px]">
                        @if ($carte->date_debut === null && $carte->date_fin === null)
                          {{ __('carte_pwa.restauration.menus_saison_permanente') }}
                        @else
                          {{ $carte->date_debut?->format('d/m/Y') ?? MontantFcfa::TIRET }} → {{ $carte->date_fin?->format('d/m/Y') ?? MontantFcfa::TIRET }}
                        @endif
                      </td>
                      <td class="px-3 py-2.5 text-right font-semibold text-slate-700">{{ $carte->plats_count }}</td>
                      <td class="px-3 py-2.5 text-right whitespace-nowrap">
                        <button type="button" wire:click="ouvrirModificationMenu('{{ $carte->id }}')"
                                class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white">{{ __('carte_pwa.restauration.menus_action_editer') }}</button>
                      </td>
                    </tr>
                  @empty
                    <tr>
                      <td colspan="5" class="p-10 text-center text-[13px] text-slate-400">
                        <span class="font-semibold text-slate-500">{{ __('carte_pwa.restauration.vide_titre') }}</span><br>
                        {{ __('carte_pwa.restauration.menus_aucun') }}
                      </td>
                    </tr>
                  @endforelse
                </tbody>
              </table>
            </div>
          </div>

        @endif

      </div>
    </main>
  </div>

  {{-- ==================== FORMULAIRE DE PLAT ============================ --}}
  @if ($etatFormulaire === 'plat')
    <x-pwa.modale :titre="$platCibleId === null ? __('carte_pwa.restauration.form_titre_creation') : __('carte_pwa.restauration.form_titre_modification')"
                  largeur="560px"
                  fermer="$set('etatFormulaire', null)">

      <div>
        <label for="plat-nom" class="block text-[13px] font-semibold text-slate-700 mb-1.5">
          {{ __('carte_pwa.restauration.label_nom') }} <span class="text-red-500">*</span>
        </label>
        <input id="plat-nom" type="text" wire:model="libelleSaisi" required
               placeholder="{{ __('carte_pwa.restauration.invite_nom') }}"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
        @error('libelleSaisi')<p class="text-[11px] text-red-600 mt-1">{{ $message }}</p>@enderror
      </div>

      {{-- 30/10/2026 (décision du PO) : description FACULTATIVE, 500 caractères. --}}
      <div>
        <label for="plat-description" class="block text-[13px] font-semibold text-slate-700 mb-1.5">
          {{ __('carte_pwa.restauration.label_description') }}
        </label>
        <textarea id="plat-description" wire:model="descriptionSaisie" rows="3" maxlength="500"
                  class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5"></textarea>
        @error('descriptionSaisie')<p class="text-[11px] text-red-600 mt-1">{{ $message }}</p>@enderror
      </div>

      <div>
        <label for="plat-categorie" class="block text-[13px] font-semibold text-slate-700 mb-1.5">
          {{ __('carte_pwa.restauration.label_categorie') }} <span class="text-red-500">*</span>
        </label>
        <select id="plat-categorie" wire:model="categorieSaisie" required
                class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @foreach ($categories as $cle => $libelle)
            <option value="{{ $cle }}">{{ $libelle }}</option>
          @endforeach
        </select>
        @error('categorieSaisie')<p class="text-[11px] text-red-600 mt-1">{{ $message }}</p>@enderror
      </div>

      <div>
        <label for="plat-prix" class="block text-[13px] font-semibold text-slate-700 mb-1.5">
          {{ __('carte_pwa.restauration.label_prix') }} <span class="text-red-500">*</span>
        </label>
        <input id="plat-prix" type="number" min="0" step="any" required wire:model="prixVenteSaisi"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
        @error('prixVenteSaisi')<p class="text-[11px] text-red-600 mt-1">{{ $message }}</p>@enderror

        {{--
            PA-161 (b) — la marque « prix provisoire ».

            Seule la marque PROVISOIRE se coche : c'est une décision. « Corrigé
            à la main » est un FAIT, et il se déduit — changer au clavier le
            prix d'un plat marqué provisoire EST la correction manuelle
            (`App\Domain\Carte\MarquesDePrix`). Le faire cocher en plus
            reviendrait à demander de déclarer ce qu'on vient de faire, et on
            l'oublierait.
        --}}
        <label class="flex items-start gap-2 mt-2.5 cursor-pointer">
          <input id="plat-provisoire" type="checkbox" wire:model="prixProvisoireSaisi"
                 class="mt-0.5 h-3.5 w-3.5 rounded border-slate-300">
          <span class="text-[12px] text-slate-600">
            <strong class="text-red-600">{{ __('carte_pwa.restauration.label_prix_provisoire') }}</strong>
            <span class="block text-[11px] text-slate-400">{{ __('carte_pwa.restauration.aide_prix_provisoire') }}</span>
          </span>
        </label>
        @error('prixProvisoireSaisi')<p class="text-[11px] text-red-600 mt-1">{{ $message }}</p>@enderror

        @if ($platCorrigeMain)
          {{-- État DÉRIVÉ, en lecture seule : le plat porte déjà la marque, et
               la carte est donc instable. Elle se lève depuis l'API, pas
               d'ici — la lever d'un clic sur le même écran qui la pose
               annulerait un fait au lieu de le corriger. --}}
          <p class="text-[11px] text-amber-600 mt-1.5">{{ __('carte_pwa.restauration.etat_prix_corrige_main') }}</p>
        @endif
      </div>

      {{-- `plats.menu_id` est NOT NULL : c'est une vraie clé étrangère, jamais
           un menu fabriqué à la volée depuis la catégorie. --}}
      <div>
        <label for="plat-menu" class="block text-[13px] font-semibold text-slate-700 mb-1.5">
          {{ __('carte_pwa.restauration.label_menu') }} <span class="text-red-500">*</span>
        </label>
        <select id="plat-menu" wire:model="menuIdSaisi" required
                class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          <option value="">{{ __('carte_pwa.restauration.invite_menu') }}</option>
          @foreach ($menus as $menu)
            <option value="{{ $menu->id }}">{{ $menu->libelle }}</option>
          @endforeach
        </select>

        {{-- LA SORTIE D'IMPASSE (03/09/2026). Un sélecteur vide ne dit ni ce
             qui manque ni où aller : le manque est NOMMÉ, et le bouton qui le
             lève est à côté du champ qui l'exige. Le bouton est rendu dans les
             deux cas — sinon il faudrait fermer le formulaire pour créer un
             second menu, et retaper le plat.
             AJOUT AU MAITRE, hors du perimetre compare : le comparateur
             de structure ne descend pas dans les modales, et un jeton
             a nom invente n'y correspondrait jamais. --}}
        @if ($menus->isEmpty())
          <p class="text-[11px] text-amber-700 mt-1">{{ __('carte_pwa.restauration.aucun_menu') }}</p>
        @endif
        <button type="button" wire:click="ouvrirCreationMenu"
                class="text-[11px] px-2 py-0.5 mt-1 rounded border border-slate-300 hover:bg-slate-50">{{ __('carte_pwa.restauration.bouton_creer_menu') }}</button>

        @error('menuIdSaisi')<p class="text-[11px] text-red-600 mt-1">{{ $message }}</p>@enderror
      </div>

      {{-- `plats.recette_id` est NOT NULL aussi : « Aucune fiche technique »
           faisait échouer l'insertion sur la contrainte. --}}
      <div>
        <label for="plat-recette" class="block text-[13px] font-semibold text-slate-700 mb-1.5">
          {{ __('carte_pwa.restauration.label_fiche') }} <span class="text-red-500">*</span>
        </label>
        <select id="plat-recette" wire:model="recetteIdSaisie" required
                class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          <option value="">{{ __('carte_pwa.restauration.invite_fiche') }}</option>
          @foreach ($recettes as $recette)
            <option value="{{ $recette->id }}">{{ $recette->libelle }}</option>
          @endforeach
        </select>
        <p class="text-[11px] text-slate-400 mt-1">{{ __('carte_pwa.restauration.aide_fiche') }}</p>

        {{-- Même sortie d'impasse que le menu, et pour la même raison :
             `plats.recette_id` est NOT NULL.
             AJOUT AU MAITRE, meme portee que le bouton du champ Menu. --}}
        @if ($recettes->isEmpty())
          <p class="text-[11px] text-amber-700 mt-1">{{ __('carte_pwa.restauration.aucune_fiche') }}</p>
        @endif
        <button type="button" wire:click="ouvrirCreationRecette"
                class="text-[11px] px-2 py-0.5 mt-1 rounded border border-slate-300 hover:bg-slate-50">{{ __('carte_pwa.restauration.bouton_creer_fiche') }}</button>

        @error('recetteIdSaisie')<p class="text-[11px] text-red-600 mt-1">{{ $message }}</p>@enderror
      </div>

      <x-slot:pied>
        <button type="button" wire:click="$set('etatFormulaire', null)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerPlat" wire:loading.attr="disabled"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('carte_pwa.restauration.bouton_enregistrer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ==================== NOUVEAU MENU (EF-M4-01) ======================= --}}
  {{-- AJOUT AU MAITRE : son prototype n'a ni menu ni recette — sa carte
       tient dans un tableau et un textarea. --}}
  @if ($etatFormulaire === 'menu')
    <x-pwa.modale :titre="$menuCibleId === null ? __('carte_pwa.restauration.menu_form_titre') : __('carte_pwa.restauration.menu_form_titre_modification')"
                  :sousTitre="__('carte_pwa.restauration.menu_form_sous_titre')"
                  largeur="560px"
                  fermer="fermerFormulaireSecondaire">

      <div>
        <label for="menu-nom" class="block text-[13px] font-semibold text-slate-700 mb-1.5">
          {{ __('carte_pwa.restauration.menu_label_libelle') }} <span class="text-red-500">*</span>
        </label>
        <input id="menu-nom" type="text" wire:model="menuLibelleSaisi" required
               placeholder="{{ __('carte_pwa.restauration.menu_invite_libelle') }}"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
        @error('menuLibelleSaisi')<p class="text-[11px] text-red-600 mt-1">{{ $message }}</p>@enderror
      </div>

      <div>
        <label for="menu-type" class="block text-[13px] font-semibold text-slate-700 mb-1.5">
          {{ __('carte_pwa.restauration.menu_label_type') }} <span class="text-red-500">*</span>
        </label>
        <select id="menu-type" wire:model="menuTypeSaisi" required
                class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @foreach ($typesMenu as $cle => $libelle)
            <option value="{{ $cle }}">{{ $libelle }}</option>
          @endforeach
        </select>
        @error('menuTypeSaisi')<p class="text-[11px] text-red-600 mt-1">{{ $message }}</p>@enderror
      </div>

      {{-- Les dates ENCADRENT la saison, elles ne la déclarent pas : nullables
           au schéma, un menu permanent n'en a pas. --}}
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div>
          <label for="menu-debut" class="block text-[13px] font-semibold text-slate-700 mb-1.5">
            {{ __('carte_pwa.restauration.menu_label_date_debut') }}
          </label>
          <input id="menu-debut" type="date" wire:model="menuDateDebutSaisie"
                 class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('menuDateDebutSaisie')<p class="text-[11px] text-red-600 mt-1">{{ $message }}</p>@enderror
        </div>
        <div>
          <label for="menu-fin" class="block text-[13px] font-semibold text-slate-700 mb-1.5">
            {{ __('carte_pwa.restauration.menu_label_date_fin') }}
          </label>
          <input id="menu-fin" type="date" wire:model="menuDateFinSaisie"
                 class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('menuDateFinSaisie')<p class="text-[11px] text-red-600 mt-1">{{ $message }}</p>@enderror
        </div>
      </div>
      <p class="text-[11px] text-slate-400">{{ __('carte_pwa.restauration.menu_aide_dates') }}</p>

      <x-slot:pied>
        <button type="button" wire:click="fermerFormulaireSecondaire"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerMenu" wire:loading.attr="disabled"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('carte_pwa.restauration.bouton_enregistrer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ============== NOUVELLE FICHE TECHNIQUE (EF-M4-02, PA-23) ========== --}}
  {{-- AJOUT AU MAITRE : le sous-formulaire que PA-23 reclame a la place
       du textarea « Ingredients principaux ». --}}
  @if ($etatFormulaire === 'recette')
    <x-pwa.modale :titre="$recetteCibleId === null ? __('carte_pwa.restauration.recette_form_titre') : __('carte_pwa.restauration.recette_form_titre_modification')"
                  :sousTitre="$recetteCibleId === null ? __('carte_pwa.restauration.recette_form_sous_titre') : __('carte_pwa.restauration.recette_form_sous_titre_modification')"
                  largeur="680px"
                  fermer="fermerFormulaireSecondaire">

      {{-- La marque « composition provisoire » sur la fiche OUVERTE : elle dit
           pourquoi ces quantités sont là et ce qu'il faut en faire. Elle tombe
           d'elle-même à l'enregistrement (`CompositionRecetteService`), sans
           case à décocher — c'est un fait, pas une décision (PA-161 b). --}}
      @if ($ficheCibleProvisoire)
        <p class="text-[12px] text-amber-700 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2">{{ __('carte_pwa.restauration.recette_bandeau_provisoire') }}</p>
      @endif

      <div>
        <label for="recette-nom" class="block text-[13px] font-semibold text-slate-700 mb-1.5">
          {{ __('carte_pwa.restauration.recette_label_libelle') }} <span class="text-red-500">*</span>
        </label>
        <input id="recette-nom" type="text" wire:model="recetteLibelleSaisi" required
               placeholder="{{ __('carte_pwa.restauration.recette_invite_libelle') }}"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
        @error('recetteLibelleSaisi')<p class="text-[11px] text-red-600 mt-1">{{ $message }}</p>@enderror
      </div>

      {{--
          LE COÛT MATIÈRE ENREGISTRÉ — EN LECTURE SEULE, ET DANS SES TROIS
          ÉTATS.

          Ce n'est PAS un champ, et il ne suit PAS la frappe : il dit ce que la
          composition valait à l'ouverture, et se recalcule à l'enregistrement.
          Un chiffre qui bougerait au clavier serait un champ déguisé — le
          premier des anti-patterns du prototype (« Net à payer » saisi).
      --}}
      @if ($coutFicheCible !== null)
        <div class="rounded-lg border border-slate-200 bg-slate-50 px-3 py-2.5">
          <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('carte_pwa.restauration.recette_cout_actuel') }}</div>
          @if ($coutFicheCible->compositionVide)
            <div class="text-[15px] font-bold mt-0.5 text-slate-400">{{ __('carte_pwa.restauration.fiches_cout_vide') }}</div>
          @elseif ($coutFicheCible->incomplet)
            <div class="text-[15px] font-bold mt-0.5 text-amber-600">{{ __('carte_pwa.restauration.fiches_cout_incomplet') }}</div>
            <div class="text-[11px] text-amber-700 mt-0.5">{{ __('carte_pwa.restauration.fiches_cout_incomplet_infobulle', ['articles' => implode(', ', $coutFicheCible->articlesSansCout)]) }}</div>
          @else
            <div class="text-[15px] font-bold mt-0.5" style="color:var(--gold)">{{ MontantFcfa::format((string) $coutFicheCible->montant) }}</div>
          @endif
          <p class="text-[11px] text-slate-400 mt-0.5">{{ __('carte_pwa.restauration.recette_cout_actuel_aide') }}</p>
        </div>
      @endif

      {{--
          LA COMPOSITION — le sous-formulaire que PA-23 réclame.

          Des LIGNES, pas un tableau : le maître ne porte ici qu'un textarea
          « Ingrédients principaux », et inventer un `<thead>` ferait entrer des
          colonnes que personne n'a décidées (garde G5, même raison que le
          retrait de « Fiche Technique » du tableau principal le 02/09/2026).

          ⚠ AUCUN champ de coût. Le coût matière se CALCULE depuis ces lignes et
          le coût moyen pondéré de chaque article (M6) ; il est annoncé après
          l'enregistrement, dans ses trois états.
      --}}
      <div>
        <div class="flex items-center justify-between mb-1.5">
          <span class="text-[13px] font-semibold text-slate-700">{{ __('carte_pwa.restauration.recette_composition_titre') }}</span>
          <button type="button" wire:click="ajouterIngredient"
                  class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-slate-50">{{ __('carte_pwa.restauration.recette_bouton_ajouter_ingredient') }}</button>
        </div>

        <p class="text-[11px] text-slate-400 mb-2">{{ __('carte_pwa.restauration.recette_composition_aide') }}</p>

        <input type="search" wire:model.live.debounce.300ms="rechercheArticleIngredient"
               placeholder="{{ __('carte_pwa.restauration.recette_recherche_article') }}"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 mb-2 focus:border-[var(--gold)] focus:outline-none">

        @if ($articlesIngredient->isEmpty())
          {{-- Une liste vide se DIT : un `<select>` sans option laisserait
               croire à un écran cassé plutôt qu'à une recherche trop étroite. --}}
          <p class="text-[11px] text-amber-700 mb-2">{{ __('carte_pwa.restauration.recette_aucun_article') }}</p>
        @endif

        @forelse ($ingredientsSaisis as $index => $ingredient)
          <div wire:key="ingredient-{{ $index }}" class="flex flex-wrap items-end gap-2 mb-2">
            <div class="flex-1 min-w-[200px]">
              <label for="ingredient-article-{{ $index }}" class="block text-[11px] text-slate-500 mb-1">
                {{ __('carte_pwa.restauration.recette_label_article') }}
              </label>
              <select id="ingredient-article-{{ $index }}" wire:model="ingredientsSaisis.{{ $index }}.article_id"
                      class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
                <option value="">{{ __('carte_pwa.restauration.recette_invite_article') }}</option>
                @foreach ($articlesIngredient as $article)
                  <option value="{{ $article->id }}">{{ $article->libelle }} — {{ $article->unite_mesure }}</option>
                @endforeach
              </select>
              @error('ingredientsSaisis.'.$index.'.article_id')<p class="text-[11px] text-red-600 mt-1">{{ $message }}</p>@enderror
            </div>

            <div class="w-[150px]">
              <label for="ingredient-quantite-{{ $index }}" class="block text-[11px] text-slate-500 mb-1">
                {{ __('carte_pwa.restauration.recette_label_quantite') }}
              </label>
              <input id="ingredient-quantite-{{ $index }}" type="number" min="0" step="any"
                     wire:model="ingredientsSaisis.{{ $index }}.quantite_unitaire"
                     class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
              @error('ingredientsSaisis.'.$index.'.quantite_unitaire')<p class="text-[11px] text-red-600 mt-1">{{ $message }}</p>@enderror
            </div>

            <button type="button" wire:click="retirerIngredient({{ $index }})"
                    class="text-[11px] px-2 py-2 rounded border border-slate-300 hover:bg-slate-50">{{ __('carte_pwa.restauration.recette_bouton_retirer_ingredient') }}</button>
          </div>
        @empty
          <p class="text-[11px] text-amber-700">{{ __('carte_pwa.restauration.recette_sans_ingredient') }}</p>
        @endforelse
      </div>

      <x-slot:pied>
        <button type="button" wire:click="fermerFormulaireSecondaire"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerRecette" wire:loading.attr="disabled"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('carte_pwa.restauration.bouton_enregistrer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ==================== RETRAIT DE LA CARTE =========================== --}}
  @if ($etatFormulaire === 'archivage' && $platCible !== null)
    <x-pwa.modale-archivage action="confirmerRetraitDuPlat"
                            :titre="__('carte_pwa.restauration.archiver_titre', ['plat' => $platCible->libelle])"
                            :message="__('carte_pwa.restauration.archiver_message')"
                            :element="$platCible->libelle"
                            :messagesVerrou="$verrous"
                            :bloque="$verrous !== []"
                            :libelleConfirmer="__('carte_pwa.restauration.archiver_confirmer')"
                            fermer="$set('etatFormulaire', null)" />
  @endif

  @include('pwa.partials.acces-rapide')
</div>

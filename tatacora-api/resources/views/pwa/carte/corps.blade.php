{{--
    LE CORPS DE L'ÉCRAN DE CARTE — un seul, pour le bar et le restaurant.

    Maîtres : prototype_v2/pages/m5-bar-carte.html,
    prototype_v2/pages/m4-restaurant-carte.html, et le fichier qui rend le
    corps des deux, prototype_v2/pages/carte-module.js.

    ## Pourquoi ce fichier existe

    Le maître n'a qu'UN fichier pour les deux écrans et écrit sa raison l.7 :
    « Deux écrans jumeaux finiraient par diverger au premier ajustement ». Les
    deux vues de la PWA avaient déjà divergé — la carte du bar affichait le
    sous-titre du restaurant, et aucune des deux n'avait la ligne TOTAL de
    l'onglet Couverture. Le défaut de `/pwa/stocks` (HTTP 500) est né
    exactement d'un copier-coller de vue.

    Ce qui change entre les deux tient dans `$page` : titre, sous-titre,
    icône, refus, et le seul geste qui n'existe pas des deux côtés
    (« Délier », impossible au bar — `cartes_boisson.article_id` est NOT NULL).

    ## La casse des entêtes est celle du MAÎTRE

    `Article`, pas `ARTICLE`. Le maître pose `Article` et laisse la classe
    `uppercase` faire le rendu — une règle CSS, qui ne s'applique ni au CSV ni
    au PDF. Une majuscule écrite en dur ressort telle quelle sur le document
    remis au comptable. La colonne d'actions n'a PAS d'entête : le maître
    termine son tableau par une chaîne vide (`carte-module.js` l.127).

    ⚠ ESPACEMENTS = échelle nommée de Tailwind (`py-2.5` fait 10 px) ;
    TAILLES DE POLICE = valeurs entre crochets (PA-145). Gris `slate`, jamais
    `neutral`.
--}}
@php
    use App\Pwa\Support\MontantFcfa;

    // Classes d'onglets : directive PO du 01/09/2026, UN SEUL AUTEUR —
    // voir le docblock de `App\Pwa\Support\Onglets`.
    $classeOnglet = static fn (bool $actif): string => \App\Pwa\Support\Onglets::classes($actif);

    // `uppercase` est laissé à la feuille de style, comme au maître.
    $entete = static fn (string $libelle, bool $gauche = false): string => '<th class="px-3 py-2.5 '
        . ($gauche ? 'text-left' : 'text-right')
        . ' text-[11px] uppercase tracking-wide text-white/90 font-semibold">'
        . e($libelle) . '</th>';

    $k = $indicateurs;
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

  @if (session('pwa-avertissement'))
    <div class="fixed top-20 right-5 z-50 flex items-center gap-3 px-4 py-3 rounded-xl shadow-xl bg-amber-600 text-white text-[13px] font-medium no-print"
         x-data="{ visible: true }" x-show="visible" x-init="setTimeout(() => visible = false, 8000)">
      <span>{{ session('pwa-avertissement') }}</span>
      <button type="button" @click="visible = false" class="ml-2 text-white/80 hover:text-white">✕</button>
    </div>
  @endif

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')

    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        {{-- EN-TÊTE — maître l.26-49 --}}
        <div class="mb-5 flex flex-wrap items-start justify-between gap-3">
          <div>
            <div class="flex items-center gap-2.5">
              {!! $page['icone'] !!}
              <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ $page['titre'] }}</h1>
            </div>
            <p class="text-[15px] text-slate-500 mt-1.5">{!! $page['sous_titre'] !!}</p>
          </div>

          <div class="flex flex-wrap gap-2">
            <a href="{{ route('pwa.pos.comptant') }}" wire:navigate
               class="text-[13px] px-3.5 py-2 rounded-lg border border-slate-300 bg-white hover:bg-slate-50">{{ __('carte_pwa.commun.lien_pos') }}</a>
            <a href="{{ route('pwa.stocks.liste') }}" wire:navigate
               class="text-[13px] px-3.5 py-2 rounded-lg border border-slate-300 bg-white hover:bg-slate-50">{{ __('carte_pwa.commun.lien_stocks') }}</a>

            {{-- ⚠ DÉROGATION PO du 01/09/2026, rappelée le 02/09/2026 — la
                 paire de boutons du maître (« Excel » l.38 / « PDF » l.39,
                 `m5-bar-carte.html` et `m4-restaurant-carte.html` l.37-38)
                 est FUSIONNÉE en UN bouton « Exporter » : les deux ouvraient
                 déjà la même modale de format, et deux entrées pour un seul
                 formulaire laissaient croire à deux documents. Le format
                 PDF/Excel se choisit DANS la modale. Registre :
                 `App\Pwa\Support\DerogationsMaquette` (export_bouton_unique).
                 Jetons : maitre-refuse:m5-bar-carte.html#page
                         maitre-refuse:m4-restaurant-carte.html#page --}}
            <button type="button" wire:click="$set('etatFormulaire', 'export')"
                    class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white hover:opacity-90 font-semibold">{{ __('pwa.export.bouton') }}</button>

            {{-- maître l.48 : la FICHE DES PRIX est un document qui se lit,
                 groupé par catégorie — le bouton PDF voisin exporte le tableau
                 de gestion, qui se consulte. Elle s'imprime DIRECTEMENT, sans
                 passer par la modale de format. --}}
            <button type="button" wire:click="imprimerFichePrix" wire:loading.attr="disabled"
                    class="text-[13px] px-4 py-2 rounded-lg border border-[var(--gold)] text-[var(--gold)] hover:bg-amber-50 font-semibold">{{ __('carte_pwa.commun.bouton_fiche_prix') }}</button>
            {{-- « Nouvelle boisson » — AJOUT FONCTIONNEL (PO 03/09/2026) : le
                 geste manquait ENTIEREMENT a la PWA du bar (creer une boisson
                 exigeait l'API ou un import CSV), alors que le restaurant a
                 son ecran de creation de plat. Propre au bar : le restaurant
                 cree ses plats sur « Plats & menus », avec son menu et sa
                 fiche technique obligatoires.
                 structure-ajout:m5-bar-carte.html#bouton-nouvelle-boisson --}}
            @if ($page['creation_boisson'] ?? false)
              <button type="button" wire:click="ouvrirCreationBoisson"
                      class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('carte_pwa.commun.bouton_nouvelle_boisson') }}</button>
            @endif

            {{-- L'ACCES A L'ECRAN DU CATALOGUE — AJOUT (PO 04/09/2026), et il
                 ferme un ecran ORPHELIN.

                 `/pwa/restaurant/plats` porte « Nouveau plat », les fiches
                 techniques et les menus, et il n'etait relie a RIEN : l'entree
                 de menu « Restaurant » pointe sur `pwa.restaurant.carte` (le
                 maitre n'a qu'une entree par rayon), et aucune vue ne renvoyait
                 vers lui. Seule la recherche globale y menait. Un ecran livre
                 qu'aucun clic n'atteint est le symetrique de l'entree de menu
                 inerte que l'Article 3.3 interdit — et c'est ce qui a fait
                 croire que le geste de composition n'existait pas.

                 Un lien, pas un bouton d'action : c'est une NAVIGATION, et le
                 rendre en `wire:click` ferait perdre l'ouverture dans un nouvel
                 onglet. Propre au restaurant — le bar n'a pas d'ecran de
                 catalogue separe, il cree ses boissons ici meme.
                 structure-ajout:m4-restaurant-carte.html#lien-catalogue --}}
            @if ($page['lien_catalogue'] ?? false)
              <a href="{{ route('pwa.restaurant.plats') }}"
                 class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('carte_pwa.restaurant.bouton_catalogue') }}</a>
            @endif
          </div>
        </div>

        {{-- KPI — maître, carte-module.js l.336-353 : SIX cartes, et la
             sixième est « Prix provisoires ». Elle n'était pas rendue faute de
             colonne au schéma ; PA-161 (b) l'a créée, et le compteur lit
             désormais la donnée au lieu de la dériver de `prix_vente <= 0`,
             qui affichait zéro en permanence. --}}
        {{-- ACCORDEON (directive PO du 03/09/2026) : la bande de six cartes
             repoussait le tableau sous la ligne de flottaison, et l'onglet
             « Ventes » l'a rendue encore plus couteuse. Meme motif que
             `pos/historique-ventes` et `rh/paie` : etat retenu en
             `localStorage`, DEPLIE par defaut — un ecran qui s'ouvre vide se
             lit comme un ecran casse. L'ORDRE et le CONTENU des six cartes
             sont inchanges : c'est un repli d'affichage, pas une reecriture.
             Derogation au maitre, qui n'a pas d'accordeon ici. Une cle par
             ECRAN (`$page['cle_kpis']`) : replier la carte du bar ne doit pas
             replier celle du restaurant, ce sont deux postes de travail.
             structure-ajout:m5-bar-carte.html#bouton-accordeon-kpi
             structure-ajout:m4-restaurant-carte.html#bouton-accordeon-kpi --}}
        <div x-data="{ ouvert: localStorage.getItem('{{ $page['cle_kpis'] }}') !== 'false' }" class="mb-5">
          <button type="button" class="w-full flex items-center justify-between px-4 py-3 bg-white border border-slate-200 rounded-xl no-print"
                  @click="ouvert = !ouvert; localStorage.setItem('{{ $page['cle_kpis'] }}', ouvert)">
            <span class="text-sm font-bold text-slate-700">{{ __('carte_pwa.commun.kpis_accordeon') }}</span>
            <span class="text-[11px] text-slate-400 font-normal hidden sm:inline">{{ __('carte_pwa.commun.kpis_aide') }}</span>
          </button>

        <div x-show="ouvert" x-cloak class="grid grid-cols-2 lg:grid-cols-6 gap-3 mt-3">
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('carte_pwa.commun.kpi_articles') }}</div>
            <div class="text-[17px] font-bold mt-1" style="color:var(--navy)">{{ $k['articles'] }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('carte_pwa.commun.kpi_articles_detail', ['nombre' => $k['disponibles']]) }}</div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('carte_pwa.commun.kpi_retires') }}</div>
            <div class="text-[17px] font-bold mt-1 {{ $k['indisponibles'] > 0 ? 'text-amber-600' : 'text-slate-400' }}">{{ $k['indisponibles'] }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('carte_pwa.commun.kpi_retires_detail') }}</div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('carte_pwa.commun.kpi_lies') }}</div>
            <div class="text-[17px] font-bold mt-1 {{ $k['taux_couverture'] < 50 ? 'text-amber-600' : 'text-emerald-600' }}">{{ $k['lies'] }} / {{ $k['articles'] }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('carte_pwa.commun.kpi_lies_detail', ['taux' => $k['taux_couverture']]) }}</div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('carte_pwa.commun.kpi_sans_lien') }}</div>
            <div class="text-[17px] font-bold mt-1 {{ $k['sans_lien'] > 0 ? 'text-red-600' : 'text-emerald-600' }}">{{ $k['sans_lien'] }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('carte_pwa.commun.kpi_sans_lien_detail') }}</div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('carte_pwa.commun.kpi_rupture') }}</div>
            <div class="text-[17px] font-bold mt-1 {{ $k['en_rupture_stock'] > 0 ? 'text-red-600' : 'text-slate-400' }}">{{ $k['en_rupture_stock'] }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('carte_pwa.commun.kpi_rupture_detail', ['nombre' => $k['sous_seuil']]) }}</div>
          </div>

          {{-- maître — carte-module.js l.395-396 : rouge dès qu'il en reste un,
               gris quand il n'y en a plus. --}}
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('carte_pwa.commun.kpi_provisoires') }}</div>
            <div class="text-[17px] font-bold mt-1 {{ $k['prix_provisoires'] > 0 ? 'text-red-600' : 'text-slate-400' }}">{{ $k['prix_provisoires'] }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('carte_pwa.commun.kpi_provisoires_detail') }}</div>
          </div>
        </div>
        </div>

        {{-- ONGLETS — maître l.55-58 --}}
        <div class="flex flex-wrap gap-1.5 mb-4">
          <button type="button" wire:click="$set('onglet', 'carte')" class="{{ $classeOnglet($onglet === 'carte') }}">{{ __('carte_pwa.commun.onglet_carte') }}</button>
          <button type="button" wire:click="$set('onglet', 'couverture')" class="{{ $classeOnglet($onglet === 'couverture') }}">{{ __('carte_pwa.commun.onglet_couverture') }}</button>

          {{-- Onglet AJOUTÉ le 03/09/2026 (demande du Product Owner) : le
               maître n'a que deux onglets. Le code le nomme neutralement
               (`ventes`), le libellé vient du `$page` de chaque vue — « Ventes
               du Bar » / « Ventes du Restaurant ».

               Aucun jeton `structure-ajout` ici : le bouton s'ajoute DANS la
               barre d'onglets que le maître pose déjà, sans créer de bloc.
               Le comparateur de squelette compare des conteneurs, pas des
               boutons — il ne relève donc rien, et déclarer un bloc qui
               n'existe pas laisserait un jeton que plus rien ne désigne. --}}
          <button type="button" wire:click="$set('onglet', 'ventes')" class="{{ $classeOnglet($onglet === 'ventes') }}">{{ $page['onglet_ventes'] }}</button>
        </div>

        {{-- FILTRES — maître l.60-78 --}}
        <div class="bg-white rounded-xl border border-slate-200 p-3.5 mb-4">
          <div class="flex flex-wrap gap-2.5 items-center">
            <div class="relative flex-1 min-w-[200px]">
              <svg class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
              <input type="search" wire:model.live.debounce.300ms="recherche"
                     placeholder="{{ __('carte_pwa.commun.recherche') }}"
                     class="w-full text-[13px] border border-slate-300 rounded-lg pl-9 pr-3 py-2 focus:border-[var(--gold)] focus:outline-none">
            </div>

            <select wire:model.live="categorie" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <option value="">{{ __('carte_pwa.commun.toutes_categories') }}</option>
              @foreach ($categories as $cle => $libelle)
                <option value="{{ $cle }}">{{ $libelle }}</option>
              @endforeach
            </select>

            <select wire:model.live="etat" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <option value="">{{ __('carte_pwa.commun.tous_articles') }}</option>
              <option value="indisponible">{{ __('carte_pwa.commun.etat_indisponible') }}</option>
              <option value="lie">{{ __('carte_pwa.commun.etat_lie') }}</option>
              <option value="sans_lien">{{ __('carte_pwa.commun.etat_sans_lien') }}</option>
              <option value="rupture_stock">{{ __('carte_pwa.commun.etat_rupture') }}</option>
              {{-- maître — m5-bar-carte.html l.71. --}}
              <option value="provisoire">{{ __('carte_pwa.commun.etat_provisoire') }}</option>
            </select>
          </div>
        </div>

        {{-- Le bandeau d'information du module (maître, carte-module.js l.63-86 :
             « Un plat n'est pas un article de stock… » au restaurant, « Au bar,
             vendre et sortir du stock désignent la même chose… » au bar) a été
             RETIRÉ sur demande du Product Owner (30/10/2026), web et poste. --}}

        @if ($pointDeStockageAbsent)
          {{-- Le stock vendable est celui du POINT de vente, jamais tous
               points confondus : ce qui dort au magasin n'est pas au comptoir.
               Sans point déclaré, aucun chiffre n'est rendu — et l'écran DIT
               pourquoi plutôt que d'afficher zéro, qui se lirait « rupture ». --}}
          <div class="rounded-xl p-3.5 mb-4" style="background:#FFFBEB;border:1px solid #FDE68A">
            <p class="text-[13px]" style="color:#78350F">{{ $page['point_absent'] }}</p>
          </div>
        @endif

        @if ($stocksNonConsultes > 0)
          {{-- Un échec de lecture se NOMME. Il ne se replie ni sur zéro ni sur
               une collection vide : « 0 » se lirait comme une rupture. --}}
          <div class="rounded-xl p-3.5 mb-4" style="background:#FFFBEB;border:1px solid #FDE68A">
            <p class="text-[13px]" style="color:#78350F">{{ __('carte_pwa.commun.stock_non_consulte_detail') }}</p>
          </div>
        @endif

        @error('etat')
          <div class="rounded-xl p-3.5 mb-4" style="background:#FEF2F2;border:1px solid #FECACA">
            <p class="text-[13px]" style="color:#7F1D1D">{{ $message }}</p>
          </div>
        @enderror

        {{-- 02/09/2026 — les DEUX panneaux d'onglet sont rendus, l'inactif
             porte `hidden` (garde G5) : un `@if` qui retirait l'onglet
             Couverture du HTML du premier GET faisait disparaître ses sept
             colonnes du rendu, et la garde les comptait absentes. Le maître
             garde lui aussi les deux vues prêtes (`VUES`, carte-module.js
             l.419) et n'en montre qu'une. --}}
        <div class="{{ $onglet === 'carte' ? '' : 'hidden' }}">
          @if ($lignes === [])
            <div class="bg-white rounded-xl border border-slate-200 py-14 text-center text-slate-400 text-[13px]">
              {{ __('carte_pwa.commun.vide') }}
            </div>
          @else
            {{-- TABLEAU — maître, carte-module.js l.46-53 et l.126-131 --}}
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
              <div class="px-4 py-3 border-b border-slate-200 flex flex-wrap items-center justify-between gap-2">
                <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('carte_pwa.commun.tableau_titre', ['nombre' => count($lignes)]) }}</h3>
                <span class="text-[11px] text-slate-400">{!! __('carte_pwa.commun.tableau_aside') !!}</span>
              </div>

              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  <thead class="bg-[var(--navy)]">
                    <tr>
                      {!! $entete(__('carte_pwa.commun.col_article'), true) !!}
                      {!! $entete(__('carte_pwa.commun.col_categorie')) !!}
                      {!! $entete(__('carte_pwa.commun.col_prix')) !!}
                      {{-- 02/09/2026 — « Disponible » et « Réserve » (garde
                           G5) : le maître les nomme dans son état exporté
                           (`carte-module.js` l.408) sans les rendre à
                           l'écran ; la PWA les rend, aux places de l'export.
                           « Disponible » vient d'`indisponibilites_carte`
                           (DisponibiliteCarteService), « Réserve » est le
                           stock détenu hors du point de vente, dérivé de
                           `mouvements_stock` (StockTheoriqueService). --}}
                      {!! $entete(__('carte_pwa.commun.export_col_disponible')) !!}
                      {!! $entete(__('carte_pwa.commun.col_article_stock')) !!}
                      {!! $entete(__('carte_pwa.commun.col_stock_vendable')) !!}
                      {!! $entete(__('carte_pwa.commun.export_col_reserve')) !!}
                      {{-- maître l.127 : la colonne d'actions n'a pas d'entête. --}}
                      <th class="px-3 py-2.5"></th>
                    </tr>
                  </thead>
                  <tbody>
                    @foreach ($lignes as $ligne)
                      <tr wire:key="carte-{{ $ligne['id'] }}"
                          class="border-t border-slate-100 hover:bg-slate-50 {{ $ligne['disponible'] ? '' : 'opacity-55' }}">

                        <td class="px-3 py-2.5 text-left">
                          <div class="font-semibold text-slate-800">{{ $ligne['nom'] }}</div>
                          @if (! empty($ligne['description']))
                            <div class="text-[11px] text-slate-400 whitespace-pre-line">{{ $ligne['description'] }}</div>
                          @endif
                          @if (! $ligne['disponible'])
                            <div class="text-[11px] text-amber-700">
                              {{ $ligne['indisponibilite']->libelleMotif() }}@if ($ligne['indisponibilite']->commentaire) — {{ $ligne['indisponibilite']->commentaire }}@endif
                            </div>
                          @endif
                        </td>

                        <td class="px-3 py-2.5 text-right text-slate-500 text-[12px]">{{ $ligne['categorie'] }}</td>

                        {{-- maître — carte-module.js l.107-109, AU PIXEL : les
                             deux marques sont des `<div>` de 10 px SOUS le
                             prix, rouge semi-gras pour « provisoire », ambre
                             normal pour « corrigé à la main ». Un prix
                             provisoire non marqué se lit comme un tarif ferme. --}}
                        <td class="px-3 py-2.5 text-right font-semibold" style="color:var(--gold)">{{ $ligne['prix'] }}
                          @if ($ligne['prix_provisoire'])
                            <div class="text-[10px] text-red-600 font-semibold">{{ __('carte_pwa.commun.marque_provisoire') }}</div>
                          @endif
                          @if ($ligne['prix_corrige_main'])
                            <div class="text-[10px] text-amber-600">{{ __('carte_pwa.commun.marque_corrige_main') }}</div>
                          @endif
                        </td>

                        {{-- « Disponible » — le mot de l'export du maître
                             (`carte-module.js` l.410 : 'oui' / 'non'). --}}
                        <td class="px-3 py-2.5 text-right">
                          @if ($ligne['disponible'])
                            <span class="text-[11px] px-1.5 py-0.5 rounded bg-emerald-50 text-emerald-700 font-semibold">{{ __('carte_pwa.commun.export_oui') }}</span>
                          @else
                            <span class="text-[11px] px-1.5 py-0.5 rounded bg-amber-50 text-amber-700 font-semibold">{{ __('carte_pwa.commun.export_non') }}</span>
                          @endif
                        </td>

                        <td class="px-3 py-2.5 text-right">
                          @if ($ligne['lien_affiche'] !== null)
                            <div class="text-[12px] {{ $ligne['lien_affiche']['accent'] ? 'text-emerald-700 font-medium' : 'text-slate-600' }}">{{ $ligne['lien_affiche']['libelle'] }}</div>
                            <div class="text-[10.5px] text-slate-400">{{ $ligne['lien_affiche']['detail'] }}</div>
                          @else
                            <span class="text-[11px] text-slate-400" title="{{ $motifSansLien }}">{{ MontantFcfa::TIRET }}</span>
                          @endif
                        </td>

                        {{-- Les trois états du stock vivent dans UN partiel
                             depuis le 03/09/2026 : l'onglet « Ventes du
                             rayon » rend le même chiffre, et deux cellules
                             écrites à deux endroits divergent. --}}
                        <td class="px-3 py-2.5 text-right">
                          @include('pwa.carte.cellule-stock', ['stock' => $ligne['stock'], 'motif' => $motifSansLien])
                        </td>

                        {{-- « Réserve » — stock détenu hors du point de vente
                             (magasin…), en unités vendables comme la colonne
                             voisine. « — » quand la donnée n'a pas pu être
                             lue : un zéro se lirait « rien en réserve ». --}}
                        <td class="px-3 py-2.5 text-right">
                          @if ($ligne['reserve'] !== null)
                            <span class="text-[13px] text-slate-500">{{ $ligne['reserve'] }}</span>
                          @else
                            <span class="text-[11px] text-slate-400">{{ MontantFcfa::TIRET }}</span>
                          @endif
                        </td>

                        <td class="px-3 py-2.5 text-right whitespace-nowrap">
                          @if ($ligne['disponible'])
                            <button type="button" wire:click="ouvrirRetraitDeLaCarte('{{ $ligne['id'] }}')"
                                    class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white">{{ __('carte_pwa.commun.bouton_rendre_indispo') }}</button>
                          @else
                            <button type="button" wire:click="remettreALaCarte('{{ $ligne['id'] }}')"
                                    class="text-[11px] px-2 py-0.5 rounded border border-emerald-300 text-emerald-700 hover:bg-emerald-50">{{ __('carte_pwa.commun.bouton_remettre') }}</button>
                          @endif

                          <button type="button" wire:click="ouvrirLienAuStock('{{ $ligne['id'] }}')"
                                  class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white ml-1">
                            {{ $ligne['article_stock'] !== null ? __('carte_pwa.commun.bouton_modifier_lien') : __('carte_pwa.commun.bouton_lier') }}
                          </button>

                          @if ($page['delier'] && $ligne['article_stock'] !== null)
                            <button type="button" wire:click="ouvrirRetraitDuLien('{{ $ligne['id'] }}')"
                                    class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white ml-1">{{ __('carte_pwa.commun.bouton_delier') }}</button>
                          @endif

                          {{-- Ajout fonctionnel (01/09/2026, demande du
                               Product Owner) : n'existe pas au maître, qui
                               n'a pas d'historique des prix. Ce partiel sert
                               les DEUX écrans (bar ET restaurant), donc le
                               bloc est déclaré sur les deux maîtres :
                               structure-ajout:m5-bar-carte.html#bouton-historique-prix
                               structure-ajout:m4-restaurant-carte.html#bouton-historique-prix --}}
                          {{-- Modifier le prix (directive PO du 02/09/2026,
                               second volet du retracage des prix) : la trace
                               existait, le geste manquait. Meme declaration
                               de bloc que l'historique :
                               structure-ajout:m5-bar-carte.html#bouton-modifier-prix
                               structure-ajout:m4-restaurant-carte.html#bouton-modifier-prix --}}
                          {{-- Modifier la boisson (PO 08/10/2026) : propre au bar,
                               comme « Nouvelle boisson ». Renomme / reclasse ;
                               le prix garde sa modale tracee.
                               structure-ajout:m5-bar-carte.html#bouton-modifier-boisson --}}
                          @if ($page['creation_boisson'] ?? false)
                            <button type="button" wire:click="ouvrirModificationBoisson('{{ $ligne['id'] }}')"
                                    class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white ml-1">{{ __('carte_pwa.commun.bouton_modifier_boisson') }}</button>
                          @endif
                          <button type="button" wire:click="ouvrirModificationPrix('{{ $ligne['id'] }}')"
                                  class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white ml-1">{{ __('carte_pwa.commun.bouton_modifier_prix') }}</button>
                          <button type="button" wire:click="ouvrirHistoriquePrix('{{ $ligne['id'] }}')"
                                  class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white ml-1">{{ __('carte_pwa.commun.bouton_historique_prix') }}</button>
                        </td>
                      </tr>
                    @endforeach
                  </tbody>
                </table>
              </div>
            </div>
          @endif
        </div>

        {{-- ONGLET COUVERTURE — maître, carte-module.js l.176-201.
             02/09/2026 — bloc AJOUTÉ au premier GET (garde G5) : le maître ne
             monte qu'un onglet à la fois dans `#zone` ; la PWA rend les deux
             et cache l'inactif. Ce partiel sert les DEUX écrans, donc le bloc
             est déclaré sur les deux maîtres :
             structure-ajout:m5-bar-carte.html#div-f45deea9
             structure-ajout:m4-restaurant-carte.html#div-f45deea9 --}}
        <div class="{{ $onglet === 'couverture' ? '' : 'hidden' }}">
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
            <div class="px-4 py-3 border-b border-slate-200">
              <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('carte_pwa.commun.couverture_titre') }}</h3>
            </div>

            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]">
                  <tr>
                    {!! $entete(__('carte_pwa.commun.couverture_col_categorie'), true) !!}
                    {!! $entete(__('carte_pwa.commun.couverture_col_articles')) !!}
                    {!! $entete(__('carte_pwa.commun.couverture_col_lies')) !!}
                    {!! $entete(__('carte_pwa.commun.couverture_col_sans_lien')) !!}
                    {!! $entete(__('carte_pwa.commun.couverture_col_couverture')) !!}
                    {!! $entete(__('carte_pwa.commun.couverture_col_indisponibles')) !!}
                    {{-- maître — carte-module.js l.184 : la septième colonne. --}}
                    {!! $entete(__('carte_pwa.commun.couverture_col_provisoires')) !!}
                  </tr>
                </thead>
                <tbody>
                  @foreach ($couverture['categories'] as $cat)
                    <tr class="border-t border-slate-100" wire:key="couv-{{ $cat['cle'] }}">
                      <td class="px-3 py-2.5 text-left font-semibold text-slate-800">{{ $cat['libelle'] }}</td>
                      <td class="px-3 py-2.5 text-right text-slate-600">{{ $cat['total'] }}</td>
                      <td class="px-3 py-2.5 text-right font-semibold {{ $cat['lies'] ? 'text-emerald-700' : 'text-slate-300' }}">{{ $cat['lies'] }}</td>
                      <td class="px-3 py-2.5 text-right {{ $cat['sans_lien'] ? 'text-amber-600' : 'text-slate-300' }}">{{ $cat['sans_lien'] }}</td>
                      <td class="px-3 py-2.5">
                        <div class="flex items-center gap-2 justify-end">
                          <div class="w-24 h-2 rounded-full bg-slate-200 overflow-hidden">
                            <div class="h-full" style="width:{{ $cat['taux'] }}%;background:{{ $cat['taux'] >= 80 ? '#059669' : ($cat['taux'] >= 40 ? '#B8891E' : '#DC2626') }}"></div>
                          </div>
                          <span class="text-[12px] font-semibold w-11 text-right">{{ $cat['taux'] }} %</span>
                        </div>
                      </td>
                      <td class="px-3 py-2.5 text-right {{ $cat['indisponibles'] ? 'text-amber-600' : 'text-slate-300' }}">{{ $cat['indisponibles'] ?: MontantFcfa::TIRET }}</td>
                      {{-- maître — carte-module.js l.178 : rouge semi-gras dès
                           qu'il en reste un, « — » gris quand il n'y en a plus. --}}
                      <td class="px-3 py-2.5 text-right {{ $cat['provisoires'] ? 'text-red-600 font-semibold' : 'text-slate-300' }}">{{ $cat['provisoires'] ?: MontantFcfa::TIRET }}</td>
                    </tr>
                  @endforeach

                  {{-- maître, carte-module.js l.188-196 : la ligne TOTAL.
                       Aucune des deux vues de la PWA ne la rendait. --}}
                  <tr class="border-t-2 border-slate-300 bg-slate-50 font-bold">
                    <td class="px-3 py-2.5" style="color:var(--navy)">{{ __('carte_pwa.commun.couverture_total') }}</td>
                    <td class="px-3 py-2.5 text-right">{{ $couverture['total']['articles'] }}</td>
                    <td class="px-3 py-2.5 text-right">{{ $couverture['total']['lies'] }}</td>
                    <td class="px-3 py-2.5 text-right">{{ $couverture['total']['sans_lien'] }}</td>
                    <td class="px-3 py-2.5 text-right">{{ $couverture['total']['taux_couverture'] }} %</td>
                    <td class="px-3 py-2.5 text-right">{{ $couverture['total']['indisponibles'] }}</td>
                    <td class="px-3 py-2.5 text-right">{{ $couverture['total']['prix_provisoires'] }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          @if ($couverture['total']['sans_lien'] > 0)
            <div class="rounded-xl p-3.5 mb-4" style="background:#FFFBEB;border:1px solid #FDE68A">
              <p class="text-[13px]" style="color:#78350F">
                <strong>{{ __('carte_pwa.commun.couverture_dette_titre', ['nombre' => $couverture['total']['sans_lien']]) }}</strong>
                {{ __('carte_pwa.commun.couverture_dette_texte') }}
              </p>
            </div>
          @else
            <div class="rounded-xl p-3.5 mb-4" style="background:#F8FAFC;border:1px solid #E2E8F0">
              <p class="text-[13px]" style="color:#334155">
                <strong>{{ __('carte_pwa.commun.couverture_complete_titre') }}</strong>
                {{ __('carte_pwa.commun.couverture_complete_texte') }}
              </p>
            </div>
          @endif
        </div>

        {{-- ================================================== ONGLET VENTES
             AJOUT du 03/09/2026 (demande du Product Owner) : le maître n'a
             aucun onglet de ventes sur ses deux pages de carte.

             DEUX blocs sont relevés par le comparateur de squelette, et ce
             partiel sert les DEUX écrans — chaque bloc est donc déclaré sur
             les deux maîtres, avec le nom que le comparateur lui donne :

             1. la barre de filtres du panneau
                (`div [flex flex-wrap gap-2.5 items-center]`) :
                structure-ajout:m5-bar-carte.html#div-9396a819
                structure-ajout:m4-restaurant-carte.html#div-9396a819
             2. le cadre du tableau (`div [overflow-hidden]`), de même forme
                que celui de l'onglet Couverture, déjà déclaré plus haut :
                structure-ajout:m5-bar-carte.html#div-f45deea9
                structure-ajout:m4-restaurant-carte.html#div-f45deea9

             ⚠ CE PANNEAU N'EST RENDU QUE LORSQU'IL EST OUVERT, contrairement
             aux deux autres. Les colonnes des onglets Carte et Couverture sont
             celles du MAÎTRE, et la garde G5 exige de les retrouver dans le
             HTML du premier GET — d'où leur rendu permanent, l'inactif caché.
             Celles-ci n'existent dans aucun tableau du maître : les rendre au
             premier GET les ferait compter comme des colonnes INVENTÉES par la
             seconde moitié de cette même garde. Voir le commentaire jumeau
             dans `EcranDeCarte::socleDeLaCarte()`. --}}
        @if ($onglet === 'ventes' && $ventes !== null)
          {{-- FILTRES du panneau — ils portent leurs propres clés d'URL
               (`qv`, `vstatut`, `du`, `au`) : ceux du haut de page filtrent la
               CARTE, jamais les ventes. --}}
          <div class="bg-white rounded-xl border border-slate-200 p-3.5 mb-4">
            <div class="flex flex-wrap gap-2.5 items-center">
              <div class="relative flex-1 min-w-[200px]">
                <svg class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
                <input type="search" wire:model.live.debounce.300ms="rechercheVentes"
                       placeholder="{{ __('carte_pwa.commun.ventes_recherche') }}"
                       class="w-full text-[13px] border border-slate-300 rounded-lg pl-9 pr-3 py-2 focus:border-[var(--gold)] focus:outline-none">
              </div>

              <select wire:model.live="statutVente" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
                <option value="">{{ __('carte_pwa.commun.ventes_tous_statuts') }}</option>
                <option value="validee">{{ __('carte_pwa.commun.ventes_statut_validee') }}</option>
                <option value="annulee">{{ __('carte_pwa.commun.ventes_statut_annulee') }}</option>
              </select>

              <label class="text-[12px] text-slate-500 flex items-center gap-1.5">
                {{ __('carte_pwa.commun.ventes_du') }}
                <input type="date" wire:model.live="debutVentes"
                       class="text-[13px] border border-slate-300 rounded-lg px-3 py-2 focus:border-[var(--gold)] focus:outline-none">
              </label>

              <label class="text-[12px] text-slate-500 flex items-center gap-1.5">
                {{ __('carte_pwa.commun.ventes_au') }}
                <input type="date" wire:model.live="finVentes"
                       class="text-[13px] border border-slate-300 rounded-lg px-3 py-2 focus:border-[var(--gold)] focus:outline-none">
              </label>
            </div>

            <p class="text-[11px] text-slate-400 mt-2">{{ __('carte_pwa.commun.ventes_bornes_aide') }}</p>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
            {{-- COMPTEUR — il porte sur le JEU FILTRÉ ENTIER, jamais sur la
                 page : un total qui changerait en tournant les pages dirait
                 deux vérités sur le même filtre (PA-119, même esprit). --}}
            <div class="px-4 py-3 border-b border-slate-200 flex flex-wrap items-center justify-between gap-2">
              <h3 class="text-[14px] font-bold" style="color:var(--navy)">
                {{ __('carte_pwa.commun.ventes_compteur', [
                    'nombre' => $ventes['lignes_filtre'],
                    'total' => $ventes['total_filtre'],
                ]) }}
                @if ($ventes['annulees_filtre'] > 0)
                  <span class="text-[12px] font-normal" style="color:var(--erreur)">— {{ __('carte_pwa.commun.ventes_compteur_annulees', ['nombre' => $ventes['annulees_filtre']]) }}</span>
                @endif
              </h3>
              <span class="text-[11px] text-slate-400">{{ __('carte_pwa.commun.ventes_stock_aide') }}</span>
            </div>

            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]">
                  <tr>
                    {!! $entete(__('carte_pwa.commun.ventes_col_date'), true) !!}
                    {!! $entete(__('carte_pwa.commun.ventes_col_ticket'), true) !!}
                    {!! $entete(__('carte_pwa.commun.ventes_col_article'), true) !!}
                    {!! $entete(__('carte_pwa.commun.ventes_col_stock')) !!}
                    {!! $entete(__('carte_pwa.commun.ventes_col_prix')) !!}
                    {!! $entete(__('carte_pwa.commun.ventes_col_quantite')) !!}
                    {!! $entete(__('carte_pwa.commun.ventes_col_montant')) !!}
                    {!! $entete(__('carte_pwa.commun.ventes_col_statut')) !!}
                    {!! $entete(__('carte_pwa.commun.ventes_col_utilisateur')) !!}
                  </tr>
                </thead>
                <tbody>
                  {{-- L'état vide garde le `<thead>` et DIT pourquoi il est
                       vide : un tableau qui disparaît ne distingue pas « aucun
                       résultat » de « écran cassé ». --}}
                  @forelse ($ventes['lignes'] as $vl)
                    <tr wire:key="vente-ligne-{{ $vl['id'] }}"
                        class="border-t border-slate-100 hover:bg-slate-50 {{ $vl['annulee'] ? 'opacity-55' : '' }}">
                      <td class="px-3 py-2.5 text-left text-slate-500 text-[12px] whitespace-nowrap">{{ $vl['quand'] }}</td>
                      <td class="px-3 py-2.5 text-left text-slate-500 text-[12px] whitespace-nowrap">{{ $vl['numero'] }}</td>
                      <td class="px-3 py-2.5 text-left font-semibold text-slate-800">{{ $vl['nom'] }}</td>

                      {{-- Stock du JOUR, lu par le même chemin que l'onglet
                           Carte. Un article retiré de la carte rend « — » : il
                           n'a pas un stock nul, il n'a plus d'article où le
                           lire (PA-129). --}}
                      <td class="px-3 py-2.5 text-right">
                        @if ($vl['article_a_la_carte'])
                          @include('pwa.carte.cellule-stock', ['stock' => $vl['stock'], 'motif' => $motifSansLien])
                        @else
                          <span class="text-[11px] text-slate-400" title="{{ __('carte_pwa.commun.ventes_stock_hors_carte') }}">{{ MontantFcfa::TIRET }}</span>
                        @endif
                      </td>

                      <td class="px-3 py-2.5 text-right text-slate-600">{{ $vl['prix_unitaire'] }}</td>
                      <td class="px-3 py-2.5 text-right font-semibold text-slate-700">{{ $vl['quantite'] }}</td>
                      <td class="px-3 py-2.5 text-right font-semibold" style="color:var(--gold)">{{ $vl['montant'] }}</td>

                      <td class="px-3 py-2.5 text-right">
                        @if ($vl['annulee'])
                          {{-- RG-02 : la vente reste au registre. Le motif,
                               quand il existe, part en infobulle — le tableau
                               dirait sinon « annulée » sans dire pourquoi. --}}
                          <span class="text-[11px] px-1.5 py-0.5 rounded font-semibold"
                                style="background:#FDECEC;color:var(--erreur)"
                                @if ($vl['motif_annulation'] !== '') title="{{ $vl['motif_annulation'] }}" @endif>{{ __('carte_pwa.commun.ventes_statut_annulee') }}</span>
                        @else
                          <span class="text-[11px] px-1.5 py-0.5 rounded font-semibold"
                                style="background:#E8F5E9;color:var(--succes)">{{ __('carte_pwa.commun.ventes_statut_validee') }}</span>
                        @endif
                      </td>

                      <td class="px-3 py-2.5 text-right text-slate-500 text-[12px]">{{ $vl['utilisateur'] }}</td>
                    </tr>
                  @empty
                    <tr class="border-t border-slate-100">
                      <td colspan="9" class="px-3 py-14 text-center text-slate-400 text-[13px]">{{ __('carte_pwa.commun.ventes_vide') }}</td>
                    </tr>
                  @endforelse

                  {{-- TOTAL — la somme des lignes VALIDÉES de la page, en
                       `bcadd` sur les chaînes rendues par PDO. Jamais `sum()`
                       sur des flottants, et jamais les annulations : elles
                       restent affichées (RG-02) mais leur montant n'est pas de
                       l'argent. --}}
                  <tr class="border-t-2 border-slate-300 bg-slate-50 font-bold">
                    <td class="px-3 py-2.5" colspan="6" style="color:var(--navy)">{{ __('carte_pwa.commun.ventes_total_page') }}
                      <span class="block text-[11px] font-normal text-slate-400">{{ __('carte_pwa.commun.ventes_total_page_aide') }}</span>
                    </td>
                    <td class="px-3 py-2.5 text-right" style="color:var(--gold)">{{ $ventes['total_page'] }}</td>
                    <td class="px-3 py-2.5 text-right text-[11px] font-normal text-slate-400">
                      @if ($ventes['annulees_page'] > 0)
                        {{ __('carte_pwa.commun.ventes_compteur_annulees', ['nombre' => $ventes['annulees_page']]) }}
                      @endif
                    </td>
                    <td class="px-3 py-2.5"></td>
                  </tr>
                </tbody>
              </table>
            </div>

            {{-- PAGINATION G6 — « Affichage de X-Y sur Z » à gauche, les
                 liens à droite, exactement comme `Facturation`. --}}
            <div class="flex items-center justify-between px-4 py-3 border-t border-slate-100 no-print">
              <p class="text-xs text-slate-500">{!! __('carte_pwa.commun.ventes_affichage', [
                  'debut' => '<strong>' . ($ventes['page']->total() === 0 ? 0 : $ventes['page']->firstItem()) . '</strong>',
                  'fin' => '<strong>' . ($ventes['page']->lastItem() ?? 0) . '</strong>',
                  'total' => '<strong>' . $ventes['page']->total() . '</strong>',
              ]) !!}</p>
              {{ $ventes['page']->onEachSide(1)->links() }}
            </div>
          </div>
        @endif

      </div>
    </main>
  </div>

  {{-- ==================== MODALES ======================================= --}}
  @if ($etatFormulaire === 'lien' && $articleCible !== null)
    <x-pwa.modal-lieraustock :nom="$articleCible->libelle"
                             :prix="MontantFcfa::format((string) $articleCible->prix_vente)"
                             :articles="$articlesDeStock"
                             :apercu="$apercuDuLien" />
  @endif

  {{-- « Nouvelle boisson » (PO 03/09/2026) — declaree au bouton ci-dessus.
       L'article de stock est une VRAIE cle etrangere (`cartes_boisson
       .article_id` est NOT NULL) : sans lui, aucune vente ne pourrait
       decrementer quoi que ce soit. Le champ est donc un selecteur, jamais
       du texte libre. --}}
  @if (($page['creation_boisson'] ?? false) && $etatFormulaire === 'boisson')
    <x-pwa.modale :titre="__('carte_pwa.commun.modale_boisson_titre')"
                  :sousTitre="__('carte_pwa.commun.modale_boisson_sous_titre')"
                  fermer="$set('etatFormulaire', null)" largeur="520px">
      <div class="space-y-3">
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('carte_pwa.commun.champ_boisson_libelle') }} <span class="text-red-500">*</span></label>
          <input type="text" wire:model="libelleSaisi"
                 class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 focus:border-[var(--gold)] focus:outline-none">
          @error('libelleSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>

        <div class="grid grid-cols-2 gap-3">
          <div>
            <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('carte_pwa.commun.champ_boisson_categorie') }} <span class="text-red-500">*</span></label>
            <select wire:model="categorieSaisie" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 bg-white">
              @foreach ($page['categories'] as $cleCategorie => $libelleCategorie)
                <option value="{{ $cleCategorie }}">{{ $libelleCategorie }}</option>
              @endforeach
            </select>
            @error('categorieSaisie') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
          <div>
            <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('carte_pwa.commun.champ_boisson_prix') }} <span class="text-red-500">*</span></label>
            <input type="number" step="1" min="0" wire:model="prixSaisi"
                   class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 focus:border-[var(--gold)] focus:outline-none">
            @error('prixSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
        </div>

        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('carte_pwa.commun.champ_boisson_article') }} <span class="text-red-500">*</span></label>
          <input type="search" wire:model.live.debounce.300ms="rechercheArticleStock"
                 placeholder="{{ __('carte_pwa.commun.champ_boisson_article_invite') }}"
                 class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2 mb-2">
          <select wire:model="articleStockId" size="5" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2 bg-white">
            @foreach ($articlesDeStock as $articleDeStock)
              <option value="{{ $articleDeStock->id }}">{{ $articleDeStock->libelle }}</option>
            @endforeach
          </select>
          <p class="text-[12px] text-slate-500 mt-1">{{ __('carte_pwa.commun.champ_boisson_article_aide') }}</p>
          @error('articleStockId') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
      </div>

      <x-slot:pied>
        <button type="button" wire:click="$set('etatFormulaire', null)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerCreationBoisson"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('carte_pwa.commun.boisson_confirmer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- « Modifier la boisson » (PO 08/10/2026) - declaree au bouton de la ligne.
       Libelle + categorie seulement : le prix et le lien au stock ont leurs
       modales. `fermer` est obligatoire (voir la modale du prix). --}}
  @if (($page['creation_boisson'] ?? false) && $etatFormulaire === 'modificationBoisson' && $articleCible !== null)
    <x-pwa.modale :titre="__('carte_pwa.commun.modale_modifier_boisson_titre', ['article' => $articleCible->libelle])"
                  :sousTitre="__('carte_pwa.commun.modale_modifier_boisson_sous_titre')"
                  fermer="$set('etatFormulaire', null)" largeur="480px">
      <div class="space-y-3">
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('carte_pwa.commun.champ_boisson_libelle') }} <span class="text-red-500">*</span></label>
          <input type="text" wire:model="libelleSaisi"
                 class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 focus:border-[var(--gold)] focus:outline-none">
          @error('libelleSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('carte_pwa.commun.champ_boisson_categorie') }} <span class="text-red-500">*</span></label>
          <select wire:model="categorieSaisie" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 bg-white">
            @foreach ($page['categories'] as $cleCategorie => $libelleCategorie)
              <option value="{{ $cleCategorie }}">{{ $libelleCategorie }}</option>
            @endforeach
          </select>
          @error('categorieSaisie') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
      </div>

      <x-slot:pied>
        <button type="button" wire:click="$set('etatFormulaire', null)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerModificationBoisson"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('carte_pwa.commun.modifier_boisson_confirmer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  @if ($etatFormulaire === 'retrait' && $articleCible !== null)
    <x-pwa.modal-retirerdelacartedujour :nom="$articleCible->libelle" :motifs="$motifs" />
  @endif

  @if ($page['delier'] && $etatFormulaire === 'delier' && $articleCible !== null)
    <x-pwa.modal-delier :titre="__('carte_pwa.modale_delier.titre')"
                        :message="__('carte_pwa.modale_delier.message')"
                        :detail="__('carte_pwa.modale_delier.detail')"
                        :confirmer="__('carte_pwa.modale_delier.bouton_confirmer')"
                        action="confirmerRetraitDuLien" />
  @endif

  {{-- « Historique des prix » — AJOUT FONCTIONNEL (01/09/2026, demande du
       Product Owner) : n'existe pas au maître. Déclaré ci-dessus, au bouton
       qui l'ouvre, sous les DEUX jetons `structure-ajout`. Modale de LECTURE
       seule : aucune écriture n'est proposée, `ouvrirHistoriquePrix()` est
       inscrite dans les méthodes de LECTURE de `PwaEcritureAutoriseeTest`. --}}
  {{-- ================================================ MODALE — PRIX
       (PO 02/09/2026). L'ecriture passe par le service de domaine de la
       carte ; l'Observer consigne la trace que la modale d'historique
       affiche. --}}
  @if ($etatFormulaire === 'prix' && $articleCible !== null)
    {{-- `fermer` est OBLIGATOIRE ici : le chassis retombe sinon sur
         `fermerModales`, que les ecrans de carte n'ont pas — la croix
         plantait en 500 (constate par le PO le 03/09/2026). --}}
    <x-pwa.modale :titre="__('carte_pwa.commun.modale_prix_titre', ['article' => $articleCible->libelle])"
                  :sousTitre="__('carte_pwa.commun.modale_prix_sous_titre')"
                  fermer="$set('etatFormulaire', null)" largeur="420px">
      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('carte_pwa.commun.champ_nouveau_prix') }} <span class="text-red-500">*</span></label>
        <input type="number" step="1" min="1" wire:model="prixSaisi"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 focus:border-[var(--gold)] focus:outline-none">
        @error('prixSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        <p class="text-[12px] text-slate-500 mt-2">{{ __('carte_pwa.commun.prix_trace') }}</p>
      </div>

      <x-slot:pied>
        <button type="button" wire:click="$set('etatFormulaire', null)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerModificationPrix"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('carte_pwa.commun.prix_confirmer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  @if ($etatFormulaire === 'historiquePrix' && $articleCible !== null)
    @php
        $libelleChampPrix = static fn (string $champ): string => match ($champ) {
            \App\Domain\Carte\Models\HistoriquePrixCarte::CHAMP_PRIX_CORRIGE_MAIN => __('carte_pwa.modale_historique_prix.champ_prix_corrige_main'),
            default => __('carte_pwa.modale_historique_prix.champ_prix_vente'),
        };

        $valeurAffichee = static function (?string $valeur, string $champ) : string {
            if ($valeur === null) {
                return MontantFcfa::TIRET;
            }

            if ($champ === \App\Domain\Carte\Models\HistoriquePrixCarte::CHAMP_PRIX_CORRIGE_MAIN) {
                return bccomp($valeur, '1', 2) === 0
                    ? __('carte_pwa.modale_historique_prix.marque_active')
                    : __('carte_pwa.modale_historique_prix.marque_inactive');
            }

            return MontantFcfa::format($valeur);
        };
    @endphp
    <x-pwa.modale :titre="__('carte_pwa.modale_historique_prix.titre')"
                  :sousTitre="__('carte_pwa.modale_historique_prix.sous_titre', ['article' => $articleCible->libelle])"
                  fermer="$set('etatFormulaire', null)" largeur="640px">
      @if ($historiquePrix->isEmpty())
        <p class="text-center text-slate-400 py-10 text-[13px]">{{ __('carte_pwa.modale_historique_prix.vide') }}</p>
      @else
        <div class="overflow-x-auto">
          <table class="w-full text-[13px]">
            <thead class="bg-[var(--navy)]"><tr>
              {!! $entete(__('carte_pwa.modale_historique_prix.col_date'), true) !!}
              {!! $entete(__('carte_pwa.modale_historique_prix.col_champ')) !!}
              {!! $entete(__('carte_pwa.modale_historique_prix.col_ancien_prix')) !!}
              {!! $entete(__('carte_pwa.modale_historique_prix.col_nouveau_prix')) !!}
              {!! $entete(__('carte_pwa.modale_historique_prix.col_par')) !!}
            </tr></thead>
            <tbody>
              @foreach ($historiquePrix as $trace)
                <tr class="border-t border-slate-100" wire:key="hist-prix-{{ $trace->id }}">
                  <td class="px-3 py-2 text-slate-600 whitespace-nowrap">{{ $trace->created_at?->format('d/m/Y H:i') }}</td>
                  <td class="px-3 py-2 text-slate-700">{{ $libelleChampPrix($trace->champ) }}</td>
                  <td class="px-3 py-2 text-right text-slate-500">{{ $valeurAffichee($trace->ancien_prix, $trace->champ) }}</td>
                  <td class="px-3 py-2 text-right font-semibold" style="color:var(--navy)">{{ $valeurAffichee($trace->nouveau_prix, $trace->champ) }}</td>
                  <td class="px-3 py-2 text-slate-500 text-[12px]">{{ $trace->utilisateurCreation?->login ?? MontantFcfa::TIRET }}</td>
                </tr>
              @endforeach
            </tbody>
          </table>
        </div>
      @endif
      <x-slot:pied>
        <button type="button" wire:click="$set('etatFormulaire', null)" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('carte_pwa.modale_historique_prix.bouton_fermer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- L'export suit l'ONGLET COURANT (PO 03/09/2026), et la modale le NOMME :
       sur l'onglet Ventes elle titre « Exporter — Ventes du Bar », sur les deux
       autres « Exporter — Carte du bar ». Un titre unique laisserait douter du
       périmètre du fichier téléchargé, ce que le maître évite lui-même en
       titrant « Exporter — <entité> » (`crud-ui.js` l.147). L'aiguillage réel
       est dans `EcranDeCarte::genererExport()` ; ceci n'en est que le libellé.
       Aucun bloc nouveau : la modale partagée est déjà déclarée
       (`maitre-refuse:chassis#modale-export`). --}}
  @if ($etatFormulaire === 'export')
    @include('pwa.partials.modale-export', [
        'titre' => $onglet === 'ventes' ? $page['export_titre_ventes'] : $page['export_titre'],
    ])
  @endif

  @error('formatExport')
    <div class="fixed bottom-5 right-5 z-50 px-4 py-3 rounded-xl bg-red-600 text-white text-[13px] no-print">{{ $message }}</div>
  @enderror

  @include('pwa.partials.acces-rapide')
</div>

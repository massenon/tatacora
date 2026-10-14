{{--
    ÉCRAN « GESTION DES STOCKS » (M6).

    Maître : `prototype_v2/pages/m6-stocks.html`.

    ## Ce fichier a remplacé une COPIE

    Jusqu'au 31/08/2026, cette vue était `inventaires.blade.php` recopiée :
    `diff` ne rendait que trois blocs de CSS d'impression. Elle appelait six
    méthodes du composant `Inventaires` qui n'existent pas sur `Stocks`, et
    `GET /pwa/stocks` répondait 500. Les sept actions du composant n'étaient
    câblées nulle part.

    ## Les colonnes sont celles du maître, dans son ordre et sa CASSE

    `m6-stocks.html` l.192-201 :
    Article · Catégorie · Point · Suivi · Stock · Seuil · Valeur d'achat ·
    CMP · Valeur stock · Actions.

    La casse est celle du maître, et `uppercase` fait le rendu. Une majuscule
    écrite en dur ressortirait telle quelle dans le CSV et le PDF, où aucune
    feuille de style ne s'applique.

    ## Les trois refus ont été LEVÉS le 02/09/2026 — PA-161 (a)

    Cette vue déclarait `maitre-refuse:m6-stocks#colonne-point`,
    `#colonne-suivi` et `#colonne-valeur-achat`, et affichait leurs motifs sous
    le tableau : « `articles` ne porte aucun point de rattachement », « aucune
    colonne `suivi` au schéma », « aucun prix d'achat d'origine n'est
    conservé ». Les trois étaient exacts à l'écriture. La migration
    `2026_09_02_210000` les a créées : les déclarations et les motifs sont donc
    RETIRÉS, pas laissés à vieillir — un motif de refus périmé transforme une
    décision en oubli, et c'est pire qu'une colonne vide, parce que personne ne
    rouvre la question quand l'écran dit que c'est impossible (PA-144).

    Ce qui est dit à la place l'est LIGNE PAR LIGNE : un article jamais
    réceptionné rend « — » avec `liste.jamais_receptionne` en infobulle. La
    colonne existe ; c'est cet article-là qui n'a pas de valeur.

    ## Deux distinctions que le tableau ne doit jamais brouiller

    - « Point » est le RATTACHEMENT de l'article. Le filtre « Tous les points »
      reste, lui, une portée de CALCUL sur les mouvements — « 10 au bar et 0 au
      magasin » n'est pas « 0 au bar et 10 au magasin ».
    - Un article `journalier` n'a pas de stock : sa cellule « Stock » rend
      « non suivi » et non « 0 », qui se lirait comme une rupture (maître
      l.230-236).

    ## État vide

    Le maître écrit « Aucun article ne correspond à ces filtres. » (l.189).
    `crud-ui.js` pose ailleurs le couple générique « Aucun résultat » /
    « Essayez de modifier votre recherche ou vos filtres. » — le titre générique
    est repris, le détail est celui de la page, qui nomme l'objet manquant.
--}}
@php
    use App\Pwa\Support\MontantFcfa;

    // maître — l.192-201 : `text-left` sur les libellés, `text-right` sur les
    // chiffres, et la casse laissée à `uppercase`.
    $colonnes = [
        ['cle' => 'col_article', 'droite' => false],
        ['cle' => 'col_categorie', 'droite' => false],
        // 02/09/2026 — « Unité » (garde G5) : le maître la nomme en colonne
        // de son état exporté (l.464), entre Catégorie et Point. L'écran du
        // maître la rendait entre parenthèses à côté du libellé ; la PWA la
        // porte en colonne — la rendre deux fois par ligne serait redondant.
        ['cle' => 'col_unite', 'droite' => false],
        ['cle' => 'col_point', 'droite' => false],
        ['cle' => 'col_suivi', 'droite' => false],
        ['cle' => 'col_stock', 'droite' => true],
        ['cle' => 'col_seuil', 'droite' => true],
        ['cle' => 'col_valeur_achat', 'droite' => true],
        ['cle' => 'col_cmp', 'droite' => true],
        ['cle' => 'col_valeur_stock', 'droite' => true],
        ['cle' => 'col_actions', 'droite' => true],
    ];
@endphp

<div class="contents">

  @include('pwa.partials.barre-superieure')

  <style>
    @media print {
      html, body, main, div, section, .contents, .flex, .zone-impression {
        overflow: visible !important; height: auto !important; max-height: none !important;
      }
      #shell-sidebar, #shell-topbar, .no-print, nav, button, input, select, .overlay-modale {
        display: none !important;
      }
      .zone-impression { width: 100% !important; margin: 0 !important; padding: 0 !important; }
      thead { display: table-header-group !important; }
      tr { break-inside: avoid !important; }
    }
  </style>

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')

    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8 zone-impression">

        {{--
            EN-TÊTE INSTITUTIONNEL D'IMPRESSION.

            ⚠ `<h2>`, jamais `<h1>` : une page ne porte qu'un seul `<h1>`, et
            c'est celui du maître. Deux `<h1>` empêchent `t-trois-sources.js`
            d'ancrer l'écran, et un lecteur d'écran annonce le mauvais en
            premier (G2, `TitreDePageH1PwaTest`).
        --}}
        <div class="hidden print:block mb-6 border-b-2 border-[var(--navy)] pb-4">
          <h2 class="text-xl font-bold" style="color:var(--navy)">TATACORA AFRIQUE — GÎTE CHEZ NOËL</h2>
          <p class="text-xs text-slate-600 mt-1">{{ __('stocks_pwa.liste.titre') }} — {{ now()->format('d/m/Y H:i') }}</p>
        </div>

        {{-- ===================== EN-TÊTE DE PAGE — maître l.22-38 ===================== --}}
        <div class="mb-5 flex flex-wrap items-start justify-between gap-3 no-print">
          <div>
            <div class="flex items-center gap-2.5">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M21 8l-9-5-9 5 9 5 9-5zM3 8v8l9 5 9-5V8M12 13v8"/></svg>
              <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('stocks_pwa.liste.titre') }}</h1>
            </div>
            <p class="text-[15px] text-slate-500 mt-1.5">
              {{ __('stocks_pwa.liste.sous_titre') }}
              <strong>{{ __('stocks_pwa.liste.sous_titre_fort') }}</strong>{{ __('stocks_pwa.liste.sous_titre_fin') }}
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <a href="{{ route('pwa.stocks.inventaires') }}" wire:navigate
               class="text-[13px] px-3.5 py-2 rounded-lg border border-slate-300 bg-white hover:bg-slate-50">{{ __('stocks_pwa.liste.lien_inventaires') }}</a>
            <a href="{{ route('pwa.achats.approvisionnement') }}" wire:navigate
               class="text-[13px] px-3.5 py-2 rounded-lg border border-slate-300 bg-white hover:bg-slate-50">{{ __('stocks_pwa.liste.lien_approvisionnement') }}</a>
            <button type="button" wire:click="nouvelArticle"
                    class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white hover:opacity-90 font-semibold">{{ __('stocks_pwa.liste.nouvel_article') }}</button>
          </div>
        </div>

        @if (session('pwa-succes'))
          <div class="mb-4 rounded-xl px-4 py-3 text-[13px] no-print"
               style="background:#E8F5E9;color:#2E7D32;border:1px solid #C8E6C9">{{ session('pwa-succes') }}</div>
        @endif

        {{-- ===================== INDICATEURS — maître l.169-174 ===================== --}}
        <div id="kpis-stock" class="grid grid-cols-2 lg:grid-cols-5 gap-3 mb-5">
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <p class="text-[10px] font-bold uppercase tracking-wider text-slate-400">{{ __('stocks_pwa.liste.kpi_references') }}</p>
            <p class="text-lg font-bold mt-0.5 text-[var(--navy)]">{{ $consolide->references }}</p>
            {{-- maître l.170 : le détail de « Références » ventile le
                 référentiel entre suivi permanent et achat journalier. --}}
            <p class="text-[11px] text-slate-400 mt-0.5">{{ __('stocks_pwa.liste.kpi_references_detail', ['permanents' => $consolide->permanents, 'journaliers' => $consolide->journaliers]) }}</p>
          </div>
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <p class="text-[10px] font-bold uppercase tracking-wider text-slate-400">{{ __('stocks_pwa.liste.kpi_valeur') }}</p>
            <p class="text-lg font-bold mt-0.5 text-[var(--navy)]">{{ MontantFcfa::format($consolide->valeurTotale) }}</p>
            <p class="text-[11px] text-slate-400 mt-0.5">{{ __('stocks_pwa.liste.kpi_valeur_detail') }}</p>
          </div>
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <p class="text-[10px] font-bold uppercase tracking-wider text-slate-400">{{ __('stocks_pwa.liste.kpi_sous_seuil') }}</p>
            <p class="text-lg font-bold mt-0.5 {{ $consolide->sousSeuil > 0 ? 'text-red-600' : 'text-emerald-600' }}">{{ $consolide->sousSeuil }}</p>
            <p class="text-[11px] text-slate-400 mt-0.5">{{ __('stocks_pwa.liste.kpi_sous_seuil_detail') }}</p>
          </div>
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <p class="text-[10px] font-bold uppercase tracking-wider text-slate-400">{{ __('stocks_pwa.liste.kpi_mouvements') }}</p>
            <p class="text-lg font-bold mt-0.5 text-[var(--navy)]">{{ $consolide->mouvements30Jours }}</p>
          </div>
          {{--
              « Gros / petit stock » — maître l.174. Il rendait « — » faute de
              colonne `suivi` ; elle existe depuis PA-161 (a), et le compte est
              réel. Il porte sur TOUT le référentiel de la portée, comme les
              alarmes : masquer les articles sains ne change pas la
              répartition du parc.
          --}}
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <p class="text-[10px] font-bold uppercase tracking-wider text-slate-400">{{ __('stocks_pwa.liste.kpi_suivi') }}</p>
            <p class="text-lg font-bold mt-0.5 text-[var(--navy)]">{{ __('stocks_pwa.liste.kpi_suivi_valeur', ['permanents' => $consolide->permanents, 'journaliers' => $consolide->journaliers]) }}</p>
            <p class="text-[11px] text-slate-400 mt-0.5">{{ __('stocks_pwa.liste.kpi_suivi_detail') }}</p>
          </div>
        </div>

        {{-- ===================== FILTRES — maître l.43-69 ===================== --}}
        <div class="bg-white rounded-xl border border-slate-200 p-3.5 mb-4 no-print">
          <div class="flex flex-wrap gap-2.5 items-center">
            <div class="relative flex-1 min-w-[220px]">
              <svg class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
              <input type="search" wire:model.live.debounce.400ms="recherche"
                     placeholder="{{ __('stocks_pwa.liste.rechercher') }}"
                     class="w-full text-[13px] border border-slate-300 rounded-lg pl-9 pr-3 py-2 focus:border-[var(--gold)] focus:outline-none">
            </div>

            <select wire:model.live="categorie" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <option value="">{{ __('stocks_pwa.liste.toutes_categories') }}</option>
              @foreach ($categories as $libelle)
                <option value="{{ $libelle }}">{{ $libelle }}</option>
              @endforeach
            </select>

            <select wire:model.live="point" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <option value="">{{ __('stocks_pwa.liste.tous_points') }}</option>
              @foreach ($points as $lieu)
                <option value="{{ $lieu->id }}">{{ $lieu->libelle }}</option>
              @endforeach
            </select>

            {{--
                maître l.52-56 — « Tous les suivis ». Les VALEURS sont celles
                du registre fermé `Article::SUIVIS` (donc de l'`enum` au
                schéma), les LIBELLÉS ceux du maître. Ce filtre était refusé
                jusqu'au 02/09/2026, faute de colonne : PA-161 (a) l'a créée.
            --}}
            <select wire:model.live="suivi" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <option value="">{{ __('stocks_pwa.liste.tous_suivis') }}</option>
              <option value="permanent">{{ __('stocks_pwa.liste.suivi_permanent') }}</option>
              <option value="journalier">{{ __('stocks_pwa.liste.suivi_journalier') }}</option>
            </select>

            {{--
                Les VALEURS sont celles du registre fermé
                `ConsultationStockService::ETATS`, les LIBELLÉS ceux du maître
                (l.59-60). Le maître écrit `critique` là où le service dit
                `sous_seuil` : c'est le mot du service qui circule en URL et en
                requête, celui du maître qui s'affiche.
            --}}
            <select wire:model.live="etat" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <option value="">{{ __('stocks_pwa.liste.tous_etats') }}</option>
              <option value="sous_seuil">{{ __('stocks_pwa.liste.etat_sous_seuil') }}</option>
              <option value="rupture">{{ __('stocks_pwa.liste.etat_rupture') }}</option>
            </select>

            <div class="flex-1"></div>

            <button type="button" wire:click="ouvrirImport"
                    class="text-[12px] px-3 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('stocks_pwa.liste.importer') }}</button>
            <button type="button" wire:click="telechargerModeleCsv"
                    class="text-[12px] px-3 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('stocks_pwa.liste.modele') }}</button>
            {{-- ⚠ DÉROGATION PO du 01/09/2026 — les deux boutons du maître
                 (`m6-stocks.html` l.65-66, « Excel » / « PDF ») sont
                 remplacés par UN bouton « Exporter » qui ouvre la même
                 modale d'export ; le format s'y choisit (PDF/Excel), sans
                 présélection imposée. Registre :
                 `App\Pwa\Support\DerogationsMaquette` (export_bouton_unique).
                 Jeton : maitre-refuse:m6-stocks.html#page --}}
            <button type="button" wire:click="ouvrirExport"
                    class="text-[12px] px-3 py-2 rounded-lg bg-[var(--navy)] text-white hover:opacity-90">{{ __('pwa.export.bouton') }}</button>
          </div>
        </div>

        {{--
            maître l.380-383 — le refus de mouvement sur un article journalier.
            Le maître le rend en `Toast.alerte`, pas en fenêtre : rien ne
            s'ouvre, donc rien n'est à fermer. Il s'efface seul, comme le
            toast, plutôt que de rester à l'écran jusqu'au prochain clic.
        --}}
        @if ($mvtRefusJournalier !== null)
          <div wire:key="refus-journalier" class="mb-4 rounded-xl px-4 py-3 text-[13px] no-print"
               style="background:#FFFBEB;color:#78350F;border:1px solid #FDE68A"
               x-data="{ visible: true }" x-show="visible"
               x-init="setTimeout(() => visible = false, 6000)">{{ $mvtRefusJournalier }}</div>
        @endif

        {{-- Barre de sélection groupée du maître (crud-ui.js l.36-46), rendue
             ici parce que « Supprimer » existe désormais (demande du Product
             Owner du 03/09/2026). Elle ARCHIVE : `ReferentielArticleService`
             pose `actif = false`, et aucun `delete()` n'existe dans ce dépôt.
             structure-ajout:m6-stocks.html#barre-selection
             structure-ajout:m6-stocks.html#div-20a2b0c8
             ⚠ Le second jeton nomme le bloc tel que le comparateur le
             DESIGNE (`div-20a2b0c8`) : le premier est lisible, le second
             est celui qu'il exige — les deux sont conserves pour que la
             declaration se retrouve aussi bien a la lecture qu'a la
             mesure. Le conteneur de tableau qui suit change de rang du
             fait de cet ajout, d'ou son propre jeton :
             structure-ajout:m6-stocks.html#div-f1c8b22c --}}
        @if ($peutArchiver && $selection !== [])
          <div class="flex items-center gap-3 bg-[var(--navy)] text-white rounded-lg px-4 py-2.5 mb-3 text-xs no-print">
            <span>{!! __('stocks_pwa.archivage.selectionnes', ['nombre' => '<strong>' . count($selection) . '</strong>']) !!}</span>
            <div class="flex-1"></div>
            <button type="button" wire:click="confirmerArchivageArticle"
                    class="underline decoration-white/40 hover:decoration-white">{{ __('stocks_pwa.archivage.bouton_lot') }}</button>
            <button type="button" wire:click="$set('selection', [])" class="text-white/60 hover:text-white"
                    aria-label="{{ __('pwa.modale.annuler') }}">✕</button>
          </div>
        @endif

        {{-- ===================== TABLEAU — maître l.182-246 ===================== --}}
        <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
          <div class="px-4 py-2.5 border-b border-slate-200 flex items-center justify-between">
            <span class="text-[12px] text-slate-500">{{ __('stocks_pwa.liste.nombre_articles', ['nombre' => $lignes->total()]) }}</span>
            <span class="text-[11px] text-slate-400">{{ __('stocks_pwa.liste.stock_non_modifiable') }}</span>
          </div>

          @if ($lignes->isEmpty())
            {{-- État vide — icône loupe, titre générique, détail du maître. --}}
            <div class="p-10 text-center">
              <svg class="mx-auto mb-3 text-slate-300" width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
              <p class="text-[15px] font-semibold" style="color:var(--navy)">{{ __('stocks_pwa.liste.vide_titre') }}</p>
              <p class="text-[13px] text-slate-500 mt-1">{{ __('stocks_pwa.liste.vide_detail') }}</p>
            </div>
          @else
            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)] text-[11px] uppercase tracking-wide text-white/90 font-semibold">
                  <tr>
                    {{-- Case « tout sélectionner » (crud-ui.js l.66). Elle
                         n'existe que pour le geste d'archivage, et n'est donc
                         rendue que pour qui peut archiver : une case sans
                         action serait un contrôle qui n'ouvre rien.
                         structure-ajout:m6-stocks.html#colonne-selection --}}
                    @if ($peutArchiver)
                      <th class="px-4 py-2.5 w-10">
                        <input type="checkbox" wire:model.live="toutSelectionne" class="w-4 h-4 rounded"
                               aria-label="{{ __('stocks_pwa.archivage.selection_tout') }}">
                      </th>
                    @endif
                    @foreach ($colonnes as $colonne)
                      <th class="{{ $colonne['droite'] ? 'text-right' : 'text-left' }} px-4 py-2.5">{{ __('stocks_pwa.liste.'.$colonne['cle']) }}</th>
                    @endforeach
                  </tr>
                </thead>
                <tbody>
                  @foreach ($lignes as $ligne)
                    @php
                        // maître l.209-220 : les trois valeurs dérivées de la
                        // ligne, calculées une fois plutôt que trois dans les
                        // cellules. `$derive` vaut `null` — pas 0 — quand la
                        // dérive n'est pas mesurable (aucun prix d'achat).
                        $journalier = ! $ligne->article->estSuiviEnStock();
                        $derive = $ligne->article->deriveCoutMoyenPondere();
                    @endphp
                    <tr wire:key="article-{{ $ligne->article->id }}" class="border-t border-slate-100 hover:bg-slate-50/60">
                      @if ($peutArchiver)
                        <td class="px-4 py-2.5">
                          <input type="checkbox" value="{{ $ligne->article->id }}" wire:model.live="selection"
                                 class="w-4 h-4 rounded" aria-label="{{ __('stocks_pwa.archivage.selection_ligne') }}">
                        </td>
                      @endif
                      <td class="px-4 py-2.5 font-medium">
                        {{ $ligne->article->libelle }}
                        {{-- Un article ARCHIVÉ reste dans la liste, marqué. Le
                             masquer le rendrait indiscernable d'un article
                             inexistant, et « reste restaurable » ne serait
                             tenue nulle part (PA-59/60/61). --}}
                        @unless ($ligne->article->actif)
                          <span class="ml-1 text-[10px] px-1.5 py-0.5 rounded"
                                style="background:#F3F4F6;color:#6B7280">{{ __('stocks_pwa.archivage.badge') }}</span>
                        @endunless
                      </td>

                      <td class="px-4 py-2.5 text-slate-600">{{ $ligne->article->categorie }}</td>

                      {{-- 02/09/2026 — « Unité » en colonne (garde G5, maître
                           l.464). L'écran du maître la rendait entre
                           parenthèses à côté du libellé (l.225-226) ; elle
                           n'est pas rendue deux fois par ligne. --}}
                      <td class="px-4 py-2.5 text-slate-600">{{ $ligne->article->unite_mesure }}</td>

                      {{-- maître l.227 — « Point ». C'est le RATTACHEMENT de
                           l'article, jamais la portée de son stock. « — » avec
                           sa raison quand il n'a jamais été réceptionné. --}}
                      <td class="px-4 py-2.5 text-slate-600">
                        @if ($ligne->article->pointStockage !== null)
                          {{ $ligne->article->pointStockage->libelle }}
                        @else
                          <span class="text-slate-300" title="{{ __('stocks_pwa.liste.jamais_receptionne') }}">{{ MontantFcfa::TIRET }}</span>
                        @endif
                      </td>

                      {{-- maître l.229-233 — « Suivi », en badge. --}}
                      <td class="px-4 py-2.5">
                        <span class="px-2 py-0.5 rounded text-[11px] font-semibold {{ $journalier ? 'bg-slate-100 text-slate-600' : 'bg-blue-50 text-blue-700' }}">{{ $journalier ? __('stocks_pwa.liste.badge_journalier') : __('stocks_pwa.liste.badge_permanent') }}</span>
                      </td>

                      {{-- maître l.234-236 : un article journalier affiche
                           « non suivi », pas « 0 » — qui se lirait comme une
                           rupture, sur une marchandise dont personne ne tient
                           le compte. --}}
                      <td class="px-4 py-2.5 text-right {{ $journalier ? 'text-slate-300' : ($ligne->rupture ? 'text-red-600 font-bold' : ($ligne->sousSeuil ? 'text-amber-600 font-bold' : 'font-semibold')) }}">{{ $journalier ? __('stocks_pwa.liste.stock_non_suivi') : $ligne->stock }}</td>

                      {{-- maître l.237 : le seuil n'a pas de sens sans stock. --}}
                      <td class="px-4 py-2.5 text-right text-slate-400">{{ $journalier ? MontantFcfa::TIRET : $ligne->article->seuil_alerte }}</td>

                      {{-- maître l.238 — « Valeur d'achat » : le DERNIER prix
                           d'achat connu, jamais le CMP. --}}
                      <td class="px-4 py-2.5 text-right">
                        @if ($ligne->article->prix_achat !== null)
                          {{ MontantFcfa::format((string) $ligne->article->prix_achat) }}
                        @else
                          <span class="text-slate-300" title="{{ __('stocks_pwa.liste.jamais_receptionne') }}">{{ MontantFcfa::TIRET }}</span>
                        @endif
                      </td>

                      {{-- maître l.239-243 : la dérive du CMP contre le prix
                           d'achat, en pourcentage, à côté du CMP. Elle n'est
                           rendue que lorsqu'elle est mesurable ET non nulle —
                           « +0 % » sur un article jamais réceptionné
                           affirmerait une stabilité que rien n'a mesurée. --}}
                      <td class="px-4 py-2.5 text-right">{{ MontantFcfa::format((string) $ligne->article->cout_moyen_pondere) }}
                        @if ($derive !== null && $derive !== 0)
                          <span class="ml-1 text-[10px] {{ $derive > 0 ? 'text-red-500' : 'text-emerald-600' }}">{{ $derive > 0 ? '+' : '' }}{{ $derive }}%</span>
                        @endif
                      </td>

                      <td class="px-4 py-2.5 text-right font-semibold">{{ $journalier ? MontantFcfa::TIRET : MontantFcfa::format($ligne->valeur) }}</td>

                      <td class="px-4 py-2.5 text-right whitespace-nowrap no-print">
                        <a href="{{ route('pwa.stocks.inventaires', ['article' => $ligne->article->id]) }}" wire:navigate
                           class="text-[12px] px-2 py-1 rounded-lg border border-slate-300 hover:bg-white">{{ __('stocks_pwa.liste.action_fiche') }}</a>
                        <button type="button" wire:click="ouvrirMouvement('{{ $ligne->article->id }}')"
                                class="text-[12px] px-2 py-1 rounded-lg border border-slate-300 hover:bg-white ml-1">{{ __('stocks_pwa.liste.action_mouvement') }}</button>
                        <button type="button" wire:click="editerArticle('{{ $ligne->article->id }}')"
                                class="text-[12px] px-2 py-1 rounded-lg border border-slate-300 hover:bg-white ml-1">{{ __('stocks_pwa.liste.action_modifier') }}</button>
                        {{-- « Supprimer » du maître (crud-ui.js l.100), rendu
                             ici comme ARCHIVAGE : le mot du bouton est celui
                             que le client a validé, le geste pose `actif =
                             false`.
                             structure-ajout:m6-stocks.html#bouton-supprimer --}}
                        @unless ($ligne->article->actif)
                          <button type="button" wire:click="restaurerArticle('{{ $ligne->article->id }}')"
                                  class="text-[12px] px-2 py-1 rounded-lg border border-slate-300 hover:bg-white ml-1">{{ __('stocks_pwa.archivage.bouton_restaurer') }}</button>
                        @else
                          @if ($peutArchiver)
                            <button type="button" wire:click="confirmerArchivageArticle('{{ $ligne->article->id }}')"
                                    class="text-[12px] px-2 py-1 rounded-lg border border-red-200 text-[var(--erreur)] hover:bg-red-50 ml-1">{{ __('stocks_pwa.archivage.bouton_ligne') }}</button>
                          @endif
                        @endunless
                      </td>
                    </tr>
                  @endforeach
                </tbody>
              </table>
            </div>

            @if ($lignes->hasPages())
              <div class="px-4 py-3 border-t border-slate-200 flex items-center justify-between no-print">
                <span class="text-[12px] text-slate-500">{{ $lignes->firstItem() }} – {{ $lignes->lastItem() }} / {{ $lignes->total() }}</span>
                <div class="flex gap-2">
                  <button type="button" wire:click="previousPage" @disabled($lignes->onFirstPage())
                          class="text-[12px] px-3 py-1.5 rounded-lg border border-slate-300 hover:bg-slate-50 disabled:opacity-40">{!! __('pagination.previous') !!}</button>
                  <button type="button" wire:click="nextPage" @disabled(! $lignes->hasMorePages())
                          class="text-[12px] px-3 py-1.5 rounded-lg border border-slate-300 hover:bg-slate-50 disabled:opacity-40">{!! __('pagination.next') !!}</button>
                </div>
              </div>
            @endif
          @endif
        </div>

      </div>
    </main>
  </div>

  {{--
      ===================== MODALES =====================

      Toutes passent par le châssis partagé `<x-pwa.modale>` : il porte
      `.overlay-modale` + `.boite-modale`, donc le voile `rgba(0,0,0,.5)`, le
      flou de 2 px, le rayon de 12 px et surtout `max-height:90vh;
      overflow-y:auto` — sans quoi une modale plus haute que la fenêtre est
      tronquée et son bouton « Enregistrer » inatteignable.

      ⚠ Aucune n'est rendue au premier GET : le formulaire n'apparaît qu'après
      une action gardée par `exigerEcriture(self::MODULE)`. C'est ce qui rend
      `RefuseLaSaisie` et le régime CRUD compatibles.
  --}}

  @if ($etatFormulaire === 'article')
    <x-pwa.modale
      :titre="$articleId === null ? __('stocks_pwa.article.titre_creation') : __('stocks_pwa.article.titre_edition')"
      :sousTitre="$articleId === null ? __('stocks_pwa.article.sous_titre_creation') : $libelle"
      largeur="560px">

      <div>
        <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.article.nom') }}</label>
        <input type="text" wire:model="libelle" placeholder="{{ __('stocks_pwa.article.nom_invite') }}"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 focus:border-[var(--gold)] focus:outline-none">
        @error('libelle') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <div>
        <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.article.categorie') }}</label>
        <select wire:model="categorieSaisie" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @foreach ($categories as $libelleCategorie)
            <option value="{{ $libelleCategorie }}">{{ $libelleCategorie }}</option>
          @endforeach
        </select>
        @error('categorieSaisie') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <div>
        <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.article.unite') }}</label>
        <select wire:model="uniteSaisie" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @foreach ($unites as $unite)
            <option value="{{ $unite }}">{{ $unite }}</option>
          @endforeach
        </select>
        @error('uniteSaisie') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      {{--
          maître l.304 — « Point de stockage », en CRÉATION comme en
          MODIFICATION. Il n'était offert qu'à la création tant que la colonne
          n'existait pas : un article mal classé aurait été incorrigible.
      --}}
      <div>
        <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.article.point') }}</label>
        <select wire:model="pointOuverture" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @if ($articleId !== null)
            <option value="">{{ MontantFcfa::TIRET }}</option>
          @endif
          @foreach ($points as $lieu)
            <option value="{{ $lieu->id }}">{{ $lieu->libelle }}</option>
          @endforeach
        </select>
        <p class="text-[11px] text-slate-400 mt-1">{{ __('stocks_pwa.article.point_aide') }}</p>
        @error('pointOuverture') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      {{--
          maître l.312-315 — « Mode de suivi ». `.live` parce que le maître
          masque le seuil et le stock d'ouverture dès que « journalier » est
          choisi (l.342-346) : les deux n'ont pas de sens sans stock tenu.
      --}}
      <div>
        <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.article.suivi') }}</label>
        <select wire:model.live="suiviSaisi" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @foreach ($suivis as $code => $libelleSuivi)
            <option value="{{ $code }}">{{ $libelleSuivi }}</option>
          @endforeach
        </select>
        <p class="text-[11px] text-slate-400 mt-1">{{ __('stocks_pwa.article.suivi_aide') }}</p>
        @error('suiviSaisi') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      @if ($articleId === null)
        {{-- maître l.306-310 : l'encadré ambre autour de la valeur d'achat.
             Elle n'est saisissable qu'à la CRÉATION : elle valorise l'entrée
             d'ouverture, qui est ce qui la pose réellement. --}}
        <div class="rounded-lg bg-amber-50 border border-amber-200 p-3">
          <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.article.valeur_achat') }}</label>
          <input type="number" min="0" step="1" wire:model="valeurAchat" placeholder="{{ __('stocks_pwa.article.valeur_achat_invite') }}"
                 class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 focus:border-[var(--gold)] focus:outline-none">
          <p class="text-[11px] text-slate-400 mt-1">{{ __('stocks_pwa.article.valeur_achat_aide') }}</p>
          @error('valeurAchat') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
      @endif

      {{-- maître l.319-333 (`#bloc-permanent`) : le seuil et le stock
           d'ouverture disparaissent en suivi journalier — « le petit stock
           n'est ni décrémenté à la vente, ni inventorié, ni alerté ». --}}
      @if ($suiviSaisi !== 'journalier')
        <div>
          <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.article.seuil') }}</label>
          <input type="number" min="0" step="0.01" wire:model="seuilAlerte"
                 class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 focus:border-[var(--gold)] focus:outline-none">
          <p class="text-[11px] text-slate-400 mt-1">{{ __('stocks_pwa.article.seuil_aide') }}</p>
          @error('seuilAlerte') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>

        @if ($articleId === null)
          <div>
            <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.article.stock_ouverture') }}</label>
            <input type="number" min="0" step="0.01" wire:model="stockOuverture"
                   class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 focus:border-[var(--gold)] focus:outline-none">
            <p class="text-[11px] text-slate-400 mt-1">{{ __('stocks_pwa.article.stock_ouverture_aide') }}</p>
            @error('stockOuverture') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
        @endif
      @endif

      {{--
          ENTRÉE DE STOCK DEPUIS LA FICHE — directive PO du 06/09/2026.

          « Niveau stock, permettre de modifier le stock dans le modal Modifier
          l'article. » Jusqu'ici, corriger un stock depuis cette fenêtre était
          impossible : le stock d'ouverture n'existait qu'à la création, et
          `enregistrerArticle()` rendait la main avant lui en édition.

          ⚠ CE N'EST PAS UN CHAMP « stock ». Le récapitulatif juste en dessous
          rend le stock CALCULÉ, en lecture seule, comme avant. Ce qui se
          saisit ici est une ENTRÉE, écrite par `MouvementStockService` — un
          champ qui écraserait le stock serait la deuxième des sept règles du
          projet prise à revers.

          Rendu pour les seuls rôles d'administration, et retiré sinon plutôt
          que grisé (Article 3.3). Absent aussi en suivi journalier : un article
          acheté au marché chaque matin n'a pas de stock à tenir.
          structure-ajout:m6-stocks.html#bloc-entree-stock
      --}}
      @if ($articleId !== null && $peutAjusterLeStock && $suiviSaisi !== 'journalier')
        <div class="rounded-lg bg-emerald-50 border border-emerald-200 p-3">
          <p class="text-[11px] font-semibold text-slate-600 mb-2">{{ __('stocks_pwa.article.entree_titre') }}</p>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.article.entree_quantite') }}</label>
              <input type="number" min="0" step="0.01" wire:model="entreeQuantite"
                     class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 focus:border-[var(--gold)] focus:outline-none">
              @error('entreeQuantite') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
            </div>

            <div>
              <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.article.entree_point') }}</label>
              <select wire:model="entreePoint" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
                @foreach ($points as $point)
                  <option value="{{ $point->id }}">{{ $point->libelle }}</option>
                @endforeach
              </select>
              @error('entreePoint') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
            </div>
          </div>

          <div class="mt-3">
            <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.article.entree_cout') }}</label>
            <input type="number" min="0" step="1" wire:model="entreeCout"
                   class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 focus:border-[var(--gold)] focus:outline-none">
            @error('entreeCout') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>

          <p class="text-[11px] text-slate-500 mt-2">{{ __('stocks_pwa.article.entree_aide') }}</p>
        </div>
      @endif

      @if ($articleId !== null && $recapitulatif !== null)
        {{-- maître l.320-330 : en édition, les trois chiffres sont en LECTURE
             SEULE et le stock ne se corrige que par un mouvement. --}}
        <div class="rounded-lg bg-slate-50 border border-slate-200 p-3 text-[12px] text-slate-600">
          {{-- ÉCART DÉCLARÉ avec le maître (l.307-310), qui rend « Valeur
               d'achat unitaire » ÉDITABLE en modification. Elle est ici en
               lecture seule : elle est posée par l'entrée de stock, seul geste
               qui l'établit et le seul qui laisse une trace en fiche. --}}
          <div class="flex justify-between mb-1"><span>{{ __('stocks_pwa.article.recap_valeur_achat') }}</span>
            <strong>{{ $recapitulatif['prix_achat'] ?? __('stocks_pwa.article.recap_valeur_achat_absente') }}</strong></div>
          <div class="flex justify-between mb-1"><span>{{ __('stocks_pwa.article.recap_stock') }}</span>
            <strong>{{ $recapitulatif['stock'] }} {{ $recapitulatif['unite'] }}</strong></div>
          <div class="flex justify-between mb-1"><span>{{ __('stocks_pwa.article.recap_cmp') }}</span>
            <strong>{{ $recapitulatif['cmp'] }}</strong></div>
          <div class="flex justify-between"><span>{{ __('stocks_pwa.article.recap_valeur') }}</span>
            <strong>{{ $recapitulatif['valeur'] }}</strong></div>
          <p class="mt-2 text-[11px] text-slate-400">{{ __('stocks_pwa.article.recap_valeur_achat_note') }}</p>
          <p class="mt-1 text-[11px] text-slate-400">{{ __('stocks_pwa.article.recap_note') }}</p>
        </div>
      @endif

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerArticle"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ $articleId === null ? __('stocks_pwa.article.valider_creation') : __('stocks_pwa.article.valider_edition') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  @if ($etatFormulaire === 'mouvement')
    <x-pwa.modale :titre="__('stocks_pwa.mouvement.titre')"
                  :sousTitre="$articleMouvemente?->libelle"
                  largeur="560px">

      {{-- maître l.386-390 : le rappel du stock et du CMP, en tête de modale. --}}
      <div class="rounded-lg bg-slate-50 border border-slate-200 p-3 mb-4 text-[12px]">
        <div class="flex justify-between"><span class="text-slate-500">{{ __('stocks_pwa.mouvement.stock_actuel') }}</span>
          <strong>{{ $stockMouvemente }} {{ $articleMouvemente?->unite_mesure }}</strong></div>
        <div class="flex justify-between"><span class="text-slate-500">{{ __('stocks_pwa.mouvement.cmp') }}</span>
          <strong>{{ MontantFcfa::format((string) ($articleMouvemente?->cout_moyen_pondere ?? '0')) }}</strong></div>
      </div>

      <div>
        <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.mouvement.type') }}</label>
        <select wire:model.live="mvtType" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          <option value="entree">{{ __('stocks_pwa.mouvement.type_entree') }}</option>
          <option value="sortie">{{ __('stocks_pwa.mouvement.type_sortie') }}</option>
          <option value="perte">{{ __('stocks_pwa.mouvement.type_perte') }}</option>
        </select>
        @error('mvtType') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <div>
        <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.mouvement.point') }}</label>
        <select wire:model="mvtPoint" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @forelse ($points as $lieu)
            <option value="{{ $lieu->id }}">{{ $lieu->libelle }}</option>
          @empty
            <option value="">{{ __('stocks_pwa.mouvement.aucun_point') }}</option>
          @endforelse
        </select>
        @error('mvtPoint') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <div>
        <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.mouvement.quantite') }}</label>
        <input type="number" min="0.01" step="0.01" wire:model="mvtQuantite"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 focus:border-[var(--gold)] focus:outline-none">
        @error('mvtQuantite') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      {{--
          maître l.398-408 (`majCout`) : le bloc de coût DISPARAÎT dès que le
          type n'est pas « entrée ». Une sortie est valorisée au coût moyen
          pondéré du moment et ne le modifie pas — offrir le champ laisserait
          croire le contraire.
      --}}
      @if ($mvtType === 'entree')
        <div>
          <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.mouvement.cout') }}</label>
          <input type="number" min="0" step="1" wire:model="mvtCout"
                 class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 focus:border-[var(--gold)] focus:outline-none">
          <p class="text-[11px] text-slate-400 mt-1">{{ __('stocks_pwa.mouvement.cout_aide') }}</p>
          @error('mvtCout') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
      @endif

      <div>
        <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.mouvement.motif') }}</label>
        <input type="text" wire:model="mvtMotif" placeholder="{{ __('stocks_pwa.mouvement.motif_invite') }}"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 focus:border-[var(--gold)] focus:outline-none">
        @error('mvtMotif') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerMouvement"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('stocks_pwa.mouvement.valider') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  @if ($etatFormulaire === 'rupture')
    {{--
        RG-06 — la rupture n'est pas une erreur définitive : c'est une demande
        de confirmation explicite auprès d'un utilisateur habilité. Le message
        est celui du DOMAINE, qui chiffre le disponible et le demandé.
    --}}
    <x-pwa.modale :titre="__('stocks_pwa.mouvement.rupture_titre')"
                  :sousTitre="$mvtRupture"
                  largeur="448px">
      <p class="text-[13px] text-slate-600">{{ __('stocks_pwa.mouvement.rupture_detail') }}</p>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="forcerMouvement"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--erreur)] text-white font-semibold hover:opacity-90">{{ __('stocks_pwa.mouvement.rupture_confirmer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  @if ($etatFormulaire === 'import')
    <x-pwa.modale :titre="__('stocks_pwa.import.titre')"
                  :sousTitre="__('stocks_pwa.import.sous_titre')"
                  largeur="560px">
      <div>
        <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.import.fichier') }}</label>
        <input type="file" accept=".csv,text/csv" wire:model="fichierImport"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
        <p class="text-[11px] text-slate-400 mt-1">{{ __('stocks_pwa.import.colonnes', ['colonnes' => implode(' ; ', App\Pwa\Livewire\Stocks\Stocks::COLONNES_IMPORT)]) }}</p>
        @error('fichierImport') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      @if ($lignesRefusees !== [])
        {{-- Les lignes fautives sont NOMMÉES, une par une : refuser le lot
             entier obligerait à tout refaire pour une coquille. --}}
        <ul class="list-disc pl-5 space-y-1 max-h-40 overflow-y-auto">
          @foreach ($lignesRefusees as $refusee)
            <li class="text-[12px] text-red-700">{{ $refusee }}</li>
          @endforeach
        </ul>
      @endif

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="lancerImport"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('stocks_pwa.import.valider') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ============ ARCHIVAGE — « Confirmer la suppression » du maitre
       (crud-ui.js l.123-140), servi par le chassis partage. Le titre et le
       bouton gardent les mots du maitre ; le corps dit ce qui a reellement
       lieu — l'article part aux archives. --}}
  @if ($etatFormulaire === 'archivage')
    <x-pwa.modale-archivage action="archiverArticles"
                            :element="$libelleArchivage !== '' ? $libelleArchivage : null"
                            :nombre="$libelleArchivage === '' ? count($articlesAArchiver) : null"
                            :messagesVerrou="$verrousArchivage"
                            :bloque="$archivageBloque"
                            :conserves="$conservesArchivage" />
  @endif

  {{-- Le refus d'archivage est rendu HORS de la modale, et c'est le correctif
       d'un defaut reel trouve a la relecture du 03/09/2026 : le geste ferme la
       modale (`etatFormulaire = null`) avant de rendre, si bien qu'un toast
       pose a l'interieur du `@if` n'apparaissait JAMAIS. Le refus du Service —
       celui qui tombe quand un engagement est ne entre l'ouverture et le clic
       — serait reste silencieux, et l'ecran aurait eu l'air d'avoir archive. --}}
  @error('archivage')
    <div class="fixed bottom-5 right-5 z-50 px-4 py-3 rounded-xl bg-red-600 text-white text-[13px] no-print">{{ $message }}</div>
  @enderror

  @if ($etatFormulaire === 'export')
    {{-- La modale d'export est PARTAGÉE : onze vues en portaient une copie sous
         dix titres différents. Le titre nomme ce qui sera exporté, le
         sous-titre DIT le filtre appliqué (PA-119). --}}
    @include('pwa.partials.modale-export', [
      'titre' => __('stocks_pwa.export.titre_stocks'),
      'sousTitre' => __('stocks_pwa.export.sous_titre_filtre', ['filtres' => $filtresAffiches]),
    ])
  @endif
</div>

{{--
    ÉCRAN « INVENTAIRES & FICHES DE STOCK » (M6).

    Maître : `prototype_v2/pages/m6-inventaires.html`.

    ## EXCLU de la barre de recherche par table (PO, 01/09/2026)

    Les QUATRE tableaux de cet écran sont déjà filtrés autrement, et une
    recherche texte y serait soit redondante soit sans objet :
      — « Mouvements » (le grand-livre d'UN article) : le sélecteur d'article
        (`wire:model.live="articleId"`) EST déjà le filtre — même motif que
        `App\Pwa\Livewire\Comptabilite\GrandLivre`, un compte à la fois.
      — « Feuille de comptage » : la liste de travail d'UN inventaire en
        cours, bornée aux articles du point compté — un texte de recherche
        n'a rien à filtrer sur une liste qu'on parcourt entièrement.
      — « Cycle d'inventaire » : une ligne par magasin, quelques lignes.
      — « Historique » : les inventaires clôturés, également borné.
    Le maître (`m6-inventaires.html`) ne pose d'ailleurs aucune barre de
    recherche sur cette page — mesuré, pas supposé.

    ## Trois écarts assumés, nommés ici plutôt que découverts plus tard

    1. **Le comptage passe par une MODALE, pas par un champ dans la ligne.**
       Le maître pose un `<input type="number" data-comptage>` sur chaque ligne
       du tableau (l.451-457). Un champ d'écriture rendu au premier GET est
       servi à un rôle en lecture seule AVANT toute garde — c'est la règle que
       `tests/Feature/Pwa/Concerns/RefuseLaSaisie` tient sur chaque page, et
       elle est plus forte que la commodité de saisie. Le bouton « Compter »
       ouvre la modale, gardée par `exigerEcriture(self::MODULE)`.

    2. maitre-refuse:m6-inventaires.html#colonne-par — la colonne « Par » du détail
       des mouvements rend « — ». `mouvements_stock.utilisateur_id` existe, mais
       `FicheStockService::pourArticle()` ne le remonte pas ; le lire ici
       exigerait une seconde requête par ligne, et surtout une seconde source
       pour un document qui doit n'en avoir qu'une.

    3. maitre-refuse:m6-inventaires.html#cycle-inventaire — le panneau « Cycle
       d'inventaire par magasin » (périodicité journalière, hebdomadaire, par
       quinzaine, mensuelle) n'est pas rendu : aucune table ne porte de
       périodicité, et l'échéance se calcule depuis le dernier inventaire
       CLÔTURÉ — un état que le schéma ne distingue pas (PA-150). Afficher « à
       jour » ou « en retard de N jours » serait un indicateur qui affirme un
       état qu'il n'a pas vérifié.

    ## PA-150 — aucun statut d'inventaire au schéma

    L'onglet « Inventaires clôturés » montre TOUS les inventaires et le DIT.
    Ses colonnes « Manquants » et « Excédents » rendent « — » : seule la
    clôture les produit, et rien ici n'atteste qu'elle a eu lieu.

    ## PA-135 — « 7 jours » couvre SEPT jours, aujourd'hui compris

    Les raccourcis sont des LIENS : `du` et `au` restent dans l'URL, ce qui rend
    une fiche partageable et rechargeable telle quelle.
--}}
@php
    use App\Pwa\Support\MontantFcfa;

    // Classes d'onglets : directive PO du 01/09/2026, UN SEUL AUTEUR —
    // voir le docblock de `App\Pwa\Support\Onglets`.
    $classeOnglet = static fn (bool $actif): string => \App\Pwa\Support\Onglets::classes($actif);

    // maître l.257-263 : les libellés et les couleurs des quatre types.
    $libelleType = [
        'entree' => __('stocks_pwa.inventaires.type_entree'),
        'sortie' => __('stocks_pwa.inventaires.type_sortie'),
        'perte' => __('stocks_pwa.inventaires.type_perte'),
        'inventaire' => __('stocks_pwa.inventaires.type_inventaire'),
    ];
    $couleurType = [
        'entree' => 'bg-emerald-50 text-emerald-700',
        'sortie' => 'bg-blue-50 text-blue-700',
        'perte' => 'bg-red-50 text-red-700',
        'inventaire' => 'bg-amber-50 text-amber-700',
    ];

    // Le signe MOINS du maître (U+2212), écrit par son point de code : le
    // transcrire à la main confondrait avec le tiret ASCII, et l'écart ne se
    // verrait qu'à l'impression.
    $moins = "\u{2212}";

    $lienPeriode = static fn (array $r, string $onglet, string $article, string $point): string => route(
        'pwa.stocks.inventaires',
        ['onglet' => $onglet, 'article' => $article, 'point' => $point, 'du' => $r['du'], 'au' => $r['au']],
    );
@endphp

<div class="contents">

  {{-- SQUELETTE — ajouts DÉCLARÉS (01/09/2026, vague G) : l'étape 1
     « Cycle d'inventaire par magasin » (tableau des points + Lancer
     l'inventaire) est la marche du maître portée en DEUX temps — le
     comparateur ne lisant que la première branche, ses blocs sont déclarés.
     structure-ajout:m6-inventaires.html#h2-85b20550
     structure-ajout:m6-inventaires.html#div-8c8a5efc
     structure-ajout:m6-inventaires.html#div-6d936ab7 --}}
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

        {{-- EN-TÊTE INSTITUTIONNEL D'IMPRESSION — `<h2>`, jamais `<h1>` (G2). --}}
        <div class="hidden print:block mb-6 border-b-2 border-[var(--navy)] pb-4">
          <h2 class="text-xl font-bold" style="color:var(--navy)">TATACORA AFRIQUE — GÎTE CHEZ NOËL</h2>
          <p class="text-xs text-slate-600 mt-1">{{ __('stocks_pwa.inventaires.titre') }} — {{ now()->format('d/m/Y H:i') }}</p>
        </div>

        {{-- ===================== EN-TÊTE DE PAGE — maître l.22-33 ===================== --}}
        <div class="mb-5 flex flex-wrap items-start justify-between gap-3 no-print">
          <div>
            <div class="flex items-center gap-2.5">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11"/></svg>
              <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('stocks_pwa.inventaires.titre') }}</h1>
            </div>
            <p class="text-[15px] text-slate-500 mt-1.5">
              {{ __('stocks_pwa.inventaires.sous_titre') }}
              <strong>{{ __('stocks_pwa.inventaires.sous_titre_fort') }}</strong>{{ __('stocks_pwa.inventaires.sous_titre_fin') }}
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <a href="{{ route('pwa.stocks.liste') }}" wire:navigate
               class="text-[13px] px-3.5 py-2 rounded-lg border border-slate-300 bg-white hover:bg-slate-50">{{ __('stocks_pwa.liste.titre') }}</a>
          </div>
        </div>

        @if (session('pwa-succes'))
          <div class="mb-4 rounded-xl px-4 py-3 text-[13px] no-print"
               style="background:#E8F5E9;color:#2E7D32;border:1px solid #C8E6C9">{{ session('pwa-succes') }}</div>
        @endif

        {{-- ===================== ONGLETS — maître l.36-46 ===================== --}}
        <div class="flex gap-1 mb-5 border-b border-slate-200 no-print" role="tablist">
          <button type="button" role="tab" wire:click="$set('onglet', 'fiche')"
                  class="{{ $classeOnglet($onglet === 'fiche') }}">{{ __('stocks_pwa.inventaires.onglet_fiche') }}</button>
          <button type="button" role="tab" wire:click="$set('onglet', 'inventaire')"
                  class="{{ $classeOnglet($onglet === 'inventaire') }}">{{ __('stocks_pwa.inventaires.onglet_inventaire') }}</button>
          <button type="button" role="tab" wire:click="$set('onglet', 'historique')"
                  class="{{ $classeOnglet($onglet === 'historique') }}">{{ __('stocks_pwa.inventaires.onglet_historique') }}</button>
        </div>

        {{-- ============================================================== --}}
        {{-- ONGLET « FICHE DE STOCK » — maître l.49-84 et l.187-274        --}}
        {{-- 02/09/2026 — les TROIS panneaux d'onglet sont rendus, l'inactif
             porte `hidden`, comme le maître (`.vue-inv hidden`, l.87-93) :
             un `@if` qui retirait un panneau du HTML du premier GET faisait
             disparaître ses colonnes du rendu, et la garde G5 les comptait
             absentes. --}}
        <div class="{{ $onglet === 'fiche' ? '' : 'hidden' }}">
          <div class="bg-white rounded-xl border border-slate-200 p-4 mb-4 no-print">
            <div class="grid grid-cols-1 md:grid-cols-5 gap-3">
              <div class="md:col-span-2">
                <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.inventaires.article') }}</label>
                <select wire:model.live="articleId" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2">
                  {{-- « Tous les articles » (PO 06/09/2026) : la valeur VIDE.
                       Le detail des mouvements devient alors consolide, avec
                       une colonne Article — voir le panneau ci-dessous.
                       structure-ajout:m6-inventaires.html#option-tous-articles --}}
                  @if ($articles->isNotEmpty())
                    <option value="">{{ __('stocks_pwa.inventaires.tous_les_articles') }}</option>
                  @endif
                  @forelse ($articles as $unArticle)
                    <option value="{{ $unArticle->id }}">{{ $unArticle->libelle }}</option>
                  @empty
                    <option value="">{{ __('stocks_pwa.inventaires.aucun_article_detail') }}</option>
                  @endforelse
                </select>
              </div>
              <div>
                <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.inventaires.point') }}</label>
                <select wire:model.live="point" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2">
                  <option value="">{{ __('stocks_pwa.inventaires.tous_points') }}</option>
                  @foreach ($points as $lieu)
                    <option value="{{ $lieu->id }}">{{ $lieu->libelle }}</option>
                  @endforeach
                </select>
              </div>
              <div>
                <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.inventaires.du') }}</label>
                <input type="date" wire:model.live="debut" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              </div>
              <div>
                <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.inventaires.au') }}</label>
                <input type="date" wire:model.live="fin" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              </div>
            </div>

            <div class="flex flex-wrap gap-2 mt-3">
              @foreach ($raccourcis as $raccourci)
                <a href="{{ $lienPeriode($raccourci, 'fiche', $articleSelectionne?->id ?? '', $point) }}" wire:navigate
                   class="raccourci-periode text-[12px] px-3 py-1.5 rounded-lg bg-slate-100 hover:bg-slate-200">{{ $raccourci['libelle'] }}</a>
              @endforeach
              <div class="flex-1"></div>
              {{-- ⚠ DÉROGATION PO du 01/09/2026 — les deux boutons du maître
                   (`m6-inventaires.html` l.78-79, « Export PDF » /
                   « Export Excel ») sont remplacés par UN bouton « Exporter »
                   qui ouvre la même modale d'export ; le format s'y choisit,
                   sans présélection imposée. Registre :
                   `App\Pwa\Support\DerogationsMaquette`
                   (export_bouton_unique). Jeton :
                   maitre-refuse:m6-inventaires.html#page --}}
              <button type="button" wire:click="ouvrirExport"
                      class="text-[12px] px-3 py-1.5 rounded-lg bg-[var(--navy)] text-white hover:opacity-90">{{ __('pwa.export.bouton') }}</button>
            </div>
          </div>

          @if ($tousLesArticles && $ficheConsolidee !== null)
            {{-- ================= TOUS LES ARTICLES (PO 06/09/2026) =========
                 ⚠ AUCUN CUMUL DE QUANTITES : additionner des kilos, des
                 casiers et des portions donnerait « 17 » de rien du tout.
                 Seule la VALEUR est totalisee, parce qu'elle a une unite
                 commune. Chaque ligne porte donc SON article et SON unite,
                 et le solde progressif reste celui de sa propre fiche.
                 Le jeton porte le nom que le comparateur CALCULE, jamais un
                 nom invente : un jeton qui ne designe aucun bloc ne declare
                 rien.
                 structure-ajout:m6-inventaires.html#div-cf191190 --}}
            @if ($ficheConsolidee['incoherents'] !== [])
              <div class="mb-4 rounded-xl border border-red-200 bg-red-50 p-3.5 text-[13px] text-red-800">
                <strong>{{ __('stocks_pwa.inventaires.incoherence') }}</strong>
                {{ __('stocks_pwa.inventaires.incoherents_liste', ['articles' => implode(', ', $ficheConsolidee['incoherents'])]) }}
              </div>
            @endif

            <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
              <div class="bg-white rounded-xl border border-slate-200 p-3.5">
                <p class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('stocks_pwa.inventaires.kpi_articles') }}</p>
                <p class="text-lg font-bold mt-0.5 text-[var(--navy)]">{{ $ficheConsolidee['articles'] }}</p>
              </div>
              <div class="bg-white rounded-xl border border-slate-200 p-3.5">
                <p class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('stocks_pwa.inventaires.kpi_articles_mouvementes') }}</p>
                <p class="text-lg font-bold mt-0.5 text-blue-600">{{ $ficheConsolidee['articles_avec_mouvement'] }}</p>
              </div>
              <div class="bg-white rounded-xl border border-slate-200 p-3.5">
                <p class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('stocks_pwa.inventaires.kpi_mouvements') }}</p>
                <p class="text-lg font-bold mt-0.5 text-[var(--navy)]">{{ $ficheConsolidee['mouvements'] }}</p>
              </div>
              <div class="bg-white rounded-xl border border-slate-200 p-3.5">
                <p class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('stocks_pwa.inventaires.kpi_valeur') }}</p>
                <p class="text-lg font-bold mt-0.5 text-[var(--navy)]">{{ MontantFcfa::format($ficheConsolidee['valeur_stock_theorique']) }}</p>
              </div>
            </div>

            <p class="text-[12px] text-slate-500 mb-3">{{ __('stocks_pwa.inventaires.tous_aide') }}</p>

            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
              <div class="px-4 py-3 border-b border-slate-200 flex items-center justify-between">
                <h2 class="text-[13px] font-bold text-[var(--navy)]">{{ __('stocks_pwa.inventaires.detail_mouvements') }}</h2>
                <span class="text-[11px] text-slate-400">{{ __('stocks_pwa.inventaires.nombre_mouvements', ['nombre' => $ficheConsolidee['mouvements']]) }}</span>
              </div>

              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  <thead class="bg-[var(--navy)] text-[11px] uppercase tracking-wide text-white/90 font-semibold">
                    <tr>
                      <th class="text-left px-4 py-2.5">{{ __('stocks_pwa.inventaires.col_date') }}</th>
                      <th class="text-left px-4 py-2.5">{{ __('stocks_pwa.inventaires.article') }}</th>
                      <th class="text-left px-4 py-2.5">{{ __('stocks_pwa.inventaires.col_type') }}</th>
                      <th class="text-left px-4 py-2.5">{{ __('stocks_pwa.inventaires.col_motif') }}</th>
                      <th class="text-right px-4 py-2.5">{{ __('stocks_pwa.inventaires.col_entree') }}</th>
                      <th class="text-right px-4 py-2.5">{{ __('stocks_pwa.inventaires.col_sortie') }}</th>
                      <th class="text-right px-4 py-2.5">{{ __('stocks_pwa.inventaires.col_solde') }}</th>
                      {{-- « Utilisateur » : la colonne du maitre, rendue ici
                           comme au tableau unitaire — le tiret, faute d'auteur
                           lisible sur `mouvements_stock` (motif en tete de
                           fichier). Une colonne du maitre absente d'un seul
                           des deux modes serait un ecart non declare. --}}
                      <th class="text-left px-4 py-2.5">{{ __('stocks_pwa.inventaires.col_utilisateur') }}</th>
                    </tr>
                  </thead>
                  <tbody>
                    @if ($ficheConsolidee['lignes'] === [])
                      <tr>
                        <td colspan="8" class="p-8 text-center text-[13px] text-slate-400">{{ __('stocks_pwa.inventaires.aucun_mouvement') }}</td>
                      </tr>
                    @endif
                    @foreach ($ficheConsolidee['lignes'] as $index => $mouvement)
                      <tr wire:key="mvt-tous-{{ $index }}" class="border-t border-slate-100">
                        <td class="px-4 py-2.5 whitespace-nowrap">{{ \Carbon\CarbonImmutable::parse($mouvement['date'])->format('d/m/Y H:i') }}</td>
                        <td class="px-4 py-2.5 font-semibold text-slate-700">{{ $mouvement['article'] }}</td>
                        <td class="px-4 py-2.5"><span class="px-2 py-0.5 rounded text-[11px] font-semibold {{ $couleurType[$mouvement['type']] ?? 'bg-slate-100 text-slate-600' }}">{{ $libelleType[$mouvement['type']] ?? $mouvement['type'] }}</span></td>
                        <td class="px-4 py-2.5 text-slate-600">{{ $mouvement['motif'] }}</td>
                        <td class="px-4 py-2.5 text-right {{ bccomp($mouvement['entree'], '0', 2) > 0 ? 'text-emerald-600 font-semibold' : 'text-slate-300' }}">{{ bccomp($mouvement['entree'], '0', 2) > 0 ? '+'.$mouvement['entree'].' '.$mouvement['unite'] : MontantFcfa::TIRET }}</td>
                        <td class="px-4 py-2.5 text-right {{ bccomp($mouvement['sortie'], '0', 2) > 0 ? 'text-blue-600 font-semibold' : 'text-slate-300' }}">{{ bccomp($mouvement['sortie'], '0', 2) > 0 ? $moins.$mouvement['sortie'].' '.$mouvement['unite'] : MontantFcfa::TIRET }}</td>
                        <td class="px-4 py-2.5 text-right font-bold">{{ $mouvement['solde'] }} {{ $mouvement['unite'] }}</td>
                        <td class="px-4 py-2.5 text-slate-300 text-[12px]">{{ MontantFcfa::TIRET }}</td>
                      </tr>
                    @endforeach
                  </tbody>
                </table>
              </div>
            </div>
          @elseif ($fiche === null)
            <div class="bg-white rounded-xl border border-slate-200 p-10 text-center">
              <p class="text-[15px] font-semibold" style="color:var(--navy)">{{ __('stocks_pwa.inventaires.aucun_article') }}</p>
              <p class="text-[13px] text-slate-500 mt-1">{{ __('stocks_pwa.inventaires.aucun_article_detail') }}</p>
            </div>
          @else
            {{--
                Le bandeau d'incohérence se lit AVANT les chiffres — même
                raisonnement que « ne vaut pas facture » au corps d'un document
                (PA-113). Il n'apparaît QUE lorsqu'il vaut : une mention
                permanente cesserait d'être lue (PA-135).
            --}}
            @unless ($fiche['coherent'])
              <div class="mb-4 rounded-xl border border-red-200 bg-red-50 p-3.5 text-[13px] text-red-800">
                <strong>{{ __('stocks_pwa.inventaires.incoherence') }}</strong>
                {{ __('stocks_pwa.inventaires.incoherence_detail') }}
              </div>
            @endunless

            {{-- maître l.225-232 : les six cartes, dans cet ordre. --}}
            <div class="grid grid-cols-2 lg:grid-cols-6 gap-3 mb-4">
              <div class="bg-white rounded-xl border border-slate-200 p-3.5">
                <p class="text-[10px] font-bold uppercase tracking-wider text-slate-400">{{ __('stocks_pwa.inventaires.kpi_stock_initial') }}</p>
                <p class="text-lg font-bold mt-0.5 text-[var(--navy)]">{{ $fiche['stock_initial'] }} {{ $fiche['article']['unite'] }}</p>
              </div>
              <div class="bg-white rounded-xl border border-slate-200 p-3.5">
                <p class="text-[10px] font-bold uppercase tracking-wider text-slate-400">{{ __('stocks_pwa.inventaires.kpi_entrees') }}</p>
                <p class="text-lg font-bold mt-0.5 text-emerald-600">+{{ $fiche['entrees'] }} {{ $fiche['article']['unite'] }}</p>
              </div>
              <div class="bg-white rounded-xl border border-slate-200 p-3.5">
                <p class="text-[10px] font-bold uppercase tracking-wider text-slate-400">{{ __('stocks_pwa.inventaires.kpi_sorties') }}</p>
                <p class="text-lg font-bold mt-0.5 text-blue-600">{{ $moins }}{{ $fiche['sorties'] }} {{ $fiche['article']['unite'] }}</p>
              </div>
              <div class="bg-white rounded-xl border border-slate-200 p-3.5">
                <p class="text-[10px] font-bold uppercase tracking-wider text-slate-400">{{ __('stocks_pwa.inventaires.kpi_pertes') }}</p>
                <p class="text-lg font-bold mt-0.5 text-red-600">{{ $moins }}{{ $fiche['pertes'] }} {{ $fiche['article']['unite'] }}</p>
              </div>
              <div class="bg-white rounded-xl border border-slate-200 p-3.5">
                <p class="text-[10px] font-bold uppercase tracking-wider text-slate-400">{{ __('stocks_pwa.inventaires.kpi_regularisations') }}</p>
                <p class="text-lg font-bold mt-0.5 text-amber-600">{{ bccomp($fiche['regularisations'], '0', 2) >= 0 ? '+' : '' }}{{ $fiche['regularisations'] }} {{ $fiche['article']['unite'] }}</p>
              </div>
              <div class="bg-white rounded-xl border border-slate-200 p-3.5">
                <p class="text-[10px] font-bold uppercase tracking-wider text-slate-400">{{ __('stocks_pwa.inventaires.kpi_stock_theorique') }}</p>
                <p class="text-lg font-bold mt-0.5 text-[var(--navy)]">{{ $fiche['stock_theorique'] }} {{ $fiche['article']['unite'] }}</p>
              </div>
            </div>

            {{-- maître l.234-242. --}}
            <div class="bg-white rounded-xl border border-slate-200 p-4 mb-4 flex flex-wrap items-center gap-x-8 gap-y-2">
              <div><span class="text-[11px] text-slate-400">{{ __('stocks_pwa.inventaires.cmp') }}</span>
                <span class="ml-2 text-[13px] font-semibold">{{ MontantFcfa::format($fiche['article']['cmp']) }}</span></div>
              <div><span class="text-[11px] text-slate-400">{{ __('stocks_pwa.inventaires.valeur_theorique') }}</span>
                <span class="ml-2 text-[15px] font-bold text-[var(--navy)]">{{ MontantFcfa::format($fiche['valeur_stock_theorique']) }}</span></div>
              <div><span class="text-[11px] text-slate-400">{{ __('stocks_pwa.inventaires.point_courant') }}</span>
                <span class="ml-2 text-[13px]">{{ $point === '' ? __('stocks_pwa.inventaires.tous_points') : ($points->firstWhere('id', $point)?->libelle ?? $point) }}</span></div>
            </div>

            {{-- maître l.244-273. --}}
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
              <div class="px-4 py-3 border-b border-slate-200 flex items-center justify-between">
                <h2 class="text-[13px] font-bold text-[var(--navy)]">{{ __('stocks_pwa.inventaires.detail_mouvements') }}</h2>
                <span class="text-[11px] text-slate-400">{{ __('stocks_pwa.inventaires.nombre_mouvements', ['nombre' => count($fiche['lignes'])]) }}</span>
              </div>

              {{-- 02/09/2026 — le `<thead>` est rendu même sans mouvement
                   (garde G5) : le corps dit qu'il n'y a rien, l'entête reste. --}}
                <div class="overflow-x-auto">
                  <table class="w-full text-[13px]">
                    <thead class="bg-[var(--navy)] text-[11px] uppercase tracking-wide text-white/90 font-semibold">
                      <tr>
                        <th class="text-left px-4 py-2.5">{{ __('stocks_pwa.inventaires.col_date') }}</th>
                        <th class="text-left px-4 py-2.5">{{ __('stocks_pwa.inventaires.col_type') }}</th>
                        <th class="text-left px-4 py-2.5">{{ __('stocks_pwa.inventaires.col_motif') }}</th>
                        <th class="text-right px-4 py-2.5">{{ __('stocks_pwa.inventaires.col_entree') }}</th>
                        <th class="text-right px-4 py-2.5">{{ __('stocks_pwa.inventaires.col_sortie') }}</th>
                        <th class="text-right px-4 py-2.5">{{ __('stocks_pwa.inventaires.col_solde') }}</th>
                        {{-- 02/09/2026 — « Utilisateur » (garde G5) : le nom
                             que le maître donne à cette colonne dans son état
                             exporté (l.290). Son écran écrit « Par », rendu
                             par l'historique (hist_col_par). --}}
                        <th class="text-left px-4 py-2.5">{{ __('stocks_pwa.inventaires.col_utilisateur') }}</th>
                      </tr>
                    </thead>
                    <tbody>
                      @if ($fiche['lignes'] === [])
                        <tr>
                          <td colspan="7" class="p-8 text-center text-[13px] text-slate-400">{{ __('stocks_pwa.inventaires.aucun_mouvement') }}</td>
                        </tr>
                      @endif
                      @foreach ($fiche['lignes'] as $index => $mouvement)
                        <tr wire:key="mvt-{{ $index }}" class="border-t border-slate-100">
                          <td class="px-4 py-2.5 whitespace-nowrap">{{ \Carbon\CarbonImmutable::parse($mouvement['date'])->format('d/m/Y H:i') }}</td>
                          <td class="px-4 py-2.5"><span class="px-2 py-0.5 rounded text-[11px] font-semibold {{ $couleurType[$mouvement['type']] ?? 'bg-slate-100 text-slate-600' }}">{{ $libelleType[$mouvement['type']] ?? $mouvement['type'] }}</span></td>
                          <td class="px-4 py-2.5 text-slate-600">{{ $mouvement['motif'] }}</td>
                          <td class="px-4 py-2.5 text-right {{ bccomp($mouvement['entree'], '0', 2) > 0 ? 'text-emerald-600 font-semibold' : 'text-slate-300' }}">{{ bccomp($mouvement['entree'], '0', 2) > 0 ? '+'.$mouvement['entree'] : MontantFcfa::TIRET }}</td>
                          <td class="px-4 py-2.5 text-right {{ bccomp($mouvement['sortie'], '0', 2) > 0 ? 'text-blue-600 font-semibold' : 'text-slate-300' }}">{{ bccomp($mouvement['sortie'], '0', 2) > 0 ? $moins.$mouvement['sortie'] : MontantFcfa::TIRET }}</td>
                          <td class="px-4 py-2.5 text-right font-bold">{{ $mouvement['solde'] }}</td>
                          {{-- « Par » — refusée, motif en tête de fichier. --}}
                          <td class="px-4 py-2.5 text-slate-300 text-[12px]">{{ MontantFcfa::TIRET }}</td>
                        </tr>
                      @endforeach
                    </tbody>
                  </table>
                </div>
            </div>
          @endif
        </div>

        {{-- ============================================================== --}}
        {{-- ONGLET « INVENTAIRE PHYSIQUE » — maître l.389-500              --}}
        {{-- ============================================================== --}}
        <div class="{{ $onglet === 'inventaire' ? '' : 'hidden' }}">
          {{-- 02/09/2026 — les DEUX étapes sont rendues, l'inactive porte
               `hidden` (garde G5) : la feuille de comptage retirée du HTML
               quand aucun inventaire ne court faisait disparaître ses
               colonnes du premier GET. --}}
          <div class="{{ $inventaireEnCours === null ? '' : 'hidden' }}">
            {{--
                ÉTAPE 1 — maitre, m6-inventaires.html l.337-357
                (`rendrePeriodicite()`) : le tableau « Cycle d'inventaire par
                magasin ». Le geste de lancement rejoint chaque ligne — le
                clic EST le choix du magasin — et ouvre l'ÉTAPE 2, la grille
                de comptage ci-dessous (@else), inchangée.
            --}}
            <div class="bg-white rounded-xl border border-slate-200 p-4">
              <div class="mb-3">
                <p class="text-[15px] font-semibold text-[var(--navy)]">{{ __('stocks_pwa.inventaires.aucun_inventaire') }}</p>
                <p class="text-[13px] text-slate-500 mt-0.5 max-w-2xl">{{ __('stocks_pwa.inventaires.aucun_inventaire_detail') }}</p>
              </div>

              <div class="mb-2">
                <h2 class="text-[13px] font-bold" style="color:var(--navy)">{{ __('stocks_pwa.inventaires.cycle_titre') }}</h2>
                <p class="text-[12px] text-slate-500 mt-0.5">{{ __('stocks_pwa.inventaires.cycle_aide') }}</p>
              </div>

              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  <thead class="bg-[var(--navy)]">
                    <tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
                      <th class="px-3 py-2">{{ __('stocks_pwa.inventaires.cycle_col_magasin') }}</th>
                      <th class="px-3 py-2">{{ __('stocks_pwa.inventaires.cycle_col_periodicite') }}</th>
                      <th class="px-3 py-2">{{ __('stocks_pwa.inventaires.cycle_col_dernier') }}</th>
                      <th class="px-3 py-2">{{ __('stocks_pwa.inventaires.cycle_col_etat') }}</th>
                      {{-- 02/09/2026 — la colonne d'action n'a pas d'entête
                           (garde G5) : « Lancer l'inventaire » n'est le nom
                           d'aucune colonne du maître, c'est le bouton de la
                           ligne. --}}
                      <th class="px-3 py-2 text-right no-print"></th>
                    </tr>
                  </thead>
                  <tbody>
                    @forelse ($points as $lieu)
                      @php $dernierDuPoint = $dernierInventaireParPoint[$lieu->id] ?? null; @endphp
                      <tr wire:key="cycle-{{ $lieu->id }}" class="border-b border-slate-100">
                        <td class="px-3 py-2 font-semibold" style="color:var(--navy)">{{ $lieu->libelle }}</td>
                        {{-- Aucune periodicite persistee cote serveur — voir le lang key. --}}
                        <td class="px-3 py-2"><span class="text-[12px] text-slate-400">{{ __('stocks_pwa.inventaires.cycle_non_definie') }}</span></td>
                        <td class="px-3 py-2 text-slate-600">
                          {{ $dernierDuPoint ? $dernierDuPoint->date_inventaire->format('d/m/Y') : '' }}
                          @unless ($dernierDuPoint)
                            <span class="text-slate-400">{{ __('stocks_pwa.inventaires.cycle_dernier_aucun') }}</span>
                          @endunless
                        </td>
                        <td class="px-3 py-2"><span class="text-[12px] text-slate-400">{{ __('stocks_pwa.inventaires.cycle_non_definie') }}</span></td>
                        <td class="px-3 py-2 text-right no-print">
                          <button type="button" wire:click="ouvrirInventaire('{{ $lieu->id }}')"
                                  class="text-[12px] px-3 py-1.5 rounded-lg bg-[var(--navy)] text-white hover:opacity-90 font-semibold">{{ __('stocks_pwa.inventaires.lancer') }}</button>
                        </td>
                      </tr>
                    @empty
                      <tr>
                        <td colspan="5" class="px-3 py-6 text-center text-slate-400">{{ __('stocks_pwa.inventaires.aucun_point_defini') }}</td>
                      </tr>
                    @endforelse
                  </tbody>
                </table>
              </div>
              @error('pointInventaire') <p class="text-[12px] text-red-600 mt-3">{{ $message }}</p> @enderror
            </div>
          </div>

          {{-- ÉTAPE 2 — la feuille de comptage. Rendue `hidden` tant
               qu'aucun inventaire ne court : son thead reste dans le HTML
               (garde G5), son corps dit alors qu'il n'y a rien.
               02/09/2026 — blocs AJOUTÉS au premier GET (garde G5) : le
               maître ne monte l'étape 2 qu'à l'ouverture d'un inventaire ;
               la PWA la rend cachée. Le second jeton couvre aussi le
               tableau de l'historique, de même signature :
               structure-ajout:m6-inventaires.html#div-d63ee0cf
               structure-ajout:m6-inventaires.html#div-f1c8b22c --}}
          <div class="{{ $inventaireEnCours !== null ? '' : 'hidden' }}">
            @php
              $comptes = count($feuille) - $nonComptes;
              $nbEcarts = count(array_filter($feuille, static fn (array $l): bool => $l['ecart'] !== null && bccomp($l['ecart'], '0', 2) !== 0));
              $impact = '0.00';
              foreach ($feuille as $ligneFeuille) {
                  if ($ligneFeuille['valorise'] !== null) {
                      $impact = bcadd($impact, $ligneFeuille['valorise'], 2);
                  }
              }
            @endphp

            @if ($inventaireEnCours !== null)
            <div class="bg-white rounded-xl border border-slate-200 p-4 mb-4 flex flex-wrap items-center justify-between gap-3">
              <div>
                <p class="text-[13px] font-bold text-[var(--navy)]">{{ __('stocks_pwa.inventaires.inventaire_du', [
                    'date' => $inventaireEnCours->date_inventaire->format('d/m/Y'),
                    'point' => $inventaireEnCours->point?->libelle ?? __('stocks_pwa.inventaires.tous_points_libelle'),
                ]) }}</p>
                <p class="text-[12px] text-slate-500 mt-0.5">
                  {{ __('stocks_pwa.inventaires.comptes', ['comptes' => $comptes, 'total' => count($feuille)]) }} ·
                  {{ __('stocks_pwa.inventaires.ecarts', ['nombre' => $nbEcarts]) }} ·
                  {{ __('stocks_pwa.inventaires.impact') }}
                  <strong class="{{ MontantFcfa::estNegatif($impact) ? 'text-red-600' : 'text-emerald-600' }}">{{ MontantFcfa::format($impact) }}</strong>
                </p>
              </div>
              <div class="flex gap-2 no-print">
                {{-- ⚠ DÉROGATION PO du 01/09/2026 — le maître
                     (`m6-inventaires.html` l.443) n'offre ici qu'« Export
                     PDF » ; la PWA élargit déjà à l'Excel via la même modale
                     partagée (même dérogation que `modale-export`). Les deux
                     boutons d'entrée sont désormais UN bouton « Exporter » ;
                     le choix PDF/Excel reste dans la modale. Registre :
                     `App\Pwa\Support\DerogationsMaquette`
                     (export_bouton_unique). Jeton :
                     maitre-refuse:m6-inventaires.html#page --}}
                <button type="button" wire:click="ouvrirExport"
                        class="text-[12px] px-3 py-1.5 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.export.bouton') }}</button>
                <button type="button" wire:click="demanderCloture"
                        class="text-[12px] px-4 py-1.5 rounded-lg bg-[var(--navy)] text-white hover:opacity-90 font-semibold">{{ __('stocks_pwa.inventaires.cloturer') }}</button>
              </div>
            </div>
            @endif

            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  <thead class="bg-[var(--navy)] text-[11px] uppercase tracking-wide text-white/90 font-semibold">
                    <tr>
                      <th class="text-left px-4 py-2.5">{{ __('stocks_pwa.inventaires.article') }}</th>
                      {{-- 02/09/2026 — « Unité » (garde G5) : colonne de
                           l'état exporté du maître (l.538), entre Article et
                           Théorique. Son écran la rendait entre parenthèses
                           à côté du libellé ; elle n'est pas rendue deux
                           fois par ligne. --}}
                      <th class="text-left px-4 py-2.5">{{ __('stocks_pwa.inventaires.col_unite_comptage') }}</th>
                      <th class="text-right px-4 py-2.5">{{ __('stocks_pwa.inventaires.col_theorique') }}</th>
                      <th class="text-right px-4 py-2.5">{{ __('stocks_pwa.inventaires.col_compte') }}</th>
                      <th class="text-right px-4 py-2.5">{{ __('stocks_pwa.inventaires.col_ecart') }}</th>
                      <th class="text-right px-4 py-2.5">{{ __('stocks_pwa.inventaires.col_ecart_valorise') }}</th>
                    </tr>
                  </thead>
                  <tbody>
                    @if ($feuille === [])
                      <tr>
                        <td colspan="6" class="p-8 text-center">
                          <p class="text-[13px] font-semibold text-slate-500">{{ __('stocks_pwa.inventaires.comptage_vide_titre') }}</p>
                          <p class="text-[12px] text-slate-400 mt-1">{{ __('stocks_pwa.inventaires.comptage_vide_detail') }}</p>
                        </td>
                      </tr>
                    @endif
                    @foreach ($feuille as $ligneFeuille)
                      @php
                        $classeEcart = $ligneFeuille['ecart'] === null
                            ? 'text-slate-300'
                            : (bccomp($ligneFeuille['ecart'], '0', 2) === 0
                                ? 'text-slate-400'
                                : (bccomp($ligneFeuille['ecart'], '0', 2) > 0 ? 'text-emerald-600 font-bold' : 'text-red-600 font-bold'));
                      @endphp
                      <tr wire:key="comptage-{{ $ligneFeuille['article']->id }}"
                          class="border-t border-slate-100 {{ $ligneFeuille['comptee'] === null ? 'bg-amber-50/40' : '' }}">
                        <td class="px-4 py-2">{{ $ligneFeuille['article']->libelle }}</td>
                        <td class="px-4 py-2 text-slate-600">{{ $ligneFeuille['article']->unite_mesure }}</td>
                        <td class="px-4 py-2 text-right font-semibold">{{ $ligneFeuille['theorique'] }}</td>
                        <td class="px-4 py-2 text-right">
                          @if ($ligneFeuille['comptee'] === null)
                            <button type="button" wire:click="ouvrirComptage('{{ $ligneFeuille['article']->id }}')"
                                    class="text-[12px] px-2.5 py-1 rounded-lg border border-slate-300 hover:bg-slate-50 no-print">{{ __('stocks_pwa.inventaires.a_compter') }}</button>
                          @else
                            <button type="button" wire:click="ouvrirComptage('{{ $ligneFeuille['article']->id }}')"
                                    class="text-[12px] px-2.5 py-1 rounded-lg border border-slate-300 hover:bg-slate-50 font-semibold">{{ $ligneFeuille['comptee'] }}</button>
                          @endif
                        </td>
                        <td class="px-4 py-2 text-right {{ $classeEcart }}">
                          {{ $ligneFeuille['ecart'] === null ? MontantFcfa::TIRET : (bccomp($ligneFeuille['ecart'], '0', 2) > 0 ? '+'.$ligneFeuille['ecart'] : $ligneFeuille['ecart']) }}</td>
                        <td class="px-4 py-2 text-right {{ $classeEcart }}">
                          {{ $ligneFeuille['valorise'] === null ? MontantFcfa::TIRET : MontantFcfa::format($ligneFeuille['valorise']) }}</td>
                      </tr>
                    @endforeach
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>

        {{-- ============================================================== --}}
        {{-- ONGLET « INVENTAIRES CLÔTURÉS » — maître l.552-580             --}}
        {{-- ============================================================== --}}
        <div class="{{ $onglet === 'historique' ? '' : 'hidden' }}">
          {{--
              NON PORTE, ET PLUS RENDU A L'ECRAN (02/09/2026). Le maitre
              distingue un inventaire EN COURS d'un inventaire CLOTURE ;
              `inventaires` ne porte aucun statut (PA-150), et l'historique
              liste donc ce qui existe sans pouvoir dire ou chacun en est.
              Le refus etait affiche au-dessus de la liste ; il est retire par
              directive du Product Owner et vit desormais ici.
          --}}
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
            {{-- 02/09/2026 — le `<thead>` est rendu même sans inventaire
                 (garde G5) : le corps dit qu'il n'y a rien, l'entête reste. --}}
              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  <thead class="bg-[var(--navy)] text-[11px] uppercase tracking-wide text-white/90 font-semibold">
                    <tr>
                      <th class="text-left px-4 py-2.5">{{ __('stocks_pwa.inventaires.hist_col_date') }}</th>
                      <th class="text-left px-4 py-2.5">{{ __('stocks_pwa.inventaires.hist_col_point') }}</th>
                      <th class="text-right px-4 py-2.5">{{ __('stocks_pwa.inventaires.hist_col_articles') }}</th>
                      <th class="text-right px-4 py-2.5">{{ __('stocks_pwa.inventaires.hist_col_regularises') }}</th>
                      <th class="text-right px-4 py-2.5">{{ __('stocks_pwa.inventaires.hist_col_manquants') }}</th>
                      <th class="text-right px-4 py-2.5">{{ __('stocks_pwa.inventaires.hist_col_excedents') }}</th>
                      <th class="text-right px-4 py-2.5">{{ __('stocks_pwa.inventaires.hist_col_impact') }}</th>
                      <th class="text-left px-4 py-2.5">{{ __('stocks_pwa.inventaires.hist_col_par') }}</th>
                    </tr>
                  </thead>
                  <tbody>
                    @if ($historique->isEmpty())
                      <tr>
                        <td colspan="8" class="p-10 text-center">
                          <p class="text-[15px] font-semibold" style="color:var(--navy)">{{ __('stocks_pwa.inventaires.hist_vide') }}</p>
                          <p class="text-[13px] text-slate-500 mt-1">{{ __('stocks_pwa.inventaires.hist_vide_detail') }}</p>
                        </td>
                      </tr>
                    @endif
                    @foreach ($historique as $inventaire)
                      @php
                        $regularises = $inventaire->lignes->filter(
                            static fn ($l): bool => bccomp((string) $l->ecart, '0', 2) !== 0,
                        )->count();
                      @endphp
                      <tr wire:key="inv-{{ $inventaire->id }}" class="border-t border-slate-100">
                        <td class="px-4 py-2.5">{{ $inventaire->date_inventaire->format('d/m/Y') }}</td>
                        <td class="px-4 py-2.5">{{ $inventaire->point?->libelle ?? __('stocks_pwa.inventaires.tous_points_libelle') }}</td>
                        <td class="px-4 py-2.5 text-right">{{ $inventaire->lignes->count() }}</td>
                        <td class="px-4 py-2.5 text-right">{{ $regularises }}</td>
                        {{-- « Manquants » et « Excédents » — seule la clôture les
                             produit, et le schéma ne dit pas qu'elle a eu lieu. --}}
                        <td class="px-4 py-2.5 text-right text-slate-300">{{ MontantFcfa::TIRET }}</td>
                        <td class="px-4 py-2.5 text-right text-slate-300">{{ MontantFcfa::TIRET }}</td>
                        <td class="px-4 py-2.5 text-right text-slate-300">{{ MontantFcfa::TIRET }}</td>
                        <td class="px-4 py-2.5 text-slate-400 text-[12px]">{{ $inventaire->utilisateur?->login ?? MontantFcfa::TIRET }}</td>
                      </tr>
                    @endforeach
                  </tbody>
                </table>
              </div>
          </div>
        </div>

      </div>
    </main>
  </div>

  {{-- ===================== MODALES ===================== --}}

  @if ($etatFormulaire === 'comptage')
    <x-pwa.modale :titre="__('stocks_pwa.inventaires.enregistrer_comptage')"
                  :sousTitre="$articles->firstWhere('id', $comptageArticleId)?->libelle"
                  largeur="448px">
      <div>
        <label class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('stocks_pwa.inventaires.col_compte') }}</label>
        <input type="number" min="0" step="0.01" wire:model="quantiteComptee"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 focus:border-[var(--gold)] focus:outline-none">
        @error('quantiteComptee') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerComptage"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('stocks_pwa.inventaires.enregistrer_comptage') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  @if ($etatFormulaire === 'cloture')
    {{--
        La clôture ANNONCE avant le clic combien d'articles n'ont pas été
        comptés et ce qu'il advient d'eux. Un décompte affiché après coup serait
        une surprise, et une clôture partielle silencieuse laisserait une partie
        du stock régularisée et le reste intact.
    --}}
    <x-pwa.modale :titre="__('stocks_pwa.inventaires.incomplet_titre')"
                  :sousTitre="__('stocks.inventaire_incomplet', ['nombre' => $nonComptes])"
                  largeur="448px">
      <p class="text-[13px] text-slate-600">{{ __('stocks_pwa.inventaires.incomplet_detail') }}</p>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="cloturer"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ $nonComptes > 0 ? __('stocks_pwa.inventaires.incomplet_confirmer') : __('stocks_pwa.inventaires.cloturer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  @if ($etatFormulaire === 'export')
    @include('pwa.partials.modale-export', [
      'titre' => $onglet === 'fiche' ? __('stocks_pwa.export.titre_fiche') : __('stocks_pwa.export.titre_stocks'),
      'sousTitre' => __('stocks_pwa.export.sous_titre_filtre', ['filtres' => $onglet === 'fiche'
          ? ($articleSelectionne?->libelle ?? __('stocks_pwa.inventaires.aucun_article')).' · '.$debut.' → '.$fin
          : __('stocks_pwa.inventaires.onglet_inventaire')]),
    ])
  @endif
</div>

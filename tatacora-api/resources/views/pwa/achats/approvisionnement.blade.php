{{--
    APPROVISIONNEMENT (M7)
    Maître : prototype_v2/pages/m7-approvisionnement.html

    Les quatre onglets du maître (l.36-39) sont rendus dans le DOM, trois
    masqués — c'est exactement ce que le maître fait avec ses `.vue-app.hidden`
    (l.42-45), et cela garde ses colonnes vérifiables sur un seul chargement.

    ⚠ DÉROGATION DU 31/08/2026 RENVERSÉE LE 01/09/2026 (décision du Product
    Owner) : l'entête `slate-50` qui remplaçait l'entête navy du maître est
    ABANDONNÉE — les tableaux de consultation sont désormais navy comme le
    maître (voir `App\Pwa\Support\DerogationsMaquette`). Les grilles de
    SAISIE (lignes de commande, lignes de réception, ci-dessous) restent
    claires : le maître lui-même les garde ainsi (`border-b border-slate-200`,
    jamais navy) pour ses lignes éditables.

    ⚠ Déclaration pour la garde des trois sources :
    maitre-refuse:m7-approvisionnement.html#fond-modale — les trois fenêtres
    construites dans `#fond-modale` (l.560, l.623, l.694) passent par le châssis
    partagé `<x-pwa.modale>` : leur voile, leur rayon et leur `max-height:90vh`
    viennent de `app.css`, jamais d'un conteneur positionné recopié à la main
    avec son propre voile. La troisième — « Régler » — est PORTÉE depuis le
    02/09/2026 (PA-165, `ReglementFournisseurService`) : le jeton ne porte
    plus que sur le CHÂSSIS des trois fenêtres, jamais sur leur fonction.

    ⚠ Ne réécrivez pas la phrase ci-dessus en y citant les DEUX classes du
    motif fautif sur une même ligne : `ChassisModalePwaTest` lit le source
    ligne par ligne et signalerait ce commentaire comme un conteneur de modale
    écrit à la main (mesuré le 31/08/2026).
--}}
@php
    use App\Pwa\Livewire\Achats\Achats;
    use App\Pwa\Support\MontantFcfa;

    // Classes d'onglets : directive PO du 01/09/2026, UN SEUL AUTEUR —
    // voir le docblock de `App\Pwa\Support\Onglets`.
    $classeOnglet = static fn (bool $actif): string => \App\Pwa\Support\Onglets::classes($actif);

    $entete = static fn (string $libelle, string $align = 'left'): string
        => '<th class="px-4 py-2.5 text-' . $align
        . ' text-[11px] font-semibold uppercase tracking-wide text-white/90">' . e($libelle) . '</th>';

    $badge = 'px-2 py-0.5 rounded text-[11px] font-semibold';

    /** L'état vide du moteur du maître (crud-ui.js l.75-79), une seule fois. */
    $etatVide = 'flex flex-col items-center justify-center py-16 text-center';
@endphp

<div class="contents">

  @include('pwa.partials.barre-superieure')

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')

    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        {{-- En-tête institutionnel d'IMPRESSION — `<h2>`, jamais `<h1>`. --}}
        <div class="hidden print:block mb-6 border-b-2 border-[var(--navy)] pb-4">
          <h2 class="text-xl font-bold" style="color:var(--navy)">{{ __('pwa.marque') }} — {{ __('pwa.enseigne_courte') }}</h2>
          <p class="text-xs text-slate-600 mt-1">{{ __('pwa.appro.titre') }} — {{ now()->format('d/m/Y H:i') }}</p>
        </div>

        {{-- ============================ EN-TÊTE (maître l.22-31) --}}
        <div class="mb-5 flex flex-wrap items-start justify-between gap-3">
          <div>
            <div class="flex items-center gap-2.5">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 2L3 6v14a2 2 0 002 2h14a2 2 0 002-2V6l-3-4z"/><path d="M3 6h18M16 10a4 4 0 01-8 0"/></svg>
              <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('pwa.appro.titre') }}</h1>
            </div>
            <p class="text-[15px] text-slate-500 mt-1.5">{!! __('pwa.appro.sous_titre') !!}</p>
          </div>

          <div class="flex flex-wrap items-center gap-2 no-print">
            {{-- ⚠ DÉROGATION PO du 01/09/2026 — les deux boutons du maître
                 (`m7-approvisionnement.html` l.225-226, « Export Excel » /
                 « Export PDF ») sont remplacés par UN bouton « Exporter » qui
                 ouvre la même modale d'export ; le format s'y choisit, sans
                 présélection imposée. Registre :
                 `App\Pwa\Support\DerogationsMaquette` (export_bouton_unique).
                 Jeton : maitre-refuse:m7-approvisionnement.html#besoins --}}
            <button type="button" wire:click="ouvrirExport"
                    class="flex items-center gap-2 px-3.5 py-2.5 rounded-lg border border-slate-200 bg-white text-slate-600 text-xs font-semibold">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/></svg>
              {{ __('pwa.export.bouton') }}
            </button>
            @if ($peutEcrire && $onglet === 'besoins')
              <button type="button" wire:click="ouvrirFormulaireCommande"
                      class="px-4 py-2.5 rounded-lg bg-[var(--navy)] text-white text-xs font-semibold">{{ __('achats_pwa.appro.commander_selection') }}</button>
            @endif
          </div>
        </div>

        @if (session('pwa-succes'))
          <div class="mb-4 rounded-xl px-4 py-3 text-[13px] font-semibold no-print"
               style="background:#E8F5E9;color:#2E7D32;border:1px solid #C8E6C9">{{ session('pwa-succes') }}</div>
        @endif

        @error('selection')
          <div class="mb-4 rounded-xl px-4 py-3 text-[13px] no-print"
               style="background:#FDECEC;color:#C62828;border:1px solid #F5C6C6">{{ $message }}</div>
        @enderror

        {{-- ============================ INDICATEURS (maître l.114-133) --}}
        <div id="kpis-appro" class="grid grid-cols-2 lg:grid-cols-5 gap-3 mb-5">
          @foreach ([
              ['libelle' => __('pwa.appro.kpi_sous_seuil'), 'valeur' => (string) $sousSeuil, 'accent' => 'text-red-600'],
              ['libelle' => __('pwa.appro.kpi_en_attente'), 'valeur' => (string) $enAttente, 'accent' => ''],
              ['libelle' => __('pwa.appro.kpi_partielles'), 'valeur' => (string) $partielles, 'accent' => $partielles > 0 ? 'text-amber-600' : ''],
              // RÉELLEMENT CHIFFRÉS depuis le 02/09/2026 (PA-165) — sommés
              // depuis `ReglementFournisseurService::resteDu()`, jamais le
              // montant commandé (voir `render()`).
              ['libelle' => __('pwa.appro.kpi_a_payer'), 'valeur' => (string) $fournisseursAPayer, 'accent' => $fournisseursAPayer > 0 ? 'text-amber-600' : ''],
              ['libelle' => __('pwa.appro.kpi_total_du'), 'valeur' => MontantFcfa::format($totalDu), 'accent' => bccomp($totalDu, '0.00', 2) > 0 ? 'text-red-600' : ''],
          ] as $kpi)
            <div class="bg-white rounded-xl border border-slate-200 p-3.5">
              <p class="text-[10px] font-bold uppercase tracking-wider text-slate-400">{{ $kpi['libelle'] }}</p>
              <p class="text-lg font-bold mt-0.5 {{ $kpi['accent'] ?: 'text-[var(--navy)]' }}">{{ $kpi['valeur'] }}</p>
            </div>
          @endforeach
        </div>

        {{-- ============================ ONGLETS (maître l.35-40) --}}
        <div class="flex gap-1 mb-5 border-b border-slate-200 no-print" role="tablist">
          @foreach ([
              'besoins' => __('pwa.appro.onglet_besoins'),
              'commandes' => __('pwa.appro.onglet_commandes'),
              'receptions' => __('pwa.appro.onglet_receptions'),
              'dettes' => __('pwa.appro.onglet_dettes'),
          ] as $cle => $libelle)
            <button type="button" role="tab" wire:click="$set('onglet', '{{ $cle }}')"
                    aria-selected="{{ $onglet === $cle ? 'true' : 'false' }}"
                    class="{{ $classeOnglet($onglet === $cle) }}">{{ $libelle }}</button>
          @endforeach
        </div>

        {{-- Recherche et filtre — la barre d'outils commune du maître (l.150-162). --}}
        <div class="flex flex-wrap items-center gap-2 mb-4 no-print">
          <input type="search" wire:model.live.debounce.300ms="recherche"
                 placeholder="{{ $onglet === 'besoins' ? __('pwa.appro.recherche_besoin') : __('pwa.appro.recherche_commande') }}"
                 class="text-[13px] border border-slate-300 rounded-lg px-3 py-1.5 w-56">
          @if ($onglet === 'commandes')
            <select wire:model.live="statut" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-1.5">
              <option value="">{{ __('pwa.appro.tous_statuts') }}</option>
              @foreach (Achats::STATUTS as $cle => $style)
                <option value="{{ $cle }}">{{ $style['libelle'] }}</option>
              @endforeach
            </select>
          @endif
        </div>

        {{-- ============================ BESOINS (maître l.209-268) --}}
        <section class="{{ $onglet === 'besoins' ? '' : 'hidden' }}">
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
            <div class="px-4 py-3 border-b border-slate-200">
              <h2 class="text-[13px] font-bold text-[var(--navy)]">{{ __('pwa.appro.besoins_titre') }}</h2>
              <p class="text-[11px] text-slate-400 mt-0.5">{{ __('pwa.appro.besoins_detail') }} {{ __('pwa.appro.besoins_portee') }}</p>
            </div>

            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]">
                  <tr>
                    <th class="px-4 py-2.5 w-10">
                      <input type="checkbox" wire:model.live="toutSelectionne" class="w-4 h-4 rounded"
                             aria-label="{{ __('achats_pwa.tableau.selection_tout') }}">
                    </th>
                    {!! $entete(__('pwa.appro.col_article')) !!}
                    {!! $entete(__('pwa.appro.col_point')) !!}
                    {!! $entete(__('pwa.appro.col_stock'), 'right') !!}
                    {!! $entete(__('pwa.appro.col_seuil'), 'right') !!}
                    {!! $entete(__('pwa.appro.col_manque'), 'right') !!}
                    {!! $entete(__('pwa.appro.col_prix_achat'), 'right') !!}
                    {!! $entete(__('pwa.appro.col_a_commander'), 'right') !!}
                  </tr>
                </thead>
                <tbody>
                  @foreach ($besoins as $b)
                    <tr wire:key="besoin-{{ $b['article_id'] }}" class="border-t border-slate-100">
                      <td class="px-4 py-2">
                        <input type="checkbox" value="{{ $b['article_id'] }}" wire:model.live="selection"
                               class="w-4 h-4 rounded" aria-label="{{ __('achats_pwa.tableau.selection_ligne') }}">
                      </td>
                      <td class="px-4 py-2 font-medium">{{ $b['libelle'] }}</td>
                      {{-- « Point » : le stock affiché est CONSOLIDÉ sur tous
                           les points, et `articles` ne porte aucun point. --}}
                      <td class="px-4 py-2 text-slate-500">{{ MontantFcfa::TIRET }}</td>
                      <td class="px-4 py-2 text-right {{ $b['rupture'] ? 'text-red-600 font-bold' : 'font-semibold' }}">{{ $b['stock'] }}</td>
                      <td class="px-4 py-2 text-right text-slate-400">{{ $b['seuil'] }}</td>
                      <td class="px-4 py-2 text-right text-red-600 font-semibold">{{ $b['manque'] }}</td>
                      {{-- « Prix d'achat » : aucune colonne au schéma. Le coût
                           moyen pondéré n'est pas un prix d'achat — il sert de
                           PRÉ-REMPLISSAGE dans la fenêtre de commande, où il
                           est dit et corrigible. --}}
                      <td class="px-4 py-2 text-right text-slate-500">{{ MontantFcfa::TIRET }}</td>
                      <td class="px-4 py-2 text-right">{{ $b['a_commander'] }} {{ $b['unite'] }}</td>
                    </tr>
                  @endforeach
                </tbody>
              </table>

              <div class="{{ $besoins === [] ? 'flex' : 'hidden' }} {{ $etatVide }}">
                <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="#CBD5E1" stroke-width="1.5" class="mb-3"><path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/></svg>
                <p class="text-sm font-semibold text-slate-500">{{ __('pwa.appro.besoins_vide') }}</p>
                <p class="text-xs text-slate-400 mt-1">{{ __('pwa.achats.vide_detail') }}</p>
              </div>
            </div>
          </div>
        </section>

        {{-- ============================ COMMANDES (maître l.329-399) --}}
        <section class="{{ $onglet === 'commandes' ? '' : 'hidden' }}">
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
            <div class="px-4 py-3 border-b border-slate-200">
              <h2 class="text-[13px] font-bold text-[var(--navy)]">{{ __('pwa.appro.commandes_titre') }}</h2>
            </div>

            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]">
                  <tr>
                    {!! $entete(__('pwa.appro.col_numero')) !!}
                    {!! $entete(__('pwa.appro.col_fournisseur')) !!}
                    {!! $entete(__('pwa.appro.col_date')) !!}
                    {!! $entete(__('pwa.appro.col_lignes'), 'right') !!}
                    {!! $entete(__('pwa.appro.col_montant'), 'right') !!}
                    {!! $entete(__('pwa.appro.col_regle'), 'right') !!}
                    {!! $entete(__('achats_pwa.appro.col_reste_du'), 'right') !!}
                    {!! $entete(__('pwa.appro.col_statut')) !!}
                    {!! $entete(__('pwa.appro.col_actions'), 'right') !!}
                  </tr>
                </thead>
                <tbody>
                  @foreach ($commandes as $c)
                    <tr wire:key="cmd-{{ $c->id }}" class="border-t border-slate-100">
                      {{-- L'identifiant RÉEL : aucune commande ne porte de
                           numéro au schéma, et en fabriquer un créerait une
                           référence introuvable partout ailleurs. --}}
                      <td class="px-4 py-2.5 font-mono-tatacora text-[12px]">{{ $c->id }}</td>
                      <td class="px-4 py-2.5 font-medium">{{ $c->fournisseur?->raison_sociale ?? MontantFcfa::TIRET }}</td>
                      <td class="px-4 py-2.5 text-slate-500">{{ $c->date_commande?->format('d/m/Y') ?? MontantFcfa::TIRET }}</td>
                      <td class="px-4 py-2.5 text-right">{{ $c->lignes->count() }}</td>
                      <td class="px-4 py-2.5 text-right font-semibold">{{ MontantFcfa::format($c->montantTotal()) }}</td>
                      {{-- « Réglé » et « Reste dû » — RÉELLEMENT CHIFFRÉS
                           depuis le 02/09/2026 (PA-165), lus depuis
                           `ReglementFournisseurService` (`reglesEtRestes`),
                           jamais une soustraction locale. --}}
                      <td class="px-4 py-2.5 text-right {{ $reglesEtRestes[$c->id]['regle'] !== '0.00' ? 'text-emerald-600 font-semibold' : 'text-slate-400' }}">{{ MontantFcfa::formatOuTiret($reglesEtRestes[$c->id]['regle']) }}</td>
                      <td class="px-4 py-2.5 text-right {{ $reglesEtRestes[$c->id]['reste'] !== '0.00' ? 'text-red-600 font-semibold' : 'text-slate-400' }}">{{ MontantFcfa::formatOuTiret($reglesEtRestes[$c->id]['reste']) }}</td>
                      <td class="px-4 py-2.5">
                        @php $st = Achats::STATUTS[$c->statut] ?? null; @endphp
                        @if ($st === null)
                          {{ MontantFcfa::TIRET }}
                        @else
                          <span class="{{ $badge }}" style="background:{{ $st['fond'] }};color:{{ $st['texte'] }}">{{ $st['libelle'] }}</span>
                        @endif
                      </td>
                      <td class="px-4 py-2.5 text-right whitespace-nowrap no-print">
                        @if ($peutEcrire && ! $c->estCloturee())
                          <button type="button" wire:click="ouvrirFormulaireReception('{{ $c->id }}')"
                                  class="text-[12px] px-2.5 py-1 rounded-lg bg-[var(--navy)] text-white hover:opacity-90">{{ __('achats_pwa.appro.receptionner') }}</button>
                        @endif
                        {{-- « Régler » (maître, `ligneCommande()`) — PA-165,
                             02/09/2026 : condition sur le RESTE DÛ réel
                             (`reglesEtRestes`), jamais `montant_total`. --}}
                        @if ($peutEcrire && bccomp($reglesEtRestes[$c->id]['reste'], '0.00', 2) > 0)
                          <button type="button" wire:click="ouvrirFormulaireReglement('{{ $c->id }}')"
                                  class="text-[12px] px-2.5 py-1 rounded-lg border border-slate-300 hover:bg-slate-50 ml-1">{{ __('achats_pwa.appro.regler') }}</button>
                        @endif
                        @if (! $peutEcrire || ($c->estCloturee() && bccomp($reglesEtRestes[$c->id]['reste'], '0.00', 2) <= 0))
                          {{ MontantFcfa::TIRET }}
                        @endif
                      </td>
                    </tr>
                  @endforeach
                </tbody>
              </table>

              <div class="{{ $commandes->isEmpty() ? 'flex' : 'hidden' }} {{ $etatVide }}">
                <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="#CBD5E1" stroke-width="1.5" class="mb-3"><path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/></svg>
                <p class="text-sm font-semibold text-slate-500">{{ __('pwa.appro.commandes_vide') }}</p>
                <p class="text-xs text-slate-400 mt-1">{{ __('pwa.achats.vide_detail') }}</p>
              </div>
            </div>
          </div>
        </section>

        {{-- ============================ RÉCEPTIONS (maître l.403-476) --}}
        <section class="{{ $onglet === 'receptions' ? '' : 'hidden' }}">
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
            <div class="px-4 py-3 border-b border-slate-200">
              <h2 class="text-[13px] font-bold text-[var(--navy)]">{{ __('pwa.appro.receptions_titre') }}</h2>
              <p class="text-[11px] text-slate-400 mt-0.5">{{ __('pwa.appro.receptions_detail') }}</p>
            </div>

            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]">
                  <tr>
                    {!! $entete(__('pwa.appro.col_numero')) !!}
                    {!! $entete(__('pwa.appro.col_commande')) !!}
                    {!! $entete(__('pwa.appro.col_fournisseur')) !!}
                    {!! $entete(__('pwa.appro.col_date')) !!}
                    {!! $entete(__('pwa.appro.col_point')) !!}
                    {!! $entete(__('pwa.appro.col_articles'), 'right') !!}
                    {!! $entete(__('pwa.appro.col_conformite')) !!}
                  </tr>
                </thead>
                <tbody>
                  @foreach ($receptions as $r)
                    <tr wire:key="rec-{{ $r->id }}" class="border-t border-slate-100">
                      <td class="px-4 py-2.5 font-mono-tatacora text-[12px]">{{ $r->id }}</td>
                      <td class="px-4 py-2.5 font-mono-tatacora text-[12px] text-slate-500">{{ $r->commande_id }}</td>
                      <td class="px-4 py-2.5">{{ $r->commande?->fournisseur?->raison_sociale ?? MontantFcfa::TIRET }}</td>
                      <td class="px-4 py-2.5 text-slate-500">{{ $r->date_reception?->format('d/m/Y') ?? MontantFcfa::TIRET }}</td>
                      {{-- « Point » et « Articles » : un bon de réception n'a
                           AUCUNE ligne de détail au schéma (PA-39). --}}
                      <td class="px-4 py-2.5 text-slate-500">{{ MontantFcfa::TIRET }}</td>
                      <td class="px-4 py-2.5 text-right text-slate-500">{{ MontantFcfa::TIRET }}</td>
                      <td class="px-4 py-2.5">
                        <span class="{{ $badge }} {{ $r->conformite === 'totale' ? 'bg-emerald-50 text-emerald-700' : 'bg-amber-50 text-amber-700' }}">{{ $r->conformite }}</span>
                      </td>
                    </tr>
                  @endforeach
                </tbody>
              </table>

              <div class="{{ $receptions->isEmpty() ? 'flex' : 'hidden' }} {{ $etatVide }}">
                <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="#CBD5E1" stroke-width="1.5" class="mb-3"><path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/></svg>
                <p class="text-sm font-semibold text-slate-500">{{ __('pwa.appro.receptions_vide') }}</p>
                <p class="text-xs text-slate-400 mt-1">{{ __('pwa.achats.vide_detail') }}</p>
              </div>
            </div>
          </div>
        </section>

        {{-- ============================ DETTES (maître l.480-539) --}}
        <section class="{{ $onglet === 'dettes' ? '' : 'hidden' }}">
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
            <div class="px-4 py-3 border-b border-slate-200 flex flex-wrap items-center justify-between gap-2">
              <div>
                <h2 class="text-[13px] font-bold text-[var(--navy)]">{{ __('pwa.appro.dettes_titre') }}</h2>
                <p class="text-[11px] text-slate-400 mt-0.5">{{ __('achats_pwa.appro.dettes_portee') }}</p>
              </div>
              <span class="text-[13px]">{{ __('pwa.appro.total_du') }}
                <strong class="text-[15px] ml-1 {{ bccomp($totalDu, '0.00', 2) > 0 ? 'text-red-600' : 'text-slate-400' }}">{{ MontantFcfa::formatOuTiret($totalDu) }}</strong></span>
            </div>

            {{-- UNE seule table, un seul entête, un `<tbody>` par fournisseur.

                 Le maître groupe par fournisseur en ouvrant une table par
                 groupe (l.505) et ne pose AUCUNE ligne d'entête : six colonnes
                 de chiffres s'y lisent à l'aveugle. Les libellés repris sont
                 les SIENS, ceux de l'entête de son export (l.534).

                 ⚠ L'entête vit HORS de la boucle, et ce n'est pas cosmétique :
                 posé à l'intérieur, il disparaissait entièrement dès qu'aucune
                 commande n'était due — c'est-à-dire exactement quand un
                 relecteur ouvre l'écran pour la première fois. --}}
            <table class="w-full text-[13px]">
              <thead class="bg-[var(--navy)]">
                <tr>
                  {!! $entete(__('achats_pwa.appro.col_numero_commande')) !!}
                  {!! $entete(__('pwa.appro.col_date')) !!}
                  {!! $entete(__('achats_pwa.appro.col_anciennete')) !!}
                  {!! $entete(__('pwa.appro.col_montant'), 'right') !!}
                  {!! $entete(__('pwa.appro.col_regle'), 'right') !!}
                  {!! $entete(__('achats_pwa.appro.col_reste_du'), 'right') !!}
                </tr>
              </thead>

              @foreach ($dettes as $groupe)
                @php
                  $totalGroupe = collect($groupe['commandes'])->reduce(
                      fn (?string $t, \App\Domain\Achats\Models\CommandeAchat $c) => bcadd((string) $t, $reglesEtRestes[$c->id]['reste'], 2),
                      '0.00',
                  );
                @endphp
                <tbody class="border-t border-slate-100" wire:key="dette-{{ $loop->index }}">
                  {{-- La bande de regroupement du maître (l.501-504) : le nom
                       du fournisseur, et son total dû — RÉELLEMENT CHIFFRÉ
                       depuis le 02/09/2026 (PA-165). --}}
                  <tr class="bg-slate-50">
                    <td colspan="5" class="px-4 py-2.5 text-[13px] font-bold text-[var(--navy)]">{{ $groupe['fournisseur'] }}</td>
                    <td class="px-4 py-2.5 text-right text-[13px] font-bold text-red-600">{{ MontantFcfa::format($totalGroupe) }}</td>
                  </tr>

                  @foreach ($groupe['commandes'] as $c)
                    @php $anciennete = (int) ($c->date_commande?->diffInDays(now()) ?? 0); @endphp
                    <tr class="border-t border-slate-50" wire:key="dette-cmd-{{ $c->id }}">
                      <td class="px-4 py-2 font-mono-tatacora text-[12px]">{{ $c->id }}</td>
                      <td class="px-4 py-2 text-slate-500">{{ $c->date_commande?->format('d/m/Y') ?? MontantFcfa::TIRET }}</td>
                      {{-- L'ancienneté conditionne la relance au maître : au
                           delà de 60 jours, une dette fournisseur devient un
                           sujet de trésorerie. Elle mesure l'âge du BON DE
                           COMMANDE, jamais le retard d'un paiement. --}}
                      <td class="px-4 py-2 {{ $anciennete > 60 ? 'text-red-600 font-bold' : ($anciennete > 30 ? 'text-amber-600' : 'text-slate-400') }}">{{ __('pwa.appro.jours', ['nombre' => $anciennete]) }}</td>
                      <td class="px-4 py-2 text-right">{{ MontantFcfa::format($c->montantTotal()) }}</td>
                      {{-- « Réglé » et « Reste dû » — RÉELLEMENT CHIFFRÉS
                           depuis le 02/09/2026 (PA-165), lus depuis
                           `ReglementFournisseurService`. --}}
                      <td class="px-4 py-2 text-right {{ $reglesEtRestes[$c->id]['regle'] !== '0.00' ? 'text-emerald-600' : 'text-slate-400' }}">{{ MontantFcfa::formatOuTiret($reglesEtRestes[$c->id]['regle']) }}</td>
                      <td class="px-4 py-2 text-right font-bold {{ $reglesEtRestes[$c->id]['reste'] !== '0.00' ? 'text-red-600' : 'text-slate-400' }}">{{ MontantFcfa::formatOuTiret($reglesEtRestes[$c->id]['reste']) }}</td>
                    </tr>
                  @endforeach
                </tbody>
              @endforeach
            </table>

            <div class="{{ $dettes === [] ? 'flex' : 'hidden' }} {{ $etatVide }}">
              <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="#CBD5E1" stroke-width="1.5" class="mb-3"><path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/></svg>
              <p class="text-sm font-semibold text-slate-500">{{ __('pwa.appro.dettes_vide') }}</p>
              <p class="text-xs text-slate-400 mt-1">{{ __('pwa.achats.vide_detail') }}</p>
            </div>
          </div>
        </section>

        {{--
            NON PORTE, ET PLUS RENDU A L'ECRAN. Colonnes supplementaires du
            maitre, numero de commande et vue « a commander » ne sont pas
            portes. Les REGLEMENTS FOURNISSEURS SONT PORTES depuis le
            02/09/2026 (PA-165) — voir `ReglementFournisseurService` et le
            bouton « Régler » de l'onglet Commandes. La section « ce que cet
            ecran ne fait pas » est retiree par directive du Product Owner.

            Le jeton `maitre-refuse:m7-approvisionnement.html#fond-modale`
            reste declare en tete de ce fichier (chassis des modales, pas
            leur fonction).
        --}}

      </div>
    </main>
  </div>

  {{-- ============================ NOUVEAU BON DE COMMANDE (maître l.560-595) --}}
  @if ($etatFormulaire === 'commande')
    <x-pwa.modale :titre="__('achats_pwa.appro.form_commande')"
                  :sousTitre="__('achats_pwa.appro.form_commande_sous_titre', ['nombre' => count($cLignes)])"
                  largeur="672px" fermer="$set('etatFormulaire', null)">
      <div>
        <label for="c-fournisseur" class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('achats_pwa.appro.form_fournisseur') }}</label>
        {{-- VRAIE clé étrangère, jamais du texte libre : le rapprochement à
             trois voies suppose une relation exacte. --}}
        <select id="c-fournisseur" wire:model="cFournisseurId" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          <option value="">{{ __('achats_pwa.achats.form_non_renseigne') }}</option>
          @foreach ($fournisseurs as $f)
            <option value="{{ $f->id }}">{{ $f->raison_sociale }}</option>
          @endforeach
        </select>
        @error('cFournisseurId')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
      </div>

      <p class="text-[12px] text-slate-500 bg-slate-50 rounded-lg p-3">{{ __('achats_pwa.appro.prix_suggere') }}</p>

      {{-- ⚠ EXCLUE de la conversion navy du 01/09/2026 : grille de saisie
           (quantité et prix unitaire en `<input>`), pas une table de
           consultation — le maître garde ce style clair pour ses lignes
           éditables (`m7-approvisionnement.html` l.453+). --}}
      <table class="w-full text-[13px]">
        <thead class="text-[11px] uppercase text-slate-500 border-b border-slate-200">
          <tr>
            {!! $entete(__('pwa.appro.col_article')) !!}
            {!! $entete(__('achats_pwa.appro.form_quantite'), 'right') !!}
            {!! $entete(__('achats_pwa.appro.form_prix_unitaire'), 'right') !!}
            {!! $entete(__('achats_pwa.appro.form_montant'), 'right') !!}
          </tr>
        </thead>
        <tbody>
          @php $total = '0.00'; @endphp
          @foreach ($cLignes as $index => $ligne)
            @php $montant = bcmul((string) ($ligne['quantite'] ?: '0'), (string) ($ligne['prix_unitaire'] ?: '0'), 2); @endphp
            @php $total = bcadd($total, $montant, 2); @endphp
            <tr class="border-b border-slate-50" wire:key="cl-{{ $ligne['article_id'] }}">
              <td class="py-2">{{ $ligne['libelle'] }}</td>
              <td class="py-2 text-right">
                <input type="number" min="0" step="0.01" wire:model.live="cLignes.{{ $index }}.quantite"
                       class="w-24 text-right text-[13px] border border-slate-300 rounded-lg px-2 py-1">
                <span class="text-slate-400">{{ $ligne['unite'] }}</span>
                @error('cLignes.'.$index.'.quantite')<p class="text-[11px]" style="color:var(--erreur)">{{ $message }}</p>@enderror
              </td>
              <td class="py-2 text-right">
                <input type="number" min="0" step="1" wire:model.live="cLignes.{{ $index }}.prix_unitaire"
                       class="w-28 text-right text-[13px] border border-slate-300 rounded-lg px-2 py-1">
                @error('cLignes.'.$index.'.prix_unitaire')<p class="text-[11px]" style="color:var(--erreur)">{{ $message }}</p>@enderror
              </td>
              {{-- CALCULÉ, en lecture seule : un total saisi ne bougerait plus
                   quand une ligne change. --}}
              <td class="py-2 text-right font-semibold">{{ MontantFcfa::format($montant) }}</td>
            </tr>
          @endforeach
        </tbody>
        <tfoot>
          <tr class="font-bold">
            <td colspan="3" class="py-2.5 text-right">{{ __('achats_pwa.appro.form_total') }}</td>
            <td class="py-2.5 text-right text-[15px] text-[var(--navy)]">{{ MontantFcfa::format($total) }}</td>
          </tr>
        </tfoot>
      </table>

      <x-slot:pied>
        <button type="button" wire:click="$set('etatFormulaire', null)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerCommande"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('achats_pwa.appro.form_creer_commande') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ============================ RÉCEPTION (maître l.623-666) --}}
  @if ($etatFormulaire === 'reception' && $commandeEnReception !== null)
    <x-pwa.modale :titre="__('achats_pwa.appro.form_reception', ['commande' => $commandeEnReception->id])"
                  :sousTitre="__('achats_pwa.appro.form_reception_sous_titre', [
                      'fournisseur' => $commandeEnReception->fournisseur?->raison_sociale ?? '',
                      'date' => $commandeEnReception->date_commande?->format('d/m/Y') ?? '',
                  ])"
                  largeur="672px" fermer="$set('etatFormulaire', null)">
      <div>
        <label for="r-point" class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('achats_pwa.appro.form_point') }}</label>
        <select id="r-point" wire:model="rPointId" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @foreach ($points as $point)
            <option value="{{ $point->id }}">{{ $point->libelle }}</option>
          @endforeach
        </select>
        @error('rPointId')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
      </div>

      {{-- Même exclusion que la grille de commande ci-dessus : « reçu
           maintenant » est un `<input>`, ligne éditable. --}}
      <table class="w-full text-[13px]">
        <thead class="text-[11px] uppercase text-slate-500 border-b border-slate-200">
          <tr>
            {!! $entete(__('pwa.appro.col_article')) !!}
            {!! $entete(__('achats_pwa.appro.form_commandee'), 'right') !!}
            {!! $entete(__('achats_pwa.appro.form_deja_recu'), 'right') !!}
            {!! $entete(__('achats_pwa.appro.form_recu_maintenant'), 'right') !!}
          </tr>
        </thead>
        <tbody>
          @foreach ($commandeEnReception->lignes as $ligne)
            <tr class="border-b border-slate-50" wire:key="rl-{{ $ligne->article_id }}">
              <td class="py-2">{{ $ligne->article?->libelle ?? MontantFcfa::TIRET }}</td>
              <td class="py-2 text-right">{{ $ligne->quantite_commandee }} {{ $ligne->article?->unite_mesure }}</td>
              {{-- « Déjà reçu » : `bons_reception` n'a aucune ligne de détail
                   au schéma (PA-39). Le cumul par article n'est reconstituable
                   que depuis le journal de stock, qui mélangerait les entrées
                   d'autres origines. --}}
              <td class="py-2 text-right text-slate-400">{{ MontantFcfa::TIRET }}</td>
              <td class="py-2 text-right">
                <input type="number" min="0" step="0.01" wire:model="rQuantites.{{ $ligne->article_id }}"
                       class="w-24 text-right text-[13px] border border-slate-300 rounded-lg px-2 py-1">
              </td>
            </tr>
          @endforeach
        </tbody>
      </table>

      @error('rQuantites')<p class="text-[12px]" style="color:var(--erreur)">{{ $message }}</p>@enderror

      <p class="text-[12px] text-slate-500 bg-slate-50 rounded-lg p-3">{!! __('achats_pwa.appro.form_avertissement_double') !!}</p>

      <x-slot:pied>
        <button type="button" wire:click="$set('etatFormulaire', null)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerReception"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('achats_pwa.appro.form_valider_reception') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ============================ RÉGLER (maître l.694, PA-165) — troisième
       fenêtre de `#fond-modale` : PORTÉE depuis le 02/09/2026, comme les deux
       précédentes, par le châssis partagé `<x-pwa.modale>`. --}}
  @if ($etatFormulaire === 'reglement')
    <x-pwa.modale :titre="__('achats_pwa.appro.form_reglement', ['fournisseur' => $regFournisseurNom])"
                  :sousTitre="__('achats_pwa.appro.form_reglement_sous_titre', [
                      'commande' => $regCommandeId,
                      'reste' => MontantFcfa::format($regMontant),
                  ])"
                  largeur="420px" fermer="$set('etatFormulaire', null)">
      <div>
        <label for="reg-montant" class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('achats_pwa.appro.form_montant_regle') }}</label>
        <input id="reg-montant" type="number" min="1" step="1" wire:model="regMontant"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
        @error('regMontant')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
      </div>
      <div>
        <label for="reg-tresorerie" class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('achats_pwa.appro.form_tresorerie') }}</label>
        <select id="reg-tresorerie" wire:model="regTresorerie" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @foreach (\App\Domain\Depenses\Services\DepenseService::TRESORERIES as $cle => $tresorerie)
            <option value="{{ $cle }}">{{ __(match ($cle) {
                'momo' => 'achats_pwa.appro.tresorerie_momo',
                'banque' => 'achats_pwa.appro.tresorerie_banque',
                default => 'achats_pwa.appro.tresorerie_caisse',
            }) }}</option>
          @endforeach
        </select>
      </div>
      @error('selection')<p class="text-[12px]" style="color:var(--erreur)">{{ $message }}</p>@enderror
      <x-slot:pied>
        <button type="button" wire:click="$set('etatFormulaire', null)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerReglement"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('achats_pwa.appro.form_valider_reglement') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ============================ EXPORT — le châssis PARTAGÉ --}}
  @if ($etatFormulaire === 'export')
    @include('pwa.partials.modale-export', ['titre' => __('achats_pwa.export.titre_appro')])
    @error('formatExport')
      <p class="fixed bottom-5 right-5 z-50 rounded-lg px-4 py-3 text-[13px] font-semibold text-white"
         style="background:var(--erreur)">{{ $message }}</p>
    @enderror
  @endif

</div>

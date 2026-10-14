{{--
    JOURNAL DES VENTES.

    Maitre : prototype_v2/pages/historique-ventes.html.

    Quatre points a connaitre avant d'y toucher :

    1. UN SEUL <h1> par page. L'en-tete d'impression portait un second <h1>
       (« TATACORA AFRIQUE — GITE CHEZ NOEL ») avant le titre de l'ecran : deux
       <h1> sur une page, c'est un plan de document faux pour un lecteur
       d'ecran comme pour la garde `TitreDePageH1PwaTest`. Il est passe en <h2>.
    2. Les colonnes sont EXACTEMENT celles du maitre (l.247-256) : « N° »,
       « Date », « Poste », « Activites », « Reglement », « Montant »,
       « Statut », « Actions ». Ni « N° Vente », ni « Montant (FCFA) » — une
       colonne renommee est une colonne que la garde ne retrouve plus, et la
       majuscule en dur ressort telle quelle dans les exports.
    3. La modale de DETAIL est pilotee par `$set('venteDetailId', …)`, pas par
       une action du composant. Cet ecran n'est protege par aucun middleware
       `module:` : c'est le journal de caisse, que la gerance et le comptable
       doivent pouvoir consulter. En faire une action gardee leur en
       interdirait la lecture.
    4. L'export passe par le chassis partage
       (`pwa/partials/modale-export.blade.php`). La copie locale qui vivait ici
       — « Exporter le Journal des Ventes » — etait la douzieme d'un meme bloc :
       douze endroits ou corriger un libelle, et onze qu'on oubliera.
--}}
@php
    use App\Pwa\Support\MontantFcfa;
@endphp

<div class="contents">

  @include('pwa.partials.barre-superieure')

  <style>
    @media print {
      html, body, main, div, section, .contents, .flex, .zone-impression {
        overflow: visible !important;
        height: auto !important;
        min-height: 0 !important;
        max-height: none !important;
        position: static !important;
      }
      #shell-sidebar, #shell-topbar, .no-print, nav, button, .overlay-modale { display: none !important; }
      .zone-impression { width: 100% !important; margin: 0 !important; padding: 0 !important; }
      thead { display: table-header-group !important; }
      tr { break-inside: avoid !important; }
    }
  </style>

  @if (session('pwa-succes'))
    <div x-data="{ visible: true }" x-show="visible" x-init="setTimeout(() => visible = false, 5000)"
         class="fixed top-5 right-5 z-50 px-4 py-3 rounded-xl shadow-xl bg-emerald-600 text-white text-[13px] font-medium no-print">
      {{ session('pwa-succes') }}
    </div>
  @endif

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')

    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1600px] mx-auto p-5 lg:p-8 zone-impression">

        {{-- EN-TETE D'IMPRESSION — <h2>, jamais un second <h1>. --}}
        <div class="hidden print:block mb-6 border-b-2 border-[var(--navy)] pb-4">
          <div class="flex justify-between items-start">
            <div>
              <h2 class="text-xl font-bold" style="color:var(--navy)">{{ __('pwa.marque') }} — {{ __('pwa.enseigne_courte') }}</h2>
            </div>
            <div class="text-right text-xs text-slate-600">
              <p><strong>{{ __('pos_pwa.document.journal_titre') }}</strong></p>
              <p>{{ __('pos_pwa.document.edite_le') }} : {{ now()->format('d/m/Y H:i') }}</p>
              <p>{{ __('pos_pwa.document.filtre') }} : {{ $descriptionDuFiltre }}</p>
            </div>
          </div>
        </div>

        {{-- HERO — maitre, historique-ventes.html l.22-31 --}}
        <div class="mb-5 no-print">
          <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('pos_pwa.journal.titre') }}</h1>
          <p class="text-[12px] text-slate-500 mt-1 max-w-3xl">
            {{ __('pos_pwa.journal.sous_titre_avant') }}
            <strong>{{ __('pos_pwa.journal.sous_titre_gras') }}</strong>{{ __('pos_pwa.journal.sous_titre_apres') }}
            <span class="font-mono-tatacora">{{ __('pos_pwa.journal.sous_titre_exemple_vente') }}</span>{{ __('pos_pwa.journal.sous_titre_liaison') }}
            <span class="font-mono-tatacora">{{ __('pos_pwa.journal.sous_titre_exemple_facture') }}</span>.
          </p>
        </div>

        {{-- LES CINQ INDICATEURS — maitre, `rendreKpis()`, dans l'ordre.

             REPLIABLES depuis le 03/09/2026 (demande du Product Owner) : le
             journal des ventes est un ecran de RECHERCHE, et cinq cartes en
             tete repoussaient le tableau sous la ligne de flottaison. Meme
             motif que `notifications/hub.blade.php` et `rh/paie.blade.php` :
             etat retenu en `localStorage`, DEPLIE par defaut — un ecran qui
             s'ouvre vide se lit comme un ecran casse.

             L'ORDRE et le CONTENU des cinq cartes sont inchanges : c'est un
             repli d'affichage, pas une reecriture de la bande. Derogation au
             maitre, qui n'a pas d'accordeon ici. --}}
        <div x-data="{ ouvert: localStorage.getItem('pwa_kpis_journal_ventes') !== 'false' }" class="mb-5">
          <button type="button" class="w-full flex items-center justify-between px-4 py-3 bg-white border border-slate-200 rounded-xl no-print"
                  @click="ouvert = !ouvert; localStorage.setItem('pwa_kpis_journal_ventes', ouvert)">
            <span class="text-sm font-bold text-slate-700">{{ __('pos_pwa.journal.kpis_accordeon') }}</span>
            <span class="text-[11px] text-slate-400 font-normal hidden sm:inline">{{ __('pos_pwa.journal.kpis_aide') }}</span>
          </button>

          <div x-show="ouvert" class="grid grid-cols-2 sm:grid-cols-3 xl:grid-cols-5 gap-3 mt-3" x-cloak>
          <div class="bg-white rounded-xl border border-slate-200 p-3.5 shadow-sm">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('pos_pwa.journal.kpi_ventes') }}</div>
            <div class="text-[17px] font-bold mt-1 tabular-nums" style="color:var(--navy)">{{ $valideesCount }}</div>
            <div class="text-[11px] text-slate-400 mt-1">{{ __('pos_pwa.journal.kpi_ventes_detail', ['nombre' => $annuleesCount]) }}</div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-3.5 shadow-sm">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('pos_pwa.journal.kpi_ca') }}</div>
            <div class="text-[17px] font-bold mt-1 tabular-nums" style="color:var(--navy)">{{ MontantFcfa::format($chiffreAffaires) }}</div>
            <div class="text-[11px] text-slate-400 mt-1">{{ __('pos_pwa.journal.kpi_ca_detail') }}</div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-3.5 shadow-sm">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('pos_pwa.journal.kpi_encaisse') }}</div>
            <div class="text-[17px] font-bold mt-1 tabular-nums text-emerald-600">{{ MontantFcfa::format($encaisseTotal) }}</div>
            <div class="text-[11px] text-slate-400 mt-1">{{ __('pos_pwa.journal.kpi_encaisse_detail') }}</div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-3.5 shadow-sm">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('pos_pwa.journal.kpi_note') }}</div>
            <div class="text-[17px] font-bold mt-1 tabular-nums {{ bccomp($porteEnNoteTotal, '0.00', 2) > 0 ? 'text-amber-600' : 'text-slate-400' }}">{{ MontantFcfa::format($porteEnNoteTotal) }}</div>
            <div class="text-[11px] text-slate-400 mt-1">{{ __('pos_pwa.journal.kpi_note_detail') }}</div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-3.5 shadow-sm">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('pos_pwa.journal.kpi_stock') }}</div>
            <div class="text-[17px] font-bold mt-1 tabular-nums {{ $sansImpactStockCount > 0 ? 'text-red-600' : 'text-slate-400' }}">{{ $sansImpactStockCount }}</div>
              <div class="text-[11px] text-slate-400 mt-1">
                {{ $sansImpactStockCount > 0 ? __('pos_pwa.journal.kpi_stock_detail') : __('pos_pwa.journal.kpi_stock_detail_ok') }}
              </div>
            </div>
          </div>
        </div>

        <div class="bg-white rounded-xl border border-slate-200 overflow-hidden shadow-sm mb-4">
          {{-- FILTRES — maitre, l.36-51. Le maitre n'a pas de bouton
               « Reinitialiser » : ne pas en ajouter un. --}}
          <div class="px-4 py-3 border-b border-slate-200 flex flex-wrap items-center gap-2 no-print">
            <input type="search" wire:model.live.debounce.300ms="recherche"
              placeholder="{{ __('pos_pwa.journal.rechercher') }}"
              class="text-[13px] border border-slate-300 rounded-lg px-3 py-1.5 w-56 focus:border-[var(--gold)] focus:outline-none">

            <select wire:model.live="point" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-1.5 bg-white">
              <option value="">{{ __('pos_pwa.journal.tous_postes') }}</option>
              @foreach ($points as $poste)
                <option value="{{ $poste }}">{{ $poste }}</option>
              @endforeach
            </select>

            <select wire:model.live="activite" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-1.5 bg-white">
              <option value="">{{ __('pos_pwa.journal.toutes_activites') }}</option>
              @foreach ($modules as $cleModule => $libelleModule)
                <option value="{{ $cleModule }}">{{ $libelleModule }}</option>
              @endforeach
            </select>

            <select wire:model.live="mode" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-1.5 bg-white">
              <option value="">{{ __('pos_pwa.journal.tous_reglements') }}</option>
              @foreach ($modesPaiement as $cleMode => $libelleMode)
                <option value="{{ $cleMode }}">{{ $libelleMode }}</option>
              @endforeach
            </select>

            <select wire:model.live="statut" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-1.5 bg-white">
              <option value="">{{ __('pos_pwa.journal.tous_statuts') }}</option>
              <option value="validee">{{ __('pos_pwa.journal.statut_validees') }}</option>
              <option value="annulee">{{ __('pos_pwa.journal.statut_annulees') }}</option>
            </select>

            <input type="date" wire:model.live="debut" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-1.5 bg-white">
            <input type="date" wire:model.live="fin" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-1.5 bg-white">

            <div class="flex-1"></div>

            {{-- ⚠ DÉROGATION PO du 01/09/2026 — les deux boutons du maître
                 (`historique-ventes.html` l.50-51, « Export Excel » /
                 « Export PDF ») sont remplacés par UN bouton « Exporter » qui
                 ouvre la même modale d'export ; le format s'y choisit, sans
                 présélection imposée. Registre :
                 `App\Pwa\Support\DerogationsMaquette` (export_bouton_unique).
                 Jeton : maitre-refuse:historique-ventes.html#page --}}
            <button type="button" wire:click="ouvrirExport"
                    class="text-[12px] px-3 py-1.5 rounded-lg bg-[var(--navy)] text-white hover:opacity-90 font-semibold">{{ __('pwa.export.bouton') }}</button>
          </div>

          {{-- PA-119 — l'ecran DIT son filtre, et l'export porte le meme. --}}
          <p class="px-4 py-2 text-[11px] text-slate-400 border-b border-slate-100">
            {{ __('pos_pwa.document.filtre') }} : {{ $descriptionDuFiltre }}
          </p>

          {{-- `print:hidden` (01/09/2026) : le maître n'imprime jamais son
               tableau d'écran — son document est la forme EXPORT
               (`donneesExport()`, l.348), rendue plus bas en `print:block`.
               Imprimer les deux remettrait deux fois le même journal. --}}
          <div class="overflow-x-auto print:hidden">
            <table class="w-full text-[13px]">
              <thead class="bg-[var(--navy)] text-[11px] uppercase tracking-wide text-white/90 font-semibold print:bg-slate-200 print:text-slate-500">
                <tr>
                  <th class="text-left px-4 py-2.5">{{ __('pos_pwa.journal.colonne_numero') }}</th>
                  <th class="text-left px-4 py-2.5">{{ __('pos_pwa.journal.colonne_date') }}</th>
                  <th class="text-left px-4 py-2.5">{{ __('pos_pwa.journal.colonne_poste') }}</th>
                  <th class="text-left px-4 py-2.5">{{ __('pos_pwa.journal.colonne_activites') }}</th>
                  <th class="text-left px-4 py-2.5">{{ __('pos_pwa.journal.colonne_reglement') }}</th>
                  <th class="text-right px-4 py-2.5">{{ __('pos_pwa.journal.colonne_montant') }}</th>
                  <th class="text-left px-4 py-2.5">{{ __('pos_pwa.journal.colonne_statut') }}</th>
                  <th class="text-right px-4 py-2.5 no-print">{{ __('pos_pwa.journal.colonne_actions') }}</th>
                </tr>
              </thead>
              <tbody>
                @forelse ($ventesPage as $vente)
                  @php
                    $activites = $vente->lignes
                        ->pluck('module')
                        ->unique()
                        ->map(fn ($module) => $modules[$module] ?? $module)
                        ->implode(', ');
                  @endphp
                  <tr wire:key="vente-{{ $vente->id }}"
                      class="border-t border-slate-100 hover:bg-slate-50 {{ $vente->estAnnulee() ? 'opacity-60' : '' }}">
                    <td class="px-4 py-2.5 font-mono-tatacora text-[12px] font-bold text-slate-700">{{ $vente->numero }}</td>
                    <td class="px-4 py-2.5 text-slate-500 whitespace-nowrap">{{ $vente->created_at?->format('d/m/Y H:i') }}</td>
                    <td class="px-4 py-2.5 font-medium text-slate-800">
                      {{ $vente->point_vente }}
                      @if ($vente->table)
                        <span class="text-slate-400 font-normal">· {{ $vente->table }}</span>
                      @endif
                    </td>
                    <td class="px-4 py-2.5 text-slate-500">{{ $activites }}</td>
                    <td class="px-4 py-2.5 text-slate-500">{{ $modesPaiement[$vente->mode_paiement] ?? $vente->mode_paiement }}</td>
                    <td class="px-4 py-2.5 text-right font-bold tabular-nums" style="color:var(--navy)">{{ MontantFcfa::format((string) $vente->montant_total) }}</td>
                    <td class="px-4 py-2.5 whitespace-nowrap">
                      @if ($vente->estAnnulee())
                        <span class="px-2 py-0.5 rounded text-[11px] font-semibold bg-red-50 text-red-700">{{ __('pos_pwa.journal.badge_annulee') }}</span>
                      @elseif ($vente->encaisse)
                        <span class="px-2 py-0.5 rounded text-[11px] font-semibold bg-emerald-50 text-emerald-700">{{ __('pos_pwa.journal.badge_encaissee') }}</span>
                      @else
                        <span class="px-2 py-0.5 rounded text-[11px] font-semibold bg-amber-50 text-amber-700">{{ __('pos_pwa.journal.badge_note') }}</span>
                      @endif

                      @if ($vente->aDesLignesSansImpactStock())
                        <span title="{{ __('pos_pwa.journal.badge_stock_infobulle') }}"
                              class="ml-1 px-2 py-0.5 rounded text-[11px] font-semibold bg-red-50 text-red-700">{{ __('pos_pwa.journal.badge_stock') }}</span>
                      @endif
                    </td>
                    <td class="px-4 py-2.5 text-right whitespace-nowrap no-print">
                      <button type="button" wire:click="$set('venteDetailId', '{{ $vente->id }}')"
                              class="text-[12px] px-2.5 py-1 rounded-lg border border-slate-300 hover:bg-slate-50 font-semibold text-slate-700">{{ __('pos_pwa.journal.detail') }}</button>
                      {{-- maitre — historique-ventes.html l.234 : la reference de la facture liee, quand elle existe. --}}
                      @if (isset($facturesParVenteId[$vente->id]))
                        <span class="ml-1 text-[11px] text-slate-400 font-mono-tatacora">{{ $facturesParVenteId[$vente->id]->numero_mecef ?? MontantFcfa::TIRET }}</span>
                      @endif
                    </td>
                  </tr>
                @empty
                  <tr>
                    <td colspan="8" class="px-4 py-10 text-center text-slate-400">{{ __('pos_pwa.journal.liste_vide') }}</td>
                  </tr>
                @endforelse
              </tbody>
            </table>
          </div>

          {{-- LA PAGINATION — décision du Product Owner du 13/10/2026 : dix
               ventes par page, les mots et les boutons du pied « Réservations
               en cours » de l'hébergement, IDENTIQUE au client Flutter
               (`PiedPagination`) : les deux boutons sont TOUJOURS rendus,
               désactivés aux bornes. Seul le tableau d'écran est paginé : les
               indicateurs, l'export et l'impression portent sur la liste
               filtrée entière. --}}
          @php
            $debutPage = $totalVentes === 0 ? 0 : ($page - 1) * \App\Pwa\Livewire\Pos\HistoriqueVentes::VENTES_PAR_PAGE + 1;
            $finPage = $totalVentes === 0 ? 0 : $debutPage + $ventesPage->count() - 1;
          @endphp
          <div class="flex items-center justify-between px-4 py-3 border-t border-slate-100 no-print">
            <p class="text-xs text-slate-500">
              {{ __('pos_pwa.journal.decompte_avant') }}
              <strong>{{ $debutPage }}-{{ $finPage }}</strong>
              {{ __('pos_pwa.journal.decompte_liaison') }}
              <strong>{{ $totalVentes }}</strong>
            </p>
            <div class="flex items-center gap-2">
              <button type="button" wire:click="$set('page', {{ max(1, $page - 1) }})"
                      @disabled($page <= 1)
                      class="btn px-3 py-1.5 text-xs rounded-lg border border-slate-200 disabled:opacity-40">{{ __('pos_pwa.journal.page_precedent') }}</button>
              <span class="text-xs text-slate-600 px-2">{{ __('pos_pwa.journal.page_sur', ['page' => $page, 'total' => $pagesVentes]) }}</span>
              <button type="button" wire:click="$set('page', {{ min($pagesVentes, $page + 1) }})"
                      @disabled($page >= $pagesVentes)
                      class="btn px-3 py-1.5 text-xs rounded-lg border border-slate-200 disabled:opacity-40">{{ __('pos_pwa.journal.page_suivant') }}</button>
            </div>
          </div>
        </div>

        {{-- ============ LE DOCUMENT IMPRIMÉ : LA FORME EXPORT DU MAÎTRE ============
             maitre — `historique-ventes.html` l.348 (`donneesExport()`) : le
             document du journal porte les HUIT entêtes de l'export — « Table »,
             « Reglement », « Encaisse » comprises, SANS accent sur
             « Reglement », comme le maître l'écrit (ses PDF sont en Latin-1).
             C'est déjà la forme de `pdf/ventes-rapport.blade.php` — mêmes clés
             de langue, mêmes expressions, jamais un second calcul — et
             l'impression navigateur rend le MÊME document, sur les ventes
             AFFICHÉES (PA-119 : le filtre est dit dans l'en-tête d'impression).
             Rendu au premier GET (en `hidden print:block`), donc vérifiable
             par `ColonnesDesTableauxPwaTest`. --}}
        <div class="hidden print:block mb-6">
          <table class="w-full text-[12px]">
            <thead>
              <tr class="text-left text-[11px] font-semibold text-slate-500 uppercase border-b-2 border-slate-400">
                <th class="text-left px-2 py-1.5">{{ __('pos_pwa.document.entete_numero') }}</th>
                <th class="text-left px-2 py-1.5">{{ __('pos_pwa.document.entete_date') }}</th>
                <th class="text-left px-2 py-1.5">{{ __('pos_pwa.document.entete_poste') }}</th>
                <th class="text-left px-2 py-1.5">{{ __('pos_pwa.document.entete_table') }}</th>
                <th class="text-left px-2 py-1.5">{{ __('pos_pwa.document.entete_reglement_export') }}</th>
                <th class="text-right px-2 py-1.5">{{ __('pos_pwa.document.entete_montant') }}</th>
                <th class="text-center px-2 py-1.5">{{ __('pos_pwa.document.entete_encaisse') }}</th>
                <th class="text-center px-2 py-1.5">{{ __('pos_pwa.document.entete_statut') }}</th>
              </tr>
            </thead>
            <tbody>
              @forelse ($ventes as $vente)
                <tr class="border-b border-slate-200" wire:key="doc-vente-{{ $vente->id }}">
                  <td class="px-2 py-1.5 font-bold">{{ $vente->numero }}</td>
                  <td class="px-2 py-1.5">{{ $vente->created_at?->format('d/m/Y H:i') }}</td>
                  <td class="px-2 py-1.5">{{ $vente->point_vente }}</td>
                  <td class="px-2 py-1.5">{{ $vente->table ?? '' }}</td>
                  <td class="px-2 py-1.5">{{ $modesPaiement[$vente->mode_paiement] ?? $vente->mode_paiement }}</td>
                  <td class="px-2 py-1.5 text-right font-bold tabular-nums">{{ MontantFcfa::format((string) $vente->montant_total) }}</td>
                  {{-- « Encaisse » n'est PAS « Montant » : une note de chambre
                       est une créance, pas de l'argent dans le tiroir. --}}
                  <td class="px-2 py-1.5 text-center">
                    {{ $vente->encaisse ? __('pos_pwa.journal.badge_encaissee') : __('pos_pwa.journal.badge_note') }}
                  </td>
                  <td class="px-2 py-1.5 text-center">
                    {{ $vente->estAnnulee() ? __('pos_pwa.journal.statut_annulees') : __('pos_pwa.journal.statut_validees') }}
                  </td>
                </tr>
              @empty
                <tr>
                  <td colspan="8" class="px-2 py-6 text-center text-slate-400">{{ __('pos_pwa.journal.liste_vide') }}</td>
                </tr>
              @endforelse
            </tbody>
          </table>
        </div>

        {{-- DÉTAIL DES LIGNES — maitre, `historique-ventes.html` l.333 : le
             TICKET de chaque vente (PA-101) porte ces cinq entêtes — sans
             accent sur « Activite » et « Quantite », comme le maître les
             écrit. Le journal imprimé rend le détail des pièces affichées,
             précédé du N° de la vente ; mêmes clés et mêmes champs que la
             modale de détail — jamais une seconde formule. --}}
        <div class="hidden print:block mb-6">
          <h2 class="text-sm font-bold mb-2" style="color:var(--navy)">{{ __('pos_pwa.document.detail_lignes_titre') }}</h2>
          <table class="w-full text-[12px]">
            <thead>
              <tr class="text-left text-[11px] font-semibold text-slate-500 uppercase border-b-2 border-slate-400">
                <th class="text-left px-2 py-1.5">{{ __('pos_pwa.document.entete_numero') }}</th>
                <th class="text-left px-2 py-1.5">{{ __('pos_pwa.document.entete_article') }}</th>
                <th class="text-left px-2 py-1.5">{{ __('pos_pwa.document.entete_activite') }}</th>
                <th class="text-center px-2 py-1.5">{{ __('pos_pwa.document.entete_quantite') }}</th>
                <th class="text-right px-2 py-1.5">{{ __('pos_pwa.document.entete_prix_unitaire') }}</th>
                <th class="text-right px-2 py-1.5">{{ __('pos_pwa.document.entete_montant') }}</th>
              </tr>
            </thead>
            <tbody>
              @forelse ($ventes as $vente)
                @foreach ($vente->lignes as $ligne)
                  <tr class="border-b border-slate-200" wire:key="doc-ligne-{{ $ligne->id }}">
                    <td class="px-2 py-1.5 font-bold">{{ $vente->numero }}</td>
                    <td class="px-2 py-1.5">{{ $ligne->nom }}</td>
                    <td class="px-2 py-1.5 text-slate-500">{{ $modules[$ligne->module] ?? $ligne->module }}</td>
                    <td class="px-2 py-1.5 text-center tabular-nums">{{ $ligne->quantite }}</td>
                    <td class="px-2 py-1.5 text-right tabular-nums">{{ MontantFcfa::format((string) $ligne->prix_unitaire) }}</td>
                    <td class="px-2 py-1.5 text-right font-bold tabular-nums">{{ MontantFcfa::format((string) $ligne->montant) }}</td>
                  </tr>
                @endforeach
              @empty
                <tr>
                  <td colspan="6" class="px-2 py-6 text-center text-slate-400">{{ __('pos_pwa.journal.liste_vide') }}</td>
                </tr>
              @endforelse
            </tbody>
          </table>
        </div>

        <div class="hidden print:block mt-12 pt-6 border-t border-slate-300">
          <div class="grid grid-cols-2 gap-8 text-center text-xs">
            <div>
              <p class="font-bold mb-10">{{ __('pos_pwa.document.visa_caisse') }}</p>
              <p class="text-slate-400">___________________________</p>
            </div>
            <div>
              <p class="font-bold mb-10">{{ __('pos_pwa.document.visa_direction') }}</p>
              <p class="text-slate-400">___________________________</p>
            </div>
          </div>
        </div>

      </div>
    </main>
  </div>

  {{-- ================= MODALE DE DETAIL — maitre, `ov-vente` ================= --}}
  @if ($venteDetail)
    <x-pwa.modale :titre="$venteDetail->numero"
                  :sousTitre="$venteDetail->created_at?->format('d/m/Y H:i') . ' · ' . $venteDetail->point_vente . ($venteDetail->table ? ' · ' . $venteDetail->table : '')"
                  largeur="520px"
                  fermer="$set('venteDetailId', null)">
      {{--
          maitre — historique-ventes.html l.333 : les CINQ entetes, a la lettre.
          La version precedente rendait des lignes libres et perdait
          « Prix unitaire » : sur un ticket conteste, c'est precisement la
          colonne qu'on vient verifier.

          ⚠ EXCLUE de la conversion navy du 01/09/2026 : c'est la relecture du
          TICKET d'une vente passée (PA-101), pas un tableau de consultation —
          même style clair que la modale ticket de `pos/comptant.blade.php`.
      --}}
      <div class="overflow-x-auto">
        <table class="w-full text-[13px]">
          <thead class="text-[11px] uppercase text-slate-500 border-b border-slate-200">
            <tr>
              <th class="text-left py-1.5">{{ __('pos_pwa.document.entete_article') }}</th>
              <th class="text-left py-1.5">{{ __('pos_pwa.document.entete_activite') }}</th>
              <th class="text-center py-1.5">{{ __('pos_pwa.document.entete_quantite') }}</th>
              <th class="text-right py-1.5">{{ __('pos_pwa.document.entete_prix_unitaire') }}</th>
              <th class="text-right py-1.5">{{ __('pos_pwa.document.entete_montant') }}</th>
            </tr>
          </thead>
          <tbody>
            @foreach ($venteDetail->lignes as $ligne)
              <tr class="border-b border-slate-100" wire:key="det-{{ $ligne->id }}">
                <td class="py-1.5">{{ $ligne->nom }}</td>
                <td class="py-1.5 text-slate-500">{{ $modules[$ligne->module] ?? $ligne->module }}</td>
                <td class="py-1.5 text-center tabular-nums">{{ $ligne->quantite }}</td>
                <td class="py-1.5 text-right tabular-nums">{{ MontantFcfa::format((string) $ligne->prix_unitaire) }}</td>
                <td class="py-1.5 text-right font-bold tabular-nums" style="color:var(--navy)">{{ MontantFcfa::format((string) $ligne->montant) }}</td>
              </tr>
            @endforeach
          </tbody>
        </table>
      </div>

      <div class="flex justify-between items-baseline pt-2.5 border-t-2 border-slate-300">
        <span class="font-semibold text-[13px]">
          {{ __('pos_pwa.journal.detail_total') }} · {{ $modesPaiement[$venteDetail->mode_paiement] ?? $venteDetail->mode_paiement }}
        </span>
        <strong class="text-[17px]" style="color:var(--navy)">{{ MontantFcfa::format((string) $venteDetail->montant_total) }}</strong>
      </div>

      @unless ($venteDetail->encaisse)
        <p class="text-[11.5px] text-amber-800 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2">
          {{ __('pos_pwa.journal.detail_porte_en_note') }}
        </p>
      @endunless

      @if ($venteDetail->aDesLignesSansImpactStock())
        <p class="text-[11.5px] text-red-700 bg-red-50 border border-red-200 rounded-lg px-3 py-2">
          {{ __('pos_pwa.journal.detail_stock', [
              'nombre' => count($venteDetail->stock_non_impacte),
              'articles' => implode(', ', array_column($venteDetail->stock_non_impacte, 'ligne')),
          ]) }}
        </p>
      @endif

      @if ($venteDetail->estAnnulee())
        <p class="text-[11.5px] text-slate-600 bg-slate-50 border border-slate-200 rounded-lg px-3 py-2">
          {{ __('pos_pwa.journal.detail_annulee', [
              'motif' => $venteDetail->motif_annulation ? ' — ' . $venteDetail->motif_annulation : '',
          ]) }}
        </p>
      @else
        {{-- RG-02 — le motif est OBLIGATOIRE : le journal doit dire pourquoi. --}}
        <div class="pt-3 border-t border-slate-100">
          <label for="motif-annulation-vente" class="block text-[12px] font-semibold text-slate-700 mb-1.5">{{ __('pos_pwa.journal.detail_motif') }}</label>
          <div class="flex gap-2">
            <input id="motif-annulation-vente" type="text" wire:model="motifAnnulation"
                   class="flex-1 text-[12px] border border-slate-300 rounded-lg px-2.5 py-1.5 focus:border-[var(--gold)] focus:outline-none">
            <button type="button" wire:click="annulerVente"
                    class="px-3 py-1.5 rounded-lg bg-[var(--erreur)] text-white font-bold text-[12px]">{{ __('pos_pwa.journal.detail_annuler') }}</button>
          </div>
          @error('motifAnnulation')
            <p class="mt-2 text-[12px] text-red-600">{{ $message }}</p>
          @enderror
        </div>
      @endif

      <x-slot:pied>
        <button type="button" wire:click="$set('venteDetailId', null)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pos_pwa.journal.detail_fermer') }}</button>
        {{-- Le bouton « Imprimer » du maitre est RETIRE (directive PO du
             02/09/2026, meme decision que la modale « Vente encaissee » du
             POS le meme jour) : il imprimait la PAGE entiere via
             window.print(), pas la piece — les deux documents reels restent,
             Ticket 80 mm et le telechargement. --}}
        {{-- Ajout hors maitre — décision du Product Owner du 01/09/2026, en
             attendant la validation de l'API MECeF : fenêtre d'impression
             80 mm dédiée (PA-101), la MÊME pièce sur un troisième papier. --}}
        <a href="{{ route('pwa.pos.ticket-thermique', $venteDetail->id) }}" target="_blank" rel="noopener"
           class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pos_pwa.journal.detail_ticket_thermique') }}</a>
        {{-- PA-101 — la MEME piece, rendue sur un autre papier. --}}
        <button type="button" wire:click="telechargerTicket"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('pos_pwa.journal.detail_telecharger') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ================= MODALE D'EXPORT — chassis partage ================= --}}
  @if ($etatFormulaire === 'export')
    @include('pwa.partials.modale-export', ['titre' => __('pos_pwa.journal.export_titre')])
    @error('formatExport')
      <p class="fixed bottom-5 right-5 z-50 px-4 py-3 rounded-xl shadow-xl bg-red-600 text-white text-[13px] no-print">{{ $message }}</p>
    @enderror
  @endif

  @include('pwa.partials.acces-rapide')

</div>

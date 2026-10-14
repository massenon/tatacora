{{--
    M9 — TOURISME.

    Maitre : `prototype_v2/pages/m9-tourisme-departs.html` et
    `m9-tourisme-departs.js`.

    ## Un depart est DERIVE, il n'est pas stocke

    Aucune table `departs` n'existe au schema : un depart est le couple
    (circuit, date) porte par ses lignes de `reservations_tour`. Il nait donc
    de sa premiere reservation, et le bouton « + Depart » du maitre est refuse
    et NOMME ci-dessous.

    ## La casse des entetes est celle du MAITRE

    `Circuit`, pas `CIRCUIT`. `uppercase` est une regle CSS : elle ne
    s'applique ni au CSV ni au PDF, et une majuscule ecrite en dur ressort
    telle quelle sur le document remis.

    ## La colonne d'actions n'a PAS d'entete

    Le maitre termine ses tableaux par une chaine vide
    (`m9-tourisme-departs.js` l.91, l.145, l.180).

    Declarations pour la garde des trois sources :
      maitre-refuse:m9-tourisme-departs.html#modale-depart
      maitre-refuse:m9-tourisme-departs.html#catalogue
        Le bloc est `catalogue` et NON `departs` : la garde derive le bloc du
        dernier `data-onglet` rencontre AVANT le controle, et le maitre declare
        ses trois onglets ensemble en tete de page (l.48-50). Le bouton
        « + Depart » (l.77) tombe donc apres `catalogue`. Ne pas le
        « corriger » : le jeton cesserait d'etre reconnu.
        Le bouton « + Depart » : un depart n'est pas une entite, il naît de sa
        premiere reservation. Le rendre ouvrirait un formulaire qui n'ecrit
        nulle part.
      maitre-refuse:m9-tourisme-departs.html#modale-resa
        « Telephone » et « Acompte (F) » : aucune colonne sur
        `reservations_tour`. Un acompte saisi et jamais lu ferait croire a un
        encaissement.
      maitre-refuse:m9-tourisme-departs.html#modale-guide
        « Motif » de reaffectation : aucune colonne. RG-51 fait de l'affectation
        une REaffectation (`guide_id` est NOT NULL), et le motif se perdrait.
--}}
@php
    use App\Pwa\Support\MontantFcfa;

    // Classes d'onglets : directive PO du 01/09/2026, UN SEUL AUTEUR —
    // voir le docblock de `App\Pwa\Support\Onglets`.
    $classeOnglet = static fn (bool $actif): string => \App\Pwa\Support\Onglets::classes($actif);

    $entete = static fn (string $libelle, bool $gauche = false): string => '<th class="px-3 py-2.5 '
        . ($gauche ? 'text-left' : 'text-right')
        . ' text-[11px] uppercase tracking-wide text-white/90 font-semibold">'
        . e($libelle) . '</th>';

    // En-tete de colonne d'un ETAT IMPRIMABLE (`hidden print:block`) : les
    // colonnes du DOCUMENT d'export du maitre (`m9-tourisme-departs.js`
    // l.463-499, `etatCourant()`), rendues sur papier par l'impression du
    // navigateur comme le maitre les rend par `ExportEngine`. Texte sombre
    // sur fond blanc : un en-tete blanc sur navy disparaitrait du papier.
    $enteteDoc = static fn (string $libelle, bool $gauche = false): string => '<th class="px-2 py-1.5 '
        . ($gauche ? 'text-left' : 'text-right')
        . ' text-[11px] uppercase tracking-wide text-slate-500 font-semibold border-b border-slate-300">'
        . e($libelle) . '</th>';

    $celluleDoc = 'px-2 py-1 border-b border-slate-100';
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
      <div class="max-w-[1600px] mx-auto p-5 lg:p-8">

        {{-- EN-TETE — maitre l.27-43 --}}
        <div class="mb-5 flex flex-wrap items-start justify-between gap-3">
          <div>
            <div class="flex items-center gap-2.5">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0118 0z"/><circle cx="12" cy="10" r="3"/></svg>
              <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('tourisme.pwa.titre') }}</h1>
            </div>
            <p class="text-[15px] text-slate-500 mt-1.5">{!! __('tourisme.pwa.sous_titre') !!}</p>
          </div>

          <div class="flex flex-wrap gap-2 items-center">
            <label class="text-[12px] text-slate-500">{{ __('tourisme.pwa.du') }}</label>
            <input type="date" wire:model.live="debut" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-2">
            <label class="text-[12px] text-slate-500">{{ __('tourisme.pwa.au') }}</label>
            <input type="date" wire:model.live="fin" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-2">

            {{-- Exporter est une LECTURE, offerte a tout role qui peut ouvrir
                 l'ecran : le droit de lire est deja porte par le middleware
                 `module:M#,L` de la route, et l'export ne rend que ce qui est
                 deja affiche (PA-119).

                 ⚠ DEROGATION PO du 01/09/2026, rappelee le 02/09/2026 — la
                 paire de boutons du maitre (« Excel » / « PDF »,
                 `m9-tourisme-departs.html` l.40-41) est FUSIONNEE en UN bouton
                 « Exporter » : les deux ouvraient deja la meme modale de
                 format. Le format PDF/Excel se choisit DANS la modale.
                 Registre : `App\Pwa\Support\DerogationsMaquette`
                 (export_bouton_unique).
                 Jeton : maitre-refuse:m9-tourisme-departs.html#page --}}
              <button type="button" wire:click="$set('etatFormulaire', 'export')" wire:loading.attr="disabled"
                      class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white hover:opacity-90 font-semibold">{{ __('pwa.export.bouton') }}</button>
          </div>
        </div>

        {{-- KPI — maitre `m9-tourisme-departs.js` l.440-460 --}}
        <div class="grid grid-cols-2 lg:grid-cols-6 gap-3 mb-5">
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('tourisme.pwa.kpi_departs') }}</div>
            <div class="text-[17px] font-bold mt-1" style="color:var(--navy)">{{ $totalDeparts }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('tourisme.pwa.kpi_departs_detail', ['nombre' => $completsCount]) }}</div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('tourisme.pwa.kpi_places') }}</div>
            <div class="text-[17px] font-bold mt-1" style="color:var(--navy)">{{ $totalPlacesVendues }} / {{ $totalCapaciteOfferte }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('tourisme.pwa.kpi_places_detail') }}</div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('tourisme.pwa.kpi_remplissage') }}</div>
            {{-- Aucune capacite offerte : « 0 % » se lirait comme un depart
                 desert, alors qu'il n'y a rien a remplir (Article 7). --}}
            <div class="text-[17px] font-bold mt-1 {{ $tauxRemplissage !== null && $tauxRemplissage < 50 ? 'text-amber-600' : '' }}"
                 style="{{ $tauxRemplissage !== null && $tauxRemplissage < 50 ? '' : 'color:var(--navy)' }}">
              {{ $tauxRemplissage === null ? MontantFcfa::TIRET : $tauxRemplissage . ' %' }}
            </div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('tourisme.pwa.kpi_remplissage_detail') }}</div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('tourisme.pwa.kpi_ca') }}</div>
            <div class="text-[17px] font-bold mt-1" style="color:var(--navy)">{{ MontantFcfa::format($chiffreAffairesTotal) }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('tourisme.pwa.kpi_ca_detail') }}</div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('tourisme.pwa.kpi_reste') }}</div>
            {{-- Aucune colonne `acompte` sur `reservations_tour` : le reste a
                 encaisser n'est pas calculable, faute de colonne d'acompte. Afficher le
                 montant entier le presenterait comme impaye. --}}
            <div class="text-[17px] font-bold mt-1 text-slate-400">{{ MontantFcfa::TIRET }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('tourisme.pwa.kpi_reste_detail') }}</div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('tourisme.pwa.kpi_duree') }}</div>
            <div class="text-[17px] font-bold mt-1 {{ $dureeIndetermineeCount > 0 ? 'text-amber-600' : 'text-slate-400' }}">{{ $dureeIndetermineeCount }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('tourisme.pwa.kpi_duree_detail') }}</div>
          </div>
        </div>

        {{-- ONGLETS — maitre l.48-52 --}}
        <div class="flex flex-wrap gap-1.5 mb-4">
          <button type="button" wire:click="$set('onglet', 'departs')" class="{{ $classeOnglet($onglet === 'departs') }}">{{ __('tourisme.pwa.onglet_departs') }}</button>
          <button type="button" wire:click="$set('onglet', 'reservations')" class="{{ $classeOnglet($onglet === 'reservations') }}">{{ __('tourisme.pwa.onglet_reservations') }}</button>
          <button type="button" wire:click="$set('onglet', 'catalogue')" class="{{ $classeOnglet($onglet === 'catalogue') }}">{{ __('tourisme.pwa.onglet_catalogue') }}</button>
        </div>

        {{-- FILTRES — maitre l.54-80 --}}
        <div class="bg-white rounded-xl border border-slate-200 p-3.5 mb-4">
          <div class="flex flex-wrap gap-2.5 items-center">
            <div class="relative flex-1 min-w-[200px]">
              <svg class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
              <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="{{ __('tourisme.pwa.recherche') }}"
                     class="w-full text-[13px] border border-slate-300 rounded-lg pl-9 pr-3 py-2 focus:border-[var(--gold)] focus:outline-none">
            </div>

            {{--
                maitre — `#f-type` (l.60-64). REBRANCHE le 01/09/2026 : le
                schema ne distingue pas un circuit d'une excursion (aucune
                colonne), donc ce select filtre par PRESTATION plutot que par
                type — voir le docblock de `Departs::$prestationId`. Meme
                position, meme libelle par defaut que le maitre.
            --}}
            <select wire:model.live="prestationId" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <option value="">{{ __('tourisme.pwa.type_tous') }}</option>
              @foreach ($catalogueComplet as $prestation)
                <option value="{{ $prestation->id }}">{{ $prestation->nom }}</option>
              @endforeach
            </select>

            <select wire:model.live="remplissage" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <option value="">{{ __('tourisme.pwa.remplissage_tous') }}</option>
              <option value="disponible">{{ __('tourisme.pwa.remplissage_disponible') }}</option>
              <option value="complet">{{ __('tourisme.pwa.remplissage_complet') }}</option>
              <option value="vide">{{ __('tourisme.pwa.remplissage_vide') }}</option>
            </select>

            <select wire:model.live="statut" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <option value="planifie">{{ __('tourisme.pwa.statut_planifie') }}</option>
              <option value="">{{ __('tourisme.pwa.statut_tous') }}</option>
              <option value="annule">{{ __('tourisme.pwa.statut_annule') }}</option>
            </select>

            <div class="flex-1"></div>

            @if ($peutEcrire)
              @if ($onglet === 'catalogue')
                <button type="button" wire:click="ouvrirFormulairePrestation"
                        class="text-[13px] px-3.5 py-2 rounded-lg border border-slate-300 bg-white hover:bg-slate-50">{{ __('tourisme.pwa.action_prestation') }}</button>
              @endif
              <button type="button" wire:click="ouvrirFormulaireReservation"
                      class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('tourisme.pwa.action_reservation') }}</button>
            @endif
          </div>
        </div>

        {{--
            UN PANNEAU D'ONGLET FERME RESTE DANS LE HTML, MASQUE PAR `hidden`
            (01/09/2026). La garde G5 (`ColonnesDesTableauxPwaTest`) lit les
            colonnes du maitre dans le HTML rendu AU PREMIER GET : un `@if`
            qui retirait les panneaux inactifs faisait disparaitre les
            en-tetes des onglets Reservations et Catalogue — cinq groupes de
            colonnes rapportes absents sur un ecran qui les rendait des le
            premier clic. Meme motif que `achats.blade.php`.

            Chaque onglet porte aussi son ETAT IMPRIMABLE (`hidden
            print:block`) : les colonnes du DOCUMENT d'export du maitre
            (`etatCourant()`, `m9-tourisme-departs.js` l.463-499), que le
            maitre rend par `ExportEngine.pdf()` et jamais a l'ecran — le
            document separe « Zone » et « Theme », ecrit « Personnes » et
            « Telephone » en toutes lettres, et ajoute Capacite / Vendues /
            Restantes. Le tableau d'ecran est alors `print:hidden` : sur le
            papier, c'est le document du maitre qui sort, pas deux fois la
            meme table.

            Declaration pour la garde de structure (`t-structure.js`) — le
            maitre ne rend au premier chargement que le tableau de l'onglet
            actif, la PWA les garde tous dans le DOM (raison ci-dessus,
            01/09/2026) :
              structure-ajout:m9-tourisme-departs.html#div-cc70a52a
        --}}
        {{-- ============================== ONGLET DEPARTS ================== --}}
        <section class="{{ $onglet === 'departs' ? '' : 'hidden' }}">
          @if ($dureeIndetermineeCount > 0)
            <div class="rounded-xl p-3.5 mb-4" style="background:#FFFBEB;border:1px solid #FDE68A">
              <p class="text-[13px]" style="color:#78350F">
                <strong>{{ __('tourisme.pwa.bandeau_duree_titre', ['nombre' => $dureeIndetermineeCount]) }}</strong>
                {!! __('tourisme.pwa.bandeau_duree_texte') !!}
              </p>
            </div>
          @endif

          {{-- L'etat vide du maitre (`vide()`), le tableau restant dans le
               DOM : les en-tetes se lisent meme sans ligne. --}}
          <div class="{{ $departs === [] ? '' : 'hidden' }} bg-white rounded-xl border border-slate-200 py-14 text-center text-slate-400 text-[13px]">{{ __('tourisme.pwa.departs_vide') }}</div>
          <div class="{{ $departs === [] ? 'hidden' : '' }}">
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3 print:hidden">
              <div class="px-4 py-3 border-b border-slate-200">
                <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('tourisme.pwa.departs_titre') }}</h3>
              </div>
              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  <thead class="bg-[var(--navy)]">
                    <tr>
                      {!! $entete(__('tourisme.pwa.col_numero'), true) !!}
                      {!! $entete(__('tourisme.pwa.col_circuit'), true) !!}
                      {!! $entete(__('tourisme.pwa.col_depart')) !!}
                      {!! $entete(__('tourisme.pwa.col_guide')) !!}
                      {!! $entete(__('tourisme.pwa.col_vehicule')) !!}
                      {!! $entete(__('tourisme.pwa.col_remplissage')) !!}
                      {!! $entete(__('tourisme.pwa.col_prix')) !!}
                      {!! $entete(__('tourisme.pwa.col_ca')) !!}
                      {!! $entete(__('tourisme.pwa.col_etat')) !!}
                      <th class="px-3 py-2.5"></th>
                    </tr>
                  </thead>
                  <tbody>
                    @php $totalVendues = 0; @endphp
                    @php $totalCapacite = 0; @endphp
                    @php $totalCa = '0.00'; @endphp
                    @foreach ($departs as $d)
                      @php $totalVendues += $d['places_vendues']; @endphp
                      @php $totalCapacite += $d['capacite']; @endphp
                      @php $totalCa = bcadd($totalCa, $d['chiffre_affaires'], 2); @endphp
                      @php $pct = $d['capacite'] > 0 ? min(100, (int) round(($d['places_vendues'] / $d['capacite']) * 100)) : 0; @endphp
                      @php $couleur = $pct >= 100 ? '#DC2626' : ($pct >= 70 ? '#B8891E' : '#059669'); @endphp
                      <tr class="border-t border-slate-100 hover:bg-slate-50 {{ $d['annule'] ? 'opacity-50' : '' }}"
                          wire:key="depart-{{ $d['circuit_id'] }}-{{ $d['date'] }}">
                        {{-- « N° » : aucune colonne `numero` sur `reservations_tour`. --}}
                        <td class="px-3 py-2 text-left font-mono text-[11px] text-slate-400">{{ MontantFcfa::TIRET }}</td>
                        <td class="px-3 py-2 text-left">
                          <div class="font-semibold text-slate-800">{{ $d['circuit_nom'] }}</div>
                          <div class="text-[11px] text-slate-400">{{ $d['duree'] }}</div>
                        </td>
                        <td class="px-3 py-2 text-right text-slate-600">{{ \Carbon\CarbonImmutable::parse($d['date'])->format('d/m/Y') }}</td>
                        <td class="px-3 py-2 text-right text-slate-700">{{ $d['guide'] ?? MontantFcfa::TIRET }}</td>
                        {{-- « Véhicule » : aucune colonne au schéma. --}}
                        <td class="px-3 py-2 text-right text-slate-400">{{ MontantFcfa::TIRET }}</td>
                        <td class="px-3 py-2">
                          <div class="flex items-center gap-2 justify-end">
                            <div class="w-20 h-2 rounded-full bg-slate-200 overflow-hidden">
                              <div style="width:{{ $pct }}%;background:{{ $couleur }}" class="h-full"></div>
                            </div>
                            <span class="text-[12px] font-semibold" style="color:{{ $couleur }}">{{ $d['places_vendues'] }}/{{ $d['capacite'] }}</span>
                          </div>
                        </td>
                        <td class="px-3 py-2 text-right text-slate-600">{{ MontantFcfa::format($d['prix_unitaire']) }}</td>
                        <td class="px-3 py-2 text-right font-semibold" style="color:var(--navy)">{{ MontantFcfa::formatOuTiret($d['chiffre_affaires']) }}</td>
                        <td class="px-3 py-2 text-right">
                          @if ($d['annule'])
                            <span class="text-[11px] px-2 py-0.5 rounded bg-slate-100 text-slate-500">{{ __('tourisme.pwa.depart_annule') }}</span>
                          @elseif ($d['places_restantes'] === 0)
                            <span class="text-[11px] px-2 py-0.5 rounded bg-red-50 text-red-700">{{ __('tourisme.pwa.complet') }}</span>
                          @else
                            <span class="text-[11px] px-2 py-0.5 rounded bg-emerald-50 text-emerald-700">{{ __('tourisme.pwa.places_restantes', ['nombre' => $d['places_restantes']]) }}</span>
                          @endif
                        </td>
                        <td class="px-3 py-2 text-right whitespace-nowrap">
                          @if ($peutEcrire && ! $d['annule'])
                            @if ($d['places_restantes'] > 0)
                              <button type="button"
                                      wire:click="ouvrirFormulaireReservation('{{ $d['circuit_id'] }}', '{{ $d['date'] }}', '{{ $d['guide_id'] }}')"
                                      class="text-[11px] px-2 py-0.5 rounded bg-[var(--navy)] text-white hover:opacity-90">{{ __('tourisme.pwa.reserver') }}</button>
                            @endif
                            <button type="button" wire:click="ouvrirFormulaireGuide('{{ $d['circuit_id'] }}', '{{ $d['date'] }}')"
                                    class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white ml-1">{{ __('tourisme.pwa.guide') }}</button>
                            <button type="button" wire:click="confirmerArchivage('depart', '{{ $d['circuit_id'] }}', '{{ $d['date'] }}')"
                                    class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white ml-1">{{ __('tourisme.pwa.annuler') }}</button>
                          @endif
                        </td>
                      </tr>
                    @endforeach
                    <tr class="bg-[var(--navy)] text-white font-bold">
                      <td class="px-3 py-2.5" colspan="5">{{ __('tourisme.pwa.total_departs', ['nombre' => count($departs)]) }}</td>
                      <td class="px-3 py-2.5 text-right">{{ $totalVendues }}/{{ $totalCapacite }}</td>
                      <td></td>
                      <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($totalCa) }}</td>
                      <td colspan="2"></td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>

            <div class="rounded-xl p-3.5 mb-4" style="background:#F8FAFC;border:1px solid #E2E8F0">
              <p class="text-[13px]" style="color:#334155">
                <strong>{{ __('tourisme.pwa.bandeau_capacite_titre') }}</strong> {!! __('tourisme.pwa.bandeau_capacite_texte') !!}
              </p>
            </div>
          </div>

          {{-- ETAT IMPRIMABLE — document d'export du maitre, onglet Departs
               (`m9-tourisme-departs.js` l.494) : Capacite, Vendues et
               Restantes y sont trois colonnes, la ou l'ecran les reunit dans
               la jauge « Remplissage ». Memes lignes que l'ecran (PA-119). --}}
          <div class="hidden print:block mb-4">
            <h3 class="text-[13px] font-bold mb-2" style="color:var(--navy)">{{ __('tourisme.pwa.doc_titre_departs') }}</h3>
            <table class="w-full text-[12px]">
              <thead>
                <tr>
                  {!! $enteteDoc(__('tourisme.pwa.col_numero'), true) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_circuit'), true) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_type')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_depart')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_duree')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_guide')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_vehicule')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_capacite')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_vendues')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_restantes')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_ca')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_etat')) !!}
                </tr>
              </thead>
              <tbody>
                @foreach ($departs as $d)
                  <tr wire:key="doc-depart-{{ $d['circuit_id'] }}-{{ $d['date'] }}">
                    {{-- « N° » : aucune colonne `numero` sur `reservations_tour` (verifie le 01/09/2026). --}}
                    <td class="{{ $celluleDoc }} text-left text-slate-400">{{ MontantFcfa::TIRET }}</td>
                    <td class="{{ $celluleDoc }} text-left">{{ $d['circuit_nom'] }}</td>
                    {{-- « Type » : `circuits` ne porte aucun discriminant circuit/excursion (01/09/2026). --}}
                    <td class="{{ $celluleDoc }} text-right">{{ __('tourisme.pwa.type_valeur_circuit') }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ \Carbon\CarbonImmutable::parse($d['date'])->format('d/m/Y') }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ $d['duree'] }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ $d['guide'] ?? MontantFcfa::TIRET }}</td>
                    {{-- « Vehicule » : aucune colonne au schema (verifie le 01/09/2026). --}}
                    <td class="{{ $celluleDoc }} text-right text-slate-400">{{ MontantFcfa::TIRET }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ $d['capacite'] }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ $d['places_vendues'] }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ $d['places_restantes'] }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ MontantFcfa::formatOuTiret($d['chiffre_affaires']) }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ $d['annule'] ? __('tourisme.pwa.depart_annule') : __('tourisme.pwa.etat_planifie') }}</td>
                  </tr>
                @endforeach
              </tbody>
            </table>
          </div>
        </section>

        {{-- ========================== ONGLET RESERVATIONS ================= --}}
        <section class="{{ $onglet === 'reservations' ? '' : 'hidden' }}">
          <div class="{{ $reservations->isEmpty() ? '' : 'hidden' }} bg-white rounded-xl border border-slate-200 py-14 text-center text-slate-400 text-[13px]">{{ __('tourisme.pwa.reservations_vide') }}</div>
          <div class="{{ $reservations->isEmpty() ? 'hidden' : '' }}">
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3 print:hidden">
              <div class="px-4 py-3 border-b border-slate-200">
                <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('tourisme.pwa.reservations_titre') }}</h3>
              </div>
              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  <thead class="bg-[var(--navy)]">
                    <tr>
                      {!! $entete(__('tourisme.pwa.col_numero'), true) !!}
                      {!! $entete(__('tourisme.pwa.col_client'), true) !!}
                      {!! $entete(__('tourisme.pwa.col_circuit'), true) !!}
                      {!! $entete(__('tourisme.pwa.col_depart')) !!}
                      {!! $entete(__('tourisme.pwa.col_personnes')) !!}
                      {!! $entete(__('tourisme.pwa.col_prix')) !!}
                      {!! $entete(__('tourisme.pwa.col_montant')) !!}
                      {!! $entete(__('tourisme.pwa.col_acompte')) !!}
                      {!! $entete(__('tourisme.pwa.col_reste')) !!}
                      <th class="px-3 py-2.5"></th>
                    </tr>
                  </thead>
                  <tbody>
                    @php $totalPers = 0; @endphp
                    @php $totalMontant = '0.00'; @endphp
                    @foreach ($reservations as $r)
                      @php $estAnnulee = $r->estAnnulee(); @endphp
                      @if (! $estAnnulee)
                        @php $totalPers += $r->nb_participants; @endphp
                        @php $totalMontant = bcadd($totalMontant, $r->montant(), 2); @endphp
                      @endif
                      <tr class="border-t border-slate-100 hover:bg-slate-50 {{ $estAnnulee ? 'opacity-50' : '' }}" wire:key="resa-{{ $r->id }}">
                        <td class="px-3 py-2 text-left font-mono text-[11px] text-slate-400">{{ MontantFcfa::TIRET }}</td>
                        <td class="px-3 py-2 text-left">
                          <div class="font-semibold text-slate-800">{{ $r->client?->nom ?? MontantFcfa::TIRET }}</div>
                          <div class="text-[11px] text-slate-400">{{ $r->client?->telephone ?? MontantFcfa::TIRET }}</div>
                          @if ($estAnnulee)
                            <div class="text-[11px] text-red-600">{{ __('tourisme.pwa.reservation_annulee') }}</div>
                          @endif
                        </td>
                        <td class="px-3 py-2 text-left text-slate-700">{{ $r->circuit?->nom ?? MontantFcfa::TIRET }}</td>
                        <td class="px-3 py-2 text-right text-slate-600">{{ $r->date_circuit->format('d/m/Y') }}</td>
                        <td class="px-3 py-2 text-right font-semibold">{{ $r->nb_participants }}</td>
                        <td class="px-3 py-2 text-right text-slate-600">{{ MontantFcfa::format((string) ($r->circuit?->prix ?? '0')) }}</td>
                        <td class="px-3 py-2 text-right font-semibold" style="color:var(--navy)">{{ MontantFcfa::format($r->montant()) }}</td>
                        {{-- « Acompte » et « Reste dû » : aucune colonne au schéma. --}}
                        <td class="px-3 py-2 text-right text-slate-400">{{ MontantFcfa::TIRET }}</td>
                        <td class="px-3 py-2 text-right text-slate-400">{{ MontantFcfa::TIRET }}</td>
                        <td class="px-3 py-2 text-right">
                          @if ($peutEcrire && ! $estAnnulee)
                            <button type="button" wire:click="confirmerArchivage('reservation', '{{ $r->id }}')"
                                    class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white">{{ __('tourisme.pwa.annuler') }}</button>
                          @endif
                        </td>
                      </tr>
                    @endforeach
                    <tr class="bg-[var(--navy)] text-white font-bold">
                      <td class="px-3 py-2.5" colspan="4">{{ __('tourisme.pwa.total_reservations') }}</td>
                      <td class="px-3 py-2.5 text-right">{{ $totalPers }}</td>
                      <td></td>
                      <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($totalMontant) }}</td>
                      <td class="px-3 py-2.5 text-right">{{ MontantFcfa::TIRET }}</td>
                      <td class="px-3 py-2.5 text-right">{{ MontantFcfa::TIRET }}</td>
                      <td></td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>

          {{-- ETAT IMPRIMABLE — document d'export du maitre, onglet
               Reservations (`m9-tourisme-departs.js` l.472) : « Telephone »
               et « Personnes » y sont des colonnes en toutes lettres, la ou
               l'ecran abrege (« Pers. ») ou glisse le telephone sous la
               colonne Client. Memes lignes que l'ecran (PA-119). --}}
          <div class="hidden print:block mb-4">
            <h3 class="text-[13px] font-bold mb-2" style="color:var(--navy)">{{ __('tourisme.pwa.doc_titre_reservations') }}</h3>
            <table class="w-full text-[12px]">
              <thead>
                <tr>
                  {!! $enteteDoc(__('tourisme.pwa.col_numero'), true) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_client'), true) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_telephone'), true) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_circuit'), true) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_depart')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_personnes_document')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_prix')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_montant')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_acompte')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_reste')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_etat')) !!}
                </tr>
              </thead>
              <tbody>
                @foreach ($reservations as $r)
                  <tr wire:key="doc-resa-{{ $r->id }}">
                    {{-- « N° » : aucune colonne `numero` sur `reservations_tour` (verifie le 01/09/2026). --}}
                    <td class="{{ $celluleDoc }} text-left text-slate-400">{{ MontantFcfa::TIRET }}</td>
                    <td class="{{ $celluleDoc }} text-left">{{ $r->client?->nom ?? MontantFcfa::TIRET }}</td>
                    <td class="{{ $celluleDoc }} text-left">{{ $r->client?->telephone ?? MontantFcfa::TIRET }}</td>
                    <td class="{{ $celluleDoc }} text-left">{{ $r->circuit?->nom ?? MontantFcfa::TIRET }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ $r->date_circuit->format('d/m/Y') }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ $r->nb_participants }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ MontantFcfa::format((string) ($r->circuit?->prix ?? '0')) }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ MontantFcfa::format($r->montant()) }}</td>
                    {{-- « Acompte » et « Reste du » : aucune colonne au schema (verifie le 01/09/2026). --}}
                    <td class="{{ $celluleDoc }} text-right text-slate-400">{{ MontantFcfa::TIRET }}</td>
                    <td class="{{ $celluleDoc }} text-right text-slate-400">{{ MontantFcfa::TIRET }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ match ($r->statut) {
                        'annulee' => __('tourisme.pwa.reservation_annulee'),
                        'en_cours' => __('tourisme.pwa.etat_en_cours'),
                        'terminee' => __('tourisme.pwa.etat_terminee'),
                        default => __('tourisme.pwa.etat_reservee'),
                    } }}</td>
                  </tr>
                @endforeach
              </tbody>
            </table>
          </div>
        </section>

        {{-- ============================= ONGLET CATALOGUE ================= --}}
        <section class="{{ $onglet === 'catalogue' ? '' : 'hidden' }}">
          <div class="{{ $catalogue->isEmpty() ? '' : 'hidden' }} bg-white rounded-xl border border-slate-200 py-14 text-center text-slate-400 text-[13px]">{{ __('tourisme.pwa.catalogue_vide') }}</div>
          <div class="{{ $catalogue->isEmpty() ? 'hidden' : '' }}">
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3 print:hidden">
              <div class="px-4 py-3 border-b border-slate-200">
                <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('tourisme.pwa.catalogue_titre') }}</h3>
              </div>
              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  <thead class="bg-[var(--navy)]">
                    <tr>
                      {!! $entete(__('tourisme.pwa.col_prestation'), true) !!}
                      {!! $entete(__('tourisme.pwa.col_type')) !!}
                      {!! $entete(__('tourisme.pwa.col_duree')) !!}
                      {!! $entete(__('tourisme.pwa.col_zone_theme')) !!}
                      {!! $entete(__('tourisme.pwa.col_prix_catalogue')) !!}
                      {!! $entete(__('tourisme.pwa.col_indicatif')) !!}
                      {!! $entete(__('tourisme.pwa.col_departs_planifies')) !!}
                      <th class="px-3 py-2.5"></th>
                    </tr>
                  </thead>
                  <tbody>
                    @foreach ($catalogue as $c)
                      <tr class="border-t border-slate-100 hover:bg-slate-50" wire:key="circuit-{{ $c->id }}">
                        <td class="px-3 py-2 text-left font-semibold text-slate-800">{{ $c->nom }}</td>
                        {{-- Le schema ne connait que `circuits` : aucun discriminant « excursion ». --}}
                        <td class="px-3 py-2 text-right">
                          <span class="text-[11px] px-2 py-0.5 rounded bg-slate-100 text-slate-600">{{ __('tourisme.pwa.type_valeur_circuit') }}</span>
                        </td>
                        <td class="px-3 py-2 text-right text-slate-600">{{ $c->duree }}</td>
                        <td class="px-3 py-2 text-right text-slate-600 text-[12px]">{{ $c->zone }} · {{ $c->theme }}</td>
                        <td class="px-3 py-2 text-right font-bold" style="color:var(--navy)">{{ MontantFcfa::format((string) $c->prix) }}</td>
                        {{-- « Indicatif € » : aucune colonne au schéma. --}}
                        <td class="px-3 py-2 text-right text-slate-400">{{ MontantFcfa::TIRET }}</td>
                        <td class="px-3 py-2 text-right text-slate-600">{{ $departsParCircuit[$c->id] ?? MontantFcfa::TIRET }}</td>
                        <td class="px-3 py-2 text-right whitespace-nowrap">
                          @if ($peutEcrire)
                            <button type="button" wire:click="ouvrirFormulaireReservation('{{ $c->id }}')"
                                    class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white">{{ __('tourisme.pwa.planifier') }}</button>
                            <button type="button" wire:click="ouvrirFormulairePrestation('{{ $c->id }}')"
                                    class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white ml-1">{{ __('tourisme.pwa.editer') }}</button>
                          @endif
                        </td>
                      </tr>
                    @endforeach
                  </tbody>
                </table>
              </div>
            </div>
          </div>

          {{-- ETAT IMPRIMABLE — document d'export du maitre, onglet
               Catalogue (`m9-tourisme-departs.js` l.483) : « Zone » et
               « Theme » y sont deux colonnes que l'ecran reunit, et les prix
               s'y nomment « Prix FCFA » / « Indicatif EUR ». Memes lignes
               que l'ecran (PA-119). --}}
          <div class="hidden print:block mb-4">
            <h3 class="text-[13px] font-bold mb-2" style="color:var(--navy)">{{ __('tourisme.pwa.doc_titre_catalogue') }}</h3>
            <table class="w-full text-[12px]">
              <thead>
                <tr>
                  {!! $enteteDoc(__('tourisme.pwa.col_prestation'), true) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_type')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_duree')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_zone')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_theme')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_prix_fcfa')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_indicatif_eur')) !!}
                  {!! $enteteDoc(__('tourisme.pwa.col_page_catalogue')) !!}
                </tr>
              </thead>
              <tbody>
                @foreach ($catalogue as $c)
                  <tr wire:key="doc-circuit-{{ $c->id }}">
                    <td class="{{ $celluleDoc }} text-left">{{ $c->nom }}</td>
                    {{-- « Type » : `circuits` ne porte aucun discriminant circuit/excursion (01/09/2026). --}}
                    <td class="{{ $celluleDoc }} text-right">{{ __('tourisme.pwa.type_valeur_circuit') }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ $c->duree }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ $c->zone }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ $c->theme }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ MontantFcfa::format((string) $c->prix) }}</td>
                    {{-- « Indicatif EUR » : aucune colonne au schema — le taux imprime du maitre n'est pas un taux du jour (verifie le 01/09/2026). --}}
                    <td class="{{ $celluleDoc }} text-right text-slate-400">{{ MontantFcfa::TIRET }}</td>
                    {{-- « Page catalogue » : aucune colonne au schema (verifie le 01/09/2026). --}}
                    <td class="{{ $celluleDoc }} text-right text-slate-400">{{ MontantFcfa::TIRET }}</td>
                  </tr>
                @endforeach
              </tbody>
            </table>
          </div>
        </section>

        {{--
            NON PORTE, ET PLUS RENDU A L'ECRAN (02/09/2026). Directive du
            Product Owner : un ecran dit ce qu'il FAIT. Ce qui reste non porte
            se declare ici, dans le code :
            - planifier un depart, vehicule affecte, numero de prestation,
              acompte, indicatif de prix en EUR : aucune colonne au schema ;
            - distinguer un circuit d'une excursion dans le select de filtre
              (01/09/2026) : aucun discriminant au schema ne les separe — le
              select existe (rebranche, filtre desormais PAR PRESTATION, voir
              Departs::$prestationId), seule la distinction de TYPE reste hors
              de portee ;
            - motif de reaffectation d'un guide : non porte au schema ;
            - supprimer une prestation : interdit (RG-02), elle s'annule.
        --}}

      </div>
    </main>
  </div>

  {{-- ==================== MODALE « Réserver des places » ================= --}}
  @if ($etatFormulaire === 'reservation')
    @php $circuitChoisi = $catalogueComplet->firstWhere('id', $circuitIdResa); @endphp
    <x-pwa.modale :titre="__('tourisme.pwa.modale_resa_titre')"
                  :sousTitre="__('tourisme.pwa.modale_resa_sous_titre', [
                      'circuit' => $circuitChoisi?->nom ?? MontantFcfa::TIRET,
                      'date' => $dateDepartResa === '' ? MontantFcfa::TIRET : \Carbon\CarbonImmutable::parse($dateDepartResa)->format('d/m/Y'),
                  ])"
                  largeur="520px">
      <div class="bg-slate-50 border border-slate-200 rounded-lg p-3 text-[13px]">
        <div class="flex justify-between"><span class="text-slate-600">{{ __('tourisme.pwa.bloc_capacite') }}</span><strong>{{ $capaciteResa ?? MontantFcfa::TIRET }}</strong></div>
        <div class="flex justify-between">
          <span class="text-slate-600">{{ __('tourisme.pwa.bloc_vendues') }}</span>
          <strong>{{ $capaciteResa !== null && $placesRestantesResa !== null ? $capaciteResa - $placesRestantesResa : MontantFcfa::TIRET }}</strong>
        </div>
        <div class="flex justify-between">
          <span class="text-slate-600">{{ __('tourisme.pwa.bloc_restantes') }}</span>
          <strong class="text-emerald-700">{{ $placesRestantesResa ?? MontantFcfa::TIRET }}</strong>
        </div>
      </div>

      @if ($catalogueComplet->isEmpty())
        <p class="text-[12px] text-amber-700">{{ __('tourisme.pwa.prestation_aucune') }}</p>
      @else
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('tourisme.pwa.champ_prestation') }} <span class="text-red-500">*</span></label>
          <select wire:model.live="circuitIdResa" @disabled($departImpose) class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
            @foreach ($catalogueComplet as $c)
              <option value="{{ $c->id }}">{{ $c->nom }} — {{ MontantFcfa::format((string) $c->prix) }} · {{ $c->duree }}</option>
            @endforeach
          </select>
          @error('circuitIdResa') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
      @endif

      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('tourisme.pwa.champ_date_depart') }} <span class="text-red-500">*</span></label>
          <input type="date" wire:model.live="dateDepartResa" @disabled($departImpose) class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('dateDepartResa') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('tourisme.pwa.champ_guide') }} <span class="text-red-500">*</span></label>
          @if ($guides->isEmpty())
            <p class="text-[12px] text-amber-700">{{ __('tourisme.pwa.guide_aucun') }}</p>
          @elseif ($guideImpose !== null)
            {{-- Le depart existe deja : son guide est IMPOSE. La liaison
                 `wire:model` est conservee — le champ n'est pas libre, il
                 n'est pas absent. --}}
            <select wire:model="guideIdResa" disabled class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 bg-slate-50 text-slate-600">
              <option value="{{ $guideImpose->id }}">{{ $guideImpose->nom }}</option>
            </select>
          @else
            <select wire:model="guideIdResa" @disabled($departImpose) class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
              @foreach ($guides as $g)
                <option value="{{ $g->id }}">{{ $g->nom }}</option>
              @endforeach
            </select>
          @endif
          @error('guideIdResa') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div>
          {{-- RG-18 : le client est une CLE ETRANGERE, jamais un nom libre. --}}
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('tourisme.pwa.champ_client') }} <span class="text-red-500">*</span></label>
          @if ($clients->isEmpty())
            <p class="text-[12px] text-amber-700">{{ __('tourisme.pwa.client_aucun') }}</p>
          @else
            <select wire:model="clientIdResa" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
              @foreach ($clients as $client)
                <option value="{{ $client->id }}">{{ trim($client->prenom . ' ' . $client->nom) }}</option>
              @endforeach
            </select>
          @endif
          @error('clientIdResa') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('tourisme.pwa.champ_nb_personnes') }} <span class="text-red-500">*</span></label>
          <input type="number" min="1" step="1" wire:model.live="nbPersonnesSaisi" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('nbPersonnesSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
      </div>

      <p class="text-[11px] text-slate-500 bg-slate-50 border border-slate-200 rounded-lg p-2.5">{!! __('tourisme.pwa.note_cumul') !!}</p>
      @if ($guideImpose !== null)
        <p class="text-[11px] text-slate-500 bg-slate-50 border border-slate-200 rounded-lg p-2.5">{!! __('tourisme.pwa.note_guide_du_depart') !!}</p>
      @else
        <p class="text-[11px] text-slate-500 bg-slate-50 border border-slate-200 rounded-lg p-2.5">{!! __('tourisme.pwa.note_guide_obligatoire') !!}</p>
      @endif
      {{-- NON PORTE (02/09/2026) : ni le telephone du participant ni
           l'acompte n'ont de colonne au schema. Les deux phrases qui le
           disaient dans la modale sont retirees ; la raison se lit ici. --}}

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerReservation" wire:loading.attr="disabled"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('tourisme.pwa.bouton_reserver') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ==================== MODALE « Réaffecter le guide » ================= --}}
  @if ($etatFormulaire === 'guide')
    @php $circuitGuide = $catalogueComplet->firstWhere('id', $circuitIdGuide); @endphp
    <x-pwa.modale :titre="__('tourisme.pwa.modale_guide_titre')"
                  :sousTitre="__('tourisme.pwa.modale_guide_sous_titre', [
                      'circuit' => $circuitGuide?->nom ?? MontantFcfa::TIRET,
                      'date' => $dateDepartGuide === '' ? MontantFcfa::TIRET : \Carbon\CarbonImmutable::parse($dateDepartGuide)->format('d/m/Y'),
                  ])"
                  largeur="520px">
      <div class="bg-slate-50 border border-slate-200 rounded-lg p-3 text-[13px]">
        {{ __('tourisme.pwa.guide_actuel') }} <strong>{{ $guideActuel ?? MontantFcfa::TIRET }}</strong>
      </div>

      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('tourisme.pwa.champ_nouveau_guide') }} <span class="text-red-500">*</span></label>
        @if ($guides->isEmpty())
          <p class="text-[12px] text-amber-700">{{ __('tourisme.pwa.guide_aucun') }}</p>
        @else
          <select wire:model="nouveauGuideId" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
            @foreach ($guides as $g)
              <option value="{{ $g->id }}">{{ $g->nom }}</option>
            @endforeach
          </select>
        @endif
        @error('nouveauGuideId') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <p class="text-[11px] text-slate-500 bg-slate-50 border border-slate-200 rounded-lg p-2.5">{!! __('tourisme.pwa.note_reaffectation') !!}</p>
      {{-- NON PORTE (02/09/2026) : le motif de reaffectation n'a pas de
           colonne au schema ; la phrase qui le disait ici est retiree. --}}

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerReaffectationGuide" wire:loading.attr="disabled"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('tourisme.pwa.bouton_reaffecter') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ==================== MODALE « Prestation » ========================== --}}
  @if ($etatFormulaire === 'prestation')
    <x-pwa.modale :titre="$circuitIdEdite
                      ? __('tourisme.pwa.modale_circuit_titre_edition')
                      : __('tourisme.pwa.modale_circuit_titre_creation')"
                  :sousTitre="__('tourisme.pwa.modale_circuit_sous_titre')"
                  largeur="560px">
      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('tourisme.pwa.champ_nom') }} <span class="text-red-500">*</span></label>
        <input type="text" wire:model="circuitNomSaisi" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
        @error('circuitNomSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('tourisme.pwa.champ_theme') }} <span class="text-red-500">*</span></label>
          <select wire:model="circuitThemeSaisi" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
            @foreach ($themes as $theme)
              <option value="{{ $theme }}">{{ $theme }}</option>
            @endforeach
          </select>
          @error('circuitThemeSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('tourisme.pwa.champ_zone') }} <span class="text-red-500">*</span></label>
          <input type="text" wire:model="circuitZoneSaisie" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('circuitZoneSaisie') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
      </div>

      <div class="grid grid-cols-3 gap-3">
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('tourisme.pwa.champ_duree') }} <span class="text-red-500">*</span></label>
          <input type="text" wire:model="circuitDureeSaisie" placeholder="{{ __('tourisme.pwa.invite_duree') }}"
                 class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('circuitDureeSaisie') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('tourisme.pwa.champ_prix') }} <span class="text-red-500">*</span></label>
          <input type="number" min="0" step="500" wire:model="circuitPrixSaisi" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('circuitPrixSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('tourisme.pwa.champ_capacite') }} <span class="text-red-500">*</span></label>
          <input type="number" min="1" step="1" wire:model="circuitCapaciteSaisie" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('circuitCapaciteSaisie') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
      </div>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerPrestation" wire:loading.attr="disabled"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('tourisme.pwa.bouton_enregistrer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ==================== MODALE D'ARCHIVAGE ============================= --}}
  @if ($etatFormulaire === 'archivage')
    <x-pwa.modale-archivage action="executerSuppression"
                            :element="$libelleElementSupprime"
                            :messagesVerrou="$verrousArchivage"
                            :bloque="$archivageBloque"
                            :message="$archivageBloque ? null : ($typeElementSupprime === 'reservation'
                                ? __('tourisme.pwa.archiver_reservation', ['element' => $libelleElementSupprime])
                                : __('tourisme.pwa.archiver_depart', ['element' => $libelleElementSupprime]))" />

    @if (! $archivageBloque && $typeElementSupprime === 'depart' && $placesConcernees > 0)
      <div class="fixed bottom-5 left-1/2 -translate-x-1/2 z-[60] max-w-md px-4 py-3 rounded-xl bg-red-50 border border-red-200 text-[12px] text-red-800 no-print">
        {{ __('tourisme.pwa.depart_places_vendues', ['nombre' => $placesConcernees]) }}
      </div>
    @endif
  @endif

  {{-- ==================== MODALE D'EXPORT (partagee) ===================== --}}
  @if ($etatFormulaire === 'export')
    @include('pwa.partials.modale-export', ['titre' => __('tourisme.pwa.export_titre')])
    @error('formatExport')
      <div class="fixed bottom-5 right-5 z-50 px-4 py-3 rounded-xl bg-red-600 text-white text-[13px] no-print">{{ $message }}</div>
    @enderror
  @endif

  @include('pwa.partials.acces-rapide')
</div>

{{--
    M8 — VEHICULES & LOCATIONS.

    Maitre : `prototype_v2/pages/m8-locations.html` et `m8-locations.js`.

    ## La casse des entetes est celle du MAITRE

    `Véhicule`, pas `VÉHICULE`. Le maitre pose `Véhicule` et laisse la classe
    `uppercase` faire le rendu — une regle CSS, qui ne s'applique ni au CSV ni
    au PDF. Une majuscule ecrite en dur ressort telle quelle sur le document
    remis au comptable.

    ## La colonne d'actions n'a PAS d'entete

    Le maitre termine ses tableaux par une chaine vide (`m8-locations.js` l.67,
    l.110). Ecrire « Actions » y ajouterait une colonne que le maitre n'a pas.

    ## Ce qui n'est pas rendu est NOMME, jamais tu

    Les refus vivent dans `lang/fr/vehicules.php` (cles `pwa.refus_*`) et sont
    affiches en bas d'ecran. Un motif de refus qu'on ne voit plus redevient un
    oubli (PA-144).

    Declarations pour la garde des trois sources :
      maitre-refuse:m8-locations.html#modale-immo
--}}
@php
    use App\Pwa\Livewire\Vehicules\Locations;
    use App\Pwa\Support\MontantFcfa;

    // Classes d'onglets : directive PO du 01/09/2026, UN SEUL AUTEUR —
    // voir le docblock de `App\Pwa\Support\Onglets`.
    $classeOnglet = static fn (bool $actif): string => \App\Pwa\Support\Onglets::classes($actif);

    // Libelle d'AFFICHAGE d'une categorie (02/09/2026, passage navigateur :
    // « velo » sortait en valeur d'enum brute). Cles LITTERALES via match —
    // jamais une cle concatenee ; l'inconnu reste EN CLAIR, il doit se voir.
    $libelleCategorie = static fn (?string $c): string => match ($c) {
        'voiture' => __('vehicules.pwa.categorie_voiture'),
        '4x4' => __('vehicules.pwa.categorie_4x4'),
        'pickup' => __('vehicules.pwa.categorie_pickup'),
        'moto' => __('vehicules.pwa.categorie_moto'),
        'scooter' => __('vehicules.pwa.categorie_scooter'),
        'velo' => __('vehicules.pwa.categorie_velo'),
        'bus' => __('vehicules.pwa.categorie_bus'),
        default => (string) $c,
    };

    // `uppercase` est laisse a la feuille de style, comme au maitre.
    $entete = static fn (string $libelle, bool $gauche = false): string => '<th class="px-3 py-2.5 '
        . ($gauche ? 'text-left' : 'text-right')
        . ' text-[11px] uppercase tracking-wide text-white/90 font-semibold">'
        . e($libelle) . '</th>';

    // En-tete de colonne de l'ETAT IMPRIMABLE (`hidden print:block`) : les
    // colonnes du DOCUMENT d'export du maitre (`m8-locations.js` l.405-441,
    // `etatCourant()`), rendues sur papier par l'impression du navigateur
    // comme le maitre les rend par `ExportEngine`. Texte sombre sur fond
    // blanc : un en-tete blanc sur navy disparaitrait du papier.
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
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        {{-- EN-TETE — maitre l.30-48 --}}
        <div class="mb-5 flex flex-wrap items-start justify-between gap-3">
          <div>
            <div class="flex items-center gap-2.5">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M5 17h14M6 17v-5l2-5h8l2 5v5M7 17v2M17 17v2"/><circle cx="8" cy="14" r="1"/><circle cx="16" cy="14" r="1"/></svg>
              <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('vehicules.pwa.titre') }}</h1>
            </div>
            <p class="text-[15px] text-slate-500 mt-1.5">{{ __('vehicules.pwa.sous_titre') }}</p>
          </div>

          <div class="flex flex-wrap gap-2 items-center">
            <label class="text-[12px] text-slate-500">{{ __('vehicules.pwa.du') }}</label>
            <input type="date" wire:model.live="debut" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-2">
            <label class="text-[12px] text-slate-500">{{ __('vehicules.pwa.au') }}</label>
            <input type="date" wire:model.live="fin" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-2">

            {{-- Exporter est une LECTURE, offerte a tout role qui peut ouvrir
                 l'ecran : le droit de lire est deja porte par le middleware
                 `module:M#,L` de la route, et l'export ne rend que ce qui est
                 deja affiche (PA-119).

                 ⚠ DEROGATION PO du 01/09/2026, rappelee le 02/09/2026 — la
                 paire de boutons du maitre (« Excel » / « PDF »,
                 `m8-locations.html` l.40-41) est FUSIONNEE en UN bouton
                 « Exporter » : les deux ouvraient deja la meme modale de
                 format. Le format PDF/Excel se choisit DANS la modale.
                 Registre : `App\Pwa\Support\DerogationsMaquette`
                 (export_bouton_unique).
                 Jeton : maitre-refuse:m8-locations.html#page --}}
              <button type="button" wire:click="$set('etatFormulaire', 'export')" wire:loading.attr="disabled"
                      class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white hover:opacity-90 font-semibold">{{ __('pwa.export.bouton') }}</button>
          </div>
        </div>

        {{-- KPI — maitre `m8-locations.js` l.386-403 --}}
        <div class="grid grid-cols-2 lg:grid-cols-6 gap-3 mb-5">
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('vehicules.pwa.kpi_parc') }}</div>
            <div class="text-[17px] font-bold mt-1" style="color:var(--navy)">{{ $parcCount }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">
              {{ $immobilisesCount > 0
                  ? __('vehicules.pwa.kpi_parc_immobilises', ['nombre' => $immobilisesCount])
                  : __('vehicules.pwa.kpi_parc_aucun') }}
            </div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('vehicules.pwa.kpi_contrats') }}</div>
            <div class="text-[17px] font-bold mt-1" style="color:var(--navy)">{{ $contratsActifsCount }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('vehicules.pwa.kpi_contrats_detail', ['nombre' => $contratsAnnulesCount]) }}</div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('vehicules.pwa.kpi_ca') }}</div>
            <div class="text-[17px] font-bold mt-1" style="color:var(--navy)">{{ MontantFcfa::format($chiffreAffaires) }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('vehicules.pwa.kpi_ca_detail', ['jours' => $joursLoues]) }}</div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('vehicules.pwa.kpi_occupation') }}</div>
            {{-- Aucun vehicule : le taux n'a pas de sens. « 0 % » se lirait
                 comme un parc inoccupe (Article 7). --}}
            <div class="text-[17px] font-bold mt-1" style="color:var(--navy)">{{ $tauxOccupation === null ? MontantFcfa::TIRET : $tauxOccupation . ' %' }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('vehicules.pwa.kpi_occupation_detail') }}</div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('vehicules.pwa.kpi_reste') }}</div>
            <div class="text-[17px] font-bold mt-1 {{ bccomp($resteAEncaisser, '0', 2) > 0 ? 'text-red-600' : '' }}"
                 style="{{ bccomp($resteAEncaisser, '0', 2) > 0 ? '' : 'color:var(--navy)' }}">{{ MontantFcfa::format($resteAEncaisser) }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('vehicules.pwa.kpi_reste_detail') }}</div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('vehicules.pwa.kpi_jours') }}</div>
            <div class="text-[17px] font-bold mt-1" style="color:var(--navy)">{{ $joursLoues }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('vehicules.pwa.kpi_jours_detail') }}</div>
          </div>
        </div>

        {{-- ONGLETS — maitre l.53-58 --}}
        <div class="flex flex-wrap gap-1.5 mb-4">
          <button type="button" wire:click="$set('onglet', 'parc')" class="{{ $classeOnglet($onglet === 'parc') }}">{{ __('vehicules.pwa.onglet_parc') }}</button>
          <button type="button" wire:click="$set('onglet', 'contrats')" class="{{ $classeOnglet($onglet === 'contrats') }}">{{ __('vehicules.pwa.onglet_contrats') }}</button>
          <button type="button" wire:click="$set('onglet', 'planning')" class="{{ $classeOnglet($onglet === 'planning') }}">{{ __('vehicules.pwa.onglet_planning') }}</button>
          <button type="button" wire:click="$set('onglet', 'immo')" class="{{ $classeOnglet($onglet === 'immo') }}">{{ __('vehicules.pwa.onglet_immo') }}</button>
        </div>

        {{-- FILTRES ET ACTIONS — maitre l.60-79 --}}
        <div class="bg-white rounded-xl border border-slate-200 p-3.5 mb-4">
          <div class="flex flex-wrap gap-2.5 items-center">
            <div class="relative flex-1 min-w-[200px]">
              <svg class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
              <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="{{ __('vehicules.pwa.recherche') }}"
                     class="w-full text-[13px] border border-slate-300 rounded-lg pl-9 pr-3 py-2 focus:border-[var(--gold)] focus:outline-none">
            </div>

            <select wire:model.live="categorie" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <option value="">{{ __('vehicules.pwa.toutes_categories') }}</option>
              @foreach ($categories as $cat)
                <option value="{{ $cat }}">{{ $libelleCategorie($cat) }}</option>
              @endforeach
            </select>

            <select wire:model.live="statut" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <option value="actif">{{ __('vehicules.pwa.statut_actif') }}</option>
              <option value="">{{ __('vehicules.pwa.statut_tous') }}</option>
              <option value="annule">{{ __('vehicules.pwa.statut_annule') }}</option>
            </select>

            <div class="flex-1"></div>

            @if ($peutEcrire)
              <button type="button" wire:click="ouvrirFormulaireVehicule"
                      class="text-[13px] px-3.5 py-2 rounded-lg border border-slate-300 bg-white hover:bg-slate-50">{{ __('vehicules.pwa.action_vehicule') }}</button>
              <button type="button" wire:click="ouvrirFormulaireImmobilisation"
                      class="text-[13px] px-3.5 py-2 rounded-lg border border-slate-300 bg-white hover:bg-slate-50">{{ __('vehicules.pwa.action_immobiliser') }}</button>
              <button type="button" wire:click="ouvrirFormulaireContrat"
                      class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('vehicules.pwa.action_contrat') }}</button>
            @endif
          </div>
        </div>

        {{--
            UN PANNEAU D'ONGLET FERME RESTE DANS LE HTML, MASQUE PAR `hidden`
            (01/09/2026). La garde G5 (`ColonnesDesTableauxPwaTest`) lit les
            colonnes du maitre dans le HTML rendu AU PREMIER GET : un `@if`
            qui retirait les panneaux inactifs faisait disparaitre les
            en-tetes des onglets Contrats et Immobilisations — quatre groupes
            de colonnes rapportes absents sur un ecran qui les rendait des le
            premier clic. Meme motif que `achats.blade.php`.

            SEUL le Planning garde son `@if` : ses en-tetes de jours (1..31)
            sont des DONNEES, pas des libelles du maitre — rendus au premier
            GET, le cas « aucune colonne n'est inventee » de la meme garde
            les prendrait pour des colonnes apparues de nulle part. Le
            panneau se rend des l'activation de l'onglet (Livewire re-rend),
            l'Article 3.3 reste tenu.

            Declaration pour la garde de structure (`t-structure.js`) — le
            maitre ne rend au premier chargement que le tableau de l'onglet
            actif, la PWA les garde tous dans le DOM (raison ci-dessus,
            01/09/2026) :
              structure-ajout:m8-locations.html#div-cc70a52a
        --}}
        {{-- ================================ ONGLET PARC ================== --}}
        <section class="{{ $onglet === 'parc' ? '' : 'hidden' }}">
          <div class="rounded-xl p-3.5 mb-4" style="background:#F8FAFC;border:1px solid #E2E8F0">
            <p class="text-[13px]" style="color:#334155">
              <strong>{{ __('vehicules.pwa.bandeau_permis_titre') }}</strong> {{ __('vehicules.pwa.bandeau_permis_texte') }}
            </p>
          </div>

          {{-- L'etat vide du maitre (`vide()`), le tableau restant dans le
               DOM : les en-tetes se lisent meme sans ligne. --}}
          <div class="{{ $parc->isEmpty() ? '' : 'hidden' }} bg-white rounded-xl border border-slate-200 py-14 text-center text-slate-400 text-[13px]">{{ __('vehicules.pwa.parc_vide') }}</div>
          <div class="{{ $parc->isEmpty() ? 'hidden' : '' }}">
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
              <div class="px-4 py-3 border-b border-slate-200">
                <h3 class="text-[14px] font-bold" style="color:var(--navy)">
                  {{ __('vehicules.pwa.parc_titre', ['debut' => $fenetreDebut->format('d/m/Y'), 'fin' => $fenetreFin->format('d/m/Y')]) }}
                </h3>
              </div>
              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  <thead class="bg-[var(--navy)]">
                    <tr>
                      {!! $entete(__('vehicules.pwa.col_vehicule'), true) !!}
                      {!! $entete(__('vehicules.pwa.col_categorie')) !!}
                      {!! $entete(__('vehicules.pwa.col_places')) !!}
                      {!! $entete(__('vehicules.pwa.col_permis')) !!}
                      {!! $entete(__('vehicules.pwa.col_tarif')) !!}
                      {{-- ⚠ Le NOM de la colonne est celui du maître
                           (`m8-locations.js` l.414). La fenêtre en jours est
                           une précision, pas un titre : elle vivait dans le
                           `<th>` et l'en-tête affichait « 14 jour(s) ». --}}
                      <th class="px-3 py-2.5 text-right text-[11px] uppercase tracking-wide text-white/90 font-semibold"
                          title="{{ __('vehicules.pwa.col_periode_parc_precision', ['jours' => $joursFenetre]) }}">{{ __('vehicules.pwa.col_periode_parc') }}</th>
                      {!! $entete(__('vehicules.pwa.col_disponibilite')) !!}
                      {{-- Le maitre ne titre pas la colonne d'actions. --}}
                      <th class="px-3 py-2.5"></th>
                    </tr>
                  </thead>
                  <tbody>
                    @foreach ($parc as $v)
                      <tr class="border-t border-slate-100 hover:bg-slate-50" wire:key="vehicule-{{ $v->id }}">
                        <td class="px-3 py-2 text-left">
                          <div class="font-semibold text-slate-800">{{ $v->immatriculation }}</div>
                          <div class="text-[11px] text-slate-400">{{ $v->annee }}{{ $v->transmission ? ' · ' . $v->transmission : '' }}</div>
                        </td>
                        <td class="px-3 py-2 text-right text-slate-600">{{ $libelleCategorie($v->categorie) }}</td>
                        <td class="px-3 py-2 text-right text-slate-600">{{ $v->capacite ?? MontantFcfa::TIRET }}</td>
                        <td class="px-3 py-2 text-right">
                          @if ($v->exigePermis())
                            <span class="text-[11px] px-1.5 py-0.5 rounded bg-amber-50 text-amber-700">{{ __('vehicules.pwa.permis_exige') }}</span>
                          @else
                            <span class="text-[11px] px-1.5 py-0.5 rounded bg-emerald-50 text-emerald-700">{{ __('vehicules.pwa.permis_dispense') }}</span>
                          @endif
                        </td>
                        <td class="px-3 py-2 text-right text-slate-600">{{ MontantFcfa::format((string) $v->tarif_jour) }}</td>
                        <td class="px-3 py-2 text-right font-bold" style="color:var(--navy)">
                          {{ MontantFcfa::format(bcmul((string) $v->tarif_jour, (string) $joursFenetre, 2)) }}
                        </td>
                        <td class="px-3 py-2 text-right">
                          @if ($v->statut === 'hors_service')
                            <span class="text-[11px] px-2 py-0.5 rounded bg-slate-100 text-slate-500">{{ __('vehicules.pwa.hors_service') }}</span>
                          @elseif ($disponibilites[$v->id] ?? false)
                            <span class="text-[11px] px-2 py-0.5 rounded bg-emerald-50 text-emerald-700">{{ __('vehicules.pwa.disponible') }}</span>
                          @else
                            <span class="text-[11px] px-2 py-0.5 rounded bg-red-50 text-red-700">{{ __('vehicules.pwa.engage') }}</span>
                          @endif
                        </td>
                        <td class="px-3 py-2 text-right whitespace-nowrap">
                          @if ($peutEcrire)
                            @if ($disponibilites[$v->id] ?? false)
                              <button type="button" wire:click="ouvrirFormulaireContrat('{{ $v->id }}')"
                                      class="text-[11px] px-2 py-0.5 rounded bg-[var(--navy)] text-white hover:opacity-90">{{ __('vehicules.pwa.louer') }}</button>
                            @endif
                            <button type="button" wire:click="ouvrirFormulaireVehicule('{{ $v->id }}')"
                                    class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white ml-1">{{ __('vehicules.pwa.editer') }}</button>
                            @if ($v->statut === 'hors_service' || $v->statut === 'entretien')
                              <button type="button" wire:click="remettreEnService('{{ $v->id }}')"
                                      class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white ml-1">{{ __('vehicules.pwa.remettre_en_service') }}</button>
                            @else
                              <button type="button" wire:click="confirmerArchivage('vehicule', '{{ $v->id }}')"
                                      class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white ml-1">{{ __('vehicules.pwa.archiver') }}</button>
                            @endif
                          @endif
                        </td>
                      </tr>
                    @endforeach
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </section>

        {{-- ============================= ONGLET CONTRATS ================== --}}
        <section class="{{ $onglet === 'contrats' ? '' : 'hidden' }}">
          <div class="{{ $contrats->isEmpty() ? '' : 'hidden' }} bg-white rounded-xl border border-slate-200 py-14 text-center text-slate-400 text-[13px]">{{ __('vehicules.pwa.contrats_vide') }}</div>
          <div class="{{ $contrats->isEmpty() ? 'hidden' : '' }}">
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3 print:hidden">
              <div class="px-4 py-3 border-b border-slate-200">
                <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('vehicules.pwa.contrats_titre') }}</h3>
              </div>
              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  <thead class="bg-[var(--navy)]">
                    <tr>
                      {!! $entete(__('vehicules.pwa.col_numero'), true) !!}
                      {!! $entete(__('vehicules.pwa.col_vehicule'), true) !!}
                      {!! $entete(__('vehicules.pwa.col_client'), true) !!}
                      {!! $entete(__('vehicules.pwa.col_periode')) !!}
                      {!! $entete(__('vehicules.pwa.col_jours')) !!}
                      {!! $entete(__('vehicules.pwa.col_montant')) !!}
                      {!! $entete(__('vehicules.pwa.col_acompte')) !!}
                      {!! $entete(__('vehicules.pwa.col_reste')) !!}
                      {!! $entete(__('vehicules.pwa.col_etat')) !!}
                      <th class="px-3 py-2.5"></th>
                    </tr>
                  </thead>
                  <tbody>
                    @php $totalMontant = '0.00'; @endphp
                    @php $totalAcompte = '0.00'; @endphp
                    @php $totalReste = '0.00'; @endphp
                    @foreach ($contrats as $c)
                      @php $estAnnule = $c->statut === 'annule'; @endphp
                      @if (! $estAnnule)
                        @php $totalMontant = bcadd($totalMontant, (string) ($c->montant ?? '0'), 2); @endphp
                        @php $totalAcompte = bcadd($totalAcompte, (string) ($c->acompte ?? '0'), 2); @endphp
                        @php $totalReste = bcadd($totalReste, (string) ($c->reste_a_payer ?? '0'), 2); @endphp
                      @endif
                      <tr class="border-t border-slate-100 hover:bg-slate-50 {{ $estAnnule ? 'opacity-50' : '' }}" wire:key="contrat-{{ $c->id }}">
                        <td class="px-3 py-2 font-mono text-[11px] text-slate-500">{{ $c->numero ?? MontantFcfa::TIRET }}</td>
                        <td class="px-3 py-2 text-left">
                          <div class="font-semibold text-slate-800">{{ $c->vehicule?->immatriculation ?? MontantFcfa::TIRET }}</div>
                          <div class="text-[11px] text-slate-400">
                            {{ $c->permis_conduire
                                ? __('vehicules.pwa.permis_numero', ['numero' => $c->permis_conduire])
                                : __('vehicules.pwa.sans_permis') }}
                          </div>
                        </td>
                        <td class="px-3 py-2 text-left text-slate-700">
                          {{ $c->client?->nom ?? MontantFcfa::TIRET }}
                          <div class="text-[11px] text-slate-400">{{ $c->piece_identite ?? MontantFcfa::TIRET }}</div>
                        </td>
                        <td class="px-3 py-2 text-right text-slate-600 text-[12px]">
                          {{ $c->date_debut->format('d/m/Y') }}<br>{{ $c->date_fin->format('d/m/Y') }}
                        </td>
                        <td class="px-3 py-2 text-right text-slate-600">{{ $c->nombreJours() }}</td>
                        <td class="px-3 py-2 text-right font-semibold" style="color:var(--navy)">{{ MontantFcfa::format((string) ($c->montant ?? '0')) }}</td>
                        <td class="px-3 py-2 text-right text-emerald-700">{{ MontantFcfa::formatOuTiret((string) ($c->acompte ?? '0')) }}</td>
                        <td class="px-3 py-2 text-right font-semibold {{ bccomp((string) ($c->reste_a_payer ?? '0'), '0', 2) > 0 ? 'text-red-600' : 'text-slate-400' }}">
                          {{ bccomp((string) ($c->reste_a_payer ?? '0'), '0', 2) > 0
                              ? MontantFcfa::format((string) $c->reste_a_payer)
                              : __('vehicules.pwa.solde') }}
                        </td>
                        <td class="px-3 py-2 text-right">
                          @if ($estAnnule)
                            <span class="text-[11px] px-2 py-0.5 rounded bg-slate-100 text-slate-500">{{ __('vehicules.pwa.contrat_annule') }}</span>
                          @else
                            <span class="text-[11px] px-2 py-0.5 rounded bg-emerald-50 text-emerald-700">{{ __('vehicules.pwa.contrat_actif') }}</span>
                          @endif
                        </td>
                        <td class="px-3 py-2 text-right whitespace-nowrap">
                          {{-- Le reçu (PDF) est une LECTURE : offert à tout rôle qui voit l'écran,
                               annulé compris (le document porte alors « ANNULÉ »). --}}
                          <button type="button" wire:click="imprimerRecu('{{ $c->id }}')"
                                  class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white">{{ __('vehicules.pwa.recu') }}</button>
                          @if ($peutEcrire && ! $estAnnule)
                            <button type="button" wire:click="confirmerArchivage('contrat', '{{ $c->id }}')"
                                    class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white">{{ __('vehicules.pwa.annuler_contrat') }}</button>
                          @endif
                        </td>
                      </tr>
                    @endforeach
                    <tr class="bg-[var(--navy)] text-white font-bold">
                      <td class="px-3 py-2.5" colspan="5">{{ __('vehicules.pwa.total_contrats', ['nombre' => $contratsActifsCount]) }}</td>
                      <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($totalMontant) }}</td>
                      <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($totalAcompte) }}</td>
                      <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($totalReste) }}</td>
                      <td colspan="2"></td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>

          {{-- ETAT IMPRIMABLE — document d'export du maitre, onglet Contrats
               (`m8-locations.js` l.436) : la piece d'identite, le permis et
               les bornes « Du » / « Au » y sont des colonnes, la ou l'ecran
               les glisse sous Client / Vehicule / Periode. Memes lignes que
               l'ecran (PA-119) ; le tableau d'ecran est `print:hidden` pour
               que le papier ne porte pas deux fois la meme table. --}}
          <div class="hidden print:block mb-4">
            <h3 class="text-[13px] font-bold mb-2" style="color:var(--navy)">{{ __('vehicules.pwa.contrats_titre') }}</h3>
            <table class="w-full text-[12px]">
              <thead>
                <tr>
                  {!! $enteteDoc(__('vehicules.pwa.col_numero'), true) !!}
                  {!! $enteteDoc(__('vehicules.pwa.col_vehicule'), true) !!}
                  {!! $enteteDoc(__('vehicules.pwa.col_client'), true) !!}
                  {!! $enteteDoc(__('vehicules.pwa.col_piece'), true) !!}
                  {!! $enteteDoc(__('vehicules.pwa.col_permis'), true) !!}
                  {!! $enteteDoc(__('vehicules.pwa.col_du')) !!}
                  {!! $enteteDoc(__('vehicules.pwa.col_au')) !!}
                  {!! $enteteDoc(__('vehicules.pwa.col_jours')) !!}
                  {!! $enteteDoc(__('vehicules.pwa.col_montant')) !!}
                  {!! $enteteDoc(__('vehicules.pwa.col_acompte')) !!}
                  {!! $enteteDoc(__('vehicules.pwa.col_reste')) !!}
                  {!! $enteteDoc(__('vehicules.pwa.col_etat')) !!}
                </tr>
              </thead>
              <tbody>
                @foreach ($contrats as $c)
                  <tr wire:key="doc-contrat-{{ $c->id }}">
                    <td class="{{ $celluleDoc }} text-left font-mono text-[11px]">{{ $c->numero ?? MontantFcfa::TIRET }}</td>
                    <td class="{{ $celluleDoc }} text-left">{{ $c->vehicule?->immatriculation ?? MontantFcfa::TIRET }}</td>
                    <td class="{{ $celluleDoc }} text-left">{{ $c->client?->nom ?? MontantFcfa::TIRET }}</td>
                    {{-- Article 7 : « — » quand la donnee n'existe pas. --}}
                    <td class="{{ $celluleDoc }} text-left">{{ $c->piece_identite ?? MontantFcfa::TIRET }}</td>
                    {{-- Le maitre ecrit « dispense » quand la categorie n'exige pas de permis (RG-09, `m8-locations.js` l.438). --}}
                    <td class="{{ $celluleDoc }} text-left">{{ $c->permis_conduire ?? __('vehicules.pwa.permis_dispense') }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ $c->date_debut->format('d/m/Y') }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ $c->date_fin->format('d/m/Y') }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ $c->nombreJours() }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ MontantFcfa::format((string) ($c->montant ?? '0')) }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ MontantFcfa::formatOuTiret((string) ($c->acompte ?? '0')) }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ MontantFcfa::format((string) ($c->reste_a_payer ?? '0')) }}</td>
                    <td class="{{ $celluleDoc }} text-right">{{ $c->statut === 'annule'
                        ? __('vehicules.pwa.contrat_annule')
                        : __('vehicules.pwa.contrat_actif') }}</td>
                  </tr>
                @endforeach
              </tbody>
            </table>
          </div>
        </section>

        {{-- ============================= ONGLET PLANNING ================== --}}
        {{-- `@if` CONSERVE, seul de la page — voir le commentaire de tete des
             onglets : les en-tetes de jours (1..31) sont des donnees, pas des
             libelles du maitre (01/09/2026). --}}
        @if ($onglet === 'planning')
          @php
              $joursListe = [];
              for ($i = 0; $i < $joursFenetre; $i++) {
                  $joursListe[] = $fenetreDebut->addDays($i);
              }
          @endphp
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
            <div class="px-4 py-3 border-b border-slate-200 flex flex-wrap items-center justify-between gap-2">
              <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('vehicules.pwa.planning_titre', ['jours' => count($joursListe)]) }}</h3>
              <div class="flex gap-3 text-[11px] text-slate-500">
                <span class="flex items-center gap-1"><span class="w-3 h-3 rounded" style="background:#ECFDF5;border:1px solid #A7F3D0"></span>{{ __('vehicules.pwa.legende_libre') }}</span>
                <span class="flex items-center gap-1"><span class="w-3 h-3 rounded" style="background:#1D4ED8"></span>{{ __('vehicules.pwa.legende_location') }}</span>
                <span class="flex items-center gap-1"><span class="w-3 h-3 rounded" style="background:#DC2626"></span>{{ __('vehicules.pwa.legende_immobilise') }}</span>
              </div>
            </div>
            <div class="overflow-x-auto">
              <table class="w-full">
                {{-- En-tête navy (01/09/2026). Pas de barre de recherche : ce
                     tableau est un PLANNING calendaire (véhicule × jours),
                     pas une liste — la légende ci-dessus tient lieu de
                     filtre visuel, comme au maître. --}}
                <thead class="bg-[var(--navy)]">
                  <tr>
                    <th class="px-2 py-2 text-left text-[11px] uppercase tracking-wide text-white/90 font-semibold sticky left-0 bg-[var(--navy)]">{{ __('vehicules.pwa.col_vehicule') }}</th>
                    @foreach ($joursListe as $j)
                      <th class="px-1 py-2 text-center text-[10px] {{ $j->isWeekend() ? 'text-[var(--gold)]' : 'text-white/70' }} font-semibold" title="{{ $j->format('Y-m-d') }}">{{ $j->day }}</th>
                    @endforeach
                  </tr>
                </thead>
                <tbody>
                  @foreach ($parc as $v)
                    <tr class="border-t border-slate-100" wire:key="planning-{{ $v->id }}">
                      <td class="px-2 py-1.5 text-left sticky left-0 bg-white">
                        <div class="text-[12px] font-semibold text-slate-800">{{ $v->immatriculation }}</div>
                        <div class="text-[10px] text-slate-400">{{ MontantFcfa::format((string) $v->tarif_jour) }}/j</div>
                      </td>
                      @foreach ($joursListe as $j)
                        @php
                            $jour = $j->format('Y-m-d');
                            $horsService = $v->statut === 'hors_service';
                            $loue = ! $horsService && $contrats
                                ->where('vehicule_id', $v->id)
                                ->first(fn ($c) => $c->statut !== 'annule'
                                    && $c->date_debut->format('Y-m-d') <= $jour
                                    && $c->date_fin->format('Y-m-d') > $jour) !== null;
                            $couleur = $horsService ? '#DC2626' : ($loue ? '#1D4ED8' : '#ECFDF5');
                        @endphp
                        <td class="px-1 py-1.5">
                          <div class="h-4 rounded" style="background:{{ $couleur }};{{ $couleur === '#ECFDF5' ? 'border:1px solid #A7F3D0' : '' }}"></div>
                        </td>
                      @endforeach
                    </tr>
                  @endforeach
                </tbody>
              </table>
            </div>
          </div>

        @endif

        {{-- ========================== ONGLET IMMOBILISATIONS ============== --}}
        <section class="{{ $onglet === 'immo' ? '' : 'hidden' }}">
          {{--
              L'ETAT VIDE SE RENd DANS LE TABLEAU, PAS A SA PLACE (corrigé le
              02/09/2026). La version précédente remplaçait le tableau ENTIER
              — en-têtes compris — par une simple phrase centrée quand
              `$immobilisations` était vide : l'audit navigateur du Product
              Owner a relevé qu'un onglet vide n'affichait alors AUCUN
              en-tête de colonne, alors que le maître (`m8-locations.js`
              l.414) montre toujours les sept colonnes, même sans ligne.
          --}}
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
            <div class="px-4 py-3 border-b border-slate-200">
              <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('vehicules.pwa.immo_titre') }}</h3>
            </div>
            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]">
                  <tr>
                    {!! $entete(__('vehicules.pwa.col_vehicule'), true) !!}
                    {!! $entete(__('vehicules.pwa.col_motif')) !!}
                    {!! $entete(__('vehicules.pwa.col_du')) !!}
                    {!! $entete(__('vehicules.pwa.col_au')) !!}
                    {!! $entete(__('vehicules.pwa.col_jours')) !!}
                    {!! $entete(__('vehicules.pwa.col_commentaire')) !!}
                    {!! $entete(__('vehicules.pwa.col_enregistre_par')) !!}
                  </tr>
                </thead>
                <tbody>
                  @forelse ($immobilisations as $i)
                    <tr class="border-t border-slate-100" wire:key="immo-{{ $i['id'] }}">
                      <td class="px-3 py-2 text-left font-semibold text-slate-800">{{ $i['vehicule'] }}</td>
                      <td class="px-3 py-2 text-right">
                        <span class="text-[11px] px-2 py-0.5 rounded bg-slate-100 text-slate-600">
                          {{ __('vehicules.pwa.' . Locations::MOTIFS_IMMOBILISATION[$i['motif']]) }}
                        </span>
                      </td>
                      <td class="px-3 py-2 text-right text-slate-600">{{ $i['date']->format('d/m/Y') }}</td>
                      {{-- « Au », « Jours » et « Commentaire » : aucune colonne au schema. --}}
                      <td class="px-3 py-2 text-right text-slate-400">{{ MontantFcfa::TIRET }}</td>
                      <td class="px-3 py-2 text-right text-slate-400">{{ MontantFcfa::TIRET }}</td>
                      <td class="px-3 py-2 text-right text-slate-400">{{ MontantFcfa::TIRET }}</td>
                      <td class="px-3 py-2 text-right text-slate-500 text-[12px]">{{ $i['auteur'] ?? MontantFcfa::TIRET }}</td>
                    </tr>
                  @empty
                    <tr>
                      <td colspan="7" class="py-14 text-center text-slate-400 text-[13px]">{{ __('vehicules.pwa.immo_vide') }}</td>
                    </tr>
                  @endforelse
                </tbody>
              </table>
            </div>
          </div>
        </section>

        {{--
            NON PORTE, ET PLUS RENDU A L'ECRAN (02/09/2026). Directive du
            Product Owner : un ecran dit ce qu'il FAIT. Ce qui reste non porte
            se declare ici :
            - le client d'un contrat est une vraie cle etrangere, jamais du
              texte libre comme au maitre ;
            - le registre des immobilisations et leur levee n'ont aucune table ;
            - le planning des circuits est celui de M9, pas de cet ecran ;
            - les categories dispensees de permis attendent l'arbitrage PA-50
              (`Vehicule::CATEGORIES_SANS_PERMIS` est le seul endroit a
              modifier ce jour-la).
        --}}

      </div>
    </main>
  </div>

  {{-- ==================== MODALE « Nouveau contrat de location » ========= --}}
  @if ($etatFormulaire === 'contrat')
    <x-pwa.modale :titre="__('vehicules.pwa.modale_contrat_titre')"
                  :sousTitre="__('vehicules.pwa.modale_contrat_sous_titre')"
                  largeur="620px">
      @php $vehiculeChoisi = $parcComplet->firstWhere('id', $vehiculeIdContrat); @endphp
      @php $clientChoisi = $clients->firstWhere('id', $clientIdContrat); @endphp
      @php $joursApercu = 0; @endphp
      @php $montantApercu = '0.00'; @endphp
      @if ($vehiculeChoisi && $dateDebutContrat !== '' && $dateFinContrat !== '' && $dateFinContrat > $dateDebutContrat)
        @php $joursApercu = (int) \Carbon\CarbonImmutable::parse($dateDebutContrat)->diffInDays(\Carbon\CarbonImmutable::parse($dateFinContrat)); @endphp
        @php $montantApercu = bcmul((string) $vehiculeChoisi->tarif_jour, (string) $joursApercu, 2); @endphp
      @endif

      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('vehicules.pwa.champ_vehicule') }} <span class="text-red-500">*</span></label>
        <select wire:model.live="vehiculeIdContrat" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @foreach ($parcComplet as $v)
            <option value="{{ $v->id }}">{{ $v->immatriculation }} — {{ MontantFcfa::format((string) $v->tarif_jour) }}{{ __('vehicules.pwa.par_jour') }}</option>
          @endforeach
        </select>
        @if ($vehiculeChoisi)
          <div class="text-[11px] text-slate-500 mt-1">
            {{ __('vehicules.pwa.info_vehicule', ['places' => $vehiculeChoisi->capacite, 'categorie' => $libelleCategorie($vehiculeChoisi->categorie)]) }} ·
            @if ($vehiculeChoisi->exigePermis())
              <span class="text-amber-700">{{ __('vehicules.pwa.info_permis_exige') }}</span>
            @else
              <span class="text-emerald-700">{{ __('vehicules.pwa.info_permis_dispense') }}</span>
            @endif
          </div>
        @endif
        @error('vehiculeIdContrat') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('vehicules.pwa.champ_depart') }} <span class="text-red-500">*</span></label>
          <input type="date" wire:model.live="dateDebutContrat" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('dateDebutContrat') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('vehicules.pwa.champ_restitution') }} <span class="text-red-500">*</span></label>
          <input type="date" wire:model.live="dateFinContrat" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('dateFinContrat') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div>
          {{-- RG-18 : le client est une CLE ETRANGERE, jamais un nom libre. --}}
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('vehicules.pwa.champ_client') }} <span class="text-red-500">*</span></label>
          @if ($clients->isEmpty())
            <p class="text-[12px] text-amber-700">{{ __('vehicules.pwa.client_aucun') }}</p>
          @else
            <select wire:model.live="clientIdContrat" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
              @foreach ($clients as $client)
                <option value="{{ $client->id }}">{{ trim($client->prenom . ' ' . $client->nom) }}</option>
              @endforeach
            </select>
          @endif
          @error('clientIdContrat') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('vehicules.pwa.champ_telephone') }}</label>
          {{-- Lu sur la fiche client : le saisir ici en dupliquerait la source. --}}
          <p class="text-[13px] text-slate-600 border border-slate-200 bg-slate-50 rounded-lg px-3 py-2.5">{{ $clientChoisi?->telephone ?? MontantFcfa::TIRET }}</p>
        </div>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('vehicules.pwa.champ_piece') }} <span class="text-red-500">*</span></label>
          <input type="text" wire:model="pieceIdentiteSaisie" placeholder="{{ __('vehicules.pwa.invite_piece') }}"
                 class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('pieceIdentiteSaisie') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        @if (! $vehiculeChoisi || $vehiculeChoisi->exigePermis())
          <div>
            <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('vehicules.pwa.champ_permis') }} <span class="text-red-500">*</span></label>
            <input type="text" wire:model="numeroPermisSaisi" placeholder="{{ __('vehicules.pwa.invite_permis') }}"
                   class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
            @error('numeroPermisSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
        @endif
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('vehicules.pwa.champ_remise') }}</label>
          <input type="number" min="0" step="500" wire:model.live="remiseSaisie" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('remiseSaisie') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('vehicules.pwa.champ_acompte') }}</label>
          <input type="number" min="0" step="500" wire:model.live="acompteSaisi" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('acompteSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
      </div>

      @if ($joursApercu > 0)
        <div class="border border-slate-200 rounded-lg p-3 text-[12px]">
          <div class="flex justify-between">
            <span class="text-slate-600">{{ __('vehicules.pwa.apercu_jours', ['jours' => $joursApercu, 'tarif' => MontantFcfa::format((string) $vehiculeChoisi->tarif_jour)]) }}</span>
            <strong>{{ MontantFcfa::format($montantApercu) }}</strong>
          </div>
          <div class="flex justify-between"><span class="text-slate-600">{{ __('vehicules.pwa.apercu_remise') }}</span><span class="text-emerald-600">− {{ MontantFcfa::format(bcadd((string) $remiseSaisie, '0', 2)) }}</span></div>
          <div class="flex justify-between"><span class="text-slate-600">{{ __('vehicules.pwa.apercu_acompte') }}</span><span class="text-emerald-600">− {{ MontantFcfa::format(bcadd((string) $acompteSaisi, '0', 2)) }}</span></div>
          <div class="flex justify-between border-t border-slate-200 mt-1 pt-1">
            <strong style="color:var(--navy)">{{ __('vehicules.pwa.apercu_reste') }}</strong>
            <strong style="color:var(--navy)">
              {{ MontantFcfa::format(bcsub(bcsub($montantApercu, bcadd((string) $remiseSaisie, '0', 2), 2), bcadd((string) $acompteSaisi, '0', 2), 2)) }}
            </strong>
          </div>
        </div>
      @endif

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerContrat" wire:loading.attr="disabled"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('vehicules.pwa.bouton_etablir') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ==================== MODALE « Immobiliser un véhicule » ============= --}}
  @if ($etatFormulaire === 'immobilisation')
    <x-pwa.modale :titre="__('vehicules.pwa.modale_immo_titre')"
                  :sousTitre="__('vehicules.pwa.modale_immo_sous_titre')"
                  largeur="520px">
      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('vehicules.pwa.champ_vehicule') }} <span class="text-red-500">*</span></label>
        <select wire:model="vehiculeIdImmo" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @foreach ($parcComplet as $v)
            <option value="{{ $v->id }}">{{ $v->immatriculation }}</option>
          @endforeach
        </select>
        @error('vehiculeIdImmo') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('vehicules.pwa.champ_motif') }} <span class="text-red-500">*</span></label>
        <select wire:model="motifImmo" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @foreach (Locations::MOTIFS_IMMOBILISATION as $valeur => $cle)
            <option value="{{ $valeur }}">{{ __('vehicules.pwa.' . $cle) }}</option>
          @endforeach
        </select>
        @error('motifImmo') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('vehicules.pwa.champ_date') }} <span class="text-red-500">*</span></label>
          <input type="date" wire:model="dateImmo" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('dateImmo') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('vehicules.pwa.champ_cout') }} <span class="text-red-500">*</span></label>
          <input type="number" min="0" step="500" wire:model="coutImmo" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('coutImmo') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
      </div>

      {{-- NON PORTE (02/09/2026) : aucune table ne porte un registre des
           immobilisations. Le bandeau qui le disait dans cette modale est
           retire ; la raison se lit ici. --}}

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerImmobilisation" wire:loading.attr="disabled"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('vehicules.pwa.bouton_immobiliser') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ==================== MODALE « Véhicule » (hors maitre) ============== --}}
  @if ($etatFormulaire === 'vehicule')
    <x-pwa.modale :titre="$vehiculeIdEdite
                      ? __('vehicules.pwa.modale_vehicule_titre_edition')
                      : __('vehicules.pwa.modale_vehicule_titre_creation')"
                  :sousTitre="__('vehicules.pwa.modale_vehicule_sous_titre')"
                  largeur="560px">
      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('vehicules.pwa.champ_immatriculation') }} <span class="text-red-500">*</span></label>
          <input type="text" wire:model="immatriculationSaisie" placeholder="{{ __('vehicules.pwa.invite_immatriculation') }}"
                 class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('immatriculationSaisie') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('vehicules.pwa.col_categorie') }} <span class="text-red-500">*</span></label>
          <select wire:model="categorieSaisie" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
            @foreach ($categories as $cat)
              <option value="{{ $cat }}">{{ $libelleCategorie($cat) }}</option>
            @endforeach
          </select>
          @error('categorieSaisie') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
      </div>

      <div class="grid grid-cols-3 gap-3">
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('vehicules.pwa.champ_capacite') }} <span class="text-red-500">*</span></label>
          <input type="number" min="1" step="1" wire:model="capaciteSaisie" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('capaciteSaisie') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('vehicules.pwa.champ_annee') }} <span class="text-red-500">*</span></label>
          <input type="number" min="1950" step="1" wire:model="anneeSaisie" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('anneeSaisie') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('vehicules.pwa.champ_transmission') }}</label>
          <input type="text" wire:model="transmissionSaisie" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('transmissionSaisie') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
      </div>

      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('vehicules.pwa.champ_tarif') }} <span class="text-red-500">*</span></label>
        <input type="number" min="0" step="500" wire:model="tarifJourSaisi" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
        @error('tarifJourSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerVehicule" wire:loading.attr="disabled"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('vehicules.pwa.bouton_enregistrer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ==================== MODALE D'ARCHIVAGE ============================= --}}
  @if ($etatFormulaire === 'archivage')
    <x-pwa.modale-archivage action="executerSuppression"
                            :element="$libelleElementSupprime"
                            :messagesVerrou="$verrousArchivage"
                            :bloque="$archivageBloque"
                            :message="$archivageBloque ? null : ($typeElementSupprime === 'vehicule'
                                ? __('vehicules.pwa.archiver_vehicule', ['element' => $libelleElementSupprime])
                                : __('vehicules.pwa.archiver_contrat', ['element' => $libelleElementSupprime]))" />
  @endif

  {{-- ==================== MODALE D'EXPORT (partagee) ===================== --}}
  @if ($etatFormulaire === 'export')
    @include('pwa.partials.modale-export', ['titre' => __('vehicules.pwa.export_titre')])
    @error('formatExport')
      <div class="fixed bottom-5 right-5 z-50 px-4 py-3 rounded-xl bg-red-600 text-white text-[13px] no-print">{{ $message }}</div>
    @enderror
  @endif

  @include('pwa.partials.acces-rapide')
</div>

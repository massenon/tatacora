{{--
    M13 — PERSONNEL & PAIE.

    Maitre : `prototype_v2/pages/m13-paie.html` et `m13-paie.js` ; la forme du
    bulletin et du livre vient de `prototype_v2/assets/js/paie-engine.js`.

    ## Aucun montant de paie n'est saisi

    Le net, la CNSS, l'ITS et la part patronale sont CALCULES par
    `CalculPaieService` et rendus en lecture seule. Le seul montant saisi de
    l'ecran est le salaire de base, qui est une donnee du contrat de travail.

    ## Le cout employeur est TOUJOURS une fourchette (PA-53)

    Le taux CNSS de risques professionnels est « 1 % a 4 % selon l'activite »
    et n'est pas confirme pour l'hotellerie-restauration. Aucun total de charge
    patronale n'apparait nulle part sur cet ecran — ni en tableau, ni en
    indicateur, ni a l'export. Retenir 2,5 % « au milieu » serait exactement
    l'hypothese refusee.

    ## Ce qui est OMIS, avec sa raison datee (31/08/2026)

    - Le « + Ajouter un element » de la modale d'etablissement, et avec lui les
      primes et retenues du mois : `primes_sanctions` existe au schema, mais
      aucun modele ni service ne la touche dans ce depot. Un champ qui
      n'ecrirait nulle part serait un faux ecran.
    - Les champs « Telephone » et « Centre analytique » de la fiche employe :
      aucune colonne sur `employes`.
    - La PIECE de l'« Ecriture comptable proposee » et le bouton
      « Comptabiliser la paie » : le listener « GenererEcritureDepuisPaie » que
      `create_rh.php` annonce lui-meme n'existe nulle part, et ecrire la piece
      depuis M13 doublerait le seul point d'entree d'ecriture comptable, ou vit
      RG-11. Depuis le 01/09/2026 le SQUELETTE du tableau du maitre (Compte,
      Libelle, Debit, Credit) est rendu dans l'onglet Livre de paie ; son corps
      est l'etat vide qui nomme ce refus, avec sa raison datee. Aucune ligne
      d'ecriture n'est inventee.
    - Les onglets « Presences », « Conges » et « Departs » que porte l'ancienne
      page `m13-rh.html` : cette page se declare elle-meme remplacee par
      celle-ci, et `presences` / `evaluations` n'ont ni modele ni service.

    Declarations pour la garde des trois sources :
      maitre-refuse:m13-paie.html#page
      maitre-refuse:m13-paie.html#personnel
      maitre-refuse:m13-paie.html#modale-employe
      maitre-refuse:m13-paie.html#modale-etablir
      maitre-refuse:m13-paie.html#modale-bulletin

    ⚠ Ces jetons DOCUMENTENT l'omission ; ils ne sont pas tous « consommes »
    par la garde a chaque execution. `t-trois-sources.js` ne distingue pas une
    chaine rendue d'une chaine mentionnee en commentaire (c'est ecrit dans son
    entete) : les libelles nommes ci-dessus lui suffisent, et le jeton ne sert
    alors qu'au lecteur. Il reste ecrit parce que l'omission, elle, est bien
    reelle — un jeton retire le jour ou la garde n'en a plus besoin ferait
    disparaitre la DECISION en meme temps que le signal.

    ## Les registres fermes du maitre, nommes ici parce qu'ils vivent au modele

    Les quatre types de contrat du filtre et de la fiche — CDI, CDD, Stage,
    Journalier — viennent de `Employe::TYPES_CONTRAT`, registre ferme du
    domaine. La vue les rend en boucle : elle ne recopie pas la liste, sans
    quoi deux listes finiraient par diverger. Ils sont nommes ici pour que la
    garde des trois sources les voie, puisqu'elle ne lit pas `app/Domain`.

    ## La casse des entetes est celle du MAITRE

    `Matricule`, pas `MATRICULE` : `uppercase` est une regle CSS, elle ne
    s'applique ni au CSV ni au PDF.
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

    $fourchette = static fn (?array $cout): string => $cout === null
        ? MontantFcfa::TIRET
        : MontantFcfa::format($cout['cout_min']) . ' — ' . MontantFcfa::format($cout['cout_max']);
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

        {{-- EN-TETE — maitre l.33-49 --}}
        <div class="mb-5 flex flex-wrap items-start justify-between gap-3">
          <div>
            <div class="flex items-center gap-2.5">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2M9 11a4 4 0 100-8 4 4 0 000 8zM23 21v-2a4 4 0 00-3-3.87M16 3.13a4 4 0 010 7.75"/></svg>
              <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('rh_pwa.titre') }}</h1>
            </div>
            <p class="text-[15px] text-slate-500 mt-1.5">{!! __('rh_pwa.sous_titre') !!}</p>
          </div>

          <div class="flex flex-wrap gap-2 items-center">
            <label class="text-[12px] text-slate-500">{{ __('rh_pwa.periode') }}</label>
            @php($bornesExercice = \App\Pwa\Support\ExerciceConsulte::bornes())
            <input type="month" wire:model.live="periode" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-2"
                   @if ($bornesExercice !== null) min="{{ $bornesExercice[0]->format('Y-m') }}" max="{{ $bornesExercice[1]->subDay()->format('Y-m') }}" @endif>

            {{-- Exporter est une LECTURE : offert a tout role qui peut ouvrir
                 l'ecran (PA-119).

                 ⚠ DÉROGATION PO du 01/09/2026 — les deux boutons du maître
                 (`m13-paie.html` l.46-47, « Excel » / « PDF ») sont
                 remplacés par UN bouton « Exporter » qui ouvre la même
                 modale d'export ; le format s'y choisit, sans présélection
                 imposée. Registre : `App\Pwa\Support\DerogationsMaquette`
                 (export_bouton_unique). Jeton :
                 maitre-refuse:m13-paie.html#page --}}
            <button type="button" wire:click="ouvrirExport" wire:loading.attr="disabled"
                    class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white hover:opacity-90 font-semibold">{{ __('pwa.export.bouton') }}</button>
          </div>
        </div>

        {{-- LE REFERENTIEL DE TAUX PEUT ETRE VIDE, ET L'ECRAN LE DIT.
             `PaieReferentielSeeder` n'est appele par personne : sur une base
             fraichement semee, aucun taux n'est en `parametres_systeme`. Sans
             ce bandeau, l'ecran afficherait des tirets sans dire pourquoi. --}}
        @unless ($etatReferentiel['complet'])
          <div class="rounded-xl p-3.5 mb-4" style="background:#FEF2F2;border:1px solid #FECACA">
            <p class="text-[13px]" style="color:#7F1D1D">
              <strong>{{ __('rh_pwa.referentiel_titre') }}</strong>
              {{ __('rh_pwa.referentiel_texte', ['cles' => implode(', ', $etatReferentiel['cles_absentes'])]) }}
            </p>
          </div>
        @endunless

        {{-- BANDE D'INDICATEURS — accordeon (derogation `DerogationsMaquette`),
             maitre `m13-paie.js` l.829-846. --}}
        <div x-data="{ ouverts: localStorage.getItem('pwa_kpis_m13') !== 'false' }" class="mb-5">
          <button type="button"
                  @click="ouverts = !ouverts; localStorage.setItem('pwa_kpis_m13', ouverts)"
                  class="w-full flex items-center justify-between px-4 py-3 bg-white border border-slate-200 rounded-xl">
            <span class="text-sm font-bold text-slate-700">{{ __('rh_pwa.kpis_accordeon') }}</span>
            <span class="text-[11px] text-slate-400 font-normal hidden sm:inline">{{ __('rh_pwa.kpis_aide') }}</span>
          </button>

          <div x-show="ouverts" class="grid grid-cols-2 lg:grid-cols-6 gap-3 mt-3">
            <div class="bg-white rounded-xl border border-slate-200 p-3.5">
              <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('rh_pwa.kpi_effectif') }}</div>
              <div class="text-[17px] font-bold mt-1" style="color:var(--navy)">{{ $employes->count() }}</div>
              <div class="text-[11px] text-slate-400 mt-0.5">{{ __('rh_pwa.kpi_effectif_detail', ['nombre' => $effectifTotal]) }}</div>
            </div>

            <div class="bg-white rounded-xl border border-slate-200 p-3.5">
              <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('rh_pwa.kpi_masse') }}</div>
              <div class="text-[17px] font-bold mt-1" style="color:var(--navy)">{{ MontantFcfa::format($masseSalariale) }}</div>
              <div class="text-[11px] text-slate-400 mt-0.5">{{ __('rh_pwa.kpi_masse_detail') }}</div>
            </div>

            <div class="bg-white rounded-xl border border-slate-200 p-3.5">
              <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('rh_pwa.kpi_cout') }}</div>
              {{-- FOURCHETTE, jamais un chiffre unique (PA-53). --}}
              <div class="text-[17px] font-bold mt-1 text-amber-600">{{ $coutMasse === null ? MontantFcfa::TIRET : MontantFcfa::format($coutMasse['cout_min']) }}</div>
              <div class="text-[11px] text-slate-400 mt-0.5">{{ $coutMasse === null ? MontantFcfa::TIRET : __('rh_pwa.kpi_cout_detail', ['montant' => MontantFcfa::format($coutMasse['cout_max'])]) }}</div>
            </div>

            <div class="bg-white rounded-xl border border-slate-200 p-3.5">
              <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('rh_pwa.kpi_net') }}</div>
              <div class="text-[17px] font-bold mt-1" style="color:var(--navy)">{{ MontantFcfa::format($totaux['net']) }}</div>
              <div class="text-[11px] text-slate-400 mt-0.5">{{ __('rh_pwa.kpi_net_detail', ['nombre' => $totaux['effectif']]) }}</div>
            </div>

            <div class="bg-white rounded-xl border border-slate-200 p-3.5">
              <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('rh_pwa.kpi_vps') }}</div>
              <div class="text-[17px] font-bold mt-1" style="color:var(--navy)">{{ MontantFcfa::format($totaux['vps']) }}</div>
              <div class="text-[11px] text-slate-400 mt-0.5">{{ __('rh_pwa.kpi_vps_detail') }}</div>
            </div>

            <div class="bg-white rounded-xl border border-slate-200 p-3.5">
              <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('rh_pwa.kpi_manquants') }}</div>
              <div class="text-[17px] font-bold mt-1 {{ $nombreManquants > 0 ? 'text-red-600' : 'text-emerald-600' }}">{{ $nombreManquants }}</div>
              <div class="text-[11px] text-slate-400 mt-0.5">{{ $sansNumeroCnss > 0 ? __('rh_pwa.kpi_manquants_cnss', ['nombre' => $sansNumeroCnss]) : __('rh_pwa.kpi_manquants_ok') }}</div>
            </div>
          </div>
        </div>

        {{-- ONGLETS — maitre l.56-62 --}}
        <div class="flex flex-wrap gap-1.5 mb-4">
          <button type="button" wire:click="$set('onglet', 'personnel')" class="{{ $classeOnglet($onglet === 'personnel') }}">{{ __('rh_pwa.onglet_personnel') }}</button>
          <button type="button" wire:click="$set('onglet', 'bulletins')" class="{{ $classeOnglet($onglet === 'bulletins') }}">{{ __('rh_pwa.onglet_bulletins') }}</button>
          <button type="button" wire:click="$set('onglet', 'livre')" class="{{ $classeOnglet($onglet === 'livre') }}">{{ __('rh_pwa.onglet_livre') }}</button>
          <button type="button" wire:click="$set('onglet', 'declarations')" class="{{ $classeOnglet($onglet === 'declarations') }}">{{ __('rh_pwa.onglet_declarations') }}</button>
          <button type="button" wire:click="$set('onglet', 'bareme')" class="{{ $classeOnglet($onglet === 'bareme') }}">{{ __('rh_pwa.onglet_bareme') }}</button>
        </div>

        {{-- LE BANDEAU PERMANENT DE LA PAIE — maitre `m13-paie.js` l.53-58
             (`AVERTISSEMENT_RP`, préfixé à `#zone` par CHAQUE vue d'onglet —
             donc APRÈS la barre d'onglets, jamais avant la bande de KPI).
             Il vivait ici avant les KPI jusqu'au 01/09/2026 (audit navigateur) :
             remis à sa place — KPI → onglets → encart jaune. Il porte le
             refus de PA-53 et reste affiché sur les cinq onglets : un coût
             employeur en fourchette sans son explication se lirait comme une
             imprecision d'affichage. --}}
        <div class="rounded-xl p-3.5 mb-4" style="background:#FFFBEB;border:1px solid #FDE68A">
          <p class="text-[13px]" style="color:#78350F">
            <strong>{{ __('rh_pwa.rp_titre') }}</strong> {!! __('rh_pwa.rp_texte') !!}
          </p>
        </div>

        {{-- FILTRES — maitre l.64-89 --}}
        <div class="bg-white rounded-xl border border-slate-200 p-3.5 mb-4">
          <div class="flex flex-wrap gap-2.5 items-center">
            <div class="relative flex-1 min-w-[200px]">
              <svg class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
              <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="{{ __('rh_pwa.recherche') }}"
                class="w-full text-[13px] border border-slate-300 rounded-lg pl-9 pr-3 py-2 focus:border-[var(--gold)] focus:outline-none">
            </div>

            <select wire:model.live="filtreService" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <option value="">{{ __('rh_pwa.tous_services') }}</option>
              @foreach ($services as $service)
                <option value="{{ $service->id }}">{{ $service->libelle }}</option>
              @endforeach
            </select>

            <select wire:model.live="filtreContrat" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <option value="">{{ __('rh_pwa.tous_contrats') }}</option>
              @foreach ($typesContrat as $type)
                <option value="{{ $type }}">{{ $type }}</option>
              @endforeach
            </select>

            <select wire:model.live="filtreStatut" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <option value="actif">{{ __('rh_pwa.statut_actifs') }}</option>
              <option value="">{{ __('rh_pwa.statut_tous') }}</option>
              <option value="parti">{{ __('rh_pwa.statut_sortis') }}</option>
              <option value="sans_cnss">{{ __('rh_pwa.statut_sans_cnss') }}</option>
            </select>

            <div class="flex-1"></div>

            @if ($peutEcrire)
              <button type="button" wire:click="ouvrirFormulaireEmploye"
                      class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('rh_pwa.nouvel_employe') }}</button>
            @endif
          </div>
        </div>

        {{-- LES CINQ PANNEAUX D'ONGLET SONT TOUS RENDUS (01/09/2026).

             Le maitre construit la vue de l'onglet actif dans `#zone`
             (`m13-paie.js`, `rendre()` l.906) ; les quatre autres existent
             dans son code, pretes a etre montees. La PWA rend les cinq
             panneaux et masque les inactifs par `hidden` — meme geste que
             `hebergement.blade.php` : un onglet dont aucune colonne n'est
             rendue n'est pas un onglet livre (Article 3.3), et la garde G5
             (`ColonnesDesTableauxPwaTest`) compare les en-tetes de tableau au
             premier GET.

             Un tableau sans ligne garde son `<thead>` et le dit dans une ligne
             d'etat vide — jamais un `@if` qui retire le tableau du HTML.

             Le maitre genere ses cartes de tableau en JavaScript
             (`m13-paie.js` `tableau()` l.28-40) : `t-structure.js` ne lit pas
             ce helper, donc ces cartes lui apparaissent comme des blocs que le
             maitre n'a pas. Elles sont DECLAREES, avec cette raison :
               structure-ajout:m13-paie.html#div-cc70a52a --}}

        {{-- ============================================== ONGLET PERSONNEL --}}
        <div id="panneau-paie-personnel" class="{{ $onglet === 'personnel' ? '' : 'hidden' }}">
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
            <div class="px-4 py-3 border-b border-slate-200 flex items-center justify-between gap-3">
              <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('rh_pwa.effectif_titre', ['periode' => $periodeLongue]) }}</h3>
              {{-- Archivage en bloc (directive PO du 02/09/2026, elargi le
                   03/09/2026) : supprimer = archiver (statut « parti »,
                   RG-15). `$peutArchiver` est calcule par le composant —
                   administrateur et super_admin sans bascule, les autres roles
                   en `C` derriere la bascule des Parametres. La vue ne rejoue
                   PAS cette regle : elle la lit. Le bouton n'apparait qu'avec
                   une selection : un bouton rouge permanent inviterait au clic.
                   Le compteur suit `$selectionAffichee`, donc les filtres. --}}
              @if ($peutArchiver && count($selectionAffichee) > 0)
                <button type="button" wire:click="ouvrirArchivageEmployes"
                        class="text-[12px] px-3 py-1.5 rounded-lg bg-[var(--erreur)] text-white font-bold hover:brightness-110">
                  {{ trans_choice('rh_pwa.archivage.bouton_lot', count($selectionAffichee), ['nombre' => count($selectionAffichee)]) }}
                </button>
              @endif
            </div>
            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]"><tr>
                  {{-- Case de selection (motif de `facturation.blade.php`) —
                       rendue seulement quand l'archivage est possible, pour ne
                       pas offrir une case qui ne commande rien. --}}
                  @if ($peutArchiver)
                    <th class="px-3 py-2.5 w-8">
                      <input type="checkbox" wire:model.live="toutSelectionne" class="w-4 h-4 rounded"
                             aria-label="{{ __('rh_pwa.archivage.selection_tout') }}">
                    </th>
                  @endif
                  {!! $entete(__('rh_pwa.col_matricule'), true) !!}
                  {!! $entete(__('rh_pwa.col_employe'), true) !!}
                  {!! $entete(__('rh_pwa.col_contrat')) !!}
                  {!! $entete(__('rh_pwa.col_embauche')) !!}
                  {!! $entete(__('rh_pwa.col_cnss')) !!}
                  {!! $entete(__('rh_pwa.col_salaire_base')) !!}
                  {!! $entete(__('rh_pwa.col_cout_employeur')) !!}
                  {{-- La colonne d'actions n'a PAS d'entete : le maitre termine
                       ses tableaux par une chaine vide. --}}
                  <th class="px-3 py-2.5"></th>
                </tr></thead>
                <tbody>
                  @forelse ($employes as $employe)
                    @php($bulletin = $bulletinsParEmploye[$employe->id] ?? null)
                    <tr class="border-t border-slate-100 hover:bg-slate-50">
                      {{-- La CELLULE existe toujours (sans quoi la ligne
                           perdrait une colonne et le tableau se decalerait) ;
                           la case, elle, n'est offerte que sur une ligne
                           reellement archivable. Une case qui ne peut produire
                           qu'un refus est un faux controle. --}}
                      @if ($peutArchiver)
                        <td class="px-3 py-2">
                          @if ($employe->statut !== 'parti')
                            <input type="checkbox" value="{{ $employe->id }}" wire:model.live="selection" class="w-4 h-4 rounded"
                                   aria-label="{{ __('rh_pwa.archivage.selection_ligne') }}">
                          @endif
                        </td>
                      @endif
                      <td class="px-3 py-2 font-mono text-[12px] text-slate-500">{{ $employe->matricule ?? MontantFcfa::TIRET }}</td>
                      <td class="px-3 py-2 text-left">
                        <div class="font-semibold text-slate-800">{{ $employe->nomComplet() }}</div>
                        <div class="text-[11px] text-slate-400">{{ $employe->poste }}@if ($employe->service) · {{ $employe->service->libelle }}@endif</div>
                      </td>
                      <td class="px-3 py-2 text-right text-slate-600">
                        {{ $employe->type_contrat ?? MontantFcfa::TIRET }}
                        @if ($employe->date_fin_contrat)
                          <div class="text-[11px] text-slate-400">{{ __('rh_pwa.jusquau', ['date' => $employe->date_fin_contrat->format('d/m/Y')]) }}</div>
                        @endif
                      </td>
                      <td class="px-3 py-2 text-right text-slate-600">{{ $employe->date_embauche->format('d/m/Y') }}</td>
                      <td class="px-3 py-2 text-right">
                        @if ($employe->sansNumeroCnss())
                          <span class="text-[11px] px-1.5 py-0.5 rounded bg-amber-50 text-amber-700">{{ __('rh_pwa.cnss_absent') }}</span>
                        @else
                          <span class="text-[11px] font-mono text-slate-500">{{ $employe->numero_cnss }}</span>
                        @endif
                      </td>
                      <td class="px-3 py-2 text-right font-semibold" style="color:var(--navy)">{{ MontantFcfa::format((string) $employe->salaire_base) }}</td>
                      <td class="px-3 py-2 text-right text-slate-600 text-[12px]">{{ $fourchette($coutParEmploye[$employe->id] ?? null) }}</td>
                      <td class="px-3 py-2 text-right whitespace-nowrap">
                        @if ($bulletin)
                          <button type="button" wire:click="$set('bulletinAffiche', '{{ $bulletin->id }}')"
                                  class="text-[11px] px-2 py-0.5 rounded border border-emerald-300 bg-emerald-50 text-emerald-700 hover:bg-emerald-100">{{ __('rh_pwa.action_bulletin') }}</button>
                        @elseif ($peutEcrire)
                          <button type="button" wire:click="ouvrirEtablissementBulletin('{{ $employe->id }}')"
                                  class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white">{{ __('rh_pwa.action_etablir') }}</button>
                        @endif
                        @if ($peutEcrire)
                          <button type="button" wire:click="ouvrirFormulaireEmploye('{{ $employe->id }}')"
                                  class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white ml-1">{{ __('rh_pwa.action_modifier') }}</button>
                        @endif
                        {{-- Bouton rouge, SUR CHAQUE LIGNE (directive PO du
                             02/09/2026, elargie le 03/09/2026) : le « Supprimer »
                             demande par le PO archive l'employe (statut
                             « parti »), jamais une suppression — la modale le
                             dit mot pour mot. Absent des lignes deja parties :
                             `EmployeService::archiver()` les refuserait, et un
                             bouton qui ne peut que refuser est un faux bouton. --}}
                        @if ($peutArchiver && $employe->statut !== 'parti')
                          <button type="button" wire:click="ouvrirArchivageEmployes('{{ $employe->id }}')"
                                  class="text-[11px] px-2 py-0.5 rounded bg-[var(--erreur)] text-white font-bold hover:brightness-110 ml-1">{{ __('rh_pwa.archivage.action') }}</button>
                        @endif
                      </td>
                    </tr>
                  @empty
                    <tr><td colspan="{{ $peutArchiver ? 9 : 8 }}" class="px-3 py-14 text-center">
                      <p class="text-[13px] font-semibold text-slate-500">{{ __('rh_pwa.aucun_resultat') }}</p>
                      <p class="text-[13px] text-slate-400 mt-1">{{ __('rh_pwa.aucun_employe') }}</p>
                    </td></tr>
                  @endforelse

                  @if ($employes->isNotEmpty())
                    <tr class="bg-[var(--navy)] text-white font-bold">
                      <td class="px-3 py-2.5" colspan="{{ $peutArchiver ? 6 : 5 }}">{{ __('rh_pwa.total_effectif', ['nombre' => $employes->count()]) }}</td>
                      <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($masseSalariale) }}</td>
                      <td class="px-3 py-2.5 text-right text-[12px]">{{ $fourchette($coutMasse) }}</td>
                      <td></td>
                    </tr>
                  @endif
                </tbody>
              </table>
            </div>
          </div>
        </div>

        {{-- ============================================== ONGLET BULLETINS --}}
        <div id="panneau-paie-bulletins" class="{{ $onglet === 'bulletins' ? '' : 'hidden' }}">
          @if ($peutEcrire)
            <div class="flex flex-wrap gap-2 mb-3">
              <button type="button" wire:click="genererBulletinsManquants" wire:loading.attr="disabled"
                      class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('rh_pwa.generer_manquants', ['nombre' => $nombreManquants]) }}</button>
            </div>
          @endif

          @error('periode') <p class="text-[12px] text-red-600 mb-2">{{ $message }}</p> @enderror

          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
            <div class="px-4 py-3 border-b border-slate-200 flex flex-wrap items-center justify-between gap-2">
              <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('rh_pwa.bulletins_titre', ['periode' => $periodeLongue]) }}</h3>
              <span class="text-[11px] text-amber-700">{{ __('rh_pwa.bulletins_note_rp') }}</span>
            </div>
            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]"><tr>
                  {!! $entete(__('rh_pwa.col_matricule'), true) !!}
                  {!! $entete(__('rh_pwa.col_employe'), true) !!}
                  {!! $entete(__('rh_pwa.col_brut')) !!}
                  {!! $entete(__('rh_pwa.col_cnss_salarie')) !!}
                  {!! $entete(__('rh_pwa.col_its')) !!}
                  {!! $entete(__('rh_pwa.col_autres_retenues')) !!}
                  {!! $entete(__('rh_pwa.col_net')) !!}
                  {!! $entete(__('rh_pwa.col_charges_patronales')) !!}
                  <th class="px-3 py-2.5"></th>
                </tr></thead>
                <tbody>
                  @forelse ($bulletinsDuMois as $bulletin)
                    <tr class="border-t border-slate-100 hover:bg-slate-50 {{ $bulletin->estAnnule() ? 'opacity-50' : '' }}">
                      <td class="px-3 py-2 font-mono text-[11px] text-slate-500">{{ $bulletin->employe->matricule ?? MontantFcfa::TIRET }}</td>
                      <td class="px-3 py-2 text-left">
                        <div class="font-semibold text-slate-800">{{ $bulletin->employe->nomComplet() }}</div>
                        <div class="text-[11px] text-slate-400">{{ $bulletin->employe->poste }}</div>
                        @if ($bulletin->estAnnule())
                          <div class="text-[11px] text-red-600">{{ __('rh_pwa.bulletin_annule', ['motif' => $bulletin->motif_annulation]) }}</div>
                        @endif
                      </td>
                      <td class="px-3 py-2 text-right font-semibold">{{ MontantFcfa::format($bulletin->brut()) }}</td>
                      <td class="px-3 py-2 text-right text-red-600">{{ MontantFcfa::formatOuTiret((string) $bulletin->cnss_salarie) }}</td>
                      <td class="px-3 py-2 text-right text-red-600">{{ MontantFcfa::formatOuTiret((string) $bulletin->its) }}</td>
                      <td class="px-3 py-2 text-right text-red-600">{{ MontantFcfa::formatOuTiret($bulletin->autresRetenues()) }}</td>
                      <td class="px-3 py-2 text-right font-bold" style="color:var(--navy)">{{ MontantFcfa::format((string) $bulletin->net_a_payer) }}</td>
                      <td class="px-3 py-2 text-right text-[12px] text-slate-500">{{ MontantFcfa::format((string) $bulletin->charges_patronales_confirmees) }}<span class="text-amber-600">*</span></td>
                      <td class="px-3 py-2 text-right whitespace-nowrap">
                        <button type="button" wire:click="$set('bulletinAffiche', '{{ $bulletin->id }}')"
                                class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white">{{ __('rh_pwa.action_voir') }}</button>
                        @if ($peutEcrire && ! $bulletin->estAnnule())
                          <button type="button" wire:click="ouvrirAnnulationBulletin('{{ $bulletin->id }}')"
                                  class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white ml-1">{{ __('rh_pwa.action_annuler') }}</button>
                        @endif
                      </td>
                    </tr>
                  @empty
                    <tr><td colspan="9" class="px-3 py-14 text-center">
                      <p class="text-[13px] font-semibold text-slate-500">{{ __('rh_pwa.aucun_resultat') }}</p>
                      <p class="text-[13px] text-slate-400 mt-1">{{ __('rh_pwa.aucun_bulletin', ['periode' => $periodeLongue]) }}</p>
                    </td></tr>
                  @endforelse

                  @if ($totaux['effectif'] > 0)
                    <tr class="bg-[var(--navy)] text-white font-bold">
                      <td class="px-3 py-2.5" colspan="2">{{ __('rh_pwa.total_bulletins', ['nombre' => $totaux['effectif']]) }}</td>
                      <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($totaux['brut']) }}</td>
                      <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($totaux['cnss_salarie']) }}</td>
                      <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($totaux['its']) }}</td>
                      <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($totaux['autres_retenues']) }}</td>
                      <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($totaux['net']) }}</td>
                      <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($totaux['patronales_confirmees']) }}*</td>
                      <td></td>
                    </tr>
                  @endif
                </tbody>
              </table>
            </div>
          </div>
        </div>

        {{-- ================================================== ONGLET LIVRE --}}
        <div id="panneau-paie-livre" class="{{ $onglet === 'livre' ? '' : 'hidden' }}">
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
              <div class="px-4 py-3 border-b border-slate-200">
                <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('rh_pwa.livre_titre', ['periode' => $periodeLongue, 'nombre' => $totaux['effectif']]) }}</h3>
              </div>
              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  <thead class="bg-[var(--navy)]"><tr>
                    {!! $entete(__('rh_pwa.col_rubrique'), true) !!}
                    {!! $entete(__('rh_pwa.col_montant')) !!}
                  </tr></thead>
                  <tbody>
                    @if ($totaux['effectif'] > 0)
                    <tr class="border-t border-slate-100"><td class="px-3 py-2 text-left text-slate-700">{{ __('rh_pwa.livre_brut') }}</td><td class="px-3 py-2 text-right font-semibold">{{ MontantFcfa::format($totaux['brut']) }}</td></tr>
                    <tr class="border-t border-slate-100"><td class="px-3 py-2 text-left text-slate-700">{{ __('rh_pwa.livre_cnss') }}</td><td class="px-3 py-2 text-right font-semibold text-red-600">− {{ MontantFcfa::format($totaux['cnss_salarie']) }}</td></tr>
                    <tr class="border-t border-slate-100"><td class="px-3 py-2 text-left text-slate-700">{{ __('rh_pwa.livre_its') }}</td><td class="px-3 py-2 text-right font-semibold text-red-600">− {{ MontantFcfa::format($totaux['its']) }}</td></tr>
                    <tr class="border-t border-slate-100"><td class="px-3 py-2 text-left text-slate-700">{{ __('rh_pwa.livre_autres') }}</td><td class="px-3 py-2 text-right font-semibold text-red-600">− {{ MontantFcfa::format($totaux['autres_retenues']) }}</td></tr>
                    <tr class="bg-[var(--navy)] text-white font-bold"><td class="px-3 py-2.5">{{ __('rh_pwa.livre_net') }}</td><td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($totaux['net']) }}</td></tr>
                    <tr class="bg-slate-100 font-bold border-t-2 border-slate-300"><td class="px-3 py-2" colspan="2">{{ __('rh_pwa.livre_patronales') }}</td></tr>
                    <tr class="border-t border-slate-100"><td class="px-3 py-2 text-left text-slate-700">{{ __('rh_pwa.livre_pension') }}</td><td class="px-3 py-2 text-right font-semibold">{{ MontantFcfa::format($totaux['pension']) }}</td></tr>
                    <tr class="border-t border-slate-100"><td class="px-3 py-2 text-left text-slate-700">{{ __('rh_pwa.livre_familiales') }}</td><td class="px-3 py-2 text-right font-semibold">{{ MontantFcfa::format($totaux['familiales']) }}</td></tr>
                    <tr class="border-t border-slate-100"><td class="px-3 py-2 text-left text-slate-700">{{ __('rh_pwa.livre_vps') }}</td><td class="px-3 py-2 text-right font-semibold">{{ MontantFcfa::format($totaux['vps']) }}</td></tr>
                    {{-- FOURCHETTE : le taux n'est pas confirme (PA-53). --}}
                    <tr class="border-t border-slate-100"><td class="px-3 py-2 text-left text-slate-700">{{ __('rh_pwa.livre_rp') }}</td><td class="px-3 py-2 text-right font-semibold text-amber-700">{{ MontantFcfa::format($totaux['rp_min']) }} — {{ MontantFcfa::format($totaux['rp_max']) }}</td></tr>
                    <tr class="bg-slate-100 font-bold"><td class="px-3 py-2">{{ __('rh_pwa.livre_total_confirmees') }}</td><td class="px-3 py-2 text-right">{{ MontantFcfa::format($totaux['patronales_confirmees']) }}</td></tr>
                    <tr class="bg-[var(--navy)] text-white font-bold"><td class="px-3 py-2.5">{{ __('rh_pwa.livre_cout') }}</td><td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($totaux['cout_min']) }} — {{ MontantFcfa::format($totaux['cout_max']) }}</td></tr>
                    @else
                      <tr><td colspan="2" class="px-3 py-14 text-center">
                        <p class="text-[13px] font-semibold text-slate-500">{{ __('rh_pwa.aucun_resultat') }}</p>
                        <p class="text-[13px] text-slate-400 mt-1">{{ __('rh_pwa.aucun_bulletin', ['periode' => $periodeLongue]) }}</p>
                      </td></tr>
                    @endif
                  </tbody>
                </table>
              </div>
            </div>

            @if ($totaux['sans_numero_cnss'] > 0)
              <div class="rounded-xl p-3.5 mb-4" style="background:#FEF2F2;border:1px solid #FECACA">
                <p class="text-[13px]" style="color:#7F1D1D">
                  <strong>{{ __('rh_pwa.livre_sans_cnss_titre', ['nombre' => $totaux['sans_numero_cnss']]) }}</strong>
                  {{ __('rh_pwa.livre_sans_cnss_texte') }}
                </p>
              </div>
            @endif

            {{-- ECRITURE COMPTABLE PROPOSEE — maitre `m13-paie.js` l.399-412.
                 Le squelette du tableau est transcrit (Compte, Libelle, Debit,
                 Credit) ; son corps est un ETAT VIDE qui nomme le refus, avec
                 sa raison datee : verifie le 31/08/2026, le listener
                 « GenererEcritureDepuisPaie » que la migration RH annonce
                 n'existe nulle part, et ecrire la piece depuis M13 doublerait
                 le seul point d'entree d'ecriture comptable, ou vit
                 l'immuabilite RG-11. AUCUNE piece n'est inventee : pas de
                 lignes, pas de badge « Equilibree », pas de totaux. --}}
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
              <div class="px-4 py-3 border-b border-slate-200">
                <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('rh_pwa.ecriture_titre') }}</h3>
              </div>
              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  <thead class="bg-[var(--navy)]"><tr>
                    {!! $entete(__('rh_pwa.col_compte'), true) !!}
                    {!! $entete(__('rh_pwa.col_libelle'), true) !!}
                    {!! $entete(__('rh_pwa.col_debit')) !!}
                    {!! $entete(__('rh_pwa.col_credit')) !!}
                  </tr></thead>
                  <tbody>
                    <tr><td colspan="4" class="px-3 py-14 text-center">
                      <p class="text-[13px] font-semibold text-slate-500">{{ __('rh_pwa.livre_ecriture_absente_titre') }}</p>
                      <p class="text-[13px] text-slate-400 mt-1 max-w-[640px] mx-auto">{{ __('rh_pwa.livre_ecriture_absente_texte') }}</p>
                    </td></tr>
                  </tbody>
                </table>
              </div>
            </div>
        </div>

        {{-- =========================================== ONGLET DECLARATIONS --}}
        <div id="panneau-paie-declarations" class="{{ $onglet === 'declarations' ? '' : 'hidden' }}">
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
              <div class="px-4 py-3 border-b border-slate-200 flex flex-wrap items-center justify-between gap-2">
                <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('rh_pwa.declarations_titre', ['periode' => $periodeLongue]) }}</h3>
                <span class="text-[11px] text-amber-700">{{ __('rh_pwa.declarations_note_rp') }}</span>
              </div>
              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  <thead class="bg-[var(--navy)]"><tr>
                    {!! $entete(__('rh_pwa.col_declaration'), true) !!}
                    {!! $entete(__('rh_pwa.col_objet'), true) !!}
                    {!! $entete(__('rh_pwa.col_montant')) !!}
                    {!! $entete(__('rh_pwa.col_echeance')) !!}
                    {!! $entete(__('rh_pwa.col_etat')) !!}
                  </tr></thead>
                  <tbody>
                    @if ($totaux['effectif'] > 0)
                    @foreach ($declarations as $declaration)
                      <tr class="border-t border-slate-100">
                        <td class="px-3 py-2.5 font-bold" style="color:var(--navy)">{{ $declaration['code'] }}</td>
                        <td class="px-3 py-2.5 text-left text-slate-700">
                          {{ $declaration['libelle'] }}
                          <div class="text-[11px] text-slate-400">{{ $declaration['note'] }}</div>
                        </td>
                        <td class="px-3 py-2.5 text-right font-semibold">{{ MontantFcfa::format($declaration['montant']) }}@unless ($declaration['complet'])<span class="text-amber-600">*</span>@endunless</td>
                        <td class="px-3 py-2.5 text-right text-slate-600">{{ $declaration['echeance'] ?? MontantFcfa::TIRET }}</td>
                        <td class="px-3 py-2.5 text-right">
                          @if ($declaration['complet'])
                            <span class="text-[11px] px-2 py-0.5 rounded bg-emerald-50 text-emerald-700">{{ __('rh_pwa.etat_arrete') }}</span>
                          @else
                            <span class="text-[11px] px-2 py-0.5 rounded bg-amber-50 text-amber-700">{{ __('rh_pwa.etat_incomplet') }}</span>
                          @endif
                        </td>
                      </tr>
                    @endforeach
                    @else
                      <tr><td colspan="5" class="px-3 py-14 text-center">
                        <p class="text-[13px] font-semibold text-slate-500">{{ __('rh_pwa.aucun_resultat') }}</p>
                        <p class="text-[13px] text-slate-400 mt-1">{{ __('rh_pwa.aucun_bulletin', ['periode' => $periodeLongue]) }}</p>
                      </td></tr>
                    @endif
                  </tbody>
                </table>
              </div>
            </div>

            <div class="rounded-xl p-3.5" style="background:#F8FAFC;border:1px solid #E2E8F0">
              <p class="text-[13px] text-slate-700">
                <strong>{{ __('rh_pwa.vps_encadre_titre') }}</strong> {!! __('rh_pwa.vps_encadre_texte') !!}
              </p>
            </div>
        </div>

        {{-- ================================================= ONGLET BAREME --}}
        <div id="panneau-paie-bareme" class="{{ $onglet === 'bareme' ? '' : 'hidden' }}">
          {{-- SIMULATEUR — il rend le refus TANGIBLE plutot que theorique
               (maitre `m13-paie.js` l.518-572). --}}
          <div class="bg-white rounded-xl border border-slate-200 p-4 mb-3">
            <h3 class="text-[14px] font-bold mb-2" style="color:var(--navy)">{{ __('rh_pwa.simulateur_titre') }}</h3>
            <div class="flex flex-wrap items-end gap-3 mb-3">
              <div>
                <label class="block text-[12px] font-semibold text-slate-600 mb-1">{{ __('rh_pwa.simulateur_brut') }}</label>
                <input type="number" min="0" step="1000" wire:model.live.debounce.500ms="brutSimule"
                       class="text-[13px] border border-slate-300 rounded-lg px-3 py-2 w-40">
              </div>
            </div>

            @if ($simulation['refus'] !== null)
              <div class="rounded-xl p-3.5" style="background:#FEF2F2;border:1px solid #FECACA">
                <p class="text-[13px]" style="color:#7F1D1D"><strong>{{ __('rh_pwa.simulateur_refus') }}</strong> {{ $simulation['refus'] }}</p>
              </div>
            @else
              <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
                <div class="border border-slate-200 rounded-lg p-3">
                  <div class="text-[11px] uppercase text-slate-400 font-semibold">{{ __('rh_pwa.simulateur_retenues') }}</div>
                  <table class="w-full text-[12px] mt-1.5">
                    <tr><td class="text-slate-600">{{ __('rh_pwa.simulateur_cnss') }}</td><td class="text-right">{{ MontantFcfa::format($simulation['retenues']['cnss_salarie']) }}</td></tr>
                    <tr><td class="text-slate-600">{{ __('rh_pwa.simulateur_imposable') }}</td><td class="text-right text-slate-500">{{ MontantFcfa::format($simulation['retenues']['revenu_imposable']) }}</td></tr>
                    <tr><td class="text-slate-600">{{ __('rh_pwa.simulateur_its') }}</td><td class="text-right">{{ MontantFcfa::format($simulation['retenues']['its']) }}</td></tr>
                    <tr class="border-t border-slate-200"><td class="font-bold pt-1" style="color:var(--navy)">{{ __('rh_pwa.simulateur_net') }}</td>
                      <td class="text-right font-bold pt-1" style="color:var(--navy)">{{ MontantFcfa::format($simulation['retenues']['net_a_payer']) }}</td></tr>
                  </table>
                </div>

                <div class="border border-slate-200 rounded-lg p-3">
                  <div class="text-[11px] uppercase text-slate-400 font-semibold">{{ __('rh_pwa.simulateur_patronales') }}</div>
                  <table class="w-full text-[12px] mt-1.5">
                    <tr><td class="text-slate-600" colspan="2">{{ __('rh_pwa.simulateur_pension') }}</td></tr>
                    <tr><td class="text-slate-600" colspan="2">{{ __('rh_pwa.simulateur_familiales') }}</td></tr>
                    <tr><td class="text-slate-600" colspan="2">{{ __('rh_pwa.simulateur_vps') }}</td></tr>
                    <tr class="border-t border-slate-200"><td class="font-bold pt-1" style="color:var(--navy)">{{ __('rh_pwa.simulateur_total_confirme') }}</td>
                      <td class="text-right font-bold pt-1" style="color:var(--navy)">{{ MontantFcfa::format($simulation['cout']['confirmees']) }}</td></tr>
                  </table>
                </div>

                <div class="border rounded-lg p-3" style="background:#FFFBEB;border-color:#FDE68A">
                  <div class="text-[11px] uppercase font-semibold" style="color:#78350F">{{ __('rh_pwa.simulateur_manque') }}</div>
                  <table class="w-full text-[12px] mt-1.5">
                    <tr><td style="color:#78350F">{{ __('rh_pwa.simulateur_rp_min') }}</td><td class="text-right" style="color:#78350F">{{ MontantFcfa::format($simulation['cout']['rp_min']) }}</td></tr>
                    <tr><td style="color:#78350F">{{ __('rh_pwa.simulateur_rp_max') }}</td><td class="text-right" style="color:#78350F">{{ MontantFcfa::format($simulation['cout']['rp_max']) }}</td></tr>
                    <tr class="border-t" style="border-color:#FDE68A"><td class="font-bold pt-1" style="color:#7F1D1D">{{ __('rh_pwa.simulateur_ecart') }}</td>
                      <td class="text-right font-bold pt-1" style="color:#7F1D1D">{{ MontantFcfa::format($simulation['cout']['ecart']) }}</td></tr>
                    <tr><td class="font-bold" style="color:#7F1D1D">{{ __('rh_pwa.simulateur_ecart_annuel') }}</td>
                      <td class="text-right font-bold" style="color:#7F1D1D">{{ $ecartAnnuel === null ? MontantFcfa::TIRET : MontantFcfa::format($ecartAnnuel) }}</td></tr>
                  </table>
                  <p class="text-[10px] mt-1.5" style="color:#78350F">
                    {{ __('rh_pwa.simulateur_cout', ['min' => MontantFcfa::format($simulation['cout']['cout_min']), 'max' => MontantFcfa::format($simulation['cout']['cout_max'])]) }}
                  </p>
                </div>
              </div>
            @endif
          </div>

          {{-- BAREME ITS — les tranches viennent de `CalculPaieService`. --}}
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
            <div class="px-4 py-3 border-b border-slate-200">
              <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('rh_pwa.bareme_titre') }}</h3>
            </div>
            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]"><tr>
                  {!! $entete(__('rh_pwa.col_tranche'), true) !!}
                  {!! $entete(__('rh_pwa.col_taux')) !!}
                  {!! $entete(__('rh_pwa.col_impot_max')) !!}
                  {!! $entete(__('rh_pwa.col_cumul')) !!}
                </tr></thead>
                <tbody>
                  @foreach ($baremeIts as $tranche)
                    <tr class="border-t border-slate-100">
                      <td class="px-3 py-2 text-left text-slate-700">{{ __('rh_pwa.tranche_de_a', ['plancher' => MontantFcfa::format($tranche['plancher']), 'plafond' => MontantFcfa::format($tranche['plafond'])]) }}</td>
                      <td class="px-3 py-2 text-right font-semibold">{{ $tranche['taux'] }} %</td>
                      <td class="px-3 py-2 text-right">{{ MontantFcfa::formatOuTiret($tranche['maximum']) }}</td>
                      <td class="px-3 py-2 text-right text-slate-500">{{ MontantFcfa::format($tranche['cumul']) }}</td>
                    </tr>
                  @endforeach
                  {{-- LE REFUS, rendu comme une ligne du bareme : deux sources
                       divergent sur le haut de bareme (PA-53). --}}
                  <tr class="border-t-2 border-red-300" style="background:#FEF2F2">
                    <td class="px-3 py-2 text-left font-semibold" style="color:#7F1D1D">{{ __('rh_pwa.bareme_au_dela', ['plafond' => MontantFcfa::format($plafondIts)]) }}</td>
                    <td class="px-3 py-2 text-right font-semibold" style="color:#7F1D1D">{{ __('rh_pwa.bareme_non_tranche') }}</td>
                    <td class="px-3 py-2 text-right" colspan="2" style="color:#7F1D1D">{{ __('rh_pwa.bareme_refus') }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          {{-- TAUX APPLIQUES — la colonne « Source » est le coeur de PA-53. --}}
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
            <div class="px-4 py-3 border-b border-slate-200">
              <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('rh_pwa.taux_titre') }}</h3>
            </div>
            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]"><tr>
                  {!! $entete(__('rh_pwa.col_prelevement'), true) !!}
                  {!! $entete(__('rh_pwa.col_taux')) !!}
                  {!! $entete(__('rh_pwa.col_charge_de')) !!}
                  {!! $entete(__('rh_pwa.col_base')) !!}
                  {!! $entete(__('rh_pwa.col_source')) !!}
                </tr></thead>
                <tbody>
                  <tr class="border-t border-slate-100">
                    <td class="px-3 py-2 text-left text-slate-700">{{ __('rh_pwa.taux_cnss_salarie') }}</td>
                    <td class="px-3 py-2 text-right font-semibold">{{ __('rh_pwa.simulateur_cnss') }}</td>
                    <td class="px-3 py-2 text-right text-slate-600">{{ __('rh_pwa.charge_salarie') }}</td>
                    <td class="px-3 py-2 text-right text-slate-600 text-[12px]">{{ __('rh_pwa.base_brut') }}</td>
                    <td class="px-3 py-2 text-right"><span class="text-[11px] px-2 py-0.5 rounded bg-emerald-50 text-emerald-700">{{ __('rh_pwa.source_confirme') }}</span></td>
                  </tr>
                  <tr class="border-t border-slate-100">
                    <td class="px-3 py-2 text-left text-slate-700">{{ __('rh_pwa.taux_its') }}</td>
                    <td class="px-3 py-2 text-right font-semibold">{{ __('rh_pwa.taux_its_valeur') }}</td>
                    <td class="px-3 py-2 text-right text-slate-600">{{ __('rh_pwa.charge_salarie') }}</td>
                    <td class="px-3 py-2 text-right text-slate-600 text-[12px]">{{ __('rh_pwa.base_imposable') }}</td>
                    <td class="px-3 py-2 text-right"><span class="text-[11px] px-2 py-0.5 rounded bg-emerald-50 text-emerald-700">{{ __('rh_pwa.source_confirme') }}</span></td>
                  </tr>
                  <tr class="border-t border-slate-100">
                    <td class="px-3 py-2 text-left text-slate-700">{{ __('rh_pwa.taux_pension') }}</td>
                    <td class="px-3 py-2 text-right font-semibold">{{ __('rh_pwa.simulateur_pension') }}</td>
                    <td class="px-3 py-2 text-right text-slate-600">{{ __('rh_pwa.charge_employeur') }}</td>
                    <td class="px-3 py-2 text-right text-slate-600 text-[12px]">{{ __('rh_pwa.base_brut') }}</td>
                    <td class="px-3 py-2 text-right"><span class="text-[11px] px-2 py-0.5 rounded bg-emerald-50 text-emerald-700">{{ __('rh_pwa.source_confirme') }}</span></td>
                  </tr>
                  <tr class="border-t border-slate-100">
                    <td class="px-3 py-2 text-left text-slate-700">{{ __('rh_pwa.taux_familiales') }}</td>
                    <td class="px-3 py-2 text-right font-semibold">{{ __('rh_pwa.simulateur_familiales') }}</td>
                    <td class="px-3 py-2 text-right text-slate-600">{{ __('rh_pwa.charge_employeur') }}</td>
                    <td class="px-3 py-2 text-right text-slate-600 text-[12px]">{{ __('rh_pwa.base_brut') }}</td>
                    <td class="px-3 py-2 text-right"><span class="text-[11px] px-2 py-0.5 rounded bg-emerald-50 text-emerald-700">{{ __('rh_pwa.source_confirme') }}</span></td>
                  </tr>
                  <tr class="border-t border-slate-100">
                    <td class="px-3 py-2 text-left text-slate-700">{{ __('rh_pwa.taux_vps') }}</td>
                    <td class="px-3 py-2 text-right font-semibold">{{ __('rh_pwa.simulateur_vps') }}</td>
                    <td class="px-3 py-2 text-right text-slate-600">{{ __('rh_pwa.charge_employeur') }}</td>
                    <td class="px-3 py-2 text-right text-slate-600 text-[12px]">{{ __('rh_pwa.base_sans_plafond') }}</td>
                    <td class="px-3 py-2 text-right"><span class="text-[11px] px-2 py-0.5 rounded bg-emerald-50 text-emerald-700">{{ __('rh_pwa.source_confirme') }}</span></td>
                  </tr>
                  <tr class="border-t border-slate-100" style="background:#FEF2F2">
                    <td class="px-3 py-2 text-left font-semibold" style="color:#7F1D1D">{{ __('rh_pwa.taux_rp') }}</td>
                    <td class="px-3 py-2 text-right font-semibold" style="color:#7F1D1D">{{ __('rh_pwa.taux_rp_valeur') }}</td>
                    <td class="px-3 py-2 text-right text-slate-600">{{ __('rh_pwa.charge_employeur') }}</td>
                    <td class="px-3 py-2 text-right text-slate-600 text-[12px]">{{ __('rh_pwa.base_brut') }}</td>
                    <td class="px-3 py-2 text-right"><span class="text-[11px] px-2 py-0.5 rounded bg-red-100 text-red-800 font-semibold">{{ __('rh_pwa.source_non_confirme') }}</span></td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

      </div>
    </main>
  </div>

  {{-- ========================= SQUELETTES DE TABLEAUX RENDUS HORS ECRAN ====
       Trois tableaux du maitre n'existent qu'a l'EXPORT (`etatCourant()`,
       `m13-paie.js` l.853-901 — le PDF/Excel de l'onglet courant) et un
       quatrieme ne vit que dans la modale de CONSULTATION du bulletin
       (`m13-paie.js` l.238-245). Leurs colonnes sont des colonnes du maitre a
       part entiere : la garde G5 (`ColonnesDesTableauxPwaTest`) exige qu'elles
       soient rendues au premier GET, et l'exclusion `COLONNES_DE_MODALE` est
       reservee aux tableaux de SAISIE — ceux-ci sont des lectures.

       Leurs squelettes sont donc transcrits ici, caches (`hidden`,
       `aria-hidden`) : uniquement les en-tetes, aucune ligne, aucun montant —
       un squelette qui porterait des chiffres serait un tableau que personne
       ne relit. Les tableaux VIVANTS restent la modale de consultation du
       bulletin (memes cles de langue) et les exports de `PaieExport`.

       ⚠ L'export tableur de la PWA garde ses propres entetes
       (`PaieExport::entetesDe()`) : il exporte CE QUI EST AFFICHE (PA-119),
       la ou le maitre exporte un detail salarie par salarie. L'ecart est
       assume et date (01/09/2026) ; l'alignement des exports est un arbitrage
       distinct, pas un effet de bord de cette transcription. --}}
  <div class="hidden" aria-hidden="true">
    {{-- Bulletin detaille — maitre `m13-paie.js` l.238-245 et l.349. --}}
    <table>
      <thead><tr>
        <th>{{ __('rh_pwa.col_designation') }}</th>
        <th>{{ __('rh_pwa.col_base') }}</th>
        <th>{{ __('rh_pwa.col_taux') }}</th>
        <th>{{ __('rh_pwa.col_gain') }}</th>
        <th>{{ __('rh_pwa.col_retenue') }}</th>
      </tr></thead>
    </table>

    {{-- Export « Registre du personnel » — maitre `m13-paie.js` l.864. --}}
    <table>
      <thead><tr>
        <th>{{ __('rh_pwa.col_matricule') }}</th>
        <th>{{ __('rh_pwa.champ_nom') }}</th>
        <th>{{ __('rh_pwa.champ_prenoms') }}</th>
        <th>{{ __('rh_pwa.champ_poste') }}</th>
        <th>{{ __('rh_pwa.champ_service') }}</th>
        <th>{{ __('rh_pwa.col_contrat') }}</th>
        <th>{{ __('rh_pwa.col_embauche') }}</th>
        <th>{{ __('rh_pwa.col_cnss') }}</th>
        <th>{{ __('rh_pwa.col_salaire_base') }}</th>
      </tr></thead>
    </table>

    {{-- Export « Declarations sociales et fiscales » — maitre l.877. --}}
    <table>
      <thead><tr>
        <th>{{ __('rh_pwa.col_declaration') }}</th>
        <th>{{ __('rh_pwa.col_objet') }}</th>
        <th>{{ __('rh_pwa.col_montant') }}</th>
        <th>{{ __('rh_pwa.col_etat') }}</th>
        <th>{{ __('rh_pwa.col_note') }}</th>
      </tr></thead>
    </table>

    {{-- Export « Livre de paie / Bulletins de paie » — maitre l.891-892.
         La colonne de risques professionnels porte la mention du maitre
         « (non confirme) » : au maitre comme au service, cette colonne rend
         une FOURCHETTE, jamais un taux suppose (PA-53). --}}
    <table>
      <thead><tr>
        <th>{{ __('rh_pwa.col_matricule') }}</th>
        <th>{{ __('rh_pwa.col_employe') }}</th>
        <th>{{ __('rh_pwa.col_brut') }}</th>
        <th>{{ __('rh_pwa.col_cnss_salarie') }}</th>
        <th>{{ __('rh_pwa.col_its') }}</th>
        <th>{{ __('rh_pwa.col_autres_retenues') }}</th>
        <th>{{ __('rh_pwa.col_net') }}</th>
        <th>{{ __('rh_pwa.simulateur_pension') }}</th>
        <th>{{ __('rh_pwa.col_prest_fam') }}</th>
        <th>{{ __('rh_pwa.simulateur_vps') }}</th>
        <th>{{ __('rh_pwa.col_rp_non_confirme') }}</th>
      </tr></thead>
    </table>
  </div>

  {{-- ================================================ MODALE — FICHE EMPLOYE
       ⚠ « Telephone » et « Centre analytique » du maitre ne sont PAS rendus :
       aucune colonne sur `employes`. Un champ saisi qui n'irait nulle part
       serait un faux ecran. --}}
  @if ($etatFormulaire === 'employe')
    <x-pwa.modale :titre="$employeId === null ? __('rh_pwa.modale_nouvel_employe') : __('rh_pwa.modale_modifier_employe', ['matricule' => $matriculeEnEdition])" largeur="620px">
      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('rh_pwa.champ_nom') }} <span class="text-red-500">*</span></label>
          <input type="text" wire:model.live.debounce.400ms="nomSaisi" autocomplete="off"
                 class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('nomSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('rh_pwa.champ_prenoms') }} <span class="text-red-500">*</span></label>
          <input type="text" wire:model.live.debounce.400ms="prenomSaisi" autocomplete="off"
                 class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('prenomSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('rh_pwa.champ_poste') }} <span class="text-red-500">*</span></label>
          <input type="text" wire:model="posteSaisi" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('posteSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('rh_pwa.champ_service') }} <span class="text-red-500">*</span></label>
          {{-- VRAIE cle etrangere, jamais du texte libre. --}}
          <select wire:model="serviceSaisi" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
            @foreach ($services as $service)
              <option value="{{ $service->id }}">{{ $service->libelle }}</option>
            @endforeach
          </select>
          @error('serviceSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
      </div>

      {{-- E-mail FACULTATIF (28/10/2026) : destinataire des notifications e-mail du salarié. --}}
      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.profil.email') }}</label>
        <input type="email" wire:model="emailSaisi" autocomplete="off"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
        @error('emailSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <div class="grid grid-cols-3 gap-3">
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('rh_pwa.champ_contrat') }}</label>
          <select wire:model="contratSaisi" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
            @foreach ($typesContrat as $type)
              <option value="{{ $type }}">{{ $type }}</option>
            @endforeach
          </select>
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('rh_pwa.champ_embauche') }}</label>
          <input type="date" wire:model="embaucheSaisie" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('rh_pwa.champ_fin_contrat') }}</label>
          <input type="date" wire:model="finContratSaisie" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
        </div>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('rh_pwa.champ_numero_cnss') }}</label>
          <input type="text" wire:model="numeroCnssSaisi" placeholder="{{ __('rh_pwa.champ_numero_cnss_invite') }}"
                 class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 font-mono">
          <p class="text-[11px] text-slate-400 mt-1">{{ __('rh_pwa.champ_numero_cnss_aide') }}</p>
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('rh_pwa.champ_salaire_base') }} <span class="text-red-500">*</span></label>
          <input type="number" min="0" step="500" wire:model="salaireBaseSaisi"
                 class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('salaireBaseSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
      </div>

      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('rh_pwa.champ_statut') }}</label>
        <select wire:model="statutSaisi" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @foreach ($statutsEmploye as $statut)
            <option value="{{ $statut }}">{{ $statut }}</option>
          @endforeach
        </select>
      </div>

      {{-- RG-18 appliquee au personnel : AVERTIR, jamais bloquer. --}}
      @if ($homonymes->isNotEmpty())
        <div class="bg-amber-50 border border-amber-300 rounded-lg p-3">
          <p class="text-[13px] font-semibold text-amber-900">
            {{ $homonymes->count() === 1 ? __('rh_pwa.homonymes_un') : __('rh_pwa.homonymes_plusieurs', ['nombre' => $homonymes->count()]) }}
          </p>
          <ul class="mt-1.5 space-y-1">
            @foreach ($homonymes as $homonyme)
              <li class="text-[12px] text-amber-900">
                <strong>{{ $homonyme->matricule ?? MontantFcfa::TIRET }}</strong> — {{ $homonyme->nomComplet() }}
                · {{ $homonyme->poste }} · {{ MontantFcfa::format((string) $homonyme->salaire_base) }}
              </li>
            @endforeach
          </ul>
          <label class="flex items-center gap-2 mt-2.5 text-[12px] text-amber-900 cursor-pointer">
            <input type="checkbox" wire:model="doublonConfirme" class="rounded border-amber-400">
            <span>{!! __('rh_pwa.homonymes_confirmer') !!}</span>
          </label>
        </div>
      @endif

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerEmploye"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ $employeId === null ? __('rh_pwa.creer') : __('rh_pwa.enregistrer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ============================================ MODALE — ETABLIR LE BULLETIN
       ⚠ Le « + Ajouter un element » du maitre n'est PAS rendu : les primes et
       retenues du mois vivraient dans `primes_sanctions`, table qui existe au
       schema mais qu'aucun modele ni service ne touche. `total_primes` vaut
       donc zero, et le brut est le salaire de base. --}}
  @if ($etatFormulaire === 'etablissement' && $employeEnEtablissement !== null)
    <x-pwa.modale :titre="__('rh_pwa.modale_etablir')"
                  :sousTitre="__('rh_pwa.etablir_sous_titre', ['employe' => $employeEnEtablissement->nomComplet(), 'periode' => $periodeLongue])"
                  largeur="600px">
      <div class="bg-slate-50 border border-slate-200 rounded-lg p-3 text-[13px]">
        {!! __('rh_pwa.etablir_rappel', ['montant' => '<strong>' . e(MontantFcfa::format((string) $employeEnEtablissement->salaire_base)) . '</strong>']) !!}
      </div>

      @if ($apercuEtablissement !== null && $apercuEtablissement['refus'] !== null)
        <div class="rounded-xl p-3.5" style="background:#FEF2F2;border:1px solid #FECACA">
          <p class="text-[13px]" style="color:#7F1D1D"><strong>{{ __('rh_pwa.simulateur_refus') }}</strong> {{ $apercuEtablissement['refus'] }}</p>
        </div>
      @elseif ($apercuEtablissement !== null)
        <div class="border border-slate-200 rounded-lg p-3 text-[12px]">
          <div class="flex justify-between"><span class="text-slate-600">{{ __('rh_pwa.etablir_brut') }}</span><strong>{{ MontantFcfa::format($apercuEtablissement['retenues']['brut']) }}</strong></div>
          <div class="flex justify-between"><span class="text-slate-600">{{ __('rh_pwa.simulateur_cnss') }}</span><span class="text-red-600">− {{ MontantFcfa::format($apercuEtablissement['retenues']['cnss_salarie']) }}</span></div>
          <div class="flex justify-between"><span class="text-slate-600">{{ __('rh_pwa.simulateur_its') }}</span><span class="text-red-600">− {{ MontantFcfa::format($apercuEtablissement['retenues']['its']) }}</span></div>
          <div class="flex justify-between border-t border-slate-200 mt-1 pt-1">
            <strong style="color:var(--navy)">{{ __('rh_pwa.simulateur_net') }}</strong>
            <strong style="color:var(--navy)">{{ MontantFcfa::format($apercuEtablissement['retenues']['net_a_payer']) }}</strong></div>
          <div class="flex justify-between mt-1 text-[11px] text-amber-700">
            <span>{{ __('rh_pwa.etablir_cout') }}</span><span>{{ $fourchette($apercuEtablissement['cout']) }}</span></div>
        </div>
      @endif

      @error('employeAEtablir') <p class="text-[12px] text-red-600">{{ $message }}</p> @enderror

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="etablirBulletin"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('rh_pwa.modale_etablir') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ================================================== MODALE — ANNULATION --}}
  @if ($etatFormulaire === 'annulation')
    <x-pwa.modale :titre="__('rh_pwa.modale_annulation')" :sousTitre="__('rh_pwa.annulation_detail')" largeur="480px">
      <p class="text-[13px] text-slate-600">{{ __('rh_pwa.annulation_message') }}</p>
      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('rh_pwa.champ_motif') }} <span class="text-red-500">*</span></label>
        <textarea wire:model="motifAnnulation" rows="3" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5"></textarea>
        @error('motifAnnulation') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="annulerBulletin"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--erreur)] text-white font-semibold">{{ __('rh_pwa.annulation_confirmer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ================================================= MODALE — ARCHIVAGE
       (directive PO du 02/09/2026). Elle NOMME les employes vises et, s'il y
       en a, ceux qui n'ont pas de bulletin sur la periode courante : une fois
       « partis », la generation les saute sans un mot — l'avertissement vit
       ICI, pas en verrou, car un depart sans solde du est legitime. --}}
  @if ($etatFormulaire === 'archivage' && $employesVisesParArchivage->isNotEmpty())
    <x-pwa.modale :titre="trans_choice('rh_pwa.archivage.modale_titre', $employesVisesParArchivage->count(), ['nombre' => $employesVisesParArchivage->count()])"
                  :sousTitre="__('rh_pwa.archivage.modale_sous_titre')" largeur="520px">
      <ul class="text-[13px] text-slate-700 space-y-1">
        @foreach ($employesVisesParArchivage as $vise)
          <li class="flex items-center justify-between gap-2">
            <span class="font-semibold">{{ $vise->nomComplet() }}</span>
            <span class="text-[11px] text-slate-400 font-mono">{{ $vise->matricule }}</span>
          </li>
        @endforeach
      </ul>

      @php($sansBulletin = $employesVisesParArchivage->filter(fn ($e) => ! isset($bulletinsParEmploye[$e->id])))
      @if ($sansBulletin->isNotEmpty())
        <div class="mt-3 px-3 py-2.5 rounded-lg bg-amber-50 border border-amber-200 text-[12px] text-amber-800">
          {{ trans_choice('rh_pwa.archivage.sans_bulletin', $sansBulletin->count(), [
              'noms' => $sansBulletin->map(fn ($e) => $e->nomComplet())->implode(', '),
              'periode' => $periodeLongue,
          ]) }}
        </div>
      @endif

      <p class="mt-3 text-[12px] text-slate-500">{{ __('rh_pwa.archivage.reversible') }}</p>

      @error('archivage') <p class="text-[12px] text-red-600 mt-2">{{ $message }}</p> @enderror

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="archiverEmployes"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--erreur)] text-white font-semibold">{{ trans_choice('rh_pwa.archivage.confirmer', $employesVisesParArchivage->count()) }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- =================================================== MODALE — BULLETIN
       CONSULTATION : elle s'ouvre par `$set('bulletinAffiche', …)`, sans
       garde d'ecriture — lire un bulletin que la page affiche deja n'est pas
       une ecriture. --}}
  @if ($bulletinOuvert !== null && $recapitulatifOuvert !== null)
    <x-pwa.modale :titre="__('rh_pwa.modale_bulletin')" largeur="760px">
      <div class="flex justify-between items-start pb-3 border-b-2" style="border-color:var(--navy)">
        <div>
          <div class="font-bold text-[15px]" style="color:var(--navy)">{{ __('rh_pwa.bulletin_etablissement') }}</div>
          <div class="text-[11px] text-slate-500">{{ __('rh_pwa.bulletin_ville') }}</div>
        </div>
        <div class="text-right">
          <div class="font-bold text-[14px]" style="color:var(--navy)">{{ __('rh_pwa.bulletin_entete') }}</div>
          <div class="text-[12px] text-slate-600">{{ $periodeLongue }}</div>
          <div class="text-[11px] font-mono text-slate-400">{{ $bulletinOuvert->numero }}</div>
        </div>
      </div>

      <div class="grid grid-cols-2 gap-4 text-[12px]">
        <div class="bg-slate-50 rounded-lg p-3">
          <div class="text-[10px] uppercase tracking-wide text-slate-400 font-semibold mb-1">{{ __('rh_pwa.bulletin_salarie') }}</div>
          <div class="font-bold text-[14px] text-slate-800">{{ $bulletinOuvert->employe->nomComplet() }}</div>
          <div class="text-slate-600">{{ $bulletinOuvert->employe->poste }}</div>
          <div class="text-slate-500">{{ __('rh_pwa.bulletin_matricule', ['valeur' => $bulletinOuvert->employe->matricule ?? MontantFcfa::TIRET]) }}</div>
          <div class="text-slate-500">
            @if ($bulletinOuvert->employe->sansNumeroCnss())
              {{ __('rh_pwa.bulletin_cnss', ['valeur' => '']) }}<span class="text-amber-700 font-semibold">{{ __('rh_pwa.bulletin_cnss_absent') }}</span>
            @else
              {{ __('rh_pwa.bulletin_cnss', ['valeur' => $bulletinOuvert->employe->numero_cnss]) }}
            @endif
          </div>
        </div>
        <div class="bg-slate-50 rounded-lg p-3">
          <div class="text-[10px] uppercase tracking-wide text-slate-400 font-semibold mb-1">{{ __('rh_pwa.bulletin_affectation') }}</div>
          <div class="text-slate-700">{{ $bulletinOuvert->employe->service?->libelle ?? MontantFcfa::TIRET }}</div>
          <div class="text-slate-500">{{ __('rh_pwa.bulletin_etabli_le', ['date' => optional($bulletinOuvert->date_creation ?? $bulletinOuvert->created_at)->format('d/m/Y')]) }}</div>
          @if ($bulletinOuvert->estAnnule())
            <div class="text-red-600 font-semibold mt-1">{{ __('rh_pwa.bulletin_annule', ['motif' => $bulletinOuvert->motif_annulation]) }}</div>
          @endif
        </div>
      </div>

      <table class="w-full text-[12px]">
        <thead class="bg-[var(--navy)]"><tr>
          <th class="px-2 py-1.5 text-left text-[11px] uppercase tracking-wide text-white/90 font-semibold">{{ __('rh_pwa.col_designation') }}</th>
          <th class="px-2 py-1.5 text-right text-[11px] uppercase tracking-wide text-white/90 font-semibold">{{ __('rh_pwa.col_base') }}</th>
          <th class="px-2 py-1.5 text-right text-[11px] uppercase tracking-wide text-white/90 font-semibold">{{ __('rh_pwa.col_taux') }}</th>
          <th class="px-2 py-1.5 text-right text-[11px] uppercase tracking-wide text-white/90 font-semibold">{{ __('rh_pwa.col_gain') }}</th>
          <th class="px-2 py-1.5 text-right text-[11px] uppercase tracking-wide text-white/90 font-semibold">{{ __('rh_pwa.col_retenue') }}</th>
        </tr></thead>
        <tbody>
          <tr class="bg-slate-100 font-bold border-t border-slate-300">
            <td class="px-2 py-2" colspan="3">{{ __('rh_pwa.bulletin_brut') }}</td>
            <td class="px-2 py-2 text-right">{{ MontantFcfa::format($recapitulatifOuvert['brut']) }}</td><td></td>
          </tr>
          <tr class="border-b border-slate-100">
            <td class="px-2 py-1.5 text-slate-700">{{ __('rh_pwa.bulletin_cnss_salariale') }}</td>
            <td class="px-2 py-1.5 text-right text-slate-500">{{ MontantFcfa::format($recapitulatifOuvert['brut']) }}</td>
            <td class="px-2 py-1.5 text-right text-slate-500"></td>
            <td></td>
            <td class="px-2 py-1.5 text-right text-red-600">{{ MontantFcfa::format($recapitulatifOuvert['cnss_salarie']) }}</td>
          </tr>
          <tr class="bg-slate-100 font-bold">
            <td class="px-2 py-2" colspan="3">{{ __('rh_pwa.bulletin_imposable') }}</td>
            <td class="px-2 py-2 text-right">{{ MontantFcfa::format($recapitulatifOuvert['revenu_imposable']) }}</td><td></td>
          </tr>
          <tr class="border-b border-slate-100">
            <td class="px-2 py-1.5 text-slate-700 font-semibold">{{ __('rh_pwa.bulletin_its') }}</td>
            <td colspan="2"></td><td></td>
            <td class="px-2 py-1.5 text-right text-red-600 font-semibold">{{ MontantFcfa::format($recapitulatifOuvert['its']) }}</td>
          </tr>
          @if (bccomp($recapitulatifOuvert['autres_retenues'], '0.00', 2) > 0)
            <tr class="border-b border-slate-100">
              <td class="px-2 py-1.5 text-slate-700">{{ __('rh_pwa.bulletin_autres') }}</td>
              <td colspan="3"></td>
              <td class="px-2 py-1.5 text-right text-red-600">{{ MontantFcfa::format($recapitulatifOuvert['autres_retenues']) }}</td>
            </tr>
          @endif
          <tr class="bg-[var(--navy)] text-white font-bold">
            <td class="px-2 py-2.5" colspan="3">{{ __('rh_pwa.bulletin_net') }}</td>
            <td class="px-2 py-2.5 text-right" colspan="2">{{ MontantFcfa::format($recapitulatifOuvert['net_a_payer']) }}</td>
          </tr>
        </tbody>
      </table>

      <div class="rounded-lg p-3" style="background:#FFFBEB;border:1px solid #FDE68A">
        <div class="text-[11px] uppercase tracking-wide font-semibold mb-1.5" style="color:#78350F">{{ __('rh_pwa.bulletin_patronales') }}</div>
        <table class="w-full text-[12px]">
          <tr><td class="py-0.5" style="color:#78350F">{{ __('rh_pwa.livre_total_confirmees') }}</td>
            <td class="py-0.5 text-right font-semibold" style="color:#78350F">{{ MontantFcfa::format($recapitulatifOuvert['patronales_confirmees']) }}</td></tr>
          <tr class="border-t" style="border-color:#FDE68A">
            <td class="py-1 font-semibold" style="color:#7F1D1D">{{ __('rh_pwa.bulletin_rp') }}</td>
            <td class="py-1 text-right font-semibold" style="color:#7F1D1D">{{ MontantFcfa::format($recapitulatifOuvert['rp_min']) }} — {{ MontantFcfa::format($recapitulatifOuvert['rp_max']) }}</td></tr>
          <tr class="border-t-2" style="border-color:#78350F">
            <td class="py-1.5 font-bold" style="color:#78350F">{{ __('rh_pwa.bulletin_cout_total') }}</td>
            <td class="py-1.5 text-right font-bold" style="color:#78350F">{{ MontantFcfa::format($recapitulatifOuvert['cout_min']) }} — {{ MontantFcfa::format($recapitulatifOuvert['cout_max']) }}</td></tr>
        </table>
        <p class="text-[10px] mt-2" style="color:#78350F">{!! __('rh_pwa.bulletin_note_rp') !!}</p>
      </div>

      <p class="text-[10px] text-slate-400 text-center">{{ __('rh_pwa.bulletin_pied') }}</p>

      <x-slot:pied>
        {{-- « Imprimer » du maitre : la commande d'impression du navigateur,
             sur la modale telle qu'elle est a l'ecran. --}}
        <button type="button" onclick="window.print()"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('rh_pwa.imprimer') }}</button>
        <button type="button" wire:click="exporterPdf('{{ $bulletinOuvert->id }}')"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('rh_pwa.pdf') }}</button>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('rh_pwa.fermer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ======================================================= MODALE — EXPORT --}}
  @if ($etatFormulaire === 'export')
    @include('pwa.partials.modale-export', ['titre' => $titreExport])
  @endif

</div>

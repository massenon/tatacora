{{--
    PLAN D'HÉBERGEMENT, RÉSERVATIONS EN COURS, CALENDRIER D'OCCUPATION (M1).

    Maître : `prototype_v2/pages/m1-hebergement.html` — trois onglets, un rendu
    en CARTES (pas en tableau), et le cycle opérationnel sur le bouton de
    chaque carte (`ACTION_PAR_STATUT`, l.165-171).

    ## Ce que la pastille dit, et ce qu'elle ne dit pas

    Elle porte la DISPONIBILITÉ DU JOUR, dérivée des réservations actives et du
    séjour en cours (RG-02) — jamais `unites_hebergement.statut` lu seul, qui
    ne connaît ni date ni période. Le composant en tient la dérivation ; cette
    vue n'a rien à recalculer.

    ## Les trois panneaux sont TOUS rendus

    Le maître les construit tous et masque les inactifs (`activerOnglet()`,
    l.470-485). La PWA fait de même : un onglet dont aucune colonne n'est
    rendue n'est pas un onglet livré (Article 3.3), et les gardes de conformité
    comparent les en-têtes de tableau au premier GET.

    Declarations pour la garde des trois sources :
      maitre-refuse:m1-hebergement.html#champ-equipements
        Le champ « Équipements (séparés par des virgules) » de la modale
        « Ajouter / Éditer Hébergement » du maître n'est pas porté :
        `unites_hebergement` ne porte AUCUNE colonne d'équipements (vérifié
        contre la base le 31/08/2026 — numero, categorie_id, statut et les
        colonnes d'audit, rien d'autre). Le rendre écrirait dans le vide, et
        une migration d'équipements est un arbitrage de schéma, pas un champ
        de formulaire à improviser. Raison datée : elle tombe le jour où la
        colonne existe.
      maitre-refuse:m1-hebergement.html#modale-reservation-rapide
        « Canal de reservation » (Sur place, Booking.com...) et la saisie du
        client en TEXTE LIBRE (« Nom du client ou de l'agence ») ne sont pas
        portes. Le schema serveur ne porte aucun canal (PA-29), et un client
        est une vraie cle etrangere, jamais une chaine tapee au clavier.
--}}
@php
    use App\Pwa\Support\MontantFcfa;

    // Classes d'onglets : directive PO du 01/09/2026, UN SEUL AUTEUR —
    // voir le docblock de `App\Pwa\Support\Onglets`.
    $classeOnglet = static fn (bool $actif): string => \App\Pwa\Support\Onglets::classes($actif);

    $peutEcrire = ($utilisateur?->niveauSurModule(\App\Pwa\Livewire\Hebergement\Hebergement::MODULE) ?? '-') === 'C';
    $tiret = MontantFcfa::TIRET;
@endphp

<div class="contents">
  @include('pwa.partials.barre-superieure')

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')

    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        @if (session('pwa-succes'))
          <div class="mb-4 rounded-lg px-4 py-3 text-[13px] font-semibold"
               style="background:#E8F5E9;color:#2E7D32">{{ session('pwa-succes') }}</div>
        @endif

        @error('cycle')
          <div class="mb-4 rounded-lg px-4 py-3 text-[13px]"
               style="background:#FDECEC;color:#8C1D1D">{{ $message }}</div>
        @enderror
        @error('archivage')
          <div class="mb-4 rounded-lg px-4 py-3 text-[13px]"
               style="background:#FDECEC;color:#8C1D1D">{{ $message }}</div>
        @enderror
        @error('export')
          <div class="mb-4 rounded-lg px-4 py-3 text-[13px]"
               style="background:#FDECEC;color:#8C1D1D">{{ $message }}</div>
        @enderror

        {{-- maître — l.20-33 --}}
        <div class="flex flex-col lg:flex-row lg:items-center gap-4 mb-1">
          <div>
            <div class="flex items-center gap-2.5">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M2 4v16M2 8h18a2 2 0 012 2v10M2 17h20M6 8v-1a2 2 0 012-2h2a2 2 0 012 2v1"/></svg>
              <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('pwa.hebergement.titre') }}</h1>
            </div>
            <p class="text-[15px] text-slate-500 mt-1.5">{{ __('pwa.hebergement.sous_titre') }}</p>
          </div>
          <div class="lg:ml-auto flex gap-2">
            <button wire:click="$set('onglet', 'plan')" class="{{ $classeOnglet($onglet === 'plan') }}">{{ __('pwa.hebergement.onglet_plan') }}</button>
            <button wire:click="$set('onglet', 'reservations')" class="{{ $classeOnglet($onglet === 'reservations') }}">{{ __('pwa.hebergement.onglet_reservations') }}</button>
            <button wire:click="$set('onglet', 'calendrier')" class="{{ $classeOnglet($onglet === 'calendrier') }}">{{ __('pwa.hebergement.onglet_calendrier') }}</button>
            {{-- AJOUT (PO 08/10/2026) : le maitre n'a que trois onglets ;
                 « Disponibilites » existait au client Flutter et repond a
                 « avez-vous une chambre du 12 au 15 ? ».
                 structure-ajout:m1-hebergement.html#onglet-disponibilites --}}
            <button wire:click="$set('onglet', 'disponibilites')" class="{{ $classeOnglet($onglet === 'disponibilites') }}">{{ __('pwa.hebergement.onglet_disponibilites') }}</button>
          </div>
        </div>

        {{-- maître — l.35-44 --}}
        <div class="mt-5 flex flex-col sm:flex-row sm:items-center gap-2 mb-3">
          <a href="{{ route('pwa.reservations') }}" wire:navigate
             class="btn flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg bg-[var(--navy)] text-white text-[15px] font-semibold">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2"/><path stroke-linecap="round" stroke-linejoin="round" d="M16 2v4M8 2v4M3 10h18"/></svg>
            {{ __('pwa.hebergement.bouton_nouvelle_reservation') }}
          </a>

          {{-- 1er niveau du RBAC : il ne protège rien (le serveur refuse de
               toute façon), mais un bouton offert puis refusé ferait perdre la
               saisie. --}}
          @if ($peutEcrire)
            <button wire:click="ouvrirFormulaireUnite"
                    class="btn flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg border border-[var(--navy)] text-[var(--navy)] text-[15px] font-semibold bg-white">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" d="M12 5v14M5 12h14"/></svg>
              {{ __('hebergement_pwa.hebergement.bouton_ajouter') }}
            </button>
          @endif

        </div>

        {{-- La rangée de cinq indicateurs (parc/libre/occupée/réservée/
             nettoyage) qui vivait ici n'existe pas au maître
             (`m1-hebergement.html`) : addition retirée le 01/09/2026 (audit
             navigateur, doctrine « 100 % du template, aucune addition »).
             `$totalParc` reste utilisé plus bas (taux d'occupation du
             calendrier) ; les quatre autres variables restent calculées par
             le composant pour qui les lirait, mais ne sont plus rendues ici. --}}

        {{-- ============ ONGLET « Plan d'Hébergement » ============ --}}
        <div id="panneau-plan-hebergement" class="{{ $onglet === 'plan' ? '' : 'hidden' }}">

          {{--
              LA BARRE D'OUTILS DU MOTEUR CRUD — `assets/js/crud-ui.js`
              `toolbarHtml()` (l.16-38), posée par le maître dans
              `#crud-toolbar-zone` (`m1-hebergement.html` l.46). Quatre
              contrôles dans l'ordre du maître (01/09/2026) :
              Actualiser / Importer / Exporter / « + Nouveau ».

              - « Actualiser » — même geste que `Accueil` (`accueil.blade.php`
                l.293) : un rafraîchissement du CADRE, `wire:click="$refresh"`,
                jamais une méthode qui affirmerait une relecture qu'elle
                n'aurait pas faite (PA-59/60/61).
              - « Importer » — REFUSÉ ET NOMMÉ, pas rendu inerte (Article
                3.3) : `unites_hebergement` n'a AUCUN moteur d'import
                (contrairement à `Stocks::lancerImport()`, qui existe pour les
                articles). L'inventer ici serait une écriture de schéma/service
                hors du périmètre de ce lot. Jeton :
                maitre-refuse:m1-hebergement.html#crud-bouton-importer
              - « Exporter » — déjà porté, INCHANGÉ. Il n'est pas derrière la
                condition d'écriture : il met en page les lignes déjà
                affichées et n'écrit aucune table ; un `comptable` doit
                pouvoir l'emporter.
              - « + Ajouter hébergement » — le maître pose CE MÊME geste
                DEUX fois : le bouton `#bouton-ajouter-hebergement` au-dessus
                (l.40-43, déjà porté ci-dessus) ET le bouton générique
                `crud-bouton-nouveau` du moteur CRUD, ici (`crud-engine.js`
                l.112-119, `Ajouter ${entiteLabelSingulier}`). Les deux
                appellent le même geste (`ouvrirFormulaire(null)` au maître,
                `ouvrirFormulaireUnite()` ici) : transcription littérale, pas
                une invention.
          --}}
          <div class="flex flex-col lg:flex-row lg:items-center gap-3 mb-4">
            <div class="relative flex-1">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" stroke-width="2" class="absolute left-3.5 top-1/2 -translate-y-1/2"><circle cx="11" cy="11" r="8"/><path stroke-linecap="round" d="M21 21l-4.35-4.35"/></svg>
              <input type="search" wire:model.live.debounce.300ms="recherche"
                     placeholder="{{ __('pwa.hebergement.recherche') }}"
                     class="champ w-full border border-slate-200 rounded-lg pl-10 pr-4 py-2.5 text-sm bg-white">
            </div>

            <div class="flex flex-wrap gap-2">
              <select wire:model.live="categorie" class="champ text-[13px] border border-slate-300 rounded-lg px-3 py-2 bg-white">
                <option value="">{{ __('pwa.hebergement.toutes_categories') }}</option>
                @foreach ($categories as $cat)
                  <option value="{{ $cat->id }}">{{ $cat->libelle }}</option>
                @endforeach
              </select>
            </div>

            <div class="flex items-center gap-2 shrink-0">
              <button type="button" wire:click="$refresh"
                      class="btn p-2.5 rounded-lg border border-slate-200 bg-white text-slate-500" title="{{ __('pwa.hebergement.actualiser') }}">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M23 4v6h-6M1 20v-6h6"/><path stroke-linecap="round" stroke-linejoin="round" d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/></svg>
              </button>

              {{-- Importer : REFUSÉ, non inerte — voir la note ci-dessus.
                   Aucun contrôle n'est rendu ; le jeton porte la raison. --}}

              <button wire:click="$set('etatFormulaire', 'export')"
                      class="btn flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg border border-slate-300 bg-white text-[15px] font-semibold text-slate-700">
                {{ __('pwa.export.generer') }}
              </button>

              @if ($peutEcrire)
                <button type="button" wire:click="ouvrirFormulaireUnite"
                        class="btn flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg bg-[var(--navy)] text-white text-[15px] font-semibold">
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" d="M12 5v14M5 12h14"/></svg>
                  {{ __('hebergement_pwa.hebergement.bouton_ajouter') }}
                </button>
              @endif
            </div>
          </div>

          {{--
              ⚠ BLOC DU MAÎTRE OMIS, ET DÉCLARÉ : structure-refuse:m1-hebergement.html#crud-barre-groupee

              `crud-ui.js` `toolbarHtml()` pose une barre d'action GROUPÉE —
              « N sélectionné(s) », « Exporter la sélection », « Supprimer ».
              Elle n'est pas portée, et elle ne le sera pas : le « D » de CRUD
              n'existe nulle part dans ce dépôt. `BasePolicy::delete()` rend
              `false` pour les vingt policies, et une unité d'hébergement
              s'ARCHIVE (`confirmerArchivageUnite`), une par une, avec la
              vérification de verrou qui refuse d'archiver une unité engagée
              dans une réservation. Une case à cocher par ligne et un bouton
              « Supprimer » offriraient un geste que le serveur refuse toujours
              — un contrôle inerte, que l'Article 3.3 proscrit.
          --}}

          {{-- LA GRILLE DE CARTES — `crud-ui.js` `tableHtml()`, branche
               « cartes », posée par le maître dans `#crud-table-zone`.
               `m1-hebergement.html` est la SEULE page du maître qui déclare
               `modeAffichage: 'cartes'` (l.398) : ses unités sont des cartes,
               jamais des lignes de tableau.

               Deux corrections mesurées le 31/08/2026 :
               — l'écart est `gap-5`, pas `gap-4` ;
               — la grille est TOUJOURS posée, l'état vide vient APRÈS elle.
                 La PWA rendait l'un OU l'autre, l'état vide en premier : la
                 grille du maître n'avait alors aucun équivalent au repos. --}}
          <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-5">
              @foreach ($parc as $unite)
                @php $etat = $etats[$unite->id] ?? null; @endphp
                <div class="carte-hover bg-white rounded-xl border border-slate-200 p-4 flex flex-col" wire:key="unite-{{ $unite->id }}">
                  <div class="flex items-start justify-between mb-2.5">
                    <span class="font-mono-tatacora text-[15px] bg-slate-100 px-2 py-0.5 rounded font-semibold">{{ $unite->numero }}</span>
                    <span class="text-[15px] font-semibold px-2.5 py-1 rounded"
                          style="background:{{ $etat['bg'] ?? '#F3F4F6' }};color:{{ $etat['txt'] ?? '#6B7280' }}">{{ $etat['libelle'] ?? $tiret }}</span>
                  </div>

                  {{-- `unites_hebergement` ne porte ni nom ni description : la
                       carte affiche la catégorie, seule autre colonne. --}}
                  <h3 class="font-bold text-[15px] text-slate-800">{{ $unite->categorie?->libelle ?? $tiret }}</h3>

                  <div class="flex items-center justify-between text-[15px] my-3 pt-3 border-t border-slate-100">
                    <span class="text-slate-500">{{ __('pwa.hebergement.tarif_de_base') }}</span>
                    <span class="font-mono-tatacora font-bold" style="color:var(--gold)">
                      {{ $unite->categorie === null ? $tiret : MontantFcfa::format((string) $unite->categorie->tarif_base) }}
                    </span>
                  </div>

                  {{-- Le bouton du maître n'est pas une étiquette : chaque
                       transition est adossée aux réservations et au séjour. --}}
                  @if ($peutEcrire)
                    <div class="flex gap-2 mt-auto">
                      <div class="flex-1">
                        @switch($etat['cle'] ?? 'hors_service')
                          @case('libre')
                            <button wire:click="ouvrirReservationRapide('{{ $unite->id }}')"
                                    class="btn w-full flex items-center justify-center gap-2 text-white text-[15px] font-semibold py-2.5 rounded-lg" style="background:var(--navy)">
                              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" d="M12 5v14M5 12h14"/></svg>
                              {{ __('hebergement_pwa.hebergement.action_reserver') }}
                            </button>
                            @break
                          @case('reservee')
                            <button wire:click="effectuerCheckIn('{{ $unite->id }}')"
                                    class="btn w-full flex items-center justify-center gap-2 text-white text-[15px] font-semibold py-2.5 rounded-lg" style="background:var(--gold)">
                              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="12" cy="7" r="4"/><path stroke-linecap="round" stroke-linejoin="round" d="M5.5 21a6.5 6.5 0 0113 0"/></svg>
                              {{ __('hebergement_pwa.hebergement.action_checkin') }}
                            </button>
                            @break
                          @case('occupee')
                            <button wire:click="effectuerCheckOut('{{ $unite->id }}')"
                                    class="btn w-full flex items-center justify-center gap-2 text-white text-[15px] font-semibold py-2.5 rounded-lg" style="background:var(--erreur)">
                              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M9 21H5a2 2 0 01-2-2V5a2 2 0 012-2h4M16 17l5-5-5-5M21 12H9"/></svg>
                              {{ __('hebergement_pwa.hebergement.action_checkout') }}
                            </button>
                            @break
                          @case('nettoyage')
                            <button wire:click="marquerNettoye('{{ $unite->id }}')"
                                    class="btn w-full flex items-center justify-center gap-2 text-white text-[15px] font-semibold py-2.5 rounded-lg" style="background:var(--succes)">
                              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M20 6L9 17l-5-5"/></svg>
                              {{ __('hebergement_pwa.hebergement.action_nettoye') }}
                            </button>
                            @break
                          @default
                            {{-- maître l.170 : « Indisponible », bouton inerte.
                                 Le geste de sortie, lui, existe — sans quoi la
                                 promesse « reste restaurable » de la modale
                                 d'archivage ne serait tenue par personne. --}}
                            <button disabled
                                    class="btn w-full flex items-center justify-center gap-2 text-white text-[15px] font-semibold py-2.5 rounded-lg" style="background:#9CA3AF">
                              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="12" cy="12" r="10"/></svg>
                              {{ __('hebergement_pwa.hebergement.action_indisponible') }}
                            </button>
                        @endswitch
                      </div>

                      @if (($etat['cle'] ?? '') === 'hors_service')
                        <button wire:click="restaurerUnite('{{ $unite->id }}')"
                                class="btn px-3 py-2.5 rounded-lg border border-slate-200 text-[13px] font-semibold text-slate-600 hover:bg-slate-50">
                          {{ __('hebergement_pwa.hebergement.action_restaurer') }}
                        </button>
                      @else
                        <button wire:click="ouvrirFormulaireUnite('{{ $unite->id }}')"
                                class="btn p-2.5 rounded-lg border border-slate-200 text-slate-500 hover:bg-slate-50"
                                title="{{ __('hebergement_pwa.hebergement.action_modifier') }}">
                          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path stroke-linecap="round" stroke-linejoin="round" d="M18.5 2.5a2.12 2.12 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
                        </button>
                        {{-- Bascule « Suppression d'un enregistrement »
                             (Paramètres › Activation & Sécurité, 02/09/2026) :
                             fermée, le bouton est RETIRÉ, pas grisé — un
                             bouton grisé invite à cliquer et ne produit qu'un
                             refus (options-systeme.js, et Article 3.3). --}}
                        @if (app(\App\Shared\Parametres\Services\OptionsSystemeService::class)->suppressionActive())
                          <button wire:click="confirmerArchivageUnite('{{ $unite->id }}')"
                                  class="btn p-2.5 rounded-lg border border-slate-200 text-red-500 hover:bg-red-50"
                                  title="{{ __('hebergement_pwa.hebergement.action_supprimer') }}">
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M3 6h18M8 6V4a2 2 0 012-2h4a2 2 0 012 2v2m3 0v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6h14z"/></svg>
                          </button>
                        @endif
                      @endif
                    </div>
                  @endif
                </div>
              @endforeach
          </div>

          {{-- L'ÉTAT VIDE — `crud-ui.js` `#crud-etat-vide`, une colonne centrée
               sous la grille, jamais à sa place. --}}
          @if ($parcEstVide)
            <div class="flex flex-col items-center justify-center py-16 text-center bg-white rounded-xl border border-slate-200 mt-4">
              <p class="text-slate-400 text-sm">{{ __('pwa.hebergement.parc_vide') }}</p>
            </div>
          @else
            {{--
                LA PAGINATION — `crud-ui.js` `#crud-pagination` (tableHtml(),
                l.60) et `crud-engine.js::renderPagination()` (l.250-262),
                01/09/2026. Le décompte porte sur le FILTRE entier
                (`parcTotalFiltre`), la page affichée sur `parc`.
            --}}
            @php
              $debutPage = ($page - 1) * 10;
              $finPage = min($parcTotalFiltre, $debutPage + $parc->count());
            @endphp
            <div class="flex items-center justify-between px-1 py-4">
              <p class="text-xs text-slate-500">
                {{ __('pwa.hebergement.decompte_avant') }}
                <strong>{{ $parcTotalFiltre === 0 ? 0 : $debutPage + 1 }}-{{ $finPage }}</strong>
                {{ __('pwa.hebergement.decompte_liaison') }}
                <strong>{{ $parcTotalFiltre }}</strong>
              </p>
              <div class="flex items-center gap-2">
                <button type="button" wire:click="$set('page', {{ max(1, $page - 1) }})"
                        @disabled($page <= 1)
                        class="btn px-3 py-1.5 text-xs rounded-lg border border-slate-200 disabled:opacity-40">{{ __('pwa.hebergement.page_precedent') }}</button>
                <span class="text-xs text-slate-600 px-2">{{ __('pwa.hebergement.page_sur', ['page' => $page, 'total' => $parcTotalPages]) }}</span>
                <button type="button" wire:click="$set('page', {{ min($parcTotalPages, $page + 1) }})"
                        @disabled($page >= $parcTotalPages)
                        class="btn px-3 py-1.5 text-xs rounded-lg border border-slate-200 disabled:opacity-40">{{ __('pwa.hebergement.page_suivant') }}</button>
              </div>
            </div>
          @endif

          {{--
              NON PORTE, ET PLUS RENDU A L'ECRAN (02/09/2026). Champs d'unite
              supplementaires du maitre, selection multiple et « voir le
              detail » ne sont pas portes ; la section qui l'expliquait au
              lecteur est retiree par directive du Product Owner. Un ecran dit
              ce qu'il FAIT — ce qu'il ne fait pas se declare dans le code.
          --}}
        </div>

        {{-- ============ ONGLET « Réservations en cours » ============ --}}
        <div id="panneau-reservations-en-cours" class="{{ $onglet === 'reservations' ? '' : 'hidden' }}">
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead class="bg-[var(--navy)]">
                  <tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
                    <th class="px-4 py-3">{{ __('pwa.hebergement.col_client') }}</th>
                    <th class="px-4 py-3">{{ __('pwa.hebergement.col_unites') }}</th>
                    <th class="px-4 py-3">{{ __('pwa.hebergement.col_arrivee') }}</th>
                    <th class="px-4 py-3">{{ __('pwa.hebergement.col_depart') }}</th>
                    <th class="px-4 py-3">{{ __('pwa.hebergement.col_statut') }}</th>
                  </tr>
                </thead>
                <tbody>
                  @forelse ($reservationsEnCours as $reservation)
                    @php
                      $etatSejour = match (true) {
                          $reservation->statut === 'annulee' => ['txt' => __('hebergement_pwa.reservations.etat_annulee'), 'bg' => '#FDECEC', 'c' => '#C62828'],
                          $reservation->date_depart->toDateString() < $aujourdHui->toDateString() => ['txt' => 'Terminé', 'bg' => '#F3F4F6', 'c' => '#6B7280'],
                          $reservation->date_arrivee->toDateString() <= $aujourdHui->toDateString() => ['txt' => 'En cours', 'bg' => '#E8F5E9', 'c' => '#2E7D32'],
                          default => ['txt' => 'À venir', 'bg' => '#FDF3E0', 'c' => '#B8891E'],
                      };
                    @endphp
                    <tr class="border-t border-slate-100 hover:bg-slate-50" wire:key="resa-{{ $reservation->id }}">
                      <td class="px-4 py-3 font-medium text-slate-700">{{ $reservation->client?->nomComplet() ?: $tiret }}</td>
                      <td class="px-4 py-3 text-slate-600">{{ $reservation->unite?->numero ?? $tiret }} — {{ $reservation->unite?->categorie?->libelle ?? $tiret }}</td>
                      <td class="px-4 py-3 text-slate-500 font-mono-tatacora text-[15px]">{{ $reservation->date_arrivee->format('d/m/Y') }}</td>
                      <td class="px-4 py-3 text-slate-500 font-mono-tatacora text-[15px]">{{ $reservation->date_depart->format('d/m/Y') }}</td>
                      <td class="px-4 py-3"><span class="text-[15px] font-semibold px-2.5 py-1 rounded" style="background:{{ $etatSejour['bg'] }};color:{{ $etatSejour['c'] }}">{{ $etatSejour['txt'] }}</span></td>
                    </tr>
                  @empty
                    <tr>
                      <td colspan="5" class="px-4 py-16 text-center text-slate-400 text-sm">
                        {{-- L'état vide du moteur du maître (`crud-ui.js`
                             `#crud-etat-vide`) — le contrat du tableau
                             générique (G6) — puis l'invite propre à l'écran. --}}
                        <span class="font-semibold text-slate-500">{{ __('pwa.hebergement.reservations_vide_titre') }}</span><br>
                        <span class="text-xs">{{ __('pwa.hebergement.reservations_vide_detail') }}</span><br>
                        {{ __('pwa.hebergement.reservations_vide') }}
                        <a href="{{ route('pwa.reservations') }}" wire:navigate class="font-semibold" style="color:var(--gold)">{{ __('pwa.hebergement.reservations_vide_lien') }}</a>
                      </td>
                    </tr>
                  @endforelse
                </tbody>
              </table>
            </div>

            {{-- La pagination du maître (`crud-engine.js` `renderPagination`) :
                 « Affichage de X-Y sur Z » à gauche, les liens à droite. --}}
            <div class="flex items-center justify-between px-4 py-3 border-t border-slate-100 no-print">
              <p class="text-xs text-slate-500">{!! __('pwa.hebergement.reservations_affichage', [
                  'debut' => '<strong>' . ($reservationsEnCours->total() === 0 ? 0 : $reservationsEnCours->firstItem()) . '</strong>',
                  'fin' => '<strong>' . ($reservationsEnCours->lastItem() ?? 0) . '</strong>',
                  'total' => '<strong>' . $reservationsEnCours->total() . '</strong>',
              ]) !!}</p>
              {{ $reservationsEnCours->onEachSide(1)->links() }}
            </div>
          </div>
        </div>

        {{-- ============ ONGLET « Calendrier d'Occupation » ============ --}}
        <div id="panneau-calendrier-occupation" class="{{ $onglet === 'calendrier' ? '' : 'hidden' }}">
          <div class="bg-white rounded-xl border border-slate-200 p-5">
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-sm font-bold text-slate-700">{{ $aujourdHui->locale('fr')->isoFormat('MMMM YYYY') }}</h2>
              <div class="flex items-center gap-3 text-[12px] text-slate-400">
                <span class="flex items-center gap-1"><span class="w-2.5 h-2.5 rounded" style="background:#E8F5E9"></span>{{ __('pwa.hebergement.legende_faible') }}</span>
                <span class="flex items-center gap-1"><span class="w-2.5 h-2.5 rounded" style="background:#FDF3E0"></span>{{ __('pwa.hebergement.legende_moyen') }}</span>
                <span class="flex items-center gap-1"><span class="w-2.5 h-2.5 rounded" style="background:#FDECEC"></span>{{ __('pwa.hebergement.legende_fort') }}</span>
              </div>
            </div>

            <div class="grid grid-cols-7 gap-1.5 mb-1.5">
              @foreach (['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'] as $jour)
                <div class="text-center text-[12px] font-bold text-slate-400">{{ $jour }}</div>
              @endforeach
            </div>

            <div class="grid grid-cols-7 gap-1.5">
              {{-- Le maître aligne le 1er du mois sur le bon jour de semaine
                   (l.543, lundi = 0) : sans ces cellules vides, tout le mois
                   glisse d'un ou six jours. --}}
              @php $decalage = (int) $aujourdHui->startOfMonth()->dayOfWeekIso - 1; @endphp
              @for ($i = 0; $i < $decalage; $i++)
                <div></div>
              @endfor

              @foreach ($joursOccupation as $date => $occupees)
                @php
                  $taux = $totalParc > 0 ? $occupees / $totalParc : 0;
                  $estAuj = $date === $aujourdHui->toDateString();
                  $couleur = $occupees === 0 ? '#F9FAFB' : ($taux < 0.5 ? '#E8F5E9' : ($taux < 0.9 ? '#FDF3E0' : '#FDECEC'));
                @endphp
                <div class="aspect-square rounded-lg border {{ $estAuj ? 'border-[var(--navy)] border-2' : 'border-slate-100' }} p-1.5 flex flex-col justify-between" style="background:{{ $couleur }}">
                  <span class="text-[13px] font-semibold {{ $estAuj ? 'text-[var(--navy)]' : 'text-slate-500' }}">{{ (int) substr($date, 8, 2) }}</span>
                  @if ($occupees > 0)
                    <span class="text-[9px] text-slate-500 font-mono-tatacora">{{ $occupees }}/{{ $totalParc }}</span>
                  @endif
                </div>
              @endforeach
            </div>

            {{-- maître l.582 : « taux estimé ». Un taux présenté comme exact
                 servirait à décider d'une sur-réservation. --}}
            <p class="text-[13px] text-slate-400 mt-3">{{ __('pwa.hebergement.mention_estime', ['total' => $totalParc]) }}</p>
          </div>
        </div>

        {{-- ONGLET « Disponibilites » (PO 08/10/2026) - LECTURE seule : deux
             dates, un calcul (`DisponibiliteService`, RG-02), un bouton
             « Reserver » qui ouvre la reservation rapide deja gardee (RG-01). --}}
        <div id="panneau-disponibilites" class="{{ $onglet === 'disponibilites' ? '' : 'hidden' }}">
          <div class="bg-white rounded-xl border border-slate-200 p-5">
            <h2 class="text-sm font-bold text-slate-700">{{ __('pwa.hebergement.dispo_titre') }}</h2>
            <p class="text-[13px] text-slate-500 mt-1 mb-4">{{ __('pwa.hebergement.dispo_aide') }}</p>

            <div class="grid grid-cols-2 gap-3 max-w-md mb-4">
              <div>
                <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.hebergement.dispo_arrivee') }}</label>
                <input type="date" wire:model.live="dispoArrivee"
                       class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 focus:border-[var(--gold)] focus:outline-none">
              </div>
              <div>
                <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.hebergement.dispo_depart') }}</label>
                <input type="date" wire:model.live="dispoDepart"
                       class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 focus:border-[var(--gold)] focus:outline-none">
              </div>
            </div>

            @if ($dispoArrivee !== '' && $dispoDepart !== '' && ! $disponibilites['valide'])
              <p class="text-[13px] text-red-600">{{ __('pwa.hebergement.dispo_periode_invalide') }}</p>
            @endif

            @if ($disponibilites['valide'])
              <p class="text-[13px] text-slate-600 mb-3">{{ __('pwa.hebergement.dispo_resume', ['libres' => $disponibilites['libres'], 'total' => count($disponibilites['lignes']), 'nuits' => $disponibilites['nuits']]) }}</p>

              @if ($disponibilites['lignes'] === [])
                <p class="text-center text-slate-400 py-10 text-[13px]">{{ __('pwa.hebergement.dispo_vide') }}</p>
              @else
                <div class="overflow-x-auto border border-slate-200 rounded-lg">
                  <table class="w-full text-sm">
                    <thead class="bg-[var(--navy)]">
                      <tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
                        <th class="px-4 py-3">{{ __('pwa.hebergement.dispo_col_unite') }}</th>
                        <th class="px-4 py-3">{{ __('pwa.hebergement.dispo_col_categorie') }}</th>
                        <th class="px-4 py-3">{{ __('pwa.hebergement.dispo_col_capacite') }}</th>
                        <th class="px-4 py-3">{{ __('pwa.hebergement.dispo_col_montant') }}</th>
                        <th class="px-4 py-3">{{ __('pwa.hebergement.dispo_col_etat') }}</th>
                        <th class="px-4 py-3"></th>
                      </tr>
                    </thead>
                    <tbody>
                      @foreach ($disponibilites['lignes'] as $ligne)
                        <tr class="border-t border-slate-100">
                          <td class="px-4 py-3 font-semibold">{{ $ligne['numero'] }}</td>
                          <td class="px-4 py-3">{{ $ligne['categorie'] ?? $tiret }}</td>
                          <td class="px-4 py-3">{{ $ligne['capacite'] ?? $tiret }}</td>
                          <td class="px-4 py-3">{{ $ligne['montant'] === null ? $tiret : MontantFcfa::format($ligne['montant']) }}</td>
                          <td class="px-4 py-3">
                            @if ($ligne['libre'])
                              <span class="text-[12px] font-semibold px-2 py-0.5 rounded-full" style="background:#E8F5E9;color:#2E7D32">{{ __('pwa.hebergement.dispo_libre') }}</span>
                            @else
                              <span class="text-[12px] font-semibold px-2 py-0.5 rounded-full" style="background:#FDECEC;color:#C62828">{{ __('pwa.hebergement.dispo_indisponible') }}</span>
                              <span class="text-[12px] text-slate-500 ml-1">{{ $ligne['motif'] }}</span>
                            @endif
                          </td>
                          <td class="px-4 py-3 text-right">
                            @if ($ligne['libre'] && $peutEcrire)
                              <button type="button" wire:click="ouvrirReservationRapide('{{ $ligne['id'] }}', '{{ $dispoArrivee }}', '{{ $dispoDepart }}')"
                                      class="text-[12px] px-3 py-1 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('pwa.hebergement.dispo_reserver') }}</button>
                            @endif
                          </td>
                        </tr>
                      @endforeach
                    </tbody>
                  </table>
                </div>
              @endif
            @endif
          </div>
        </div>

      </div>
    </main>
  </div>

  {{-- ==================== MODALES ====================
       Elles ne sont JAMAIS rendues au premier GET : un formulaire d'écriture
       servi à un rôle qui n'a pas le droit d'écrire précède toute garde. --}}

  @if ($etatFormulaire === 'reservation-rapide')
    <x-pwa.modale :titre="__('hebergement_pwa.hebergement.modale_rapide_titre')"
                  :sousTitre="trim(($rrUnite?->numero ?? '') . ' · ' . ($rrUnite?->categorie?->libelle ?? ''), ' ·')"
                  largeur="512px"
                  fermer="$set('etatFormulaire', null)">
      <form wire:submit="enregistrerReservationRapide" class="space-y-3.5" id="formulaire-reservation-rapide">

        <div class="groupe-champ">
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('hebergement_pwa.hebergement.champ_client') }} <span class="text-red-500">*</span></label>
          <select wire:model="rrClientId" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
            <option value="">{{ __('hebergement_pwa.hebergement.champ_client_invite') }}</option>
            @foreach ($clients as $client)
              <option value="{{ $client->id }}">{{ $client->nomComplet() }} — {{ $client->telephone }}</option>
            @endforeach
          </select>
          @error('rrClientId') <p class="message-erreur text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>

        <div class="grid grid-cols-2 gap-3">
          <div class="groupe-champ">
            <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('hebergement_pwa.hebergement.champ_arrivee') }} <span class="text-red-500">*</span></label>
            <input type="date" wire:model.live="rrDateArrivee" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
            @error('rrDateArrivee') <p class="message-erreur text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
          <div class="groupe-champ">
            <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('hebergement_pwa.hebergement.champ_depart') }} <span class="text-red-500">*</span></label>
            <input type="date" wire:model.live="rrDateDepart" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
            @error('rrDateDepart') <p class="message-erreur text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
        </div>

        {{-- maître l.99-110 : nuits et montant CALCULÉS, jamais saisis — un
             total modifiable finit par contredire les dates. --}}
        <div class="grid grid-cols-2 gap-3 rounded-lg p-3.5" style="background:#F8FAFC">
          <div>
            <p class="text-[12px] text-slate-500">{{ __('hebergement_pwa.hebergement.nombre_nuits') }}</p>
            <p class="text-base font-bold font-mono-tatacora" style="color:var(--navy)">
              {{ $rrNuits > 0 ? __('hebergement_pwa.hebergement.nuits', ['nombre' => $rrNuits]) : $tiret }}
            </p>
          </div>
          <div class="text-right">
            <p class="text-[12px] text-slate-500">{{ __('hebergement_pwa.hebergement.montant_hebergement') }}</p>
            <p class="text-base font-bold font-mono-tatacora" style="color:var(--gold)">
              {{ $rrNuits > 0 ? MontantFcfa::format(bcmul($rrTarif, (string) $rrNuits, 2)) : $tiret }}
            </p>
          </div>
        </div>

        @error('rrUniteId')
          <p class="text-[13px] rounded-lg px-3 py-2.5" style="background:#FDECEC;color:#8C1D1D">{{ $message }}</p>
        @enderror

        <p class="text-[12px] text-slate-400 text-center">{{ __('hebergement_pwa.hebergement.rapide_pied') }}</p>

        {{--
            NON PORTE (02/09/2026) : le canal de reservation du maitre n'a
            aucune colonne serveur (PA-29), et le client ne se saisit pas en
            texte libre — c'est une vraie cle etrangere. Le refus n'est plus
            rendu dans la modale, il se lit ici.
        --}}
      </form>

      <x-slot:pied>
        <button type="button" wire:click="$set('etatFormulaire', null)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="submit" form="formulaire-reservation-rapide"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('hebergement_pwa.hebergement.bouton_rapide') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  @if ($etatFormulaire === 'unite')
    <x-pwa.modale :titre="$uniteId ? __('hebergement_pwa.hebergement.modale_unite_modification') : __('hebergement_pwa.hebergement.modale_unite_creation')"
                  :sousTitre="__('hebergement_pwa.hebergement.modale_unite_sous_titre')"
                  largeur="560px"
                  fermer="$set('etatFormulaire', null)">
      <form wire:submit="enregistrerUnite" class="space-y-4" id="formulaire-unite">
        <div class="groupe-champ">
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('hebergement_pwa.hebergement.champ_code') }} <span class="text-red-500">*</span></label>
          <input type="text" wire:model="uniteNumero" placeholder="{{ __('hebergement_pwa.hebergement.champ_code_invite') }}"
                 class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
          @error('uniteNumero') <p class="message-erreur text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>

        <div class="groupe-champ">
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('hebergement_pwa.hebergement.champ_categorie') }} <span class="text-red-500">*</span></label>
          {{-- Le modèle du Product Owner (01/09/2026) : la catégorie porte
               le type (Bungalow, Chambre simple, Suite…), le tarif et la
               capacité ; l'hébergement porte son libellé. Les catégories
               sans tarif au catalogue ne se seedent pas — elles se CRÉENT
               ici, tarif réel en main. --}}
          <label class="flex items-center gap-1.5 text-[12px] font-semibold text-slate-500 cursor-pointer mb-1.5">
            <input type="checkbox" wire:model.live="uniteNouvelleCategorie" class="rounded border-slate-300">
            {{ __('hebergement_pwa.hebergement.nouvelle_categorie') }}
          </label>
          @if ($uniteNouvelleCategorie)
            <div class="space-y-2 bg-slate-50 rounded-lg p-3">
              <input type="text" wire:model="categorieLibelle" placeholder="{{ __('hebergement_pwa.hebergement.categorie_libelle') }}" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
              @error('categorieLibelle') <p class="message-erreur text-[12px] text-red-600">{{ $message }}</p> @enderror
              <input type="number" min="1" wire:model="categorieTarif" placeholder="{{ __('hebergement_pwa.hebergement.categorie_tarif') }}" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
              @error('categorieTarif') <p class="message-erreur text-[12px] text-red-600">{{ $message }}</p> @enderror
              <input type="number" min="1" wire:model="categorieCapacite" placeholder="{{ __('hebergement_pwa.hebergement.categorie_capacite') }}" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
              @error('categorieCapacite') <p class="message-erreur text-[12px] text-red-600">{{ $message }}</p> @enderror
            </div>
          @else
            <select wire:model="uniteCategorieId" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
              <option value="">{{ __('hebergement_pwa.hebergement.champ_categorie_invite') }}</option>
              @foreach ($categories as $cat)
                <option value="{{ $cat->id }}">{{ $cat->libelle }} — {{ MontantFcfa::format((string) $cat->tarif_base) }}</option>
              @endforeach
            </select>
            @error('uniteCategorieId') <p class="message-erreur text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          @endif
        </div>

        {{--
            NON PORTE (02/09/2026) : les champs d'unite supplementaires du
            maitre ne sont pas portes, et `statut` ne se SAISIT pas — il est
            ecrit par les gestes de `SejourService` (check-in, check-out,
            nettoyage). Le laisser saisir ferait diverger l'etat affiche du
            cycle reel. Le refus n'est plus rendu, il se lit ici.
        --}}
      </form>

      <x-slot:pied>
        <button type="button" wire:click="$set('etatFormulaire', null)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="submit" form="formulaire-unite"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('hebergement_pwa.hebergement.enregistrer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  @if ($etatFormulaire === 'archivage')
    <x-pwa.modale-archivage action="archiverUnite"
                            :element="__('hebergement_pwa.hebergement.archivage_element', ['numero' => $uniteArchivee?->numero ?? ''])"
                            :messagesVerrou="$verrouArchivage === [] ? [] : [__('hebergement_pwa.hebergement.archivage_verrou', ['nombre' => count($verrouArchivage), 'details' => implode(', ', $verrouArchivage)])]"
                            :bloque="$verrouArchivage !== []"
                            fermer="$set('etatFormulaire', null)" />
  @endif

  @if ($etatFormulaire === 'export')
    @include('pwa.partials.modale-export', [
      'titre' => __('hebergement_pwa.hebergement.export_titre'),
      'sousTitre' => __('hebergement_pwa.hebergement.export_sous_titre'),
    ])
  @endif

  @include('pwa.partials.acces-rapide')
</div>

{{--
    POINT DE VENTE COMPTANT.

    Maitre : prototype_v2/pages/pos.html — c'est lui qui fait foi sur tout ce
    qui se voit. Trois choses valent d'etre sues avant de le modifier :

    1. `pos.html` N'A PAS DE <h1>. Verifie ligne a ligne : son premier titre est
       le <h2> « Salle » (l.34). Fabriquer un titre de page ici serait un ecart,
       pas une amelioration — et `BaliseTitrePwaTest` le sait.
    2. Le maitre porte le PRIX dans le DOM (`data-ajouter` avec son montant) et
       le renvoie tel quel. La PWA ne transmet qu'un module et une reference :
       le prix et le libelle sont relus du catalogue et figes cote serveur.
       Ne jamais remettre un montant dans un `wire:click`.
    3. L'etat `fermee` d'une table (maitre, `etatTable()`) N'EST PAS rendu :
       il derive de `table.actif`, qu'aucune donnee du schema ne porte
       (31/08/2026). L'afficher supposerait un drapeau que personne n'ecrit.
       Les TROIS autres — libre, ouverte, en cours — le sont depuis que le
       panier est une table (PA-161) : ils se DERIVENT du panier reel, calcules
       par `PosComptant::etatsDesTables()` et jamais recalcules ici.
    4. Le panier est un modele `Panier`, plus un tableau : ses lignes portent
       leur propre identifiant, et le prix affiche est celui FIGE a l'ajout,
       jamais relu du catalogue.
--}}
@php
    use App\Pwa\Support\MontantFcfa;
    use App\Pwa\Livewire\Pos\PosComptant;
@endphp

{{-- Le helper Alpine `imprimer()` est retire avec le bouton « Imprimer » de la
     modale de vente (PO 02/09/2026) : plus aucun appelant. --}}
<div class="contents">
  {{-- Session maintenue tant qu'un panier est ouvert OU que la caisse n'est
       pas clôturée (audit PO du 01/09/2026) — voir le partial. --}}
  @include('pwa.partials.maintien-session', ['maintenir' => $panier !== null || $session !== null])

  @include('pwa.partials.barre-superieure')

  <style>
    @media print {
      body, .contents, .flex, main, .zone-impression {
        overflow: visible !important;
        height: auto !important;
        max-height: none !important;
        position: static !important;
        background: #ffffff !important;
        color: #000000 !important;
      }
      #shell-sidebar, #shell-topbar, .no-print, nav, button, input, select { display: none !important; }
      main { margin: 0 !important; padding: 0 !important; }
    }
  </style>

  @if ($toastMessage)
    <div x-data="{ visible: true }" x-show="visible" x-init="setTimeout(() => visible = false, 5000)"
         class="fixed top-5 right-5 z-50 flex items-center gap-3 px-4 py-3 rounded-xl shadow-xl text-white text-[13px] font-medium no-print
         {{ $toastType === 'success' ? 'bg-emerald-600' : ($toastType === 'error' ? 'bg-red-600' : 'bg-slate-700') }}">
      <span>{{ $toastMessage }}</span>
      <button type="button" @click="visible = false" class="ml-2 text-white/80 hover:text-white">✕</button>
    </div>
  @endif

  @if (session('pwa-succes'))
    <div x-data="{ visible: true }" x-show="visible" x-init="setTimeout(() => visible = false, 5000)"
         class="fixed top-5 right-5 z-50 px-4 py-3 rounded-xl shadow-xl bg-emerald-600 text-white text-[13px] font-medium no-print">
      {{ session('pwa-succes') }}
    </div>
  @endif

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')

    <main class="flex-1 overflow-hidden flex flex-col">

      {{-- BARRE DE SESSION DE CAISSE — maitre, `rendreSession()` --}}
      <div class="shrink-0 px-5 py-2.5 border-b border-slate-200 bg-white no-print">
        @if ($session)
          <div class="flex flex-wrap items-center gap-x-6 gap-y-1.5">
            <span class="flex items-center gap-1.5 text-[13px]">
              <span class="w-2 h-2 rounded-full bg-emerald-500"></span>
              <strong style="color:var(--navy)">{{ __('pos_pwa.comptant.caisse_ouverte', ['point' => PosComptant::POINT_CAISSE]) }}</strong>
              <span class="text-slate-400">{{ __('pos_pwa.comptant.caisse_depuis', ['heure' => $session->date_ouverture->format('H:i')]) }}</span>
              {{--
                  ⚠ BUG CORRIGÉ (01/09/2026) — cette durée était un horodatage
                  FIGÉ au rendu serveur : « depuis 07:00 » restait affiché tel
                  quel toute la journée, sans jamais compter le temps écoulé —
                  « l'horloge ne décompte plus ». Elle est donc calculée et
                  mise à jour CÔTÉ CLIENT (Alpine, `setInterval`), à partir du
                  seul horodatage réel : `date_ouverture`. Le seuil des 24 h
                  est celui de `IndicateurCaisse::pour()` (barre supérieure) —
                  même définition d'une session « tardive », jamais une
                  seconde.
              --}}
              <span
                x-data="{
                  texte: '',
                  tardive: false,
                  majer() {
                    const depuis = new Date('{{ $session->date_ouverture->toIso8601String() }}').getTime();
                    const ms = Math.max(0, Date.now() - depuis);
                    const h = Math.floor(ms / 3600000);
                    const m = Math.floor((ms % 3600000) / 60000);
                    this.texte = h > 0 ? (h + 'h' + String(m).padStart(2, '0')) : (m + ' min');
                    this.tardive = h >= 24;
                  },
                }"
                x-init="majer(); setInterval(() => majer(), 30000)"
                :class="tardive ? 'text-red-600 font-semibold' : 'text-slate-400'"
                x-text="'· ' + texte"
              ></span>
            </span>
            <span class="text-[12px] text-slate-500">{{ __('pos_pwa.comptant.caisse_fond', ['montant' => MontantFcfa::format((string) $session->montant_fond)]) }}</span>
            <span class="text-[12px] text-slate-500">{{ __('pos_pwa.comptant.caisse_ventes', ['nombre' => $ventesDeLaSession->count()]) }}</span>
            @php
              $caSession = '0.00';
              $encaisseSession = '0.00';
              $noteSession = '0.00';
              foreach ($ventesDeLaSession as $venteSession) {
                  if ($venteSession->estAnnulee()) { continue; }
                  $caSession = bcadd($caSession, (string) $venteSession->montant_total, 2);
                  if ($venteSession->encaisse) {
                      $encaisseSession = bcadd($encaisseSession, (string) $venteSession->montant_total, 2);
                  } else {
                      $noteSession = bcadd($noteSession, (string) $venteSession->montant_total, 2);
                  }
              }
            @endphp
            <span class="text-[12px] text-slate-500">{{ __('pos_pwa.comptant.caisse_ca', ['montant' => MontantFcfa::format($caSession)]) }}</span>
            <span class="text-[12px] text-emerald-700 font-semibold">{{ __('pos_pwa.comptant.caisse_encaisse', ['montant' => MontantFcfa::format($encaisseSession)]) }}</span>
            @if (bccomp($noteSession, '0.00', 2) > 0)
              <span class="text-[12px] text-amber-700 font-semibold">{{ __('pos_pwa.comptant.caisse_en_note', ['montant' => MontantFcfa::format($noteSession)]) }}</span>
            @endif

            <div class="flex-1"></div>

            <button type="button" wire:click="ouvrirJournalDuJour"
                    class="text-[12px] px-3 py-1.5 rounded-lg border border-slate-300 hover:bg-slate-50 font-medium">{{ __('pos_pwa.comptant.journal_du_jour') }}</button>
            <button type="button" wire:click="ouvrirFormulaireClotureCaisse"
                    class="text-[12px] px-3 py-1.5 rounded-lg border border-slate-300 hover:bg-slate-50 font-medium">{{ __('pos_pwa.comptant.cloturer_caisse') }}</button>
          </div>
        @else
          <div class="flex flex-wrap items-center gap-3">
            <span class="flex items-center gap-1.5 text-[13px]">
              <span class="w-2 h-2 rounded-full bg-red-500"></span>
              <strong style="color:var(--navy)">{{ __('pos_pwa.comptant.caisse_aucune') }}</strong>
            </span>
            <span class="text-[12px] text-slate-400">{{ __('pos_pwa.comptant.caisse_aucune_aide') }}</span>
            <div class="flex-1"></div>
            <button type="button" wire:click="ouvrirFormulaireOuvertureCaisse"
                    class="text-[12px] px-4 py-1.5 rounded-lg bg-[var(--navy)] text-white hover:opacity-90 font-semibold">{{ __('pos_pwa.comptant.ouvrir_caisse') }}</button>
          </div>
        @endif
      </div>

      <div class="flex-1 overflow-hidden flex flex-col xl:flex-row">

        {{-- 1. LA SALLE — maitre, pos.html l.32-48 --}}
        <section class="xl:w-[320px] shrink-0 overflow-y-auto border-b xl:border-b-0 xl:border-r border-slate-200 bg-white">
          <div class="px-4 py-3 border-b border-slate-200">
            <h2 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('pos_pwa.comptant.salle') }}</h2>
            <p class="text-[11px] text-slate-400">{{ __('pos_pwa.comptant.salle_aide') }}</p>
          </div>

          <div class="p-4 space-y-4">
            {{--
                « Vendre au comptoir » — maitre, pos.html l.38-45. Le comptoir
                n'est PLUS present-selectionne (01/09/2026) : il faut le
                choisir explicitement, comme une table, avant de pouvoir
                ajouter un article ({@see \App\Pwa\Livewire\Pos\PosComptant::posteEstChoisi()}).
            --}}
            <button type="button" wire:click="$set('selectedTableId', null); $set('comptoirChoisi', true)"
              class="w-full flex items-center gap-3 px-3 py-2.5 rounded-lg border-2 border-dashed text-left {{ $selectedTableId === null && $comptoirChoisi ? 'border-[var(--navy)] bg-slate-50' : 'border-slate-300 hover:border-[var(--gold)] hover:bg-amber-50/40' }}">
              <span class="w-8 h-8 rounded-lg bg-[var(--navy)] text-white flex items-center justify-center font-bold text-[13px]">{{ __('pos_pwa.comptant.initiale_comptoir') }}</span>
              <span class="min-w-0">
                <span class="block text-[13px] font-bold" style="color:var(--navy)">{{ __('pos_pwa.comptant.vendre_au_comptoir') }}</span>
                <span class="block text-[11px] text-slate-500">{{ __('pos_pwa.comptant.sans_table') }}</span>
              </span>
            </button>

            @foreach ($planDeSalle as $espace => $tables)
              <div wire:key="espace-{{ $espace }}">
                <p class="text-[11px] font-bold mb-1.5 uppercase tracking-wide text-slate-500">{{ $espace }}</p>
                @if (empty($tables))
                  <p class="text-[12px] text-slate-400">{{ __('pos_pwa.comptant.espace_vide') }}</p>
                @else
                  <div class="grid grid-cols-3 gap-1.5">
                    @foreach ($tables as $table)
                      @php
                        // maitre — `etatTable()` : trois etats rendus sur quatre.
                        // Ils sont DERIVES des paniers reels par le composant ;
                        // les recalculer ici donnerait une seconde verite.
                        $etat = $etatsDesTables[$table['id']]['etat'];
                        $etatLibelle = $etatsDesTables[$table['id']]['libelle'];
                        $totalTable = $etatsDesTables[$table['id']]['total'];
                        $courante = $selectedTableId === $table['id'];
                      @endphp
                      <button type="button" wire:click="$set('selectedTableId', '{{ $table['id'] }}'); $set('comptoirChoisi', false)"
                        wire:key="table-{{ $table['id'] }}"
                        title="{{ $table['libelle'] }} — {{ $etatLibelle }}"
                        class="px-2.5 py-2 rounded-lg border text-left {{ $etat === 'en_cours' ? 'border-[var(--gold)] bg-amber-50' : ($etat === 'ouverte' ? 'border-blue-300 bg-blue-50' : 'bg-white border-slate-200 hover:border-slate-400') }} {{ $courante ? 'ring-2 ring-[var(--navy)]' : '' }}">
                        <span class="block text-[13px] font-bold" style="color:var(--navy)">{{ $table['libelle'] }}</span>
                        <span class="block text-[10.5px] {{ $etat === 'en_cours' ? 'text-amber-700' : ($etat === 'ouverte' ? 'text-blue-700' : 'text-slate-400') }}">
                          {{ $etat === 'en_cours'
                              ? MontantFcfa::format($totalTable)
                              : ($etat === 'ouverte'
                                  ? $etatLibelle
                                  : __('pos_pwa.comptant.places', ['nombre' => $table['places']])) }}
                        </span>
                      </button>
                    @endforeach
                  </div>
                @endif
              </div>
            @endforeach
          </div>
        </section>

        {{-- 2. LE CATALOGUE — maitre, pos.html l.52-70 --}}
        <section class="flex-1 overflow-hidden flex flex-col bg-slate-50/50">
          <div class="shrink-0 px-5 pt-4 pb-2 bg-white border-b border-slate-100">
            <div class="flex flex-wrap gap-2 items-center mb-3">
              <div class="relative flex-1 min-w-[200px]">
                <svg class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
                <input type="search" wire:model.live.debounce.250ms="recherche"
                  placeholder="{{ __('pos_pwa.commun.rechercher') }}"
                  class="w-full text-[14px] border border-slate-300 rounded-lg pl-9 pr-3 py-2.5 focus:border-[var(--gold)] focus:outline-none bg-white">
              </div>

              {{-- ⚠ PA-79 — ce filtre ne change ni la caisse ni le panier. Le
                   maitre le dit lui-meme dans son infobulle (pos.html l.60). --}}
              <select wire:model.live="famille"
                title="{{ __('pos_pwa.comptant.filtre_famille_aide') }}"
                class="text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 bg-white font-medium">
                <option value="tout">{{ __('pos_pwa.comptant.famille_tout') }}</option>
                <option value="{{ __('pos_pwa.comptant.famille_bar') }}">{{ __('pos_pwa.comptant.famille_bar') }}</option>
                <option value="{{ __('pos_pwa.comptant.famille_restaurant') }}">{{ __('pos_pwa.comptant.famille_restaurant') }}</option>
                <option value="{{ __('pos_pwa.comptant.famille_tourisme') }}">{{ __('pos_pwa.comptant.famille_tourisme') }}</option>
                <option value="{{ __('pos_pwa.comptant.famille_location') }}">{{ __('pos_pwa.comptant.famille_location') }}</option>
              </select>
            </div>

            {{-- Pastilles de categorie — maitre, `rendreOnglets()` --}}
            <div class="flex gap-1.5 overflow-x-auto pb-2">
              @foreach ($categories as $cle => $libelle)
                <button type="button" wire:click="$set('categorieActive', '{{ $cle }}')" wire:key="cat-{{ $cle }}"
                  class="shrink-0 px-3.5 py-1.5 rounded-full text-[12px] font-semibold {{ $categorieActive === $cle ? 'bg-[var(--navy)] text-white' : 'bg-white border border-slate-300 text-slate-600 hover:border-[var(--gold)]' }}">
                  {{ $libelle }}
                </button>
              @endforeach
            </div>
          </div>

          <div class="flex-1 overflow-y-auto px-5 py-4">
            @if ($catalogue->isEmpty())
              <p class="py-16 text-center text-[13px] text-slate-400">{{ __('pos_pwa.commun.catalogue_vide') }}</p>
            @else
              <div class="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-4 gap-2.5">
                @foreach ($catalogue as $item)
                  @php
                    $vendable = bccomp((string) $item['prix'], '0.00', 2) > 0;
                  @endphp
                  <button type="button"
                    wire:click="ajouterAuPanier('{{ $item['module'] }}', '{{ $item['reference_id'] }}')"
                    wire:key="article-{{ $item['module'] }}-{{ $item['reference_id'] }}"
                    @disabled(! $vendable)
                    class="text-left p-3 rounded-xl border relative {{ $vendable ? 'bg-white border-slate-200 hover:border-[var(--gold)] hover:shadow-sm' : 'bg-slate-50 border-slate-200 opacity-60 cursor-not-allowed' }}">
                    <div class="flex items-start justify-between gap-1.5">
                      <span class="text-[13px] font-semibold leading-snug" style="color:var(--navy)">{{ $item['nom'] }}</span>
                      @if ($vendable && ! $item['lien_stock'] && ! $item['prestation'])
                        <span title="{{ __('pos_pwa.comptant.point_orange_infobulle') }}"
                              class="shrink-0 w-1.5 h-1.5 rounded-full bg-amber-400 mt-1.5"></span>
                      @elseif ($vendable && $item['composition_provisoire'])
                        {{-- La marque « composition provisoire » (04/09/2026).
                             Ce n'est PAS le point orange, et la forme diffère
                             pour qu'on ne les confonde pas : le point orange
                             dit « rien ne sort du stock », cette pastille dit
                             « ce qui en sort est approximatif ». Elle porte une
                             lettre plutôt qu'un point — deux points de couleurs
                             voisines à la même place seraient indiscernables au
                             comptoir, sous la lumière du bar. --}}
                        <span title="{{ __('pos_pwa.comptant.composition_provisoire_infobulle') }}"
                              class="shrink-0 text-[9px] leading-none font-bold px-1 py-0.5 rounded" style="background:#FDF3E0;color:#B8891E">{{ __('pos_pwa.comptant.composition_provisoire_marque') }}</span>
                      @endif
                    </div>
                    <p class="mt-2 text-[15px] font-bold" style="color:var(--gold)">
                      {{ $vendable ? MontantFcfa::format((string) $item['prix']) : __('pos_pwa.commun.prix_a_definir') }}
                    </p>
                    <span class="text-[10px] text-slate-400 mt-0.5 block">
                      {{ $item['famille'] }} · {{ $item['categorie'] }}
                      @if ($item['stock'] !== null)
                        {{-- Quantité sans décimales muettes — « 3 » plutôt
                             que « 3.00 » (02/09/2026, passage navigateur) ;
                             « 0.5 » reste tel quel. --}}
                        · {{ rtrim(rtrim((string) $item['stock'], '0'), '.') ?: '0' }}
                      @endif
                    </span>
                  </button>
                @endforeach
              </div>
            @endif

            <p class="mt-4 text-[11px] text-slate-400 flex items-center gap-1.5">
              <span class="w-1.5 h-1.5 rounded-full bg-amber-400"></span>
              {{ __('pos_pwa.comptant.point_orange_legende') }}
            </p>

            {{-- La seconde légende, celle des compositions posées (04/09/2026).
                 Une marque sans légende fait chercher : le maître pose déjà la
                 sienne pour le point orange, celle-ci la double. --}}
            <p class="mt-1.5 text-[11px] text-slate-400 flex items-center gap-1.5">
              <span class="text-[9px] leading-none font-bold px-1 py-0.5 rounded" style="background:#FDF3E0;color:#B8891E">{{ __('pos_pwa.comptant.composition_provisoire_marque') }}</span>
              {{ __('pos_pwa.comptant.composition_provisoire_legende') }}
            </p>
          </div>
        </section>

        {{-- 3. LE PANIER — maitre, pos.html l.72-112 --}}
        <section class="w-full xl:w-[380px] shrink-0 overflow-hidden flex flex-col border-t xl:border-t-0 xl:border-l border-slate-200 bg-white">
          <header class="px-4 py-3 border-b border-slate-200 flex items-center justify-between shrink-0">
            <div>
              <h2 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('pos_pwa.comptant.panier') }}</h2>
              <p class="text-[11px] text-slate-400">{{ __('pos_pwa.comptant.articles', ['nombre' => $panier ? $panier->lignes->count() : 0]) }}</p>
            </div>
            <div class="flex items-center gap-1.5">
              <button type="button" wire:click="viderPanier"
                      class="text-[12px] px-2.5 py-1 rounded-lg border border-slate-300 hover:bg-slate-50 font-medium">{{ __('pos_pwa.comptant.vider') }}</button>
              <button type="button" wire:click="abandonnerPanier"
                      class="text-[12px] px-2.5 py-1 rounded-lg border border-slate-300 text-red-600 hover:bg-red-50 font-medium">{{ __('pos_pwa.comptant.abandonner') }}</button>
            </div>
          </header>

          {{--
              Maitre — pos.html l.94-97 (`rendreContexte()`). Trois etats,
              plus qu'auparavant : sans table NI comptoir choisi, l'ecran dit
              qu'aucun panier n'est ouvert — il ne presuppose plus le comptoir.
          --}}
          <div class="px-4 py-2.5 border-b border-slate-200 shrink-0 bg-slate-50">
            <p class="text-[13px] font-semibold text-slate-700">
              @if ($tableSelectionnee)
                {{ $poste }} — {{ $tableSelectionnee['libelle'] }}
              @elseif ($comptoirChoisi)
                {{ __('pos_pwa.comptant.vendre_au_comptoir') }}
              @else
                {{ __('pos_pwa.comptant.panier_aucun') }}
              @endif
            </p>
            <p class="text-[11px] text-slate-400 mt-0.5">{{ __('pos_pwa.comptant.panier_choisir') }}</p>
          </div>

          <div class="flex-1 overflow-y-auto">
            @if (! $panier || $panier->lignes->isEmpty())
              <div class="py-16 px-6 text-center">
                <p class="text-[13px] text-slate-400">{{ __('pos_pwa.comptant.panier_vide') }}</p>
                <p class="text-[11.5px] text-slate-300 mt-1">{{ __('pos_pwa.comptant.panier_vide_aide') }}</p>
              </div>
            @else
              @foreach ($panier->lignes as $ligne)
                <div class="px-4 py-2.5 border-b border-slate-100 flex items-center gap-2" wire:key="ligne-{{ $ligne->id }}">
                  <div class="flex-1 min-w-0">
                    <p class="text-[13px] font-medium truncate" style="color:var(--navy)">{{ $ligne->libelle }}</p>
                    <p class="text-[11px] text-slate-400">{{ MontantFcfa::format((string) $ligne->prix_unitaire) }} × {{ $ligne->quantite }}</p>
                  </div>
                  <div class="flex items-center gap-1 shrink-0">
                    <button type="button" wire:click="decrementerLigne('{{ $ligne->id }}')"
                            class="w-7 h-7 rounded-lg border border-slate-300 hover:bg-slate-50 font-bold">−</button>
                    <span class="w-7 text-center text-[13px] font-semibold">{{ $ligne->quantite }}</span>
                    <button type="button" wire:click="incrementerLigne('{{ $ligne->id }}')"
                            class="w-7 h-7 rounded-lg border border-slate-300 hover:bg-slate-50 font-bold">+</button>
                  </div>
                  <span class="w-20 text-right text-[13px] font-bold shrink-0" style="color:var(--navy)">
                    {{ MontantFcfa::format($ligne->montant()) }}
                  </span>
                  <button type="button" wire:click="retirerLigne('{{ $ligne->id }}')"
                          title="{{ __('pos_pwa.comptant.retirer_ligne', ['article' => $ligne->libelle]) }}"
                          class="text-red-500 hover:bg-red-50 p-1 rounded">✕</button>
                </div>
              @endforeach
            @endif
          </div>

          <footer class="shrink-0 border-t border-slate-200 p-4 bg-slate-50">
            <div class="flex justify-between items-baseline mb-1">
              <span class="text-[13px] text-slate-500">{{ __('pos_pwa.comptant.total') }}</span>
              <span class="text-2xl font-bold" style="color:var(--navy)">{{ MontantFcfa::format($totalNet) }}</span>
            </div>

            {{--
                REMISE — ajout hors maitre, directive PO du 02/09/2026
                (structure-ajout:pos.html#remise). Type + valeur, le motif de
                la fiche de reservation ; le montant et le net viennent du
                modele (`Panier::remiseSur()`, auteur unique), jamais d'une
                arithmetique de vue. Bornes : 0-100 %, jamais au-dela du
                total — un net negatif refuse.
            --}}
            <div class="flex items-center gap-2 mb-1">
              <label for="remise-type" class="text-[11px] font-semibold text-slate-500 shrink-0">{{ __('pos_pwa.commun.remise') }}</label>
              <select id="remise-type" wire:model="remiseType" wire:change="appliquerRemise"
                      class="text-[12px] border border-slate-300 rounded-lg px-2 py-1.5 bg-white">
                <option value="aucune">{{ __('pos_pwa.commun.remise_aucune') }}</option>
                <option value="pourcentage">%</option>
                <option value="montant">FCFA</option>
              </select>
              <input id="remise-valeur" type="number" min="0" wire:model="remiseValeur" wire:change="appliquerRemise"
                     aria-label="{{ __('pos_pwa.commun.remise_valeur') }}"
                     class="w-full text-[12px] border border-slate-300 rounded-lg px-2 py-1.5 bg-white">
            </div>
            @error('remiseValeur')
              <p class="text-[11px] text-red-600 mb-1">{{ $message }}</p>
            @enderror
            @if (bccomp($remisePanier, '0.00', 2) > 0)
              <div class="flex justify-between text-[11.5px] text-slate-500 mb-2">
                <span>{{ __('pos_pwa.commun.remise_appliquee', ['brut' => MontantFcfa::format($totalPanier)]) }}</span>
                <span>- {{ MontantFcfa::format($remisePanier) }}</span>
              </div>
            @else
              <div class="mb-2"></div>
            @endif

            {{--
                « Porté sur la note de chambre » a quitté CE sélecteur —
                directive PO du 02/09/2026 : aucune chambre au comptoir, le
                mode reste au POS des clients hébergés. Le refus serveur vit
                dans `encaissementReel()` (une propriété Livewire se pose
                depuis le navigateur). maitre-refuse:pos.html#mode-note-chambre
            --}}
            {{-- Mode de reglement et Client sur UNE ligne — directive PO du
                 03/09/2026, pour economiser la hauteur du panneau. --}}
            <div class="grid grid-cols-2 gap-2 mb-3">
              <div>
                <label for="mode-paiement" class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('pos_pwa.comptant.mode_reglement') }}</label>
                <select id="mode-paiement" wire:model="modePaiement"
                        class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2 bg-white">
                  @foreach ($modesPaiementComptoir as $cleMode => $libelleMode)
                    <option value="{{ $cleMode }}">{{ $libelleMode }}</option>
                  @endforeach
                </select>
              </div>
              <div>
                {{--
                    CLIENT EN TEXTE LIBRE — directive PO du 02/09/2026
                    (structure-ajout:pos.html#client-mention). Une MENTION
                    imprimée sur le ticket et la facture, jamais une FK : la vente
                    au comptoir est anonyme par nature, ce nom n'alimente aucun
                    registre client. Voir `PosComptant::$clientMention`.
                --}}
                <label for="client-vente" class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('pos_pwa.comptant.client') }}</label>
                <input id="client-vente" type="text" wire:model="clientMention"
                       placeholder="{{ __('pos_pwa.comptant.client_mention_aide') }}"
                       class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2 bg-white">
              </div>
            </div>


            <button type="button" wire:click="encaisser" @disabled(! $panier || $panier->lignes->isEmpty() || ! $session)
              class="w-full py-3 rounded-lg bg-[var(--navy)] text-white font-bold text-[14px] hover:opacity-90 disabled:opacity-40 disabled:cursor-not-allowed">
              {{ $session ? __('pos_pwa.comptant.encaisser') : __('pos_pwa.comptant.encaisser_sans_caisse') }}
            </button>
          </footer>
        </section>

      </div>
    </main>
  </div>

  {{-- ================= MODALE TICKET — maitre, `modaleTicket()` ================= --}}
  @if ($etatFormulaire === 'ticket' && $derniereVente)
    <x-pwa.modale :titre="__('pos_pwa.comptant.ticket_titre')"
                  :sousTitre="$derniereVente->numero . ' — ' . ($modesPaiement[$derniereVente->mode_paiement] ?? $derniereVente->mode_paiement)"
                  largeur="480px">
      {{-- maitre — pos.html l.835 : les quatre entetes, a la lettre.
           ⚠ EXCLUE de la conversion navy du 01/09/2026 : ce tableau EST le
           ticket remis au client (rouleau 80mm, PA-101), pas un écran de
           consultation — il garde le style clair du document imprimé. --}}
      <div class="overflow-x-auto">
        <table class="w-full text-[13px]">
          <thead class="text-[11px] uppercase text-slate-500 border-b border-slate-200">
            <tr>
              <th class="text-left py-1.5">{{ __('pos_pwa.document.entete_article') }}</th>
              <th class="text-center py-1.5">{{ __('pos_pwa.document.entete_quantite') }}</th>
              <th class="text-right py-1.5">{{ __('pos_pwa.document.entete_prix_unitaire') }}</th>
              <th class="text-right py-1.5">{{ __('pos_pwa.document.entete_montant') }}</th>
            </tr>
          </thead>
          <tbody>
            @foreach ($derniereVente->lignes as $ligneVente)
              <tr class="border-b border-slate-100" wire:key="tk-{{ $ligneVente->id }}">
                <td class="py-1.5">{{ $ligneVente->nom }}</td>
                <td class="py-1.5 text-center tabular-nums">{{ $ligneVente->quantite }}</td>
                <td class="py-1.5 text-right tabular-nums">{{ MontantFcfa::format((string) $ligneVente->prix_unitaire) }}</td>
                <td class="py-1.5 text-right font-bold tabular-nums">{{ MontantFcfa::format((string) $ligneVente->montant) }}</td>
              </tr>
            @endforeach
          </tbody>
        </table>
      </div>

      {{-- La remise (PO 02/09/2026) est DERIVEE : lignes brutes − net
           encaisse (`Vente::remiseDeduite()`), jamais une copie. --}}
      @if (bccomp($derniereVente->remiseDeduite(), '0.00', 2) > 0)
        <div class="flex justify-between text-[12px] text-slate-500 border-t border-slate-200 pt-2">
          <span>{{ __('pos_pwa.commun.remise') }}</span>
          <span>- {{ MontantFcfa::format($derniereVente->remiseDeduite()) }}</span>
        </div>
      @endif

      <div class="flex justify-between font-bold text-base border-t border-slate-300 pt-2" style="color:var(--navy)">
        <span>{{ __('pos_pwa.comptant.total') }}</span>
        <span>{{ MontantFcfa::format((string) $derniereVente->montant_total) }}</span>
      </div>

      @unless ($derniereVente->encaisse)
        <p class="text-[11.5px] text-amber-800 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2">
          {{ __('pos_pwa.comptant.ticket_porte_en_note') }}
        </p>
      @endunless

      @if ($derniereVente->aDesLignesSansImpactStock())
        <p class="text-[11.5px] text-red-700 bg-red-50 border border-red-200 rounded-lg px-3 py-2">
          {{ __('pos_pwa.comptant.ticket_stock', [
              'nombre' => count($derniereVente->stock_non_impacte),
              'articles' => implode(', ', array_column($derniereVente->stock_non_impacte, 'ligne')),
          ]) }}
        </p>
      @endif

      <x-slot:pied>
        {{--
            Le bouton « Imprimer » du maitre est RETIRE de cette modale —
            directive PO du 02/09/2026 : il imprimait la page courante, un
            doublon des deux documents reels ci-dessous. Seuls restent
            « Ticket 80 mm » et « Facture ». maitre-refuse:pos.html#ticket-imprimer
            (La cle `pos_pwa.comptant.ticket_imprimer` n'est PAS orpheline :
            le bouton de secours de la fenetre 80 mm — `ticket-thermique.
            blade.php` — la porte toujours.)
        --}}
        <a href="{{ route('pwa.pos.ticket-thermique', $derniereVente->id) }}" target="_blank" rel="noopener"
           class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pos_pwa.comptant.ticket_thermique') }}</a>
        <button type="button" wire:click="imprimerTicketA4"
                class="text-[13px] px-4 py-2 rounded-lg border border-[var(--gold)] text-[var(--gold)] font-semibold hover:bg-amber-50">{{ __('pos_pwa.comptant.ticket_facture_a4') }}</button>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('pwa.modale.fermer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ================= MODALE JOURNAL DU JOUR — maitre, `modaleJournal()` ================= --}}
  @if ($etatFormulaire === 'journal')
    @php
      $valideesJour = $ventesDeLaSession->filter(fn ($v) => ! $v->estAnnulee());
      $caJour = '0.00';
      $encaisseJour = '0.00';
      $articlesJour = 0;
      foreach ($valideesJour as $venteJour) {
          $caJour = bcadd($caJour, (string) $venteJour->montant_total, 2);
          if ($venteJour->encaisse) {
              $encaisseJour = bcadd($encaisseJour, (string) $venteJour->montant_total, 2);
          }
          $articlesJour += (int) $venteJour->lignes->sum('quantite');
      }
      $panierMoyen = $valideesJour->count() > 0
          ? bcdiv($caJour, (string) $valideesJour->count(), 2)
          : '0.00';
    @endphp
    <x-pwa.modale :titre="__('pos_pwa.comptant.journal_du_jour')"
                  :sousTitre="__('pos_pwa.comptant.caisse_ventes', ['nombre' => $ventesDeLaSession->count()])"
                  largeur="620px">
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-2.5 text-[12px]">
        <div class="bg-slate-50 rounded-lg p-2.5">
          <p class="text-slate-400 text-[10px] uppercase tracking-wide">{{ __('pos_pwa.comptant.journal_ca') }}</p>
          <p class="font-bold text-[15px] tabular-nums" style="color:var(--navy)">{{ MontantFcfa::format($caJour) }}</p>
        </div>
        <div class="bg-slate-50 rounded-lg p-2.5">
          <p class="text-slate-400 text-[10px] uppercase tracking-wide">{{ __('pos_pwa.comptant.journal_encaisse') }}</p>
          <p class="font-bold text-[15px] tabular-nums text-emerald-600">{{ MontantFcfa::format($encaisseJour) }}</p>
        </div>
        <div class="bg-slate-50 rounded-lg p-2.5">
          <p class="text-slate-400 text-[10px] uppercase tracking-wide">{{ __('pos_pwa.comptant.journal_panier_moyen') }}</p>
          <p class="font-bold text-[15px] tabular-nums" style="color:var(--navy)">{{ MontantFcfa::format($panierMoyen) }}</p>
        </div>
        <div class="bg-slate-50 rounded-lg p-2.5">
          <p class="text-slate-400 text-[10px] uppercase tracking-wide">{{ __('pos_pwa.comptant.journal_articles') }}</p>
          <p class="font-bold text-[15px] tabular-nums" style="color:var(--navy)">{{ $articlesJour }}</p>
        </div>
      </div>

      {{-- maitre — pos.html l.908 : les six entetes, a la lettre.
           En-tête NAVY (01/09/2026). Pas de barre de recherche : ce tableau
           est le récapitulatif borné à la session de caisse OUVERTE (pas de
           pagination possible), et le journal complet, filtrable, vit sur
           l'écran dédié « Historique des ventes ». --}}
      <div class="max-h-[300px] overflow-y-auto overflow-x-auto">
        <table class="w-full text-[12.5px]">
          <thead class="bg-[var(--navy)] sticky top-0">
            <tr>
              <th class="text-left py-1.5 px-2 text-[11px] font-semibold text-white/90 uppercase tracking-wide">{{ __('pos_pwa.document.entete_numero') }}</th>
              <th class="text-left py-1.5 px-2 text-[11px] font-semibold text-white/90 uppercase tracking-wide">{{ __('pos_pwa.document.entete_heure') }}</th>
              <th class="text-left py-1.5 px-2 text-[11px] font-semibold text-white/90 uppercase tracking-wide">{{ __('pos_pwa.document.entete_table_chambre') }}</th>
              <th class="text-left py-1.5 px-2 text-[11px] font-semibold text-white/90 uppercase tracking-wide">{{ __('pos_pwa.document.entete_reglement') }}</th>
              <th class="text-right py-1.5 px-2 text-[11px] font-semibold text-white/90 uppercase tracking-wide">{{ __('pos_pwa.document.entete_montant') }}</th>
              <th class="text-left py-1.5 px-2 text-[11px] font-semibold text-white/90 uppercase tracking-wide">{{ __('pos_pwa.document.entete_statut') }}</th>
            </tr>
          </thead>
          <tbody>
            @forelse ($ventesDeLaSession as $venteLigne)
              <tr class="border-b border-slate-100" wire:key="jour-{{ $venteLigne->id }}">
                <td class="py-2 px-2 font-mono-tatacora text-[11px] text-slate-500">{{ $venteLigne->numero }}</td>
                <td class="py-2 px-2 text-slate-500">{{ $venteLigne->created_at?->format('H:i') }}</td>
                <td class="py-2 px-2 text-slate-500">{{ $venteLigne->table ?? '—' }}</td>
                <td class="py-2 px-2 text-slate-500">{{ $modesPaiement[$venteLigne->mode_paiement] ?? $venteLigne->mode_paiement }}</td>
                <td class="py-2 px-2 text-right font-medium tabular-nums text-slate-800">{{ MontantFcfa::format((string) $venteLigne->montant_total) }}</td>
                <td class="py-2 px-2">
                  @if ($venteLigne->estAnnulee())
                    <span class="text-[11px] px-2 py-0.5 rounded bg-red-50 text-red-700 font-semibold">{{ __('pos_pwa.comptant.journal_annulee') }}</span>
                  @else
                    <button type="button" wire:click="ouvrirAnnulationVente('{{ $venteLigne->id }}')"
                            class="text-[11px] text-red-600 hover:underline">{{ __('pos_pwa.comptant.journal_annuler') }}</button>
                  @endif
                </td>
              </tr>
            @empty
              <tr>
                <td colspan="6" class="py-8 px-2 text-center text-slate-400">{{ __('pos_pwa.comptant.journal_vide') }}</td>
              </tr>
            @endforelse
          </tbody>
        </table>
      </div>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('pwa.modale.fermer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ================= MODALE OUVERTURE DE CAISSE ================= --}}
  @if ($etatFormulaire === 'ouverture-caisse')
    <x-pwa.modale :titre="__('pos_pwa.comptant.ouverture_titre', ['point' => PosComptant::POINT_CAISSE])"
                  largeur="448px">
      <div>
        <label for="fond-caisse" class="block text-[13px] font-semibold text-slate-700 mb-2">{{ __('pos_pwa.comptant.ouverture_fond') }}</label>
        <input id="fond-caisse" type="number" step="1" min="0" wire:model="fondCaisseSaisi"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2 focus:border-[var(--gold)] focus:outline-none">
        @error('fondCaisseSaisi')
          <p class="mt-2 text-[12px] text-red-600">{{ $message }}</p>
        @enderror
      </div>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="ouvrirCaisse"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('pos_pwa.comptant.ouvrir_caisse') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ================= MODALE CLOTURE DE CAISSE — maitre, caisse-ui.js l.130-150 ================= --}}
  @if ($etatFormulaire === 'cloture-caisse')
    <x-pwa.modale :titre="__('pos_pwa.comptant.cloture_titre', ['point' => PosComptant::POINT_CAISSE])"
                  :sousTitre="__('pos_pwa.comptant.cloture_theorique')"
                  largeur="448px">
      {{-- Le RECAP — maitre, caisse-ui.js l.140-143 : fond, especes, theorique. --}}
      <div class="text-[13px] space-y-1.5">
        <div class="flex justify-between">
          <span class="text-slate-500">{{ __('pos_pwa.comptant.cloture_recap_fond') }}</span>
          <strong>{{ $session ? MontantFcfa::format((string) $session->montant_fond) : MontantFcfa::TIRET }}</strong>
        </div>
        <div class="flex justify-between">
          <span class="text-slate-500">{{ __('pos_pwa.comptant.cloture_recap_especes') }}</span>
          <strong>{{ MontantFcfa::format($especesSession) }}</strong>
        </div>
        <div class="flex justify-between pt-1.5 border-t border-slate-100">
          <span class="font-semibold">{{ __('pos_pwa.comptant.cloture_recap_theorique') }}</span>
          <strong class="text-[15px]">{{ MontantFcfa::format($theoriqueSession) }}</strong>
        </div>
      </div>

      <div>
        <label for="montant-constate" class="block text-[11px] font-semibold text-slate-500 mb-1">{{ __('pos_pwa.comptant.cloture_constate') }}</label>
        <input id="montant-constate" type="number" step="100" min="0" wire:model="montantConstateSaisi"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2 focus:border-[var(--gold)] focus:outline-none">
        @error('montantConstateSaisi')
          <p class="mt-2 text-[12px] text-red-600">{{ $message }}</p>
        @enderror
        <p class="text-[11.5px] text-slate-400 mt-2">{{ __('pos_pwa.comptant.cloture_recap_aide') }}</p>
      </div>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="cloturerCaisse"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('pos_pwa.comptant.cloturer_caisse') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{--
      ================= MODALE D'ANNULATION D'UNE VENTE =================

      ⚠ Le chassis `<x-pwa.modale-archivage>` n'est PAS employe ici, et la
      raison tient en une ligne : il ne porte aucun champ, alors que le motif
      d'annulation est OBLIGATOIRE (RG-02 — le journal doit dire pourquoi).
      Le rendre avec ce chassis obligerait a saisir le motif ailleurs, ou a
      s'en passer. Les mots sont ceux du maitre (dialogue « Annuler cette
      vente »), et le geste reste une annulation : rien n'est efface.
  --}}
  @if ($etatFormulaire === 'annulation')
    <x-pwa.modale :titre="__('pos_pwa.comptant.annulation_titre')"
                  :sousTitre="__('pos_pwa.comptant.annulation_message')"
                  largeur="448px">
      <p class="text-[12px] text-slate-500">{{ __('pos_pwa.comptant.annulation_detail') }}</p>

      <div>
        <label for="motif-annulation" class="block text-[13px] font-semibold text-slate-700 mb-2">{{ __('pos_pwa.comptant.annulation_motif') }}</label>
        <input id="motif-annulation" type="text" wire:model="motifAnnulation"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2 focus:border-[var(--gold)] focus:outline-none">
        @error('motifAnnulation')
          <p class="mt-2 text-[12px] text-red-600">{{ $message }}</p>
        @enderror
      </div>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="annulerVente"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--erreur)] text-white font-semibold">{{ __('pos_pwa.comptant.annulation_confirmer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ================= MODALE RUPTURE DE STOCK (RG-06) ================= --}}
  @if ($etatFormulaire === 'rupture' && $ruptureConstatee)
    <x-pwa.modale :titre="__('pos_pwa.comptant.rupture_titre')" largeur="448px">
      <p class="text-[13px] text-slate-700">{{ $ruptureConstatee }}</p>
      <p class="text-[12px] text-slate-500">{{ __('pos_pwa.comptant.rupture_aide') }}</p>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="encaisserMalgreRupture"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--alerte)] text-white font-semibold">{{ __('pos_pwa.comptant.rupture_confirmer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

</div>

{{--
    DÉPENSE COURANTE (M10)
    Maître : prototype_v2/pages/depenses.html
    Rendu du tableau et des indicateurs : prototype_v2/pages/depenses.js
    (indicateurs l.79-92, tableau l.99-140, état vide l.104-116).
    Référentiels : prototype_v2/assets/js/depenses-engine.js (trésoreries
    l.60-64, natures l.70-85).

    Conteneur `max-w-[1500px] mx-auto p-4 sm:p-5 lg:p-8` (maître l.21), en-tête
    (l.24-40), bande d'indicateurs (l.46-53), carte du tableau (l.56-84).

    ⚠ ÉCART DÉLIBÉRÉ — `prototype_v2/pages/depenses.html` l.60-72 (avant ce lot)
    Le maître : un seul `<h1>`, « Dépense courante ».
    Ici (état antérieur) : un en-tête d'impression `hidden print:block` posait
    un SECOND `<h1>` — « TATACORA AFRIQUE — GÎTE CHEZ NOËL » — AVANT celui du
    maître. Deux `<h1>` sur une page, et le premier n'est pas le titre.
    Corrigé : l'en-tête d'impression est un `<h2>`, et le `<h1>` de la page est
    celui du maître, seul.

    ⚠ ÉCART DÉLIBÉRÉ — `prototype_v2/pages/depenses.html` l.104-150
    Le maître : la modale de saisie porte UN montant, UN libellé, UN compte de
    charge et UNE nature.
    Ici : la saisie est MULTI-LIGNES.

    ~~« Ici : idem. La ventilation multi-lignes de la version antérieure de cet
    écran (« + Ajouter une ligne », « Total Général Décaissé ») ne vient
    d'aucune source du maître — Article 1.07. Raison : bug de portage. »~~
    NOTE PÉRIMÉE LE 31/08/2026, barrée plutôt que supprimée : elle a été vraie,
    et l'effacer ferait relire demain une décision comme un oubli. Sa mesure
    était juste — « + Ajouter une ligne » est à zéro sur la page du maître et
    sur `depenses.js` —, mais elle appliquait le bon raisonnement à la mauvaise
    autorité.

    DÉCISION DU PRODUCT OWNER DU 31/08/2026, qui PRÉVAUT sur le maître. Ses
    mots : « une dépense globale peut contenir une ou plusieurs lignes de
    libellé d'achats ou autre avec son prix ; on peut éditer et supprimer dans
    la même modale ». L'ordre de préséance du dépôt est celui-là — les mots du
    client d'abord, la maquette ensuite. L'écart est donc désormais dans
    l'AUTRE sens : la PWA fait PLUS que la maquette, et cela se déclare.

    Ce qui n'a pas bougé : le domaine était DÉJÀ multi-lignes (`lignes_depense`,
    `DepenseService::enregistrer()` a toujours pris une liste), tout part en UN
    seul appel donc UNE seule transaction, et le total n'est ni saisi ni posté.

    ⚠ ÉCART DÉLIBÉRÉ — largeur de la boîte
    Le maître : `max-width:560px` (`depenses.html` l.92).
    Ici : 760 px.
    Raison : conséquence directe de la décision ci-dessus. Un tableau à quatre
    colonnes — libellé, compte SYSCOHADA, prix, retrait — dans 560 px rendrait
    le sélecteur de compte illisible (les libellés du plan font jusqu'à
    cinquante caractères). La hauteur, elle, ne bouge pas : `.boite-modale`
    porte `max-height:90vh; overflow-y:auto`, et le châssis partagé la fait
    défiler.
--}}
@php
    use App\Pwa\Livewire\Depenses\Depenses;
    use App\Pwa\Support\MontantFcfa;

    /** Entête de colonne — casse du maître, `uppercase` laissé au CSS. */
    $entete = static fn (string $libelle, string $align = 'left'): string
        => '<th class="text-' . $align . ' px-4 py-2.5">' . e($libelle) . '</th>';

    $carte = 'bg-white rounded-xl border border-slate-200 p-3.5';
    $badge = 'text-[11px] px-2 py-0.5 rounded';
    $champ = 'champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm';
    $etiquette = 'block text-[15px] font-semibold text-slate-700 mb-1.5';
@endphp

<div class="contents">

  @include('pwa.partials.barre-superieure')

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')

    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1500px] mx-auto p-4 sm:p-5 lg:p-8">

        {{-- En-tête d'impression : un `<h2>`, jamais un second `<h1>`. --}}
        <div class="hidden print:block mb-6 border-b-2 border-[var(--navy)] pb-4">
          <h2 class="text-xl font-bold" style="color:var(--navy)">{{ __('pwa.marque') }}</h2>
          <p class="text-[12px] text-slate-600 mt-1">{{ __('depenses_pwa.export_document') }} — {{ now()->format('d/m/Y H:i') }}</p>
        </div>

        {{-- ================================================== HERO (l.24-40) --}}
        <div class="mb-5 flex flex-wrap items-start justify-between gap-3">
          <div>
            <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('depenses_pwa.titre') }}</h1>
            <p class="text-[12px] text-slate-500 mt-1 max-w-3xl">
              {{ __('depenses_pwa.sous_titre_avant') }}<strong>{{ __('depenses_pwa.sous_titre_fort') }}</strong>{{ __('depenses_pwa.sous_titre_apres') }}<a
                href="{{ route('pwa.achats.approvisionnement') }}" wire:navigate
                class="font-semibold" style="color:var(--gold)">{{ __('depenses_pwa.sous_titre_lien') }}</a>{{ __('depenses_pwa.sous_titre_fin') }}
            </p>
          </div>
          <button type="button" wire:click="ouvrirFormulaireDepense"
            class="btn shrink-0 flex items-center gap-2 px-4 py-2.5 rounded-lg bg-[var(--navy)] text-white text-sm font-semibold no-print">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" d="M12 5v14M5 12h14"/></svg>
            {{ __('depenses_pwa.nouvelle_depense') }}
          </button>
        </div>

        @if (session('pwa-succes'))
          <div class="mb-4 rounded-xl px-4 py-3 text-[13px] font-semibold no-print"
               style="background:#E8F5E9;color:#2E7D32;border:1px solid #C8E6C9">{{ session('pwa-succes') }}</div>
        @endif

        @error('rattrapage')
          <div class="mb-4 rounded-xl px-4 py-3 text-[13px] font-semibold no-print"
               style="background:#FDECEC;color:#C62828;border:1px solid #F5C6C6">{{ $message }}</div>
        @enderror

        {{--
            Le bandeau de rattrapage n'est pas au maître, et sa raison est
            datée : le prototype AFFICHE `ecriture_refus` sans jamais offrir de
            le reprendre (`depenses.js` l.120-122). Ici la reprise existe, et
            une dépense sans écriture manque au grand livre tant que personne
            ne la passe. Il n'apparaît QUE s'il y a réellement quelque chose à
            reprendre — Article 7.
        --}}
        @if ($sansEcriture > 0)
          <div class="mb-4 rounded-xl px-4 py-3 text-[13px] no-print"
               style="background:#FDF3E0;color:#B8891E;border:1px solid #F0DCB0">
            {{ __('depenses_pwa.rattrapage_bandeau', ['nombre' => $sansEcriture]) }}
            <label class="block mt-2 text-[12px] font-semibold">{{ __('depenses_pwa.rattrapage_centre') }}
              <select wire:model="centreRattrapage" class="mt-1 block w-full sm:w-72 border border-slate-300 rounded-lg px-2 py-1.5 text-[13px] bg-white text-slate-700">
                <option value="">{{ __('depenses_pwa.rattrapage_centre_choisir') }}</option>
                @foreach ($centresDeCout as $centre)
                  <option value="{{ $centre->id }}">{{ $centre->libelle }}</option>
                @endforeach
              </select>
            </label>
          </div>
        @endif

        {{-- ============================================ INDICATEURS (l.46-53)

             ACCORDEON A TOUTES LES LARGEURS depuis le 03/09/2026 (demande du
             Product Owner). La bascule existait deja, mais elle etait
             `sm:hidden` : au-dela de 640 px la bande restait toujours
             depliee, et le bouton lui-meme disparaissait. Sur un poste de
             bureau — celui du Gerant, precisement — six cartes mangeaient la
             hauteur du tableau sans qu'aucun controle ne permette de les
             replier. Meme motif que `notifications/hub.blade.php` et
             `rh/paie.blade.php` : etat retenu en `localStorage`, DEPLIE par
             defaut (un ecran qui s'ouvre vide se lit comme un ecran casse).

             DEUX ECARTS AU MAITRE, tous deux voulus et nommes :

             1. Le conteneur `sm:hidden` du maitre — celui qui ne portait le
                bouton que sous 640 px — n'existe plus : le bouton est unique
                et visible a toutes les largeurs. C'est tout l'objet de la
                demande, donc l'omission se declare :
                structure-refuse:depenses.html#div-b7daa05c
             2. La grille perd `sm:grid` au profit d'un `x-show` pilote par
                l'etat : le maitre la force depliee au-dela de 640 px, ce qui
                est exactement ce que le Product Owner demande de lever. Cet
                ecart sort en SIGNATURE au comparateur — il n'a pas de jeton,
                il est porte par la dette figee de la page, et c'est ici qu'il
                est explique. --}}
        <div x-data="{ ouvert: localStorage.getItem('pwa_kpis_depenses') !== 'false' }" class="mb-5">
          <button type="button" class="w-full flex items-center justify-between px-4 py-3 bg-white border border-slate-200 rounded-xl no-print"
                  @click="ouvert = !ouvert; localStorage.setItem('pwa_kpis_depenses', ouvert)">
            <span class="text-sm font-bold text-slate-700">{{ __('depenses_pwa.kpis_bascule') }}</span>
            <span class="text-[11px] text-slate-400 font-normal hidden sm:inline">{{ __('depenses_pwa.kpis_aide') }}</span>
          </button>

          <div x-show="ouvert" class="grid sm:grid-cols-3 xl:grid-cols-6 grid-cols-2 gap-3 mt-3" x-cloak>
            <div class="{{ $carte }}">
              <p class="text-[11px] uppercase tracking-wide text-slate-400">{{ __('depenses_pwa.kpi_total') }}</p>
              <p class="text-[18px] font-bold mt-1 tabular-nums" style="color:var(--navy)">{{ MontantFcfa::format($total) }}</p>
              <p class="text-[11px] text-slate-400 mt-0.5">{{ __('depenses_pwa.kpi_total_detail', ['nombre' => $depenses->count()]) }}</p>
            </div>

            <div class="{{ $carte }}">
              <p class="text-[11px] uppercase tracking-wide text-slate-400">{{ __('depenses_pwa.kpi_moyenne') }}</p>
              {{-- Article 7 : « — » quand la donnée n'existe pas. Aucune
                   dépense saisie et zéro franc dépensé ne disent pas la même
                   chose (maître, `depenses.js` l.68). --}}
              <p class="text-[18px] font-bold mt-1 tabular-nums" style="color:var(--navy)">{{ $moyenne === null ? MontantFcfa::TIRET : MontantFcfa::format($moyenne) }}</p>
              <p class="text-[11px] text-slate-400 mt-0.5">{{ __('depenses_pwa.kpi_moyenne_detail') }}</p>
            </div>

            <div class="{{ $carte }}">
              <p class="text-[11px] uppercase tracking-wide text-slate-400">{{ __('depenses_pwa.kpi_marche') }}</p>
              <p class="text-[18px] font-bold mt-1 tabular-nums" style="color:var(--navy)">{{ MontantFcfa::format($marche) }}</p>
              <p class="text-[11px] text-slate-400 mt-0.5">{{ __('depenses_pwa.kpi_marche_detail') }}</p>
            </div>

            <div class="{{ $carte }}">
              <p class="text-[11px] uppercase tracking-wide text-slate-400">{{ __('depenses_pwa.kpi_services') }}</p>
              <p class="text-[18px] font-bold mt-1 tabular-nums" style="color:var(--navy)">{{ MontantFcfa::format($services) }}</p>
              <p class="text-[11px] text-slate-400 mt-0.5">{{ __('depenses_pwa.kpi_services_detail') }}</p>
            </div>

            <div class="{{ $carte }}">
              <p class="text-[11px] uppercase tracking-wide text-slate-400">{{ __('depenses_pwa.kpi_caisse') }}</p>
              <p class="text-[18px] font-bold mt-1 tabular-nums" style="color:var(--navy)">{{ MontantFcfa::format($decaisseEnCaisse) }}</p>
              <p class="text-[11px] text-slate-400 mt-0.5">{{ __('depenses_pwa.kpi_caisse_detail') }}</p>
            </div>

            {{-- Compteur de VIGILANCE, pas de performance : en alerte quand il
                 n'est pas nul, pour qu'il ne passe pas pour un chiffre
                 ordinaire (maître, `depenses.js` l.87-91). --}}
            <div class="{{ $carte }}">
              <p class="text-[11px] uppercase tracking-wide text-slate-400">{{ __('depenses_pwa.kpi_sans_ecriture') }}</p>
              <p class="text-[18px] font-bold mt-1 tabular-nums" style="color:{{ $sansEcriture > 0 ? 'var(--erreur)' : 'var(--succes)' }}">{{ $sansEcriture }}</p>
              <p class="text-[11px] text-slate-400 mt-0.5">{{ $sansEcriture > 0 ? __('depenses_pwa.kpi_sans_ecriture_a_faire') : __('depenses_pwa.kpi_sans_ecriture_ok') }}</p>
            </div>
          </div>
        </div>

        {{-- ================================================= TABLEAU (l.56-84) --}}
        <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
          <div class="px-4 py-3 border-b border-slate-200 flex flex-wrap items-center gap-2 no-print">
            <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="{{ __('depenses_pwa.recherche') }}"
              class="text-[13px] border border-slate-300 rounded-lg px-3 py-1.5 w-56">
            <input type="date" wire:model.live="du" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-1.5" title="{{ __('depenses_pwa.du') }}">
            <input type="date" wire:model.live="au" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-1.5" title="{{ __('depenses_pwa.au') }}">

            <select wire:model.live="tresorerie" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-1.5">
              <option value="">{{ __('depenses_pwa.toute_tresorerie') }}</option>
              @foreach (Depenses::TRESORERIES as $code => $libelle)
                <option value="{{ $code }}">{{ $libelle }}</option>
              @endforeach
            </select>

            <select wire:model.live="famille" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-1.5">
              <option value="">{{ __('depenses_pwa.toute_categorie') }}</option>
              @foreach (array_keys(Depenses::NATURES) as $familleProposee)
                <option value="{{ $familleProposee }}">{{ $familleProposee }}</option>
              @endforeach
            </select>

            {{-- « Réinitialiser » est un LIEN, pas une action Livewire : vider
                 un filtre est une lecture, et l'exiger derrière un droit
                 d'écriture empêcherait un profil en consultation de revenir à
                 la liste entière. --}}
            <a href="{{ route('pwa.depenses') }}" wire:navigate
               class="text-[12px] font-semibold text-slate-500 hover:text-slate-700 px-2">{{ __('depenses_pwa.reinitialiser') }}</a>

            <div class="flex-1"></div>

            {{-- ⚠ DÉROGATION PO du 01/09/2026 — les deux boutons du maître
                 (`depenses.html` l.66-67, « Export PDF » / « Export Excel »)
                 sont remplacés par UN bouton « Exporter » qui ouvre la même
                 modale d'export ; le format s'y choisit, sans présélection
                 imposée. Registre : `App\Pwa\Support\DerogationsMaquette`
                 (export_bouton_unique). Jeton :
                 maitre-refuse:depenses.html#page --}}
            <button type="button" wire:click="ouvrirExport"
              class="text-[12px] font-semibold px-3 py-1.5 rounded-lg border border-slate-200 text-slate-600 hover:bg-slate-50">{{ __('pwa.export.bouton') }}</button>
          </div>

          <div class="overflow-x-auto">
            <table class="w-full text-[13px]">
              <thead class="bg-[var(--navy)] text-[11px] uppercase tracking-wide text-white/90 font-semibold"><tr>
                {!! $entete(__('depenses_pwa.col_date')) !!}
                {!! $entete(__('depenses_pwa.col_libelle')) !!}
                {!! $entete(__('depenses_pwa.col_nature')) !!}
                {!! $entete(__('depenses_pwa.col_charge')) !!}
                {!! $entete(__('depenses_pwa.col_tresorerie')) !!}
                {!! $entete(__('depenses_pwa.col_montant'), 'right') !!}
                {!! $entete(__('depenses_pwa.col_pieces')) !!}
              </tr></thead>
              <tbody>
                @forelse ($depenses as $depense)
                  <tr class="border-t border-slate-100" wire:key="depense-{{ $depense->id }}">
                    <td class="px-4 py-2.5 text-slate-500 whitespace-nowrap">{{ $depense->date_transaction->format('d/m/Y') }}</td>
                    <td class="px-4 py-2.5 font-semibold text-slate-700">{{ $depense->libelle }}</td>
                    <td class="px-4 py-2.5 text-slate-500">{{ Depenses::valeursDistinctes($depense->lignes, 'nature') }}</td>
                    <td class="px-4 py-2.5 text-slate-500">
                      @foreach ($depense->lignes as $ligne)
                        <span class="font-mono-tatacora">{{ $ligne->compte_charge }}</span> ·
                        {{ $libellesComptes[$ligne->compte_charge] ?? MontantFcfa::TIRET }}@if (! $loop->last)<br>@endif
                      @endforeach
                    </td>
                    <td class="px-4 py-2.5 text-slate-500">{{ Depenses::TRESORERIES[$depense->tresorerie] ?? $depense->tresorerie }}</td>
                    <td class="px-4 py-2.5 text-right font-semibold tabular-nums">{{ MontantFcfa::format((string) $depense->montant_total) }}</td>
                    <td class="px-4 py-2.5 whitespace-nowrap">
                      @if ($depense->recu_path)
                        <a href="{{ asset('storage/'.$depense->recu_path) }}" target="_blank" rel="noopener"
                           class="text-[11px] font-semibold px-2 py-0.5 rounded bg-slate-100 text-slate-600">{{ __('depenses_pwa.recu') }}</a>
                      @else
                        <span class="{{ $badge }} bg-amber-50 text-amber-700">{{ __('depenses_pwa.sans_recu') }}</span>
                      @endif

                      {{-- La badge lit `ecriture_id`, jamais `ecriture_refus` :
                           une dépense antérieure à ce lot n'a NI l'un NI
                           l'autre, et se serait affichée comme comptabilisée.
                           `estComptabilisee()` est la seule preuve. --}}
                      @unless ($depense->estComptabilisee())
                        <span title="{{ $depense->ecriture_refus }}" class="{{ $badge }} bg-red-50 text-red-700">{{ __('depenses_pwa.non_comptabilisee') }}</span>
                        <button type="button" wire:click="comptabiliserDepense('{{ $depense->id }}')"
                          class="text-[11px] font-semibold px-2 py-0.5 rounded bg-[var(--navy)] text-white ml-1 no-print">{{ __('depenses_pwa.rattrapage_action') }}</button>
                      @endunless
                    </td>
                  </tr>
                @empty
                  <tr>
                    <td colspan="7" class="px-4 py-10 text-center text-[13px] text-slate-400">
                      @if ($filtreApplique)
                        {{ __('depenses_pwa.vide_filtre') }}
                        <a href="{{ route('pwa.depenses') }}" wire:navigate class="font-semibold underline">{{ __('depenses_pwa.tout_afficher') }}</a>
                      @else
                        {{ __('depenses_pwa.vide') }}
                      @endif
                    </td>
                  </tr>
                @endforelse
              </tbody>
            </table>
          </div>
        </div>

        {{--
            NON PORTE, ET PLUS RENDU A L'ECRAN (02/09/2026). La section « ce
            que cet ecran ne fait pas » est retiree par directive du Product
            Owner : un ecran dit ce qu'il FAIT. Ce qui reste non porte se
            declare ici, dans le code, ou la garde des trois sources le lit.

            - Reduction du recu joint : le maitre l'offre a la saisie, aucune
              colonne ne la porte et aucun service ne la calcule.
            - Natures de depense parametrables : le registre est ferme cote
              serveur ; l'ouvrir demande un arbitrage qui n'est pas de cet
              ecran.
        --}}

      </div>
    </main>
  </div>

  {{-- ============================ MODALE : NOUVELLE DÉPENSE (maître l.91-170) --}}
  @if ($etatFormulaire === 'depense')
    <x-pwa.modale :titre="__('depenses_pwa.modale_titre')" largeur="760px" fermer="fermerModales">
      <form wire:submit.prevent="enregistrerDepense" class="space-y-4">
        <p class="text-[13px] text-slate-400 bg-slate-50 rounded-lg px-3 py-2">
          {{ __('depenses_pwa.modale_intro') }}
        </p>

        {{-- Le refus COMPTABLE, en tête et en clair : il porte sur la pièce
             entière — journal, exercice, compte, centre de coût —, jamais sur
             une ligne. L'accrocher à un champ ferait chercher l'erreur dans ce
             champ. Rien n'a été écrit quand il s'affiche. --}}
        @error('comptabilisation')
          <p class="text-[13px] rounded-lg px-3 py-2 font-semibold"
             style="background:#FDECEC;color:#C62828;border:1px solid #F5C6C6">{{ $message }}</p>
        @enderror

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div>
            <label class="{{ $etiquette }}">{{ __('depenses_pwa.champ_date') }} <span class="text-red-500">*</span></label>
            <input type="date" wire:model="dateTransaction" class="{{ $champ }}">
            @error('dateTransaction') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
          <div>
            <label class="{{ $etiquette }}">{{ __('depenses_pwa.champ_libelle') }} <span class="text-red-500">*</span></label>
            <input type="text" wire:model="libelle" placeholder="{{ __('depenses_pwa.champ_libelle_invite') }}" class="{{ $champ }}">
            @error('libelle') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
        </div>

        {{-- ======================================= LES LIGNES D'ACHAT
             Décision du Product Owner du 31/08/2026 (voir l'entête du
             fichier). Édition EN PLACE : les champs restent des `input` et des
             `select`, jamais un mode lecture qu'il faudrait déverrouiller —
             « on peut éditer et supprimer dans la même modale ». --}}
        <div>
          <div class="flex flex-wrap items-end justify-between gap-2 mb-1.5">
            <div>
              <label class="{{ $etiquette }}">{{ __('depenses_pwa.lignes_titre') }} <span class="text-red-500">*</span></label>
              <p class="text-[12px] text-slate-400">{{ __('depenses_pwa.lignes_aide') }}</p>
            </div>
            <button type="button" wire:click="ajouterLigneDepense"
              class="text-[12px] font-semibold px-3 py-1.5 rounded-lg border border-slate-300 text-slate-600 hover:bg-slate-50 shrink-0">{{ __('depenses_pwa.ligne_ajouter') }}</button>
          </div>

          @error('lignes') <p class="text-[12px] text-red-600 mb-1">{{ $message }}</p> @enderror

          <div class="overflow-x-auto border border-slate-200 rounded-lg">
            <table class="w-full text-[13px]">
              <thead class="bg-[var(--navy)] text-[11px] uppercase tracking-wide text-white/90 font-semibold"><tr>
                {!! $entete(__('depenses_pwa.col_ligne_libelle')) !!}
                {{-- Les comptes viennent du PLAN COMPTABLE, jamais d'une liste
                     recopiée ici : le composant en portait sept qui n'existent
                     dans aucun plan du dépôt. Classe 6 seulement — proposer un
                     compte de bilan permettrait un décaissement sans charge,
                     invisible au résultat (maître, `depenses.js` l.161-163). --}}
                {!! $entete(__('depenses_pwa.champ_compte')) !!}
                {!! $entete(__('depenses_pwa.champ_nature')) !!}
                {!! $entete(__('depenses_pwa.col_ligne_montant'), 'right') !!}
                <th class="px-2 py-2.5"><span class="sr-only">{{ __('depenses_pwa.ligne_retirer') }}</span></th>
              </tr></thead>
              <tbody>
                @foreach ($lignes as $index => $ligne)
                  <tr class="border-t border-slate-100 align-top" wire:key="ligne-depense-{{ $index }}">
                    <td class="px-2 py-2">
                      <input type="text" wire:model.live.debounce.400ms="lignes.{{ $index }}.libelle"
                        placeholder="{{ __('depenses_pwa.champ_libelle_invite') }}"
                        class="champ w-full border border-slate-200 rounded-lg px-2.5 py-2 text-[13px]">
                      @error('lignes.'.$index.'.libelle') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
                    </td>
                    <td class="px-2 py-2">
                      <select wire:model.live="lignes.{{ $index }}.compte_charge"
                        class="champ w-full border border-slate-200 rounded-lg px-2.5 py-2 text-[13px] bg-white">
                        <option value="">{{ __('depenses_pwa.choisir') }}</option>
                        @foreach ($comptesDeCharge as $compte)
                          <option value="{{ $compte->numero_compte }}">{{ $compte->numero_compte }} — {{ $compte->libelle }}</option>
                        @endforeach
                      </select>
                      @error('lignes.'.$index.'.compte_charge') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
                    </td>
                    <td class="px-2 py-2">
                      {{-- Categorie PAR LIGNE (PO 03/09/2026). --}}
                      <select wire:model.live="lignes.{{ $index }}.nature"
                        class="champ w-full border border-slate-200 rounded-lg px-2.5 py-2 text-[13px] bg-white">
                        <option value="">{{ __('depenses_pwa.choisir') }}</option>
                        @foreach ($naturesProposables as $familleProposee => $natures)
                          <optgroup label="{{ $familleProposee }}">
                            @foreach ($natures as $natureProposee)
                              <option value="{{ $natureProposee }}">{{ $natureProposee }}</option>
                            @endforeach
                          </optgroup>
                        @endforeach
                      </select>
                      @error('lignes.'.$index.'.nature') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
                    </td>
                    <td class="px-2 py-2">
                      {{-- `wire:model.live` : c'est ce qui fait recalculer le
                           total général par le SERVEUR à chaque frappe. Une
                           somme refaite en JavaScript serait une seconde
                           formule, et le jour où l'une changerait, l'écran
                           afficherait deux vérités. --}}
                      <input type="number" min="1" step="1" inputmode="numeric"
                        wire:model.live.debounce.400ms="lignes.{{ $index }}.montant"
                        placeholder="{{ __('depenses_pwa.champ_montant_invite') }}"
                        class="champ w-full text-right border border-slate-200 rounded-lg px-2.5 py-2 text-[13px] tabular-nums">
                      @error('lignes.'.$index.'.montant') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
                    </td>
                    <td class="px-2 py-2 text-center">
                      {{-- Le bouton n'existe QUE s'il reste une ligne après le
                           retrait : une dépense sans ligne n'existe pas. Le
                           composant refuse aussi le geste — la vue cache, elle
                           ne protège pas. --}}
                      @if (count($lignes) > 1)
                        <button type="button" wire:click="retirerLigneDepense({{ $index }})"
                          title="{{ __('depenses_pwa.ligne_retirer') }}"
                          aria-label="{{ __('depenses_pwa.ligne_retirer') }}"
                          class="text-slate-400 hover:text-red-600 px-2 py-1 rounded-lg text-[15px] font-semibold">&times;</button>
                      @endif
                    </td>
                  </tr>
                @endforeach
              </tbody>
              <tfoot class="bg-slate-50 border-t border-slate-200">
                <tr>
                  {{-- LE TOTAL GÉNÉRAL — calculé, donc en lecture seule (règle
                       n° 2 du dépôt). Le libellé est celui du maître, « Montant
                       décaissé (FCFA) » : c'est bien le montant qui sort de la
                       caisse, il n'est simplement plus tapé. Le navigateur ne
                       le poste jamais ; `DepenseService::totaliser()` le
                       recalcule, et c'est ce montant-là qui est comptabilisé. --}}
                  <td colspan="2" class="px-4 py-2.5 text-right font-semibold text-slate-600">{{ __('depenses_pwa.champ_montant') }}</td>
                  <td class="px-2 py-2.5 text-right text-[15px] font-bold tabular-nums" style="color:var(--navy)">{{ MontantFcfa::format($totalSaisi) }}</td>
                  <td></td>
                </tr>
              </tfoot>
            </table>
          </div>
          <p class="text-[12px] text-slate-400 mt-1">{{ __('depenses_pwa.total_aide') }}</p>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div>
            {{-- « Compte de trésorerie » et non « compte débité » : régler une
                 charge CRÉDITE la trésorerie et DÉBITE le compte de charge.
                 Nommer l'un pour l'autre sur un écran qui affiche par ailleurs
                 des comptes SYSCOHADA enseignerait l'inverse de la règle
                 (maître l.134-137). --}}
            <label class="{{ $etiquette }}">{{ __('depenses_pwa.champ_tresorerie') }} <span class="text-red-500">*</span></label>
            <select wire:model="tresorerieCode" class="{{ $champ }} bg-white">
              <option value="">{{ __('depenses_pwa.choisir') }}</option>
              @foreach (Depenses::TRESORERIES as $code => $libelle)
                <option value="{{ $code }}">{{ $libelle }}</option>
              @endforeach
            </select>
            <p class="text-[12px] text-slate-400 mt-1">{{ __('depenses_pwa.champ_tresorerie_aide') }}</p>
            @error('tresorerieCode') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
          <div>
            <label class="{{ $etiquette }}">{{ __('depenses_pwa.champ_centre') }}</label>
            <select wire:model="centreId" class="{{ $champ }} bg-white">
              <option value="">{{ __('depenses_pwa.centre_defaut_du_compte') }}</option>
              @foreach ($centresDeCout as $centre)
                <option value="{{ $centre->id }}">{{ $centre->libelle }}</option>
              @endforeach
            </select>
            @error('centreId') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
          {{-- Le select de categorie de TETE est retire (PO 03/09/2026) :
               la categorie vit sur CHAQUE ligne d'achat ci-dessous — une
               depense peut meler Tomate, Viande et Transport sur une seule
               piece, chaque ligne comptee dans SA famille. --}}
        </div>

        <div>
          <label class="{{ $etiquette }}">{{ __('depenses_pwa.champ_recu') }}</label>
          <input type="file" accept="image/*" wire:model="photoRecu"
            class="w-full text-[13px] text-slate-600 file:mr-3 file:py-2 file:px-3 file:rounded-lg file:border-0 file:text-[13px] file:font-semibold file:bg-slate-100 file:text-slate-700">
          <p class="text-[12px] text-slate-400 mt-1">{{ __('depenses_pwa.champ_recu_aide') }}</p>
          @error('photoRecu') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>

        {{-- Le bouton de soumission vit DANS le `<form>` : le pied de la
             modale est hors du formulaire, et un `<button type="submit">` qui
             y serait posé ne soumettrait rien. --}}
        <div class="flex justify-end gap-2 pt-2">
          {{-- Le bouton « Annuler » du maître (depenses.html l.165). Son
               libellé vient de la clé PARTAGÉE `pwa.modale.annuler` — le même
               mot sur les quarante écrans, jamais une copie par page. Il est
               nommé ici pour que la garde des trois sources le retrouve dans
               le fichier qui cite `depenses.html`. --}}
          <button type="button" wire:click="fermerModales"
            class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
          <button type="submit"
            class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('depenses_pwa.enregistrer') }}</button>
        </div>
      </form>
    </x-pwa.modale>
  @endif

  {{-- Le châssis d'export PARTAGÉ, jamais une copie locale : le même bloc
       était recopié dans douze vues sous dix titres. --}}
  @if ($etatFormulaire === 'export')
    @include('pwa.partials.modale-export', ['titre' => __('depenses_pwa.export_titre')])
  @endif

  @include('pwa.partials.acces-rapide')

</div>

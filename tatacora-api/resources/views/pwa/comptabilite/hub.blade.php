{{--
    Hub Comptabilité SYSCOHADA — maître : `prototype_v2/pages/m10-syscohada.html`.

    Conteneur `max-w-[1600px] mx-auto p-5 lg:p-8` (l.28), en-tête
    `mb-5 flex flex-wrap items-start justify-between gap-3` (l.30), zone
    d'alerte globale (l.51), bandeau de six indicateurs
    `grid grid-cols-2 lg:grid-cols-6 gap-3 mb-5` (l.52), barre de dix onglets
    `flex flex-wrap gap-1.5 mb-4` (l.54-65), barre de filtres
    `bg-white rounded-xl border border-slate-200 p-3.5 mb-4` (l.67) et zone de
    contenu (l.90).

    ## Les styles d'onglet du maître vivent dans un `<style>` de PAGE

    `m10-syscohada.html` l.12-13 :
      `.onglet-actif { background: var(--navy); color: #fff; }`
      `.onglet-inactif { background: #fff; color: #64748B; border: 1px solid #E2E8F0; }`
    Ce `<head>` est partagé par toute la coquille PWA (`layouts/pwa.blade.php`),
    et y ajouter deux règles pour un seul écran ferait porter à toutes les pages
    une feuille qu'une seule utilise. Les mêmes valeurs sont donc posées en
    attribut `style`, au caractère près — l'effet de rendu est identique, et
    aucun `@apply` ni aucune approximation d'échelle n'intervient.
    Idem pour `.solde-intermediaire` (l.15) et `.solde-final` (l.16).

    Les cinq écarts — onglet de saisie, onglet actif par défaut, onglet
    immobilisations, trois filtres, export — sont motivés au complet dans
    `App\Pwa\Livewire\Comptabilite\Hub`, chacun avec son fichier, sa ligne et
    sa raison.
--}}
@php
    use App\Pwa\Livewire\Comptabilite\Hub;
    use App\Pwa\Support\MontantFcfa;

    // Classes d'onglets : directive PO du 01/09/2026, UN SEUL AUTEUR —
    // voir le docblock de `App\Pwa\Support\Onglets`. Les deux anciennes
    // chaines de style inline (`--navy`/#64748B) disaient la meme chose en
    // CSS embarque ; le registre unique les remplace.
    $classeOnglet = static fn (bool $actif): string => \App\Pwa\Support\Onglets::classes($actif);
@endphp
<div class="contents">

  @include('pwa.partials.barre-superieure')
  

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        <div class="mb-5 flex flex-wrap items-start justify-between gap-3">
          <div>
            <div class="flex items-center gap-2.5">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M9 17V7m4 10V11m4 6V9M4 21h16a1 1 0 001-1V4a1 1 0 00-1-1H4a1 1 0 00-1 1v16a1 1 0 001 1z"/></svg>
              <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('pwa.comptabilite.titre_hub') }}</h1>
            </div>
            <p class="text-[15px] text-slate-500 mt-1.5">
              Système Normal. Une écriture validée est <strong>immuable</strong> : la seule
              correction est la contre-passation.
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            {{-- Le sélecteur d'exercice prend la place du `#bandeau-exercice`
                 du maître (l.46), qui affiche une année sans permettre d'en
                 changer : son jeu de démonstration n'en contient qu'une. Voir
                 `pwa/comptabilite/partials/socle.blade.php` pour l'écart
                 complet et sa raison. --}}
            <select wire:model.live="exerciceId" aria-label="{{ __('pwa.comptabilite.exercice') }}"
                    class="text-[13px] px-3.5 py-2 rounded-lg bg-white border border-slate-300">
              <option value="">{{ __('pwa.comptabilite.exercice_choisir') }}</option>
              @foreach ($exercices as $unExercice)
                <option value="{{ $unExercice->id }}">{{ __('pwa.comptabilite.exercice') }} {{ $unExercice->annee }}</option>
              @endforeach
            </select>
            @if ($indicateurs !== null)
              <div class="text-[13px] px-3.5 py-2 rounded-lg bg-white border border-slate-300">
                {{-- ÉCART DÉLIBÉRÉ — `m10-syscohada-init.js` l.27
                     Le maître : « N pièce(s) · M brouillon(s) ».
                     Ici : « ligne(s) », pas « pièce(s) ».
                     Raison : PA-52 — le schéma ne porte AUCUN identifiant de
                     pièce, et `ecritures_comptables` est une table de LIGNES.
                     Le serveur ne peut donc compter que des lignes. Écrire
                     « 12 pièces » sur 12 lignes annoncerait douze documents
                     là où il y en a six : un décompte faux mais plausible. --}}
                {{ $indicateurs->statuts->validee + $indicateurs->statuts->brouillon }} ligne(s)
                @if ($indicateurs->statuts->brouillon > 0)
                  · <span class="text-amber-700">{{ $indicateurs->statuts->brouillon }} brouillon(s)</span>
                @endif
              </div>
            @endif
          </div>
        </div>

        {{-- La cloture d'exercice est IRREVERSIBLE : sa confirmation ne
             doit pas se perdre. `Hub::cloturerExercice()` flashait
             `pwa-succes` depuis toujours et cette vue ne le rendait PAS
             (03/09/2026) — le geste avait lieu, l'ecran restait muet, ce
             qui invite a le refaire. --}}
        @include('pwa.partials.toast-succes')

        {{-- Navigation temporelle et statut de l'exercice consulté (lot 3,
             20/10/2026) : N-1 et N+1 en un clic ; un exercice en clôture ou
             clôturé le DIT — les services refusent déjà d'y écrire, l'écran
             ne laisse pas croire le contraire. --}}
        @if ($exercice !== null)
          @php
            $exercicePrecedent = $exercices->firstWhere('annee', $exercice->annee - 1);
            $exerciceSuivant = $exercices->firstWhere('annee', $exercice->annee + 1);
          @endphp
          <div id="navigation-exercices" class="flex flex-wrap items-center gap-2 mb-3">
            @if ($exercicePrecedent !== null)
              <a href="{{ route('pwa.comptabilite.hub', ['exercice' => $exercicePrecedent->id, 'onglet' => $ongletActif]) }}" wire:navigate
                 class="text-[13px] px-3 py-1.5 rounded-lg border border-slate-300 bg-white hover:bg-slate-50">← {{ __('comptabilite_pwa.exercice_precedent', ['annee' => $exercicePrecedent->annee]) }}</a>
            @endif
            @if ($exerciceSuivant !== null)
              <a href="{{ route('pwa.comptabilite.hub', ['exercice' => $exerciceSuivant->id, 'onglet' => $ongletActif]) }}" wire:navigate
                 class="text-[13px] px-3 py-1.5 rounded-lg border border-slate-300 bg-white hover:bg-slate-50">{{ __('comptabilite_pwa.exercice_suivant', ['annee' => $exerciceSuivant->annee]) }} →</a>
            @endif
          </div>
          @if ($exercice->statut === 'en_cloture')
            <div id="bandeau-statut-exercice" class="rounded-xl p-3.5 mb-4" style="background:#FFFBEB;border:1px solid #FDE68A">
              <p class="text-[13px]" style="color:#78350F">{{ __('comptabilite_pwa.bandeau_en_cloture', ['annee' => $exercice->annee]) }}</p>
            </div>
          @elseif ($exercice->statut === 'cloture')
            <div id="bandeau-statut-exercice" class="rounded-xl p-3.5 mb-4" style="background:#F1F5F9;border:1px solid #CBD5E1">
              <p class="text-[13px]" style="color:#334155">{{ __('comptabilite_pwa.bandeau_cloture', ['annee' => $exercice->annee]) }}</p>
            </div>
          @endif
        @endif

        @if ($indicateurs !== null && ! $indicateurs->equilibre)
          {{-- `#alerte-globale` (l.51 / init l.56) — les deux phrases du maître. --}}
          <div class="rounded-xl p-3.5 mb-4" style="background:#FEF2F2;border:1px solid #FECACA">
            <p class="text-[13px]" style="color:#7F1D1D">
              <strong>{{ __('pwa.comptabilite.desequilibre_titre') }}</strong>
              Aucun état financier n'est exploitable tant que l'écart subsiste. Vérifiez la balance générale.
            </p>
          </div>
        @endif

        @if ($indicateurs !== null)
          @php
              // Les six indicateurs, dans l'ordre du maître (init l.42-52), avec
              // ses libellés et ses mentions de code de liasse.
              $accentSiNegatif = fn (string $montant): string => MontantFcfa::estNegatif($montant) ? 'text-red-600' : '';
              $cartes = [
                  ["Chiffre d'affaires", MontantFcfa::format($indicateurs->chiffreAffaires), '', 'XB — hors TVA'],
                  ['Valeur ajoutée', MontantFcfa::format($indicateurs->valeurAjoutee), '', 'XC'],
                  ['Excédent brut', MontantFcfa::format($indicateurs->excedentBrut), $accentSiNegatif($indicateurs->excedentBrut), 'XD — EBE'],
                  ['Résultat net', MontantFcfa::format($indicateurs->resultatNet),
                      MontantFcfa::estNegatif($indicateurs->resultatNet) ? 'text-red-600' : 'text-emerald-600',
                      $indicateurs->impotNonComptabilise ? 'XI — avant impôt' : 'XI'],
                  ['Trésorerie', MontantFcfa::format($indicateurs->tresorerie), $accentSiNegatif($indicateurs->tresorerie), 'Classe 5'],
                  ['Total bilan', MontantFcfa::format($indicateurs->totalBilan),
                      $indicateurs->equilibre ? '' : 'text-red-600',
                      $indicateurs->equilibre ? 'Équilibré' : 'DÉSÉQUILIBRÉ'],
              ];
          @endphp
          <div class="grid grid-cols-2 lg:grid-cols-6 gap-3 mb-5">
            @foreach ($cartes as [$libelle, $valeur, $accent, $detail])
              <div class="bg-white rounded-xl border border-slate-200 p-3.5">
                <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ $libelle }}</div>
                <div class="text-[17px] font-bold mt-1 {{ $accent }}" @if ($accent === '') style="color:var(--navy)" @endif>{{ $valeur }}</div>
                <div class="text-[11px] text-slate-400 mt-0.5">{{ $detail }}</div>
              </div>
            @endforeach
          </div>
        @endif

        {{-- Les DIX onglets du maître (l.55-64), TOUS servis. « saisie » et
             « immo » ont longtemps été omis (leur refus était daté dans
             `Hub`) ; la vague E du 01/09/2026 a livré la saisie d'écriture et
             les immobilisations, et l'omission est levée — le commentaire qui
             l'affirmait encore a été repris le 02/09/2026 (PA-144 : un motif
             périmé transforme une décision en oubli). --}}
        <div class="flex flex-wrap gap-1.5 mb-4">
          @foreach (Hub::ONGLETS as $cle => $libelle)
            <button type="button" wire:click="$set('onglet', '{{ $cle }}')"
                    class="{{ $classeOnglet($cle === $ongletActif) }}">{{ $libelle }}</button>
          @endforeach
        </div>

        <div class="bg-white rounded-xl border border-slate-200 p-3.5 mb-4">
          <div class="flex flex-wrap gap-2.5 items-center">
            <label for="f-journal" class="text-[12px] text-slate-500">{{ __('pwa.comptabilite.filtre_journal') }}</label>
            <select id="f-journal" wire:model.live="journalId" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <option value="">{{ __('pwa.comptabilite.filtre_tous_journaux') }}</option>
              @foreach ($journaux as $unJournal)
                <option value="{{ $unJournal->id }}">{{ $unJournal->code }} — {{ $unJournal->libelle }}</option>
              @endforeach
            </select>

            {{-- La case « Inclure les brouillons » du maître (l.93) rendue en
                 trois états : le serveur en admet trois
                 (`EcritureComptable::FILTRES_STATUT`), et une case à cocher
                 n'en dirait que deux — « brouillons seuls » serait indemandable. --}}
            <label for="f-brouillons" class="text-[12px] text-slate-600">{{ __('pwa.comptabilite.filtre_brouillons') }}</label>
            <select id="f-brouillons" wire:model.live="filtreStatut" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <option value="toutes">{{ __('pwa.comptabilite.statut_toutes') }}</option>
              <option value="validee">{{ __('pwa.comptabilite.statut_validee') }}</option>
              <option value="brouillon">{{ __('pwa.comptabilite.statut_brouillon') }}</option>
            </select>

            <a href="{{ route('pwa.comptabilite.hub', ['exercice' => $exercice?->id, 'onglet' => $ongletActif]) }}" wire:navigate
               class="text-[12px] px-3 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.comptabilite.filtre_reinitialiser') }}</a>

            {{-- « Excel » et « PDF » (maquette l.47-48) — portés le
                 01/09/2026 via la modale d'export UNIFIÉE, sur l'onglet
                 Journal seul : voir `Hub::ouvrirExport()`/`genererExport()`. --}}
            <button type="button" wire:click="ouvrirExport"
                    class="text-[12px] px-3 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.export.bouton') }}</button>

            {{-- La mention n'est vraie QUE sur les onglets de consultation :
                 l'afficher sous « Passer écriture », Immobilisations ou
                 Clôtures — qui ÉCRIVENT depuis la vague E — dirait le
                 contraire de ce que l'écran fait (02/09/2026, passage
                 navigateur). --}}
            @unless (in_array($ongletActif, ['saisie', 'immo', 'clotures'], true))
              <span class="ml-auto text-[12px] text-slate-400">{{ __('pwa.comptabilite.lecture_seule') }}</span>
            @endunless
          </div>
        </div>

        @error('export')
          <div class="px-4 py-2.5 mb-4 rounded-lg text-[13px] no-print"
               style="background:#FFFBEB;color:#78350F;border:1px solid #FDE68A">{{ $message }}</div>
        @enderror

        {{--
            LES DIX PANNEAUX D'ONGLET, TOUS RENDUS À CHAQUE GET (02/09/2026, G5).

            L'onglet actif est visible et porte ses données réelles, comme
            avant ; les neuf autres sont `hidden` et rendent le SQUELETTE de
            leur tableau — l'entête du maître (même auteur que le rendu
            complet, voir `onglets/_entetes`) au-dessus d'une ligne unique qui
            dit pourquoi il est vide. Un panneau inactif ne calcule RIEN :
            afficher des chiffres qu'aucun Service n'a produits serait
            PA-59/60/61, et calculer les huit états à chaque GET paierait huit
            fois pour un seul onglet regardé. Cliquer un onglet reste un
            aller-retour Livewire qui recharge la page avec cet onglet actif.

            `saisie` n'a pas de tableau de consultation (sa grille vit dans la
            modale « Passer écriture ») : son panneau inactif est vide.
        --}}
        <div>
          @foreach (Hub::ONGLETS as $cleOnglet => $libelleOnglet)
            @php($estOngletActif = $cleOnglet === $ongletActif)
            <div @if (! $estOngletActif) hidden @endif>
              @if ($estOngletActif && $exercice === null)
                @include('pwa.comptabilite.partials.aucun-exercice')
              @elseif ($estOngletActif && array_key_exists('refusDeVolume', $contenu))
                <div class="rounded-lg px-4 py-3 text-[15px] font-semibold" style="background:#FDECEC;color:#C62828">
                  {{ $contenu['refusDeVolume'] }}
                </div>
              @elseif ($estOngletActif)
                @include('pwa.comptabilite.onglets.' . $cleOnglet, $contenu)
              @elseif ($cleOnglet !== 'saisie')
                @include('pwa.comptabilite.onglets.' . $cleOnglet, [
                    'squelette' => true,
                    'messageSquelette' => $exercice === null
                        ? __('pwa.comptabilite.aucun_exercice_titre')
                        : __('pwa.comptabilite.onglet_non_ouvert'),
                ])
              @endif
            </div>
          @endforeach
        </div>

        {{--
            LES ONZE TUILES DE `prototype_v2/pages/m10-comptabilite.html` (l.74).

            La page d'atterrissage du maître se déclare elle-même remplacée par
            « Comptabilité SYSCOHADA » (l.19-24), c'est-à-dire par CETTE page :
            ses tuiles y vivent donc, plutôt que sous une seconde URL qui ferait
            deux hubs M10 pour un seul maître fonctionnel.

            Elles ne sont pas décoratives : jusqu'au 31/08/2026, `MenuLateral`
            n'avait qu'UNE entrée M10 et les onze écrans servis sous
            `/pwa/comptabilite/…` n'étaient atteignables qu'en tapant leur URL.

            Structure du maître, au caractère près : `grid grid-cols-1
            lg:grid-cols-2 gap-4`, carte `carte-hover bg-white rounded-xl border
            border-slate-200 p-5 flex items-start gap-4`, pastille d'icône
            `w-10 h-10 rounded-lg bg-[var(--navy)]/5`, titre `font-bold
            text-[15px] text-slate-800`, description `text-[13px] text-slate-500
            mt-1 leading-relaxed`, chevron `#9CA3AF`.

            ⚠ L'ICÔNE de chaque tuile n'est PAS transcrite. Le maître pose onze
            tracés SVG distincts dans son `<script>` (l.75-104) ; les recopier
            ici sans les mesurer produirait le défaut PA-143 — un point de trop
            sur un tracé, invisible à la relecture. La pastille garde donc la
            même géométrie et porte le chevron seul. Écart nommé, non dissimulé.
        --}}
        {{-- Le sous-titre du maître (`m10-comptabilite.html` l.37), qui est ce
             qui introduit ses tuiles. Aucun titre de section n'est inventé :
             le maître n'en pose pas au-dessus de sa grille. --}}
        <p class="text-[15px] text-slate-500 mt-8 mb-3">{{ __('pwa.comptabilite.pilotage_intro') }}</p>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          @foreach (Hub::TUILES as [$titreTuile, $descriptionTuile, $routeTuile])
            <a href="{{ route($routeTuile, ['exercice' => $exercice?->id, 'statut' => $filtreStatut]) }}" wire:navigate
               class="carte-hover bg-white rounded-xl border border-slate-200 p-5 flex items-start gap-4">
              <div class="w-10 h-10 rounded-lg bg-[var(--navy)]/5 flex items-center justify-center shrink-0">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M9 18l6-6-6-6"/></svg>
              </div>
              <div class="flex-1 min-w-0">
                <span class="block font-bold text-[15px] text-slate-800">{{ $titreTuile }}</span>
                <span class="block text-[13px] text-slate-500 mt-1 leading-relaxed">{{ $descriptionTuile }}</span>
              </div>
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" stroke-width="2" class="shrink-0 mt-1"><path stroke-linecap="round" stroke-linejoin="round" d="M9 18l6-6-6-6"/></svg>
            </a>
          @endforeach
        </div>

      </div>
    </main>
  </div>

  {{-- ==================================================================
       MODALE « Passer écriture » — maître : `m10-syscohada.js` vueSaisie()
       l.68-137. Transcrit dans la modale, jamais toujours-dans-le-DOM :
       doctrine `RefuseLaSaisie` (voir `onglets/saisie.blade.php`).
       ================================================================== --}}
  @if ($etatFormulaire === 'piece')
    <x-pwa.modale :titre="__('comptabilite_pwa.modale_piece_titre')" largeur="900px">
      <form wire:submit.prevent="enregistrerPieceBrouillon" class="space-y-4">
        @error('piece')
          <p class="text-[13px] rounded-lg px-3 py-2 font-semibold"
             style="background:#FDECEC;color:#C62828;border:1px solid #F5C6C6">{{ $message }}</p>
        @enderror

        <div class="rounded-xl p-3 text-[12px]" style="background:#F8FAFC;border:1px solid #E2E8F0;color:#334155">
          {{ __('comptabilite_pwa.saisie_intro_detail') }}
        </div>

        <div class="grid grid-cols-1 md:grid-cols-4 gap-3">
          <div>
            <label class="block text-[12px] font-semibold text-slate-600 mb-1">{{ __('comptabilite_pwa.champ_journal') }} <span class="text-red-500">*</span></label>
            <select wire:model="journalCode" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2 bg-white">
              <option value="">{{ __('comptabilite_pwa.choisir') }}</option>
              {{-- CL et AN : les journaux que seule la clôture écrit. --}}
              @foreach ($journaux->reject(fn ($j) => in_array($j->code, \App\Domain\Comptabilite\Services\ClotureExerciceService::JOURNAUX_RESERVES, true)) as $unJournal)
                <option value="{{ $unJournal->code }}">{{ $unJournal->code }} — {{ $unJournal->libelle }}</option>
              @endforeach
            </select>
            @error('journalCode') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
          <div>
            <label class="block text-[12px] font-semibold text-slate-600 mb-1">{{ __('comptabilite_pwa.champ_date') }} <span class="text-red-500">*</span></label>
            <input type="date" wire:model="dateEcriture" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2">
            @error('dateEcriture') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
          <div class="md:col-span-2">
            <label class="block text-[12px] font-semibold text-slate-600 mb-1">{{ __('comptabilite_pwa.champ_libelle_piece') }} <span class="text-red-500">*</span></label>
            <input type="text" wire:model="libellePiece" placeholder="{{ __('comptabilite_pwa.champ_libelle_piece_invite') }}"
                   class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2">
            @error('libellePiece') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
        </div>

        {{-- ⚠ EXCLUE de la conversion navy du 01/09/2026 (décision PO) : cette
             grille est un FORMULAIRE de saisie (chaque cellule est un
             `<select>`/`<input>` en édition directe), pas une table de
             consultation — le maître lui-même garde ce style clair pour ses
             grilles de lignes éditables (`m7-approvisionnement.html`
             « Lignes de la commande »), jamais navy. --}}
        <div class="overflow-x-auto border border-slate-200 rounded-lg">
          <table class="w-full text-[13px]">
            <thead class="bg-slate-50 text-[11px] uppercase text-slate-500"><tr>
              <th class="px-2 py-2 text-left" style="width:28%">{{ __('comptabilite_pwa.col_compte') }}</th>
              <th class="px-2 py-2 text-left">{{ __('comptabilite_pwa.col_libelle_ligne') }}</th>
              <th class="px-2 py-2 text-left" style="width:18%">{{ __('comptabilite_pwa.col_centre') }}</th>
              <th class="px-2 py-2 text-right" style="width:14%">{{ __('comptabilite_pwa.col_debit') }}</th>
              <th class="px-2 py-2 text-right" style="width:14%">{{ __('comptabilite_pwa.col_credit') }}</th>
              <th style="width:32px"></th>
            </tr></thead>
            <tbody>
              @foreach ($lignesPiece as $index => $ligne)
                <tr class="border-t border-slate-100 align-top" wire:key="ligne-piece-{{ $index }}">
                  <td class="px-2 py-1.5">
                    <select wire:model="lignesPiece.{{ $index }}.compte" class="champ w-full text-[13px] border border-slate-300 rounded px-2 py-1.5 bg-white">
                      <option value="">{{ __('comptabilite_pwa.choisir') }}</option>
                      @foreach ($comptesDuPlan as $unCompte)
                        <option value="{{ $unCompte->numero_compte }}">{{ $unCompte->numero_compte }} — {{ $unCompte->libelle }}</option>
                      @endforeach
                    </select>
                    @error('lignesPiece.'.$index.'.compte') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
                  </td>
                  <td class="px-2 py-1.5">
                    <input type="text" wire:model="lignesPiece.{{ $index }}.libelle" class="champ w-full text-[13px] border border-slate-300 rounded px-2 py-1.5">
                  </td>
                  <td class="px-2 py-1.5">
                    <select wire:model="lignesPiece.{{ $index }}.centre_id" class="champ w-full text-[13px] border border-slate-300 rounded px-2 py-1.5 bg-white">
                      <option value="">—</option>
                      @foreach ($centresDeCout as $unCentre)
                        <option value="{{ $unCentre->id }}">{{ $unCentre->libelle }}</option>
                      @endforeach
                    </select>
                  </td>
                  <td class="px-2 py-1.5">
                    <input type="number" min="0" step="1" inputmode="numeric"
                           wire:model.live.debounce.400ms="lignesPiece.{{ $index }}.debit"
                           class="champ w-full text-right text-[13px] border border-slate-300 rounded px-2 py-1.5 tabular-nums">
                  </td>
                  <td class="px-2 py-1.5">
                    <input type="number" min="0" step="1" inputmode="numeric"
                           wire:model.live.debounce.400ms="lignesPiece.{{ $index }}.credit"
                           class="champ w-full text-right text-[13px] border border-slate-300 rounded px-2 py-1.5 tabular-nums">
                  </td>
                  <td class="px-1 text-center">
                    @if (count($lignesPiece) > 2)
                      <button type="button" wire:click="retirerLignePiece({{ $index }})"
                              aria-label="{{ __('comptabilite_pwa.ligne_retirer') }}"
                              class="text-slate-300 hover:text-red-500 text-lg leading-none">&times;</button>
                    @endif
                  </td>
                </tr>
              @endforeach
            </tbody>
            <tfoot>
              <tr class="border-t-2 border-slate-300 bg-slate-50 font-bold">
                <td class="px-2 py-2.5" colspan="3" style="color:var(--navy)">{{ __('comptabilite_pwa.totaux') }}</td>
                <td class="px-2 py-2.5 text-right">{{ \App\Pwa\Support\MontantFcfa::formatOuTiret($totauxPiece['debit']) }}</td>
                <td class="px-2 py-2.5 text-right">{{ \App\Pwa\Support\MontantFcfa::formatOuTiret($totauxPiece['credit']) }}</td>
                <td></td>
              </tr>
              <tr>
                <td colspan="6" class="px-2 py-2">
                  @if ($totauxPiece['debit'] !== '0.00' || $totauxPiece['credit'] !== '0.00')
                    @if ($totauxPiece['equilibre'])
                      <span class="text-[12px] text-emerald-700 bg-emerald-50 border border-emerald-200 rounded px-2 py-1">{{ __('comptabilite_pwa.piece_equilibree') }}</span>
                    @else
                      <span class="text-[12px] text-red-700 bg-red-50 border border-red-200 rounded px-2 py-1">
                        {{ __('comptabilite_pwa.piece_ecart', ['montant' => \App\Pwa\Support\MontantFcfa::format(ltrim(bcsub($totauxPiece['debit'], $totauxPiece['credit'], 2), '-'))]) }}
                      </span>
                    @endif
                  @endif
                </td>
              </tr>
            </tfoot>
          </table>
        </div>
        @error('lignesPiece') <p class="text-[12px] text-red-600">{{ $message }}</p> @enderror

        <button type="button" wire:click="ajouterLignePiece"
                class="text-[12px] px-3 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">+ {{ __('comptabilite_pwa.ligne_ajouter') }}</button>

        <div class="rounded-xl p-3 text-[12px]" style="background:#FFFBEB;border:1px solid #FDE68A;color:#78350F">
          <strong>{{ __('comptabilite_pwa.immuabilite_titre') }}</strong> {{ __('comptabilite_pwa.immuabilite_detail') }}
        </div>

        <div class="flex justify-end gap-2 pt-2">
          <button type="button" wire:click="fermerModales"
                  class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
          <button type="button" wire:click="enregistrerPieceBrouillon"
                  class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('comptabilite_pwa.enregistrer_brouillon') }}</button>
          <button type="button" wire:click="enregistrerPieceValidee"
                  class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('comptabilite_pwa.enregistrer_valider') }}</button>
        </div>
      </form>
    </x-pwa.modale>
  @endif

  {{-- MODALE « Créer un compte » — maître : `m10-syscohada.js` l.401-458. --}}
  @if ($etatFormulaire === 'compte')
    <x-pwa.modale :titre="__('comptabilite_pwa.compte_modale_titre')" largeur="520px">
      <form wire:submit.prevent="enregistrerCompte" class="space-y-4">
        @error('compte')
          <p class="text-[13px] rounded-lg px-3 py-2 font-semibold"
             style="background:#FDECEC;color:#C62828;border:1px solid #F5C6C6">{{ $message }}</p>
        @enderror

        <div class="grid grid-cols-3 gap-3">
          <div>
            <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('comptabilite_pwa.champ_numero') }} <span class="text-red-500">*</span></label>
            <input type="text" wire:model="numeroCompte" placeholder="{{ \App\Domain\Comptabilite\Services\PlanComptableService::NUMERO_COMPTE_EXEMPLE }}" inputmode="numeric" maxlength="{{ \App\Domain\Comptabilite\Services\PlanComptableService::NUMERO_COMPTE_CHIFFRES_MAX }}"
                   class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 font-mono">
            @error('numeroCompte') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
          <div class="col-span-2">
            <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('comptabilite_pwa.champ_intitule') }} <span class="text-red-500">*</span></label>
            <input type="text" wire:model="libelleCompte" placeholder="{{ __('comptabilite_pwa.champ_intitule_invite') }}"
                   class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
            @error('libelleCompte') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('comptabilite_pwa.champ_nature') }} <span class="text-red-500">*</span></label>
          <select wire:model="natureCompte" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 bg-white">
            <option value="">{{ __('comptabilite_pwa.choisir') }}</option>
            @foreach ($naturesDeCompte as $uneNature)
              <option value="{{ $uneNature }}">{{ __(match ($uneNature) {
                'actif' => 'comptabilite_pwa.nature_actif',
                'passif' => 'comptabilite_pwa.nature_passif',
                'charge' => 'comptabilite_pwa.nature_charge',
                default => 'comptabilite_pwa.nature_produit',
              }) }}</option>
            @endforeach
          </select>
          <p class="text-[11px] text-slate-500 mt-1.5">{{ __('comptabilite_pwa.champ_nature_aide') }}</p>
          @error('natureCompte') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>

        <div class="flex justify-end gap-2 pt-2">
          <button type="button" wire:click="fermerModales"
                  class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
          <button type="submit"
                  class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('comptabilite_pwa.creer_compte') }}</button>
        </div>
      </form>
    </x-pwa.modale>
  @endif

  {{-- MODALE « Nouvelle immobilisation » — maître : `m10-syscohada-etats.js` l.318-400. --}}
  {{-- Étiquette « Centre d’affectation » du maître (modale-immo) NON rendue :
       le centre analytique des immobilisations attend l'arbitrage Comptable,
       avec la comptabilisation des dotations (681/28x) — hors du périmètre
       commandé le 01/09/2026. Refus déclaré :
       maitre-refuse:m10-syscohada.html#immo-centre-affectation --}}
  @if ($etatFormulaire === 'immo')
    <x-pwa.modale :titre="__('comptabilite_pwa.immo_modale_titre')" largeur="560px">
      <form wire:submit.prevent="enregistrerImmo" class="space-y-4">
        @error('immo')
          <p class="text-[13px] rounded-lg px-3 py-2 font-semibold"
             style="background:#FDECEC;color:#C62828;border:1px solid #F5C6C6">{{ $message }}</p>
        @enderror

        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('comptabilite_pwa.champ_intitule') }} <span class="text-red-500">*</span></label>
          <input type="text" wire:model="libelleImmo" placeholder="{{ __('comptabilite_pwa.immo_libelle_invite') }}" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('libelleImmo') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('comptabilite_pwa.champ_compte_immo') }} <span class="text-red-500">*</span></label>
          <select wire:model="compteImmo" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 bg-white">
            <option value="">{{ __('comptabilite_pwa.choisir') }}</option>
            @foreach ($comptesDuPlan->where('classe', '2') as $unCompte)
              <option value="{{ $unCompte->numero_compte }}">{{ $unCompte->numero_compte }} — {{ $unCompte->libelle }}</option>
            @endforeach
          </select>
          @error('compteImmo') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div class="grid grid-cols-2 gap-3">
          <div>
            <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('comptabilite_pwa.champ_valeur_origine') }} <span class="text-red-500">*</span></label>
            <input type="number" min="1" step="1" wire:model="valeurOrigineImmo" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
            @error('valeurOrigineImmo') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
          <div>
            <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('comptabilite_pwa.champ_date_mise_service') }} <span class="text-red-500">*</span></label>
            <input type="date" wire:model="dateMiseServiceImmo" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
            @error('dateMiseServiceImmo') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('comptabilite_pwa.champ_duree_annees') }} <span class="text-red-500">*</span></label>
          <input type="number" min="1" max="60" step="1" wire:model="dureeAnneesImmo"
                 placeholder="{{ __('comptabilite_pwa.immo_duree_invite') }}"
                 class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('dureeAnneesImmo') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <p class="text-[11px] text-slate-500 bg-amber-50 border border-amber-200 rounded-lg p-2.5">{{ __('comptabilite_pwa.immo_aide') }}</p>

        <div class="flex justify-end gap-2 pt-2">
          <button type="button" wire:click="fermerModales"
                  class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
          <button type="submit"
                  class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('comptabilite_pwa.enregistrer') }}</button>
        </div>
      </form>
    </x-pwa.modale>
  @endif

  {{-- MODALE « Plan » d'amortissement — LECTURE, maître :
       `m10-syscohada-etats.js` l.252-316. --}}
  @if ($etatFormulaire === 'planAmortissement' && $immobilisationConsultee !== null && $planAmortissementConsulte !== null)
    <x-pwa.modale :titre="$immobilisationConsultee->libelle" largeur="640px">
      <p class="text-[12px] text-slate-500 -mt-2 mb-2">
        {{ \App\Pwa\Support\MontantFcfa::format($immobilisationConsultee->valeur_origine) }} ·
        {{ $immobilisationConsultee->duree_annees }} ans · linéaire ·
        mise en service {{ $immobilisationConsultee->date_mise_service->format('d/m/Y') }}
      </p>
      <div class="overflow-x-auto max-h-[60vh]">
        <table class="w-full text-[13px]">
          <thead class="bg-[var(--navy)]"><tr>
            <th class="px-3 py-2 text-left text-[11px] uppercase tracking-wide text-white/90 font-semibold">{{ __('comptabilite_pwa.col_exercice') }}</th>
            <th class="px-3 py-2 text-right text-[11px] uppercase tracking-wide text-white/90 font-semibold">{{ __('comptabilite_pwa.col_base') }}</th>
            <th class="px-3 py-2 text-right text-[11px] uppercase tracking-wide text-white/90 font-semibold">{{ __('comptabilite_pwa.col_dotation_annuelle') }}</th>
            <th class="px-3 py-2 text-right text-[11px] uppercase tracking-wide text-white/90 font-semibold">{{ __('comptabilite_pwa.col_cumul') }}</th>
            <th class="px-3 py-2 text-right text-[11px] uppercase tracking-wide text-white/90 font-semibold">{{ __('comptabilite_pwa.col_vnc') }}</th>
          </tr></thead>
          <tbody>
            @foreach ($planAmortissementConsulte->lignes as $ligne)
              <tr class="border-t border-slate-100">
                <td class="px-3 py-2 font-semibold" style="color:var(--navy)">
                  {{ $ligne->annee }}
                  @if ($ligne->prorata)
                    <span class="text-[11px] font-normal text-amber-700">prorata {{ $ligne->prorata }}</span>
                  @endif
                </td>
                <td class="px-3 py-2 text-right text-slate-500">{{ \App\Pwa\Support\MontantFcfa::format($ligne->base) }}</td>
                <td class="px-3 py-2 text-right font-semibold">{{ \App\Pwa\Support\MontantFcfa::format($ligne->dotation) }}</td>
                <td class="px-3 py-2 text-right text-slate-600">{{ \App\Pwa\Support\MontantFcfa::format($ligne->cumul) }}</td>
                <td class="px-3 py-2 text-right">{{ \App\Pwa\Support\MontantFcfa::format($ligne->vnc) }}</td>
              </tr>
            @endforeach
            <tr class="solde-final">
              <td class="px-3 py-2.5" colspan="2">{{ __('comptabilite_pwa.total') }}</td>
              <td class="px-3 py-2.5 text-right">{{ \App\Pwa\Support\MontantFcfa::format($planAmortissementConsulte->total) }}</td>
              <td colspan="2"></td>
            </tr>
          </tbody>
        </table>
      </div>
      <p class="text-[11px] text-slate-500 mt-3">{{ __('comptabilite_pwa.plan_amortissement_note') }}</p>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('pwa.modale.fermer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- MODALE « Ouvrir un exercice » — maître : `m10-syscohada-etats.js` l.500-516 (Dialogue.saisir). --}}
  @if ($etatFormulaire === 'exercice')
    <x-pwa.modale :titre="__('comptabilite_pwa.exercice_ouvrir')" largeur="420px">
      <form wire:submit.prevent="enregistrerExercice" class="space-y-4">
        @error('exercice')
          <p class="text-[13px] rounded-lg px-3 py-2 font-semibold"
             style="background:#FDECEC;color:#C62828;border:1px solid #F5C6C6">{{ $message }}</p>
        @enderror

        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('comptabilite_pwa.exercice_annee') }} <span class="text-red-500">*</span></label>
          <input type="number" wire:model="anneeOuverture" min="2000" max="2100" step="1"
                 class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('anneeOuverture') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>

        <div class="flex justify-end gap-2 pt-2">
          <button type="button" wire:click="fermerModales"
                  class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
          <button type="submit"
                  class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('comptabilite_pwa.exercice_ouvrir_valider') }}</button>
        </div>
      </form>
    </x-pwa.modale>
  @endif

  {{-- Le châssis d'export PARTAGÉ, jamais une copie locale. --}}
  @if ($etatFormulaire === 'export')
    @include('pwa.partials.modale-export', ['titre' => __('comptabilite_pwa.export_journal_titre')])
  @endif

</div>

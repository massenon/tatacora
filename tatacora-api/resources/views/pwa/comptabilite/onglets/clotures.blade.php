{{--
    Onglet « Clôtures » du hub — maître :
    `prototype_v2/pages/m10-syscohada-etats.js` `vueClotures()` l.405-497.

    ⚠ EXCLU de la barre de recherche par table (PO, 01/09/2026) : la liste des
    exercices comptables compte au plus une poignée de lignes (un exercice par
    année d'activité) — un registre de cette taille n'a rien à filtrer.

    Le maître y pose TROIS blocs : la liste des exercices comptables (l.408),
    la grille des clôtures périodiques (l.430) et le bloc de clôture d'exercice
    (l.451), avec ses trois cartes « Résultat à reporter », « Blocages »,
    « Avertissements ».

    ## CE BLOC PORTE DEUX DES TROIS ACTIONS DU MAÎTRE — commande du Product
    ## Owner (Vague E, 01/09/2026), qui RENVERSE le refus ci-dessous

    ~~ÉCART DÉLIBÉRÉ — les trois actions du maître ne sont pas rendues~~
    LEVÉ POUR DEUX DES TROIS. Le motif tenait tant qu'aucun Service ne
    clôturait quoi que ce soit ; il ne dit plus l'état du dépôt.
    `ExerciceComptableService` existe désormais (Vague E) et porte
    `ouvrir()`/`cloturer()` — SOUS UN PÉRIMÈTRE VOLONTAIREMENT RÉDUIT, nommé
    dans son propre docblock : ouvrir = créer la ligne d'exercice, rien de
    plus ; clôturer = changer le statut, REFUSÉ si des écritures y restent en
    brouillon. AUCUN solde des comptes de gestion (6/7/8) par le compte 13,
    AUCUNE écriture d'à-nouveaux au journal AN — la clôture comptable COMPLÈTE
    que `EtatClotureService` décrit reste À FAIRE, sous l'arbitrage du
    Comptable. C'est la raison pour laquelle la note ci-dessous,
    `cloture_perimetre_note`, est rendue À CÔTÉ du bouton : un geste qui
    change un statut sans toucher au grand livre ne doit pas se faire passer
    pour une clôture comptable intégrale.

    Ce qui reste REFUSÉ : « Clôturer » une PÉRIODE (mois) — voir la section
    suivante, inchangée, aucune table de période comptable n'existe au schéma.
    Refus déclaré : maitre-refuse:m10-syscohada.html#clotures-periodiques

    ## La grille des clôtures périodiques n'est pas rendue non plus

    ÉCART DÉLIBÉRÉ — `m10-syscohada-etats.js` l.430-449
    Le maître : douze cases, une par mois, portant « Clôturée le <date> » ou un
    bouton « Clôturer ».
    Ici : absente.
    Raison : aucune table de période comptable n'existe au schéma — le verrou
    par mois n'est stocké nulle part. Rendre douze cases toutes « non
    clôturées » afficherait un état qu'aucun calcul n'a produit (PA-59/60/61),
    et sur la fonction même dont PA-28 dit qu'elle n'est pas arbitrée.
--}}
@php
    use App\Domain\Comptabilite\ReadModels\EtatCloture;
    use App\Pwa\Support\MontantFcfa;

    // Les colonnes de l'onglet, écrites UNE fois (voir `_entetes`).
    $colonnesEntete = [
        ['Exercice', 'left'],
        ['Début', 'right'],
        ['Fin', 'right'],
        ['Statut', 'right'],
        ['Résultat reporté', 'right'],
        ['Clôturé le', 'right'],
    ];
@endphp
@if ($squelette ?? false)
  @include('pwa.comptabilite.onglets._squelette_tableau', ['colonnes' => $colonnesEntete, 'message' => $messageSquelette])
@else
<div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
  <div class="px-4 py-3 border-b border-slate-200 flex items-center justify-between">
    <h3 class="text-[14px] font-bold" style="color:var(--navy)">Exercices comptables</h3>
    {{-- « Ouvrir un exercice » (maître l.424) — porté le 01/09/2026. --}}
    <button type="button" wire:click="ouvrirFormulaireExercice"
            class="text-[12px] px-3 py-1.5 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('comptabilite_pwa.exercice_ouvrir') }}</button>
  </div>
  <div class="overflow-x-auto">
    <table class="w-full text-[13px] compta" style="white-space: nowrap">
      {{-- « Résultat reporté » (maître l.412) — RENDU depuis le 01/09/2026,
           mais CALCULÉ, jamais stocké : aucune colonne de ce nom n'existe
           sur `exercices_comptables`. Seule la ligne de l'exercice
           CONSULTÉ (sélecteur en tête de hub) porte une valeur — c'est
           `$cloture->resultatAReporter`, déjà calculé pour lui plus bas ;
           le recalculer pour chaque exercice de la liste referait, pour
           chacun, tout le travail d'`EtatClotureService`. Les autres
           lignes portent un tiret : jamais un résultat inventé (Article 7). --}}
      @include('pwa.comptabilite.onglets._entetes', ['colonnes' => $colonnesEntete])
      <tbody>
        @foreach ($tousExercices as $unExercice)
          <tr class="border-t border-slate-100">
            <td class="px-3 py-2 font-bold" style="color:var(--navy)">{{ $unExercice->annee }}</td>
            <td class="px-3 py-2 text-right text-slate-600">{{ $unExercice->date_debut->format('d/m/Y') }}</td>
            <td class="px-3 py-2 text-right text-slate-600">{{ $unExercice->date_fin->format('d/m/Y') }}</td>
            <td class="px-3 py-2 text-right">
              @if ($unExercice->statut === 'ouvert')
                <span class="text-[11px] px-2 py-0.5 rounded bg-emerald-50 text-emerald-700">Ouvert</span>
              @elseif ($unExercice->statut === 'en_cloture')
                <span class="text-[11px] px-2 py-0.5 rounded bg-amber-50 text-amber-700">En clôture</span>
              @else
                <span class="text-[11px] px-2 py-0.5 rounded bg-slate-100 text-slate-600">Clôturé</span>
              @endif
            </td>
            <td class="px-3 py-2 text-right font-semibold {{ ($cloture !== null && $unExercice->id === $exerciceIdConsulte && MontantFcfa::estNegatif($cloture->resultatAReporter)) ? 'text-red-600' : '' }}">
              {{ ($cloture !== null && $unExercice->id === $exerciceIdConsulte) ? MontantFcfa::format($cloture->resultatAReporter) : MontantFcfa::TIRET }}
            </td>
            <td class="px-3 py-2 text-right text-slate-500 text-[12px]">{{ $unExercice->date_cloture?->format('d/m/Y') ?? '—' }}</td>
          </tr>
        @endforeach
      </tbody>
    </table>
  </div>
</div>

@if ($cloture !== null)
  <div class="bg-white rounded-xl border border-slate-200 p-4">
    <h3 class="text-[14px] font-bold mb-1" style="color:var(--navy)">Clôture de l'exercice {{ $cloture->annee }}</h3>
    {{-- La phrase du maître (l.455-458), mot pour mot. --}}
    <p class="text-[12px] text-slate-500 mb-3">
      Trois opérations enchaînées : solde des comptes de gestion (6, 7, 8) par le compte 13,
      verrouillage de l'exercice, puis réouverture du suivant par une écriture d'à-nouveaux
      au journal AN qui reprend <strong>les seuls comptes de bilan</strong>.
    </p>

    <div class="grid grid-cols-1 md:grid-cols-3 gap-3 mb-3">
      <div class="border border-slate-200 rounded-lg p-3">
        <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">Résultat à reporter</div>
        <div class="text-lg font-bold mt-1 {{ MontantFcfa::estNegatif($cloture->resultatAReporter) ? 'text-red-600' : '' }}"
             @if (! MontantFcfa::estNegatif($cloture->resultatAReporter)) style="color:var(--navy)" @endif>{{ MontantFcfa::format($cloture->resultatAReporter) }}</div>
        <div class="text-[11px] text-slate-400 mt-0.5">
          Vers le compte {{ $cloture->compteDeDestination }}
          ({{ MontantFcfa::estNegatif($cloture->resultatAReporter) ? 'perte' : 'bénéfice' }})
        </div>
      </div>
      @php($blocages = array_merge($cloture->blocagesStructurels, $cloture->blocagesDeDonnees))
      <div class="border border-slate-200 rounded-lg p-3">
        <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">Blocages</div>
        <div class="text-lg font-bold mt-1 {{ $blocages !== [] ? 'text-red-600' : 'text-emerald-600' }}">{{ count($blocages) }}</div>
      </div>
      <div class="border border-slate-200 rounded-lg p-3">
        <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">Avertissements</div>
        <div class="text-lg font-bold mt-1 {{ $cloture->avertissements !== [] ? 'text-amber-600' : 'text-slate-400' }}">{{ count($cloture->avertissements) }}</div>
      </div>
    </div>

    @if ($blocages !== [])
      <div class="bg-red-50 border border-red-200 rounded-lg p-3 mb-3">
        <p class="text-[13px] font-semibold text-red-900 mb-1.5">La clôture est impossible en l'état :</p>
        <ul class="list-disc pl-5 space-y-1">
          @foreach ($blocages as $blocage)
            <li class="text-[12px] text-red-800">{{ __('pwa.comptabilite.motifs.' . $blocage) }}</li>
          @endforeach
        </ul>
      </div>
    @else
      <div class="bg-emerald-50 border border-emerald-200 rounded-lg p-3 mb-3">
        <p class="text-[13px] text-emerald-900">Tous les contrôles bloquants sont satisfaits.</p>
      </div>
    @endif

    @if ($cloture->avertissements !== [])
      <div class="bg-amber-50 border border-amber-200 rounded-lg p-3 mb-3">
        <p class="text-[13px] font-semibold text-amber-900 mb-1.5">Avertissements — la clôture reste possible :</p>
        <ul class="list-disc pl-5 space-y-1">
          @foreach ($cloture->avertissements as $avertissement)
            <li class="text-[12px] text-amber-800">{{ __('pwa.comptabilite.motifs.' . $avertissement) }}</li>
          @endforeach
        </ul>
      </div>
    @endif

    @if ($cloture->limitesNonVerifiables !== [])
      <div class="bg-slate-50 border border-slate-200 rounded-lg p-3 mb-3">
        <p class="text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.comptabilite.limites_titre') }}</p>
        <ul class="list-disc pl-5 space-y-1">
          @foreach ($cloture->limitesNonVerifiables as $limite)
            <li class="text-[12px] text-slate-500">{{ __('pwa.comptabilite.motifs.' . $limite) }}</li>
          @endforeach
        </ul>
      </div>
    @endif

    <p class="text-[13px] text-slate-400 mt-3">
      <a href="{{ route('pwa.comptabilite.cloture', ['exercice' => $exerciceIdConsulte, 'statut' => $filtreStatut]) }}" wire:navigate
         class="font-semibold underline" style="color:var(--gold)">Voir le détail des six étapes de clôture</a>
    </p>
  </div>

  {{--
      « Clôturer l'exercice <année> » (maître l.491-494) — la clôture
      SYSCOHADA ANNUELLE complète depuis le 20/10/2026 (lot 2, décisions du
      Product Owner : annuelle seulement, réouverture par le comptable),
      `ClotureExerciceService`. Le geste dépend du statut :
        ouvert     → « Démarrer la clôture »
        en_cloture → « Clôturer définitivement » (la liste de contrôle
                     ci-dessus doit être réunie) ou « Reprendre la saisie »
        cloture    → « Rouvrir » (le comptable seul, motif obligatoire)
  --}}
  @if ($exercice !== null)
    <div id="geste-cloture" class="bg-white rounded-xl border border-slate-200 p-4 mt-3">
      @error('cloture')
        <div class="bg-red-50 border border-red-200 rounded-lg p-3 mb-3">
          <p class="text-[13px] text-red-800">{{ $message }}</p>
        </div>
      @enderror

      @if ($exercice->statut === 'ouvert')
        @if ($postesNonAJour !== [])
          <div id="alerte-postes" class="bg-amber-50 border border-amber-200 rounded-lg p-3 mb-3">
            <p class="text-[13px] font-semibold text-amber-900">{{ __('comptabilite_pwa.alerte_postes_titre') }}</p>
            <p class="text-[12px] text-amber-900 mt-1">{{ __('comptabilite_pwa.alerte_postes_detail', ['annee' => $exercice->annee]) }}</p>
            <ul class="list-disc pl-5 mt-1.5">
              @foreach ($postesNonAJour as $poste)
                <li class="text-[12px] text-amber-900">
                  <span class="font-mono">{{ $poste['poste_id'] }}</span> —
                  @if ($poste['en_attente'] > 0)
                    {{ __('comptabilite_pwa.alerte_postes_en_attente', ['nombre' => $poste['en_attente']]) }}
                  @else
                    {{ $poste['derniere_descente'] === null
                        ? __('comptabilite_pwa.alerte_postes_jamais')
                        : __('comptabilite_pwa.alerte_postes_silencieux', ['date' => $poste['derniere_descente']->format('d/m/Y H:i')]) }}
                  @endif
                </li>
              @endforeach
            </ul>
          </div>
        @endif
        <h3 class="text-[14px] font-bold mb-1" style="color:var(--navy)">{{ __('comptabilite_pwa.cloture_demarrer', ['annee' => $exercice->annee]) }}</h3>
        <p class="text-[12px] text-slate-500 mb-3">{{ __('comptabilite_pwa.cloture_demarrer_note', ['annee' => $exercice->annee]) }}</p>
        <button type="button" wire:click="demarrerCloture"
                class="text-[13px] px-4 py-2.5 rounded-lg font-semibold bg-[var(--navy)] text-white hover:opacity-90">
          {{ __('comptabilite_pwa.cloture_demarrer', ['annee' => $exercice->annee]) }}
        </button>
      @elseif ($exercice->statut === 'en_cloture')
        <h3 class="text-[14px] font-bold mb-1" style="color:var(--navy)">{{ __('comptabilite_pwa.cloture_definitive', ['annee' => $exercice->annee]) }}</h3>
        <p class="text-[12px] text-slate-500 mb-3">{{ __('comptabilite_pwa.cloture_definitive_note') }}</p>
        <div class="flex flex-wrap gap-2">
          <button type="button" wire:click="cloturerExercice"
                  class="text-[13px] px-4 py-2.5 rounded-lg font-semibold bg-[var(--navy)] text-white hover:opacity-90">
            {{ __('comptabilite_pwa.cloture_definitive', ['annee' => $exercice->annee]) }}
          </button>
          <button type="button" wire:click="reprendreSaisie"
                  class="text-[13px] px-4 py-2.5 rounded-lg border border-slate-300 hover:bg-slate-50">
            {{ __('comptabilite_pwa.cloture_reprendre') }}
          </button>
        </div>
      @else
        @if ($clotureActive !== null)
          <p class="text-[13px] text-slate-600 mb-3">{{ __('comptabilite_pwa.cloture_passee', [
              'date' => $clotureActive->cloturee_le->format('d/m/Y H:i'),
              'cloture' => $clotureActive->piece_cloture ?? '—',
              'an' => $clotureActive->piece_a_nouveaux ?? '—',
          ]) }}</p>
          <div id="archive-cloture" class="border border-slate-200 rounded-lg p-3 mb-4">
            <h3 class="text-[14px] font-bold mb-1" style="color:var(--navy)">{{ __('comptabilite_pwa.archive_ecran') }}</h3>
            <p class="text-[12px] text-slate-500 mb-2">{{ __('comptabilite_pwa.archive_ecran_note') }}</p>
            @if ($clotureActive->archive_empreinte !== null)
              <p class="text-[12px] text-slate-600 mb-2">{{ __('comptabilite_pwa.archive_empreinte') }}
                <code class="break-all text-[11px]">{{ $clotureActive->archive_empreinte }}</code></p>
              <button type="button" wire:click="telechargerArchive"
                      class="text-[13px] px-4 py-2.5 rounded-lg border border-slate-300 hover:bg-slate-50 font-semibold">
                {{ __('comptabilite_pwa.archive_telecharger') }}
              </button>
            @else
              <p class="text-[12px] text-amber-700 mb-2">{{ __('comptabilite_pwa.archive_absente') }}</p>
              <button type="button" wire:click="genererArchive"
                      class="text-[13px] px-4 py-2.5 rounded-lg bg-[var(--navy)] text-white hover:opacity-90 font-semibold">
                {{ __('comptabilite_pwa.archive_generer') }}
              </button>
            @endif
          </div>
        @endif
        <h3 class="text-[14px] font-bold mb-1" style="color:var(--navy)">{{ __('comptabilite_pwa.reouvrir', ['annee' => $exercice->annee]) }}</h3>
        <p class="text-[12px] text-slate-500 mb-3">{{ __('comptabilite_pwa.reouvrir_note') }}</p>
        @if ($peutRouvrir)
          <label for="motif-reouverture" class="block text-[13px] font-semibold text-slate-700 mb-1">{{ __('comptabilite_pwa.reouvrir_motif') }}</label>
          <textarea id="motif-reouverture" wire:model="motifReouverture" rows="2"
                    class="champ w-full border border-slate-200 rounded-lg px-3 py-2 text-sm mb-2"></textarea>
          <button type="button" wire:click="rouvrirExercice"
                  class="text-[13px] px-4 py-2.5 rounded-lg border border-red-200 text-red-700 hover:bg-red-50 font-semibold">
            {{ __('comptabilite_pwa.reouvrir', ['annee' => $exercice->annee]) }}
          </button>
        @else
          <p class="text-[12px] text-slate-400">{{ __('comptabilite_pwa.reouvrir_reserve') }}</p>
        @endif
      @endif
    </div>
  @endif
@endif
@endif

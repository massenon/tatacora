{{--
    Onglet « Bilan » du hub — maître :
    `prototype_v2/pages/m10-syscohada-etats.js` `vueBilan()` l.112-157.

    ⚠ EXCLU de la barre de recherche par table (PO, 01/09/2026) : « TOTAL
    ACTIF » doit égaler « TOTAL PASSIF » sur un BILAN — c'est la définition
    même du document. Un texte de recherche masquerait des postes sans
    recalculer ces totaux, produisant un bilan qui ne s'équilibre plus.
    Même famille de refus que `App\Pwa\Livewire\Comptabilite\Balance`.

    Deux tableaux côte à côte dans une grille `grid grid-cols-1 xl:grid-cols-2
    gap-3` (l.153) : à gauche « Réf. », « ACTIF », « Brut », « Amort./Dépr. »,
    « Net » ; à droite « Réf. », « PASSIF », « Montant ». Chacun se termine par
    sa ligne `.solde-final` — « TOTAL ACTIF », « TOTAL PASSIF ».

    L'encadré gris du maître (l.148-152) est repris mot pour mot : il nomme les
    deux traitements qu'une lecture littérale du plan manquerait.

    ## Les références de liasse sont REFUSÉES — Article 8

    ÉCART DÉLIBÉRÉ — `m10-syscohada-etats.js` l.119 et l.138, colonne « Réf. »
    Le maître : un code de liasse par poste (`p.code`), du type AD, AI, BB, CA,
    DR.
    Ici : la colonne porte le code TECHNIQUE du poste rendu par le Service
    (`actif_immobilise`, `capitaux_propres`…), jamais un code de liasse.
    Raison : PA-151 point (6) — les références de liasse supposent une colonne
    `plan_comptable.type` à 19 valeurs QUI N'EXISTE PAS au schéma, et aucune n'a
    été inventée côté serveur. « Un faux repère réglementaire sur un état
    financier » est interdit : une liasse déposée sur des références inventées
    est rejetée, et le bilan s'équilibre quand même.
    Refus déclaré : maitre-refuse:m10-syscohada.html#bilan

    ## Colonne comparative N-1 (lot 3, 20/10/2026)

    Quand l'exercice précédent existe, chaque tableau gagne une colonne : le
    NET du même poste (même code technique) en N-1, et son total.
--}}
@php
    use App\Pwa\Support\MontantFcfa;

    // Les colonnes des DEUX tableaux du maître, écrites UNE fois chacune
    // (voir `_entetes`) : actif à gauche, passif à droite.
    $colonnesActif = [
        ['Réf.', 'left'],
        ['ACTIF', 'left'],
        ['Brut', 'right'],
        ['Amort./Dépr.', 'right'],
        ['Net', 'right'],
    ];
    $colonnesPassif = [
        ['Réf.', 'left'],
        ['PASSIF', 'left'],
        ['Montant', 'right'],
    ];

    $bilanPrecedent ??= null;
    $netsPrecedents = $bilanPrecedent === null ? [] : collect([...$bilanPrecedent->actif, ...$bilanPrecedent->passif])
        ->mapWithKeys(fn ($p): array => [$p->section.'|'.$p->code => $p->net])->all();
    if ($bilanPrecedent !== null) {
        $colonneN1 = [__('comptabilite_pwa.colonne_exercice_precedent', ['annee' => $precedent->annee]), 'right'];
        $colonnesActif[] = $colonneN1;
        $colonnesPassif[] = $colonneN1;
    }

    $styleSoldeFinal = 'background: var(--navy); color: #fff; font-weight: 700;';
@endphp
@if ($squelette ?? false)
  <div class="grid grid-cols-1 xl:grid-cols-2 gap-3">
    <div>
      @include('pwa.comptabilite.onglets._squelette_tableau', ['colonnes' => $colonnesActif, 'message' => $messageSquelette])
    </div>
    <div>
      @include('pwa.comptabilite.onglets._squelette_tableau', ['colonnes' => $colonnesPassif, 'message' => $messageSquelette])
    </div>
  </div>
@else
@unless ($bilan->equilibre)
  <div class="rounded-xl p-3.5 mb-4" style="background:#FEF2F2;border:1px solid #FECACA">
    <p class="text-[13px]" style="color:#7F1D1D">
      <strong>Bilan déséquilibré.</strong>
      Écart de {{ MontantFcfa::format(ltrim($bilan->ecart, '-')) }} entre actif et passif.
    </p>
  </div>
@endunless

@if ($bilan->impotNonComptabilise)
  <div class="rounded-xl p-3.5 mb-4" style="background:#FFFBEB;border:1px solid #FDE68A">
    <p class="text-[13px]" style="color:#78350F">
      <strong>Résultat AVANT impôt.</strong> {{ __('pwa.comptabilite.resultat_avant_impot') }}
    </p>
  </div>
@endif

{{-- L'encadré gris du maître (l.148-152), mot pour mot. --}}
<div class="rounded-xl p-3.5 mb-4" style="background:#F8FAFC;border:1px solid #E2E8F0">
  <p class="text-[13px]" style="color:#334155">
    <strong>Deux traitements que la lecture littérale du plan manquerait :</strong>
    <strong>amortissements et dépréciations en soustraction de l'actif</strong> (présentation brut / amort. / net),
    et <strong>reclassement des classes 4 et 5 selon le sens réel du solde</strong> — un compte 521 créditeur est un découvert,
    donc une trésorerie-passif, pas un actif négatif.
  </p>
</div>

<div class="grid grid-cols-1 xl:grid-cols-2 gap-3">
  <div>
    <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
      <div class="overflow-x-auto">
        <table class="w-full text-[13px] compta" style="white-space: nowrap">
          @include('pwa.comptabilite.onglets._entetes', ['colonnes' => $colonnesActif])
          <tbody>
            @foreach ($bilan->actif as $poste)
              <tr class="border-t border-slate-100">
                <td class="px-3 py-2 font-mono text-slate-400 text-[12px]">{{ $poste->code }}</td>
                <td class="px-3 py-2 text-left text-slate-700">
                  {{ $poste->libelle }}
                  @if ($poste->prefixes !== [])
                    <div class="text-[11px] text-slate-400">{{ implode(', ', $poste->prefixes) }}</div>
                  @endif
                </td>
                <td class="px-3 py-2 text-right">{{ MontantFcfa::formatOuTiret($poste->brut) }}</td>
                <td class="px-3 py-2 text-right text-red-600">{{ MontantFcfa::formatOuTiret($poste->amortissement) }}</td>
                <td class="px-3 py-2 text-right font-semibold">{{ MontantFcfa::formatOuTiret($poste->net) }}</td>
                @if ($bilanPrecedent !== null)
                  <td class="px-3 py-2 text-right text-slate-500">{{ MontantFcfa::formatOuTiret($netsPrecedents[$poste->section.'|'.$poste->code] ?? '0.00') }}</td>
                @endif
              </tr>
            @endforeach
            <tr style="{{ $styleSoldeFinal }}">
              <td class="px-3 py-2.5" colspan="2">TOTAL ACTIF</td>
              <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($bilan->totalActifBrut) }}</td>
              <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($bilan->totalActifAmortissement) }}</td>
              <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($bilan->totalActif) }}</td>
              @if ($bilanPrecedent !== null)
                <td class="px-3 py-2.5 text-right opacity-80">{{ MontantFcfa::format($bilanPrecedent->totalActif) }}</td>
              @endif
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
  <div>
    <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
      <div class="overflow-x-auto">
        <table class="w-full text-[13px] compta" style="white-space: nowrap">
          @include('pwa.comptabilite.onglets._entetes', ['colonnes' => $colonnesPassif])
          <tbody>
            @foreach ($bilan->passif as $poste)
              <tr class="border-t border-slate-100">
                <td class="px-3 py-2 font-mono text-slate-400 text-[12px]">{{ $poste->code }}</td>
                <td class="px-3 py-2 text-left text-slate-700">
                  {{ $poste->libelle }}
                  @if ($poste->prefixes !== [])
                    <div class="text-[11px] text-slate-400">{{ implode(', ', $poste->prefixes) }}</div>
                  @endif
                </td>
                <td class="px-3 py-2 text-right font-semibold {{ MontantFcfa::estNegatif($poste->net) ? 'text-red-600' : '' }}">{{ MontantFcfa::formatOuTiret($poste->net) }}</td>
                @if ($bilanPrecedent !== null)
                  <td class="px-3 py-2 text-right text-slate-500">{{ MontantFcfa::formatOuTiret($netsPrecedents[$poste->section.'|'.$poste->code] ?? '0.00') }}</td>
                @endif
              </tr>
            @endforeach
            <tr style="{{ $styleSoldeFinal }}">
              <td class="px-3 py-2.5" colspan="2">TOTAL PASSIF</td>
              <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($bilan->totalPassif) }}</td>
              @if ($bilanPrecedent !== null)
                <td class="px-3 py-2.5 text-right opacity-80">{{ MontantFcfa::format($bilanPrecedent->totalPassif) }}</td>
              @endif
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</div>

@if ($bilan->comptesHorsRubrique !== [])
  <div class="rounded-xl p-3.5" style="background:#FEF2F2;border:1px solid #FECACA">
    <p class="text-[13px] font-bold" style="color:#7F1D1D">{{ __('pwa.comptabilite.comptes_hors_rubrique_titre') }}</p>
    <p class="text-[13px] mt-1" style="color:#7F1D1D">{{ __('pwa.comptabilite.comptes_hors_rubrique_detail') }}</p>
    <ul class="list-disc pl-5 mt-1.5">
      @foreach ($bilan->comptesHorsRubrique as $compte)
        <li class="text-[13px]" style="color:#7F1D1D">
          <span class="font-mono">{{ $compte['numero_compte'] }}</span> — {{ $compte['libelle'] }} : {{ MontantFcfa::format($compte['solde']) }}
        </li>
      @endforeach
    </ul>
  </div>
@endif
@endif

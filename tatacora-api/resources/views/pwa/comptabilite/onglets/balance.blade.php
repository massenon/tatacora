{{--
    Onglet « Balance générale » du hub — maître :
    `prototype_v2/pages/m10-syscohada-etats.js` `vueBalance()` l.18-70.

    ⚠ EXCLU de la barre de recherche par table (PO, 01/09/2026) : même motif
    que `pwa/comptabilite/balance.blade.php` — une balance filtrée par texte
    n'est plus une balance (sous-totaux par classe compris).

    ⚠ CE N'EST PAS LE MÊME TABLEAU QUE `m10-balance.html` : ici les colonnes
    sont « Compte », « Intitulé », « Mouvements débit », « Mouvements crédit »,
    « Solde débiteur », « Solde créditeur » (l.65), et le tableau porte des
    SOUS-TOTAUX PAR CLASSE (l.32-41) — « c'est la lecture qu'un Comptable fait
    en premier », dit le maître. La page autonome, elle, écrit « Total Débit »
    et n'a pas de sous-totaux. Les deux sont portés séparément.

    Les sous-totaux sont calculés ICI, sur les lignes que le Service a déjà
    rendues — c'est un regroupement d'affichage, pas une règle de gestion : la
    classe est portée par `LigneBalance::classe`, et aucune requête n'est
    refaite. Les additions passent par `bcadd`, jamais par un flottant.
--}}
@php
    use App\Pwa\Support\MontantFcfa;

    // Les colonnes de l'onglet, écrites UNE fois (voir `_entetes`).
    $colonnesEntete = [
        ['Compte', 'left'],
        ['Intitulé', 'left'],
        ['Mouvements débit', 'right'],
        ['Mouvements crédit', 'right'],
        ['Solde débiteur', 'right'],
        ['Solde créditeur', 'right'],
    ];
@endphp
@if ($squelette ?? false)
  @include('pwa.comptabilite.onglets._squelette_tableau', ['colonnes' => $colonnesEntete, 'message' => $messageSquelette])
@else
@php
    $styleSoldeIntermediaire = 'background: #F1F5F9; font-weight: 700;';
    $styleSoldeFinal = 'background: var(--navy); color: #fff; font-weight: 700;';

    // Regroupement d'AFFICHAGE : les lignes arrivent déjà triées par numéro de
    // compte, donc par classe. `groupBy` conserve cet ordre.
    $parClasse = collect($balance->lignes)->groupBy(fn ($ligne) => $ligne->classe);

    $classesLibelle = [
        '1' => 'Capitaux', '2' => 'Immobilisations', '3' => 'Stocks', '4' => 'Tiers',
        '5' => 'Trésorerie', '6' => 'Charges', '7' => 'Produits',
        '8' => 'Hors activités ordinaires', '9' => 'Analytique',
    ];
@endphp
@if (! $balance->equilibree)
  <div class="rounded-xl p-3.5 mb-4" style="background:#FEF2F2;border:1px solid #FECACA">
    <p class="text-[13px]" style="color:#7F1D1D">
      <strong>Balance déséquilibrée.</strong>
      Écart de {{ MontantFcfa::format(ltrim(bcsub($balance->totalSoldeDebiteur, $balance->totalSoldeCrediteur, 2), '-')) }}
      entre soldes débiteurs et créditeurs. Aucun état financier n'est exploitable tant que cet écart subsiste.
    </p>
  </div>
@endif

<div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
  <div class="px-4 py-3 border-b border-slate-200 flex items-center justify-between">
    <h3 class="text-[14px] font-bold" style="color:var(--navy)">Balance générale — {{ count($balance->lignes) }} compte(s)</h3>
    @if ($balance->equilibree)
      <span class="text-[12px] text-emerald-700 bg-emerald-50 border border-emerald-200 rounded px-2 py-1">Équilibrée</span>
    @endif
  </div>
  <div class="overflow-x-auto">
    <table class="w-full text-[13px] compta" style="white-space: nowrap">
      @include('pwa.comptabilite.onglets._entetes', ['colonnes' => $colonnesEntete])
      <tbody>
        @forelse ($parClasse as $classe => $lignes)
          @foreach ($lignes as $ligne)
            <tr class="border-t border-slate-100 hover:bg-slate-50">
              <td class="px-3 py-2 font-mono font-semibold" style="color:var(--navy)">{{ $ligne->numeroCompte }}</td>
              <td class="px-3 py-2 text-left text-slate-700">{{ $ligne->libelle }}</td>
              <td class="px-3 py-2 text-right">{{ MontantFcfa::formatOuTiret($ligne->totalDebit) }}</td>
              <td class="px-3 py-2 text-right">{{ MontantFcfa::formatOuTiret($ligne->totalCredit) }}</td>
              <td class="px-3 py-2 text-right font-semibold">{{ MontantFcfa::formatOuTiret($ligne->soldeDebiteur) }}</td>
              <td class="px-3 py-2 text-right font-semibold">{{ MontantFcfa::formatOuTiret($ligne->soldeCrediteur) }}</td>
            </tr>
          @endforeach
          @php
              $sousTotal = fn (string $champ): string => $lignes->reduce(
                  fn (string $cumul, $ligne): string => bcadd($cumul, $ligne->{$champ}, 2),
                  '0.00',
              );
          @endphp
          <tr class="border-t border-slate-300" style="{{ $styleSoldeIntermediaire }}">
            <td class="px-3 py-2" colspan="2">Total classe {{ $classe }} — {{ $classesLibelle[$classe] ?? '' }}</td>
            <td class="px-3 py-2 text-right">{{ MontantFcfa::format($sousTotal('totalDebit')) }}</td>
            <td class="px-3 py-2 text-right">{{ MontantFcfa::format($sousTotal('totalCredit')) }}</td>
            <td class="px-3 py-2 text-right">{{ MontantFcfa::formatOuTiret($sousTotal('soldeDebiteur')) }}</td>
            <td class="px-3 py-2 text-right">{{ MontantFcfa::formatOuTiret($sousTotal('soldeCrediteur')) }}</td>
          </tr>
        @empty
          <tr><td colspan="6" class="py-14 text-center text-slate-400 text-[13px]">Aucun compte mouvementé sur la période.</td></tr>
        @endforelse

        @if ($balance->lignes !== [])
          <tr style="{{ $styleSoldeFinal }}">
            <td class="px-3 py-2.5" colspan="2">TOTAUX GÉNÉRAUX</td>
            <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($balance->totalDebit) }}</td>
            <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($balance->totalCredit) }}</td>
            <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($balance->totalSoldeDebiteur) }}</td>
            <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($balance->totalSoldeCrediteur) }}</td>
          </tr>
        @endif
      </tbody>
    </table>
  </div>
</div>
@endif

{{--
    Onglet « Compte de résultat » du hub — maître :
    `prototype_v2/pages/m10-syscohada-etats.js` `vueResultat()` l.76-106.

    Quatre colonnes du maître (l.104) : « Réf. », « Libellé », « Charges »,
    « Produits / Solde ». Les lignes de solde prennent le style
    `.solde-intermediaire`, sauf `XI` qui prend `.solde-final` (l.90).

    C'est la cascade complète des Soldes Intermédiaires de Gestion, telle que
    `SoldesIntermediairesGestion::CASCADE` la définit — donc exactement ce que
    le Service calcule, jamais un regroupement réécrit ici.

    ⚠ EXCLU de la barre de recherche par table (PO, 01/09/2026) : c'est une
    CASCADE — chaque solde intermédiaire se calcule à partir des lignes qui le
    précèdent. Masquer une ligne par un filtre texte romprait la cascade sans
    recalculer les soldes qui en dépendent. Même famille de refus que
    `App\Pwa\Livewire\Comptabilite\Balance`.
--}}
@php
    use App\Pwa\Support\MontantFcfa;

    // Les colonnes de l'onglet, écrites UNE fois (voir `_entetes`).
    $colonnesEntete = [
        ['Réf.', 'left'],
        ['Libellé', 'left'],
        ['Charges', 'right'],
        ['Produits / Solde', 'right'],
    ];

    $styleSoldeIntermediaire = 'background: #F1F5F9; font-weight: 700;';
    $styleSoldeFinal = 'background: var(--navy); color: #fff; font-weight: 700;';
@endphp
@if ($squelette ?? false)
  @include('pwa.comptabilite.onglets._squelette_tableau', ['colonnes' => $colonnesEntete, 'message' => $messageSquelette])
@else
@if ($resultat->impotNonComptabilise)
  {{-- `encadre('amber', 'Résultat AVANT impôt.', ...)` du maître (l.79).
       Le texte vient de l'état du serveur, pas d'un taux à configurer — voir
       `App\Pwa\Livewire\Comptabilite\CompteResultat` pour l'écart complet. --}}
  <div class="rounded-xl p-3.5 mb-4" style="background:#FFFBEB;border:1px solid #FDE68A">
    <p class="text-[13px]" style="color:#78350F">
      <strong>Résultat AVANT impôt.</strong> {{ __('pwa.comptabilite.resultat_avant_impot') }}
    </p>
  </div>
@endif

<div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
  <div class="px-4 py-3 border-b border-slate-200 flex items-center justify-between">
    <h3 class="text-[14px] font-bold" style="color:var(--navy)">Compte de résultat — Système Normal</h3>
  </div>
  <div class="overflow-x-auto">
    <table class="w-full text-[13px] compta" style="white-space: nowrap">
      @include('pwa.comptabilite.onglets._entetes', ['colonnes' => $colonnesEntete])
      <tbody>
        @foreach ($resultat->lignes as $ligne)
          @if ($ligne->estSolde)
            @php($final = $ligne->code === 'XI')
            <tr class="border-t border-slate-300" style="{{ $final ? $styleSoldeFinal : $styleSoldeIntermediaire }}">
              <td class="px-3 py-2.5 font-mono">{{ $ligne->code }}</td>
              <td class="px-3 py-2.5 text-left">{{ $ligne->libelle }}</td>
              <td class="px-3 py-2.5"></td>
              <td class="px-3 py-2.5 text-right {{ ! $final && MontantFcfa::estNegatif($ligne->montant) ? 'text-red-600' : '' }}">{{ MontantFcfa::format($ligne->montant) }}</td>
            </tr>
          @else
            @php($charge = $ligne->sens === 'charge')
            <tr class="border-t border-slate-100 hover:bg-slate-50">
              <td class="px-3 py-2 font-mono text-slate-400 text-[12px]">{{ $ligne->code }}</td>
              <td class="px-3 py-2 text-left text-slate-700">
                {{ $ligne->libelle }}
                @if ($ligne->prefixes !== [])
                  <span class="text-[11px] text-slate-400"> · {{ implode(', ', $ligne->prefixes) }}</span>
                @endif
              </td>
              {{-- Le maître écrit « — » dans la colonne du sens inverse (l.100)
                   plutôt que de la laisser vide : la ligne appartient à un seul
                   des deux sens, et « 0 F » y ferait lire un montant. --}}
              <td class="px-3 py-2 text-right {{ $charge ? 'text-red-600' : 'text-slate-300' }}">{{ $charge ? MontantFcfa::formatOuTiret($ligne->montant) : '—' }}</td>
              <td class="px-3 py-2 text-right {{ $charge ? 'text-slate-300' : 'text-emerald-700 font-semibold' }}">{{ $charge ? '—' : MontantFcfa::formatOuTiret($ligne->montant) }}</td>
            </tr>
          @endif
        @endforeach
      </tbody>
    </table>
  </div>
</div>
@endif

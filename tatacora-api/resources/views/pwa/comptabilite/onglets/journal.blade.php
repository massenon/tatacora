{{--
    Onglet « Journal » du hub — maître : `prototype_v2/pages/m10-syscohada.js`
    `vueJournal()` l.234-297.

    ⚠ EXCLU de la barre de recherche par table (PO, 01/09/2026) : même motif
    que `pwa/comptabilite/journal.blade.php` — le bandeau d'équilibre porte
    sur les lignes AFFICHÉES, un filtre texte le fausserait sans recalcul.

    ⚠ CE N'EST PAS LE MÊME TABLEAU QUE LA PAGE `m10-journal.html`, et l'écart
    est celui du maître, pas du portage : ici les colonnes sont « N° pièce »,
    « Date », « Intitulé », « Libellé / centre », « Débit », « Crédit » et une
    colonne d'actions (l.295) ; là-bas ce sont « Date », « Journal »,
    « Compte », « Libellé », « Débit », « Crédit ». Les deux sont portés
    séparément.

    ## Une colonne du maître, REFUSÉE ; une autre, LEVÉE le 01/09/2026

    ~~ÉCART DÉLIBÉRÉ — `m10-syscohada.js` l.295, colonne « N° pièce » ABSENTE~~
    PARTIELLEMENT LEVÉ : `ecritures_comptables.numero_piece` existe désormais
    (migration `ajouter_numero_piece_aux_ecritures`, Vague E), écrit par
    `PasserEcritureService::passer()` sur toute pièce saisie DEPUIS ce lot.
    La colonne est rendue ci-dessous. Ce qui reste VRAI de l'ancien motif :
    aucune écriture ANTÉRIEURE à ce lot ne porte de numéro — `null`, rendu en
    tiret, jamais un numéro reconstitué après coup (Article 7). Le
    REGROUPEMENT par pièce, lui, N'EST TOUJOURS PAS fait : une ligne par
    écriture, comme avant — grouper exigerait de fusionner des lignes qui
    partagent une valeur, pas une clé technique dédiée, ce qui reste hors du
    périmètre de ce lot.

    ÉCART DÉLIBÉRÉ — `m10-syscohada.js` l.283-287, colonne d'actions
    Le maître : un bouton « Valider » sur les brouillons, « Contre-passer » sur
    les écritures validées.
    Ici : la colonne n'est pas rendue.
    Raison : les deux sont des ÉCRITURES. `LARAVEL_PWA.md` §6 exclut nommément
    la « validation d'écriture comptable » de la PWA, et RG-11 fait de la
    contre-passation la seule correction possible — donc une écriture de plus.
    Le refus est nommé en tête du hub, pas rendu inerte.
    Refus déclaré : maitre-refuse:m10-syscohada.html#journal
--}}
@php
    use App\Pwa\Support\MontantFcfa;

    // Les colonnes de l'onglet, écrites UNE fois (voir `_entetes`) : rendues
    // par le tableau complet comme par son squelette.
    $colonnesEntete = [
        [__('comptabilite_pwa.col_numero_piece'), 'left'],
        ['Date', 'left'],
        ['Compte', 'left'],
        ['Intitulé', 'left'],
        ['Libellé / centre', 'left'],
        ['Débit', 'right'],
        ['Crédit', 'right'],
        ['Statut', 'right'],
    ];
@endphp
@if ($squelette ?? false)
  @include('pwa.comptabilite.onglets._squelette_tableau', ['colonnes' => $colonnesEntete, 'message' => $messageSquelette])
@else
<div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
  <div class="px-4 py-3 border-b border-slate-200 flex items-center justify-between">
    <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ $journal->lignes->count() }} ligne(s)</h3>
  </div>
  <div class="overflow-x-auto">
    <table class="w-full text-[13px] compta" style="white-space: nowrap">
      @include('pwa.comptabilite.onglets._entetes', ['colonnes' => $colonnesEntete])
      <tbody>
        @forelse ($journal->lignes as $ligne)
          <tr class="border-t border-slate-100 text-slate-600">
            <td class="px-3 py-1.5 font-mono text-[12px]">{{ $ligne->numero_piece ?? MontantFcfa::TIRET }}</td>
            <td class="px-3 py-1.5 text-slate-600">{{ $ligne->date_ecriture->format('d/m/Y') }}</td>
            <td class="px-3 py-1.5 font-mono text-[12px]">{{ $ligne->compte?->numero_compte }}</td>
            <td class="px-3 py-1.5 text-left">{{ $ligne->compte?->libelle }}</td>
            <td class="px-3 py-1.5 text-left text-[12px] text-slate-400">
              {{ $ligne->libelle }}
              @if ($ligne->centre !== null)
                · <span class="text-[10px] px-1 rounded bg-slate-100">{{ $ligne->centre->libelle }}</span>
              @endif
            </td>
            {{-- `mt()` du maître (l.21) : « Zéro affiché comme un tiret : une
                 colonne de zéros masque les vrais montants. » --}}
            <td class="px-3 py-1.5 text-right">{{ MontantFcfa::formatOuTiret($ligne->debit) }}</td>
            <td class="px-3 py-1.5 text-right">{{ MontantFcfa::formatOuTiret($ligne->credit) }}</td>
            <td class="px-3 py-1.5 text-right">
              @if ($ligne->statut === 'brouillon')
                <span class="text-[10px] px-1.5 py-0.5 rounded bg-slate-100 text-slate-600">Brouillon</span>
              @else
                <span class="text-[10px] px-1.5 py-0.5 rounded bg-emerald-50 text-emerald-700">Validée</span>
              @endif
            </td>
          </tr>
        @empty
          <tr><td colspan="8" class="py-14 text-center text-slate-400 text-[13px]">Aucune pièce ne correspond à ces critères.</td></tr>
        @endforelse
      </tbody>
      @if ($journal->lignes->isNotEmpty())
        <tfoot>
          <tr class="border-t-2 border-slate-300 font-bold" style="background:var(--navy);color:#fff">
            <td class="px-3 py-2.5" colspan="5">TOTAUX</td>
            <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($journal->totalDebit) }}</td>
            <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($journal->totalCredit) }}</td>
            <td></td>
          </tr>
        </tfoot>
      @endif
    </table>
  </div>
</div>
@endif

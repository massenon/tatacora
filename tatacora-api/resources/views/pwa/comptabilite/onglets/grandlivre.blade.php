{{--
    Onglet « Grand livre » du hub — maître :
    `prototype_v2/pages/m10-syscohada.js` `vueGrandLivre()` l.303-337.

    Colonnes du maître (l.311) : « Date », « N° pièce », « Journal »,
    « Libellé », « Débit », « Crédit », « Solde », plus une ligne « Totaux ».

    ⚠ EXCLU de la barre de recherche par table (PO, 01/09/2026) : le sélecteur
    de compte est le filtre pertinent (même motif que
    `pwa/comptabilite/grand-livre.blade.php`) — un texte de recherche
    casserait la colonne « Solde », cumul séquentiel.

    ## La colonne « N° pièce » du maître — LEVÉE partiellement le 01/09/2026

    ~~ÉCART DÉLIBÉRÉ — `m10-syscohada.js` l.311, colonne « N° pièce » ABSENTE~~
    `ecritures_comptables.numero_piece` existe désormais (migration
    `ajouter_numero_piece_aux_ecritures`, Vague E). La colonne est rendue ;
    une écriture antérieure à ce lot affiche un tiret, jamais un numéro
    reconstitué (Article 7).

    ## Un compte à la fois, et non tous les comptes mouvementés

    ÉCART DÉLIBÉRÉ — `m10-syscohada.js` l.309-337
    Le maître : rend UN tableau PAR compte mouvementé, tous à la suite.
    Ici : un sélecteur, et le grand livre du compte choisi.
    Raison : `GrandLivreService` refuse au-delà de 5 000 lignes POUR UN COMPTE
    (`EtatTropVolumineuxException`) ; empiler tous les comptes d'un exercice
    ferait la somme de ces plafonds sur une seule page. La page autonome
    `m10-grand-livre.html` procède déjà ainsi (l.32, un `<select>`), et c'est
    la même donnée : suivre le maître ici l'aurait contredit ailleurs.
--}}
@php
    use App\Pwa\Support\MontantFcfa;

    // Les colonnes de l'onglet, écrites UNE fois (voir `_entetes`).
    $colonnesEntete = [
        ['Date', 'left'],
        [__('comptabilite_pwa.col_numero_piece'), 'left'],
        ['Journal', 'right'],
        ['Libellé', 'left'],
        ['Débit', 'right'],
        ['Crédit', 'right'],
        ['Solde', 'right'],
    ];
@endphp
@if ($squelette ?? false)
  @include('pwa.comptabilite.onglets._squelette_tableau', ['colonnes' => $colonnesEntete, 'message' => $messageSquelette])
@else
<div class="bg-white rounded-xl border border-slate-200 p-3.5 mb-3">
  <label for="hub-compte-gl" class="text-[12px] text-slate-500 block mb-1.5">Compte</label>
  <select id="hub-compte-gl" wire:model.live="compteId" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2 w-full">
    @forelse ($comptesMouvementes as $unCompte)
      <option value="{{ $unCompte->id }}">{{ $unCompte->numero_compte }} — {{ $unCompte->libelle }}</option>
    @empty
      <option value="">Aucun compte mouvementé sur la période</option>
    @endforelse
  </select>
</div>

@if ($grandLivre === null)
  <div class="bg-white rounded-xl border border-slate-200 py-14 text-center text-slate-400 text-[13px]">
    Aucun compte mouvementé sur la période.
  </div>
@else
  <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
    <div class="px-4 py-3 border-b border-slate-200 flex items-center justify-between">
      <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ $grandLivre->compte->numero_compte }} — {{ $grandLivre->compte->libelle }}</h3>
    </div>
    <div class="overflow-x-auto">
      <table class="w-full text-[13px] compta" style="white-space: nowrap">
        @include('pwa.comptabilite.onglets._entetes', ['colonnes' => $colonnesEntete])
        <tbody>
          @foreach ($grandLivre->lignes as $ligne)
            <tr class="border-t border-slate-100">
              <td class="px-3 py-1.5 text-slate-600">{{ $ligne->ecriture->date_ecriture->format('d/m/Y') }}</td>
              <td class="px-3 py-1.5 font-mono text-[12px] text-slate-500">{{ $ligne->ecriture->numero_piece ?? MontantFcfa::TIRET }}</td>
              <td class="px-3 py-1.5 text-right text-slate-500">{{ $ligne->ecriture->journal?->code }}</td>
              <td class="px-3 py-1.5 text-left text-slate-700">{{ $ligne->ecriture->libelle }}</td>
              <td class="px-3 py-1.5 text-right">{{ MontantFcfa::formatOuTiret($ligne->ecriture->debit) }}</td>
              <td class="px-3 py-1.5 text-right">{{ MontantFcfa::formatOuTiret($ligne->ecriture->credit) }}</td>
              {{-- Valeur absolue + sens, comme le maître (l.322) : un solde
                   créditeur écrit en négatif se lirait comme une anomalie. --}}
              <td class="px-3 py-1.5 text-right font-semibold {{ MontantFcfa::estNegatif($ligne->soldeProgressif) ? 'text-slate-500' : '' }}">
                {{ MontantFcfa::format(ltrim($ligne->soldeProgressif, '-')) }} {{ MontantFcfa::estNegatif($ligne->soldeProgressif) ? 'C' : 'D' }}
              </td>
            </tr>
          @endforeach
          @if ($grandLivre->estSansMouvement())
            <tr><td colspan="7" class="py-14 text-center text-slate-400 text-[13px]">Ce compte n'a aucun mouvement sur l'exercice.</td></tr>
          @else
            <tr class="border-t-2 border-slate-300 bg-slate-50 font-bold">
              <td class="px-3 py-2" colspan="4" style="color:var(--navy)">Totaux</td>
              <td class="px-3 py-2 text-right" colspan="2"></td>
              <td class="px-3 py-2 text-right">
                {{ MontantFcfa::format(ltrim($grandLivre->soldeMouvements, '-')) }} {{ MontantFcfa::estNegatif($grandLivre->soldeMouvements) ? 'C' : 'D' }}
              </td>
            </tr>
          @endif
        </tbody>
      </table>
    </div>
  </div>

  @if ($grandLivre->soldeOuverture === null)
    <p class="text-[13px] text-slate-400">{{ __('pwa.comptabilite.solde_ouverture_inconnu') }}</p>
  @endif
@endif
@endif

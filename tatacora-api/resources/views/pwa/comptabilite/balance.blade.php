{{--
    Balance Générale — maître : `prototype_v2/pages/m10-balance.html`.

    Conteneur `max-w-[1200px] mx-auto p-5 lg:p-8` (l.18), en-tête (l.20-30),
    bandeau d'équilibre (l.32), tableau à six colonnes (l.36-41) et pied
    « TOTAUX » (l.80-88).

    Les deux phrases du bandeau sont celles du maître (l.60-62), et la seconde
    porte une règle : « production des états financiers bloquée tant que non
    résolu ».

    ⚠ EXCLUE de la barre de recherche par table (décision PO du 01/09/2026,
    point 3 du lot) — voir `App\Pwa\Livewire\Comptabilite\Balance` : « le
    maître n'a AUCUN filtre sur cette page, et c'est respecté ». Une balance
    générale filtrée par texte ne serait plus une balance : « Total Débit =
    Total Crédit » du bandeau porte sur la balance ENTIÈRE, et un texte de
    recherche qui masquerait des comptes sans recalculer les totaux
    afficherait un équilibre qui ne correspond plus aux lignes visibles.
--}}
@php
    use App\Pwa\Support\MontantFcfa;
@endphp
<div class="contents">

  @include('pwa.partials.barre-superieure')
  

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1200px] mx-auto p-5 lg:p-8">

        @include('pwa.comptabilite.partials.en-tete', [
            'tailleRetour' => 'text-[15px]',
            'icone' => '<path stroke-linecap="round" stroke-linejoin="round" d="M12 3v18"/><path stroke-linecap="round" stroke-linejoin="round" d="m7 21 5-4 5 4"/><path stroke-linecap="round" stroke-linejoin="round" d="M5 7 2 12l3 5"/><path stroke-linecap="round" stroke-linejoin="round" d="M19 7l3 5-3 5"/><path stroke-linecap="round" stroke-linejoin="round" d="M5 7h14"/>',
            'titre' => 'Balance Générale',
            'sousTitre' => 'Soldes de tous les comptes mouvementés — document de contrôle avant toute clôture',
        ])

        @include('pwa.comptabilite.partials.socle', [
            'identifiant' => 'f-exercice',
            'repartition' => $balance?->statuts,
        ])

        @if ($exercice !== null)
          <div class="mb-4">
            <div class="rounded-lg px-4 py-3 text-[15px] font-semibold flex items-center gap-2"
                 style="background:{{ $balance->equilibree ? '#E8F5E9' : '#FDECEC' }};color:{{ $balance->equilibree ? '#2E7D32' : '#C62828' }}">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                @if ($balance->equilibree)
                  <path stroke-linecap="round" stroke-linejoin="round" d="M20 6L9 17l-5-5"/>
                @else
                  <circle cx="12" cy="12" r="10"/><path stroke-linecap="round" d="M12 8v4M12 16h.01"/>
                @endif
              </svg>
              {{ $balance->equilibree
                  ? 'Balance équilibrée — Total Débit = Total Crédit = ' . MontantFcfa::format($balance->totalDebit)
                  : 'Balance déséquilibrée — production des états financiers bloquée tant que non résolu' }}
            </div>
          </div>
        @endif

          {{-- Le tableau est l'enfant DIRECT du conteneur `overflow-hidden`,
               comme au maître (l.34-35) — pas de conteneur de défilement
               intermédiaire, que le comparateur de structure relèverait. --}}
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
              <table class="w-full text-sm">
                <thead class="bg-[var(--navy)]"><tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
                  <th class="px-4 py-3">N° Compte</th><th class="px-4 py-3">Libellé</th>
                  <th class="px-4 py-3 text-right">Total Débit</th><th class="px-4 py-3 text-right">Total Crédit</th>
                  <th class="px-4 py-3 text-right">Solde Débiteur</th><th class="px-4 py-3 text-right">Solde Créditeur</th>
                </tr></thead>
                <tbody>
                  {{-- Le tableau du maître se rend AUSSI sans exercice choisi
                       (02/09/2026, G5) : l'entête au-dessus, le message qui
                       dit quoi faire en ligne unique (Article 7). Ni bandeau
                       d'équilibre ni TOTAUX dans ce cas : aucun chiffre
                       qu'aucun calcul n'a produit. --}}
                  @if ($exercice === null)
                    @include('pwa.comptabilite.partials.aucun-exercice-ligne', ['colonnes' => 6])
                  @else
                  @forelse ($balance->lignes as $ligne)
                    <tr class="border-t border-slate-100 hover:bg-slate-50">
                      <td class="px-4 py-2.5 font-mono-tatacora text-[15px] text-slate-700">{{ $ligne->numeroCompte }}</td>
                      <td class="px-4 py-2.5 text-slate-700">{{ $ligne->libelle }}</td>
                      <td class="px-4 py-2.5 text-right font-mono-tatacora text-[15px]">{{ MontantFcfa::format($ligne->totalDebit) }}</td>
                      <td class="px-4 py-2.5 text-right font-mono-tatacora text-[15px]">{{ MontantFcfa::format($ligne->totalCredit) }}</td>
                      {{-- Le maître laisse la colonne du sens inverse VIDE
                           (l.71-72) : un compte n'a de solde que dans UN sens,
                           et « 0 F » ferait lire deux soldes. --}}
                      <td class="px-4 py-2.5 text-right font-mono-tatacora text-[15px] font-semibold" style="color:var(--navy)">{{ MontantFcfa::formatOuVide($ligne->soldeDebiteur) }}</td>
                      <td class="px-4 py-2.5 text-right font-mono-tatacora text-[15px] font-semibold" style="color:var(--gold)">{{ MontantFcfa::formatOuVide($ligne->soldeCrediteur) }}</td>
                    </tr>
                  @empty
                    <tr><td colspan="6" class="py-14 text-center text-slate-400 text-sm">Aucun compte mouvementé sur cet exercice.</td></tr>
                  @endforelse
                  @endif
                </tbody>
                @if ($exercice !== null)
                <tfoot>
                  <tr class="border-t-2 border-slate-300 font-bold bg-slate-50">
                    <td colspan="2" class="px-4 py-3 text-right text-[15px] text-slate-600">TOTAUX</td>
                    <td class="px-4 py-3 text-right font-mono-tatacora text-[15px]">{{ MontantFcfa::format($balance->totalDebit) }}</td>
                    <td class="px-4 py-3 text-right font-mono-tatacora text-[15px]">{{ MontantFcfa::format($balance->totalCredit) }}</td>
                    <td class="px-4 py-3 text-right font-mono-tatacora text-[15px]">{{ MontantFcfa::format($balance->totalSoldeDebiteur) }}</td>
                    <td class="px-4 py-3 text-right font-mono-tatacora text-[15px]">{{ MontantFcfa::format($balance->totalSoldeCrediteur) }}</td>
                  </tr>
                </tfoot>
                @endif
              </table>
          </div>

      </div>
    </main>
  </div>

</div>

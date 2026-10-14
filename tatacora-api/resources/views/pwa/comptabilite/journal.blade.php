{{--
    Journal Comptable — maître : `prototype_v2/pages/m10-journal.html`.

    Conteneur `max-w-[1440px] mx-auto p-5 lg:p-8` (l.18), en-tête (l.20-30),
    barre de boutons de journal (l.32), tableau à six colonnes (l.36-45), pied
    « TOTAUX » (l.47-52) et bandeau d'équilibre (l.55).

    Les écarts sont motivés dans `App\Pwa\Livewire\Comptabilite\Journal` : les
    boutons de journal viennent du référentiel réel (cinq codes) et non des
    trois écrits en dur par le maître, et l'exercice est explicitement choisi.

    ⚠ EXCLUE de la barre de recherche par table (décision PO du 01/09/2026,
    point 3 du lot) : les boutons de journal (l.41-53) SONT le filtre à
    registre fermé de cet écran. Un texte de recherche ajouterait un second
    axe de filtrage sur un état dont le bandeau d'équilibre (« Total Débit =
    Total Crédit ») porte sur les lignes AFFICHÉES — masquer des lignes par
    texte sans recalculer ce bandeau reproduirait le défaut documenté sur
    `App\Pwa\Livewire\Comptabilite\Balance`.
--}}
@php
    use App\Pwa\Support\MontantFcfa;
@endphp
<div class="contents">

  @include('pwa.partials.barre-superieure')
  

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        @include('pwa.comptabilite.partials.en-tete', [
            'tailleRetour' => 'text-[15px]',
            'icone' => '<path stroke-linecap="round" stroke-linejoin="round" d="M3 22h18M6 18V11M10 18V11M14 18V11M18 18V11"/><path stroke-linecap="round" stroke-linejoin="round" d="M12 2 3 7v2h18V7z"/>',
            'titre' => 'Journal Comptable',
            'sousTitre' => 'Toutes les écritures, tous journaux confondus, par ordre chronologique',
        ])

        @include('pwa.comptabilite.partials.socle', [
            'identifiant' => 'f-exercice',
            'repartition' => $journal?->statuts,
        ])

        @if ($exercice !== null)
          {{-- Les boutons du maître (l.73-76) : « Tous les journaux », puis
               « <Libellé> (<CODE>) » par journal. --}}
          <div class="flex flex-wrap gap-2 mb-4">
            <a href="{{ route('pwa.comptabilite.journal', ['exercice' => $exercice->id, 'statut' => $filtreStatut]) }}" wire:navigate
               class="px-3 py-2 rounded-lg text-[15px] font-semibold border {{ $journalId === '' ? 'bg-[var(--navy)] text-white border-slate-200' : 'border-slate-200 bg-white text-slate-500' }}">
              Tous les journaux
            </a>
            @foreach ($journaux as $unJournal)
              <a href="{{ route('pwa.comptabilite.journal', ['exercice' => $exercice->id, 'statut' => $filtreStatut, 'journal' => $unJournal->id]) }}" wire:navigate
                 class="px-3 py-2 rounded-lg text-[15px] font-semibold border {{ $journalId === $unJournal->id ? 'bg-[var(--navy)] text-white border-slate-200' : 'border-slate-200 bg-white text-slate-500' }}">
                {{ $unJournal->libelle }} ({{ $unJournal->code }})
              </a>
            @endforeach
          </div>
        @endif

          @if ($exercice !== null && $refusDeVolume !== null)
            {{-- Article 7 : le message du refus, pas une exception technique.
                 Il porte le décompte réel et le plafond — de quoi décider quoi
                 filtrer. Ni troncature (des totaux faux sous un bandeau
                 d'anomalie) ni pagination (un total juste au-dessus de lignes
                 qui ne le font pas). --}}
            <div class="rounded-lg px-4 py-3 text-[15px] font-semibold" style="background:#FDECEC;color:#C62828">
              {{ $refusDeVolume }}
            </div>
          @else
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
              <div class="overflow-x-auto">
                <table class="w-full text-sm">
                  <thead class="bg-[var(--navy)]"><tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
                    <th class="px-4 py-3">Date</th><th class="px-4 py-3">Journal</th><th class="px-4 py-3">Compte</th>
                    <th class="px-4 py-3">Libellé</th><th class="px-4 py-3 text-right">Débit</th><th class="px-4 py-3 text-right">Crédit</th>
                  </tr></thead>
                  <tbody>
                    {{-- Le tableau du maître se rend AUSSI sans exercice
                         choisi (02/09/2026, G5) : l'entête dit ce que la page
                         montrera, la ligne unique dit quoi faire (Article 7).
                         Ni totaux ni bandeau dans ce cas : aucun chiffre
                         qu'aucun calcul n'a produit. --}}
                    @if ($exercice === null)
                      @include('pwa.comptabilite.partials.aucun-exercice-ligne', ['colonnes' => 6])
                    @else
                    @forelse ($journal->lignes as $ligne)
                      <tr class="border-t border-slate-100 hover:bg-slate-50">
                        <td class="px-4 py-2.5 font-mono-tatacora text-[15px] text-slate-500">{{ $ligne->date_ecriture->format('d/m/Y') }}</td>
                        <td class="px-4 py-2.5"><span class="text-[12px] font-bold px-2 py-0.5 rounded bg-slate-100 text-slate-600">{{ $ligne->journal?->code }}</span></td>
                        <td class="px-4 py-2.5 font-mono-tatacora text-[15px] text-slate-600">{{ $ligne->compte?->numero_compte }} — {{ $ligne->compte?->libelle }}</td>
                        <td class="px-4 py-2.5 text-slate-700">{{ $ligne->libelle }}</td>
                        {{-- Le maître laisse la cellule VIDE quand le sens ne
                             s'applique pas (l.83-84 : `${e.debit ? ... : ''}`) :
                             une ligne n'est jamais au débit ET au crédit, et
                             « 0 F » ferait lire deux montants. --}}
                        <td class="px-4 py-2.5 text-right font-mono-tatacora text-[15px]">{{ MontantFcfa::formatOuVide($ligne->debit) }}</td>
                        <td class="px-4 py-2.5 text-right font-mono-tatacora text-[15px]">{{ MontantFcfa::formatOuVide($ligne->credit) }}</td>
                      </tr>
                    @empty
                      <tr><td colspan="6" class="py-14 text-center text-slate-400 text-sm">Aucune écriture sur cet exercice.</td></tr>
                    @endforelse
                    @endif
                  </tbody>
                  @if ($exercice !== null)
                    <tfoot>
                      <tr class="border-t-2 border-slate-300 font-bold bg-slate-50">
                        <td colspan="4" class="px-4 py-3 text-right text-[15px] text-slate-600">TOTAUX</td>
                        <td class="px-4 py-3 text-right font-mono-tatacora text-[15px]">{{ MontantFcfa::format($journal->totalDebit) }}</td>
                        <td class="px-4 py-3 text-right font-mono-tatacora text-[15px]">{{ MontantFcfa::format($journal->totalCredit) }}</td>
                      </tr>
                    </tfoot>
                  @endif
                </table>
              </div>
            </div>

            {{-- Le maître ne montre ce bandeau QUE sans filtre de journal
                 (l.90 : `journalActif ? '' : ...`) : un journal isolé n'a
                 aucune raison d'être équilibré, et l'afficher annoncerait une
                 anomalie à chaque consultation d'un journal de ventes. --}}
            @if ($exercice !== null && $journalId === '')
              <div class="rounded-lg px-4 py-3 text-[15px] font-semibold flex items-center gap-2"
                   style="background:{{ $journal->equilibre ? '#E8F5E9' : '#FDECEC' }};color:{{ $journal->equilibre ? '#2E7D32' : '#C62828' }}">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                  @if ($journal->equilibre)
                    <path stroke-linecap="round" stroke-linejoin="round" d="M20 6L9 17l-5-5"/>
                  @else
                    <circle cx="12" cy="12" r="10"/><path stroke-linecap="round" d="M12 8v4M12 16h.01"/>
                  @endif
                </svg>
                {{ $journal->equilibre
                    ? 'Journal équilibré — Total Débit = Total Crédit'
                    : 'Journal déséquilibré — anomalie à investiguer avant clôture' }}
              </div>
            @endif
          @endif

      </div>
    </main>
  </div>

</div>

{{--
    Comptabilité Analytique — maître : `prototype_v2/pages/m10-analytique.html`.

    Conteneur `max-w-[1100px] mx-auto p-5 lg:p-8` (l.18), lien de retour en
    `text-[13px]` (l.21), en-tête (l.20-30), bandeau ambre (l.31), tableau à
    cinq colonnes sur fond `var(--navy)` (l.36-42), puis la note de pied sur le
    centre « Structure » (l.44-46), reprise mot pour mot.

    Les écarts sont motivés au complet dans
    `App\Pwa\Livewire\Comptabilite\Analytique`.

    ⚠ EXCLUE de la barre de recherche par table (décision PO du 01/09/2026,
    point 3 du lot) : cet écran est un ÉTAT RÉGLEMENTAIRE SYSCOHADA — la
    marge par centre est calculée pour la TOTALITÉ des centres analytiques.
    Un texte de recherche masquerait des centres sans recalculer le contexte
    (la note de pied sur « Structure » perdrait son sens si ce centre était
    filtré hors vue). Même famille de refus que documenté dans
    `App\Pwa\Livewire\Comptabilite\Balance` (« le maître n'a AUCUN filtre sur
    cette page, et c'est respecté »).
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
            'tailleRetour' => 'text-[13px]',
            'icone' => '<path stroke-linecap="round" stroke-linejoin="round" d="M22 12h-4l-3 9L9 3l-3 9H2"/>',
            'titre' => 'Comptabilité Analytique',
            'sousTitre' => 'Marges réelles par filière — Hébergement, Restauration, Bar, Tourisme, Véhicules',
        ])

        @include('pwa.comptabilite.partials.socle', [
            'identifiant' => 'f-exercice',
            'repartition' => $analytique?->statuts,
        ])

        @if ($exercice !== null)
          @unless ($analytique->repartitionStructureEffectuee)
            {{-- Le bandeau ambre du maître, à sa place et de sa couleur, avec
                 l'avertissement qui reste vrai quelles que soient les données —
                 celui du hub (`m10-syscohada-etats.js` l.196) — plutôt que
                 celui de cette page, qui décrit dix dossiers d'un jeu d'essai. --}}
            <div class="rounded-lg px-4 py-3 text-[13px] font-semibold bg-amber-50 text-amber-700 border border-amber-200 mb-5 flex items-start gap-2">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="shrink-0 mt-0.5"><circle cx="12" cy="12" r="10"/><path stroke-linecap="round" d="M12 8v4M12 16h.01"/></svg>
              <span>{{ __('pwa.comptabilite.structure_non_repartie') }}</span>
            </div>
          @endunless
        @endif

          {{-- Le tableau est l'enfant DIRECT du conteneur `overflow-hidden`,
               comme au maître (l.37-38) — pas de conteneur de défilement
               intermédiaire, que le comparateur de structure relèverait. --}}
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
              <table class="w-full text-[15px]">
                <thead class="bg-[var(--navy)]"><tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
                  <th class="px-4 py-3">Centre de coût</th>
                  <th class="px-4 py-3 text-right">Produits</th>
                  <th class="px-4 py-3 text-right">Charges</th>
                  <th class="px-4 py-3 text-right">Marge</th>
                  <th class="px-4 py-3 text-right">Taux de marge</th>
                </tr></thead>
                <tbody>
                  {{-- Le tableau du maître se rend AUSSI sans exercice choisi
                       (02/09/2026, G5) : l'entête au-dessus, le message qui
                       dit quoi faire en ligne unique (Article 7). Ni TOTAL ni
                       note de pied dans ce cas. --}}
                  @if ($exercice === null)
                    @include('pwa.comptabilite.partials.aucun-exercice-ligne', ['colonnes' => 5])
                  @else
                  @forelse ($analytique->centres as $centre)
                    <tr class="border-t border-slate-100 hover:bg-slate-50">
                      <td class="px-4 py-3 font-semibold text-slate-700">{{ $centre->libelle }}</td>
                      <td class="px-4 py-3 text-right font-mono-tatacora">{{ MontantFcfa::format($centre->produits) }}</td>
                      <td class="px-4 py-3 text-right font-mono-tatacora">{{ MontantFcfa::format($centre->charges) }}</td>
                      <td class="px-4 py-3 text-right font-mono-tatacora font-semibold" style="color:{{ MontantFcfa::estNegatif($centre->resultat) ? 'var(--erreur)' : 'var(--succes)' }}">{{ MontantFcfa::format($centre->resultat) }}</td>
                      {{-- Article 7, et le maître l'écrit déjà (l.62) : un
                           centre sans produits n'a pas un taux de zéro, il n'a
                           pas de taux. « — », jamais « 0,0 % ». --}}
                      <td class="px-4 py-3 text-right font-mono-tatacora font-semibold"
                          style="color:{{ $centre->tauxMarge === null ? '#9CA3AF' : (MontantFcfa::estNegatif($centre->tauxMarge) ? 'var(--erreur)' : 'var(--succes)') }}">
                        {{ $centre->tauxMarge === null ? '—' : $centre->tauxMarge . ' %' }}
                      </td>
                    </tr>
                  @empty
                    <tr><td colspan="5" class="py-14 text-center text-slate-400 text-sm">Aucune écriture ventilée sur cet exercice.</td></tr>
                  @endforelse
                  @endif
                </tbody>
                @if ($exercice !== null && $analytique->centres !== [])
                  <tfoot>
                    <tr class="border-t-2 border-slate-300 font-bold bg-slate-50">
                      <td class="px-4 py-3 text-right text-[15px] text-slate-600">TOTAL</td>
                      <td class="px-4 py-3 text-right font-mono-tatacora">{{ MontantFcfa::format($analytique->totalProduits) }}</td>
                      <td class="px-4 py-3 text-right font-mono-tatacora">{{ MontantFcfa::format($analytique->totalCharges) }}</td>
                      <td class="px-4 py-3 text-right font-mono-tatacora">{{ MontantFcfa::format($analytique->totalResultat) }}</td>
                      <td></td>
                    </tr>
                  </tfoot>
                @endif
              </table>
          </div>

          @if ($exercice !== null)
            {{-- La note de pied du maître (l.44-46), mot pour mot : elle explique
                 pourquoi « Structure » n'a pas de taux. --}}
            <p class="text-[13px] text-slate-400 mt-4">
              "Structure" regroupe les charges transverses non rattachées à une filière commerciale précise (paie du personnel, entretien général des bâtiments) — pas un centre générateur de produits, taux de marge non applicable ("—").
            </p>
          @endif

      </div>
    </main>
  </div>

</div>

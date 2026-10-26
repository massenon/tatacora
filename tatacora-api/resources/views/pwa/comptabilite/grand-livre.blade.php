{{--
    Grand Livre — maître : `prototype_v2/pages/m10-grand-livre.html`.

    Conteneur `max-w-[1100px] mx-auto p-5 lg:p-8` (l.18), en-tête (l.20-30),
    sélecteur de compte (l.32-35), tableau à six colonnes (l.39-44) et état vide
    (l.46), dont la phrase est celle du maître : « Ce compte n'a aucun mouvement
    sur l'exercice. »

    Les écarts sont motivés dans `App\Pwa\Livewire\Comptabilite\GrandLivre`.

    ⚠ EXCLUE de la barre de recherche par table (décision PO du 01/09/2026,
    point 3 du lot) : le sélecteur de compte (l.32-35) EST le filtre pertinent
    de cet écran — un Grand Livre se consulte compte par compte, jamais en
    texte libre sur plusieurs comptes à la fois. Un texte de recherche sur les
    lignes d'un même compte casserait en outre la colonne « Solde progressif »,
    qui est un cumul SÉQUENTIEL : masquer une ligne fausserait le solde de
    toutes celles qui suivent, sans que rien ne le signale. Même famille de
    refus que `App\Pwa\Livewire\Comptabilite\Balance`.
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
            'icone' => '<path stroke-linecap="round" stroke-linejoin="round" d="M12 7v14"/><path stroke-linecap="round" stroke-linejoin="round" d="M3 18a1 1 0 01-1-1V4a1 1 0 011-1h5a4 4 0 014 4 4 4 0 014-4h5a1 1 0 011 1v13a1 1 0 01-1 1h-6a3 3 0 00-3 3 3 3 0 00-3-3z"/>',
            'titre' => 'Grand Livre',
            'sousTitre' => 'Écritures par compte, avec solde progressif — sélectionnez un compte mouvementé',
        ])

        @include('pwa.comptabilite.partials.socle', [
            'identifiant' => 'f-exercice',
            'repartition' => $grandLivre?->statuts,
        ])

        @if ($exercice !== null)
          <div class="groupe-champ mb-4">
            <label for="select-compte-gl" class="block text-[15px] font-semibold text-slate-700 mb-1.5">Compte</label>
            <select id="select-compte-gl" wire:model.live="compteId"
                    class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
              @forelse ($comptesMouvementes as $unCompte)
                <option value="{{ $unCompte->id }}">{{ $unCompte->numero_compte }} — {{ $unCompte->libelle }}</option>
              @empty
                {{-- Le sélecteur ne propose QUE les comptes mouvementés
                     (`m10-grand-livre.html` l.55, citant
                     `MODULE_COMPTABILITE_COMPLET.md` Partie 1 §3 : « le Grand
                     Livre restitue l'activité réelle, pas le référentiel
                     complet »). Aucun mouvement sur l'exercice : la liste est
                     vide, et le dit. --}}
                <option value="">Aucun compte mouvementé sur cet exercice</option>
              @endforelse
            </select>
          </div>
        @endif

          @if ($exercice !== null && $refusDeVolume !== null)
            <div class="rounded-lg px-4 py-3 text-[15px] font-semibold" style="background:#FDECEC;color:#C62828">
              {{ $refusDeVolume }}
            </div>
          @else
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
              <div class="overflow-x-auto">
                <table class="w-full text-sm">
                  <thead class="bg-[var(--navy)]"><tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
                    <th class="px-4 py-3">Date</th><th class="px-4 py-3">Journal</th><th class="px-4 py-3">Libellé</th>
                    <th class="px-4 py-3 text-right">Débit</th><th class="px-4 py-3 text-right">Crédit</th><th class="px-4 py-3 text-right">Solde progressif</th>
                  </tr></thead>
                  <tbody>
                    {{-- Le tableau du maître se rend AUSSI sans exercice
                         choisi (02/09/2026, G5) : l'entête au-dessus, le
                         message qui dit quoi faire en ligne unique
                         (Article 7). --}}
                    @if ($exercice === null)
                      @include('pwa.comptabilite.partials.aucun-exercice-ligne', ['colonnes' => 6])
                    @endif
                    @if ($grandLivre !== null)
                      @foreach ($grandLivre->lignes as $ligne)
                        <tr class="border-t border-slate-100 hover:bg-slate-50">
                          <td class="px-4 py-2.5 font-mono-tatacora text-[15px] text-slate-500">{{ $ligne->ecriture->date_ecriture->format('d/m/Y') }}</td>
                          <td class="px-4 py-2.5"><span class="text-[12px] font-bold px-2 py-0.5 rounded bg-slate-100 text-slate-600">{{ $ligne->ecriture->journal?->code }}</span></td>
                          <td class="px-4 py-2.5 text-slate-700">{{ $ligne->ecriture->libelle }}</td>
                          <td class="px-4 py-2.5 text-right font-mono-tatacora text-[15px]">{{ MontantFcfa::formatOuVide($ligne->ecriture->debit) }}</td>
                          <td class="px-4 py-2.5 text-right font-mono-tatacora text-[15px]">{{ MontantFcfa::formatOuVide($ligne->ecriture->credit) }}</td>
                          {{-- Le maître affiche la VALEUR ABSOLUE suivie du sens
                               (l.99 : `(D)` / `(C)`). Un solde créditeur écrit
                               « −120 000 F » se lirait comme une anomalie ; en
                               comptabilité, un compte de tiers créditeur est
                               l'état normal. --}}
                          <td class="px-4 py-2.5 text-right font-mono-tatacora text-[15px] font-semibold" style="color:var(--navy)">
                            {{ MontantFcfa::format(ltrim($ligne->soldeProgressif, '-')) }}
                            {{ MontantFcfa::estNegatif($ligne->soldeProgressif) ? '(C)' : '(D)' }}
                          </td>
                        </tr>
                      @endforeach
                    @endif
                  </tbody>
                </table>
              </div>
              @if ($exercice !== null && ($grandLivre === null || $grandLivre->estSansMouvement()))
                <div class="py-16 text-center text-slate-400 text-sm">Ce compte n'a aucun mouvement sur l'exercice.</div>
              @endif
            </div>

            @if ($grandLivre !== null && $grandLivre->soldeOuverture !== null)
              @php($ouvertureProvisoire = $grandLivre->ouvertureProvisoire)
  <div id="soldes-grand-livre" class="text-[13px] text-slate-600 mt-3 flex flex-wrap gap-x-6 gap-y-1">
    <span>{{ __('pwa.comptabilite.solde_ouverture') }} :
      <strong>{{ MontantFcfa::format(ltrim((string) $grandLivre->soldeOuverture, '-')) }} {{ MontantFcfa::estNegatif((string) $grandLivre->soldeOuverture) ? 'C' : 'D' }}</strong></span>
    <span>{{ __('pwa.comptabilite.solde_cloture') }} :
      <strong>{{ MontantFcfa::format(ltrim((string) $grandLivre->soldeCloture, '-')) }} {{ MontantFcfa::estNegatif((string) $grandLivre->soldeCloture) ? 'C' : 'D' }}</strong></span>
  </div>
  @if ($ouvertureProvisoire)
    <p class="text-[12px] text-blue-800 mt-1">{{ __('pwa.comptabilite.ouverture_provisoire', ['annee' => $grandLivre->anneeOuverture]) }}</p>
  @endif
            @endif

            @if ($grandLivre !== null && $grandLivre->soldeOuverture === null)
              {{-- PA-148, cas `article7_le_solde_d_ouverture_est_inconnu_jamais_zero`.
                   Le maître n'a pas de ligne d'ouverture ; rien n'est donc
                   ajouté au tableau. Mais taire la raison laisserait croire que
                   le solde progressif part d'un compte neuf. --}}
              <p class="text-[13px] text-slate-400 mt-4">{{ __('pwa.comptabilite.solde_ouverture_inconnu') }}</p>
            @endif
          @endif

      </div>
    </main>
  </div>

</div>

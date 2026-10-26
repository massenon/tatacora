{{--
    Correspondance des comptes — écran AJOUTÉ par le PO le 26/10/2026 (« on peut
    impérativement modifier les comptes sur poste et le web »), absent du
    maître : `structure-ajout:m10-correspondance-comptes.html#page`.

    Châssis des écrans M10 (en-tête de page, conteneur `max-w-[1440px]`). Une
    table par groupe de rôles : produits des ventes, TVA, trésoreries, tiers,
    résultat de l'exercice. Chaque ligne : le rôle (libellé + ce qu'il fait), le
    compte ACTUEL avec son intitulé au plan, le défaut, et « Modifier » pour qui
    a le droit d'écriture sur M10.

    La phrase qui compte est en tête : un changement vaut pour les pièces
    FUTURES, une pièce déjà passée n'est jamais réécrite (RG-11).
--}}
<div class="contents">

  @include('pwa.partials.barre-superieure')

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        @include('pwa.comptabilite.partials.en-tete', [
            'tailleRetour' => 'text-[15px]',
            'icone' => '<path stroke-linecap="round" stroke-linejoin="round" d="M4 7h16M4 12h16M4 17h10"/>',
            'titre' => __('comptes_correspondance.titre'),
            'sousTitre' => e(__('comptes_correspondance.sous_titre')),
        ])

        <div class="rounded-xl p-3.5 mb-4" style="background:#FFFBEB;border:1px solid #FDE68A">
          <p class="text-[13px]" style="color:#78350F">{{ __('comptes_correspondance.avertissement') }}</p>
        </div>

        @unless ($peutEcrire)
          <p class="text-[13px] text-slate-500 mb-4">{{ __('comptes_correspondance.lecture_seule') }}</p>
        @endunless

        @foreach ($groupes as $groupe)
          @php($lignesDuGroupe = array_values(array_filter($lignes, static fn (array $l): bool => $l['groupe'] === $groupe)))
          @if ($lignesDuGroupe !== [])
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-4">
              <div class="px-4 py-3 border-b border-slate-200">
                <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('comptes_correspondance.groupe_'.$groupe) }}</h3>
              </div>
              <div class="overflow-x-auto">
                <table class="w-full text-sm">
                  <thead class="bg-[var(--navy)]"><tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
                    <th class="px-4 py-3">{{ __('comptes_correspondance.colonne_role') }}</th>
                    <th class="px-4 py-3">{{ __('comptes_correspondance.colonne_compte') }}</th>
                    <th class="px-4 py-3">{{ __('comptes_correspondance.colonne_defaut') }}</th>
                    @if ($peutEcrire)
                      <th class="px-4 py-3">{{ __('comptes_correspondance.colonne_action') }}</th>
                    @endif
                  </tr></thead>
                  <tbody>
                    @foreach ($lignesDuGroupe as $ligne)
                      <tr class="border-t border-slate-100 hover:bg-slate-50" data-role="{{ $ligne['role'] }}">
                        <td class="px-4 py-2.5">
                          <div class="text-slate-700 font-semibold">{{ $ligne['libelle'] }}</div>
                          <div class="text-[12px] text-slate-400">{{ $ligne['aide'] }}</div>
                        </td>
                        <td class="px-4 py-2.5">
                          <span class="font-mono-tatacora text-[15px] text-slate-700">{{ $ligne['actuel'] }}</span>
                          <span class="text-slate-500"> — {{ $ligne['libelleActuel'] ?? __('comptes_correspondance.libelle_inconnu') }}</span>
                          @if ($ligne['personnalise'])
                            <span class="ml-2 text-[12px] font-semibold px-2 py-0.5 rounded" style="background:#FDF3E0;color:#B8891E">{{ __('comptes_correspondance.etat_modifie') }}</span>
                          @else
                            <span class="ml-2 text-[12px] font-semibold px-2 py-0.5 rounded bg-slate-100 text-slate-600">{{ __('comptes_correspondance.etat_defaut') }}</span>
                          @endif
                        </td>
                        <td class="px-4 py-2.5 font-mono-tatacora text-[15px] text-slate-500">{{ $ligne['defaut'] }}</td>
                        @if ($peutEcrire)
                          <td class="px-4 py-2.5">
                            <button type="button" wire:click="ouvrirEditionRole('{{ $ligne['role'] }}')"
                                    class="text-[13px] px-3 py-1.5 rounded-lg border border-slate-300 hover:bg-slate-50 font-semibold">{{ __('comptes_correspondance.modifier') }}</button>
                          </td>
                        @endif
                      </tr>
                    @endforeach
                  </tbody>
                </table>
              </div>
            </div>
          @endif
        @endforeach

      </div>
    </main>
  </div>

  {{-- MODALE « Modifier le compte du rôle » — rendue SEULEMENT à l'ouverture
       (doctrine `RefuseLaSaisie`). --}}
  @if ($etatFormulaire === 'role' && $roleEdite !== null)
    <x-pwa.modale :titre="__('comptes_correspondance.modale_titre')" largeur="520px">
      <form wire:submit.prevent="enregistrerRole" class="space-y-4">
        <p class="text-[13px] font-semibold text-slate-700">{{ $definitionEditee['libelle'] }}</p>

        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('comptes_correspondance.champ_compte') }} <span class="text-red-500">*</span></label>
          <input type="text" wire:model="numeroEdite" inputmode="numeric"
                 maxlength="{{ \App\Domain\Comptabilite\Services\PlanComptableService::NUMERO_COMPTE_CHIFFRES_MAX }}"
                 placeholder="{{ $defautEdite }}"
                 class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 font-mono">
          <p class="text-[11px] text-slate-500 mt-1.5">{{ __('comptes_correspondance.champ_compte_aide') }}</p>
          <p class="text-[11px] text-slate-500 mt-1">{{ __('comptes_correspondance.role_attendu', ['attendu' => $attenduEdite]) }}</p>
          <p class="text-[11px] text-slate-500 mt-1">{{ __('comptes_correspondance.defaut_rappel', ['defaut' => $defautEdite]) }}</p>
          @error('numeroEdite') <p class="text-[11px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>

        <div class="flex justify-end gap-2 pt-2">
          <button type="button" wire:click="fermerModales"
                  class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('comptes_correspondance.annuler') }}</button>
          <button type="button" wire:click="retablirRole"
                  class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('comptes_correspondance.retablir') }}</button>
          <button type="submit"
                  class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('comptes_correspondance.enregistrer') }}</button>
        </div>
      </form>
    </x-pwa.modale>
  @endif

</div>

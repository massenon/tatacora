{{--
    UN CHAMP DE PARAMÈTRE — le bloc `groupe-champ` du maître
    (`parametres.html` l.44-65), en LECTURE : le libellé du maître à sa place
    dans la grille, la VALEUR au lieu d'un champ de saisie, et « Modifier »
    qui ouvre la modale gardée (`RefuseLaSaisie`, Article 6 — aucun formulaire
    au premier GET). Partagé par tous les onglets pour qu'une seule version
    du bloc existe.

    Attend : $ligne (['definition' => DefinitionParametre, 'valeur' => ?string]),
    $peutEcrire (bool), $colspan (bool, optionnel — les champs que le maître
    étale sur `sm:col-span-2`).
--}}
<div class="groupe-champ{{ ! empty($colspan) ? ' sm:col-span-2' : '' }}">
  <p class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ $ligne['definition']->libelle }}</p>

  <div class="flex items-center gap-2">
    {{-- ⚠ ARTICLE 7 — « — » quand la clé n'est PAS renseignée, « 0 » quand
         elle vaut zéro. Les confondre ferait croire l'arbitrage de PA-53
         rendu. Un type `choix` affiche le LIBELLÉ de sa valeur (la carte
         unique du registre), jamais le code stocké. --}}
    {{-- Un booléen se DIT (Oui/Non), jamais « true »/« false » — trouvé au
         passage navigateur du 02/09/2026 sur « Assujettissement à la TVA ». --}}
    <p class="text-[13px] font-mono-tatacora px-2.5 py-1 rounded bg-slate-100 text-slate-600">{{
        $ligne['valeur'] === null
            ? '—'
            : ($ligne['definition']->type === 'choix'
                ? $ligne['definition']->libelleDuChoix($ligne['valeur'])
                : ($ligne['definition']->type === 'booleen'
                    ? ($ligne['valeur'] === 'true' ? __('parametres_pwa.oui') : __('parametres_pwa.non'))
                    : $ligne['valeur']))
    }}</p>

    @if ($peutEcrire)
      <button type="button" wire:click="ouvrirEditionParametre('{{ $ligne['definition']->cle }}')"
              class="text-[12px] font-semibold px-3 py-1.5 rounded-lg border border-slate-200 hover:bg-slate-50 shrink-0">{{ __('parametres_pwa.modifier') }}</button>
    @endif
  </div>

  @if ($ligne['definition']->aide !== null)
    <p class="text-[12px] text-slate-400 mt-1.5">{{ $ligne['definition']->aide }}</p>
  @endif
</div>

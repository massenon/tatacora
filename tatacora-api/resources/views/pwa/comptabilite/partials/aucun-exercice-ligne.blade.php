{{--
    L'état « aucun exercice choisi » rendu DANS le tableau de l'écran — même
    message (mêmes clés de langue, un seul auteur des mots) que le bloc
    `aucun-exercice.blade.php`, porté ici en ligne unique de `<tbody>`.

    Pourquoi cette variante existe (02/09/2026, G5) : le maître rend TOUJOURS
    la structure de ses tableaux — un écran M10 sans exercice choisi doit donc
    montrer l'entête de son tableau (ce que la page rendra) au-dessus du
    message qui dit quoi faire (Article 7), jamais un panneau à la place du
    tableau. `ColonnesDesTableauxPwaTest` mesure ce rendu au premier GET.

    Attend : `$colonnes` (nombre de colonnes du tableau porteur) et la
    collection `$exercices` du socle M10.
--}}
<tr>
  <td colspan="{{ $colonnes }}" class="py-14 px-5 text-center">
    <p class="text-[15px] font-semibold" style="color:var(--navy)">{{ __('pwa.comptabilite.aucun_exercice_titre') }}</p>
    <p class="text-[13px] text-slate-500 mt-2 max-w-[640px] mx-auto">
      @if ($exercices->isEmpty())
        {{ __('pwa.comptabilite.aucun_exercice_ouvert') }}
      @else
        {{ __('pwa.comptabilite.aucun_exercice_detail') }}
      @endif
    </p>
  </td>
</tr>

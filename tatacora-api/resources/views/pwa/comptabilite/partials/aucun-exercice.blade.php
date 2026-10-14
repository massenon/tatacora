{{--
    L'état « aucun exercice choisi » — Article 7 : un écran vide DIT pourquoi
    il est vide et ce qu'il faut faire, il ne reste jamais blanc.

    Deux messages distincts, et les confondre serait le défaut :
    — aucun exercice n'a été CHOISI (le référentiel en contient) : on explique
      la règle comptable et on renvoie au sélecteur, juste au-dessus ;
    — aucun exercice n'EXISTE : le référentiel est vide, et aucun choix ne
      peut sortir de là. C'est une saisie à faire dans l'application, pas ici.

    Le second cas est celui de PA-128 : un message honnête décrivant un état
    dont aucun chemin de cet écran ne permet de sortir doit dire OÙ est le
    chemin, sinon il décrit une impasse.
--}}
<div class="bg-white rounded-xl border border-slate-200 py-14 px-5 text-center">
  <p class="text-[15px] font-semibold" style="color:var(--navy)">{{ __('pwa.comptabilite.aucun_exercice_titre') }}</p>
  <p class="text-[13px] text-slate-500 mt-2 max-w-[640px] mx-auto">
    @if ($exercices->isEmpty())
      {{ __('pwa.comptabilite.aucun_exercice_ouvert') }}
    @else
      {{ __('pwa.comptabilite.aucun_exercice_detail') }}
    @endif
  </p>
</div>

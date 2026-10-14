{{--
    Le SQUELETTE d'un tableau d'onglet du hub M10 (02/09/2026, G5).

    Le hub rend désormais les DIX panneaux d'onglet à chaque GET — l'actif
    visible, les autres `hidden` — pour que la structure de chaque tableau du
    maître existe dès le premier GET (`ColonnesDesTableauxPwaTest`). Un
    panneau inactif ne calcule RIEN : son tableau porte l'entête réelle de
    l'onglet (même auteur, `_entetes`) et une ligne unique qui dit pourquoi
    il est vide — jamais des chiffres qu'aucun calcul n'a produits
    (PA-59/60/61).

    Attend : `$colonnes` (les couples [libellé, alignement] de l'onglet) et
    `$message` (l'état réel : exercice non choisi, ou onglet non ouvert).
--}}
<div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
  <div class="overflow-x-auto">
    <table class="w-full text-[13px] compta" style="white-space: nowrap">
      @include('pwa.comptabilite.onglets._entetes', ['colonnes' => $colonnes])
      <tbody>
        <tr><td colspan="{{ count($colonnes) }}" class="py-14 px-5 text-center text-slate-400 text-[13px]" style="white-space: normal">{{ $message }}</td></tr>
      </tbody>
    </table>
  </div>
</div>

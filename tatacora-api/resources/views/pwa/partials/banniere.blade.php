{{--
    BANDEAU DE LA COQUILLE — `#shell-banniere`, deuxième des quatre blocs du
    `<body>` du maître (`prototype_v2/pages/tableau-de-bord.html`), rempli par
    `afficherBanniereLectureSeule()` (`shell.js` l.237-251).

    ## Le bandeau qui mentait, et ce qui l'a remplacé

    Jusqu'au 28/08/2026 les pages affichaient en permanence « Cette interface
    web sert à consulter. Toute saisie se fait depuis l'application
    TATACORA. » — faux dès la première écriture, et faux sur l'écran même qui
    portait le bouton « Ajouter fournisseur ». La phrase a été retirée ; le
    bloc, lui, ne l'a pas été : le maître laisse la zone VIDE quand il n'a
    rien à dire, il ne la supprime pas, et `ConformiteMaquettePwaTest` fige la
    présence et l'ORDRE des quatre blocs de la coquille.

    ## Trois états, et l'état dérive de DEUX choses

    `App\Pwa\Support\BanniereEcriture::pour()` croise le droit RBAC et ce que
    l'écran OFFRE réellement — un `trait AutoriseEcriture` et une constante
    `MODULE`. Les deux moitiés comptent, et c'est le point :

    - `aucune`         → rien n'est rendu. Le rôle peut écrire ici.
    - `lecture_seule`  → le bandeau du maître, mot pour mot, avec son bouton.
    - `module_non_ouvert` → un écran dont CE canal n'offre pas encore la
      saisie. Le droit ne crée pas la fonction : un `gérant` avec `C` sur le
      module voit ce bandeau-là, parce qu'il décrit l'écran, pas le profil.

    ⚠ L'état « non ouvert » n'a AUCUN équivalent au maître, qui offre le CRUD
    partout. Il nomme un manque TRANSITOIRE de ce canal, jamais un état final
    (`DIRECTIVE_CONFORMITE_100.md` Article 3.3) : sa formulation le dit, et
    aucun bouton « changer de profil » ne l'accompagne — un autre profil n'y
    gagnerait rien, la fonction n'existe pour personne.

    ## Un seul écart de libellé avec le maître, et il est motivé

    Le maître écrit « les boutons Modifier / Dupliquer / Supprimer sont
    volontairement masqués ». Les trois boutons ne sont pas ceux de la PWA —
    le « D » de CRUD n'existe nulle part au dépôt (`BasePolicy::delete()`
    renvoie `false` pour les vingt policies), et nommer un bouton
    « Supprimer » que personne ne verra jamais ferait chercher une fonction
    qui n'existe pas. La phrase dit donc « les actions d'écriture », et le
    reste est mot pour mot celui du maître (`pwa.coquille.banniere_*`).
--}}
<div id="shell-banniere">
  @if ($banniere['etat'] === \App\Pwa\Support\BanniereEcriture::LECTURE_SEULE)
    <div class="bg-amber-50 border-b-2 border-amber-300 px-6 py-3 flex flex-col sm:flex-row sm:items-center gap-2 text-amber-900 text-xs">
      <div class="flex items-center gap-2">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="shrink-0"><path stroke-linecap="round" stroke-linejoin="round" d="M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/></svg>
        <span><strong>{{ __('pwa.coquille.banniere_lecture_titre') }}</strong> {{ __('pwa.coquille.banniere_lecture_detail') }}</span>
      </div>
      {{-- Le bouton du maître (`shell.js` l.246), dont l'action est ici celle
           de la coquille Livewire : `RBAC.deconnecter()` du prototype devient
           `seDeconnecter`, le SEUL chemin de fermeture de session du dépôt
           (trait `FermeSession`), déjà emprunté par le pied du menu latéral
           et par le menu de compte. --}}
      <button id="bouton-changer-compte-banniere" type="button" wire:click="seDeconnecter" class="sm:ml-auto shrink-0 bg-amber-900 text-white text-[11px] font-semibold px-3 py-1.5 rounded-lg hover:bg-amber-800">
        {{ __('pwa.coquille.banniere_changer_profil') }}
      </button>
    </div>
  {{-- L'etat « module non ouvert » a ete retire le 31/08/2026 : le
       maitre n'affiche la banniere QUE en lecture seule (shell.js l.269),
       jamais pour un ecran de consultation. Voir BanniereEcriture. --}}
  @endif
</div>

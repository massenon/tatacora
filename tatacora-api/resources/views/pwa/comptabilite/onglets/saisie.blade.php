{{--
    Onglet « Passer écriture » du hub — maître :
    `prototype_v2/pages/m10-syscohada.js` `vueSaisie()` l.68-137.

    ## ÉCART DE MÉCANISME ACCEPTÉ — le formulaire n'est pas ici, la modale l'est

    Le maître pose le `<form>` DIRECTEMENT dans l'onglet, toujours visible dès
    qu'on l'ouvre. La doctrine `RefuseLaSaisie` de ce dépôt interdit qu'un
    `<form>` d'écriture se rende au premier GET (`tests/Feature/Pwa/Concerns/RefuseLaSaisie`) —
    et l'onglet « saisie » est désormais `ONGLET_DEFAUT` (comme au maître),
    donc le PREMIER rendu de toute la page. Le brief de cette vague accepte
    explicitement cet écart : « Aucun formulaire ne se rend au premier GET
    (doctrine RefuseLaSaisie) : les modales du maître toujours-dans-le-DOM se
    rendent derrière `@if($etatFormulaire...)`. C'est un écart de MÉCANISME
    accepté, pas de visuel. » Le contenu du formulaire — mêmes champs, même
    ordre, mêmes contrôles — est transcrit tel quel dans la modale `piece`
    (`hub.blade.php`).

    L'encadré gris des contrôles (maître l.77-79) reste ici, sur l'onglet :
    c'est de l'information, pas de la saisie.
--}}
<div class="rounded-xl p-3.5 mb-4" style="background:#F8FAFC;border:1px solid #E2E8F0">
  <p class="text-[13px]" style="color:#334155">
    <strong>{{ __('comptabilite_pwa.saisie_intro_titre') }}</strong>
    {{ __('comptabilite_pwa.saisie_intro_detail') }}
  </p>
</div>

@if ($exercice === null || $exercice->statut !== 'ouvert')
  <div class="rounded-xl p-3.5 mb-4" style="background:#FEF2F2;border:1px solid #FECACA">
    <p class="text-[13px]" style="color:#7F1D1D">
      <strong>{{ __('comptabilite_pwa.saisie_aucun_exercice') }}</strong>
      {{ __('comptabilite_pwa.saisie_aucun_exercice_detail') }}
    </p>
  </div>
@else
  <div class="bg-white rounded-xl border border-slate-200 p-4 flex items-center justify-between">
    <p class="text-[13px] text-slate-500">{{ __('comptabilite_pwa.saisie_intro_detail') }}</p>
    <button type="button" wire:click="ouvrirFormulairePiece"
            class="shrink-0 ml-4 text-[13px] px-4 py-2.5 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">
      + {{ __('comptabilite_pwa.saisie_bouton') }}
    </button>
  </div>
@endif

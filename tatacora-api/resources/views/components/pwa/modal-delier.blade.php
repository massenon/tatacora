{{--
    « DÉLIER » — le DIALOGUE PARTAGÉ du maître, pas une troisième forme.

    Maître : prototype_v2/pages/m4-restaurant-carte.html, dont l'action est
    déclenchée par prototype_v2/pages/carte-module.js l.428-440 —
    `Dialogue.confirmer({ ton: 'alerte', … })`, rendu par
    `prototype_v2/assets/js/modal.js` l.121-148.

    ## Le maître N'ÉCRIT PAS cette modale, il appelle un dialogue

    La PWA en avait fait une forme à elle, différente des deux autres et du
    dialogue : icône `w-12 h-12` posée AU-DESSUS du texte au lieu de `w-9 h-9`
    à côté, titre `text-lg slate-800` au lieu de `text-[14px]` en `var(--navy)`,
    message `13.5px` et détail `12.5px` au lieu de `13px` et `11.5px`, boîte
    `rounded-2xl max-w-[460px]` au lieu de `rounded-xl max-w-md`, et AUCUNE
    barre de pied — les boutons flottaient dans le `p-6`.

    Le ton `alerte` du maître (`modal.js` l.77) donne le fond `#FFFBEB`, la
    bordure `#FDE68A`, le texte `#B45309` et le bouton `#B8891E`. Le doré du
    bouton était déjà exact ; il est conservé tel quel.

    ## Le voile vient du châssis, la disposition vient du dialogue

    `.overlay-modale` porte `rgba(0,0,0,.5)` + `blur(2px)` et `.boite-modale`
    porte le rayon de 12 px, `max-height:90vh` et `overflow-y:auto`
    (`app.css` l.93-124). Le dialogue du maître pose son propre voile
    `bg-black/45` : c'est le seul point où les deux se contredisent, et c'est
    le châssis qui gagne — il est la règle de TOUTES les modales de la PWA, et
    le maître lui-même a deux voiles selon le fichier. Le reste — icône et
    texte CÔTE À CÔTE, barre de pied grise — est celui du dialogue.

    ⚠ `style="display:flex"` est OBLIGATOIRE sur l'overlay : `.overlay-modale`
    est `opacity:0; pointer-events:none` par défaut (app.css l.114-117). Sans
    lui, la modale est dans le DOM, invisible et inerte — et un test de rendu
    la trouverait pourtant.

    Props :
      titre     — la question
      message   — la conséquence, en une phrase
      detail    — la ligne secondaire, en plus petit
      confirmer — libellé du bouton d'action
      action    — méthode Livewire appelée à la confirmation
      fermer    — action Livewire de fermeture
--}}
@props([
    'titre',
    'message',
    'detail' => null,
    'confirmer',
    'action',
    'fermer' => "\$set('etatFormulaire', null)",
])
<div class="overlay-modale no-print" style="display:flex"
     role="dialog" aria-modal="true" aria-labelledby="dlg-delier-titre"
     wire:keydown.escape.window="{{ $fermer }}">
    {{-- Capteur de clic TRANSPARENT : le voile est celui de `.overlay-modale`. --}}
    <div class="absolute inset-0" wire:click="{{ $fermer }}"></div>

    {{-- maître — modal.js l.128 : `rounded-xl w-full max-w-md`. --}}
    <div class="boite-modale relative" style="max-width:28rem">

        {{-- maître — modal.js l.129-137 : icône et texte CÔTE À CÔTE. --}}
        <div class="flex items-start gap-3 px-5 pt-5 pb-4">
            <div class="w-9 h-9 rounded-full shrink-0 flex items-center justify-center text-[16px] font-bold"
                 style="background:#FFFBEB;border:1px solid #FDE68A;color:#B45309">!</div>
            <div class="flex-1 min-w-0">
                <h2 id="dlg-delier-titre" class="text-[14px] font-bold" style="color:var(--navy)">{{ $titre }}</h2>
                <p class="text-[13px] text-slate-600 mt-1 leading-relaxed">{{ $message }}</p>
                @if ($detail)
                    <p class="text-[11.5px] text-slate-400 mt-2 leading-relaxed">{{ $detail }}</p>
                @endif
            </div>
        </div>

        {{-- maître — modal.js l.144-148 : barre GRISE, boutons à droite. --}}
        <div class="flex justify-end gap-2.5 px-5 py-3 border-t border-slate-100 bg-slate-50">
            <button type="button" wire:click="{{ $fermer }}"
                    class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 bg-white hover:bg-slate-50 font-medium">{{ __('pwa.modale.annuler') }}</button>
            <button type="button" wire:click="{{ $action }}" wire:loading.attr="disabled"
                    class="text-[13px] px-4 py-2 rounded-lg text-white font-semibold hover:brightness-110"
                    style="background:#B8891E">{{ $confirmer }}</button>
        </div>
    </div>
</div>

{{--
    CHASSIS DE MODALE PARTAGE DE LA PWA — le gabarit du maitre, une fois.

    Maitre : `prototype_v2/assets/js/crud-ui.js` l.85-160 (les cinq gabarits de
    modale du prototype) et `prototype_v2/assets/css/app.css` l.93-124
    (`.overlay-modale`, `.boite-modale`).

    ## Pourquoi ce composant existe

    Les conteneurs de modale de la PWA reimplementaient le chrome a la main, et
    chacun avait derive dans son coin : voile `bg-black/45` la ou le maitre pose
    `.5`, aucun `backdrop-blur`, rayon `rounded-lg` (8 px) ou `rounded-2xl`
    (16 px) la ou `.boite-modale` fait 12 px.

    ⚠ Le defaut qui comptait n'etait pas cosmetique : `overflow-hidden` SANS
    limite de hauteur. `.boite-modale` porte `max-height:90vh; overflow-y:auto`
    — sans elles, une modale plus haute que la fenetre est TRONQUEE et non
    defilable, et le bouton « Enregistrer » devient inatteignable sur un
    portable 1366x768. Le formulaire s'ouvre, s'affiche, et ne peut pas etre
    valide ; rien a l'ecran ne dit pourquoi.

    ## Le voile, et pourquoi il n'y en a qu'un

    `.overlay-modale` porte DEJA `rgba(0,0,0,.5)` et `backdrop-filter: blur(2px)`.
    Superposer un `<div class="fixed inset-0 bg-black/50">` par-dessus, comme le
    faisait `modale-formulaire.blade.php`, double l'opacite : le fond passe a
    75 %. Le capteur de clic pose ici est donc TRANSPARENT — il ferme la modale,
    il ne teinte rien.

    ## Etat d'ouverture

    `.overlay-modale` est `opacity: 0; pointer-events: none` par defaut : elle
    n'apparait qu'avec la classe `.ouverte` ou l'attribut `style="display:flex"`
    (app.css l.114-117). La PWA construit sa modale au moment de l'ouvrir, comme
    les huit fichiers du maitre qui font de meme : c'est la seconde forme qui
    s'applique. La retirer rendrait la modale presente dans le DOM, invisible et
    inerte — un test de rendu la trouverait pourtant.

    Props :
      titre      — titre de l'en-tete (obligatoire)
      sousTitre  — ligne d'explication sous le titre (optionnel)
      largeur    — `max-width` de la boite (defaut 560px, comme le maitre)
      fermer     — nom de l'action Livewire de fermeture (defaut `fermerModales`)

    Slots :
      (defaut)   — le corps, deja dans `p-6 space-y-4`
      pied       — la barre de boutons, sur le fond gris du maitre. Absente si
                   le slot n'est pas fourni : une barre vide serait un bandeau
                   gris sans objet.

    Boutons standards attendus dans le pied (maitre, `crud-ui.js` l.97-99) :
      Annuler  : text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50
      Valider  : text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold
--}}
@props([
    'titre',
    'sousTitre' => null,
    'largeur' => '560px',
    'fermer' => 'fermerModales',
])
<div class="overlay-modale no-print" style="display:flex" wire:keydown.escape.window="{{ $fermer }}">
    {{-- Capteur de clic TRANSPARENT : le voile est celui de `.overlay-modale`. --}}
    <div class="absolute inset-0" wire:click="{{ $fermer }}"></div>

    <div class="boite-modale relative" style="max-width:{{ $largeur }}">
        <div class="flex items-center justify-between px-6 py-4 border-b border-slate-100">
            <div>
                <h2 class="text-base font-bold" style="color:var(--navy)">{{ $titre }}</h2>
                @if ($sousTitre)
                    <p class="text-[12px] text-slate-500 mt-0.5">{{ $sousTitre }}</p>
                @endif
            </div>
            <button type="button" wire:click="{{ $fermer }}"
                    class="text-slate-400 hover:text-slate-700 text-lg"
                    aria-label="{{ __('pwa.modale.fermer') }}">✕</button>
        </div>

        <div class="p-6 space-y-4">
            {{ $slot }}
        </div>

        @isset($pied)
            <div class="flex justify-end gap-2 px-6 py-4 border-t border-slate-100 bg-slate-50 rounded-b-xl">
                {{ $pied }}
            </div>
        @endisset
    </div>
</div>

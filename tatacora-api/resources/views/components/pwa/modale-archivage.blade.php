{{--
    MODALE DE CONFIRMATION — et le maitre N'Y SUPPRIME PAS, il ARCHIVE.

    Maitre : `prototype_v2/assets/js/crud-ui.js` l.123-140 (le chrome) et
    `prototype_v2/assets/js/crud-engine.js` l.523-551 (les trois etats).

    ## Trois etats, et le premier est celui qui compte

    1. BLOQUE — tous les elements vises sont engages ailleurs (`Verrous`). Le
       maitre affiche « Archivage impossible », liste les motifs, et MASQUE le
       bouton de confirmation (`bouton.classList.add('hidden')`). Le laisser
       visible et inerte laisserait croire a une panne ; le masquer dit que la
       decision n'appartient pas a cet ecran.
    2. PARTIEL — une partie seulement est bloquee : le geste part, et l'ecran
       annonce AVANT le clic combien d'elements resteront. Un decompte affiche
       apres coup serait une surprise.
    3. NOMINAL — la question, puis le rappel : rien n'est efface.

    ## Le titre du maitre dit « suppression », le corps dit « archiver »

    Ce n'est pas une incoherence a lisser : le titre et le bouton sont le texte
    que le client a valide (`crud-ui.js` l.131 et l.136), et le corps est ce
    que l'utilisateur lit juste avant de cliquer. Cote serveur, aucun de ces
    boutons ne supprime quoi que ce soit — `BasePolicy::delete()` rend `false`
    pour les 20 policies, et deux `Observer` levent a `deleting()`.

    Props :
      action           — methode Livewire appelee a la confirmation (obligatoire)
      titre            — defaut « Confirmer la suppression » (maitre)
      message          — la question, en TEXTE (echappe). Defaut : la question
                         du maitre, construite a partir d'`element`.
      element          — nom de l'element vise, rendu en gras comme au maitre.
      nombre           — nombre d'elements vises (question au pluriel).
      messagesVerrou   — motifs de blocage, un par ligne (defaut [])
      bloque           — true : plus rien n'est archivable, le bouton disparait
      conserves        — nombre d'elements qui resteront (etat PARTIEL, defaut 0)
      libelleConfirmer — defaut « Supprimer definitivement » (maitre)
      fermer           — action Livewire de fermeture (defaut `fermerModales`)
--}}
@props([
    'action',
    'titre' => null,
    'message' => null,
    'element' => null,
    'nombre' => null,
    'messagesVerrou' => [],
    'bloque' => false,
    'conserves' => 0,
    'libelleConfirmer' => null,
    'fermer' => 'fermerModales',
])
<div class="overlay-modale no-print" style="display:flex" wire:keydown.escape.window="{{ $fermer }}">
    {{-- Capteur de clic TRANSPARENT : le voile vient de `.overlay-modale`. --}}
    <div class="absolute inset-0" wire:click="{{ $fermer }}"></div>

    {{-- maitre — `crud-ui.js` l.126 : 420px, et pas la largeur des autres. --}}
    <div class="boite-modale relative" style="max-width:420px">
        <div class="p-6 text-center">
            {{-- maitre — `crud-ui.js` l.128-130 --}}
            <div class="w-14 h-14 rounded-full bg-red-50 flex items-center justify-center mx-auto mb-4">
                <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="var(--erreur)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M3 6h18M8 6V4a2 2 0 012-2h4a2 2 0 012 2v2m3 0v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6h14z"/></svg>
            </div>

            <h2 class="text-base font-bold text-slate-800 mb-2">{{ $titre ?? __('pwa.archivage.titre') }}</h2>

            <p class="text-sm text-slate-500 leading-relaxed">
                @if ($bloque)
                    {{-- ETAT 1 — plus rien n'est archivable. --}}
                    <span class="block font-semibold text-[var(--erreur)] mb-1.5">{{ __('pwa.archivage.impossible') }}</span>
                    @foreach ($messagesVerrou as $motif)
                        <span class="block text-slate-600">{{ $motif }}</span>
                    @endforeach
                    <span class="block text-slate-500 mt-2">{{ __('pwa.archivage.retirer_dabord') }}</span>
                @else
                    {{-- ETAT 3 — la question. Le nom de l'element est rendu en
                         gras comme au maitre, et il passe par `e()` AVANT
                         d'entrer dans la phrase : la seule facon d'avoir le
                         <strong> du maitre sans ouvrir une injection. --}}
                    @if ($message !== null)
                        {{ $message }}
                    @elseif ($nombre !== null)
                        {!! __('pwa.archivage.question_multiple', ['nombre' => '<strong>' . e((string) $nombre) . '</strong>']) !!}
                    @else
                        {!! __('pwa.archivage.question', ['element' => '<strong>' . e((string) $element) . '</strong>']) !!}
                    @endif

                    {{-- Le rappel du maitre : son <strong> fait partie du texte
                         valide, et la chaine vient de `lang/fr` — aucune donnee
                         d'utilisateur n'y entre. --}}
                    <span class="block text-slate-500 mt-2">{!! __('pwa.archivage.rappel') !!}</span>

                    @if ($conserves > 0)
                        {{-- ETAT 2 — partiel. --}}
                        <span class="block text-[var(--alerte)] mt-2">{{ __('pwa.archivage.conserves', ['nombre' => $conserves]) }}</span>
                    @endif

                    @foreach ($messagesVerrou as $motif)
                        <span class="block text-slate-600 mt-1">{{ $motif }}</span>
                    @endforeach
                @endif
            </p>
        </div>

        {{-- maitre — `crud-ui.js` l.134-137 : boutons CENTRES, pas alignes a droite. --}}
        <div class="flex justify-center gap-3 px-6 pb-6">
            <button type="button" wire:click="{{ $fermer }}"
                    class="btn px-5 py-2.5 rounded-lg border border-slate-200 bg-white text-sm font-semibold text-slate-600">{{ __('pwa.modale.annuler') }}</button>
            @unless ($bloque)
                <button type="button" wire:click="{{ $action }}"
                        class="btn px-5 py-2.5 rounded-lg bg-[var(--erreur)] text-white text-sm font-semibold">{{ $libelleConfirmer ?? __('pwa.archivage.confirmer') }}</button>
            @endunless
        </div>
    </div>
</div>

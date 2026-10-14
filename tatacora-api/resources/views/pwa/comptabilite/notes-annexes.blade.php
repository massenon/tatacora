{{--
    Notes Annexes — maître : `prototype_v2/pages/m10-notes-annexes.html`.

    Conteneur `max-w-[900px] mx-auto p-5 lg:p-8` (l.18), lien de retour en
    `text-[13px]` (l.21), en-tête (l.20-30), puis la pile `space-y-4` (l.32) de
    cartes `bg-white rounded-xl border border-slate-200 p-5`, chacune avec son
    `<h2 class="text-[15px] font-bold text-slate-800 mb-3">` numéroté (l.80-83).

    Les sept notes, leurs numéros et leurs titres viennent de
    `NotesAnnexesService` — jamais réécrits ici (`LARAVEL_PWA.md` §3). Les
    écarts sont motivés au complet dans
    `App\Pwa\Livewire\Comptabilite\NotesAnnexes`.
--}}
@php
    use App\Pwa\Support\MontantFcfa;
@endphp
<div class="contents">

  @include('pwa.partials.barre-superieure')
  

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[900px] mx-auto p-5 lg:p-8">

        @include('pwa.comptabilite.partials.en-tete', [
            'tailleRetour' => 'text-[13px]',
            'icone' => '<path stroke-linecap="round" stroke-linejoin="round" d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><path stroke-linecap="round" stroke-linejoin="round" d="M14 2v6h6"/><path stroke-linecap="round" d="M16 13H8M16 17H8M10 9H8"/>',
            'titre' => 'Notes Annexes',
            'sousTitre' => "Compléments d'information au Bilan et au Compte de Résultat",
        ])

        @include('pwa.comptabilite.partials.socle', [
            'identifiant' => 'f-exercice',
            'repartition' => $notes?->statuts,
        ])

        @if ($exercice === null)
          @include('pwa.comptabilite.partials.aucun-exercice')
        @else

          <div class="space-y-4">
            @foreach ($notes->notes as $note)
              <div class="bg-white rounded-xl border border-slate-200 p-5">
                <h2 class="text-[15px] font-bold text-slate-800 mb-3">{{ $note->numero }}. {{ $note->titre }}</h2>

                @if ($note->texte !== null)
                  <p class="text-[15px] text-slate-600 leading-relaxed">{{ $note->texte }}</p>
                @endif

                @if ($note->postes !== [])
                  <div class="space-y-1">
                    @foreach ($note->postes as $poste)
                      <div class="flex justify-between text-[15px]">
                        <span class="text-slate-600">{{ $poste['libelle'] }}</span>
                        <span class="font-mono-tatacora text-slate-700">{{ MontantFcfa::format($poste['montant']) }}</span>
                      </div>
                    @endforeach
                  </div>
                @endif

                @if ($note->motif !== null)
                  {{-- Article 7 : une note vide DIT pourquoi elle est vide. Le
                       motif est un code fermé du serveur, traduit dans
                       `lang/fr/pwa.php` — et jamais une phrase sur le jeu de
                       démonstration, qui cesserait d'être vraie sans que
                       personne ne la rouvre (PA-144). --}}
                  <p class="text-[13px] text-slate-400 italic{{ $note->postes !== [] || $note->texte !== null ? ' mt-2' : '' }}">
                    {{ __('pwa.comptabilite.motifs.' . $note->motif) }}
                  </p>
                @endif

                @if ($note->texte === null && $note->postes === [] && $note->motif === null)
                  {{-- Ni contenu ni motif : c'est un défaut du Service, pas un
                       état normal. Le taire produirait une carte vide qui
                       passerait pour un écran cassé. --}}
                  <p class="text-[13px] text-slate-400 italic">{{ __('pwa.comptabilite.note_etats.' . $note->etat) }}</p>
                @endif
              </div>
            @endforeach
          </div>
        @endif

      </div>
    </main>
  </div>

</div>

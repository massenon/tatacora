{{--
    SÉLECTEUR D'EXERCICE de la barre supérieure — AJOUT à la maquette,
    décision du PO du 20/10/2026 (`docs/SPEC_SELECTEUR_EXERCICE.md`, R1/R3).
    Voir le docblock de `App\Pwa\Livewire\Transverse\SelecteurExercice`.
--}}
@php
  // Les trois statuts, clés ÉCRITES (une clé composée ne se relit pas).
  $libellesStatut = [
      'ouvert' => __('pwa.coquille.exercice_statuts.ouvert'),
      'en_cloture' => __('pwa.coquille.exercice_statuts.en_cloture'),
      'cloture' => __('pwa.coquille.exercice_statuts.cloture'),
  ];
@endphp
<div id="selecteur-exercice" class="{{ $visible && $exercices->isNotEmpty() ? 'hidden md:flex' : 'hidden' }} items-center gap-2 mr-3">
  @if ($visible && $exercices->isNotEmpty())
    <label for="choix-exercice" class="text-white/60 text-[11px]">{{ __('pwa.coquille.exercice_consulte') }}</label>
    <select id="choix-exercice" wire:model.live="exerciceId"
            class="text-xs font-semibold rounded-lg px-2.5 py-1.5 bg-white/10 text-white border border-white/20">
      @foreach ($exercices as $unExercice)
        <option value="{{ $unExercice->id }}" class="text-slate-800">{{ __('pwa.coquille.exercice_option', [
            'annee' => $unExercice->annee,
            'statut' => $libellesStatut[$unExercice->statut] ?? $unExercice->statut,
        ]) }}</option>
      @endforeach
    </select>
    @if ($autreQueDefaut && $consulte !== null && $defaut !== null)
      {{-- R3 : l'année consultée n'est pas l'année en cours — on le voit, et on y revient d'un clic. --}}
      <span id="pastille-exercice"
            class="text-[11px] font-semibold px-2 py-1 rounded-full {{ $consulte->statut === 'en_cloture' ? 'bg-amber-100 text-amber-900' : ($consulte->statut === 'cloture' ? 'bg-slate-200 text-slate-700' : 'bg-white/15 text-white') }}">
        {{ __('pwa.coquille.exercice_pastille', ['annee' => $consulte->annee, 'statut' => $libellesStatut[$consulte->statut] ?? $consulte->statut]) }}
      </span>
      <button type="button" wire:click="revenir" id="revenir-exercice"
              class="text-[11px] text-[var(--gold)] hover:underline">{{ __('pwa.coquille.exercice_revenir', ['annee' => $defaut->annee]) }}</button>
    @endif
  @endif
</div>

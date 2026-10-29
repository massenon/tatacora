{{--
    UN CHAMP DES ÉCRANS « INVITÉ » (changement de mot de passe, mot de passe
    administrateur perdu) : le `.groupe-champ` de la connexion — étiquette en
    capitales AU-DESSUS, pictogramme à gauche, bordure `slate-300`, erreur
    dessous (`.message-erreur`). Pour un mot de passe, l'œil afficher/masquer
    (Alpine, purement client : il ne touche que l'attribut `type`).

    Paramètres : `id`, `etiquette`, `modele` (propriété Livewire), `icone`
    (clé de `pictogramme-connexion`), `secret` (bool), `autocomplete`.
--}}
@props([])
<div class="groupe-champ" @if ($secret ?? false) x-data="{ visible: false }" @endif>
  <label for="{{ $id }}" class="block text-[12px] font-bold tracking-wider text-slate-800 mb-1.5">{{ $etiquette }}</label>
  <div class="relative">
    <span class="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-500 pointer-events-none">@include('pwa.partials.pictogramme-connexion', ['nom' => $icone, 'taille' => 20])</span>
    <input id="{{ $id }}" name="{{ $id }}" wire:model="{{ $modele }}" autocomplete="{{ $autocomplete ?? 'off' }}" aria-required="true"
           @if ($secret ?? false) type="password" :type="visible ? 'text' : 'password'" @else type="text" @endif
           @error($modele) aria-invalid="true" aria-describedby="erreur-{{ $id }}" @enderror
           class="champ w-full h-[52px] border border-slate-300 hover:border-slate-400 rounded-xl pl-11 {{ ($secret ?? false) ? 'pr-12' : 'pr-3.5' }} text-base @error($modele) champ-erreur @enderror">
    @if ($secret ?? false)
      <button type="button" @click="visible = !visible" :aria-pressed="visible ? 'true' : 'false'" :aria-label="visible ? '{{ __('pwa.connexion.masquer_mot_de_passe') }}' : '{{ __('pwa.connexion.afficher_mot_de_passe') }}'" aria-label="{{ __('pwa.connexion.afficher_mot_de_passe') }}" aria-pressed="false"
              class="absolute right-1.5 top-1/2 -translate-y-1/2 w-10 h-10 flex items-center justify-center rounded-lg text-slate-500 hover:text-slate-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--navy)]">
        <span x-show="!visible">@include('pwa.partials.pictogramme-connexion', ['nom' => 'oeil', 'taille' => 20])</span>
        <span x-show="visible" x-cloak>@include('pwa.partials.pictogramme-connexion', ['nom' => 'oeil_barre', 'taille' => 20])</span>
      </button>
    @endif
  </div>
  <p id="erreur-{{ $id }}" class="message-erreur" @error($modele) role="alert" @enderror>@error($modele){{ $message }}@enderror</p>
</div>

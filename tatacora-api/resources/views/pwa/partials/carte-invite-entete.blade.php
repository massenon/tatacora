{{--
    L'EN-TÊTE DE MARQUE des écrans « invité » qui suivent la connexion (changement
    de mot de passe obligatoire, mot de passe administrateur perdu) : le logo
    téléversé s'il existe, sinon le pictogramme, puis « LogiReStock » en deux
    tons et son sous-titre. Mêmes jetons (`--navy`, `--gold`) et mêmes
    pictogrammes que `livewire/connexion.blade.php`, dont ce bloc reprend le
    haut de carte — sans le slogan ni le bandeau de modules, propres à la
    connexion.
--}}
@php($logoTeleverse = app(\App\Shared\Parametres\Services\ApparenceEtablissementService::class)->fichierDe('logo') !== null)
@if ($logoTeleverse)
  <img src="{{ app(\App\Shared\Parametres\Services\ApparenceEtablissementService::class)->urlLogo() }}" alt="{{ __('pwa.alt_logo') }}" class="block mx-auto h-16 w-auto max-w-full object-contain mb-4">
@endif
<div class="flex items-center justify-center gap-3">
  @unless ($logoTeleverse)
    <span class="shrink-0" style="color:var(--navy)">@include('pwa.partials.pictogramme-connexion', ['nom' => 'marque', 'taille' => 40])</span>
  @endunless
  <div class="min-w-0">
    <p class="text-[28px] font-extrabold leading-none"><span style="color:var(--navy)">{{ __('pwa.connexion.marque_logi') }}</span><span style="color:var(--gold)">{{ __('pwa.connexion.marque_restock') }}</span></p>
    <p class="text-[11px] font-bold uppercase tracking-widest text-slate-500 mt-1">{{ __('pwa.marque') }}</p>
  </div>
</div>
<hr class="border-slate-200 my-5">

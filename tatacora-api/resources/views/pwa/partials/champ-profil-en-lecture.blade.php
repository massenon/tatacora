{{-- La phrase d'un champ de « Mon profil » dont le droit n'est pas accordé au
     rôle (03/11/2026) : elle dit la vérité — le droit existe à l'écran
     Rôles & Permissions, et c'est l'administrateur qui l'accorde. --}}
<p class="champ-en-lecture text-[12px] text-slate-400 mt-1">{{ __('pwa.profil.champ_non_modifiable_avant') }}<a href="{{ route('pwa.roles-permissions') }}" wire:navigate class="underline">{{ __('pwa.profil.champ_non_modifiable_lien') }}</a>{{ __('pwa.profil.champ_non_modifiable_apres') }}</p>

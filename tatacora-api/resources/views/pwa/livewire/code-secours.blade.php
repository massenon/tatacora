{{--
    « J'AI PERDU MON MOT DE PASSE ADMINISTRATEUR » — AJOUT du Product Owner du
    29/10/2026 (option A). Nom d'utilisateur + code de secours + nouveau mot de
    passe ; atteint depuis le message « Contactez l'administrateur » de l'écran de
    connexion. Mise en page « invité » de la connexion (mêmes jetons, mêmes
    pictogrammes). Le poste Windows a le même écran (`ecran_code_secours.dart`).

    Après un succès, le NOUVEAU code de secours est affiché UNE seule fois
    (copier, imprimer, ranger au coffre) ; l'ancien est consommé.
--}}
<div class="contents">
  <div class="flex-1 flex items-center justify-center p-4 md:p-6 overflow-y-auto">
    <div class="w-full max-w-[560px] my-auto bg-white border border-slate-200 rounded-2xl shadow-sm p-6 md:p-8">

      @include('pwa.partials.carte-invite-entete')

      @if ($nouveauCode !== null)
        <h1 class="text-[28px] font-extrabold leading-tight" style="color:var(--navy)">{{ __('pwa.code_secours.nouveau_code_titre') }}</h1>
        <p class="text-[15px] text-slate-500 mt-1 mb-4" role="status">{{ __('pwa.code_secours.mdp_reinitialise') }}</p>
        <x-pwa.secret-unique :secret="$nouveauCode" id="nouveau-code-secours" :imprimable="true"
                             :titre="__('pwa.code_secours.impression_titre')"
                             :consigne="__('pwa.code_secours.consigne_coffre')" />
        <a href="{{ route('pwa.connexion') }}" wire:navigate
           class="btn mt-6 w-full h-[52px] rounded-xl text-white text-base font-bold tracking-wider inline-flex items-center justify-center" style="background:var(--navy)">{{ __('pwa.code_secours.retour_connexion') }}</a>
      @else
        <h1 class="text-[28px] font-extrabold leading-tight" style="color:var(--navy)">{{ __('pwa.code_secours.titre') }}</h1>
        <p class="text-[15px] text-slate-500 mt-1 mb-6">{{ __('pwa.code_secours.accroche') }}</p>

        <form id="formulaire-code-secours" class="space-y-4" method="post" action="{{ route('pwa.code-secours') }}" onsubmit="return false" wire:submit="reinitialiserParCodeDeSecours">
          @include('pwa.partials.champ-invite', ['id' => 'champ-login', 'etiquette' => __('pwa.code_secours.login'), 'modele' => 'login', 'icone' => 'utilisateur', 'autocomplete' => 'username'])
          @include('pwa.partials.champ-invite', ['id' => 'champ-code', 'etiquette' => __('pwa.code_secours.code'), 'modele' => 'code', 'icone' => 'cadenas', 'secret' => true])
          @include('pwa.partials.champ-invite', ['id' => 'champ-nouveau', 'etiquette' => __('pwa.changement_mdp.nouveau'), 'modele' => 'nouveauMotDePasse', 'icone' => 'cadenas', 'secret' => true, 'autocomplete' => 'new-password'])
          @include('pwa.partials.champ-invite', ['id' => 'champ-confirmation', 'etiquette' => __('pwa.changement_mdp.confirmation'), 'modele' => 'confirmationMotDePasse', 'icone' => 'cadenas', 'secret' => true, 'autocomplete' => 'new-password'])
          <p class="text-[13px] text-slate-500">{{ __('pwa.code_secours.regle') }}</p>

          @error('identifiants')
            <p id="erreur-identifiants" role="alert" class="text-[15px] text-red-600 bg-red-50 border border-red-100 rounded-lg px-3 py-2">⚠ {{ $message }}</p>
          @enderror

          <button type="submit" wire:loading.attr="disabled" wire:target="reinitialiserParCodeDeSecours"
                  class="btn w-full h-[52px] rounded-xl text-white text-base font-bold tracking-wider inline-flex items-center justify-center gap-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--navy)]" style="background:var(--navy)">
            <span class="inline-flex items-center gap-2" wire:loading.remove wire:target="reinitialiserParCodeDeSecours">@include('pwa.partials.pictogramme-connexion', ['nom' => 'cadenas_ouvert', 'taille' => 20]){{ __('pwa.code_secours.bouton') }}</span>
            <span class="hidden items-center gap-2" wire:loading.class.remove="hidden" wire:loading.class="inline-flex" wire:target="reinitialiserParCodeDeSecours" role="status">{{ __('pwa.code_secours.en_cours') }}</span>
          </button>
        </form>

        <p class="text-center mt-4">
          <a href="{{ route('pwa.connexion') }}" wire:navigate class="text-[15px] font-semibold underline-offset-2 hover:underline" style="color:var(--navy)">{{ __('pwa.code_secours.retour_connexion') }}</a>
        </p>
      @endif

      <p class="text-center text-[13px] text-slate-500 mt-8">{{ __('pwa.pied_de_page') }}</p>
    </div>
  </div>
</div>

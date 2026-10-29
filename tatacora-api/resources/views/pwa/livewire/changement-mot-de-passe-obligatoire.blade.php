{{--
    « DÉFINISSEZ VOTRE NOUVEAU MOT DE PASSE » — AJOUT du Product Owner du
    29/10/2026 (option A du « mot de passe perdu »). Seul écran qu'atteint un compte
    dont le mot de passe a été réinitialisé par un administrateur
    (`ExigerChangementMotDePasse`). Mise en page « invité » de la connexion : carte
    unique, mêmes jetons (`--navy`, `--gold`, `--erreur`) et mêmes pictogrammes.
    Le poste Windows a le même écran (`ecran_changement_mot_de_passe.dart`).
--}}
<div class="contents">
  <div class="flex-1 flex items-center justify-center p-4 md:p-6 overflow-y-auto">
    <div class="w-full max-w-[560px] my-auto bg-white border border-slate-200 rounded-2xl shadow-sm p-6 md:p-8">

      @include('pwa.partials.carte-invite-entete')

      <h1 class="text-[28px] font-extrabold leading-tight" style="color:var(--navy)">{{ __('pwa.changement_mdp.titre_h1') }}</h1>
      <p class="text-[15px] text-slate-500 mt-1 mb-6">{{ __('pwa.changement_mdp.accroche') }}</p>

      <form id="formulaire-changement" class="space-y-4" method="post" action="{{ route('pwa.changement-mot-de-passe') }}" onsubmit="return false" wire:submit="definirNouveauMotDePasse">
        @include('pwa.partials.champ-invite', ['id' => 'champ-nouveau', 'etiquette' => __('pwa.changement_mdp.nouveau'), 'modele' => 'nouveauMotDePasse', 'icone' => 'cadenas', 'secret' => true, 'autocomplete' => 'new-password'])
        @include('pwa.partials.champ-invite', ['id' => 'champ-confirmation', 'etiquette' => __('pwa.changement_mdp.confirmation'), 'modele' => 'confirmationMotDePasse', 'icone' => 'cadenas', 'secret' => true, 'autocomplete' => 'new-password'])
        <p class="text-[13px] text-slate-500">{{ __('pwa.changement_mdp.regle') }}</p>

        <button type="submit" wire:loading.attr="disabled" wire:target="definirNouveauMotDePasse"
                class="btn w-full h-[52px] rounded-xl text-white text-base font-bold tracking-wider inline-flex items-center justify-center gap-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--navy)]" style="background:var(--navy)">
          <span class="inline-flex items-center gap-2" wire:loading.remove wire:target="definirNouveauMotDePasse">@include('pwa.partials.pictogramme-connexion', ['nom' => 'cadenas_ouvert', 'taille' => 20]){{ __('pwa.changement_mdp.bouton') }}</span>
          <span class="hidden items-center gap-2" wire:loading.class.remove="hidden" wire:loading.class="inline-flex" wire:target="definirNouveauMotDePasse" role="status">{{ __('pwa.changement_mdp.en_cours') }}</span>
        </button>
      </form>

      <form method="post" action="{{ route('logout') }}" class="mt-4 text-center">
        @csrf
        <button type="submit" class="text-[15px] font-semibold underline-offset-2 hover:underline" style="color:var(--navy)">{{ __('pwa.changement_mdp.se_deconnecter') }}</button>
      </form>

      <p class="text-center text-[13px] text-slate-500 mt-8">{{ __('pwa.pied_de_page') }}</p>
    </div>
  </div>
</div>

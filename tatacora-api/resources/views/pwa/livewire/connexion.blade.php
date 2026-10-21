{{--
    ÉCRAN DE CONNEXION (M0 — accès).

    Maître : `prototype_v2/pages/login.html` — deux colonnes, panneau image à
    gauche (`hidden lg:block lg:w-1/2`), formulaire à droite (`flex-1`).
    Copywriting du maître au mot près, RG d'authentification inchangées.

    Declarations pour la garde des trois sources :
      maitre-refuse:login.html#comptes-demo
        La grille de ONZE comptes de démonstration cliquables (`login.html`
        l.47-54, connexion instantanée sans mot de passe) n'est PAS rendue —
        `SECURITY_STRICT.md` §12 : un raccourci d'authentification visible à
        l'écran de connexion est une vulnérabilité critique, interdite dans
        TOUT environnement, y compris `demo`. Le texte qui l'annonce
        (« Un compte par profil métier […] cliquez pour vous connecter
        instantanément […] ») est omis avec elle plutôt que conservé à moitié
        vrai : sans les tuiles, il inviterait à cliquer sur rien. Raison
        datée 01/09/2026, à revérifier si §12 est un jour levé.
--}}
<div class="contents">

  <div class="hidden lg:block lg:w-1/2 relative">
    <img src="{{ asset('assets/img/gite-cover.jpg') }}" alt="{{ __('pwa.connexion.alt_couverture') }}" class="absolute inset-0 w-full h-full object-cover">
    <div class="absolute inset-0" style="background:linear-gradient(180deg, rgba(20,33,61,.2), rgba(20,33,61,.85))"></div>
    <div class="relative z-10 h-full flex flex-col justify-end p-12 text-white">
      {{-- Logo PNG paysage (decision du PO du 14/10/2026, D392) : cadre garde,
           `object-contain` au lieu d'`object-cover` (qui rognait). PA-210. --}}
      <img src="{{ asset('assets/img/logo.png') }}" alt="{{ __('pwa.alt_logo') }}" class="w-16 h-16 rounded-xl mb-6 ring-2 ring-[var(--gold)] object-contain">
      <h1 class="text-3xl font-bold mb-2 leading-tight">{!! __('pwa.connexion.titre_panneau') !!}</h1>
      <p class="text-white/70 text-sm max-w-md">{{ __('pwa.connexion.accroche_panneau') }}</p>
    </div>
  </div>

  <div class="flex-1 flex items-center justify-center p-6 overflow-y-auto">
    <div class="w-full max-w-sm py-8">
      <div class="text-center mb-6 lg:hidden">
        <img src="{{ asset('assets/img/logo.png') }}" alt="{{ __('pwa.alt_logo') }}" class="w-14 h-14 rounded-xl mx-auto mb-3 ring-2 ring-[var(--gold)] object-contain">
      </div>
      <h2 class="text-xl font-bold text-center mb-1" style="color:var(--navy)">{{ __('pwa.marque') }}</h2>
      <p class="text-[15px] text-slate-400 text-center mb-6">{{ __('pwa.connexion.sous_titre') }}</p>

      {{-- ⚠ `method="post"` + `onsubmit="return false"` : sans eux, un navigateur dont
           Livewire n'a pas démarré (script bloqué, 404 sur son adresse, cache périmé)
           ENVOIE LE FORMULAIRE EN GET et l'identifiant comme le mot de passe finissent
           dans l'adresse, l'historique et les journaux du serveur (constaté en local le
           21/10/2026). Le repli est désormais inerte : rien ne part, le mot de passe ne
           quitte jamais le champ. Livewire, lui, écoute toujours `submit`. --}}
      <form id="formulaire-connexion" class="space-y-4" method="post" action="{{ route('pwa.connexion') }}" onsubmit="return false" wire:submit="seConnecter">
        <div class="groupe-champ">
          <label for="champ-identifiant" class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.connexion.login') }} <span class="text-red-500">*</span></label>
          <input id="champ-identifiant" name="identifiant" type="text" wire:model="login" autocomplete="username" autofocus class="champ w-full border border-slate-200 rounded-lg px-3.5 py-3 text-sm @error('login') champ-erreur @enderror" placeholder="{{ __('pwa.connexion.exemple_login') }}">
          <p class="message-erreur">@error('login'){{ $message }}@enderror</p>
        </div>
        <div class="groupe-champ">
          <label for="champ-motdepasse" class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.connexion.mot_de_passe') }} <span class="text-red-500">*</span></label>
          {{-- Œil de visibilité — ajouté le 01/09/2026, sans équivalent au
               maître (une maquette statique n'a pas de saisie réelle à
               vérifier). Purement client (Alpine) : ne touche ni au binding
               `wire:model`, ni à la valeur, seulement à l'attribut `type`. --}}
          <div class="relative" x-data="{ visible: false }">
            <input id="champ-motdepasse" name="motdepasse" type="password" :type="visible ? 'text' : 'password'" wire:model="motDePasse" autocomplete="current-password" class="champ w-full border border-slate-200 rounded-lg px-3.5 py-3 pr-11 text-sm @error('motDePasse') champ-erreur @enderror" placeholder="••••••••">
            <button type="button" @click="visible = !visible" :aria-label="visible ? '{{ __('pwa.connexion.masquer_mot_de_passe') }}' : '{{ __('pwa.connexion.afficher_mot_de_passe') }}'"
                    class="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600">
              <svg x-show="!visible" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
              <svg x-show="visible" x-cloak width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17.94 17.94A10.94 10.94 0 0112 20c-7 0-11-8-11-8a21.62 21.62 0 015.06-6.94M9.9 4.24A10.94 10.94 0 0112 4c7 0 11 8 11 8a21.6 21.6 0 01-2.66 3.94M14.12 14.12a3 3 0 11-4.24-4.24"/><path d="M1 1l22 22"/></svg>
            </button>
          </div>
          <p class="message-erreur">@error('motDePasse'){{ $message }}@enderror</p>
        </div>
        {{--
            Bandeau d'échec d'authentification — même emplacement et mêmes
            classes que `#erreur-identifiants` du prototype, qui y est masqué
            par `hidden` puis révélé en JavaScript. Ici le serveur décide :
            l'élément n'existe que lorsqu'il y a réellement un refus.

            Le message reste indifférencié (`auth.failed`) : distinguer
            « login inconnu » de « mot de passe incorrect » permettrait
            d'énumérer les comptes.
        --}}
        @error('identifiants')
          <p id="erreur-identifiants" class="text-[15px] text-red-600 bg-red-50 border border-red-100 rounded-lg px-3 py-2">⚠ {{ $message }}</p>
        @enderror
        <button type="submit" class="btn w-full py-3 rounded-lg text-white text-sm font-semibold" style="background:var(--navy)">{{ __('pwa.connexion.valider') }}</button>
      </form>
      
      {{-- Bloc « Comptes de démonstration (RBAC) » du maître (divider, texte
           d'annonce, grille de 11 tuiles) : voir le refus déclaré en tête de
           ce fichier (maitre-refuse:login.html#comptes-demo). --}}

      <p class="text-center text-[13px] text-slate-400 mt-8">{{ __('pwa.pied_de_page') }}</p>
    </div>
  </div>

</div>

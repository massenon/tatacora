{{--
    ÉCRAN DE CONNEXION (M0 — accès).

    REFONTE DU 29/10/2026 (demande du PO, docs/HANDOFF_ECRAN_CONNEXION_LOGIRESTOCK.md) :
    une carte unique, centrée, une colonne — marque, slogan, bandeau de sept
    pictogrammes, accueil, deux champs, « Se souvenir de moi » / « Mot de passe
    oublié ? », bouton. Le panneau image à deux colonnes de l'ancienne maquette
    (`login.html`) n'existe plus. La vue Blade reste le maître du poste Windows,
    qui la traduit à l'identique (`ecran_connexion.dart`).

    Couleurs : uniquement les jetons de la feuille de style (`--navy` en
    couleur primaire, `--gold` en accent, `--erreur`, échelle `slate`). Aucun
    hexadécimal ici.

    Déclarations pour la garde des trois sources :
      maitre-refuse:login.html#comptes-demo
        La grille de ONZE comptes de démonstration cliquables (`login.html`
        l.47-54, connexion instantanée sans mot de passe) n'est PAS rendue —
        `SECURITY_STRICT.md` §12 : un raccourci d'authentification visible à
        l'écran de connexion est une vulnérabilité critique, interdite dans
        TOUT environnement, y compris `demo`. Le texte qui l'annonce est omis
        avec elle. Raison datée 01/09/2026, à revérifier si §12 est un jour
        levé.

    « Se souvenir de moi » : il mémorise l'IDENTIFIANT seul, dans le navigateur
    (`localStorage`, côté client, Alpine) — jamais le mot de passe, et ce n'est
    PAS le « remember me » de Laravel (aucun cookie de longue durée, aucune
    logique d'authentification touchée). Décoché, la valeur mémorisée est
    effacée.

    « Mot de passe oublié ? » : aucune route de réinitialisation n'existe. Le
    lien n'ouvre donc rien ; il révèle, sur place, la phrase « Contactez
    l'administrateur » (la même qu'au poste, qui est hors ligne). Depuis le
    29/10/2026 (option A du PO) il propose aussi, en dessous, « J'ai perdu mon mot
    de passe administrateur » : le recours par code de secours du dernier
    administrateur.
--}}
<div class="contents">

  {{-- PANNEAU GAUCHE — décision du PO du 29/10/2026 : deux panneaux dès `lg`
       (1024 px), comme l'ancienne mise en page. Photo du gîte en `object-cover`,
       voile dégradé dérivé de `--navy` (le dégradé historique
       `rgba(20,33,61,.2)` → `.85` EST le navy du dépôt), puis le logo TÉLÉVERSÉ
       (carré 64, rayon `xl`, anneau doré de 2 px, `object-contain` : le logo est
       paysage, jamais rogné), le titre et l'accroche, collés EN BAS. Sous `lg`
       ce panneau disparaît et le logo remonte dans la carte. --}}
  <div class="hidden lg:block lg:w-1/2 relative">
    <img src="{{ asset('assets/img/gite-cover.jpg') }}" alt="{{ __('pwa.connexion.alt_couverture') }}" class="absolute inset-0 w-full h-full object-cover">
    <div class="absolute inset-0" style="background:linear-gradient(180deg, color-mix(in srgb, var(--navy) 20%, transparent), color-mix(in srgb, var(--navy) 85%, transparent))"></div>
    <div class="relative z-10 h-full flex flex-col justify-end p-12 text-white">
      <img src="{{ app(\App\Shared\Parametres\Services\ApparenceEtablissementService::class)->urlLogo() }}" alt="{{ __('pwa.alt_logo') }}" class="w-16 h-16 rounded-xl mb-6 ring-2 ring-[var(--gold)] object-contain">
      {{-- `<h2>` et non `<h1>` : le `<h1>` de la page est « Connexion »
           (masqué), dont l'onglet reprend le nom (BaliseTitrePwaTest). --}}
      <h2 class="text-3xl font-bold mb-2 leading-tight">{!! __('pwa.connexion.titre_panneau') !!}</h2>
      <p class="text-white/70 text-sm max-w-md">{{ __('pwa.connexion.accroche_panneau') }}</p>
    </div>
  </div>

  {{-- PANNEAU DROIT — correction du PO du 29/10/2026 : fond BLANC uni, plus de
       « carte » (ni fond distinct, ni bordure, ni ombre, ni rayon), plus de
       marge verticale : le contenu est centré dans la hauteur de la fenêtre
       (`min-h-screen flex items-center`), seul un retrait HORIZONTAL reste. --}}
  <div class="flex-1 min-h-screen flex items-center justify-center bg-white px-6 md:px-8">
    <div class="w-full max-w-[520px]">

      <h1 class="sr-only">{{ __('pwa.connexion.titre_h1') }}</h1>

      {{-- 1. Marque. Décision du PO du 29/10/2026 : le logo TÉLÉVERSÉ de
           l'établissement (Paramètres → Logo & Apparence) coiffe la carte
           quand il existe, AU-DESSUS de la marque (qui reste toujours affichée) ; dès
           `lg` il est dans le panneau gauche et n'est PAS répété ici.
           Proportions gardées (`object-contain`, jamais rogné ni étiré). --}}
      @php($logoTeleverse = app(\App\Shared\Parametres\Services\ApparenceEtablissementService::class)->fichierDe('logo') !== null)
      @if ($logoTeleverse)
        <img src="{{ app(\App\Shared\Parametres\Services\ApparenceEtablissementService::class)->urlLogo() }}" alt="{{ __('pwa.alt_logo') }}" class="block mx-auto h-16 w-auto max-w-full object-contain mb-4 lg:hidden">
      @endif
      {{-- Pictogramme + « LogiReStock » + « TATACORA AFRIQUE » (décision du PO
           du 29/10/2026) : éléments de marque, TOUJOURS affichés, le logo
           s'ajoutant au-dessus. Le sous-titre prend EXACTEMENT la largeur de
           « LogiReStock » : un script léger mesure les deux à l'affichage et en
           déduit l'interlettrage (jamais `text-align-last: justify`, qui écarte
           les mots). `wire:ignore` : Livewire ne défait pas le style posé. --}}
      <div class="flex items-center justify-center gap-3">
        <span class="shrink min-w-[48px] w-[68px]">@include('pwa.partials.pictogramme-marque')</span>
        <div class="shrink-0" wire:ignore
             x-data="{
               ajuster() {
                 const nom = this.$refs.nom, sous = this.$refs.sous;
                 sous.style.letterSpacing = '0px'; sous.style.marginRight = '0px'; sous.style.fontSize = '';
                 const cible = nom.getBoundingClientRect().width;
                 const brut = sous.getBoundingClientRect().width;
                 const lettres = sous.textContent.trim().length;
                 if (!cible || !brut) return;
                 if (brut > cible) { sous.style.fontSize = (parseFloat(getComputedStyle(sous).fontSize) * cible / brut) + 'px'; return; }
                 const ecart = (cible - brut) / (lettres - 1);
                 sous.style.letterSpacing = ecart + 'px';
                 sous.style.marginRight = (-ecart) + 'px';
               }
             }"
             x-init="ajuster(); if (document.fonts) document.fonts.ready.then(() => ajuster())">
          <p class="text-[28px] font-extrabold leading-none whitespace-nowrap"><span x-ref="nom" class="inline-block"><span style="color:var(--navy)">{{ __('pwa.connexion.marque_logi') }}</span><span style="color:var(--gold)">{{ __('pwa.connexion.marque_restock') }}</span></span></p>
          <p class="text-[15px] font-bold uppercase tracking-widest text-slate-500 mt-1 leading-none whitespace-nowrap"><span x-ref="sous" class="inline-block">{{ __('pwa.marque') }}</span></p>
        </div>
      </div>

      {{-- 2-4. Filet, slogan, filet, bandeau de sept modules, filet. --}}
      <hr class="border-slate-200 mt-3">
      <p class="text-[12px] font-semibold tracking-[0.2em] text-slate-500 text-center py-2">{{ __('pwa.connexion.slogan') }}</p>
      <hr class="border-slate-200">
      <ul class="flex items-center justify-between gap-1 py-2.5 text-slate-500" aria-label="{{ __('pwa.connexion.bandeau_modules') }}">
        @foreach (['restauration', 'hebergement', 'eco_tourisme', 'stock', 'location', 'caisse', 'comptabilite'] as $module)
          <li title="{{ __('pwa.connexion.modules.'.$module) }}" class="flex-1 flex justify-center">
            <span class="sr-only">{{ __('pwa.connexion.modules.'.$module) }}</span>
            @include('pwa.partials.pictogramme-connexion', ['nom' => $module, 'taille' => 26])
          </li>
        @endforeach
      </ul>
      <hr class="border-slate-200 mb-4">

      {{-- 5. Accueil. --}}
      <h2 class="text-[28px] font-extrabold leading-tight" style="color:var(--navy)">{{ __('pwa.connexion.bienvenue') }}</h2>
      <p class="text-[15px] text-slate-500 mt-1 mb-4">{{ __('pwa.connexion.accroche') }}</p>

      {{-- Un changement de mot de passe vient d'aboutir (ou un temporaire a expiré) :
           l'information est dite UNE fois, au retour sur la connexion. --}}
      @if (session('pwa-connexion-info'))
        <p id="information-connexion" role="status" class="mb-4 text-[15px] text-slate-700 bg-slate-50 border border-slate-200 rounded-lg px-3 py-2">{{ session('pwa-connexion-info') }}</p>
      @endif

      {{-- ⚠ `method="post"` + `onsubmit="return false"` : sans eux, un navigateur dont
           Livewire n'a pas démarré (script bloqué, 404 sur son adresse, cache périmé)
           ENVOIE LE FORMULAIRE EN GET et l'identifiant comme le mot de passe finissent
           dans l'adresse, l'historique et les journaux du serveur (constaté en local le
           21/10/2026). Le repli est désormais inerte : rien ne part, le mot de passe ne
           quitte jamais le champ. Livewire, lui, écoute toujours `submit`. --}}
      <form id="formulaire-connexion" class="space-y-3" method="post" action="{{ route('pwa.connexion') }}" onsubmit="return false" wire:submit="seConnecter"
            x-data="{
              souvenir: false,
              aide: false,
              cle: 'pwa-connexion-identifiant',
              init() {
                try {
                  const v = localStorage.getItem(this.cle);
                  if (v) {
                    this.souvenir = true;
                    const champ = this.$refs.identifiant;
                    champ.value = v;
                    champ.dispatchEvent(new Event('input', { bubbles: true }));
                  }
                } catch (e) { /* sans stockage : rien n'est mémorisé */ }
              },
              memoriser() {
                try {
                  if (this.souvenir && this.$refs.identifiant.value) localStorage.setItem(this.cle, this.$refs.identifiant.value);
                  else localStorage.removeItem(this.cle);
                } catch (e) { /* idem */ }
              }
            }"
            @submit="memoriser()">

        {{-- 6. Identifiant. --}}
        <div class="groupe-champ">
          <label for="champ-identifiant" class="block text-[12px] font-bold tracking-wider text-slate-800 mb-1.5">{{ __('pwa.connexion.login') }}</label>
          <div class="relative">
            <span class="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-500 pointer-events-none">@include('pwa.partials.pictogramme-connexion', ['nom' => 'utilisateur', 'taille' => 20])</span>
            <input id="champ-identifiant" x-ref="identifiant" name="identifiant" type="text" wire:model="login" autocomplete="username" autofocus aria-required="true"
                   @error('login') aria-invalid="true" aria-describedby="erreur-login" @enderror
                   class="champ w-full h-[52px] border border-slate-300 hover:border-slate-400 rounded-xl pl-11 pr-3.5 text-base truncate @error('login') champ-erreur @enderror">
          </div>
          <p id="erreur-login" class="message-erreur" @error('login') role="alert" @enderror>@error('login'){{ $message }}@enderror</p>
        </div>

        {{-- 7. Mot de passe + œil (Alpine, purement client : ne touche ni au
             binding `wire:model` ni à la valeur, seulement à l'attribut `type`). --}}
        <div class="groupe-champ">
          <label for="champ-motdepasse" class="block text-[12px] font-bold tracking-wider text-slate-800 mb-1.5">{{ __('pwa.connexion.mot_de_passe') }}</label>
          <div class="relative" x-data="{ visible: false }">
            <span class="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-500 pointer-events-none">@include('pwa.partials.pictogramme-connexion', ['nom' => 'cadenas', 'taille' => 20])</span>
            <input id="champ-motdepasse" name="motdepasse" type="password" :type="visible ? 'text' : 'password'" wire:model="motDePasse" autocomplete="current-password" aria-required="true"
                   @error('motDePasse') aria-invalid="true" aria-describedby="erreur-motdepasse" @enderror
                   class="champ w-full h-[52px] border border-slate-300 hover:border-slate-400 rounded-xl pl-11 pr-12 text-base @error('motDePasse') champ-erreur @enderror">
            <button type="button" @click="visible = !visible" :aria-pressed="visible ? 'true' : 'false'" :aria-label="visible ? '{{ __('pwa.connexion.masquer_mot_de_passe') }}' : '{{ __('pwa.connexion.afficher_mot_de_passe') }}'" aria-label="{{ __('pwa.connexion.afficher_mot_de_passe') }}" aria-pressed="false"
                    class="absolute right-1.5 top-1/2 -translate-y-1/2 w-10 h-10 flex items-center justify-center rounded-lg text-slate-500 hover:text-slate-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--navy)]">
              <span x-show="!visible">@include('pwa.partials.pictogramme-connexion', ['nom' => 'oeil', 'taille' => 20])</span>
              <span x-show="visible" x-cloak>@include('pwa.partials.pictogramme-connexion', ['nom' => 'oeil_barre', 'taille' => 20])</span>
            </button>
          </div>
          <p id="erreur-motdepasse" class="message-erreur" @error('motDePasse') role="alert" @enderror>@error('motDePasse'){{ $message }}@enderror</p>
        </div>

        {{-- 8. « Se souvenir de moi » · « Mot de passe oublié ? ». --}}
        <div class="flex items-center justify-between gap-3 flex-wrap">
          <label class="inline-flex items-center gap-2 text-[15px] text-slate-700 cursor-pointer">
            <input type="checkbox" x-model="souvenir" class="w-4 h-4 rounded border-slate-300" style="accent-color:var(--navy)">
            {{ __('pwa.connexion.se_souvenir') }}
          </label>
          <button type="button" @click="aide = !aide" :aria-expanded="aide ? 'true' : 'false'" aria-expanded="false" aria-controls="aide-mot-de-passe-oublie"
                  class="text-[15px] font-semibold underline-offset-2 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--navy)] rounded" style="color:var(--navy)">{{ __('pwa.connexion.mot_de_passe_oublie') }}</button>
        </div>
        <div id="aide-mot-de-passe-oublie" x-show="aide" x-cloak role="status" class="text-[15px] text-slate-700 bg-slate-50 border border-slate-200 rounded-lg px-3 py-2">
          <p>{{ __('pwa.connexion.mot_de_passe_oublie_aide') }}</p>
          {{-- 29/10/2026 (PO, option A) : le recours du DERNIER administrateur.
               Un compte ordinaire s'adresse à un administrateur, qui lui génère
               un mot de passe temporaire (Comptes utilisateurs). --}}
          <p class="mt-1"><a id="lien-mot-de-passe-administrateur-perdu" href="{{ route('pwa.code-secours') }}" wire:navigate class="font-semibold underline underline-offset-2" style="color:var(--navy)">{{ __('pwa.connexion.mot_de_passe_administrateur_perdu') }}</a></p>
        </div>

        {{--
            Bandeau d'échec d'authentification — l'élément n'existe que lorsqu'il
            y a réellement un refus (le serveur décide). Le message reste
            indifférencié (`auth.failed`) : distinguer « login inconnu » de
            « mot de passe incorrect » permettrait d'énumérer les comptes.
        --}}
        @error('identifiants')
          <p id="erreur-identifiants" role="alert" class="text-[15px] text-red-600 bg-red-50 border border-red-100 rounded-lg px-3 py-2">⚠ {{ $message }}</p>
        @enderror

        {{-- 9. Bouton plein. --}}
        <button type="submit" wire:loading.attr="disabled" wire:target="seConnecter"
                class="btn w-full h-[52px] rounded-xl text-white text-base font-bold tracking-wider inline-flex items-center justify-center gap-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--navy)]" style="background:var(--navy)">
          <span class="inline-flex items-center gap-2" wire:loading.remove wire:target="seConnecter">@include('pwa.partials.pictogramme-connexion', ['nom' => 'cadenas_ouvert', 'taille' => 20]){{ __('pwa.connexion.valider') }}</span>
          <span class="hidden items-center gap-2" wire:loading.class.remove="hidden" wire:loading.class="inline-flex" wire:target="seConnecter" role="status">{{ __('pwa.connexion.connexion_en_cours') }}</span>
        </button>
      </form>

      {{-- Bloc « Comptes de démonstration (RBAC) » du maître : voir le refus
           déclaré en tête de ce fichier (maitre-refuse:login.html#comptes-demo). --}}

      <p class="text-center text-[13px] text-slate-500 mt-4">{{ __('pwa.pied_de_page') }}</p>
    </div>
  </div>

</div>

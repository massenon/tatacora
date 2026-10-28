{{--
    BARRE SUPÉRIEURE — transcription de `prototype_v2/assets/js/shell.js`
    (`construireTopBar()`, le bloc `<header>`), Article 3.2 de
    `docs/DIRECTIVE_CONFORMITE_100.md`.

    ## Ce que cette réécriture répare (31/08/2026)

    La version précédente était une RÉINTERPRÉTATION Alpine du maître, et non
    une traduction : `x-data`/`x-show` à la place des identifiants du maître,
    un `<form method="POST">` à la place du bouton de déconnexion, et surtout
    DEUX widgets entiers absents — le panneau de notifications
    (`#menu-notifications`, ses deux filtres, sa liste) et le panneau du menu
    de compte (`#menu-profil`).

    ⚠ Le défaut n'était pas seulement cosmétique : `layouts/pwa.blade.php`
    porte depuis le 27/08/2026 la délégation d'événements transcrite
    d'`initialiserShell()` — elle écoute `#bouton-menu-profil`,
    `#bouton-cloche-notifications`, `#menu-notifications`, `#menu-profil` et
    `.filtre-notif`. Aucun de ces nœuds n'était rendu : **le JavaScript
    attendait un DOM que personne ne construisait**, et rien ne le signalait,
    parce qu'un écouteur posé sur `document` ne se plaint jamais de ne rien
    trouver. Le bouton de menu mobile souffrait du même mal en sens inverse :
    il émettait `$dispatch('toggle-sidebar')`, qu'AUCUN `x-data` n'écoutait —
    le menu escamotable ne s'ouvrait pas sur téléphone.

    Les identifiants du maître sont donc rétablis, et l'Alpine retiré : la
    coquille a UN seul mécanisme d'ouverture, celui du maître.

    ## Deux libellés du maître ne sont pas rendus, et ils sont nommés

    - « Réseau Synchronisé » → « Réseau » (`pwa.coquille.reseau`, où l'écart
      est motivé) : la PWA n'a AUCUNE file de synchronisation, et un badge qui
      affirme un état que rien ne vérifie est le défaut PA-59/60/61.
    - ⚠ Le paragraphe qui refusait `#badge-notifications-non-lues` et
      `#indicateur-caisse` est LEVÉ (02/09/2026, PA-144 — sa raison avait
      cessé d'être vraie deux fois) : le badge est rendu par la cloche
      d'alertes dérivées (`ClocheNotifications`, 01/09/2026), et l'indicateur
      de caisse par le bouton « Clôturer la caisse », qui lit une vraie
      `SessionCaisse` (le modèle existe depuis PA-162).
    - Libellés décidés par le PO le 02/09/2026, écarts au maître DÉCLARÉS :
      « Vente » (le maître écrit « Point de vente ») et « Clôturer la
      caisse » sans le nom du point (gardé en infobulle).

    ⚠ « Point de vente » N'EST PLUS un widget refusé (31/08/2026). Son refus
    invoquait `LARAVEL_PWA.md` §2 — « écran d'encaissement, hors périmètre de
    la consultation ». PA-159 a levé ce §2 le 28/08/2026 : la PWA écrit, et
    les deux écrans de point de vente sont SERVIS (`pwa.pos.comptant`,
    `pwa.pos.heberges`). Une raison de refus qui a cessé d'être vraie
    transforme une décision en oubli (PA-144) : le raccourci du maître est
    rendu, sous la même garde RBAC que les autres.

    ## Le bandeau de la coquille est émis ICI

    `#shell-banniere` est le deuxième des quatre blocs du `<body>` du maître
    (`prototype_v2/pages/tableau-de-bord.html`), entre la barre supérieure et
    la ligne qui porte le menu latéral. Il est inclus depuis ce partial plutôt
    que depuis chacune des quarante vues de page : une ligne à ajouter dans
    quarante fichiers est une ligne qu'on oublie dans le quarante-et-unième,
    et le bandeau manquerait sur la page suivante sans que personne ne le
    voie. L'ordre du maître est conservé — topbar, bannière, sidebar.
--}}
@php
    $utilisateur = Auth::user();

    // ⚠ RBAC DE NIVEAU 1 — LE MASQUAGE D'INTERFACE (31/08/2026).
    //
    // Ces entrées étaient des `<a href>` écrits en dur : un `guide`
    // (`PARAM = '-'`, `M14 = '-'`) obtenait « Paramètres du compte »,
    // « Import & Export » et « Journal d'Audit », cliquait, et tombait sur un
    // 403. `MenuLateral::liensChassis()` porte le filtre ; il restait à le
    // RENDRE, sans quoi la moitié serveur du correctif ne se voyait nulle
    // part.
    //
    // Un lien refusé garde sa LIGNE dans le menu de compte, avec `url = null`
    // et une raison : ce menu est court et stable, en retirer des lignes selon
    // le rôle rendrait sa lecture instable d'un poste à l'autre. Ce n'est pas
    // une entrée inerte au sens de l'Article 3.3 — elle DIT pourquoi elle ne
    // mène nulle part.
    //
    // Les RACCOURCIS de la barre, eux, sont MASQUÉS quand le droit manque :
    // c'est la règle de `shell.js` pour la navigation (« un module à '-' n'est
    // pas grisé, il est ABSENT »), et celle que `MenuLateral::pour()` applique
    // déjà à la barre latérale.
    $liensChassis = \App\Pwa\Support\MenuLateral::liensChassis($utilisateur);

    // Les icônes du menu de compte, dans l'ordre du maître (shell.js
    // l.162-181). Le libellé reste celui que le client a validé : ce bloc
    // déplace la GARDE, jamais le texte.
    $entreesDeCompte = [
        ['cle' => 'mon_profil', 'libelle' => __('pwa.coquille.mon_profil'), 'icone' => '<path stroke-linecap="round" stroke-linejoin="round" d="M20 21v-2a4 4 0 00-4-4H8a4 4 0 00-4 4v2"/><circle cx="12" cy="7" r="4"/>'],
        ['cle' => 'parametres_compte', 'libelle' => __('pwa.coquille.parametres_compte'), 'icone' => '<circle cx="12" cy="12" r="3"/>'],
        ['cle' => 'import_export', 'libelle' => __('pwa.coquille.import_export'), 'icone' => '<path stroke-linecap="round" stroke-linejoin="round" d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/>'],
        // « Journal d'Audit » vit ICI depuis le 02/09/2026 (directive PO) :
        // le maitre le pose en raccourci de barre (shell.js l.124-127), le PO
        // l'a deplace dans le menu de compte pour alleger la barre. Meme
        // icone, meme garde RBAC (`liensChassis()['journal_audit']`, M14).
        // L'ecart au maitre est DECIDE et declare aux gardes de conformite
        // (registre des widgets et sequence du menu de compte).
        ['cle' => 'journal_audit', 'libelle' => __('pwa.coquille.journal_audit'), 'icone' => '<path stroke-linecap="round" stroke-linejoin="round" d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><path stroke-linecap="round" stroke-linejoin="round" d="M14 2v6h6"/>'],
        // Décision PO du 18/10/2026 : le bouton « Synchroniser » du serveur,
        // ouvert à tout compte (`liensChassis()['synchronisation_postes']`).
        // Même tracé que l'entrée Import & Export (flèches d'échange).
        ['cle' => 'synchronisation_postes', 'libelle' => __('pwa.coquille.synchronisation_postes'), 'icone' => '<path stroke-linecap="round" stroke-linejoin="round" d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/>'],
    ];

    $entreesDAide = [
        ['cle' => 'aide_a_propos', 'libelle' => __('pwa.coquille.aide_a_propos'), 'icone' => '<circle cx="12" cy="12" r="10"/><path stroke-linecap="round" stroke-linejoin="round" d="M9.09 9a3 3 0 015.83 1c0 2-3 3-3 3M12 17h.01"/>'],
        ['cle' => 'contact_editeur', 'libelle' => __('pwa.coquille.contact_editeur'), 'icone' => '<path stroke-linecap="round" stroke-linejoin="round" d="M4 4h16a2 2 0 012 2v12a2 2 0 01-2 2H4a2 2 0 01-2-2V6a2 2 0 012-2z"/><path stroke-linecap="round" stroke-linejoin="round" d="M22 6l-10 7L2 6"/>'],
    ];
@endphp
<div id="shell-topbar">
  <header class="h-16 bg-[var(--navy)] flex items-center px-4 sm:px-6 shrink-0 z-30">
    {{-- maquette — shell.js l.99-101 --}}
    <button id="bouton-menu-mobile" type="button" class="lg:hidden text-white/80 mr-3" aria-label="{{ __('pwa.coquille.ouvrir_menu') }}">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" d="M4 6h16M4 12h16M4 18h16"/></svg>
    </button>

    {{-- AJOUT a la maquette (directive PO du 02/09/2026) : bascule
         d'affichage du menu lateral pour une vue plein ecran. Le maitre n'en
         porte pas — l'ecart est decide et date, et le trace SVG est declare a
         la garde des traces ($ajouts). L'etat vit dans localStorage et est
         reapplique a chaque navigation (voir layouts/pwa.blade.php) : un
         `wire:navigate` remplace le <body>, une classe posee a la main y
         disparaitrait. Desktop seulement — sur mobile le menu est deja
         escamotable par le burger. --}}
    <button id="bouton-plein-ecran" type="button" class="hidden lg:flex text-white/80 hover:text-white mr-3 transition-colors" aria-label="{{ __('pwa.coquille.plein_ecran') }}" title="{{ __('pwa.coquille.plein_ecran') }}">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="16" rx="2"/><path stroke-linecap="round" d="M9 4v16"/></svg>
    </button>

    {{-- maquette — shell.js l.102-112 --}}
    <a href="{{ route('pwa.accueil') }}" class="flex items-center gap-3 shrink-0" wire:navigate>
      {{-- Le logo TELEVERSE prime, l'actif livre reste le repli
           (ApparenceEtablissementService, onglet Logo & Apparence,
           02/09/2026) : par defaut le rendu est identique au pixel.
           Decision du PO du 14/10/2026 (D392) : le logo livre est un PNG
           PAYSAGE (735 x 403, fond blanc). Le cadre carre est garde ;
           `object-contain` remplace `object-cover`, qui rognait le paysage
           (« taco ») — jamais d'etirement.
           PA-210 tranchee par le PO le 14/10/2026, option (c) : le cadre de
           la BARRE passe en PAYSAGE au ratio du logo (735/403 ~ 1,82) — hauteur
           40 px gardee (h-10, la barre ne grandit pas), largeur 73 px. Le logo
           y remplit le cadre au lieu d'y flotter en bande de 22 px. Les cadres
           carres de connexion/demarrage/aide ne sont pas touches. --}}
      <img src="{{ app(\App\Shared\Parametres\Services\ApparenceEtablissementService::class)->urlLogo() }}" alt="{{ __('pwa.alt_logo') }}" class="w-[73px] h-10 rounded-lg bg-white object-contain ring-2 ring-[var(--gold)]">
      <div class="hidden md:block">
        <div class="flex items-center gap-2">
          <span class="text-white font-bold text-sm tracking-tight">{{ __('pwa.marque') }}</span>
          <span class="text-[10px] font-semibold text-[var(--gold)] border border-[var(--gold)] rounded px-1.5 py-0.5">{{ __('pwa.enseigne_courte') }}</span>
        </div>
        {{-- maquette — shell.js l.110 écrivait « Natitingou, Bénin —
             LogiRestock » en dur. DÉCISION DU PRODUCT OWNER DU 13/10/2026
             (« faut remplacer logiRestock par système d'information
             intégré ») : la ligne devient « Natitingou, Bénin — Système
             d'Information Intégré ». LogiRestock est le nom d'un autre
             produit (PA-194). La mention est désormais une clé de langue, et
             c'est celle de l'en-tête des états (`rapports.entete.localisation`)
             : un seul auteur pour la ligne de localisation, à l'écran comme
             sur le papier — deux clés de même valeur finiraient par diverger.
             Le client Flutter relit cette clé (D373). Seconde décision du PO
             du 13/10/2026 (PA-209, D389) : la mention devient « Système de
             gestion Intégré » (casse exacte du PO), dans la clé seule. --}}
        <p class="text-white/40 text-[11px]">{{ __('pwa.barre_localisation') }}</p>
      </div>
    </a>

    <div class="flex-1"></div>

    {{-- AJOUT à la maquette (audit PO du 01/09/2026) : recherche globale
         instantanée — le maître n'en porte pas, l'écart est décidé et daté.
         Voir le docblock de `RechercheGlobale`. --}}
    <livewire:pwa.recherche-globale />

    {{-- AJOUT à la maquette (PO, 20/10/2026) : le sélecteur d'exercice
         global — affiché seulement sur les écrans qui le suivent. Voir
         `SelecteurExercice`. --}}
    <livewire:pwa.selecteur-exercice />

    {{-- maquette — shell.js l.114-117. Le libellé est « Réseau » et non
         « Réseau Synchronisé » : l'écart et sa raison vivent dans
         `pwa.coquille.reseau`. --}}
    <div class="hidden md:flex items-center gap-2 px-3 py-1.5 rounded-full bg-[var(--succes)]/15 border border-[var(--succes)]/40 mr-3">
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="var(--succes)" stroke-width="2.5"><path d="M5 12.55a11 11 0 0114.08 0M1.42 9a16 16 0 0121.16 0M8.53 16.11a6 6 0 016.95 0M12 20h.01"/></svg>
      <span class="text-[var(--succes)] text-xs font-semibold">{{ __('pwa.coquille.reseau') }}</span>
    </div>

    {{-- `#indicateur-caisse` — maquette shell.js l.22 + caisse-ui.js
         l.168-193. RENDU depuis le 31/08/2026 : le motif d'omission ecrit ici
         (« aucun modele SessionCaisse n'existe, PA-21 ») etait devenu FAUX —
         le POS l'utilise depuis la vague CRUD, sixieme motif perime de la
         serie. L'etat est REEL (sessions_caisse), le point rouge passe 24 h
         est celui du maitre. Ecart declare : LIEN vers le POS comptant, pas
         bouton d'action — la barre est rendue par 40 ecrans, le geste de
         caisse a UN proprietaire (voir IndicateurCaisse). --}}
    @if (($caisse ?? null) !== null)
      <div id="indicateur-caisse" class="hidden md:block">
        @if ($caisse['etat'] === 'fermee')
          <a href="{{ route('pwa.pos.comptant') }}" wire:navigate id="btn-caisse"
             class="flex items-center gap-2 px-3 py-2 rounded-lg border border-white/15 text-white/80 hover:bg-white/5 text-xs font-medium mr-2">
            <span class="w-1.5 h-1.5 rounded-full bg-slate-400"></span>
            {{ __('pwa.coquille.caisse_fermee') }}
          </a>
        @else
          <a href="{{ route('pwa.pos.comptant') }}" wire:navigate id="btn-caisse"
             class="flex items-center gap-2 px-3 py-2 rounded-lg border {{ $caisse['etat'] === 'tardive' ? 'border-red-400/60 bg-red-500/10' : 'border-white/15' }} text-white/90 hover:bg-white/5 text-xs font-medium mr-2"
             title="{{ __('pwa.coquille.caisse_cloturer_titre', ['point' => $caisse['point']]) }}">
            <span class="w-1.5 h-1.5 rounded-full {{ $caisse['etat'] === 'tardive' ? 'bg-red-400' : 'bg-emerald-400' }}"></span>
            {{-- Le point de vente n'est plus affiché à côté du libellé —
                 directive PO du 02/09/2026 ; il reste dans l'infobulle. --}}
            {{ __('pwa.coquille.caisse_cloturer') }}
          </a>
        @endif
      </div>
    @endif

    {{-- maquette — shell.js l.119-123 --}}
    @if (\App\Pwa\Support\MenuLateral::peutVoirRoute($utilisateur, 'pwa.pos.comptant'))
      <a href="{{ route('pwa.pos.comptant') }}" class="flex items-center gap-2 px-3.5 py-2 rounded-lg bg-[var(--gold)] text-white hover:brightness-110 text-xs font-bold mr-2 shadow-sm transition-all" wire:navigate
         title="{{ __('pwa.coquille.vente_titre') }}">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><rect x="2" y="7" width="20" height="14" rx="2"/><path stroke-linecap="round" d="M16 7V5a2 2 0 00-2-2h-4a2 2 0 00-2 2v2M2 12h20"/></svg>
        {{-- « Vente », pas « Point de vente » — directive PO du 02/09/2026
             (retour d'audit) : l'écart au libellé du maître (`shell.js`
             l.119) est DÉCIDÉ, et déclaré à la garde des libellés. --}}
        {{ __('pwa.coquille.vente') }}
      </a>
    @endif

    {{-- Le raccourci « Journal d'Audit » du maitre (shell.js l.124-127)
         n'est PLUS rendu dans la barre : directive PO du 02/09/2026, il est
         deplace dans le menu de compte (voir $entreesDeCompte ci-dessus) —
         deplace, jamais supprime. --}}

    {{-- maquette — shell.js l.128-146 : la cloche et son panneau. Depuis le
         01/09/2026 (audit PO), le panneau est un composant Livewire IMBRIQUÉ
         branché sur les alertes d'ouverture dérivées — le refus
         `maitre-refuse:coquille#bouton-tout-marquer-lu` du 31/08/2026 est
         LEVÉ (sa raison, « aucune source réelle », a cessé d'être vraie).
         Mêmes ids, même markup : le JS de coquille n'a pas changé. --}}
    <livewire:pwa.cloche-notifications />

    {{-- maquette — shell.js l.147-183 : le menu de compte --}}
    <div class="relative ml-2 pl-3 border-l border-white/10">
      <button id="bouton-menu-profil" type="button" class="flex items-center gap-2 hover:bg-white/10 rounded-lg px-2 py-1.5 transition-colors">
        <div class="w-8 h-8 rounded-full bg-[var(--gold)] flex items-center justify-center text-[var(--navy)] font-bold text-xs shrink-0">{{ \App\Pwa\Support\MenuLateral::initiales($utilisateur) }}</div>
        <div class="hidden sm:block text-left">
          <p class="text-white text-xs font-semibold leading-tight">{{ $utilisateur?->login }}</p>
          <p class="text-[var(--gold)] text-[10px]">{{ \Illuminate\Support\Str::ucfirst($utilisateur?->role?->libelle ?? '') }}</p>
        </div>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="white" stroke-opacity=".7" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 9l6 6 6-6"/></svg>
      </button>
      <div id="menu-profil" class="hidden absolute right-0 top-12 w-56 bg-white rounded-xl shadow-2xl border border-slate-100 py-2 z-50">
        <div class="px-4 py-2.5 border-b border-slate-100">
          <p class="text-xs font-bold text-slate-700">{{ $utilisateur?->login }}</p>
          <p class="text-[11px] text-slate-400">{{ \Illuminate\Support\Str::ucfirst($utilisateur?->role?->libelle ?? '') }}</p>
        </div>

        @foreach ($entreesDeCompte as $entree)
          @include('pwa.partials.lien-chassis', [
            'url' => $liensChassis[$entree['cle']]['url'],
            'titre' => $liensChassis[$entree['cle']]['raison'],
            'libelle' => $entree['libelle'],
            'icone' => $entree['icone'],
            'taille' => 14,
            'classes' => 'flex items-center gap-2.5 px-4 py-2.5 text-xs text-slate-600 hover:bg-slate-50',
            'attributStyle' => '',
          ])
        @endforeach

        <div class="my-1 border-t border-slate-100"></div>

        @foreach ($entreesDAide as $entree)
          @include('pwa.partials.lien-chassis', [
            'url' => $liensChassis[$entree['cle']]['url'],
            'titre' => $liensChassis[$entree['cle']]['raison'],
            'libelle' => $entree['libelle'],
            'icone' => $entree['icone'],
            'taille' => 14,
            'classes' => 'flex items-center gap-2.5 px-4 py-2.5 text-xs text-slate-600 hover:bg-slate-50',
            'attributStyle' => '',
          ])
        @endforeach

        <div class="my-1 border-t border-slate-100"></div>

        {{-- La déconnexion est une ACTION Livewire, jamais un formulaire :
             elle doit se lier à l'intérieur de la racine du composant, et le
             trait `FermeSession` en est le seul chemin — le même que celui du
             pied du menu latéral. --}}
        <button type="button" wire:click="seDeconnecter" class="w-full flex items-center gap-2.5 px-4 py-2.5 text-xs text-[var(--erreur)] hover:bg-red-50 text-left" id="bouton-deconnexion">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M9 21H5a2 2 0 01-2-2V5a2 2 0 012-2h4M16 17l5-5-5-5M21 12H9"/></svg>
          {{ __('pwa.accueil.deconnexion') }}
        </button>
      </div>
    </div>
  </header>
</div>
@include('pwa.partials.banniere')

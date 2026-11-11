<!DOCTYPE html>
<html lang="fr">
<head>
{{--
    ⚠ LE TITRE VIENT DE `$title`, PAS DE `$titre` (corrigé le 31/08/2026).

    Ce layout lisait `$titre`. Or Livewire ne pose JAMAIS cette variable : le
    paramètre de `->layout('layouts.pwa', ['title' => …])` et l'attribut
    `#[Title]` alimentent tous deux `$title` — `SupportPageComponents` le
    fusionne dans les paramètres du layout (`View::macro('title')`, l.39-45 du
    paquet). Le `??` retombait donc sur la marque à chaque page : les cinq
    pages mesurées rendaient toutes `<title>TATACORA AFRIQUE</title>`, y
    compris celles qui déclaraient un `#[Title]`.

    Le défaut est invisible à la relecture de chaque moitié : le layout est
    correct, les composants aussi, et c'est le raccord entre les deux qui
    manque. Il n'a été vu qu'en chargeant réellement les pages.

    `$titre` reste accepté en premier : deux vues appellent ce layout en le
    passant, et les casser pour uniformiser un nom serait un dommage gratuit.
--}}
@include('pwa.partials.tete', ['titre' => $titre ?? $title ?? __('pwa.titre_defaut')])
@livewireStyles
{{-- Bascule plein ecran (directive PO du 02/09/2026) : la classe
     `sidebar-masquee` posee sur <body> escamote le menu lateral sur grand
     ecran. La regle vit ICI et non dans app.css : cette feuille est la copie
     conforme du maitre, qui ne connait pas cette bascule — y ecrire une regle
     etrangere ferait diverger la copie. Limitee a lg (1024px) : en dessous,
     le menu est deja escamotable par le burger du maitre. --}}
<style>
    /* Cible l'aside lui-meme, jamais son conteneur : la garde d'ordre des
       blocs de la coquille repere les marqueurs shell-* par position dans la
       page servie, et un selecteur qui les nommerait ici les ferait
       apparaitre avant le premier bloc reel. */
    @media (min-width: 1024px) {
        body.sidebar-masquee aside#sidebar { display: none; }
    }
</style>
</head>
{{--
    Coquille des pages avec session — reprend le `<body>` des pages protégées du
    prototype (`prototype_v2/pages/tableau-de-bord.html`) :
    `h-screen flex flex-col overflow-hidden` sur fond clair, puis
    `#shell-topbar`, `#shell-banniere`, et la ligne `flex flex-1 overflow-hidden`
    contenant `#shell-sidebar` et `<main>`.

    Ces quatre blocs sont rendus par le composant Livewire lui-même
    (`pwa/livewire/accueil.blade.php` inclut les partials) et non par ce layout :
    le bouton Déconnexion de la barre supérieure et du menu latéral est une
    action Livewire, et une action ne se lie qu'à l'intérieur de la racine du
    composant. Les placer ici les rendrait inertes — le genre de défaut qu'un
    test de rendu ne voit pas.

    ⚠ `data-module` est celui de la PAGE DU MAÎTRE, jamais une constante.
    Chaque page du maître le porte sur son `<body>` — `M6` sur
    `m6-stocks.html` l.14, `M7` sur `m7-achats.html`, `M2`, `M3`, `M5`… — et
    c'est de lui que `rbac.js` tire le masquage d'interface côté maquette. Il
    valait `M11` pour TOUTES les pages jusqu'au 27/08/2026, c'est-à-dire qu'une
    page de stocks se déclarait page de tableau de bord. Le défaut était sans
    effet ici (le RBAC de la PWA est serveur, jamais un attribut HTML), mais
    c'est exactement le genre d'attribut qu'on finit par lire comme une source :
    la clause d'immuabilité porte sur ce qui se voit ET sur ce qui se lit.
    Le `??` conserve `M11` pour l'accueil, qui est bien la page dont il vient.
--}}
<body data-module="{{ $module ?? 'M11' }}" class="h-screen flex flex-col overflow-hidden" style="background:var(--fond-clair)">
    {{ $slot }}

    {{-- Le VERROU DE SESSION — un seul point de montage, pour TOUT écran
         authentifié (ce layout n'est jamais utilisé pour la connexion, qui
         a le sien : `layouts.pwa-invite`). Voir
         `App\Pwa\Livewire\Transverse\VerrouSession`, demande du Product
         Owner du 01/09/2026, sans équivalent au maître. --}}
    @livewire(\App\Pwa\Livewire\Transverse\VerrouSession::class)
    {{-- Les deux modales d'ouverture de session (maitre :
         alertes-ouverture.js, PO 02/09/2026) — rendues seulement quand le
         drapeau pose a la connexion est present et la bascule ouverte. --}}
    @livewire(\App\Pwa\Livewire\Transverse\AlertesOuvertureModales::class)

    @livewireScripts
    @include('pwa.partials.session-expiree')

    <script>
        // Service worker : cache de l'app shell uniquement, jamais de donnees
        // metier (LARAVEL_PWA.md §4).
        // L'enregistrement du service worker vit dans `pwa.partials.tete`
        // depuis le 02/09/2026 : toutes les surfaces (connexion comprise)
        // doivent avoir la page de repli hors connexion, pas seulement la
        // coquille authentifiee.
        try { localStorage.setItem('pwa-session-active', '1'); } catch (e) { /* sans stockage, la page de repli affichera la variante non connectee */ }

        // Comportements de la coquille — transcrits de `initialiserShell()`
        // (prototype_v2/assets/js/shell.js) : ouverture du menu escamotable
        // sur mobile, fermeture par le voile, bascule des deux menus deroulants
        // de la barre superieure.
        //
        // Delegation depuis `document` plutot qu'ecouteurs poses sur les
        // elements : Livewire remplace des noeuds du DOM a chaque
        // rafraichissement, et un ecouteur pose sur un noeud remplace disparait
        // sans erreur. Le menu cesserait de s'ouvrir apres la premiere action,
        // et rien ne le signalerait.
        (function () {
            const basculer = (element, force) => {
                if (element) element.classList.toggle('hidden', force);
            };

            // ⚠ LE MENU MOBILE A UNE MEMOIRE, ET ELLE EST ICI — PAS DANS LE
            // DOM. La coquille entiere (barre superieure ET menu lateral) est
            // rendue DANS chaque composant Livewire : tout aller-retour
            // (battement de maintien de session des POS, selection d'un
            // sejour, saisie) remorphe `-translate-x-full` depuis le Blade et
            // refermait le menu a peine ouvert — « le burger ne marche pas »
            // constate par le PO sur pos/heberges le 02/09/2026. L'etat vit
            // donc dans cette variable et se REAPPLIQUE apres chaque morph.
            let sidebarMobileOuverte = false;

            const appliquerSidebarMobile = () => {
                const sidebar = document.getElementById('sidebar');
                const voile = document.getElementById('overlay-sidebar-mobile');

                if (sidebar) sidebar.classList.toggle('-translate-x-full', ! sidebarMobileOuverte);
                if (voile) voile.classList.toggle('hidden', ! sidebarMobileOuverte);
            };

            document.addEventListener('click', (evenement) => {
                const cible = evenement.target instanceof Element ? evenement.target : null;
                const menuProfil = document.getElementById('menu-profil');
                const menuNotifications = document.getElementById('menu-notifications');

                if (cible && cible.closest('#bouton-plein-ecran')) {
                    // Bascule plein ecran (PO 02/09/2026). L'etat est persiste
                    // dans localStorage et REAPPLIQUE apres chaque navigation
                    // (voir plus bas) : `wire:navigate` remplace le <body>,
                    // une classe posee a la main y disparaitrait a la page
                    // suivante et la bascule semblerait « ne pas tenir ».
                    const masquee = document.body.classList.toggle('sidebar-masquee');
                    try { localStorage.setItem('pwa-sidebar-masquee', masquee ? '1' : '0'); } catch (e) { /* stockage indisponible : la bascule reste valable pour la page courante */ }
                    return;
                }

                if (cible && cible.closest('#bouton-menu-mobile')) {
                    sidebarMobileOuverte = true;
                    appliquerSidebarMobile();
                    return;
                }

                if (cible && cible.closest('#overlay-sidebar-mobile')) {
                    sidebarMobileOuverte = false;
                    appliquerSidebarMobile();
                    return;
                }

                if (cible && cible.closest('#bouton-menu-profil')) {
                    // Le maître (shell.js l.148-149) ne ferme PAS l'autre
                    // menu deroulant a l'ouverture de celui-ci — chaque
                    // bouton a son propre `e.stopPropagation()`, et les deux
                    // fermetures globales sont deux ecouteurs `document`
                    // separes qui ne se declenchent jamais sur ce clic. Les
                    // deux panneaux peuvent donc rester ouverts en meme
                    // temps ; le forcer ici etait une divergence du maître,
                    // releve a l'audit du 01/09/2026.
                    if (menuProfil) menuProfil.classList.toggle('hidden');
                    return;
                }

                if (cible && cible.closest('#bouton-cloche-notifications')) {
                    if (menuNotifications) menuNotifications.classList.toggle('hidden');
                    return;
                }

                // Un clic a l'interieur d'un menu deroulant ne le referme pas ;
                // n'importe quel clic ailleurs referme les deux (shell.js
                // l.296 et l.364, deux ecouteurs `document` distincts qui
                // produisent le meme effet cumule ici).
                if (cible && cible.closest('#menu-notifications')) return;
                if (cible && cible.closest('#menu-profil')) return;

                basculer(menuProfil, true);
                basculer(menuNotifications, true);
            });

            // Filtres de notifications : ils changent l'etat visuel du bouton
            // actif, exactement comme dans le prototype. La liste reste vide
            // tant qu'aucune source de notification n'existe (M12 n'est
            // implemente nulle part) — aucune donnee n'est fabriquee ici.
            // La bascule plein ecran survit aux navigations : l'etat est relu
            // du stockage local a chaque remplacement du <body>. Sans cela, le
            // premier clic sur une entree du menu rafficherait la barre.
            const appliquerSidebarMasquee = () => {
                let masquee = false;
                try { masquee = localStorage.getItem('pwa-sidebar-masquee') === '1'; } catch (e) { /* stockage indisponible : la barre reste affichee */ }
                document.body.classList.toggle('sidebar-masquee', masquee);
            };
            appliquerSidebarMasquee();
            document.addEventListener('livewire:navigated', () => {
                appliquerSidebarMasquee();
                // Nouvelle page : le menu escamotable repart ferme, comme au
                // maitre — seule la bascule plein ecran est persistante.
                sidebarMobileOuverte = false;
            });

            // Reapplication apres chaque morph Livewire — c'est la moitie du
            // correctif qui compte : sans elle, la memoire ci-dessus ne sert
            // qu'au premier rendu. `livewire:init` n'a pas encore eu lieu si
            // Livewire se charge apres ce script ; les deux chemins menent au
            // meme branchement, une seule fois.
            const brancherMorph = () => {
                window.Livewire.hook('morphed', () => appliquerSidebarMobile());
            };
            if (window.Livewire && typeof window.Livewire.hook === 'function') {
                brancherMorph();
            } else {
                document.addEventListener('livewire:init', brancherMorph);
            }

            document.addEventListener('click', (evenement) => {
                const cible = evenement.target instanceof Element ? evenement.target : null;
                const bouton = cible ? cible.closest('.filtre-notif') : null;
                if (!bouton) return;

                document.querySelectorAll('.filtre-notif').forEach((autre) => {
                    const actif = autre === bouton;
                    autre.classList.toggle('bg-[var(--navy)]', actif);
                    autre.classList.toggle('text-white', actif);
                    autre.classList.toggle('text-slate-500', !actif);
                });
            });
        })();
    </script>
</body>
</html>

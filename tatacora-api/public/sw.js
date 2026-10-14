/*
 * Service worker de la PWA TATACORA — LARAVEL_PWA.md §4.
 *
 * REGLE ABSOLUE : ne met en cache QUE l'app shell (styles, page de repli).
 * Aucune donnee metier n'est jamais mise en cache.
 *
 * Pourquoi c'est structurant et non un detail de performance : mettre en
 * cache un planning d'occupation ou un niveau de stock afficherait, hors
 * connexion, des chiffres perimes ayant l'apparence de chiffres a jour.
 * Sur du stock et de la caisse, une donnee perimee credible est pire qu'une
 * absence de donnee. Le fonctionnement hors connexion est assure par
 * l'application Flutter, dont c'est le role — pas par ce service worker.
 */

const CACHE = 'tatacora-shell-v4'; // v4 (14/10/2026, D392) : nouveau logo `logo.png` (decision du PO) ; v3 (02/09/2026) : page de repli avec gestes de reprise — le bump force la remise en cache.
const REPLI = '/pwa/hors-connexion';

/*
 * App shell : la page de repli ET les ressources dont son rendu depend.
 *
 * Sans elles, la page de repli s'affichait hors connexion SANS aucune mise en
 * forme — texte brut sur fond blanc. Elle etait bien servie, donc le service
 * worker paraissait fonctionner ; seule une ouverture reelle hors connexion le
 * montrait. Aucune donnee metier n'est ajoutee ici : ces fichiers sont la
 * coquille, exactement ce que LARAVEL_PWA.md §4 autorise.
 */
const APP_SHELL = [
    REPLI,
    '/assets/css/app.css',
    '/assets/css/vendor/fonts.css',
    '/assets/js/vendor/tailwind-play-cdn.js',
    '/assets/img/logo.png',
    '/assets/img/gite-cover.jpg',
];

self.addEventListener('install', (event) => {
    event.waitUntil(
        caches.open(CACHE).then((cache) => cache.addAll(APP_SHELL)).then(() => self.skipWaiting())
    );
});

self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches.keys()
            .then((cles) => Promise.all(cles.filter((c) => c !== CACHE).map((c) => caches.delete(c))))
            .then(() => self.clients.claim())
    );
});

self.addEventListener('fetch', (event) => {
    const requete = event.request;

    // Les ressources de la coquille (styles, polices, images de marque) sont
    // servies depuis le cache quand le reseau manque. Mettre en cache la page
    // de repli sans ses styles revenait a la servir en texte brut : le cache
    // repondait, donc tout paraissait fonctionner.
    if (requete.method === 'GET' && new URL(requete.url).pathname.startsWith('/assets/')) {
        event.respondWith(
            caches.match(requete).then((enCache) => enCache || fetch(requete))
        );
        return;
    }

    // Sinon, seules les navigations sont interceptees. Tout le reste (y compris
    // les requetes Livewire qui portent des donnees metier) part sur le reseau
    // sans jamais transiter par le cache.
    if (requete.mode !== 'navigate') {
        return;
    }

    event.respondWith(
        fetch(requete).catch(() => caches.match(REPLI))
    );
});

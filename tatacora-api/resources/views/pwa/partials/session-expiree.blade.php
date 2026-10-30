{{--
    SESSION EXPIREE — le seul gestionnaire de HTTP 419 / 401 des requetes
    Livewire (Product Owner, 30/10/2026).

    Livewire 4.4 (composer.lock) reagit a un 419 (jeton CSRF ou session
    expire) par `confirm("This page has expired. Would you like to refresh the
    page?")` : boite NATIVE du navigateur, en anglais, que personne ne sait
    lire au comptoir. Elle ne doit plus jamais apparaitre. On l'intercepte par
    l'API de la version (`Livewire.interceptRequest` + `onError` +
    `preventDefault`, qui court-circuite le `confirm` de `livewire.js`) ; le
    crochet historique `Livewire.hook('request')` + `fail` reste le repli.

    Puis la page est rechargee EN SILENCE : la session etant expiree, le
    middleware `auth` renvoie vers la connexion, qui affiche « Votre session a
    expire, reconnectez-vous. » Le drapeau qui declenche ce message est un
    simple indice d'affichage dans `sessionStorage` (jamais une donnee
    d'authentification, rien d'exploitable dans l'adresse).

    Ce n'est PAS un « keep-alive » : rien ici ne prolonge la session.

    Script en ligne et local — aucun CDN. La politique de contenu est en
    mode rapport seul (`EnTetesSecurite`), comme les autres scripts du gabarit.
--}}
<script>
    (function () {
        var CLE = 'pwa-session-expiree';

        // Message de la page de connexion : montre si le rechargement vient
        // d'une session expiree, puis le drapeau est consomme. Sur une page
        // authentifiee (pas de bandeau) le drapeau est simplement efface : une
        // requete refusee alors que la session vit encore ne doit pas faire
        // apparaitre le message a une connexion ulterieure.
        try {
            var bandeau = document.getElementById('bandeau-session-expiree');
            if (bandeau && sessionStorage.getItem(CLE) === '1') bandeau.hidden = false;
            sessionStorage.removeItem(CLE);
        } catch (e) { /* sans stockage : pas de message, la redirection se fait quand meme */ }

        // `wire:navigate` rejoue les scripts du <body> : un seul branchement.
        if (window.__pwaSessionExpireeBranchee) return;
        window.__pwaSessionExpireeBranchee = true;

        var recharger = function () {
            try { sessionStorage.setItem(CLE, '1'); } catch (e) { /* idem */ }
            window.location.reload();
        };
        var estExpiration = function (statut) { return statut === 419 || statut === 401; };

        var brancher = function () {
            var L = window.Livewire;
            if (!L) return;
            if (typeof L.interceptRequest === 'function') {
                L.interceptRequest(function (contexte) {
                    contexte.onError(function (erreur) {
                        if (erreur && erreur.response && estExpiration(erreur.response.status)) {
                            erreur.preventDefault();
                            recharger();
                        }
                    });
                });
            } else if (typeof L.hook === 'function') {
                L.hook('request', function (contexte) {
                    contexte.fail(function (echec) {
                        if (estExpiration(echec.status)) {
                            echec.preventDefault();
                            recharger();
                        }
                    });
                });
            }
        };

        // Livewire demarre apres ce script : `livewire:init` precede toute requete.
        if (window.Livewire && typeof window.Livewire.interceptRequest === 'function') brancher();
        else document.addEventListener('livewire:init', brancher);
    })();
</script>

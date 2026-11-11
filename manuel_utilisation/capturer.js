/* ---------------------------------------------------------------------------
 * LogiRestock — Manuel d'utilisation : capture des écrans.
 *
 * ⚠ CE SCRIPT CAPTURE LA PWA LARAVEL (`tatacora-api`), ET C'EST UN CHANGEMENT
 * DE SOURCE (12/09/2026). Jusqu'à cette date il photographiait
 * `prototype_v2/`, devenu une ANCIENNE version le 10/09/2026 (PA-183) : le
 * manuel montrait donc une interface qui ne fait plus foi. La vue Blade de la
 * PWA porte la dernière version de chaque écran (PA-182), et c'est elle que le
 * personnel a sous les yeux. L'ancien script est conservé à côté, en
 * `capturer.prototype-v2.js.sauvegarde`, pour mémoire.
 *
 * Prérequis :
 *   1. le serveur tourne          php artisan serve --port=8000
 *   2. la base est semée          php artisan migrate:fresh --seed
 *   3. un compte réel est fourni  TATACORA_LOGIN / TATACORA_MDP
 *
 * **Aucun mot de passe n'est écrit dans ce fichier**, et il ne doit jamais y
 * en entrer : un mot de passe posé dans le dépôt est connu de quiconque le
 * lit. Le script refuse de démarrer sans ces deux variables.
 *
 * Base de capture (09/11/2026) : JAMAIS la base de développement ni `tatacora_test`.
 * Une base `tatacora_capt` à soi, un `.env.local` hors commit (APP_ENV=local,
 * APP_KEY générée localement, mots de passe COMPTE_* JETABLES inventés pour
 * l'occasion), puis : migrate:fresh --force · db:seed · db:seed
 * --class=DemonstrationSeeder · db:seed --class=ComptesReelsSeeder · serve.
 * Le navigateur est celui de CHROME_PATH, sinon le Chromium de
 * /opt/pw-browsers/chromium, sinon Chrome sous Windows. Les écrans nouveaux
 * (proformas, MECeF, postes, comptes, clôture…) sont dans capturer-nouveautes.js.
 *
 * Exécution :
 *   TATACORA_LOGIN=admin TATACORA_MDP=... PPTR_DIR=~/outils-pdf node capturer.js
 * ------------------------------------------------------------------------- */

const fs = require('fs');
const path = require('path');
const MODULES = process.env.PPTR_DIR || path.join(__dirname, 'node_modules');
const puppeteer = require(path.join(MODULES, 'node_modules', 'puppeteer-core'));

const BASE = process.env.TATACORA_URL || 'http://127.0.0.1:8000';
const LOGIN = process.env.TATACORA_LOGIN;
const MDP = process.env.TATACORA_MDP;
const SORTIE = path.join(__dirname, 'captures');
// Chemin du navigateur : variable CHROME_PATH, sinon le Chromium pré-installé (Linux), sinon Chrome sous Windows.
const CHROME = process.env.CHROME_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : 'C:/Program Files/Google/Chrome/Application/chrome.exe');

if (!LOGIN || !MDP) {
  console.error(
    'TATACORA_LOGIN et TATACORA_MDP sont obligatoires : ce script se connecte\n' +
    'réellement à la PWA. Sans session, chaque capture montrerait l’écran de\n' +
    'connexion à la place du module.',
  );
  process.exit(1);
}

/* Les écrans, dans l'ordre du manuel.
 *
 * `fichier` reprend le nom employé par les chapitres (`src/part-*.html`) :
 * garder ces noms évite de réécrire 35 balises <img> pour un changement de
 * source. Plusieurs entrées partagent une même adresse quand le manuel montre
 * le même écran sous deux angles — c'était déjà le cas au prototype. */
const ECRANS = [
  { fichier: 'tableau-de-bord', url: '/pwa' },
  { fichier: 'a-tableau-de-bord', url: '/pwa' },
  { fichier: 'a-navigation', url: '/pwa' },
  // L'onglet « Pilotage consolidé » : sans ce clic, la figure montrait la Vue d'exploitation (doublon du tableau de bord).
  { fichier: 'm11-pilotage', url: '/pwa', etapes: [{ bouton: 'Pilotage consolidé', attente: 2200 }] },
  { fichier: 'reservations', url: '/pwa/reservations' },
  { fichier: 'm1-hebergement', url: '/pwa/hebergement' },
  { fichier: 'm3-clients-creances', url: '/pwa/clients' },
  { fichier: 'm3-crm', url: '/pwa/clients' },
  { fichier: 'm2-facturation', url: '/pwa/facturation' },
  { fichier: 'historique-ventes', url: '/pwa/historique-ventes' },
  { fichier: 'pos', url: '/pwa/pos/comptant' },
  { fichier: 'a-pos', url: '/pwa/pos/comptant' },
  { fichier: 'a-caisse', url: '/pwa/pos/comptant' },
  { fichier: 'pos-heberges', url: '/pwa/pos/heberges' },
  { fichier: 'a-pos-heberges', url: '/pwa/pos/heberges' },
  { fichier: 'm5-bar-carte', url: '/pwa/bar/carte' },
  { fichier: 'm5-bar', url: '/pwa/bar/carte' },
  { fichier: 'm4-restaurant-carte', url: '/pwa/restaurant/carte' },
  { fichier: 'm4-restaurant', url: '/pwa/restaurant/plats' },
  { fichier: 'm4-restauration', url: '/pwa/restaurant/plats' },
  { fichier: 'm6-stocks', url: '/pwa/stocks' },
  { fichier: 'm6-inventaires', url: '/pwa/stocks/inventaires' },
  { fichier: 'm7-achats', url: '/pwa/achats' },
  { fichier: 'm7-approvisionnement', url: '/pwa/achats/approvisionnement' },
  { fichier: 'm8-locations', url: '/pwa/vehicules' },
  { fichier: 'm9-tourisme-departs', url: '/pwa/tourisme' },
  { fichier: 'depenses', url: '/pwa/depenses' },
  { fichier: 'm10-comptabilite', url: '/pwa/comptabilite' },
  { fichier: 'm10-syscohada', url: '/pwa/comptabilite' },
  { fichier: 'm10-plan-comptable', url: '/pwa/comptabilite/plan-comptable' },
  { fichier: 'm10-journal', url: '/pwa/comptabilite/journal' },
  { fichier: 'm10-grand-livre', url: '/pwa/comptabilite/grand-livre' },
  { fichier: 'm10-balance', url: '/pwa/comptabilite/balance' },
  { fichier: 'm10-resultat', url: '/pwa/comptabilite/compte-resultat' },
  { fichier: 'm10-bilan', url: '/pwa/comptabilite/bilan' },
  { fichier: 'm10-flux-tresorerie', url: '/pwa/comptabilite/flux-tresorerie' },
  { fichier: 'm10-notes-annexes', url: '/pwa/comptabilite/notes-annexes' },
  { fichier: 'm10-etats-financiers', url: '/pwa/comptabilite/etats-financiers' },
  { fichier: 'm10-analytique', url: '/pwa/comptabilite/analytique' },
  { fichier: 'm10-cloture', url: '/pwa/comptabilite/cloture' },
  { fichier: 'm13-paie', url: '/pwa/paie' },
  { fichier: 'm13-rh', url: '/pwa/paie' },
  { fichier: 'm12-notifications-hub', url: '/pwa/notifications' },
  { fichier: 'm12-notifications', url: '/pwa/notifications' },
  { fichier: 'm14-etats-studio', url: '/pwa/etats' },
  { fichier: 'a-etats', url: '/pwa/etats' },
  { fichier: 'm14-etats', url: '/pwa/etats/bibliotheque' },
  { fichier: 'roles-permissions', url: '/pwa/roles-permissions' },
  // L'onglet « Activation & Sécurité » : trois bascules, rubriques Charges sociales et Exploitation (demande des rédacteurs du 09/11/2026).
  { fichier: 'parametres', url: '/pwa/parametres', etapes: [{ bouton: 'Activation & Sécurité', attente: 1500 }] },
  { fichier: 'import-export', url: '/pwa/import-export' },
  { fichier: 'a-import', url: '/pwa/import-export' },
  { fichier: 'journal-audit', url: '/pwa/journal-audit' },
  { fichier: 'aide-a-propos', url: '/pwa/aide-a-propos' },
  { fichier: 'contact-editeur', url: '/pwa/contact-editeur' },
  { fichier: 'mon-profil', url: '/pwa/mon-profil' },
];

/* Les cinq figures qui montrent une MODALE : il faut l'ouvrir. Le libellé du
 * bouton est celui de la vue — s'il change, la capture échoue bruyamment
 * plutôt que de rendre l'écran sans sa fenêtre, ce que personne ne verrait. */
const MODALES = [
  { fichier: 'a-reservation-modale', url: '/pwa/reservations', etapes: [{ bouton: 'Nouvelle réservation' }] },
  { fichier: 'a-depense-modale', url: '/pwa/depenses', etapes: [{ bouton: 'Nouvelle dépense' }] },
  // ⚠ Les deux écrans d'inventaire ne portent AUCUN bouton « Nouvel
  // inventaire » : la vue ouvre un inventaire **par point de stockage**
  // (`ouvrirInventaire('<id>')`) et saisit un comptage **par article**
  // (`ouvrirComptage('<id>')`), tous deux sous l'onglet « Inventaire
  // physique ». On vise donc l'appel Livewire, pas un libellé deviné : un
  // libellé qui change fait échouer la capture en silence, un appel qui
  // disparaît la fait échouer bruyamment.
  // ⚠ `ouvrirInventaire('<lieu>')` n'ouvre AUCUNE fenêtre : il OUVRE un
  // inventaire, c'est-à-dire qu'il ÉCRIT. Le cliquer pour photographier a créé
  // un inventaire dans la base le 14/09/2026, et la figure « ouverture » a
  // montré la feuille de comptage au lieu de la liste des points de stockage.
  // Un script de capture ne déclenche pas un geste métier : on photographie
  // l'onglet tel qu'il est, et le journal DIT laquelle des deux étapes est à
  // l'écran — la liste ne s'affiche que si aucun inventaire ne court.
  {
    fichier: 'a-inventaire-ouvrir',
    url: '/pwa/stocks/inventaires',
    etapes: [{ selecteur: '[role="tab"][wire\\:click*="\'inventaire\'"]', attente: 1600 }],
  },
  {
    fichier: 'a-inventaire-compter',
    url: '/pwa/stocks/inventaires',
    etapes: [
      { selecteur: '[role="tab"][wire\\:click*="\'inventaire\'"]', attente: 1600 },
      { selecteur: '[wire\\:click^="ouvrirComptage"]' },
    ],
  },
  // ⚠ « Fiche des prix » n'ouvre AUCUNE modale : le bouton
  // (`wire:click="imprimerFichePrix"`) produit un DOCUMENT qui s'imprime. La
  // figure montre donc la carte du bar et le bouton qui l'édite — prétendre
  // photographier une fenêtre qui n'existe pas avait produit, le 14/09/2026,
  // une capture de l'alerte « Stock critique » légendée « fiche des prix ».
  { fichier: 'a-fiche-prix', url: '/pwa/bar/carte', etapes: [] },
];

const attendre = (ms) => new Promise((r) => setTimeout(r, ms));

/* Reprendre UNE capture sans refaire les soixante autres :
 *   CAPTURES=a-inventaire-ouvrir,a-inventaire-compter node capturer.js
 * La connexion reste faite dans tous les cas — sans session, la capture
 * montrerait l'écran de connexion à la place du module. */
const FILTRE = (process.env.CAPTURES || '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);
const retenu = (fichier) => FILTRE.length === 0 || FILTRE.includes(fichier);

(async () => {
  fs.mkdirSync(SORTIE, { recursive: true });

  const navigateur = await puppeteer.launch({
    executablePath: CHROME,
    headless: 'new',
    // Chromium lit sa langue dans LANGUAGE : sans elle, les champs date affichent mm/jj/aaaa.
    env: { ...process.env, LANGUAGE: 'fr', LANG: 'fr_FR.UTF-8' },
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--hide-scrollbars', '--lang=fr'],
    defaultViewport: { width: 1440, height: 900, deviceScaleFactor: 2 },
  });
  const page = await navigateur.newPage();
  await page.setExtraHTTPHeaders({ 'Accept-Language': 'fr-FR,fr;q=0.9' }); // dates jj/mm/aaaa dans les champs
  page.on('pageerror', (e) => console.log('  [erreur page]', String(e).slice(0, 120)));

  /* ⚠ La PWA est une coquille à hauteur d'écran : le contenu défile DANS
   * `<main>`, pas dans le document. `document.scrollHeight` rendait donc 900
   * partout, et tout écran long (hub comptable, paramètres, journal) était
   * coupé au premier tiers — constaté à l'œil le 09/11/2026. On mesure le
   * bas de ce qui défile, et le bas des fenêtres (`position: fixed`, plafonnées
   * à 90 vh : on agrandit tant que leur corps défile). Plafond : 1500 px. */
  const mesurerHauteur = () =>
    page.evaluate(() => {
      let bas = document.documentElement.scrollHeight;
      for (const n of document.querySelectorAll('main, [class*="overflow-y-auto"]')) {
        const r = n.getBoundingClientRect();
        if (r.width < 600) continue; // le menu latéral n'est pas le contenu
        bas = Math.max(bas, Math.ceil(r.top + n.scrollHeight));
      }
      return bas;
    });
  const deborde = () =>
    page.evaluate(() => {
      let pire = 0;
      for (const n of document.querySelectorAll('div, form, section')) {
        const st = getComputedStyle(n);
        if (st.position !== 'fixed' || st.visibility === 'hidden') continue;
        const r = n.getBoundingClientRect();
        if (r.width <= 300 || r.height <= 200 || r.width > 1300) continue;
        for (const interne of n.querySelectorAll('*')) {
          const ri = interne.getBoundingClientRect();
          if (ri.width > 200 && interne.scrollHeight > interne.clientHeight + 8) {
            pire = Math.max(pire, interne.scrollHeight - interne.clientHeight);
          }
        }
      }
      return pire;
    });

  const photographier = async (fichier) => {
    const hauteurUtile = await mesurerHauteur();
    let hauteur = Math.min(Math.max(hauteurUtile, 700), 1500);
    await page.setViewport({ width: 1440, height: hauteur, deviceScaleFactor: 2 });
    await attendre(500);
    for (let tour = 0; tour < 5; tour++) {
      const d = await deborde();
      if (d <= 8 || hauteur >= 1500) break;
      hauteur = Math.min(hauteur + Math.ceil(d / 0.85) + 8, 1500);
      await page.setViewport({ width: 1440, height: hauteur, deviceScaleFactor: 2 });
      await attendre(500);
    }
    await page.setViewport({ width: 1440, height: hauteur, deviceScaleFactor: 2 });
    await attendre(400);
    await page.screenshot({
      path: path.join(SORTIE, fichier + '.png'),
      clip: { x: 0, y: 0, width: 1440, height: hauteur },
    });
    await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 2 });
  };

  const rapport = [];

  // 0. L'écran de démarrage, AVANT la connexion : une fois connecté, il redirige
  //    aussitôt vers le tableau de bord et la navigation détruit la page.
  if (retenu('splash')) {
    // La page redirige d'elle-même 300 ms après 100 % : une page à part, dont la
    // redirection est neutralisée, pour photographier l'état final (« Prêt. »).
    const ps = await navigateur.newPage();
    await ps.setExtraHTTPHeaders({ 'Accept-Language': 'fr-FR,fr;q=0.9' });
    await ps.evaluateOnNewDocument(() => {
      const st = window.setTimeout.bind(window);
      window.setTimeout = (fn, ms, ...a) => (String(fn).includes('location.href') ? 0 : st(fn, ms, ...a));
    });
    await ps.goto(BASE + '/pwa/demarrage', { waitUntil: 'domcontentloaded' });
    await attendre(2600);
    await ps.screenshot({ path: path.join(SORTIE, 'splash.png'), clip: { x: 0, y: 0, width: 1440, height: 900 } });
    await ps.close();
    rapport.push('splash\t/pwa/demarrage');
  }

  // 1. L'écran de connexion, AVANT de se connecter.
  await page.goto(BASE + '/pwa/connexion', { waitUntil: 'networkidle0' });
  await attendre(900);
  if (retenu('login')) await photographier('login');
  if (retenu('a-connexion')) await photographier('a-connexion');
  rapport.push('login\t/pwa/connexion');

  // 2. Connexion réelle, par le formulaire.
  await page.type('#champ-identifiant', LOGIN, { delay: 12 });
  await page.type('#champ-motdepasse', MDP, { delay: 12 });
  await Promise.all([
    page.waitForNavigation({ waitUntil: 'networkidle0', timeout: 30000 }).catch(() => null),
    page.click('#formulaire-connexion button[type="submit"]'),
  ]);
  await attendre(1500);

  /* ⚠ À l'ouverture de session, la PWA empile ses alertes — « Stock
   * critique », caisse non ouverte… — dans des modales qui RECOUVRENT
   * l'écran. Sans ce congé, elles se retrouvaient sur les captures, et l'une
   * d'elles a été prise pour la fiche des prix (trouvé en REGARDANT l'image,
   * pas le journal du script : celui-ci annonçait « modale ouverte »).
   * On les ferme toutes avant la première photo. */
  const congedierAlertes = async () => {
    for (let i = 0; i < 6; i++) {
      const ferme = await page.evaluate(() => {
        const mots = ['j’ai pris connaissance', "j'ai pris connaissance"];
        const cible = [...document.querySelectorAll('button')].find((b) =>
          mots.some((m) => (b.innerText || '').trim().toLowerCase().includes(m)),
        );
        if (!cible) return false;
        cible.click();
        return true;
      });
      if (!ferme) return i;
      await attendre(700);
    }
    return 6;
  };

  const apres = page.url();
  if (apres.includes('/connexion')) {
    console.error('ÉCHEC DE CONNEXION — le formulaire a été refusé. Aucune capture de module ne serait valable.');
    await page.screenshot({ path: path.join(SORTIE, '_echec-connexion.png') });
    await navigateur.close();
    process.exit(2);
  }

  const fermees = await congedierAlertes();
  if (fermees > 0) console.log(fermees + ' alerte(s) d’ouverture de session fermée(s) avant les captures.');

  // 3. Les écrans.
  for (const e of ECRANS) {
    if (!retenu(e.fichier)) continue;
    try {
      await page.goto(BASE + e.url, { waitUntil: 'networkidle0', timeout: 45000 });
      await attendre(e.attente || 1600);
      await congedierAlertes();
      for (const etape of e.etapes || []) {
        const fait = await page.evaluate((et) => {
          const visible = (n) => n.offsetParent !== null && n.getBoundingClientRect().width > 8;
          const cible = et.selecteur
            ? document.querySelector(et.selecteur)
            : [...document.querySelectorAll('button, a, [role="tab"]')].filter(visible).find((b) =>
                (b.innerText || '').trim().toLowerCase().includes(et.bouton.toLowerCase()),
              );
          if (!cible) return false;
          cible.click();
          return true;
        }, etape);
        if (!fait) throw new Error('CIBLE INTROUVABLE ' + (etape.selecteur || etape.bouton));
        await attendre(etape.attente || 1500);
      }
      const etat = await page.evaluate(() => ({
        titre: (document.querySelector('h1') || {}).textContent || document.title,
        texte: document.body.innerText.length,
        refus: /403|Accès refusé|Cette action n’est pas autorisée/.test(document.body.innerText.slice(0, 400)),
      }));
      await photographier(e.fichier);
      rapport.push(
        `${e.fichier}\t${e.url}\t${etat.texte} car.${etat.refus ? '\tREFUS RBAC' : ''}\t${(etat.titre || '').trim().slice(0, 46)}`,
      );
    } catch (err) {
      rapport.push(`${e.fichier}\t${e.url}\tECHEC ${String(err).slice(0, 90)}`);
    }
  }

  // 4. Les modales.
  for (const m of MODALES) {
    if (!retenu(m.fichier)) continue;
    try {
      await page.goto(BASE + m.url, { waitUntil: 'networkidle0', timeout: 45000 });
      await attendre(1600);
      await congedierAlertes();

      let manquante = null;
      for (const etape of m.etapes) {
        const fait = await page.evaluate((e) => {
          const cible = e.selecteur
            ? document.querySelector(e.selecteur)
            : [...document.querySelectorAll('button, a')].find((b) =>
                (b.innerText || '').trim().toLowerCase().includes(e.bouton.toLowerCase()),
              );
          if (!cible) return false;
          cible.click();
          return true;
        }, etape);
        if (!fait) {
          manquante = etape.selecteur || `« ${etape.bouton} »`;
          break;
        }
        await attendre(etape.attente || 1800);
      }

      if (manquante) {
        rapport.push(`${m.fichier}\t${m.url}\tCIBLE INTROUVABLE ${manquante}`);
        continue;
      }
      await photographier(m.fichier);
      rapport.push(`${m.fichier}\t${m.url}\tmodale ouverte`);
    } catch (err) {
      rapport.push(`${m.fichier}\t${m.url}\tECHEC ${String(err).slice(0, 90)}`);
    }
  }

  console.log(rapport.join('\n'));
  const echecs = rapport.filter((l) => /ECHEC|REFUS RBAC|INTROUVABLE/.test(l));
  console.log('\n' + (ECRANS.length + MODALES.length + 1) + ' captures demandées · ' + echecs.length + ' à revoir');
  await navigateur.close();
})();

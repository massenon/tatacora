/* ---------------------------------------------------------------------------
 * LogiRestock — Manuel : RELEVÉ des points d'ancrage de la PWA.
 *
 * Sert à écrire `annoter.js` sur ce que la page rend RÉELLEMENT, et non sur ce
 * qu'on déduit d'un fichier Blade. La différence n'est pas théorique : le
 * 14/09/2026, un sélecteur deviné a produit une capture de l'alerte « Stock
 * critique » légendée « fiche des prix ».
 *
 * Ce script n'écrit aucune capture. Il imprime, écran par écran, les éléments
 * visibles porteurs d'un ancrage stable (id, wire:model, wire:click), avec
 * leur position et leur libellé, pour que les repères du manuel soient posés
 * sur les bons éléments.
 *
 * Exécution :
 *   TATACORA_LOGIN=... TATACORA_MDP=... PPTR_DIR=~/outils-pdf node inspecter.js
 * ------------------------------------------------------------------------- */

const path = require('path');
const MODULES = process.env.PPTR_DIR || path.join(__dirname, 'node_modules');
const puppeteer = require(path.join(MODULES, 'node_modules', 'puppeteer-core'));

const BASE = process.env.TATACORA_URL || 'http://127.0.0.1:8000';
const LOGIN = process.env.TATACORA_LOGIN;
const MDP = process.env.TATACORA_MDP;
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';

if (!LOGIN || !MDP) {
  console.error('TATACORA_LOGIN et TATACORA_MDP sont obligatoires.');
  process.exit(1);
}

/* Les écrans à relever, et les étapes qui ouvrent leur fenêtre. */
const CIBLES = [
  { nom: 'a-tableau-de-bord', url: '/pwa' },
  { nom: 'a-navigation', url: '/pwa' },
  { nom: 'a-pos', url: '/pwa/pos/comptant' },
  { nom: 'a-caisse', url: '/pwa/pos/comptant' },
  { nom: 'a-pos-heberges', url: '/pwa/pos/heberges' },
  { nom: 'a-fiche-prix', url: '/pwa/bar/carte' },
  { nom: 'a-etats', url: '/pwa/etats' },
  { nom: 'a-import', url: '/pwa/import-export' },
  {
    nom: 'a-reservation-modale',
    url: '/pwa/reservations',
    etapes: [{ bouton: 'Nouvelle réservation' }],
  },
  {
    nom: 'a-depense-modale',
    url: '/pwa/depenses',
    etapes: [{ bouton: 'Nouvelle dépense' }],
  },
  {
    nom: 'a-inventaire-ouvrir',
    url: '/pwa/stocks/inventaires',
    etapes: [
      { selecteur: '[role="tab"][wire\\:click*="\'inventaire\'"]' },
      { selecteur: '[wire\\:click^="ouvrirInventaire"]' },
    ],
  },
  {
    nom: 'a-inventaire-compter',
    url: '/pwa/stocks/inventaires',
    etapes: [
      { selecteur: '[role="tab"][wire\\:click*="\'inventaire\'"]' },
      { selecteur: '[wire\\:click^="ouvrirComptage"]' },
    ],
  },
];

const attendre = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const navigateur = await puppeteer.launch({
    executablePath: CHROME,
    headless: 'new',
    args: ['--no-sandbox', '--hide-scrollbars'],
    defaultViewport: { width: 1440, height: 1000, deviceScaleFactor: 1 },
  });
  const page = await navigateur.newPage();

  await page.goto(BASE + '/pwa/connexion', { waitUntil: 'networkidle0' });
  await page.type('#champ-identifiant', LOGIN, { delay: 10 });
  await page.type('#champ-motdepasse', MDP, { delay: 10 });
  await Promise.all([
    page.waitForNavigation({ waitUntil: 'networkidle0' }).catch(() => null),
    page.click('#formulaire-connexion button[type="submit"]'),
  ]);
  await attendre(1500);

  const congedier = async () => {
    for (let i = 0; i < 6; i++) {
      const ferme = await page.evaluate(() => {
        const cible = [...document.querySelectorAll('button')].find((b) =>
          /pris connaissance/i.test(b.innerText || ''),
        );
        if (!cible) return false;
        cible.click();
        return true;
      });
      if (!ferme) return;
      await attendre(600);
    }
  };
  await congedier();

  for (const c of CIBLES) {
    await page.goto(BASE + c.url, { waitUntil: 'networkidle0', timeout: 45000 });
    await attendre(1500);
    await congedier();

    for (const e of c.etapes || []) {
      await page.evaluate((etape) => {
        const cible = etape.selecteur
          ? document.querySelector(etape.selecteur)
          : [...document.querySelectorAll('button, a')].find((b) =>
              (b.innerText || '').trim().toLowerCase().includes(etape.bouton.toLowerCase()),
            );
        if (cible) cible.click();
      }, e);
      // Livewire rend la modale APRÈS son aller-retour serveur : 1,6 s
      // suffisait à la capture mais pas toujours au relevé, et une liste prise
      // trop tôt donne la page NUE — ce qui se lit comme « la modale ne s'est
      // pas ouverte », alors qu'elle s'ouvre une demi-seconde plus tard.
      await attendre(2600);
    }

    const elements = await page.evaluate(() => {
      const dedans = (r) => r.width > 12 && r.height > 8 && r.top < 1400 && r.left < 1440;
      const ancre = (el) => {
        if (el.id) return '#' + el.id;
        for (const a of el.attributes) {
          if (a.name.startsWith('wire:model') || a.name === 'wire:click') {
            return '[' + a.name.replace(/:/g, '\\:') + '="' + a.value + '"]';
          }
        }
        return null;
      };
      // Le CHÂSSIS (barre supérieure, menu latéral) est identique partout : le
      // laisser passer consommait la liste avant d'atteindre le contenu, et
      // c'est ce qui avait masqué les champs des modales.
      const chassis = (el) => el.closest('#shell-topbar, #shell-sidebar, #sidebar, #menu-profil') !== null;
      // Une modale est ce qui compte quand on en photographie une : on le DIT,
      // plutôt que de deviner à la position.
      // ⚠ Pas de `closest('[wire\\:ignore.self]')` : `.self` s'y lit comme une
      // CLASSE, le sélecteur est invalide et la page lève — le relevé entier
      // s'arrêtait là. On reconnaît une fenêtre à ce qui la rend visible : un
      // ancêtre positionné en `fixed` au-dessus de la page.
      const dansModale = (el) => {
        if (el.closest('[role="dialog"]')) return true;
        for (let n = el, i = 0; n && i < 8; n = n.parentElement, i++) {
          const s = getComputedStyle(n);
          if (s.position === 'fixed' && Number(s.zIndex || 0) >= 40) return true;
        }
        return false;
      };

      return [...document.querySelectorAll('input, select, textarea, button, a, section, aside, table, form')]
        .map((el) => ({ el, a: ancre(el), r: el.getBoundingClientRect() }))
        .filter((x) => x.a && dedans(x.r) && !chassis(x.el))
        .slice(0, 120)
        .map((x) => ({
          ancre: x.a,
          balise: x.el.tagName.toLowerCase(),
          modale: dansModale(x.el) ? 'MODALE' : '',
          texte: (x.el.innerText || x.el.value || x.el.getAttribute('aria-label') || '').trim().replace(/\s+/g, ' ').slice(0, 46),
          x: Math.round(x.r.left),
          y: Math.round(x.r.top),
          l: Math.round(x.r.width),
          h: Math.round(x.r.height),
        }));
    });

    const enModale = elements.filter((e) => e.modale).length;
    console.log(
      '\n===== ' + c.nom + '  (' + c.url + ') — ' + elements.length + ' ancre(s), ' + enModale + ' en modale =====',
    );
    for (const e of elements) {
      console.log(
        [e.ancre.slice(0, 60).padEnd(60), e.balise.padEnd(7), e.modale.padEnd(7), (e.x + ',' + e.y).padEnd(11), (e.l + 'x' + e.h).padEnd(10), e.texte].join(' '),
      );
    }
  }

  await navigateur.close();
})();

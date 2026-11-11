/* ---------------------------------------------------------------------------
 * LogiRestock — Manuel : les captures ANNOTÉES (pastilles rouges numérotées).
 *
 * ⚠ REPOINTÉ SUR LA PWA LE 14/09/2026. L'ancien script visait `prototype_v2/`
 * (archivé, PA-183) et ses sélecteurs — `#zone-salle`, `#btn-encaisser`,
 * `#bouton-nouvelle-reservation` — n'existent nulle part dans la PWA : les
 * repères se seraient posés sur du vide, et le manuel renverrait à des
 * pastilles absentes de l'image.
 *
 * Les ancrages viennent de `inspecter.js`, qui les RELÈVE sur la page rendue.
 * Ne pas les deviner : c'est ainsi qu'une capture de l'alerte « Stock
 * critique » s'est retrouvée légendée « fiche des prix ».
 *
 * Chaque repère porte le numéro de la liste `reperes` du chapitre : l'image et
 * le texte disent la même chose, ou l'un des deux ment.
 *
 * Exécution :
 *   TATACORA_LOGIN=... TATACORA_MDP=... PPTR_DIR=~/outils-pdf node annoter.js
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
  console.error('TATACORA_LOGIN et TATACORA_MDP sont obligatoires.');
  process.exit(1);
}

/* Les figures annotées.
 *
 * `sel`    — sélecteur CSS relevé sur la page ;
 * `texte`  — à défaut, le premier élément qui PORTE ce texte ;
 * `monte`  — remonte de N parents, pour cadrer une ZONE (colonne, tableau)
 *            plutôt que le bouton qui s'y trouve ;
 * `pos`    — où poser la pastille : gauche (défaut), droite, haut, bas.
 *
 * ⚠ Les figures d'inventaire ne sont pas annotées ici : « Lancer l'inventaire »
 * n'apparaît que si AUCUN inventaire ne court, et un script de manuel n'en
 * ouvre pas un pour la photo — ce serait écrire dans la base pour illustrer.
 */
const FIGURES = [
  {
    fichier: 'a-connexion',
    url: '/pwa/connexion',
    avantConnexion: true,
    reperes: [
      { n: 1, sel: '#champ-identifiant' },
      { n: 2, sel: '#champ-motdepasse' },
      { n: 3, sel: '#formulaire-connexion button[type="submit"]', pos: 'bas' },
    ],
  },
  {
    fichier: 'a-navigation',
    url: '/pwa',
    reperes: [
      { n: 1, sel: '#shell-topbar a[href$="/pwa"]', pos: 'bas' },
      { n: 2, sel: '#shell-topbar a[href*="/pwa/pos/comptant"]:not(#btn-caisse)', pos: 'bas' },
      { n: 3, sel: '#sidebar', pos: 'droite' },
    ],
  },
  {
    fichier: 'a-tableau-de-bord',
    url: '/pwa',
    reperes: [
      { n: 1, sel: '[wire\\:model\\.live="filtrePeriode"]', pos: 'bas' },
      { n: 2, sel: '[wire\\:click="ouvrirExport"]', pos: 'bas' },
      { n: 3, sel: '[wire\\:click="ouvrirReservationRapide"]', monte: 1, pos: 'bas' },
    ],
  },
  {
    fichier: 'a-pos',
    url: '/pwa/pos/comptant',
    reperes: [
      { n: 1, sel: '[wire\\:click*="comptoirChoisi"]', monte: 2, pos: 'droite' },
      { n: 2, sel: '[wire\\:click^="ajouterAuPanier"]', monte: 2, pos: 'haut' },
      { n: 3, sel: '[wire\\:click="viderPanier"]', monte: 3 },
      { n: 4, sel: '#mode-paiement' },
      // À gauche, pas dessous : « Encaisser » ferme la colonne du panier, et
      // une pastille posée sous lui tombe hors du cliché.
      { n: 5, sel: '[wire\\:click="encaisser"]' },
    ],
  },
  {
    fichier: 'a-caisse',
    url: '/pwa/pos/comptant',
    reperes: [
      { n: 1, sel: '[wire\\:click="ouvrirJournalDuJour"]', monte: 2, pos: 'bas' },
      { n: 2, sel: '[wire\\:click="ouvrirJournalDuJour"]', pos: 'bas' },
    ],
  },
  {
    fichier: 'a-pos-heberges',
    url: '/pwa/pos/heberges',
    reperes: [
      { n: 1, sel: '[wire\\:click^="$set(\'selectedReservationId\'"]', monte: 1, pos: 'haut' },
      { n: 2, sel: '[wire\\:click^="ajouterAuPanier"]', monte: 2, pos: 'haut' },
      { n: 3, sel: '#remise-type-sejour', monte: 3 },
    ],
  },
  {
    fichier: 'a-fiche-prix',
    url: '/pwa/bar/carte',
    reperes: [
      { n: 1, sel: '[wire\\:click="imprimerFichePrix"]', pos: 'bas' },
      { n: 2, sel: '[wire\\:click="$set(\'onglet\', \'couverture\')"]', pos: 'bas' },
    ],
  },
  {
    fichier: 'a-etats',
    url: '/pwa/etats',
    reperes: [
      { n: 1, sel: '[wire\\:model\\.live\\.debounce\\.300ms="recherche"]', pos: 'droite' },
      { n: 2, sel: '[wire\\:click="$set(\'module\', \'\')"]', monte: 1, pos: 'droite' },
      { n: 3, sel: '[wire\\:click="$set(\'etat\', \'stocks\')"]', monte: 1, pos: 'droite' },
      { n: 4, texte: 'Choisissez un état dans le catalogue', monte: 1, pos: 'haut' },
    ],
  },
  {
    fichier: 'a-import',
    url: '/pwa/import-export',
    reperes: [
      { n: 1, sel: '[wire\\:model\\.live="moduleImport"]' },
      { n: 2, sel: '[wire\\:click="telechargerModele"]', pos: 'bas' },
      { n: 3, texte: 'Glissez votre fichier ici', monte: 1 },
    ],
  },
  {
    fichier: 'a-reservation-modale',
    url: '/pwa/reservations',
    etapes: [{ texte: 'Nouvelle réservation' }],
    // La fiche porte cinq services et un récapitulatif : elle dépasse le
    // plafond commun, et les repères 5 et 6 sortaient du cadre.
    hauteurMax: 2200,
    reperes: [
      { n: 1, sel: '[wire\\:model="rClientId"]' },
      { n: 2, sel: '[wire\\:model\\.live="rDateArrivee"]' },
      { n: 3, sel: '[wire\\:model\\.live="rDateDepart"]', pos: 'droite' },
      { n: 4, sel: '[wire\\:click="basculerServiceFiche(\'bar\')"]', monte: 1, pos: 'haut' },
      { n: 5, sel: '[wire\\:model\\.live="rAcompte"]' },
      // À gauche, pas dessous : « Enregistrer la réservation » ferme la
      // fenêtre, et une pastille posée sous lui sort du cliché — même défaut
      // que le repère 5 du point de vente.
      { n: 6, sel: 'button[form="formulaire-reservation"]' },
    ],
  },
  {
    fichier: 'a-depense-modale',
    url: '/pwa/depenses',
    etapes: [{ texte: 'Nouvelle Dépense' }],
    reperes: [
      { n: 1, sel: '[wire\\:model="dateTransaction"]' },
      { n: 2, sel: '[wire\\:model="libelle"]', pos: 'droite' },
      { n: 3, sel: '[wire\\:click="ajouterLigneDepense"]', monte: 1 },
      { n: 4, sel: '[wire\\:model="tresorerieCode"]' },
      { n: 5, texte: 'Enregistrer la dépense', pos: 'bas' },
    ],
  },
];

const attendre = (ms) => new Promise((r) => setTimeout(r, ms));

/* Reprendre UNE figure sans refaire les dix autres :
 *   FIGURES=a-reservation-modale,a-depense-modale node annoter.js */
const FILTRE = (process.env.FIGURES || '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);
const retenu = (f) => FILTRE.length === 0 || FILTRE.includes(f);

/* Posée DANS la page : cadre rouge + pastille numérotée. Rend la liste des
 * repères introuvables — une pastille absente doit se voir au journal, pas se
 * découvrir à l'impression. */
function poser(reperes) {
  document.querySelectorAll('.rep-annot').forEach((e) => e.remove());
  const manquants = [];

  for (const c of reperes) {
    let el = null;
    if (c.sel) {
      try {
        el = document.querySelector(c.sel);
      } catch (e) {
        manquants.push(c.n + ':' + c.sel + ' (sélecteur invalide)');
        continue;
      }
    } else if (c.texte) {
      // Visible AU SENS DE L'IMAGE : un élément présent mais hors du cadre
      // capturé donnerait une pastille posée nulle part. Le 14/09/2026, le
      // bouton « Enregistrer la dépense » d'une modale haute est sorti du
      // cliché, et le repère 5 pointait dans le vide.
      const visible = (n) => {
        const r = n.getBoundingClientRect();
        return n.offsetParent !== null && r.width > 8 && r.height > 8 && r.top >= 0;
      };
      const porte = (n) => (n.innerText || '').trim().includes(c.texte);
      // ⚠ Le CONTENEUR porte le texte de son bouton. Sans cette préférence, le
      // repère « Enregistrer la dépense » a encadré la fenêtre ENTIÈRE le
      // 14/09/2026 : un cadre rouge autour de tout, et la pastille au dehors.
      // On vise le bouton ; à défaut, le plus PETIT élément qui porte le texte.
      const boutons = [...document.querySelectorAll('button, a')].filter((n) => visible(n) && porte(n));
      if (boutons.length) {
        el = boutons[0];
      } else {
        const autres = [...document.querySelectorAll('div, p, span, label')]
          .filter((n) => visible(n) && porte(n))
          .sort((a, b) => {
            const ra = a.getBoundingClientRect();
            const rb = b.getBoundingClientRect();
            return ra.width * ra.height - rb.width * rb.height;
          });
        el = autres[0];
      }
    }
    for (let i = 0; el && i < (c.monte || 0); i++) el = el.parentElement;

    if (!el) {
      manquants.push(c.n + ':' + (c.sel || c.texte));
      continue;
    }
    const r = el.getBoundingClientRect();
    if (r.width === 0 && r.height === 0) {
      manquants.push(c.n + ':' + (c.sel || c.texte) + ' (invisible)');
      continue;
    }

    const cadre = document.createElement('div');
    cadre.className = 'rep-annot';
    Object.assign(cadre.style, {
      position: 'fixed',
      left: r.left - 4 + 'px',
      top: r.top - 4 + 'px',
      width: r.width + 8 + 'px',
      height: r.height + 8 + 'px',
      border: '3px solid #DC2626',
      borderRadius: '10px',
      zIndex: 2147483000,
      pointerEvents: 'none',
      boxShadow: '0 0 0 3px rgba(220,38,38,.15)',
    });
    document.body.appendChild(cadre);

    const pos = c.pos || 'gauche';
    let x = r.left - 42;
    let y = r.top - 14;
    if (pos === 'droite') x = r.right + 12;
    if (pos === 'haut') {
      x = r.left - 14;
      y = r.top - 42;
    }
    if (pos === 'bas') {
      x = r.left - 14;
      y = r.bottom + 12;
    }
    if (x < 4) x = r.left + 8;
    if (y < 4) y = r.top + 8;

    const badge = document.createElement('div');
    badge.className = 'rep-annot';
    badge.textContent = String(c.n);
    Object.assign(badge.style, {
      position: 'fixed',
      left: x + 'px',
      top: y + 'px',
      width: '30px',
      height: '30px',
      borderRadius: '50%',
      background: '#DC2626',
      color: '#fff',
      font: '700 16px/30px Arial, sans-serif',
      textAlign: 'center',
      zIndex: 2147483001,
      pointerEvents: 'none',
      boxShadow: '0 2px 6px rgba(0,0,0,.35)',
    });
    document.body.appendChild(badge);
  }

  return manquants;
}

(async () => {
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

  const journal = [];

  // 1. La figure de l'écran de connexion se prend AVANT la session.
  const avant = FIGURES.filter((f) => f.avantConnexion && retenu(f.fichier));
  for (const f of avant) {
    await page.goto(BASE + f.url, { waitUntil: 'networkidle0' });
    await attendre(900);
    const manquants = await page.evaluate(poser, f.reperes);
    await attendre(250);
    await page.screenshot({
      path: path.join(SORTIE, f.fichier + '.png'),
      clip: { x: 0, y: 0, width: 1440, height: 900 },
    });
    journal.push(f.fichier + ' -> ' + (manquants.length ? 'MANQUE ' + manquants.join(', ') : 'ok'));
  }

  // 2. Session réelle.
  //
  // ⚠ La pause après le `goto` n'est pas décorative : le formulaire est un
  // composant Livewire à liaison DIFFÉRÉE (`wire:model`, sans `.live`).
  // Taper avant qu'il ait démarré remplit le DOM sans que le composant en
  // sache rien, et la soumission part avec des identifiants VIDES — le
  // serveur refuse, et le script accuse le mot de passe.
  await page.goto(BASE + '/pwa/connexion', { waitUntil: 'networkidle0' });
  await attendre(1200);
  await page.type('#champ-identifiant', LOGIN, { delay: 12 });
  await page.type('#champ-motdepasse', MDP, { delay: 12 });
  await Promise.all([
    page.waitForNavigation({ waitUntil: 'networkidle0' }).catch(() => null),
    page.click('#formulaire-connexion button[type="submit"]'),
  ]);
  await attendre(1800);
  if (page.url().includes('/connexion')) {
    // Le message de l'écran distingue un refus d'identifiants d'une limitation
    // de cadence — deux causes, deux corrections.
    const message = await page.evaluate(() =>
      (document.body.innerText.match(/.{0,120}(incorrect|tentative|patient|verrou).{0,120}/i) || [''])[0]
        .trim()
        .replace(/\s+/g, ' '),
    );
    console.error('ÉCHEC DE CONNEXION — aucune annotation ne serait valable.');
    if (message) console.error('  écran : ' + message);
    await navigateur.close();
    process.exit(2);
  }
  await congedier();

  // 3. Les autres figures.
  for (const f of FIGURES.filter((x) => !x.avantConnexion)) {
    if (!retenu(f.fichier)) continue;
    try {
      await page.goto(BASE + f.url, { waitUntil: 'networkidle0', timeout: 45000 });
      await attendre(1600);
      await congedier();

      for (const e of f.etapes || []) {
        // ⚠ Le bouton doit être VISIBLE : le panneau d'accès rapide (Alt + A)
        // porte lui aussi « Nouvelle réservation » dans le DOM, masqué. En
        // cliquer un invisible ne fait rien, et l'annotation se posait alors
        // sur une page sans sa fenêtre — les six repères manquaient d'un coup.
        const clique = await page.evaluate((etape) => {
          const visible = (n) => {
            const r = n.getBoundingClientRect();
            return n.offsetParent !== null && r.width > 8 && r.height > 8;
          };
          const cible = [...document.querySelectorAll('button, a')]
            .filter(visible)
            .find((b) => (b.innerText || '').trim().toLowerCase().includes(etape.texte.toLowerCase()));
          if (!cible) return false;
          cible.click();
          return true;
        }, e);
        if (!clique) throw new Error('bouton visible introuvable : ' + e.texte);

        // Puis ATTENDRE la fenêtre, au lieu d'espérer qu'une pause fixe suffise :
        // Livewire la rend après son aller-retour serveur.
        await page
          .waitForFunction(
            () =>
              [...document.querySelectorAll('[role="dialog"], form')].some((n) => {
                const r = n.getBoundingClientRect();
                return r.width > 300 && r.height > 200 && getComputedStyle(n).visibility !== 'hidden';
              }),
            { timeout: 12000 },
          )
          .catch(() => {
            throw new Error('la fenêtre ne s’est pas ouverte après « ' + e.texte + ' »');
          });
        await attendre(900);
      }

      // ⚠ Une fenêtre est `position: fixed` : sa hauteur n'entre PAS dans
      // `scrollHeight`. Relever le plafond n'y changeait donc rien — la
      // fenêtre « Nouvelle réservation » restait coupée sous le champ
      // Acompte, et le script annonçait « ok » parce qu'il avait TROUVÉ ses
      // six repères. Trouver n'est pas montrer : on mesure le bas réel de la
      // fenêtre, pas celui du document.
      // ⚠ Mesurer le bas VISIBLE d'une fenêtre ne suffit pas : son cadre tient
      // dans l'écran pendant que son CONTENU déborde d'un conteneur qui
      // défile. Le 14/09/2026, la fiche « Nouvelle réservation » restait
      // coupée sous l'Acompte alors que la hauteur avait bien augmenté — de
      // 48 px, c'est-à-dire du cadre, pas du formulaire. On prend donc la plus
      // grande des deux : le bas du cadre, et le bas de ce qu'il contient
      // réellement (`scrollHeight` du conteneur).
      const hauteurUtile = await page.evaluate(() => {
        let bas = document.documentElement.scrollHeight;
        for (const n of document.querySelectorAll('div, form, section')) {
          const s = getComputedStyle(n);
          if (s.position !== 'fixed' || s.visibility === 'hidden') continue;
          const r = n.getBoundingClientRect();
          if (r.width <= 300 || r.height <= 200) continue;
          bas = Math.max(bas, Math.ceil(r.bottom) + 24);
          for (const interne of n.querySelectorAll('*')) {
            const ri = interne.getBoundingClientRect();
            if (ri.width > 200 && interne.scrollHeight > interne.clientHeight + 8) {
              bas = Math.max(bas, Math.ceil(ri.top + interne.scrollHeight) + 24);
            }
          }
        }
        return bas;
      });
      let hauteur = Math.min(Math.max(hauteurUtile, 700), f.hauteurMax || 1500);
      await page.setViewport({ width: 1440, height: hauteur, deviceScaleFactor: 2 });
      await attendre(500);

      // ⚠ Une fenêtre est plafonnée à une fraction de la hauteur d'écran
      // (`max-h-[90vh]`) : agrandir le cliché agrandit le plafond, pas son
      // contenu, et le pied de la fenêtre (le bouton « Enregistrer… ») restait
      // dans la zone qui DÉFILE, à moitié coupé — constaté le 09/11/2026 à
      // l'œil sur la figure « Nouvelle réservation ». On mesure ce qui déborde
      // encore et on agrandit jusqu'à ce que plus rien ne défile.
      for (let tour = 0; tour < 5; tour++) {
        const deborde = await page.evaluate(() => {
          let pire = 0;
          for (const n of document.querySelectorAll('div, form, section')) {
            const s = getComputedStyle(n);
            if (s.position !== 'fixed' || s.visibility === 'hidden') continue;
            const r = n.getBoundingClientRect();
            if (r.width <= 300 || r.height <= 200) continue;
            for (const interne of n.querySelectorAll('*')) {
              const ri = interne.getBoundingClientRect();
              if (ri.width > 200 && interne.scrollHeight > interne.clientHeight + 8) {
                pire = Math.max(pire, interne.scrollHeight - interne.clientHeight);
              }
            }
          }
          return pire;
        });
        if (deborde <= 8 || hauteur >= (f.hauteurMax || 1500)) break;
        hauteur = Math.min(hauteur + Math.ceil(deborde / 0.85) + 8, f.hauteurMax || 1500);
        await page.setViewport({ width: 1440, height: hauteur, deviceScaleFactor: 2 });
        await attendre(500);
      }

      const manquants = await page.evaluate(poser, f.reperes);
      await attendre(250);
      await page.screenshot({
        path: path.join(SORTIE, f.fichier + '.png'),
        clip: { x: 0, y: 0, width: 1440, height: hauteur },
      });
      await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 2 });

      journal.push(f.fichier + ' -> ' + (manquants.length ? 'MANQUE ' + manquants.join(', ') : 'ok'));
    } catch (err) {
      journal.push(f.fichier + ' -> ECHEC ' + String(err).slice(0, 90));
    }
  }

  console.log(journal.join('\n'));
  const aRevoir = journal.filter((l) => /MANQUE|ECHEC/.test(l)).length;
  console.log('\n' + journal.length + ' figure(s) annotée(s) · ' + aRevoir + ' à revoir');
  await navigateur.close();
})();

/* ---------------------------------------------------------------------------
 * LogiRestock — Manuel d'utilisation : captures des ÉCRANS NOUVEAUX de la PWA
 * (novembre 2026) — proformas, facturation normalisée, postes & appairage,
 * synchronisation, comptes utilisateurs, mot de passe, exercices et clôture,
 * import, congés, correspondance des comptes, etc.
 *
 * Complète `capturer.js` (qui rejoue les 63 figures historiques). Même
 * principe : session réelle, 1440 px, facteur 2, et un échec BRUYANT — une
 * étape dont la cible n'existe pas arrête la figure au lieu de photographier
 * l'écran sans sa fenêtre.
 *
 * ⚠ RÈGLES DE SÉCURITÉ DE CE SCRIPT
 *   - il n'ouvre jamais la saisie du jeton e-MECeF, ne clique ni « Normaliser »,
 *     ni « Tester la connexion », ni aucun bouton qui ÉCRIT dans la base ou qui
 *     appelle un service externe : on photographie des écrans, on ne joue pas
 *     de gestes métier (sauf les deux « préparations » ci-dessous, déclarées) ;
 *   - préparations déclarées (`preparer`) : « Détecter maintenant »
 *     (notifications) et « Générer une sauvegarde de la base » — elles ne
 *     servent qu'à ce que l'écran ait un contenu à montrer, sur une base de
 *     capture jetable ;
 *   - aucun identifiant, aucun mot de passe n'est écrit ici : les comptes
 *     viennent de l'environnement (TATACORA_LOGIN / TATACORA_MDP, et pour la
 *     figure du changement obligatoire TATACORA_LOGIN_ESSAI / TATACORA_MDP_ESSAI).
 *
 * Exécution :
 *   TATACORA_LOGIN=... TATACORA_MDP=... PPTR_DIR=~/outils-pdf node capturer-nouveautes.js
 *   CAPTURES=pwa-proformas-liste,x-sauvegardes node capturer-nouveautes.js   (reprise partielle)
 * ------------------------------------------------------------------------- */

const fs = require('fs');
const path = require('path');
const MODULES = process.env.PPTR_DIR || path.join(__dirname, 'node_modules');
const puppeteer = require(path.join(MODULES, 'node_modules', 'puppeteer-core'));

const BASE = process.env.TATACORA_URL || 'http://127.0.0.1:8000';
const LOGIN = process.env.TATACORA_LOGIN;
const MDP = process.env.TATACORA_MDP;
const LOGIN_ESSAI = process.env.TATACORA_LOGIN_ESSAI;
const MDP_ESSAI = process.env.TATACORA_MDP_ESSAI;
const SORTIE = path.join(__dirname, 'captures');
const CHROME = process.env.CHROME_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : 'C:/Program Files/Google/Chrome/Application/chrome.exe');

if (!LOGIN || !MDP) {
  console.error('TATACORA_LOGIN et TATACORA_MDP sont obligatoires.');
  process.exit(1);
}

/* Étapes : { bouton } texte d'un bouton/lien/onglet VISIBLE · { selecteur }
 * · { saisir: [selecteur, valeur] } · { choisir: [selecteur, valeur] }
 * · { attente } pause seule.  `cadre` : ne photographier que cet élément. */
const FIGURES = [
  // ---- Proformas ----------------------------------------------------------
  { fichier: 'pwa-proformas-liste', url: '/pwa/facturation/proformas' },
  {
    fichier: 'pwa-proforma-formulaire',
    url: '/pwa/facturation/proformas',
    etapes: [
      { bouton: 'Nouvelle facture proforma', attente: 2200 },
      { saisir: ['[wire\\:model="clientNom"]', 'Client Exemple'] },
      { saisir: ['[wire\\:model="clientTelephone"]', '01 20 30 40 50'] },
      { saisir: ['[wire\\:model="objet"]', 'Séjour de deux nuits — chambre double'] },
      { saisir: ['[wire\\:model="lignes.0.designation"]', 'Chambre double — nuitée'] },
      { saisir: ['[wire\\:model="lignes.0.quantite"]', '2'] },
      { saisir: ['[wire\\:model="lignes.0.prix_unitaire"]', '30000'] },
    ],
  },
  // ---- Facturation normalisée ---------------------------------------------
  { fichier: 'x-parametres-mecef', url: '/pwa/parametres', cadre: '#mecef-jeton', cadreMonte: 2, cadreDe: 'Facturation normalisée' },
  {
    fichier: 'pwa-facture-normaliser',
    url: '/pwa/facturation',
    preparer: 'mode-emecef',
  },
  { fichier: 'pwa-parametres-mecef-emecef', url: '/pwa/parametres', cadre: '#mecef-jeton', cadreMonte: 2, cadreDe: 'Facturation normalisée', preparer: 'mode-emecef' },
  // ---- Postes, appairage, synchronisation ---------------------------------
  { fichier: 'pwa-postes-appairage', url: '/pwa/synchronisation-postes' },
  { fichier: 'pwa-synchronisation-reception', url: '/pwa/synchronisation-postes?onglet=reception' },
  { fichier: 'pwa-synchronisation-envoi', url: '/pwa/synchronisation-postes?onglet=envoi' },
  { fichier: 'pwa-synchronisation-fenetre', url: '/pwa', etapes: [{ selecteur: '#shell-topbar [wire\\:click*="synchro"], #shell-topbar button[aria-label*="ynchronisation"]', attente: 1800 }] },
  // ---- Profil, comptes, mots de passe -------------------------------------
  { fichier: 'pwa-mon-profil-mot-de-passe', url: '/pwa/mon-profil', etapes: [{ selecteur: '[wire\\:click="ouvrirFormulaireMotDePasse"]', attente: 1800 }] },
  { fichier: 'pwa-mon-profil-code-secours', url: '/pwa/mon-profil', etapes: [{ selecteur: '[wire\\:click="ouvrirFormulaireCodeSecours"]', attente: 1800 }] },
  // Les trois figures « comptes » se prennent en SUPER ADMINISTRATEUR (seul à voir « Supprimer ») : TATACORA_SUPER=1 avec ses identifiants.
  { fichier: 'pwa-comptes-utilisateurs', super: true, url: '/pwa/comptes-utilisateurs' },
  { fichier: 'pwa-comptes-reinitialisation', super: true, url: '/pwa/comptes-utilisateurs', etapes: [{ selecteur: '[wire\\:click^="ouvrirReinitialisation"]', attente: 1800 }] },
  { fichier: 'pwa-comptes-suppression', super: true, url: '/pwa/comptes-utilisateurs', etapes: [{ selecteur: '[wire\\:click^="ouvrirSuppression"]', attente: 1800 }] },
  // ---- Exercices et clôture SYSCOHADA -------------------------------------
  { fichier: 'x-compta-clotures', url: '/pwa/comptabilite?onglet=clotures' },
  { fichier: 'x-compta-immobilisations', url: '/pwa/comptabilite?onglet=immo' },
  { fichier: 'x-compta-immobilisations-nouvelle', url: '/pwa/comptabilite?onglet=immo', etapes: [{ selecteur: '[wire\\:click="ouvrirNouvelleImmo"]', attente: 1800 }] },
  { fichier: 'x-compta-correspondance', url: '/pwa/comptabilite/correspondance-comptes' },
  { fichier: 'x-compta-correspondance-modale', url: '/pwa/comptabilite/correspondance-comptes', etapes: [{ selecteur: '[wire\\:click^="ouvrirEditionRole"]', attente: 1800 }] },
  { fichier: 'x-compta-bilan-n1', url: '/pwa/comptabilite?onglet=bilan' },
  // ---- Import & Export ----------------------------------------------------
  {
    fichier: 'pwa-import-modeles',
    url: '/pwa/import-export',
    etapes: [{ choisir: ['[wire\\:model\\.live="moduleImport"]', 'premier'] }],
  },
  { fichier: 'x-sauvegardes', url: '/pwa/import-export', preparer: 'sauvegarde', etapes: [{ bouton: 'Sauvegardes de la base', attente: 1800 }] },
  { fichier: 'x-reinitialiser', url: '/pwa/import-export', etapes: [{ bouton: 'Réinitialiser les données de test', attente: 1800 }] },
  {
    fichier: 'x-reinitialiser-modale',
    url: '/pwa/import-export',
    etapes: [{ bouton: 'Réinitialiser les données de test', attente: 1800 }, { selecteur: '[wire\\:click="ouvrirReinitialisation"]', attente: 1800 }],
  },
  // ---- Approvisionnement, locations, tourisme, RH -------------------------
  { fichier: 'x-appro-reception', url: '/pwa/achats/approvisionnement', etapes: [{ bouton: 'Commandes', attente: 1800 }, { bouton: 'Réceptionner', attente: 2000 }, { choisir: ['#r-point', 'Cuisine'] }] },
  // « Régler » n'existe que sur une commande RÉCEPTIONNÉE : la préparation réceptionne la première commande envoyée (une seule fois).
  { fichier: 'x-appro-reglement', url: '/pwa/achats/approvisionnement', preparer: 'reception', etapes: [{ bouton: 'Commandes', attente: 1800 }, { bouton: 'Régler', attente: 2000 }] },
  { fichier: 'x-location-contrat', url: '/pwa/vehicules', etapes: [{ bouton: '+ Contrat', attente: 2000 }] },
  { fichier: 'x-tourisme-reservation', url: '/pwa/tourisme', etapes: [{ bouton: '+ Réservation', attente: 2000 }] },
  // L'onglet « Congés » : les demandes en attente, avec Valider / Refuser.
  { fichier: 'x-conges-plannings', url: '/pwa/rh/conges-plannings', etapes: [{ selecteur: '[wire\\:click="$set(\'onglet\', \'conges\')"]', attente: 1800 }] },
  { fichier: 'x-conges-creneau', url: '/pwa/rh/conges-plannings', etapes: [{ selecteur: '[wire\\:click="ouvrirPlanification"]', attente: 1800 }] },
  // ---- Notifications, e-mail ----------------------------------------------
  // x-notifications-envoyer : la base de démonstration ne produit aucun événement à notifier (« Détecter maintenant » répond « Aucun nouvel événement »), donc aucune file à photographier — voir CAPTURES_A_PRENDRE_CHAP7-14.md.
  { fichier: 'x-parametres-email', url: '/pwa/parametres', etapes: [{ bouton: 'Email (SMTP)', attente: 1500 }] },
  // ---- Exercice consulté ---------------------------------------------------
  { fichier: 'x-selecteur-exercice', url: '/pwa', etapes: [{ choisir: ['#choix-exercice', '2025'] }], cadre: '#shell-topbar', cadreMarge: 0 },
  { fichier: 'x-selecteur-exercice-page', url: '/pwa/comptabilite?onglet=clotures', etapes: [{ choisir: ['#choix-exercice', '2025'] }] },
  // ---- Divers --------------------------------------------------------------
  { fichier: 'pwa-hors-connexion', url: '/pwa/hors-connexion', sansSession: true },
  { fichier: 'pwa-mot-de-passe-oublie', url: '/pwa/connexion', avantConnexion: true, etapes: [{ bouton: 'Mot de passe oublié', attente: 800 }] },
  { fichier: 'pwa-code-secours-connexion', url: '/pwa/mot-de-passe-administrateur-perdu', avantConnexion: true },
];

const attendre = (ms) => new Promise((r) => setTimeout(r, ms));
const FILTRE = (process.env.CAPTURES || '').split(',').map((s) => s.trim()).filter(Boolean);
const SUPER = !!process.env.TATACORA_SUPER;
const retenu = (f) => FILTRE.length === 0 || FILTRE.includes(f);
const dupe = (f) => (SUPER ? !!f.super : !f.super);

const { execSync } = require('child_process');
const API = process.env.TATACORA_API_DIR || path.join(__dirname, '..', 'tatacora-api');
const BASE_CAPT = process.env.CAPT_DB || 'tatacora_capt';
/* Bascule du mode de facturation, sur la base de capture UNIQUEMENT : sans
 * elle le bouton « Normaliser » n'apparaît pas (mode « désactivé » = pas de
 * ligne de réglage). Aucun jeton n'est posé : le bouton se voit, il ne se
 * clique pas. Le réglage est mis en cache : on le vide. */
const modeFacturation = (mode) => {
  const sql =
    mode === 'desactive'
      ? "delete from parametres_systeme where cle='facturation_mode'"
      : `delete from parametres_systeme where cle='facturation_mode'; insert into parametres_systeme (id,cle,valeur,description,created_at,updated_at) values (uuid(),'facturation_mode','${mode}','Mode de facturation (capture)',now(),now())`;
  execSync(`mysql -uroot ${BASE_CAPT} -e "${sql}"`, { stdio: 'ignore' });
  execSync('php artisan cache:clear', { cwd: API, stdio: 'ignore', env: { ...process.env, APP_ENV: 'local' } });
};

(async () => {
  fs.mkdirSync(SORTIE, { recursive: true });
  const navigateur = await puppeteer.launch({
    executablePath: CHROME,
    headless: 'new',
    env: { ...process.env, LANGUAGE: 'fr', LANG: 'fr_FR.UTF-8' },
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--hide-scrollbars', '--lang=fr'],
    defaultViewport: { width: 1440, height: 900, deviceScaleFactor: 2 },
  });
  const page = await navigateur.newPage();
  await page.setExtraHTTPHeaders({ 'Accept-Language': 'fr-FR,fr;q=0.9' });
  page.on('pageerror', (e) => console.log('  [erreur page]', String(e).slice(0, 120)));

  const mesurerHauteur = () =>
    page.evaluate(() => {
      let bas = document.documentElement.scrollHeight;
      for (const n of document.querySelectorAll('main, [class*="overflow-y-auto"]')) {
        const r = n.getBoundingClientRect();
        if (r.width < 600) continue;
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

  const photographier = async (f) => {
    const plafond = f.cadre ? 3200 : 1500;
    let hauteur = Math.min(Math.max(await mesurerHauteur(), 700), plafond);
    await page.setViewport({ width: 1440, height: hauteur, deviceScaleFactor: 2 });
    await attendre(500);
    for (let tour = 0; tour < 5; tour++) {
      const d = await deborde();
      if (d <= 8 || hauteur >= plafond) break;
      hauteur = Math.min(hauteur + Math.ceil(d / 0.85) + 8, plafond);
      await page.setViewport({ width: 1440, height: hauteur, deviceScaleFactor: 2 });
      await attendre(500);
    }
    await attendre(300);
    const fichier = path.join(SORTIE, f.fichier + '.png');
    if (f.cadre) {
      const zone = await page.evaluate(
        (sel, monte, haut, marge, de) => {
          let el = document.querySelector(sel);
          if (!el) return null;
          el.scrollIntoView({ block: 'start' });
          for (let i = 0; i < (monte || 0); i++) el = el.parentElement;
          const r = el.getBoundingClientRect();
          if (de) {
            // De l'intertitre `de` jusqu'au bas du bloc : la rubrique, pas la page.
            const titre = [...document.querySelectorAll('h2, h3')].find((h) => (h.innerText || '').includes(de));
            if (!titre) return null;
            const rt = titre.getBoundingClientRect();
            const m0 = marge === undefined ? 16 : marge;
            return { x: Math.max(rt.left - m0, 0), y: Math.max(rt.top - m0, 0), w: Math.min(r.right - rt.left + 2 * m0, 1440), h: r.bottom - rt.top + 2 * m0 };
          }
          const m = marge === undefined ? 16 : marge;
          return { x: Math.max(r.left - m, 0), y: Math.max(r.top - (haut || 0) - m, 0), w: Math.min(r.width + 2 * m, 1440), h: r.height + (haut || 0) + 2 * m };
        },
        f.cadre, f.cadreMonte, f.cadreHaut, f.cadreMarge, f.cadreDe,
      );
      if (!zone) throw new Error('CADRE INTROUVABLE ' + f.cadre);
      await attendre(300);
      await page.screenshot({ path: fichier, clip: { x: zone.x, y: zone.y, width: zone.w, height: zone.h } });
    } else {
      await page.screenshot({ path: fichier, clip: { x: 0, y: 0, width: 1440, height: hauteur } });
    }
    await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 2 });
  };

  const congedier = async () => {
    for (let i = 0; i < 6; i++) {
      const ferme = await page.evaluate(() => {
        const cible = [...document.querySelectorAll('button')].find((b) => /pris connaissance/i.test(b.innerText || ''));
        if (!cible) return false;
        cible.click();
        return true;
      });
      if (!ferme) return;
      await attendre(700);
    }
  };

  const jouer = async (etape) => {
    if (etape.attente && Object.keys(etape).length === 1) return attendre(etape.attente);
    if (etape.saisir) {
      const [sel, val] = etape.saisir;
      await page.waitForSelector(sel, { timeout: 8000 });
      await page.focus(sel);
      await page.keyboard.down('Control');
      await page.keyboard.press('KeyA');
      await page.keyboard.up('Control');
      await page.keyboard.press('Backspace');
      await page.type(sel, val, { delay: 8 });
      await attendre(400);
      return;
    }
    if (etape.choisir) {
      const [sel, val] = etape.choisir;
      await page.waitForSelector(sel, { timeout: 8000 });
      const valeur = await page.evaluate(
        (s, v) => {
          const el = document.querySelector(s);
          const options = [...el.options].filter((o) => o.value !== '');
          const o = v === 'premier' ? options[0] : options.find((x) => x.textContent.includes(v));
          return o ? o.value : null;
        },
        sel, val,
      );
      if (valeur === null) throw new Error('OPTION INTROUVABLE ' + val);
      await page.select(sel, valeur);
      await attendre(etape.attente || 2200);
      return;
    }
    const fait = await page.evaluate((et) => {
      const visible = (n) => n.offsetParent !== null && n.getBoundingClientRect().width > 4;
      let cible = null;
      if (et.selecteur) {
        cible = [...document.querySelectorAll(et.selecteur)].find(visible) || null;
      } else {
        const bas = et.bouton.toLowerCase();
        cible = [...document.querySelectorAll('button, a, [role="tab"]')]
          .filter(visible)
          .find((b) => (b.innerText || '').trim().toLowerCase().includes(bas)) || null;
      }
      if (!cible) return false;
      cible.click();
      return true;
    }, etape);
    if (!fait) throw new Error('CIBLE INTROUVABLE ' + (etape.selecteur || etape.bouton));
    await attendre(etape.attente || 1600);
  };

  const rapport = [];

  const faire = async (f) => {
    if (f.preparer === 'mode-emecef') modeFacturation('emecef');
    try {
      await page.goto(BASE + f.url, { waitUntil: 'networkidle0', timeout: 45000 });
      await attendre(1600);
      if (!f.avantConnexion && !f.sansSession) await congedier();
      if (f.preparer === 'reception') {
        await jouer({ bouton: 'Commandes', attente: 1500 });
        const dispo = await page.evaluate(() => [...document.querySelectorAll('button')].some((b) => b.offsetParent !== null && /réceptionner/i.test(b.innerText || '')));
        if (dispo) {
          await jouer({ bouton: 'Réceptionner', attente: 2000 });
          await jouer({ choisir: ['#r-point', 'Cuisine'] });
          await jouer({ bouton: 'Valider la réception', attente: 3500 });
          await page.goto(BASE + f.url, { waitUntil: 'networkidle0', timeout: 45000 });
          await attendre(1500);
        }
      }
      if (f.preparer === 'sauvegarde') {
        await jouer({ bouton: 'Sauvegardes de la base', attente: 1500 });
        await jouer({ selecteur: '[wire\\:click="genererSauvegarde"]', attente: 6000 });
      }
      for (const e of f.etapes || []) await jouer(e);
      const etat = await page.evaluate(() => ({
        titre: ((document.querySelector('h1') || {}).textContent || document.title).trim().slice(0, 40),
        refus: /403|Accès refusé|Cette action n’est pas autorisée|Page introuvable|Server Error/.test(document.body.innerText.slice(0, 300)),
      }));
      await photographier(f);
      rapport.push(`${f.fichier}\t${f.url}\t${etat.refus ? 'REFUS/ERREUR\t' : ''}${etat.titre}`);
    } catch (err) {
      rapport.push(`${f.fichier}\t${f.url}\tECHEC ${String(err).slice(0, 110)}`);
    } finally {
      if (f.preparer === 'mode-emecef') modeFacturation('desactive');
    }
  };

  // 1. Avant connexion.
  for (const f of FIGURES.filter((x) => x.avantConnexion && retenu(x.fichier) && dupe(x))) await faire(f);

  // 2. Connexion.
  await page.goto(BASE + '/pwa/connexion', { waitUntil: 'networkidle0' });
  await attendre(1200);
  await page.type('#champ-identifiant', LOGIN, { delay: 12 });
  await page.type('#champ-motdepasse', MDP, { delay: 12 });
  await Promise.all([
    page.waitForNavigation({ waitUntil: 'networkidle0', timeout: 30000 }).catch(() => null),
    page.click('#formulaire-connexion button[type="submit"]'),
  ]);
  await attendre(1500);
  if (page.url().includes('/connexion')) {
    console.error('ÉCHEC DE CONNEXION');
    await navigateur.close();
    process.exit(2);
  }
  await congedier();

  // 3. Écrans sous session.
  for (const f of FIGURES.filter((x) => !x.avantConnexion && !x.sansSession && retenu(x.fichier) && dupe(x))) await faire(f);

  // 4. Écran sans session utile (hors connexion) : en contexte propre.
  for (const f of FIGURES.filter((x) => x.sansSession && retenu(x.fichier) && dupe(x))) await faire(f);

  // 5. Le changement de mot de passe OBLIGATOIRE : un compte d'essai dont le
  //    mot de passe vient d'être réinitialisé, connecté dans un contexte à part.
  if (!SUPER && LOGIN_ESSAI && MDP_ESSAI && retenu('pwa-changement-mot-de-passe-obligatoire')) {
    try {
      const contexte = await navigateur.createBrowserContext();
      const p2 = await contexte.newPage();
      await p2.setExtraHTTPHeaders({ 'Accept-Language': 'fr-FR,fr;q=0.9' });
      await p2.goto(BASE + '/pwa/connexion', { waitUntil: 'networkidle0' });
      await attendre(1200);
      await p2.type('#champ-identifiant', LOGIN_ESSAI, { delay: 12 });
      await p2.type('#champ-motdepasse', MDP_ESSAI, { delay: 12 });
      await Promise.all([
        p2.waitForNavigation({ waitUntil: 'networkidle0', timeout: 30000 }).catch(() => null),
        p2.click('#formulaire-connexion button[type="submit"]'),
      ]);
      await attendre(2000);
      if (!p2.url().includes('changement-mot-de-passe')) throw new Error('page inattendue : ' + p2.url());
      const h = Math.min(Math.max(await p2.evaluate(() => document.documentElement.scrollHeight), 700), 1500);
      await p2.setViewport({ width: 1440, height: h, deviceScaleFactor: 2 });
      await attendre(500);
      await p2.screenshot({ path: path.join(SORTIE, 'pwa-changement-mot-de-passe-obligatoire.png'), clip: { x: 0, y: 0, width: 1440, height: h } });
      rapport.push('pwa-changement-mot-de-passe-obligatoire\t/pwa/changement-mot-de-passe');
      await contexte.close();
    } catch (err) {
      rapport.push('pwa-changement-mot-de-passe-obligatoire\tECHEC ' + String(err).slice(0, 110));
    }
  }

  console.log(rapport.join('\n'));
  const echecs = rapport.filter((l) => /ECHEC|REFUS|INTROUVABLE/.test(l));
  console.log('\n' + rapport.length + ' captures · ' + echecs.length + ' à revoir');
  await navigateur.close();
})();

/* ---------------------------------------------------------------------------
 * LogiRestock — Manuel d'utilisation : génération du PDF.
 *
 * Principe : chaque section (avant-propos, sommaire, chapitres, annexes) est
 * rendue dans SON PROPRE PDF, puis les PDF sont assemblés. Deux garanties en
 * découlent, qu'un rendu global ne donnait pas :
 *
 *   1. un chapitre commence toujours sur une page neuve — par construction,
 *      et non parce qu'une règle `page-break-before` a été respectée ;
 *   2. les numéros de page du sommaire sont exacts : ils se déduisent du
 *      nombre de pages réellement produit par chaque section.
 *
 * L'en-tête et le pied de page (dont la pagination) sont apposés APRÈS
 * l'assemblage, page par page : les gabarits de Chrome numérotent par
 * document, ce qui redémarrerait à 1 à chaque chapitre.
 *
 * Dépendances : puppeteer-core (pilote le Chrome installé) + pdf-lib.
 * Exécution :   PPTR_DIR=<dossier des modules> node generer.js
 * ------------------------------------------------------------------------- */

const fs = require('fs');
const path = require('path');
const MODULES = process.env.PPTR_DIR || path.join(__dirname, 'node_modules');
const puppeteer = require(path.join(MODULES, 'node_modules', 'puppeteer-core'));
const { PDFDocument, StandardFonts, rgb } = require(path.join(MODULES, 'node_modules', 'pdf-lib'));

const SRC = path.join(__dirname, 'src');
// Navigateur : CHROME_PATH, sinon le Chromium pré-installé (Linux), sinon Chrome sous Windows.
const CHROME = process.env.CHROME_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : 'C:/Program Files/Google/Chrome/Application/chrome.exe');
// PDF_SORTIE : écrire ailleurs (essai de rendu) sans toucher au PDF livré.
const SORTIE = process.env.PDF_SORTIE || path.join(__dirname, 'MANUEL_UTILISATION_LOGIRESTOCK.pdf');

const MARGES = { top: '22mm', bottom: '20mm', left: '16mm', right: '16mm' };
const MARINE = rgb(0.078, 0.129, 0.239);   // #14213D
const OR = rgb(0.722, 0.537, 0.118);       // #B8891E
const ARDOISE = rgb(0.392, 0.455, 0.545);  // #64748B

const lire = (f) => fs.readFileSync(path.join(SRC, f), 'utf8');

const document = (corps) => `<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8">
<title>LogiRestock — Manuel d'utilisation</title>
<link rel="stylesheet" href="style.css">
<style>@page { size: A4; }</style>
</head><body>${corps}</body></html>`;

(async () => {
  // ------------------------------------------------------------- 1. Assemblage
  const parties = fs.readdirSync(SRC).filter((f) => /^part-\d+\.html$/.test(f)).sort();
  const premiere = lire(parties[0]);
  const coupure = premiere.indexOf('<!-- ============================ AVANT-PROPOS');
  if (coupure < 0) throw new Error('Marqueur AVANT-PROPOS introuvable dans ' + parties[0]);

  const couverture = premiere.slice(0, coupure);
  const corps = premiere.slice(coupure) + parties.slice(1).map(lire).join('\n');
  const sections = corps
    .split(/(?=<!-- ={20,} (?:CHAPITRE|ANNEXE|AVANT-PROPOS|SOMMAIRE))/g)
    .map((s) => s.trim())
    .filter(Boolean)
    .map((html) => ({ html, id: (html.match(/<section class="chapitre" id="([^"]+)"/) || [])[1] || '?' }));

  // Les ANNEXES ferment toujours le manuel : les chapitres ajoutés après coup
  // (part-10.html et suivants, chapitres 15 et suivants) s'insèrent avant elles,
  // sans qu'il faille déplacer le texte des annexes d'un fichier à l'autre.
  // Tri stable : l'ordre des fichiers est conservé à l'intérieur de chaque groupe.
  const estAnnexe = (s) => /^annexe/i.test(s.id);
  sections.splice(0, sections.length, ...sections.filter((s) => !estAnnexe(s)), ...sections.filter(estAnnexe));

  const navigateur = await puppeteer.launch({
    executablePath: CHROME, headless: 'new',
    args: ['--no-sandbox', '--allow-file-access-from-files'],
  });
  const page = await navigateur.newPage();

  // ------------------------------------------- 1bis. Allègement des captures
  //
  // Les captures sont prises à 2880 px de large (facteur 2) : à l'impression,
  // une figure n'occupe jamais plus de 148 mm, soit ~1400 px à 240 dpi. Les
  // ré-encoder en JPEG divise le poids du PDF par trois sans perte visible.
  const IMG = path.join(SRC, 'img');
  fs.mkdirSync(IMG, { recursive: true });
  const captures = fs.readdirSync(path.join(__dirname, 'captures')).filter((f) => f.endsWith('.png'));
  const pageImage = await navigateur.newPage();
  const vide = path.join(SRC, '_vide.html');
  fs.writeFileSync(vide, '<!DOCTYPE html><meta charset="UTF-8"><title>vide</title>', 'utf8');
  await pageImage.goto('file:///' + vide.replace(/\\/g, '/'));
  for (const f of captures) {
    const cible = path.join(IMG, f.replace('.png', '.jpg'));
    if (fs.existsSync(cible)) continue;
    const source = 'file:///' + path.join(__dirname, 'captures', f).replace(/\\/g, '/');
    const donnees = await pageImage.evaluate(async (url) => {
      const img = new Image();
      img.src = url;
      await img.decode();
      const largeur = Math.min(img.naturalWidth, 1400);
      const c = document.createElement('canvas');
      c.width = largeur;
      c.height = Math.round(img.naturalHeight * (largeur / img.naturalWidth));
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      return c.toDataURL('image/jpeg', 0.86);
    }, source);
    fs.writeFileSync(cible, Buffer.from(donnees.split(',')[1], 'base64'));
  }
  await pageImage.close();
  fs.unlinkSync(vide);
  const alleger = (html) => html.replace(/\.\.\/captures\/([a-z0-9-]+)\.png/g, 'img/$1.jpg');

  let compteur = 0;
  const rendre = async (html, marges) => {
    const fichier = path.join(SRC, '_rendu' + (compteur++) + '.html');
    fs.writeFileSync(fichier, html, 'utf8');
    await page.goto('file:///' + fichier.replace(/\\/g, '/'), { waitUntil: 'networkidle0', timeout: 120000 });
    await page.evaluate(() => document.fonts.ready);
    const pdf = await page.pdf({ format: 'A4', printBackground: true, margin: marges });
    fs.unlinkSync(fichier);
    return pdf;
  };

  // -------------------------------- 2. Rendu section par section et pagination
  const rendus = [];
  let curseur = 1;
  const numeros = {};
  for (const section of sections) {
    const pdf = await rendre(document(alleger(section.html)), MARGES);
    const n = (await PDFDocument.load(pdf)).getPageCount();
    numeros[section.id] = curseur;
    rendus.push({ id: section.id, pdf, n, debut: curseur });
    curseur += n;
    process.stdout.write(section.id + '=' + n + '  ');
  }
  console.log('');

  // ------------------------------- 3. Sommaire : réinjection des numéros réels
  const iSommaire = sections.findIndex((s) => s.id === 'sommaire');
  const sommaireNumerote = sections[iSommaire].html.replace(
    /<span class="p" data-ref="([^"]+)"><\/span>/g,
    (m, ref) => `<span class="p">${numeros[ref] || '—'}</span>`,
  );
  const pdfSommaire = await rendre(document(alleger(sommaireNumerote)), MARGES);
  const nSommaire = (await PDFDocument.load(pdfSommaire)).getPageCount();
  if (nSommaire !== rendus[iSommaire].n) {
    throw new Error('Le sommaire numéroté change de pagination (' + rendus[iSommaire].n + ' -> ' + nSommaire + ') : les numéros seraient faux.');
  }
  rendus[iSommaire].pdf = pdfSommaire;

  // ------------------------------------------------------- 4. Couverture + fusion
  const pdfCouverture = await rendre(document(couverture), { top: '0', bottom: '0', left: '0', right: '0' });

  const final = await PDFDocument.create();
  const ajouter = async (source) => {
    const doc = await PDFDocument.load(source);
    const pages = await final.copyPages(doc, doc.getPageIndices());
    pages.forEach((p) => final.addPage(p));
  };
  await ajouter(pdfCouverture);
  for (const r of rendus) await ajouter(r.pdf);

  // ------------------------------------- 5. En-tête et pied de page, page à page
  const normal = await final.embedFont(StandardFonts.Helvetica);
  const gras = await final.embedFont(StandardFonts.HelveticaBold);
  const pages = final.getPages();
  const totalCorps = pages.length - 1; // la couverture n'est pas numérotée

  pages.forEach((p, index) => {
    if (index === 0) return; // couverture
    const { width, height } = p.getSize();
    const numero = index; // la page 1 du corps suit la couverture
    const marge = 45.4; // 16 mm

    p.drawText("LogiRestock — Manuel d'utilisation", { x: marge, y: height - 34, size: 7.5, font: gras, color: MARINE });
    const droite = 'TATACORA AFRIQUE · Gîte Chez Noël, Natitingou';
    p.drawText(droite, { x: width - marge - normal.widthOfTextAtSize(droite, 7.5), y: height - 34, size: 7.5, font: normal, color: ARDOISE });
    p.drawLine({ start: { x: marge, y: height - 40 }, end: { x: width - marge, y: height - 40 }, thickness: 0.6, color: OR });

    const gauche = 'LogiRestock version 1.0.0 - Novembre 2026';
    p.drawText(gauche, { x: marge, y: 30, size: 7.5, font: normal, color: ARDOISE });
    const pagination = 'Page ' + numero + ' / ' + totalCorps;
    p.drawText(pagination, { x: width - marge - gras.widthOfTextAtSize(pagination, 7.5), y: 30, size: 7.5, font: gras, color: MARINE });
  });

  final.setTitle("LogiRestock — Manuel d'utilisation");
  final.setAuthor('Dr MASSENON Rhodes — FAGUEZ SARL / PAEB');
  final.setSubject("Manuel d'utilisation du logiciel LogiRestock — Gîte Chez Noël, Natitingou (Bénin)");
  final.setKeywords(['LogiRestock', 'TATACORA AFRIQUE', 'manuel d\'utilisation', 'gestion de stock', 'réservations', 'facturation', 'version 1.0.0']);
  fs.writeFileSync(SORTIE, await final.save());

  console.log('Sommaire :', rendus.map((r) => r.id + ' p.' + r.debut).join(' · '));
  console.log('PDF :', SORTIE, '·', pages.length, 'pages ·', Math.round(fs.statSync(SORTIE).size / 1024), 'Ko');
  await navigateur.close();
})();

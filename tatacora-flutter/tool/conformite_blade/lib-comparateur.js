/* =========================================================================
   OUTILS DE TEXTE DU COMPARATEUR VUE BLADE -> FLUTTER
   =========================================================================

   Decoupage, decodage et recollage des chaines : les regles qui disent ce
   qu'est un « libelle » des deux cotes de la comparaison. Elles vivent a part
   pour qu'une regle ne puisse pas etre appliquee differemment a la vue et au
   code Flutter — deux copies finissent par diverger, et le comparateur
   rendrait alors un verdict faux sans rien signaler.

   Reprises le 10/09/2026 du comparateur de l'ancien maitre
   (`prototype_v2/tests/t-trois-sources.js`, archive depuis PA-183), SANS
   changement de regle : ce sont celles que ce depot a eprouvees depuis le
   26/08/2026.
   ========================================================================= */

'use strict';

const fs = require('fs');
const path = require('path');

function fichiersSous(racine, extensions) {
  if (!fs.existsSync(racine)) return [];
  const trouves = [];
  const parcourir = (dossier) => {
    for (const entree of fs.readdirSync(dossier, { withFileTypes: true })) {
      const complet = path.join(dossier, entree.name);
      if (entree.isDirectory()) parcourir(complet);
      else if (extensions.some((e) => entree.name.endsWith(e))) trouves.push(complet);
    }
  };
  parcourir(racine);
  return trouves;
}

const ENTITES = {
  '&amp;': '&', '&nbsp;': ' ', '&mdash;': '—', '&ndash;': '–',
  '&rsquo;': '’', '&laquo;': '«', '&raquo;': '»',
  '&eacute;': 'é', '&egrave;': 'è', '&agrave;': 'à',
  '&ecirc;': 'ê', '&ccedil;': 'ç', '&hellip;': '…',
  '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'",
  // Les entites d'ICONE. Ne pas les decoder les laissait passer pour des
  // libelles : `&times;` fait sept caracteres, donc franchissait le plancher
  // de cinq, et le comparateur reclamait un « &times; » que personne
  // n'ecrira jamais — la croix de fermeture d'une modale est une icone.
  '&times;': '×', '&middot;': '·', '&minus;': '−',
};

/**
 * Le texte d'un noeud HTML, entites decodees.
 *
 * Les decoder est indispensable : la vue ecrit `&mdash;` la ou le code Dart
 * ecrit le tiret cadratin lui-meme. Les laisser tels quels ferait crier le
 * comparateur sur une transcription pourtant exacte — et un test qui crie a
 * tort finit par etre desactive.
 */
function texteNu(html) {
  let t = html.replace(/<br\s*\/?>/gi, ' ').replace(/<[^>]*>/g, ' ');
  for (const [e, c] of Object.entries(ENTITES)) t = t.split(e).join(c);
  return t.replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Les suites de texte comparables d'un fragment.
 *
 * On compare les SUITES DE TEXTE, pas la concatenation du sous-arbre : la vue
 * ecrit `<label>Identifiant <span>*</span></label>`, le portage rend
 * « Identifiant » et son asterisque separement. Confronter « Identifiant * »
 * accuserait un ecart qui n'existe pas.
 */
function* suitesDeTexte(texte) {
  for (const brut of String(texte).split(/<[^>]*>/)) {
    const t = texteNu(brut);
    // Sous 5 caracteres, une chaine est trop generique pour distinguer une
    // absence d'une coincidence — « Tous », « OK », « Du ».
    if (t.length < 5) continue;
    // Un fragment de gabarit n'est pas un libelle.
    if (t.includes('${') || t.includes('{{')) continue;
    yield t;
  }
}

/**
 * Les litteraux Dart/PHP recolles.
 *
 * Une phrase longue est coupee sur plusieurs lignes par le formateur ; la
 * chercher telle quelle ne la trouverait jamais, et le balayage passerait a
 * vide.
 */
function recoller(source) {
  return source
    .replace(/'\s*\n\s*'/g, '')
    .replace(/"\s*\n\s*"/g, '')
    .replace(/'\s*\.\s*'/g, '')
    .replace(/\\'/g, "'")
    // Le <br> est CONSERVE dans les chaines de langue : il tient un titre sur
    // deux lignes a la cesure voulue. On le neutralise des deux cotes.
    .replace(/<br\s*\/?>/gi, ' ')
    // Le saut de ligne ECHAPPE de Dart exprime la meme chose que le <br>.
    .replace(/\\n/g, ' ')
    .replace(/\s+/g, ' ');
}

module.exports = { fichiersSous, ENTITES, texteNu, suitesDeTexte, recoller };

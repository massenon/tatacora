/* =========================================================================
   CONFORMITE — VUE BLADE (maitre) -> CLIENT FLUTTER
   =========================================================================

   Decisions du Product Owner du 10/09/2026 :
     - PA-182 : le client Flutter se conforme a la VUE BLADE de la PWA,
       ecran par ecran, onglet par onglet, memes emplacements ;
     - PA-183 : `prototype_v2/` est une ANCIENNE version et n'est plus une
       reference. La vue Blade de `tatacora-api` porte la derniere version :
       elle est le SEUL maitre.

   Lance par `test/core/qualite/conformite_blade_test.dart` a chaque
   `flutter test`, ou seul :

     node tool/conformite_blade/t-blade-flutter.js            (depuis tatacora-flutter/)
     node tool/conformite_blade/t-blade-flutter.js --detail   (libelles absents)
     node tool/conformite_blade/t-blade-flutter.js --detail=crm/clients-creances
     node tool/conformite_blade/t-blade-flutter.js --figer-dette

   Pour chaque page servie par la PWA, il confronte au code Flutter :
     1. son TITRE (H1) ;
     2. ses ONGLETS ;
     3. les LIBELLES de chacun de ses blocs (panneaux d'onglet, sections) ;
     4. ses MODALES, une par une ;
   plus, une seule fois, le CHASSIS : barre superieure, menu de compte, barre
   laterale, banniere, acces rapide, et les composants montes sur toutes les
   pages (recherche globale, cloche, verrou de session...).

   ## D'ou viennent les libelles d'une vue

   Une vue Blade n'ecrit presque jamais ses mots : elle appelle
   `__('pwa.clients.titre')`. Ce script RESOUT donc les cles par PHP lui-meme
   (`lang/fr/*.php` et `lang/fr.json`) : la semantique exacte de Laravel, sans
   analyseur ecrit a la main qui pourrait se tromper en silence. Sans PHP, il
   ECHOUE — une garde dont la source manque ne saute pas.

   Une cle est reconnue partout ou elle apparait comme LITTERAL : `__('k')`,
   `:titre="__('k')"`, mais aussi `match ($cle) { 'x' => 'pwa.k' }`, forme par
   laquelle la vue des clients choisit le libelle de ses onglets. Deux
   precautions, chacune contre un faux positif mesure :
     - une cle dont la valeur est un TABLEAU (un groupe entier) ne compte que
       passee directement a `__()` : `route('pwa.clients')` nomme une route,
       et le groupe de langue du meme nom aurait sinon verse ses cent
       libelles dans la page ;
     - un litteral passe a `route()`, `view()`, `@include()` ou `livewire`
       n'est jamais une cle de langue.
   Le prix : une cle construite par concatenation (`'pwa.x.canal_' . $c`)
   n'est pas vue.

   S'y ajoutent le texte litteral du gabarit (hors commentaires, directives,
   `@php`, `{{ }}`, scripts et SVG), les `placeholder` et `title` litteraux,
   et, pour les onglets, la constante `ONGLETS` de la classe Livewire quand
   elle porte les libelles (`Comptabilite\Hub`, `Transverse\Parametres`).

   Les `@include` sont DEPLIES (sauf les partiels du chassis, compares une
   fois a part), et les composants `<x-pwa.*>` aussi : une modale d'archivage
   porte ses mots dans `components/pwa/modale-archivage.blade.php`, pas dans
   la vue qui l'appelle.

   ## L'ancrage : qui porte une vue cote Flutter

   Un fichier Dart porte une vue s'il la CITE : `pwa/<module>/<vue>.blade.php`
   (DOCTRINE §3.5, DIRECTIVE Article 8). Il n'existe PAS d'autre ancrage — plus
   de rattachement par la page de l'ancien prototype, retire le 10/09/2026
   (PA-183). Une vue qu'aucun fichier ne cite n'est pas portee : c'est un
   reste-a-faire, RAPPORTE, jamais compte comme un ecart.

   A l'inverse, un ECRAN Flutter (`ecran_*.dart`) qui ne cite aucune vue est
   rapporte a part : c'est un ecran que la PWA n'a pas (Article 1, interdit
   n. 07), qui doit etre declare comme ecart ou retire.

   ## Refus, et libelles venus du serveur

   Un bloc refuse se DECLARE dans le code Flutter : `blade-refuse:<vue>#<bloc>`,
   `<vue>` etant le chemin sous `resources/views/pwa/` sans `.blade.php` et
   `<bloc>` le nom que ce rapport affiche (`titre`, `onglets`, un nom de
   panneau, `modale:<id>`). Pour le chassis : `blade-refuse:chassis#<bloc>`.
   Un ecran qui recoit ses libelles de l'API declare `libelles-du-serveur:<vue>`.

   ## La dette, et pourquoi elle echoue dans les QUATRE sens

   Le jour de la decision, le Flutter avait ete porte depuis l'ancien
   prototype : il manque des centaines de libelles de la vue. Les compter
   comme des ecarts rendrait la suite rouge le jour de sa livraison, donc
   ignoree des le lendemain. La dette est FIGEE (`--figer-dette`, jamais a la
   main) dans `dette-blade-flutter.json` : cle « vue|bloc », valeur = libelles
   absents. Le script echoue :
     - sur un bloc incomplet qui n'y figure pas          (regression) ;
     - sur un bloc dont le compte MONTE                  (derive) ;
     - sur un bloc dont le compte BAISSE                 (cliquet a resserrer) ;
     - sur une entree qui ne correspond plus a rien,
       ou a un bloc desormais porte ou refuse            (dette perimee).
   Le troisieme sens est delibere : un cliquet qu'on ne resserre pas laisse
   une regression ulterieure se cacher jusqu'a l'ancien chiffre.

   ## Limites, ecrites plutot que decouvertes plus tard

   - Il lit le CODE SOURCE Flutter, pas l'arbre de widgets monte : une chaine
     citee en commentaire le satisfait autant qu'une chaine affichee. C'est le
     prix du contrat « rendu OU nomme comme refuse » — sans lui, on ne
     pourrait pas declarer un refus.
   - Titre, onglets et blocs de page se cherchent dans le CODE QUE L'ECRAN
     ATTEINT : ses porteurs (plus ceux qui y declarent un refus) et tout ce
     qu'ils importent, transitivement, dans `lib/` (PA-196, 11/09/2026). Ils
     se cherchaient dans l'ARBRE ENTIER du client, et quatre faux positifs
     ont ete mesures en une journee (PA-189, PA-192, PA-193, PA-195) : un
     libelle d'un bloc NON porte « trouve » dans un fichier sans rapport — un
     visa de PDF, le catalogue d'un autre ecran. Mesure au basculement : 96
     libelles de plus absents sur 26 blocs, verifies par echantillon comme de
     VRAIS manques que l'arbre entier masquait (un onglet « Annulations »
     trouve dans l'ecran des vehicules, « Actualiser » dans le catalogue du
     bar). Les porteurs SEULS, sans leurs imports, en ajoutaient 253 : les
     widgets partages qu'un ecran importe sans citer la vue sont bien rendus
     par lui. Les modales se cherchaient deja dans les seuls porteurs depuis
     le 27/08/2026, pour la meme raison.
   - La correspondance reste une SOUS-CHAINE : « Magasin », en-tete d'une
     colonne non portee de l'inventaire, est « trouve » dans « Visa
     Magasinier », que l'ecran atteint par l'etat de fiche de stock. La
     recherche par mot entier est une autre decision, non prise.
   - Les chaines de moins de 5 caracteres sont ignorees.
   - Un libelle est attribue au dernier panneau ouvert avant lui
     (`@if ($onglet === 'x')`, `data-panneau="x"`) : l'attribution est une
     aide a la lecture, pas une preuve d'emplacement.
   - Il ne compare NI les classes, NI l'ordre, NI les emplacements : c'est la
     part de la conformite qu'aucune lecture de texte ne tranche. Ce script dit
     ce qui MANQUE ; il ne dit pas que ce qui est la est bien place.
   - Le texte ecrit par la classe Livewire (messages, libelles calcules) n'est
     pas lu, sauf ses onglets et son `#[Title]`, titre de repli d'une vue dont
     le H1 est calcule.

   Mutation : COMPARATEUR_API et COMPARATEUR_FLUTTER_LIB designent une COPIE a
   eprouver — on ne retouche jamais le depot pour prouver une garde.
   ========================================================================= */

'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { fichiersSous, texteNu, suitesDeTexte, recoller } = require('./lib-comparateur');

// tool/conformite_blade/ -> tatacora-flutter/ -> racine du depot.
const RACINE = path.resolve(__dirname, '..', '..', '..');
const API = process.env.COMPARATEUR_API || path.join(RACINE, 'tatacora-api');
// Le dossier du client se deduit de CE fichier, jamais de son nom : le
// monorepo du 14/10/2026 l'a renomme `tatacora-flutter`, et l'ancien chemin
// `tatacora_flutter/lib` rendait 0 fichier Dart (comparaison a vide, rouge).
const FLUTTER = process.env.COMPARATEUR_FLUTTER_LIB || path.resolve(__dirname, '..', '..', 'lib');

const VUES = path.join(API, 'resources', 'views');
const VUES_PWA = path.join(VUES, 'pwa');
const COMPOSANTS = path.join(VUES, 'components', 'pwa');
const CODE_PWA = path.join(API, 'app', 'Pwa');
const LANG = path.join(API, 'lang', 'fr');
const SERVEUR_PARTAGE = path.join(API, 'app', 'Shared');
const MENU_LATERAL = path.join(CODE_PWA, 'Support', 'MenuLateral.php');
const GABARIT = path.join(VUES, 'layouts', 'pwa.blade.php');

const CHEMIN_DETTE = path.join(__dirname, 'dette-blade-flutter.json');
const FIGER = process.argv.includes('--figer-dette');
const argDetail = process.argv.find((a) => a.startsWith('--detail'));
const DETAIL = argDetail ? (argDetail.split('=')[1] || true) : false;

let echecs = 0;
const ecart = (message) => {
  echecs += 1;
  console.log('  \x1b[31mECART\x1b[0m  ' + message);
};
const fatal = (message) => {
  console.log('\n  \x1b[31m' + message + '\x1b[0m\n');
  process.exit(1);
};

console.log('\n\x1b[1mMAITRE BLADE -> FLUTTER — vues de la PWA / client Flutter\x1b[0m\n');

/* ------------------------------------------------------------ la dette lue */

const detteLue = fs.existsSync(CHEMIN_DETTE)
  ? JSON.parse(fs.readFileSync(CHEMIN_DETTE, 'utf8'))
  : null;
if (!detteLue && !FIGER) {
  fatal('La dette Blade -> Flutter est introuvable (' + path.basename(CHEMIN_DETTE) + ').\n'
    + '  Une garde dont la source manque ECHOUE, elle ne saute pas.\n'
    + '  Regenerez-la : node tool/conformite_blade/t-blade-flutter.js --figer-dette');
}
const dette = (detteLue && detteLue.ecarts) || {};
const detteMesuree = {};
const clesRencontrees = new Set();
const refus = [];

/* ------------------------------------------------------ la langue, par PHP */

// Le script PHP passe par l'ENTREE STANDARD, jamais par `-r` : sur Windows,
// les guillemets d'un argument `-r` sont reinterpretes par la ligne de
// commande, et un script mutile rendrait un JSON vide — la garde verte a vide.
const SCRIPT_LANGUE = [
  '<?php',
  '$plat = [];',
  'foreach (glob($argv[1] . "/*.php") as $f) {',
  '  $v = require $f;',
  '  if (!is_array($v)) { continue; }',
  '  $pile = [[basename($f, ".php"), $v]];',
  '  while ($pile) {',
  '    [$p, $t] = array_pop($pile);',
  '    foreach ($t as $k => $x) {',
  '      $c = $p . "." . $k;',
  '      if (is_array($x)) {',
  '        $pile[] = [$c, $x];',
  '        $feuilles = [];',
  '        array_walk_recursive($x, function ($y) use (&$feuilles) { if (is_string($y)) { $feuilles[] = $y; } });',
  '        $plat[$c] = $feuilles;',
  '      } elseif (is_string($x)) {',
  '        $plat[$c] = $x;',
  '      }',
  '    }',
  '  }',
  '}',
  '$json = dirname($argv[1]) . "/fr.json";',
  'if (is_file($json)) {',
  '  foreach (json_decode(file_get_contents($json), true) ?: [] as $k => $x) {',
  '    if (is_string($x)) { $plat["json:" . $k] = $x; }',
  '  }',
  '}',
  'echo json_encode($plat, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);',
].join('\n');

let LANGUE;
try {
  LANGUE = JSON.parse(execFileSync('php', ['--', LANG], {
    input: SCRIPT_LANGUE,
    encoding: 'utf8',
    maxBuffer: 1 << 26,
  }));
} catch (e) {
  fatal('Les libelles de la PWA sont illisibles : PHP introuvable, ou un fichier de '
    + '`lang/fr/` en erreur.\n  ' + String(e.message).split('\n')[0]);
}
const nbChaines = Object.values(LANGUE).filter((v) => typeof v === 'string').length;

/** Les suites comparables d'une valeur de langue : variantes, jetons retires. */
function suitesDeLangue(valeur) {
  const trouvees = [];
  for (const v of Array.isArray(valeur) ? valeur : [valeur]) {
    // `{0} aucun|[1,*] :n elements` : chaque variante est un libelle.
    for (const variante of String(v).split('|')) {
      const nette = variante.replace(/^\s*(\{[^}]*\}|\[[^\]]*\])\s*/, '');
      // `:nombre` est remplace a l'execution : le texte autour, lui, est fixe.
      for (const morceau of nette.split(/:[a-zA-Z_]\w*/)) {
        for (const s of suitesDeTexte(morceau)) trouvees.push(s);
      }
    }
  }
  return trouvees;
}

/* ------------------------------------------------------------ lecture Blade */

const cacheTexte = new Map();
function lire(fichier) {
  if (!cacheTexte.has(fichier)) {
    cacheTexte.set(fichier, fs.existsSync(fichier) ? fs.readFileSync(fichier, 'utf8') : '');
  }
  return cacheTexte.get(fichier);
}

const cheminVue = (nom) => path.join(VUES, ...nom.split('.')) + '.blade.php';

/** Commentaires Blade et HTML BLANCHIS — positions conservees. */
function sansCommentaires(source) {
  return source
    .replace(/\{\{--[\s\S]*?--\}\}/g, (m) => ' '.repeat(m.length))
    .replace(/<!--[\s\S]*?-->/g, (m) => ' '.repeat(m.length));
}

/**
 * L'indice de la parenthese fermante qui equilibre celle d'`ouvrante`.
 *
 * Les commentaires PHP (`// ...`, `/* ... *\/`) sont SAUTES hors guillemets.
 * Mesure le 11/09/2026 : les arguments d'`@include('pwa.carte.corps', [...])`
 * dans `pwa/bar/carte.blade.php` portent des commentaires `//` en francais, et
 * l'apostrophe de « qu'elle » ouvrait un guillemet jamais referme. La fermante
 * n'etait pas trouvee, l'inclusion n'etait pas depliee — et le corps entier de
 * la carte (bouton et modale « Nouvelle boisson », modale d'export, bandeau)
 * n'etait JAMAIS mesure, pour le bar comme pour le restaurant. Vert a vide.
 */
function fermante(source, ouvrante) {
  let profondeur = 0;
  let guillemet = null;
  for (let i = ouvrante; i < source.length; i++) {
    const c = source[i];
    if (guillemet) {
      if (c === '\\') i += 1;
      else if (c === guillemet) guillemet = null;
      continue;
    }
    if (c === '/' && source[i + 1] === '/') {
      const saut = source.indexOf('\n', i);
      if (saut < 0) return -1;
      i = saut;
      continue;
    }
    if (c === '/' && source[i + 1] === '*') {
      const fin = source.indexOf('*/', i + 2);
      if (fin < 0) return -1;
      i = fin + 1;
      continue;
    }
    if (c === "'" || c === '"') guillemet = c;
    else if (c === '(') profondeur += 1;
    else if (c === ')') {
      profondeur -= 1;
      if (profondeur === 0) return i;
    }
  }
  return -1;
}

// Un litteral qui suit l'un de ces appels nomme une route, une vue ou un
// composant — jamais un libelle, meme s'il ressemble a une cle de langue.
const APPEL_NON_LANGUE = /(?:route|view|@include\w*|livewire|url|asset|redirect|to_route)\s*\(\s*$/;
const APPEL_LANGUE = /(?:__|trans|trans_choice|@lang)\s*\(\s*$/;
const MOTIF_CLE = /(['"])([a-z0-9_]+(?:\.[A-Za-z0-9_]+)+)\1/g;

/** Les cles de langue d'un texte, sous forme de marqueurs relisibles. */
function resumeArguments(texte) {
  const cles = [];
  for (const m of texte.matchAll(MOTIF_CLE)) cles.push("'" + m[2] + "'");
  const litteraux = [];
  for (const m of texte.matchAll(/(?:^|\s)(?:titre|sous-?titre|sousTitre|message|libelle\w*)="([^"{}$]*)"/g)) {
    litteraux.push('<i>' + m[1] + '</i>');
  }
  // Les cles vont dans un commentaire HTML : le decoupage en texte les ecarte,
  // la recherche des cles les lit. Aucune ne contient `>`.
  return '<!--ARGS ' + cles.join(' ') + '-->' + litteraux.join(' ');
}

// Les partiels du CHASSIS ne sont pas deplies dans les pages : ils se
// comparent UNE fois (Article 3), pas quarante.
const PARTIELS_CHASSIS = new Set([
  'pwa.partials.barre-superieure', 'pwa.partials.menu-lateral', 'pwa.partials.entree-menu',
  'pwa.partials.banniere', 'pwa.partials.acces-rapide', 'pwa.partials.tete',
  'pwa.partials.maintien-session', 'pwa.partials.toast-succes',
]);

/**
 * Une vue avec ses `@include` et ses composants `<x-pwa.*>` DEPLIES.
 *
 * Chaque morceau deplie est encadre de marqueurs (`<!--INCLUS:nom-->`,
 * `<!--COMPOSANT:nom-->`) : c'est ce qui permet de reconnaitre ensuite qu'un
 * partiel ou un composant est une MODALE.
 */
function deplier(source, sauter, profondeur = 0) {
  if (profondeur > 8) return source;
  let sortie = '';
  let curseur = 0;
  const motif = /@include(?:If|When|Unless|First)?\s*\(/g;
  let m;
  while ((m = motif.exec(source))) {
    const ouvrante = m.index + m[0].length - 1;
    const fin = fermante(source, ouvrante);
    if (fin < 0) break;
    const args = source.slice(ouvrante + 1, fin);
    const nom = (args.match(/['"](pwa\.[a-z0-9_.-]+)['"]/) || [])[1];
    sortie += source.slice(curseur, m.index);
    if (nom && !sauter.has(nom) && fs.existsSync(cheminVue(nom))) {
      sortie += '<!--INCLUS:' + nom + '-->' + resumeArguments(args.replace(/['"]pwa\.[a-z0-9_.-]+['"]/, ''))
        + deplier(sansCommentaires(lire(cheminVue(nom))), sauter, profondeur + 1)
        + '<!--/INCLUS:' + nom + '-->';
    } else {
      sortie += ' '.repeat(fin + 1 - m.index);
    }
    curseur = fin + 1;
    motif.lastIndex = curseur;
  }
  sortie += source.slice(curseur);

  // Les composants `<x-pwa.*>`, SAUF le cadre `modale` : son chrome (le bouton
  // de fermeture) n'est pas un libelle d'ecran, et ses bornes servent a
  // reconnaitre la modale.
  sortie = sortie.replace(
    /<x-pwa\.([a-z0-9-]+)\b((?:[^>"']|"[^"]*"|'[^']*')*?)(\/?)>/g,
    (tout, nom, attributs, autoFermant) => {
      if (nom === 'modale') return tout;
      const fichier = path.join(COMPOSANTS, nom + '.blade.php');
      const corps = fs.existsSync(fichier)
        ? deplier(sansCommentaires(lire(fichier)), sauter, profondeur + 1)
        : '';
      return '<!--COMPOSANT:' + nom + '-->' + resumeArguments(attributs) + corps
        + (autoFermant ? '<!--/COMPOSANT:' + nom + '-->' : '');
    },
  );
  return sortie.replace(/<\/x-pwa\.([a-z0-9-]+)>/g, (tout, nom) => (
    nom === 'modale' ? tout : '<!--/COMPOSANT:' + nom + '-->'));
}

/** Le code du gabarit BLANCHI, pour ne garder que son texte. */
function sansCode(source) {
  const t = source
    .replace(/@php(?!\s*\()[\s\S]*?@endphp/g, (m) => ' '.repeat(m.length))
    .replace(/<\?php[\s\S]*?\?>/g, (m) => ' '.repeat(m.length))
    .replace(/\{\{[\s\S]*?\}\}|\{!![\s\S]*?!!\}/g, (m) => ' '.repeat(m.length))
    .replace(/<(script|style|svg)\b[\s\S]*?<\/\1>/gi, (m) => ' '.repeat(m.length));
  // Les directives, parentheses equilibrees comprises : `@if (in_array($a,
  // ['x']))` laisserait sinon « ['x'])) » dans le texte.
  let sortie = '';
  let i = 0;
  while (i < t.length) {
    const c = t[i];
    if (c === '@' && /[a-zA-Z]/.test(t[i + 1] || '') && !/[\w.]/.test(t[i - 1] || '')) {
      let j = i + 1;
      while (j < t.length && /\w/.test(t[j])) j += 1;
      let k = j;
      while (k < t.length && t[k] === ' ') k += 1;
      if (t[k] === '(') {
        const fin = fermante(t, k);
        if (fin > 0) j = fin + 1;
      }
      sortie += ' '.repeat(j - i);
      i = j;
      continue;
    }
    sortie += c;
    i += 1;
  }
  return sortie;
}

// Ce qui reste de code dans un texte n'est pas un libelle.
const RESTE_DE_CODE = /[$]|->|=>|::|\(\)|^@|;\s*$|^[\d\s.,:%px#-]+$/;

/**
 * Les libelles d'un fragment de vue : cles de langue resolues, `__('texte')`
 * litteraux, texte du gabarit et invites. Chacun garde sa POSITION, qui sert
 * a l'attribuer a son bloc.
 */
function libellesDe(fragment) {
  const trouves = new Map();
  const ajouter = (texte, index) => {
    if (!trouves.has(texte)) trouves.set(texte, index);
  };

  for (const m of fragment.matchAll(MOTIF_CLE)) {
    const valeur = LANGUE[m[2]];
    if (valeur === undefined) continue;
    const avant = fragment.slice(Math.max(0, m.index - 16), m.index);
    if (APPEL_NON_LANGUE.test(avant)) continue;
    if (Array.isArray(valeur) && !APPEL_LANGUE.test(avant)) continue;
    for (const s of suitesDeLangue(valeur)) ajouter(s, m.index);
  }

  for (const m of fragment.matchAll(/(?:__|trans|@lang)\(\s*(['"])((?:(?!\1).)+)\1/g)) {
    if (/^[a-z0-9_]+(\.[A-Za-z0-9_]+)+$/.test(m[2])) continue;
    const valeur = LANGUE['json:' + m[2]] !== undefined ? LANGUE['json:' + m[2]] : m[2];
    for (const s of suitesDeLangue(valeur)) ajouter(s, m.index);
  }

  const texte = sansCode(fragment);
  for (const m of texte.matchAll(/(?:placeholder|title)="([^"{}$]+)"/g)) {
    for (const s of suitesDeTexte(m[1])) if (!RESTE_DE_CODE.test(s)) ajouter(s, m.index);
  }
  // Les balises sont VIDEES en tenant compte des guillemets : un attribut
  // Alpine `x-init="setTimeout(() => visible = false, 5000)"` porte un `>`
  // qui, lu naivement, faisait sortir « visible = false, 5000)" » comme un
  // libelle — mesure le 10/09/2026 sur `restaurant/restauration`. Chaque
  // balise garde sa LONGUEUR : les positions attribuent les libelles aux blocs.
  const balise = /<[a-zA-Z!/][^>"']*(?:(?:"[^"]*"|'[^']*')[^>"']*)*>/g;
  const nu = texte.replace(balise, (m) => '<' + ' '.repeat(m.length - 2) + '>');
  for (const m of nu.matchAll(/(^|>)([^<]+)/g)) {
    for (const s of suitesDeTexte(m[2])) if (!RESTE_DE_CODE.test(s)) ajouter(s, m.index);
  }
  return trouves;
}

/* --------------------------------------------------------------- modales */

/**
 * Les MODALES d'une vue depliee. Quatre formes, toutes relevees dans la PWA :
 *   1. le cadre `<x-pwa.modale :titre="...">` ... `</x-pwa.modale>` ;
 *   2. un composant `<x-pwa.modale-*>` / `<x-pwa.modal-*>` (archivage, lien au
 *      stock...) ;
 *   3. un partiel `@include('pwa.partials.modale-*')` (l'export partage) ;
 *   4. une modale ecrite a la main, `overlay-modale` ou `fixed inset-0 ...
 *      justify-center`, hors des trois precedentes.
 */
function modalesDe(corps) {
  const regions = [];
  const dedans = (i) => regions.some((r) => i >= r.debut && i < r.fin);

  for (const m of corps.matchAll(/<x-pwa\.modale\b((?:[^>"']|"[^"]*"|'[^']*')*)>/g)) {
    const fin = corps.indexOf('</x-pwa.modale>', m.index);
    if (fin < 0) continue;
    const cle = (m[1].match(/['"]([a-z0-9_]+(?:\.[A-Za-z0-9_]+)+)['"]/) || [])[1];
    const litteral = (m[1].match(/(?:^|\s)titre="([^"{}$]+)"/) || [])[1];
    const titre = cle && typeof LANGUE[cle] === 'string' ? texteNu(LANGUE[cle]) : (litteral || null);
    // Une modale se nomme par la cle de son titre : stable d'une execution a
    // l'autre, et lisible dans la dette. A defaut (titre calcule), par sa forme.
    const base = cle ? cle.split('.').slice(1).join('.')
      : (litteral ? litteral.toLowerCase().replace(/[^a-z0-9]+/g, '-') : 'modale-titre-calcule');
    regions.push({ debut: m.index, fin: fin + '</x-pwa.modale>'.length, base, titre });
  }
  for (const m of corps.matchAll(/<!--(COMPOSANT|INCLUS):([a-z0-9_.-]+)-->/g)) {
    const nom = m[2];
    const court = nom.split('.').pop();
    const estModale = m[1] === 'COMPOSANT' ? /^modale?-/.test(court) : /modale/.test(court);
    if (!estModale || dedans(m.index)) continue;
    const borne = '<!--/' + m[1] + ':' + nom + '-->';
    const fin = corps.indexOf(borne, m.index);
    if (fin < 0) continue;
    // Un partiel de modale ENVELOPPE souvent le cadre `<x-pwa.modale>` : la
    // modale d'export partagee le fait. Garder les deux regions comptait ses
    // libelles DEUX fois — mesure le 10/09/2026, `modale-export` et `modale-2`
    // sur chaque page qui l'inclut. La region englobante l'emporte.
    const englobante = { debut: m.index, fin: fin + borne.length, base: court, titre: null };
    for (let i = regions.length - 1; i >= 0; i -= 1) {
      if (regions[i].debut >= englobante.debut && regions[i].fin <= englobante.fin) regions.splice(i, 1);
    }
    regions.push(englobante);
  }
  for (const m of corps.matchAll(/class="[^"]*(?:\boverlay-modale\b|\bfixed inset-0\b[^"]*\bjustify-center\b)[^"]*"/g)) {
    const debut = corps.lastIndexOf('<', m.index);
    if (debut < 0 || dedans(debut)) continue;
    let profondeur = 0;
    let fin = -1;
    const balise = /<(\/?)div\b[^>]*?(\/?)>/g;
    balise.lastIndex = debut;
    let b;
    while ((b = balise.exec(corps))) {
      if (b[2] === '/') continue;
      profondeur += b[1] ? -1 : 1;
      if (profondeur === 0) { fin = b.index + b[0].length; break; }
    }
    if (fin < 0) continue;
    const id = (corps.slice(debut, debut + 400).match(/id="([a-zA-Z0-9_-]+)"/) || [])[1];
    regions.push({ debut, fin, base: id || 'modale-ecrite', titre: null });
  }

  // Les identifiants sont attribues APRES le dedoublonnage, dans l'ordre de la
  // page : une region retiree ne doit pas decaler le nom des suivantes — la
  // dette les designe par ce nom.
  regions.sort((a, b) => a.debut - b.debut);
  const vus = new Map();
  for (const r of regions) {
    const n = (vus.get(r.base) || 0) + 1;
    vus.set(r.base, n);
    r.id = n === 1 ? r.base : r.base + '-' + n;
  }
  return regions;
}

/* ---------------------------------------------------------- pages servies */

const TOUTES_LES_VUES = fichiersSous(VUES_PWA, ['.blade.php']);
const nomDeVue = (fichier) => 'pwa.' + path.relative(VUES_PWA, fichier)
  .replace(/\\/g, '/').replace(/\.blade\.php$/, '').split('/').join('.');
const idDeVue = (nom) => nom.replace(/^pwa\./, '').split('.').join('/');

const inclusions = new Map();
for (const f of TOUTES_LES_VUES) {
  const noms = new Set();
  for (const m of sansCommentaires(lire(f)).matchAll(/@include\w*\s*\(\s*(?:[^'"]*?,\s*)?['"](pwa\.[a-z0-9_.-]+)['"]/g)) {
    noms.add(m[1]);
  }
  inclusions.set(nomDeVue(f), noms);
}
const incluses = new Set([...inclusions.values()].flatMap((s) => [...s]));

const memoCoquille = new Map();
function inclutLaCoquille(nom, pile = new Set()) {
  if (memoCoquille.has(nom)) return memoCoquille.get(nom);
  if (pile.has(nom)) return false;
  pile.add(nom);
  const enfants = inclusions.get(nom) || new Set();
  const oui = enfants.has('pwa.partials.barre-superieure')
    || [...enfants].some((e) => inclutLaCoquille(e, pile));
  memoCoquille.set(nom, oui);
  return oui;
}

// Deux pages se servent HORS coquille, et le Flutter les porte aussi : la
// connexion et l'ecran de demarrage. Liste ecrite a la main, et courte — une
// vue de plus hors coquille n'y entrera pas toute seule, d'ou le plancher.
const PAGES_HORS_COQUILLE = ['pwa.livewire.connexion', 'pwa.demarrage'];

const PAGES = TOUTES_LES_VUES.map(nomDeVue)
  .filter((n) => (inclutLaCoquille(n) && !incluses.has(n)) || PAGES_HORS_COQUILLE.includes(n))
  .sort();

if (!PAGES.length) fatal('AUCUNE vue servie trouvee : le balayage serait vert a vide.');

// La classe Livewire de chaque vue : son `#[Title]` et ses ONGLETS.
const classeDeVue = new Map();
for (const f of fichiersSous(CODE_PWA, ['.php'])) {
  for (const m of lire(f).matchAll(/view\(\s*'(pwa\.[a-z0-9_.-]+)'/g)) {
    if (!classeDeVue.has(m[1])) classeDeVue.set(m[1], f);
  }
}

/* ------------------------------------------------------- cote Flutter */

const FICHIERS_DART = fichiersSous(FLUTTER, ['.dart']);
const citeExplicite = new Map();
for (const f of FICHIERS_DART) {
  for (const m of lire(f).matchAll(/pwa\/([a-z0-9_/-]+)\.blade\.php/g)) {
    if (!citeExplicite.has(m[1])) citeExplicite.set(m[1], new Set());
    citeExplicite.get(m[1]).add(f);
  }
}
const sourceFlutter = FICHIERS_DART.map((f) => recoller(lire(f))).join(' ');

/*
 * Le CODE QU'UN ECRAN ATTEINT : ses porteurs (qui citent la vue), plus tout ce
 * qu'ils importent, transitivement, dans `lib/`. C'est contre lui seul qu'un
 * libelle de page est cherche (PA-196). Chercher dans TOUT le client faisait
 * « trouver » un libelle d'un bloc non porte dans un fichier sans rapport :
 * quatre faux positifs mesures (PA-189, PA-192, PA-193, PA-195).
 */
const cacheImports = new Map();
function importsDe(fichier) {
  if (cacheImports.has(fichier)) return cacheImports.get(fichier);
  const cibles = [];
  for (const m of lire(fichier).matchAll(/^\s*(?:import|export|part)\s+'([^']+)'/gm)) {
    const uri = m[1];
    let cible = null;
    if (uri.startsWith('package:tatacora_flutter/')) cible = path.join(FLUTTER, uri.slice('package:tatacora_flutter/'.length));
    else if (!uri.includes(':')) cible = path.resolve(path.dirname(fichier), uri);
    if (cible && fs.existsSync(cible)) cibles.push(path.normalize(cible));
  }
  cacheImports.set(fichier, cibles);
  return cibles;
}
function fermeture(departs) {
  const vus = new Set();
  const pile = [...departs].map((f) => path.normalize(f));
  while (pile.length) {
    const f = pile.pop();
    if (vus.has(f)) continue;
    vus.add(f);
    for (const c of importsDe(f)) if (!vus.has(c)) pile.push(c);
  }
  return vus;
}

const sourceServeur = fichiersSous(SERVEUR_PARTAGE, ['.php']).map((f) => recoller(lire(f))).join(' ');

if (sourceFlutter.length < 10000 || sourceServeur.length < 1000 || nbChaines < 1000) {
  fatal('Les sources sont vides ou introuvables (' + FICHIERS_DART.length + ' fichier(s) Dart, '
    + nbChaines + ' chaine(s) de langue) : rien a comparer.');
}

// Une citation qui ne designe aucune vue servie est une citation MORTE : une
// vue renommee, et l'ecran qui la citait cesse d'etre mesure sans un mot.
for (const [vue, fichiers] of citeExplicite) {
  if (PAGES.includes('pwa.' + vue.split('/').join('.'))) continue;
  if (fs.existsSync(path.join(VUES_PWA, vue + '.blade.php'))) continue;
  ecart('citation morte : `pwa/' + vue + '.blade.php` n\'existe pas, cite par '
    + [...fichiers].map((f) => path.relative(FLUTTER, f).replace(/\\/g, '/')).join(', '));
}

/* --------------------------------------------------------------- jugement */

const apercu = (absents) => (absents.length
  ? ' — ex. « ' + absents.slice(0, 3).join(' », « ') + ' »' + (absents.length > 3 ? '…' : '')
  : '');
const detailVoulu = (vue) => DETAIL === true || DETAIL === vue;
const detailsAImprimer = [];

// PHASE 0 (08/10/2026) — le DENOMINATEUR. Chaque bloc juge y laisse sa trace :
// sans lui, la dette ne dit que ce qui manque, jamais « sur combien ».
const mesures = [];
const nonPortees = [];

/** Le verdict d'un bloc, avec la dette — une seule regle pour tous. */
function juger(cle, vue, absents, total, refuse) {
  clesRencontrees.add(cle);
  mesures.push({ cle, vue, total, absents: absents.length, refuse: Boolean(refuse) });
  const du = dette[cle];
  if (refuse) {
    refus.push(cle);
    if (du !== undefined && !FIGER) {
      ecart(cle + ' : REFUSE et declare, mais la dette le compte encore. Regenerez : --figer-dette');
    }
    return;
  }
  if (detailVoulu(vue) && absents.length) detailsAImprimer.push([cle, absents]);
  if (!absents.length) {
    if (du !== undefined && !FIGER) {
      ecart(cle + ' : PORTE en entier, mais la dette le dit encore absent (' + du + '). Regenerez : --figer-dette');
    }
    return;
  }
  detteMesuree[cle] = absents.length;
  if (FIGER) return;
  if (du === undefined) {
    ecart(cle + ' : ' + absents.length + '/' + total + ' libelle(s) de la vue ni rendu(s) ni nomme(s) '
      + 'comme refuse(s)' + apercu(absents));
  } else if (absents.length > du) {
    ecart(cle + ' RECULE : ' + absents.length + ' libelle(s) absent(s) contre ' + du
      + ' a la derniere mesure' + apercu(absents));
  } else if (absents.length < du) {
    ecart(cle + ' AVANCE : ' + absents.length + ' absent(s) contre ' + du
      + ' figes. Resserrez le cliquet : --figer-dette');
  }
}

const lignes = [];
let totalLibelles = 0;
let totalModales = 0;
let totalOnglets = 0;
let absentsPortes = 0;
let portees = 0;
const titresCalcules = [];

for (const nom of PAGES) {
  const vue = idDeVue(nom);
  const brut = lire(cheminVue(nom));
  const classe = classeDeVue.get(nom);
  const sourceClasse = classe ? lire(classe) : '';

  const corps = deplier(sansCommentaires(brut), PARTIELS_CHASSIS);
  const modales = modalesDe(corps);

  // La page, ses modales BLANCHIES : elles ont leur propre verdict.
  let page = corps;
  for (const r of modales) page = page.slice(0, r.debut) + ' '.repeat(r.fin - r.debut) + page.slice(r.fin);

  // Les BLOCS : panneaux d'onglet et sections nommees.
  const blocs = [];
  for (const m of page.matchAll(/@(?:if|elseif)\s*\(/g)) {
    const fin = fermante(page, m.index + m[0].length - 1);
    if (fin < 0) continue;
    const condition = page.slice(m.index, fin);
    const c = condition.match(/\$(?:onglet\w*|panel\w*|panneau\w*|vue\w*|section\w*)\s*===?\s*'([a-z0-9_-]+)'/i)
      || condition.match(/'([a-z0-9_-]+)'\s*===?\s*\$(?:onglet\w*|panel\w*|panneau\w*|vue\w*|section\w*)/i);
    if (c) blocs.push({ debut: m.index, nom: c[1] });
  }
  for (const m of page.matchAll(/data-panneau[\w-]*="([a-z0-9_-]+)"|id="panneau-([a-z0-9_-]+)"/g)) {
    blocs.push({ debut: m.index, nom: m[1] || m[2] });
  }
  blocs.sort((a, b) => a.debut - b.debut);
  const blocDe = (position) => {
    let n = 'page';
    for (const b of blocs) {
      if (b.debut > position) break;
      n = b.nom;
    }
    return n;
  };

  const libellesPage = libellesDe(page);
  const libellesModales = modales.map((r) => ({ region: r, libelles: libellesDe(corps.slice(r.debut, r.fin)) }));

  // Le TITRE : le premier H1, ses cles resolues ; a defaut, le `#[Title]`.
  let titres = [];
  const h1 = corps.match(/<h1[^>]*>([\s\S]*?)<\/h1>/);
  if (h1) {
    for (const m of h1[1].matchAll(MOTIF_CLE)) {
      if (typeof LANGUE[m[2]] === 'string') titres.push(texteNu(LANGUE[m[2]]));
    }
    const litteral = texteNu(sansCode(h1[1]));
    if (litteral.length >= 3 && !RESTE_DE_CODE.test(litteral)) titres.push(litteral);
  }
  if (!titres.length) {
    const t = sourceClasse.match(/#\[Title\('([^']+)'\)\]/);
    if (t) titres.push(t[1].replace(/\s*—\s*(LogiReStock\s*—\s*)?TATACORA AFRIQUE\s*$/, ''));
  }
  titres = titres.filter((t) => t.length >= 3);

  // Les ONGLETS : cles de langue en `onglet*`, ou constante `ONGLETS` libellee.
  const onglets = new Set();
  for (const source of [corps, sourceClasse]) {
    for (const m of source.matchAll(MOTIF_CLE)) {
      if (!m[2].split('.').some((seg) => /^onglets?($|_)/.test(seg))) continue;
      const v = LANGUE[m[2]];
      if (typeof v === 'string' && texteNu(v).length >= 4) onglets.add(texteNu(v));
    }
  }
  const constante = sourceClasse.match(/const\s+ONGLETS\s*=\s*\[([\s\S]*?)\];/);
  if (constante) {
    for (const m of constante[1].matchAll(/'[^']*'\s*=>\s*'([^']+)'/g)) onglets.add(m[1]);
  }

  totalLibelles += libellesPage.size + libellesModales.reduce((s, x) => s + x.libelles.size, 0);
  totalModales += modales.length;
  totalOnglets += onglets.size;

  // Qui porte cette vue cote Flutter ? Ceux qui la CITENT, et eux seuls.
  const porteurs = citeExplicite.get(vue) || new Set();

  const ligne = {
    vue, portee: porteurs.size > 0, onglets: onglets.size, modales: modales.length,
    titre: '—', ongletsPortes: '—', modalesPortees: '—', absents: '—',
  };
  lignes.push(ligne);
  if (!porteurs.size) {
    nonPortees.push({
      vue,
      total: libellesPage.size + libellesModales.reduce((s, x) => s + x.libelles.size, 0)
        + onglets.size + (titres.length ? 1 : 0),
    });
    continue;
  }
  portees += 1;

  const serveur = sourceFlutter.includes('libelles-du-serveur:' + vue);
  // Le code que l'ecran ATTEINT, pas l'arbre entier (PA-196) — voir l'entete.
  const declarantsPage = FICHIERS_DART.filter((f) => lire(f).includes('blade-refuse:' + vue + '#'));
  let sourcePage = [...fermeture([...porteurs, ...declarantsPage])].map((f) => recoller(lire(f))).join(' ');
  if (serveur) sourcePage += ' ' + sourceServeur;
  const refuse = (bloc) => sourceFlutter.includes('blade-refuse:' + vue + '#' + bloc);
  let absentsVue = 0;

  // Titre.
  if (!titres.length) {
    titresCalcules.push(vue);
    ligne.titre = 'calcule';
  } else {
    const trouve = titres.some((t) => sourcePage.includes(t));
    ligne.titre = trouve ? 'oui' : 'NON';
    const absents = trouve ? [] : [titres[0]];
    absentsVue += absents.length;
    juger(vue + '|titre', vue, absents, 1, refuse('titre'));
  }

  // Onglets.
  const ongletsAbsents = [...onglets].filter((o) => !sourcePage.includes(o));
  ligne.ongletsPortes = (onglets.size - ongletsAbsents.length) + '/' + onglets.size;
  if (onglets.size) {
    absentsVue += ongletsAbsents.length;
    juger(vue + '|onglets', vue, ongletsAbsents, onglets.size, refuse('onglets'));
  }

  // Blocs de la page.
  const parBloc = new Map();
  for (const [texte, position] of libellesPage) {
    const b = blocDe(position);
    if (!parBloc.has(b)) parBloc.set(b, { total: 0, absents: [] });
    const g = parBloc.get(b);
    g.total += 1;
    if (!sourcePage.includes(texte)) g.absents.push(texte);
  }
  for (const [b, g] of parBloc) {
    absentsVue += g.absents.length;
    juger(vue + '|' + b, vue, g.absents, g.total, refuse(b));
  }

  // Modales : confrontees au seul code qui porte la vue, plus ses declarants.
  const declarants = FICHIERS_DART.filter((f) => lire(f).includes('blade-refuse:' + vue + '#'));
  let sourceModales = [...new Set([...porteurs, ...declarants])].map((f) => recoller(lire(f))).join(' ');
  if (serveur) sourceModales += ' ' + sourceServeur;
  let modalesPortees = 0;
  for (const { region, libelles } of libellesModales) {
    const absents = [...libelles.keys()].filter((t) => !sourceModales.includes(t));
    if (!absents.length) modalesPortees += 1;
    absentsVue += absents.length;
    juger(vue + '|modale:' + region.id, vue, absents, libelles.size, refuse('modale:' + region.id));
  }
  ligne.modalesPortees = modalesPortees + '/' + modales.length;
  ligne.absents = absentsVue;
  absentsPortes += absentsVue;
}

/* ----------------------------------------------------------------- chassis */

const libellesChassis = new Map();
function ajouterAuChassis(bloc, libelles) {
  if (!libellesChassis.has(bloc)) libellesChassis.set(bloc, new Set());
  for (const t of libelles) libellesChassis.get(bloc).add(t);
}

// Chaque partiel du chassis est deplie SANS les autres : la barre superieure
// inclut la banniere, et la deplier ici la comptait deux fois — une fois dans
// le menu de compte, une fois pour elle-meme (mesure le 10/09/2026).
const barre = deplier(sansCommentaires(lire(cheminVue('pwa.partials.barre-superieure'))), PARTIELS_CHASSIS);
const menuProfil = barre.indexOf('id="menu-profil"');
const libellesBarre = libellesDe(barre);
ajouterAuChassis('barre-superieure', [...libellesBarre].filter(([, i]) => menuProfil < 0 || i < menuProfil).map(([t]) => t));
ajouterAuChassis('menu-compte', [...libellesBarre].filter(([, i]) => menuProfil >= 0 && i >= menuProfil).map(([t]) => t));

for (const partiel of ['menu-lateral', 'entree-menu', 'banniere', 'acces-rapide']) {
  const source = deplier(sansCommentaires(lire(cheminVue('pwa.partials.' + partiel))), PARTIELS_CHASSIS);
  ajouterAuChassis(partiel === 'entree-menu' ? 'menu-lateral' : partiel, libellesDe(source).keys());
}

// La barre laterale : ses libelles vivent dans `MenuLateral::NAVIGATION`.
const navigation = (lire(MENU_LATERAL).match(/const\s+NAVIGATION\s*=\s*\[([\s\S]*?)\n\s{4}\];/) || [])[1] || '';
const libellesMenu = [];
for (const m of navigation.matchAll(/'(?:nom|groupe|badge)'\s*=>\s*'([^']+)'/g)) {
  for (const s of suitesDeTexte(m[1])) libellesMenu.push(s);
  // Les entrees courtes (« Bar », « Stocks ») sont sous le plancher de cinq
  // caracteres : on les garde ici, parce qu'une entree de menu n'est pas une
  // coincidence — c'est un nom exact, a sa place.
  if (m[1].length < 5 && m[1].length >= 3) libellesMenu.push(m[1]);
}
ajouterAuChassis('menu-lateral', libellesMenu);

// Les composants Livewire montes sur TOUTES les pages : par la barre
// superieure (recherche, cloche) et par le gabarit (verrou, alertes).
const montes = new Set();
for (const source of [lire(cheminVue('pwa.partials.barre-superieure')), lire(GABARIT)]) {
  for (const m of source.matchAll(/<livewire:([a-z0-9_.-]+)/g)) montes.add(m[1].split('.').pop());
}
for (const nom of montes) {
  const fichier = TOUTES_LES_VUES.find((f) => path.basename(f) === nom + '.blade.php');
  if (!fichier) continue;
  ajouterAuChassis(nom, libellesDe(deplier(sansCommentaires(lire(fichier)), new Set())).keys());
}

let totalChassis = 0;
for (const [bloc, libelles] of libellesChassis) {
  totalChassis += libelles.size;
  const absents = [...libelles].filter((t) => !sourceFlutter.includes(t));
  juger('chassis|' + bloc, 'chassis', absents, libelles.size,
    sourceFlutter.includes('blade-refuse:chassis#' + bloc));
}

/* ------------------------------------------- ecrans Flutter sans vue Blade */

// Un ecran Flutter qui ne cite AUCUNE vue est un ecran que la PWA n'a pas —
// interdit n. 07 de l'Article 1, sauf ecart declare. Rapporte, pas compte :
// les deux premiers ont ete ajoutes avant la decision du 10/09/2026, et c'est
// au Product Owner de dire s'ils restent.
const ecransOrphelins = FICHIERS_DART
  .filter((f) => /[\\/]ecran_[a-z0-9_]+\.dart$/.test(f))
  .filter((f) => !/pwa\/[a-z0-9_/-]+\.blade\.php/.test(lire(f)))
  .map((f) => path.relative(FLUTTER, f).replace(/\\/g, '/'))
  .sort();

/* ------------------------------------------------ PHASE 0 : trois taux
   Trois taux, calcules sur TOUS les libelles du maitre (titre, onglets,
   blocs, modales), vues non portees comprises :
     - STRICT      = libelles reellement presents ÷ total. Aucune exemption :
                     un bloc refuse compte comme NON rendu.
     - ASSUME      = (presents + blocs refuses et declares) ÷ total.
     - NON PORTE   = (absents hors refus + vues sans ecran) ÷ total.
   STRICT + ASSUME-STRICT + NON PORTE = 100 %. Le chassis (barres) est
   rapporte a part : il n'appartient a aucune page.
   Classes d'exemption : (a) assumee — refus argumente et date, enregistre
   dans classification-exemptions.json ; (b) non portee — la dette et les
   vues sans ecran ; (c) oubli — un ecran Flutter sans vue, jamais decide ;
   (d) ajout du PO — un ecran Flutter sans vue, DECIDE par le Product Owner
   (motif et date, `ajouts` du meme fichier). */

const CHEMIN_CLASSES = path.join(__dirname, 'classification-exemptions.json');
const CHEMIN_TABLE = path.join(__dirname, 'table-vue-ecran.json');
const CHEMIN_PLANCHER = path.join(__dirname, 'plancher-taux.json');

const pages = mesures.filter((m) => m.vue !== 'chassis');
const chassisMesures = mesures.filter((m) => m.vue === 'chassis');
const sommeTotal = (l) => l.reduce((s, m) => s + m.total, 0);
const totalPortees = sommeTotal(pages);
const totalNonPortees = nonPortees.reduce((s, v) => s + v.total, 0);
const totalMaitre = totalPortees + totalNonPortees;
const presents = pages.filter((m) => !m.refuse).reduce((s, m) => s + m.total - m.absents, 0);
const refuses = sommeTotal(pages.filter((m) => m.refuse));
const absentsHorsRefus = pages.filter((m) => !m.refuse).reduce((s, m) => s + m.absents, 0);
const pct = (n) => (totalMaitre ? Math.round((n / totalMaitre) * 10000) / 100 : 0);
const taux = {
  strict: pct(presents),
  assume: pct(presents + refuses),
  nonPorte: pct(absentsHorsRefus + totalNonPortees),
};
const presentsChassis = chassisMesures.filter((m) => !m.refuse).reduce((s, m) => s + m.total - m.absents, 0);
const tauxChassis = sommeTotal(chassisMesures)
  ? Math.round((presentsChassis / sommeTotal(chassisMesures)) * 10000) / 100 : 0;

// La classification : chaque refus porte un motif DATE, ou la garde echoue.
const classes = fs.existsSync(CHEMIN_CLASSES)
  ? JSON.parse(fs.readFileSync(CHEMIN_CLASSES, 'utf8'))
  : { assumees: {}, oublis: {} };
const aOublier = new Set(ecransOrphelins);
if (!FIGER) {
  for (const cle of refus) {
    const c = (classes.assumees || {})[cle];
    if (!c || c.classe !== 'a' || !c.motif || c.motif.length < 30 || !/^\d{4}-\d{2}-\d{2}$/.test(c.date || '')) {
      ecart(cle + ' : refus declare SANS classification (a) motivee et datee dans '
        + path.basename(CHEMIN_CLASSES));
    }
  }
  for (const cle of Object.keys(classes.assumees || {})) {
    if (!refus.includes(cle)) ecart('classification perimee : « ' + cle + ' » n\'est plus un refus declare.');
  }
  for (const f of Object.keys(classes.oublis || {})) {
    if (!aOublier.has(f)) ecart('oubli perime : « ' + f + ' » n\'est plus un ecran sans vue.');
  }
  // (d) AJOUT DU PO : un ecran sans vue que le Product Owner a DECIDE (date,
  // motif). Meme exigence qu'un refus (a) : motif de 30 caracteres au moins,
  // date ISO ; une entree dont l'ecran a disparu ou cite desormais une vue est
  // perimee. Depuis le 15/10/2026, un ecran sans vue qui n'est ni un oubli
  // liste (c) ni un ajout declare (d) fait ECHOUER la garde : il n'est plus
  // seulement rapporte.
  for (const [f, c] of Object.entries(classes.ajouts || {})) {
    if (!aOublier.has(f)) ecart('ajout perime : « ' + f + ' » n\'est plus un ecran sans vue.');
    if (!c || c.classe !== 'd' || !c.motif || c.motif.length < 30 || !/^\d{4}-\d{2}-\d{2}$/.test(c.date || '')) {
      ecart(f + ' : ajout du PO SANS classification (d) motivee et datee dans '
        + path.basename(CHEMIN_CLASSES));
    }
  }
  for (const f of ecransOrphelins) {
    if (!(f in (classes.oublis || {})) && !(f in (classes.ajouts || {}))) {
      ecart('ecran sans vue NON declare : « ' + f + ' ». Ajout du PO -> `ajouts` (d), '
        + 'sinon `oublis` (c), dans ' + path.basename(CHEMIN_CLASSES) + '.');
    }
  }
}
const ajoutsDeclares = ecransOrphelins.filter((f) => f in (classes.ajouts || {}));
const classeOubli = ecransOrphelins.length - ajoutsDeclares.length;

// La table vue -> ecran : explicite, versionnee, comparee a la mesure.
const tableMesuree = {};
for (const l of lignes) {
  const f = citeExplicite.get(l.vue);
  tableMesuree[l.vue] = f ? [...f].map((x) => path.relative(FLUTTER, x).replace(/\\/g, '/')).sort() : [];
}
if (!FIGER) {
  const tableLue = fs.existsSync(CHEMIN_TABLE) ? JSON.parse(fs.readFileSync(CHEMIN_TABLE, 'utf8')).vues : null;
  if (!tableLue) {
    ecart('table vue -> ecran introuvable (' + path.basename(CHEMIN_TABLE) + '). Regenerez : --figer-dette');
  } else {
    for (const v of Object.keys(tableMesuree)) {
      if (JSON.stringify(tableLue[v]) !== JSON.stringify(tableMesuree[v])) {
        ecart('table vue -> ecran : « ' + v + ' » differe de la mesure. Regenerez : --figer-dette');
      }
    }
    for (const v of Object.keys(tableLue)) {
      if (!(v in tableMesuree)) ecart('table vue -> ecran : « ' + v + ' » n\'est plus une vue servie.');
    }
  }
  // Cliquet du taux strict : il ne peut que monter.
  const plancher = fs.existsSync(CHEMIN_PLANCHER) ? JSON.parse(fs.readFileSync(CHEMIN_PLANCHER, 'utf8')).strict : null;
  if (plancher === null) {
    ecart('plancher du taux strict introuvable (' + path.basename(CHEMIN_PLANCHER) + '). Regenerez : --figer-dette');
  } else if (taux.strict < plancher) {
    ecart('taux STRICT en baisse : ' + taux.strict + ' % contre ' + plancher + ' % fige.');
  } else if (taux.strict > plancher) {
    ecart('taux STRICT en hausse : ' + taux.strict + ' % contre ' + plancher + ' % figes. Resserrez : --figer-dette');
  }
}

/* -------------------------------------------------------- dette : cloture */

if (!FIGER) {
  for (const cle of Object.keys(dette)) {
    if (clesRencontrees.has(cle)) continue;
    ecart('dette perimee : « ' + cle + ' » ne correspond plus a aucun bloc mesure. '
      + 'Regenerez : --figer-dette');
  }
}

if (FIGER) {
  const trie = {};
  for (const c of Object.keys(detteMesuree).sort()) trie[c] = detteMesuree[c];
  fs.writeFileSync(CHEMIN_DETTE, JSON.stringify({
    '_lisez-moi': 'PRODUIT par `node tool/conformite_blade/t-blade-flutter.js --figer-dette`, '
      + 'jamais ecrit a la main. Chaque cle est « vue|bloc », chaque valeur le NOMBRE de '
      + 'libelles de la vue Blade absents du code Flutter. Le script echoue si un chiffre '
      + 'monte, s\'il baisse sans que la dette soit resserree, si un bloc incomplet n\'y '
      + 'figure pas, et si une entree ne correspond plus a rien ou a un bloc desormais '
      + 'porte ou refuse.',
    '_regenere-le': new Date().toISOString().slice(0, 10),
    '_blocs-a-porter': Object.keys(trie).length,
    '_libelles-absents': Object.values(trie).reduce((s, n) => s + n, 0),
    ecarts: trie,
  }, null, 2) + '\n', 'utf8');
  fs.writeFileSync(CHEMIN_TABLE, JSON.stringify({
    '_lisez-moi': 'PRODUIT par --figer-dette. Vue Blade -> fichiers Flutter qui la CITENT (seul ancrage). '
      + 'Un tableau vide = vue sans ecran.',
    '_regenere-le': new Date().toISOString().slice(0, 10),
    vues: tableMesuree,
  }, null, 2) + '\n', 'utf8');
  fs.writeFileSync(CHEMIN_PLANCHER, JSON.stringify({
    '_lisez-moi': 'PRODUIT par --figer-dette. Cliquet du taux STRICT (aucune exemption).',
    '_regenere-le': new Date().toISOString().slice(0, 10),
    strict: taux.strict,
  }, null, 2) + '\n', 'utf8');
  console.log('  Dette figee : ' + Object.keys(trie).length + ' bloc(s), '
    + Object.values(trie).reduce((s, n) => s + n, 0) + ' libelle(s) absent(s), ecrite dans '
    + path.basename(CHEMIN_DETTE) + '\n');
  process.exit(0);
}

/* --------------------------------------------------------------- planchers
   Une garde qui ne trouve plus rien a comparer passe A VIDE. Mesure du
   10/09/2026 : 43 vues, 2 911 libelles, 101 modales, 70 onglets, 93 libelles
   de chassis (PA-182). Les planchers sont poses juste dessous : s'ils sont
   franchis, c'est l'EXTRACTION qui s'est cassee (un motif retouche, un
   dossier renomme), pas la PWA qui a maigri.
   ------------------------------------------------------------------------ */
const PLANCHER_PAGES = 40;
const PLANCHER_LIBELLES = 2750;
const PLANCHER_MODALES = 95;
const PLANCHER_ONGLETS = 65;
const PLANCHER_CHASSIS = 85;

if (PAGES.length < PLANCHER_PAGES) {
  ecart('seules ' + PAGES.length + ' vues servies trouvees, sous le plancher de ' + PLANCHER_PAGES
    + ' : le balayage ne couvre plus la PWA.');
}
if (totalLibelles < PLANCHER_LIBELLES) {
  ecart('seuls ' + totalLibelles + ' libelles extraits, sous le plancher de ' + PLANCHER_LIBELLES
    + ' : l\'extraction est cassee, pas la PWA.');
}
if (totalModales < PLANCHER_MODALES) {
  ecart('seules ' + totalModales + ' modales extraites, sous le plancher de ' + PLANCHER_MODALES + '.');
}
if (totalOnglets < PLANCHER_ONGLETS) {
  ecart('seuls ' + totalOnglets + ' onglets extraits, sous le plancher de ' + PLANCHER_ONGLETS + '.');
}
if (totalChassis < PLANCHER_CHASSIS) {
  ecart('seuls ' + totalChassis + ' libelles de chassis extraits, sous le plancher de '
    + PLANCHER_CHASSIS + '.');
}

/* ------------------------------------------------------------------ sortie */

const large = (s, n) => String(s).padEnd(n).slice(0, n);
console.log('\n  ' + large('VUE BLADE (resources/views/pwa/)', 36) + large('TITRE', 9)
  + large('ONGLETS', 9) + large('MODALES', 9) + large('FLUTTER', 9) + 'ABSENTS');
console.log('  ' + '-'.repeat(80));
for (const l of lignes) {
  console.log('  ' + large(l.vue, 36) + large(l.titre, 9)
    + large(l.portee ? l.ongletsPortes : (l.onglets || ''), 9)
    + large(l.portee ? l.modalesPortees : (l.modales || ''), 9)
    + large(l.portee ? 'oui' : '—', 9) + l.absents);
}

for (const [cle, absents] of detailsAImprimer) {
  console.log('\n  ' + cle + ' — ' + absents.length + ' absent(s) :');
  for (const a of absents) console.log('    · ' + a);
}

if (refus.length) {
  console.log('\n  ' + refus.length + ' bloc(s) de la vue REFUSE(S), declares dans le code Flutter :');
  for (const r of refus) console.log('    - ' + r);
}
if (titresCalcules.length) {
  console.log('\n  ' + titresCalcules.length + ' vue(s) au titre CALCULE, que ce controle ne peut '
    + 'confronter : ' + titresCalcules.join(', '));
}
if (ecransOrphelins.length) {
  console.log('\n  ' + ecransOrphelins.length + ' ecran(s) Flutter SANS vue Blade (ajouts a declarer '
    + 'ou a retirer) :');
  for (const e of ecransOrphelins) {
    const a = (classes.ajouts || {})[e];
    console.log('    - ' + e + (a ? '  [ajout du PO (d), ' + a.date + ']' : ''));
  }
}

console.log('\n  ' + PAGES.length + ' vue(s) Blade servies, ' + totalOnglets + ' onglet(s), '
  + totalModales + ' modale(s), ' + totalLibelles + ' libelle(s) extraits');
console.log('  ' + totalChassis + ' libelle(s) de chassis, ' + nbChaines + ' chaine(s) de langue resolues par PHP');
console.log('  ' + portees + ' portee(s) cote Flutter (vue citee)');
console.log('  ' + absentsPortes + ' libelle(s) de la vue absent(s) du Flutter sur les vues portees'
  + ' (dette figee le ' + ((detteLue && detteLue['_regenere-le']) || '?') + ')');
console.log('\n  \x1b[1mTROIS TAUX\x1b[0m sur ' + totalMaitre + ' libelles du maitre (' + totalPortees
  + ' sur vues portees, ' + totalNonPortees + ' sur ' + nonPortees.length + ' vues sans ecran) :');
console.log('    STRICT     ' + taux.strict.toFixed(2) + ' %   (presents, aucune exemption)');
console.log('    ASSUME     ' + taux.assume.toFixed(2) + ' %   (presents + refus declares, classe a)');
console.log('    NON PORTE  ' + taux.nonPorte.toFixed(2) + ' %   (classe b : dette + vues sans ecran)');
console.log('    chassis    ' + tauxChassis.toFixed(2) + ' %   (barres, rapporte a part)');
console.log('    exemptions : ' + refus.length + ' (a) assumee(s), ' + classeOubli
  + ' (c) oubli(s) = ecrans sans vue, ' + ajoutsDeclares.length + ' (d) ajout(s) du PO, le reste (b)\n');

if (echecs > 0) {
  console.log('\x1b[1;31m  BLADE -> FLUTTER : ECHEC\x1b[0m — ' + echecs + ' ecart(s)\n');
  process.exit(1);
}
console.log('\x1b[1;32m  BLADE -> FLUTTER : PASS\x1b[0m — rien n\'a recule depuis la derniere mesure ;'
  + '\n  la dette ci-dessus est ce qui RESTE a porter, pas ce qui est conforme.\n');

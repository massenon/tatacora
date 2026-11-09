# LogiRestock — Manuel d'utilisation

| | |
|---|---|
| **Rôle** | Manuel d'utilisation destiné au personnel du Gîte Chez Noël |
| **Éditeur du logiciel** | Dr MASSENON Rhodes, Docteur en Génie Logiciel et Intelligence Artificielle |
| **Maîtrise d'œuvre** | FAGUEZ SARL — accompagnement des PME dans le cadre du PAEB |
| **Statut** | LogiRestock 1.0.0 — édition de novembre 2026 (mise à jour complète, chapitres 15 à 19 ajoutés) ; l'édition de septembre 2026 avait été approuvée en séance par le Promoteur et le Comptable, la présente édition ne l'a pas encore été |
| **Livrable** | `MANUEL_UTILISATION_LOGIRESTOCK.pdf` (166 pages au 09/11/2026, couverture comprise — 165 numérotées ; `generer.js` affiche le nombre exact) |
| **Source documentée** | ⚠ **La PWA de `tatacora-api`** depuis le 14/09/2026 — les écrans réellement servis, capturés en session sur le serveur. `prototype_v2/` était la source jusque-là : il est **archivé depuis le 10/09/2026** (PA-183) et le manuel montrait donc une interface qui ne fait plus foi. |

---

## 1. Ce que contient ce dossier

| Chemin | Contenu |
|---|---|
| `MANUEL_UTILISATION_LOGIRESTOCK.pdf` | Le livrable. |
| `src/part-01.html` … `part-14.html` | Le texte du manuel (chapitres 1 à 19 et annexes A et B), découpé par lots de chapitres : `part-01` couverture et avant-propos, `part-02` sommaire, `part-03` à `part-09` chapitres 1 à 14 et annexes A et B, `part-10` à `part-14` chapitres 15 à 19 (poste Windows, synchronisation, facturation normalisée, proforma, comptes). |
| `CAPTURES_A_PRENDRE.md` | Les 19 captures du poste Windows des chapitres 15 à 19 : 17 sont intégrées (rendus du poste par le moteur Flutter, à confirmer par le PO sur Windows) ; **2 restent en cadre pointillé, à prendre par le PO** (assistant d'installation et avertissement de désinstallation, fenêtres Inno Setup), avec le nom de fichier attendu et la façon de les prendre. `CAPTURES_A_PRENDRE_CHAP1-6.md` et `_CHAP7-14.md` portent le statut de chaque capture PWA (fait / non prise). |
| `src/style.css` | La charte graphique appliquée au document (marine `#14213D`, or `#B8891E`, police Inter — les valeurs de `prototype_v2/assets/css/app.css`). |
| `src/img/` | Les captures ré-encodées en JPEG à la génération. **Dérivé** : supprimez le dossier pour forcer sa reconstruction. |
| `captures/*.png` | Les captures d'écran d'origine (1440 px, facteur 2), produites depuis le prototype. |
| `assets/` | Logo, photo de couverture et polices Inter, copiés de `prototype_v2/assets/`. |
| `capturer-nouveautes.js` | Produit les captures PWA ajoutées en novembre 2026 (`x-*.png`, `pwa-*.png` : chapitres 7 à 13 et écrans voisins du poste). **À ne lancer que sur une base jetable** : il crée et modifie des données (clôture d'un exercice d'essai, réinitialisation de la fenêtre, brouillons de proforma, comptes). Jamais sur la base d'exploitation. |
| `capturer.js` | Produit une capture par écran **de la PWA**, en session réelle (63 figures, modales comprises). |
| `inspecter.js` | Relève les points d'ancrage réellement rendus par chaque écran — ce sur quoi `annoter.js` pose ses repères. Écrit sur un sélecteur DEVINÉ, une annotation se pose à côté, ou sur la mauvaise fenêtre. |
| `annoter.js` | Produit les captures **annotées** — cadres et pastilles rouges numérotées. |
| `generer.js` | Assemble le HTML, pagine, appose l'en-tête et le pied de page, écrit le PDF. |

## 2. Régénérer le PDF

Prérequis : Node, Google Chrome installé, et deux modules — `puppeteer-core` et `pdf-lib` —
installés dans un dossier quelconque, désigné par `PPTR_DIR` :

```bash
mkdir -p ~/outils-pdf && cd ~/outils-pdf && npm init -y && npm i puppeteer-core pdf-lib

cd /c/Projects/tatacora_laravel/manuel_utilisation
PPTR_DIR=~/outils-pdf node generer.js
```

Le script affiche le nombre de pages de chaque section, la page de départ de chaque chapitre
(celle qu'imprime le sommaire) et le poids du PDF.

## 3. Régénérer les captures d'écran

À faire **après toute modification d'un écran du prototype**, sinon le manuel montre l'ancienne
interface :

```bash
PPTR_DIR=~/outils-pdf node capturer.js   # les 49 écrans, un fichier par écran
PPTR_DIR=~/outils-pdf node annoter.js    # les 13 captures annotées (a-*.png)
rm -rf src/img                           # force le ré-encodage JPEG
PPTR_DIR=~/outils-pdf node generer.js
```

Les deux scripts démarrent un serveur local sur `prototype_v2/`, se connectent réellement avec
le compte administrateur, laissent les jeux de démonstration s'amorcer, puis capturent chaque
page. Une capture prise sans session afficherait l'écran de connexion à la place du module.

**Procédure de prise de vues (09/11/2026).** Jamais sur la base de développement : une base `tatacora_capt` jetable, un utilisateur MySQL jetable, un `.env.local` hors dépôt (valeurs inventées, `APP_ENV=local`), `migrate:fresh` + `db:seed` + `DemonstrationSeeder` + `ComptesReelsSeeder`, `php artisan serve`, Chromium de `/opt/pw-browsers`, `PPTR_DIR=/tmp/outils-pdf` ; tout est supprimé ensuite (serveur, base, utilisateur, `.env.local`, archives de clôture générées). Pour la colonne N−1 du bilan (`x-compta-bilan-n1`), un exercice 2025 d'essai (trois pièces) est clôturé avant la prise de vues. **Piège** : `capturer.js` écrit aussi `a-connexion.png` en version non annotée ; relancer ensuite `FIGURES=a-connexion node annoter.js` pour retrouver les trois repères.

### Figures

Une figure est `<figure><img src="../captures/NOM.png" alt="…"><figcaption><b>Figure N.M</b> — …</figcaption></figure>` ;
`generer.js` remplace `../captures/NOM.png` par `img/NOM.jpg` (JPEG 1400 px, dans `src/img/`, versionné). Les captures plein écran
des ajouts de novembre 2026 portent `class="compact"` (hauteur plafonnée à 88 mm, 70 mm avec `petit`) pour tenir deux par page.
La numérotation « Figure N.M » suit l'ordre du chapitre ; elle a été recalculée aux chapitres 7 à 10 et 13 lors de l'ajout des
figures `x-*` (les fichiers `CAPTURES_A_PRENDRE*.md` citent encore les anciens numéros). Les figures du poste Windows (chapitres 15 à 19, plus 7.4 et 9.11) sont des **rendus Flutter** et le disent dans leur légende ; restent en pointillés `c15-installateur-assistant` (15.1) et `c15-desinstallation-avertissement` (15.3), à prendre par le PO sur Windows. Les captures PWA de connexion, de réception et de comptabilité ont été reprises le 09/11/2026 (bilan équilibré après la correction du compte 443).

## 4. Ordre des sections : les annexes ferment toujours le manuel

`generer.js` lit les fichiers `src/part-NN.html` dans l'ordre alphabétique, puis les découpe en sections au
marqueur `<!-- ===== CHAPITRE / ANNEXE / AVANT-PROPOS / SOMMAIRE -->`. Depuis novembre 2026, il **range les
annexes (id `annexe…`) en dernier**, quel que soit le fichier qui les porte : les chapitres 15 et suivants
(`part-10.html` et au-delà) s'insèrent donc avant les annexes A et B, qui restent dans `part-09.html`.
Pour ajouter un chapitre : créer `part-NN.html` (numéro supérieur), y poser
`<section class="chapitre" id="chN">`, puis ajouter l'entrée du sommaire dans `part-02.html`
(`<span class="p" data-ref="chN">` : le numéro de page est calculé par le générateur, pas saisi).

## 5. Deux choix de fabrication à connaître avant d'y toucher

**Chaque section est rendue dans son propre PDF, puis les PDF sont assemblés.** Un rendu global
donnait deux défauts : des chapitres qui ne commençaient pas sur une page neuve — Chrome
abandonne les `page-break-before` sur un document de cette taille — et, par voie de conséquence,
un sommaire faux. Le rendu par section garantit les deux par construction : la page de départ
d'un chapitre est la somme des pages qui le précèdent.

**L'en-tête et le pied de page sont apposés après l'assemblage, page par page** (`pdf-lib`).
Les gabarits d'en-tête de Chrome numérotent *par document* : la pagination serait repartie à 1
à chaque chapitre. La couverture, elle, n'est pas numérotée — elle est la seule page sans
en-tête ni pied.

## 6. Mise à jour du texte

Le manuel décrit l'interface **telle qu'elle est**, y compris ce qu'elle refuse de faire ou ne
fait pas encore (état de novembre 2026) : l'e-mail est le seul canal de notification qui part
(adresse connue et SMTP configuré ; WhatsApp et SMS : aucun contrat) ; la facturation normalisée
(e-MECeF, boîtier CC300) existe mais le mode livré est « Désactivé » et rien n'est éprouvé sur le
terrain ; le résultat comptable est « avant impôt » tant que la classe 89 est vide ; le coût
employeur dépend du taux CNSS « risques professionnels » saisi dans Paramètres. Ces mentions ne
sont pas des réserves de rédaction : elles sont écrites à l'écran et le manuel les reprend. Si
l'une d'elles disparaît de l'application, elle doit disparaître du manuel — et inversement.

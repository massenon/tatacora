# LogiRestock — Manuel d'utilisation

| | |
|---|---|
| **Rôle** | Manuel d'utilisation destiné au personnel du Gîte Chez Noël |
| **Éditeur du logiciel** | Dr MASSENON Rhodes, Docteur en Génie Logiciel et Intelligence Artificielle |
| **Maîtrise d'œuvre** | FAGUEZ SARL — accompagnement des PME dans le cadre du PAEB |
| **Statut** | LogiRestock 1.0.0 — édition de novembre 2026 (mise à jour complète, chapitres 15 à 19 ajoutés) ; l'édition de septembre 2026 avait été approuvée en séance par le Promoteur et le Comptable, la présente édition ne l'a pas encore été |
| **Livrable** | `MANUEL_UTILISATION_LOGIRESTOCK.pdf` (le nombre de pages est affiché par `generer.js`) |
| **Source documentée** | ⚠ **La PWA de `tatacora-api`** depuis le 14/09/2026 — les écrans réellement servis, capturés en session sur le serveur. `prototype_v2/` était la source jusque-là : il est **archivé depuis le 10/09/2026** (PA-183) et le manuel montrait donc une interface qui ne fait plus foi. |

---

## 1. Ce que contient ce dossier

| Chemin | Contenu |
|---|---|
| `MANUEL_UTILISATION_LOGIRESTOCK.pdf` | Le livrable. |
| `src/part-01.html` … `part-14.html` | Le texte du manuel, découpé par lots de chapitres : `part-01` couverture et avant-propos, `part-02` sommaire, `part-03` à `part-09` chapitres 1 à 14 et annexes A et B, `part-10` à `part-14` chapitres 15 à 19 (poste Windows, synchronisation, facturation normalisée, proforma, comptes). |
| `CAPTURES_A_PRENDRE.md` | Les 19 captures du poste Windows qui manquent aux chapitres 15 à 19 (figures `emplacement` en pointillés), avec le nom de fichier attendu et la façon de les prendre. |
| `src/style.css` | La charte graphique appliquée au document (marine `#14213D`, or `#B8891E`, police Inter — les valeurs de `prototype_v2/assets/css/app.css`). |
| `src/img/` | Les captures ré-encodées en JPEG à la génération. **Dérivé** : supprimez le dossier pour forcer sa reconstruction. |
| `captures/*.png` | Les captures d'écran d'origine (1440 px, facteur 2), produites depuis le prototype. |
| `assets/` | Logo, photo de couverture et polices Inter, copiés de `prototype_v2/assets/`. |
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

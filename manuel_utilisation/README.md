# LogiRestock — Manuel d'utilisation

| | |
|---|---|
| **Rôle** | Manuel d'utilisation destiné au personnel du Gîte Chez Noël |
| **Éditeur du logiciel** | Dr MASSENON Rhodes, Docteur en Génie Logiciel et Intelligence Artificielle |
| **Maîtrise d'œuvre** | FAGUEZ SARL — accompagnement des PME dans le cadre du PAEB |
| **Statut** | LogiRestock 1.0.0 — Septembre 2026, approuvé en séance par le Promoteur et le Comptable |
| **Livrable** | `MANUEL_UTILISATION_LOGIRESTOCK.pdf` — 75 pages A4 |
| **Source documentée** | ⚠ **La PWA de `tatacora-api`** depuis le 14/09/2026 — les écrans réellement servis, capturés en session sur le serveur. `prototype_v2/` était la source jusque-là : il est **archivé depuis le 10/09/2026** (PA-183) et le manuel montrait donc une interface qui ne fait plus foi. |

---

## 1. Ce que contient ce dossier

| Chemin | Contenu |
|---|---|
| `MANUEL_UTILISATION_LOGIRESTOCK.pdf` | Le livrable. |
| `src/part-01.html` … `part-09.html` | Le texte du manuel, découpé par lots de chapitres. |
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

## 4. Deux choix de fabrication à connaître avant d'y toucher

**Chaque section est rendue dans son propre PDF, puis les PDF sont assemblés.** Un rendu global
donnait deux défauts : des chapitres qui ne commençaient pas sur une page neuve — Chrome
abandonne les `page-break-before` sur un document de cette taille — et, par voie de conséquence,
un sommaire faux. Le rendu par section garantit les deux par construction : la page de départ
d'un chapitre est la somme des pages qui le précèdent.

**L'en-tête et le pied de page sont apposés après l'assemblage, page par page** (`pdf-lib`).
Les gabarits d'en-tête de Chrome numérotent *par document* : la pagination serait repartie à 1
à chaque chapitre. La couverture, elle, n'est pas numérotée — elle est la seule page sans
en-tête ni pied.

## 5. Mise à jour du texte

Le manuel décrit l'interface **telle qu'elle est**, y compris ce qu'elle refuse de faire :
l'envoi des notifications (RG-20, aucun canal contracté), la certification MECeF (inscription
DGI non effectuée), la clôture comptable (taux d'IS non arrêté) et le coût employeur (taux CNSS
risques professionnels non confirmé). Ces mentions ne sont pas des réserves de rédaction : elles
sont écrites à l'écran et le manuel les reprend. Si l'une d'elles disparaît de l'application,
elle doit disparaître du manuel — et inversement.

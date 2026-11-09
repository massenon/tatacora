# Guide des modèles d'import Excel (carte du Gîte Chez Noël)

Mis à jour le 09/11/2026. Les trois modèles préremplis sont dans `docs/data/` (copies
identiques octet pour octet dans `tatacora-flutter/assets/import/`, relues par un test) :

| Fichier | Contenu | Ordre |
|---|---|---|
| `modele_import_m6-stocks.xlsx` | 9 articles de boissons + 81 articles de CUISINE (un par plat, même nom, point « Cuisine ») | 1 |
| `modele_import_m5-bar.xlsx` | 9 boissons (prix) | 2 |
| `modele_import_m4-restaurant.xlsx` | 81 plats (prix, catégorie, description) | 3 |

Ils sont **générés** depuis `docs/data/carte_gite_chez_noel_2026.json` (copie
`tatacora-api/database/data/…`, gardée identique par un test) :

```bash
cd tatacora-api && php artisan import:generer-carte-gite      # écrit docs/data/*.xlsx
cp ../docs/data/modele_import_m*.xlsx ../tatacora-flutter/assets/import/
```

Aucun prix, aucune quantité n'est inventé : tout ce que l'affiche ne dit pas reste vide.

## Colonnes de stock (toutes facultatives — un ancien fichier sans elles reste valide)

| Colonne | Modèles | Effet |
|---|---|---|
| Point de stockage (aussi lu : « Point Stock », « Point de stock », « Point ») | m4, m5, m6 | point de rattachement de l'article (Bar, Cuisine, Magasin général…) ; « Cuisine » est créé s'il n'existe pas |
| Seuil d'alerte (aussi lu : « Seuil ») | m4, m5, m6 | seuil de l'article créé ; vide = 0 |
| Valeur d'achat | m4, m5, m6 | valeur d'achat de RÉFÉRENCE de l'article (jamais une quantité ni un mouvement) ; vide = « — » |
| Article de stock lié | m5 | facultatif depuis le 09/11/2026 : vide, la boisson se rapproche de l'article de même nom (créé s'il manque) |

Les apostrophes droites et typographiques (Excel) se valent dans les en-têtes.

## Ce que fait chaque import

- **m6** crée les articles (suivi permanent). Les lignes dont le nom existe déjà sont IGNORÉES.
- **m5** crée les boissons liées à leur article (celui de la colonne, sinon celui de même nom).
- **m4** crée les plats, puis relie CHAQUE plat à l'article de stock de même nom au point
  Cuisine (créé s'il manque) : « N plats rapprochés du stock ». Le plat devient « stock
  vendable » (1 assiette = 1 unité de stock), solde à ZÉRO tant qu'aucune entrée n'est saisie.
  Un plat dont la fiche technique a des ingrédients n'est jamais relié.
- **Ré-import** : jamais de doublon, jamais d'écrasement (ligne existante ignorée ; un article
  repris n'est que COMPLÉTÉ : point vide, valeur d'achat vide — jamais un prix, un seuil ou un
  stock déjà saisis). Un fichier entièrement déjà importé répond « Aucune ligne ajoutée ».

## Rattrapage d'une installation déjà importée (plats sans lien)

- Web : bouton « Rapprocher les plats du stock » sur la Carte du restaurant (droits : écriture M4 et M6).
- Poste : même bouton, mêmes mots.
- Serveur : `php artisan restaurant:rapprocher-plats-stock` (`--simuler` liste sans écrire).

Idempotent ; crée les articles Cuisine manquants, relie les plats par nom, ne remplace aucun
lien, n'écrit ni prix ni quantité, laisse à leur fiche les plats décomposés en ingrédients.
Lancer d'abord l'action SUR UN SEUL côté (web de préférence), laisser la synchronisation
descendre l'article et le point « Cuisine », puis ouvrir les postes : deux points « Cuisine »
créés chacun de leur côté seraient deux points.

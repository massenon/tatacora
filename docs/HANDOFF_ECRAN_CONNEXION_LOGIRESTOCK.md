# Handoff — Écran de connexion LogiReStock (web PWA + poste Windows)

> Source : écran de connexion d'AgriERP (capture du PO, 29/10/2026), à reprendre pour
> **LogiReStock — TATACORA AFRIQUE** avec le concept de TATACORA (restauration,
> hébergement, éco-tourisme, stock, location…). Le web (Blade/Livewire) reste le
> maître de mise en page ; le poste Flutter le traduit à l'identique.
> Rappel des règles : aucune valeur en dur (jetons du thème existant), libellés dans
> `lang/fr`, repris côté poste, comparateur Blade dans la dette figée.

## 1. Vue d'ensemble
Carte de connexion unique, centrée, une colonne, de haut en bas :
1. **Marque** : pictogramme + « LogiReStock » (deux tons) + sous-titre « TATACORA AFRIQUE ».
2. Filet horizontal.
3. **Slogan** en capitales espacées : « VOTRE LOGICIEL DE GESTION INTÉGRÉE ».
4. Filet, puis **bandeau de 7 pictogrammes** (un par module), filet.
5. **Titre** « Bienvenue ! » + phrase « Connectez-vous à votre espace d'administration LogiReStock. »
6. Champ **Nom d'utilisateur ou e-mail** (icône utilisateur à gauche).
7. Champ **Mot de passe** (icône cadenas à gauche, œil afficher/masquer à droite).
8. Ligne : case **Se souvenir de moi** (gauche) · lien **Mot de passe oublié ?** (droite).
9. Bouton plein **SE CONNECTER** (icône cadenas ouvert + capitales).

## 2. Jetons (réutiliser ceux du thème ; valeurs mesurées sur la capture à titre indicatif)
| Jeton | Valeur indicative | Usage |
|---|---|---|
| couleur de marque (primaire) | vert profond ≈ #0B5D45 | bouton, lien, « Logi », pictogrammes de marque |
| couleur d'accent | doré/olive ≈ #8A6D0B | « ReStock » (2ᵉ ton de la marque) |
| texte fort | quasi noir vert ≈ #10261C | titre, libellés de champ (capitales, gras, 12 px) |
| texte secondaire | gris ≈ #6B7280 | phrase d'accroche, icônes du bandeau, placeholders |
| bordure | gris clair ≈ #D1D5DB | champs, filets |
| fond | blanc | carte |
Règle : si le thème TATACORA a déjà un jeton équivalent (primaire, accent, bordure…), **on l'utilise** et on n'ajoute pas de hex. Contraste texte/fond ≥ 4,5:1 ; le bouton blanc sur vert primaire ≥ 4,5:1 (à vérifier avec la teinte réelle).

## 3. Typographie et mesures
- Police : celle du thème (sans empattement, type Inter). Marque ≈ 28 px/800 ; sous-titre marque 11 px/700 capitales ; slogan 12 px/600 capitales, interlettrage large ; « Bienvenue ! » 28 px/800 ; accroche 15 px/400 ; libellés 12 px/700 capitales ; saisie 16 px ; bouton 16 px/700 capitales.
- Carte : largeur max ≈ 560 px, marges internes ≈ 24 px ; champs hauteur ≈ 52 px, rayon ≈ 12 px, bordure 1 px ; bouton hauteur ≈ 52 px, rayon ≈ 12 px, pleine largeur ; espacement vertical entre blocs ≈ 16–24 px.
- Bandeau d'icônes : 7 pictogrammes de 24–28 px, répartis à égale distance sur toute la largeur, couleur secondaire.

## 4. Pictogrammes (SVG, fil 1,75–2 px, coins arrondis, style cohérent)
| Rang | Module | Pictogramme | Source libre (équivalent Material côté poste) |
|---|---|---|---|
| Marque | LogiReStock | bol/feuille + boîte (ou clé) — **sobre, monochrome vert** | à dessiner, ou Lucide `package-check` |
| 1 | Restauration | couverts / cloche | Lucide `utensils-crossed` · `Icons.restaurant` |
| 2 | Hébergement | lit | Lucide `bed-double` · `Icons.hotel` |
| 3 | Éco-tourisme | feuille/arbre ou montagne | Lucide `trees` / `mountain` · `Icons.forest` |
| 4 | Stock | boîte d'archive | Lucide `archive` / `package` · `Icons.inventory_2` |
| 5 | Location (véhicules) | voiture | Lucide `car` · `Icons.directions_car` |
| 6 | Caisse / ventes | caisse enregistreuse | Lucide `calculator` / `receipt` · `Icons.point_of_sale` |
| 7 | Comptabilité / rapports | graphique à barres | Lucide `chart-column` · `Icons.bar_chart` |
Utilisateur, cadenas, cadenas ouvert, œil / œil barré : Lucide `user`, `lock`, `lock-open`, `eye` / `eye-off`.
Licence : Lucide (ISC) est libre d'usage ; on **intègre les SVG en ligne** (web) sans CDN et on **retient `Icons.*`** côté poste sauf si `flutter_svg` est déjà une dépendance. Chaque pictogramme décoratif : `aria-hidden="true"` ; chacun du bandeau porte un `title` (info-bulle) du module.

## 5. États et interactions
| Élément | État | Comportement |
|---|---|---|
| Champ | repos | bordure grise |
| Champ | survol | bordure un cran plus sombre |
| Champ | focus | anneau de focus 2 px couleur primaire + bordure primaire (jamais retiré sans équivalent) |
| Champ | erreur | bordure rouge du thème, message en dessous, `aria-invalid="true"` |
| Œil | clic / Entrée / Espace | bascule texte/points ; `aria-label` « Afficher/Masquer le mot de passe » ; `aria-pressed` |
| Case « Se souvenir de moi » | cochée | mémorise l'identifiant seulement (JAMAIS le mot de passe) |
| Lien « Mot de passe oublié ? » | clic | route existante de réinitialisation ; si absente sur le poste : message « Contactez l'administrateur » (poste hors ligne) |
| Bouton | survol | fond primaire assombri ≈ 10 % |
| Bouton | focus | anneau de focus visible |
| Bouton | chargement | désactivé, pastille tournante, libellé « Connexion… » |
| Bouton | désactivé | si les deux champs sont vides |
| Entrée au clavier | dans un champ | soumet le formulaire |
Transitions : 150 ms ease-out sur bordure/fond ; respecter `prefers-reduced-motion` (aucune animation d'entrée).

## 6. Contenu, erreurs, cas limites
- Erreurs (français, sous le champ ou en bandeau au-dessus du bouton) : identifiants invalides ; compte désactivé ; trop de tentatives (délai affiché) ; serveur injoignable → au poste, **la connexion fonctionne hors ligne** (base locale), jamais de message « réseau » bloquant.
- Pas de grille de comptes de démonstration (garde existante `aucune grille de comptes de démonstration`).
- Textes longs : identifiant tronqué avec points de suspension dans le champ ; titres et accroche passent à la ligne, jamais tronqués.
- Écran étroit (≤ 360 px) : bandeau d'icônes à 7 colonnes qui rétrécit (24 px) ou défile sans débordement de page ; aucun défilement horizontal.
- Premier lancement du poste : le formulaire de premier compte (`formulaire_premier_compte.dart`) garde son écran ; reprendre seulement l'en-tête de marque.
- Titre d'onglet / fenêtre : « Connexion — LogiReStock — TATACORA AFRIQUE » (décision de marque existante).

## 7. Responsive
| Largeur | Comportement |
|---|---|
| ≥ 1024 px | carte centrée verticalement et horizontalement, largeur ≈ 560 px, fond uni du thème |
| 768–1023 px | idem, marges latérales 24 px |
| < 768 px | carte pleine largeur, marges 16 px, champs et bouton ≥ 48 px de haut (cible tactile) |

## 8. Accessibilité
- Ordre de tabulation : identifiant → mot de passe → œil → « Se souvenir » → « Mot de passe oublié ? » → « SE CONNECTER ».
- `<label for>` explicite pour chaque champ (pas seulement le placeholder) ; `autocomplete="username"` et `"current-password"` ; `autofocus` sur l'identifiant.
- Erreur annoncée (`role="alert"`) ; état de chargement annoncé (`aria-busy`).
- Poste : `Semantics` équivalents, focus clavier visible, Tab/Maj+Tab/Entrée identiques.

## 9. Périmètre d'implémentation
- **Web** : vue de connexion Blade/Livewire (mise en page « invité » `layouts/pwa-invite.blade.php`), libellés `lang/fr/pwa.php`, icônes SVG en ligne, sans dépendance nouvelle.
- **Poste** : `lib/features/auth/presentation/ecran_connexion.dart` (+ jetons dans `lib/core/theme/`), même ordre, mêmes libellés, mêmes pictogrammes.
- **Gardes** : comparateur Blade (`t-blade-flutter.js`, dette figée), `ecran_connexion_test.dart` (aucune grille de comptes, aucun débordement de 320 à large), `echelle_contenu_test`, `AucunLogiRestockAfficheTest`/titres, géométrie/emplacement si la vue est mesurée.
- **Hors périmètre** : logique d'authentification, politique de mot de passe, « Mot de passe oublié » côté serveur (route existante).

# presentation/ — documents ÉCHANTILLONS de la facturation

> ## ⚠ AVERTISSEMENT
> **Tous les documents de ce dossier sont des ÉCHANTILLONS FICTIFS, sans aucune valeur fiscale.**
> Ils ne doivent **jamais** être remis à un client, ni transmis à la DGI comme des factures.
> Chaque PDF/HTML porte le bandeau et le filigrane « ÉCHANTILLON — SANS VALEUR FISCALE ». Les
> données sont inventées : IFU de l'entreprise `0000000000000`, IFU du client `1234567890123`,
> client « Client Exemple », NIM « ECHANTILLON », code MECeF et QR factices
> (`F;ECHANTILLON;ECHA-NTIL-LON0-FAUX-0000-0000;0000000000000;20261107120000`). L'identité du Gîte
> (nom, adresse, téléphone, logo) vient des valeurs par défaut du dépôt. Le seul dossier qui peut
> servir à un vrai essai est `05_essai_boitier/`, et alors sur un boîtier **réel** les documents
> créés sont réels (voir son avertissement).

Pour le conseiller fiscal, la DGI et l'équipe : montrer l'aspect des factures et les mentions
fiscales, et préparer l'essai du boîtier MECeF.

## Contenu

| Fichier | À quoi il sert | Produit par |
|---|---|---|
| `01_facture_simple_A4.pdf` | Facture **simple** (mode « désactivé ») : aucune mention, aucun numéro MECeF, aucun QR | gabarit serveur `pdf.facture-mecef` |
| `02_facture_normalisee_A4.pdf` | La **même** facture **normalisée** : NIM-TC, code MECeF, date, **QR dessiné** | gabarit serveur `pdf.facture-mecef` |
| `03_ticket_thermique_poste_simple.pdf` | Ticket 80 mm du poste, facture simple | `TicketFacture` (poste) |
| `03_ticket_thermique_poste_normalisee.pdf` | Ticket 80 mm du poste, facture normalisée avec QR | `TicketFacture` (poste) |
| `03_ticket_thermique_web_simple.html` | Ticket 80 mm de la **PWA** (vente de comptoir), mode désactivé | `pwa.pos.ticket-thermique` |
| `03_ticket_thermique_web_mecef.html` | Idem, mode boîtier/e-MECeF : le pied « MECeF » apparaît | `pwa.pos.ticket-thermique` |
| `04_facture_A4_poste_simple.pdf` | A4 produit par le **poste**, facture simple (comparer avec 01) | `FactureA4` (poste) |
| `04_facture_A4_poste_normalisee.pdf` | A4 produit par le poste, normalisée (comparer avec 02) | `FactureA4` (poste) |
| `05_essai_boitier/` | **Kit d'essai du boîtier CC300** (voir ci-dessous) | `construireJsonPilote` (poste) |

Le ticket web est une page HTML (le navigateur l'imprime par `window.print()`) : elle s'ouvre dans
n'importe quel navigateur, **sans** son script d'impression. Il ne porte pas de QR : une vente de
comptoir web n'enregistre aucune facture (spécification §10) ; seul le pied « MECeF » change selon le mode.

### `05_essai_boitier/`

- `bill_essai_1_simple.json`, `bill_essai_2_multi.json` (taxe de séjour groupe F, paiement mixte),
  `bill_essai_3_avoir.json` (avoir `FA`, `rn` à remplacer) : conformes à `bill.spec.json` ; montants
  entiers, libellés ASCII ≤ 60, `seller_name` ≤ 30 (vérifié par test automatique).
- `bill.spec.json` : copie du schéma du pilote (`eltrade-cc300-driver`).
- `commandes_essai.md` : procédure pour le technicien (pilote, `/check`, `/info`, `POST /bill` en
  PowerShell et curl.exe, lecture de la réponse, que faire si 503 / corps vide / `E:`).
- `fiche_resultats.md` : tableau à remplir (compteurs avant/après) pour lever les inconnues de
  `docs/SPEC_FACTURATION_NORMALISEE_MECEF.md` §8.
- `essai_poste_pas_a_pas.md` : l'essai dans l'application, avec le vrai pilote ou le faux
  (`tatacora-flutter/tool/faux_pilote_boitier.dart`, qui ne produit aucun document fiscal).

## Régénérer (jamais à la main)

Une commande, depuis la racine du dépôt :

```bash
bash presentation/regenerer.sh
```

ou séparément :

```bash
cd tatacora-api && php artisan tatacora:generer-echantillons ../presentation      # 01, 02, 03 web
cd tatacora-flutter && PRESENTATION_DIR=../presentation \
  flutter test tool/generer_echantillons_poste_test.dart                          # 03/04 poste + JSON du kit
```

La commande serveur est **refusée en production** et ne lit **aucune base** (paramètres fictifs, modèles
jamais enregistrés). Le filigrane est injecté dans le document rendu par le générateur : les gabarits
de production ne sont pas modifiés et ne peuvent pas le produire (un test le vérifie).

Vérifications automatiques (régénèrent dans un dossier temporaire, n'écrivent jamais ici) :

```bash
cd tatacora-api && php vendor/bin/phpunit tests/Feature/Facturation/EchantillonsPresentationTest.php
cd tatacora-flutter && flutter test test/features/facturation/echantillons_presentation_test.dart \
  test/features/facturation/kit_essai_boitier_test.dart
```

Elles contrôlent : en-tête `%PDF`, fichier non vide, texte attendu (`pdftotext` si présent), mention
d'échantillon, QR présent sur les normalisés et **absent** des simples, JSON du kit conformes au schéma ;
le test du kit échoue aussi si les `.json` committés ne sont plus ceux que le code produit.

## À propos des PDF

- **Encodage** : textes en UTF-8 ; les polices intégrées des PDF (Helvetica/Courier) ne couvrent que
  Latin-1. Les accents passent ; le tiret cadratin et l'apostrophe typographique disparaîtraient sans
  message, d'où la normalisation du poste (« — » devient « - » sur ses papiers). Le serveur (dompdf)
  imprime le « — » du bandeau correctement. Les montants utilisent l'espace insécable U+00A0.
- **Polices** : aucune police embarquée, aucune police téléchargée (le poste est hors ligne).
- Le QR est dessiné (vecteur) : sur le serveur par `bacon/bacon-qr-code` (SVG), sur le poste par `package:pdf`.
  Son contenu est aussi imprimé en texte sous le dessin (serveur).

## Écarts constatés entre les rendus (pour la discussion, non corrigés ici)

- Le A4 du serveur imprime « IFU du client » quand il est saisi ; le A4 du poste ne l'imprime pas.
- Les quantités du A4 serveur sont rendues en « 2.00 » (décimales), celles du poste en « 2 ».
- Le A4 du poste porte un pied « Projet PAEB — Cabinet FAGUEZ SARL » et un courriel d'en-tête que
  l'A4 du serveur ne porte pas (le courriel a été remplacé ici par `contact@exemple.invalid`).

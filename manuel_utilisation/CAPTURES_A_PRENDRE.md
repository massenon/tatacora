# Captures à prendre — chapitres 15 à 19 (édition de novembre 2026)

Les chapitres 15 à 19 du manuel (`src/part-10.html` à `src/part-14.html`) décrivent le **poste Windows**, que les
scripts `capturer.js` et `annoter.js` ne savent pas photographier (ils pilotent la PWA du serveur). Aucune image
n'a donc été inventée : chaque figure manquante est un **cadre en pointillés** (`<figure class="emplacement">`) qui
nomme le fichier attendu. Il y a **19 captures** à prendre. Une seule figure du chapitre 16 réutilise une capture
existante (`captures/parametres.png`, onglets de Paramètres du serveur).

## Règles communes

- Application **LogiReStock** installée sur un poste Windows, fenêtre à **1440 px de large** au moins, mise à l'échelle 100 %, **facteur 2** si possible (comme les captures existantes : PNG, ~2880 px).
- Fichier **PNG** déposé dans `manuel_utilisation/captures/`, **au nom exact** de la colonne « Fichier » ci-dessous (minuscules, tirets). `generer.js` le ré-encode en JPEG tout seul, pour peu que la balise `<img>` pointe vers `../captures/NOM.png`.
- Données **fictives** : jeu de démonstration ou comptes d'essai. Aucun vrai mot de passe, aucun vrai code de secours, aucun vrai jeton, aucun vrai IFU de client.
- **Remplacement dans le texte** : dans le fichier `part-NN.html` indiqué, remplacer le bloc
  ```html
  <figure class="emplacement">
    <div class="cadre"> … </div>
    <figcaption>…</figcaption>
  </figure>
  ```
  par
  ```html
  <figure>
    <img src="../captures/NOM.png" alt="Description de l'écran.">
    <figcaption>…(la même légende)…</figcaption>
  </figure>
  ```
  (la légende `<figcaption>` ne change pas). Puis relancer `PPTR_DIR=… node generer.js`.

## Chapitre 15 — Le poste Windows (`src/part-10.html`)

| # | Fichier | Écran | Étapes pour la prendre |
|---|---|---|---|
| 1 | `c15-installateur-assistant.png` | Assistant d'installation, page « Dossier de destination » | Sur un PC d'essai (ou une machine virtuelle), lancer `LogiReStock_Setup_<version>.exe` (produit par `build_windows.bat`, dossier `build\installer`). Avancer jusqu'à la page du dossier (proposé : `C:\Program Files\LogiReStock`). Capturer la fenêtre de l'assistant. |
| 2 | `c15-premier-demarrage.png` | Écran « Premier démarrage » (création du compte administrateur) | Sur un poste **sans compte** : supprimer d'abord les données d'un poste d'essai (désinstaller avec « Oui », ou renommer `%LOCALAPPDATA%\TATACORA` et `%APPDATA%\TATACORA`), puis lancer l'application. Capturer l'écran avant de saisir quoi que ce soit (champs vides). |
| 3 | `c15-desinstallation-avertissement.png` | Fenêtre d'avertissement de la désinstallation (Oui / Non) | Sur un poste d'essai : Paramètres Windows → Applications → LogiReStock → Désinstaller. La fenêtre rouge s'ouvre avant toute suppression : capturer, puis répondre **Non** (la désinstallation est annulée). |
| 4 | `c15-sauvegardes-poste.png` | Import & Export → onglet « Sauvegardes de la base », avec une sauvegarde listée | Menu latéral → Import & Export → « Sauvegardes de la base » → « Générer une sauvegarde de la base ». Capturer la liste (au moins une ligne, bandeau « non téléchargée » visible). |
| 5 | `c15-ecran-panne.png` | Écran « L'application ne peut pas démarrer » | **Poste d'essai uniquement, jamais un poste réel.** Fermer l'application. Copier `%LOCALAPPDATA%\TATACORA\donnees\tatacora.sqlite` ailleurs. Remplacer le fichier par un fichier texte quelconque renommé `tatacora.sqlite`. Lancer l'application, capturer l'écran de panne (titre, Cause, Journal, trois boutons). Quitter, puis **remettre la copie d'origine** à sa place. |

## Chapitre 16 — Configuration, appairage, synchronisation (`src/part-11.html`)

| # | Fichier | Écran | Étapes pour la prendre |
|---|---|---|---|
| 6 | `c16-parametres-synchronisation.png` | Paramètres → onglet « Synchronisation », poste appairé | Connecté en administrateur : Paramètres → « Synchronisation ». Poste appairé à un serveur d'essai. Capturer toute la page : interrupteur « Synchronisation activée », carte « ADRESSE DU SERVEUR », carte « SYNCHRONISATION AUTOMATIQUE », état d'appairage, boutons. |
| 7 | `c16-bouton-barre.png` | Fenêtre du bouton « Synchronisation » de la barre supérieure | Cliquer sur le bouton « Synchronisation » (voyant coloré) : la fenêtre montre « Envoyées au serveur », « En attente d'envoi », « À traiter », « Synchroniser maintenant », « Voir le détail ». |
| 8 | `c16-ecran-synchronisation-envoi.png` | Écran Synchronisation, onglet « Envoi » | Paramètres → Synchronisation → « Voir la synchronisation ». De préférence avec une ligne dans « À traiter » : sur deux postes d'essai, saisir hors ligne la même chambre aux mêmes dates sur les deux, reconnecter, laisser synchroniser : la seconde saisie est refusée (« Chevauchement avec un autre enregistrement »). À défaut, capturer l'écran avec la liste vide. |
| 9 | `c16-postes-appairage.png` | Écran « Postes & Appairage » du poste | Menu latéral → Pilotage & administration → « Synchronisation ». Avec au moins deux postes appairés (colonnes État, Appairage, Dernier envoi, Dernière réception). |

La figure 16.1 utilise `captures/parametres.png`, déjà dans le dépôt : elle montre les sept onglets de Paramètres du **serveur** ; la légende précise que le poste ajoute un huitième onglet « Synchronisation ». Si une capture du **poste** est prise, la substituer.

## Chapitre 17 — Facturation normalisée (`src/part-12.html`)

| # | Fichier | Écran | Étapes pour la prendre |
|---|---|---|---|
| 10 | `c17-parametres-facturation-normalisee.png` | Paramètres → « Identité & Légal », section « Facturation normalisée (MECeF) » du poste | Descendre jusqu'à la section : « Mode reçu du serveur », « Ce poste certifie par », « Adresse du pilote du boîtier », boutons « Enregistrer », « Tester le boîtier », « Adresse par défaut ». **Ne montrer aucun jeton** (il ne s'affiche jamais au poste). |
| 11 | `c17-modale-ifu-client.png` | Fenêtre de validation d'une facture : « IFU du client », « Nom du client », « Retenir pour ce client », « Normaliser maintenant » | Poste en mode « boîtier » ou « e-MECeF » (surcharge locale possible pour l'essai) : POS clients hébergés → clôture d'un séjour, ou lien « IFU du client » au comptoir. Utiliser l'IFU fictif `1234567890123` et « Client Exemple ». |
| 12 | `c17-facture-normalisee-a4.png` | Facture normalisée imprimée en A4 (numéro, code MECeF, date, QR) | **Ne pas produire de vraie facture normalisée.** Utiliser l'échantillon fictif filigrané `presentation/02_facture_normalisee_A4.pdf` (ou `04_facture_A4_poste_normalisee.pdf`, rendu du poste) : l'ouvrir et capturer la première page. Le filigrane « ÉCHANTILLON — SANS VALEUR FISCALE » doit rester visible. |

## Chapitre 18 — La facture proforma (`src/part-13.html`)

| # | Fichier | Écran | Étapes pour la prendre |
|---|---|---|---|
| 13 | `c18-proformas-liste.png` | Écran « Factures proforma » | Facturation → lien « Proformas ». Avoir créé au préalable : une proforma émise, un brouillon, une annulée (motif « Essai »). |
| 14 | `c18-proforma-formulaire.png` | Fenêtre « Nouvelle facture proforma » | Cliquer sur « Nouvelle facture proforma », saisir un client fictif, un objet et deux lignes (désignation, quantité, prix unitaire). Capturer avant de valider. |
| 15 | `c18-proforma-a4.png` | Proforma imprimée en A4 | Ouvrir la proforma émise de la capture 13, bouton « PDF A4 » ; capturer la première page (en-tête, tableau vert, « Arrêté la présente FACTURE PROFORMA à la somme de… », bloc signature et cachet si l'interrupteur est sur Oui). Source de secours : `presentation/` ne contient pas de proforma, donc une capture réelle du poste est nécessaire. |

## Chapitre 19 — Comptes, sécurité et profil (`src/part-14.html`)

| # | Fichier | Écran | Étapes pour la prendre |
|---|---|---|---|
| 16 | `c19-mon-profil-poste.png` | Mon profil sur le poste (administrateur) | Avatar → Mon profil. Capturer la page entière : métadonnées, informations personnelles (Nom complet, Email, Téléphone, Fonction, Intitulé de poste), « Modifier le mot de passe », bloc « Code de secours ». |
| 17 | `c19-comptes-utilisateurs.png` | Écran « Comptes utilisateurs » | Pilotage & administration → Comptes utilisateurs. Avoir au moins un compte d'essai dont le mot de passe vient d'être réinitialisé (statut « Changement requis ») et un compte « Désactivé ». |
| 18 | `c19-temporaire-affiche.png` | Fenêtre « Mot de passe temporaire de « … » » | Sur un **compte d'essai**, cliquer sur « Réinitialiser le mot de passe » puis « Générer le mot de passe temporaire ». Capturer la fenêtre (le mot de passe est jetable ; si la capture est diffusée, le masquer). |
| 19 | `c19-code-secours-connexion.png` | Écran « J'ai perdu mon mot de passe administrateur » | Sur l'écran de connexion, cliquer sur « J'ai perdu mon mot de passe administrateur ». Capturer les trois champs (Nom d'utilisateur, Code de secours, nouveau mot de passe) **vides ou avec des valeurs fictives**. |

## Après les captures

1. Remplacer chaque cadre `emplacement` par son `<img>` (règle ci-dessus).
2. Si l'écran capturé diffère de ce que décrit le texte (libellé, bouton absent), **corriger le texte**, pas la capture : le manuel décrit l'interface telle qu'elle est.
3. Régénérer le PDF : `PPTR_DIR=~/outils-pdf node generer.js` (le sommaire se renumérote seul).

## Statut au 09/11/2026 (mise à jour) — poste Windows : rendus Flutter produits, installateur et boîtes Windows à prendre par le PO

**Méthode.** Le conteneur est Linux : le poste Windows ne s'y lance pas. Les figures ci-dessous sont des **rendus du poste
par le moteur Flutter lui-même** (outil `tatacora-flutter/tool/capturer_poste_test.dart`, lancé avec
`CAPTURES_POSTE_DIR=../manuel_utilisation/captures flutter test --dart-define=ENV=production tool/capturer_poste_test.dart`) :
les **vrais écrans** de `lib/features/**`, la vraie base Drift (en mémoire) alimentée de données **fictives** par les vrais
écrivains du poste, le thème et la police Inter réels, fenêtre de 1 440 px, facteur 2 (PNG de 2 880 px). Ce **ne sont pas des
photos d'écran Windows** : ni cadre de fenêtre ni barre de titre, rendu des polices du moteur Linux (pas ClearType), pictogrammes
Material tirés du SDK, monospace de repli (DejaVu Sans Mono, JetBrains Mono n'étant pas livrée), les caractères « ← » et « → »
sont rendus en carré par la police Inter livrée (Windows les tire d'une police de secours), et le jeu de données est fictif
(horodatages du jour de génération). **Statut de chaque figure : « rendu Flutter, à confirmer par le PO sur Windows »**, sauf les
deux marquées « à prendre par le PO ».

| # | Fichier | Statut | Remarque (ce que l'image montre réellement) |
|---|---|---|---|
| 1 | `c15-installateur-assistant.png` | **à prendre par le PO** | Assistant Inno Setup : fenêtre Windows, non rendable par Flutter. |
| 2 | `c15-premier-demarrage.png` | rendu Flutter, à confirmer par le PO sur Windows | Écran « Premier démarrage » (champs vides), tailles de police de la connexion du 09/11/2026. |
| 3 | `c15-desinstallation-avertissement.png` | **à prendre par le PO** | Boîte d'avertissement de la désinstallation : fenêtre du désinstalleur, non rendable. |
| 4 | `c15-sauvegardes-poste.png` | rendu Flutter, à confirmer par le PO sur Windows | Sauvegarde réellement générée (copie SQLite, bandeau vert « Sauvegarde générée », ligne « non téléchargée »). « Rythme automatique » reste à « — » (pas de planificateur dans ce rendu). |
| 5 | `c15-ecran-panne.png` | rendu Flutter, à confirmer par le PO sur Windows | Vrai chemin de panne (fichier qui n'est pas une base SQLite). La ligne « Journal » montre un chemin Linux temporaire ; sur Windows : `…\TATACORA\donnees\demarrage.log`. |
| 6 | `c16-parametres-synchronisation.png` | rendu Flutter, à confirmer par le PO sur Windows | Poste appairé (compte fictif « gerant », poste « COMPTOIR-1 », adresse publique du serveur, jeton jamais affiché). |
| 7 | `c16-bouton-barre.png` | rendu Flutter, à confirmer par le PO sur Windows | Fenêtre du bouton « Synchronisation » : 57 envoyées, 3 en attente, 0 à traiter. |
| 8 | `c16-ecran-synchronisation-envoi.png` | rendu Flutter, à confirmer par le PO sur Windows | Une ligne « À traiter » : réservation rejetée, « Chevauchement avec un autre enregistrement » (refus injecté dans la file, pas obtenu par deux postes réels). |
| 9 | `c16-postes-appairage.png` | rendu Flutter, à confirmer par le PO sur Windows | Deux postes fictifs (état « Actif » et « Sans nouvelles »). Le serveur est simulé ; la colonne « État » est coupée à droite à 1 440 px, comme l'écran réel. |
| 10 | `c17-parametres-facturation-normalisee.png` | rendu Flutter, à confirmer par le PO sur Windows | Mode reçu du serveur (boîtier), « Ce poste certifie par », adresse du pilote, « Enregistrer », « Adresse par défaut », « Tester le boîtier ». Aucun jeton. Le mode s'affiche en code brut (« boitier ») : c'est l'écran actuel. |
| 11 | `c17-modale-ifu-client.png` | rendu Flutter, à confirmer par le PO sur Windows | Fenêtre de clôture d'un séjour : IFU fictif `1234567890123`, « Client Exemple », « Retenir pour ce client », « Normaliser maintenant » (poste en mode boîtier). |
| 12 | `c17-facture-normalisee-a4.png` | rendu Flutter (PDF du poste rastérisé), à confirmer par le PO | Première page de l'échantillon fictif `04_facture_A4_poste_normalisee`, filigrane « ÉCHANTILLON — SANS VALEUR FISCALE » visible. L'en-tête garde le téléphone de l'échantillon du dépôt. |
| 13 | `c18-proformas-liste.png` | rendu Flutter, à confirmer par le PO sur Windows | Une émise, un brouillon, une annulée (motif « Essai »). Numéros provisoires `PROV-FP-…`. |
| 14 | `c18-proforma-formulaire.png` | rendu Flutter, à confirmer par le PO sur Windows | Fenêtre « Nouvelle facture proforma » saisie, non validée. |
| 15 | `c18-proforma-a4.png` | rendu Flutter (PDF du poste rastérisé), à confirmer par le PO | Identité de l'établissement **fictive** (IFU, RCCM, téléphone et e-mail d'exemple), signature en texte seul (sans image de signature ni cachet). |
| 16 | `c19-mon-profil-poste.png` | rendu Flutter, à confirmer par le PO sur Windows | Compte administrateur fictif, bloc « Code de secours » (code posé, valeur jamais affichée). « Dernière connexion », « Adresse IP » et « Statut du compte » sont vides à gauche dans ce rendu (pas de connexion réelle). |
| 17 | `c19-comptes-utilisateurs.png` | rendu Flutter, à confirmer par le PO sur Windows | Un compte « Changement requis », un « Désactivé ». La colonne des boutons est coupée à droite à 1 440 px, comme l'écran réel. |
| 18 | `c19-temporaire-affiche.png` | rendu Flutter, à confirmer par le PO sur Windows | Mot de passe temporaire jetable d'un compte fictif (valeur aléatoire, sans valeur). |
| 19 | `c19-code-secours-connexion.png` | rendu Flutter, à confirmer par le PO sur Windows | Trois champs vides. Le libellé du bouton et « Retour à la connexion » n'ont pas de police propre dans le code : sous `flutter test` ils sortent en carrés ; sur cette figure seule, Inter leur a été appliquée dans une copie de travail (le dépôt est inchangé). Sur Windows, ces textes prennent la police système. |

Annexes du poste (`CAPTURES_A_PRENDRE_CHAP7-14.md`) : `x-poste-comptage-inventaire.png` et `x-poste-compta-bandeaux.png` —
rendu Flutter, à confirmer par le PO sur Windows (voir ce fichier).

Les cadres `emplacement` de `part-10.html` à `part-14.html` ne sont **pas** modifiés ici (un autre flux intègre les images).

Des écrans PWA voisins avaient été pris, sous d'autres noms, pour qui voudrait un repère visuel **sans les substituer** (l'interface
du poste diffère : libellés, boutons) : `pwa-postes-appairage` et `pwa-synchronisation-reception` / `-envoi` (figures 8 et 9),
`pwa-synchronisation-fenetre` (7), `x-parametres-mecef` et `pwa-parametres-mecef-emecef` (10), `pwa-facture-normaliser` (11),
`pwa-proformas-liste` et `pwa-proforma-formulaire` (13 et 14), `pwa-comptes-utilisateurs`, `pwa-comptes-reinitialisation`,
`pwa-code-secours-connexion` (17, 18 et 19), `x-sauvegardes` (4). La proforma A4 imprimée (15) n'a pas été photographiée : le
PDF produit par le serveur reprend l'identité réelle de l'établissement (e-mail, téléphone) dans son en-tête.

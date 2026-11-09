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

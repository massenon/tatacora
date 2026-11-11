# Prompt d'implémentation — sélecteur d'exercice, passage N → N+1, clôture SYSCOHADA

> **Note du 11/11/2026 — document HISTORIQUE** (prompt de départ pour un autre projet, corps inchangé). Il s'arrête à la clôture et à l'archive : il ne couvre PAS ce que TATACORA a ajouté ensuite, à savoir l'affectation du résultat selon la forme juridique (entreprise individuelle par défaut, `forme_juridique`), la clôture menée aussi au poste par demande de synchronisation, ni les états financiers révisés (TAFIRE, bilan). Pour l'état réel : `CLOTURE_EXERCICE_SYSCOHADA.md` (§4 ter, §5, §5 bis).

> À coller tel quel à Claude dans l'autre projet. Il reprend ce que TATACORA fait
> réellement (`docs/CLOTURE_EXERCICE_SYSCOHADA.md`, `ExerciceConsulte`,
> `ClotureExerciceService`). Adaptez les noms de tables et de langage à votre pile.

```text
Tu es expert-comptable SYSCOHADA révisé ET ingénieur logiciel senior. Implémente dans
ce projet la gestion des EXERCICES COMPTABLES : sélecteur d'exercice dans la barre
supérieure, passage automatique N → N+1, clôture annuelle, consultation des années
précédentes, réouverture. Réponds en français, travaille par lots testables et
commence par lire le code existant (plan comptable, journaux, écritures, états).

1. MODÈLE
- Table `exercices_comptables` : id, annee (unique, 2000..2100), date_debut (1er janv.),
  date_fin (31 déc.), statut ∈ {ouvert, en_cloture, cloture}.
- Table `clotures_exercices` : exercice, statut de la clôture, resultat (écrit au moment
  de la clôture, jamais recalculé), empreinte de l'archive, auteur, dates, motif de
  réouverture, identifiants des pièces CL et AN.
- Journaux réservés `CL` (clôture) et `AN` (à-nouveaux) : jamais proposés à la saisie
  manuelle, écrits seulement par le service de clôture.
- Comptes de résultat 131 (bénéfice) et 139 (perte) pris dans une table de
  correspondance PARAMÉTRABLE, jamais en dur.
- Une pièce validée est IMMUABLE (aucun UPDATE/DELETE : déclencheurs en base) ; on
  corrige par contre-passation.

2. SÉLECTEUR D'EXERCICE (barre supérieure)
- Il choisit ce qu'on LIT, il n'écrit RIEN : une écriture va TOUJOURS dans l'exercice
  de SA date, jamais dans l'exercice consulté. Aucun chemin d'écriture ne lit le
  sélecteur.
- Le choix vit dans la session de l'utilisateur, en UN seul endroit (classe
  `ExerciceConsulte` : exercice(), defaut(), choisir(), revenirAuDefaut(),
  reference(), bornes()). Tout écran le lit là, jamais une copie.
- Défaut = exercice OUVERT le plus récent, sinon le plus récent. Choisir le défaut
  efface le choix de la session. Identifiant inconnu : ignoré. Exercice supprimé :
  choix oublié.
- N'afficher le sélecteur que sur les écrans qui ont une année (comptabilité, accueil,
  états, dépenses, facturation, achats, paie) ; pas sur caisse/POS/planning.
- Changer d'exercice recharge l'écran courant (sans paramètre `exercice` ni page de
  liste), sans nouveau droit : l'écran garde ses permissions.
- Date de référence des périodes relatives (« ce mois », « ce trimestre », « exercice
  entier ») = aujourd'hui si l'exercice consulté la contient, sinon son dernier jour
  (consulter 2025 en 2026 = décembre 2025 sous « ce mois »).
- Bandeau de statut sous l'en-tête (en clôture / clôturé), boutons « Exercice N−1 » et
  « Exercice N+1 » à côté du sélecteur.

3. PASSAGE N → N+1 SANS RIEN ARRÊTER
- Tâche planifiée quotidienne (00:05) : ouvre l'exercice de l'année en cours et, en
  décembre, celui de l'année suivante (idempotent). Une pièce datée du 1er janvier
  ouvre l'année si elle manque (tracé au journal d'audit).
- N reste OUVERT tant que sa clôture n'a pas commencé : deux exercices ouverts en même
  temps sont normaux (écritures tardives de décembre dans N, janvier dans N+1).
- En clôture : les modules n'écrivent plus dans N ; seul le comptable y passe des
  écritures d'inventaire. Clôturé : lecture seule.
- À-nouveaux PROVISOIRES : tant que N n'est pas clôturé, la balance/bilan de N+1
  incluent les soldes des classes 1 à 5 de N, CALCULÉS À LA VOLÉE, JAMAIS ÉCRITS ; le
  résultat de N apparaît en 131/139 ; l'écran le dit. Classes 6 à 9 : repartent de zéro.

4. CLÔTURE (onglet « Clôtures », droit comptable)
- Transitions : ouvert → en_cloture (« Démarrer la clôture ») ; en_cloture → ouvert
  (« Reprendre la saisie ») ; en_cloture → cloture (« Clôturer définitivement ») ;
  cloture → en_cloture (« Rouvrir » : comptable seul, motif ≥ 10 caractères,
  contre-passe CL et AN, trace le motif, n'efface rien).
- Liste de contrôle AVANT clôture définitive (refus avec phrases lisibles) : aucune
  écriture en brouillon ; balance équilibrée ; exercice N−1 clôturé ; exercice N+1 non
  clôturé. Avertissement non bloquant : postes/sources avec opérations non envoyées.
- La clôture produit, dans UNE transaction et dans cet ordre : (1) pièce CL datée du
  31/12/N qui solde les classes 6, 7, 8 (centre par centre) avec contrepartie 131 ou
  139 ; (2) pièce AN datée du 01/01/N+1 qui reporte les classes 1 à 5 de N, résultat
  compris (les à-nouveaux deviennent définitifs) ; (3) statut cloture ; (4) archive
  légale. Toutes les écritures passent par UN SEUL service d'écriture (jamais
  d'INSERT direct).
- Les états de N restent ceux d'AVANT clôture : le journal CL est exclu des états (le
  compte de résultat montre le résultat de l'année, pas zéro).
- « Résultat reporté » = lu sur la clôture active (clotures_exercices.resultat), jamais
  recalculé ; une clôture rouverte n'est plus active.

5. ARCHIVE LÉGALE (immuable)
- Dossier par année et par clôture : `ecritures.csv` (UTF-8 BOM, séparateur `;`, dates
  AAAAMMJJ, montants à virgule ; colonnes JournalCode, JournalLib, EcritureNum,
  EcritureDate, CompteNum, CompteLib, CentreCout, EcritureLib, Debit, Credit…),
  `balance.csv`, `etats-cloture.pdf` (pièces, résultat, balance, compte de résultat,
  bilan, visas), `manifeste.json` (SHA-256 et taille de chaque fichier).
- Empreinte de l'archive = SHA-256 du manifeste, affichée à l'écran (à noter sur le PV).
- Le téléchargement VÉRIFIE l'archive et refuse si un fichier a changé. Jamais
  régénérée ; une nouvelle clôture après réouverture produit une NOUVELLE archive.
- Si la génération échoue, la clôture tient et l'écran propose « Générer l'archive ».
- Les colonnes du CSV sont déclarées à un seul endroit ; format exact à CONFIRMER avec
  l'expert-comptable / l'administration fiscale du pays.

6. CONSULTATION DES ANNÉES PRÉCÉDENTES
- Comparatif N / N−1 sur le compte de résultat et le bilan (même ligne, même poste,
  mêmes totaux, même filtre de statut).
- Grand livre : solde d'ouverture et de clôture par compte ; pour un compte de bilan
  l'ouverture est l'à-nouveau (écrit au journal AN si N−1 clôturé, sinon PROVISOIRE et
  dit tel ; « inconnu », jamais zéro, si N−1 clôturé sans pièce d'à-nouveaux).
- Notes annexes immobilisations/amortissements : ouverture + variation par compte.

7. SÉCURITÉ ET TRAÇABILITÉ
- Droits : démarrer/clôturer = comptable (ou rôle défini) ; rouvrir = comptable seul.
- Journal d'audit pour chaque transition (qui, quand, motif, exercice).
- RG de non-régression : une pièce n'est jamais modifiée ; une clôture ne se défait que
  par contre-passation.

8. TESTS À ÉCRIRE (avec mutations pour prouver qu'ils mordent)
- Écriture de décembre dans N pendant que janvier s'écrit dans N+1.
- N en clôture : module refusé, écriture d'inventaire du comptable acceptée.
- Clôture : pièce CL équilibrée, 131 vs 139 selon le signe, pièce AN = classes 1–5,
  états de N inchangés, refus (brouillon, balance déséquilibrée, N−1 non clôturé).
- Réouverture : contre-passation, motif < 10 caractères refusé, non-comptable refusé.
- Archive : empreinte, vérification, fichier modifié → téléchargement refusé.
- Sélecteur : choix en session, défaut, exercice supprimé, écrans concernés seulement,
  aucune écriture ne lit l'exercice consulté (test qui scanne les chemins d'écriture).
- Tests de mesure/horloge : figer l'horloge (un test qui lit la date réelle casse au
  changement de mois ou d'année).

Livre par lots : (1) modèle + ouverture automatique ; (2) sélecteur + consultation
N−1 + comparatif ; (3) clôture + pièces CL/AN + réouverture ; (4) archive légale.
Après chaque lot : tests ciblés, puis résume ce qui reste à valider avec le comptable.
```

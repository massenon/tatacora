# Essai du poste en mode « boîtier » — pas à pas dans l'application

À faire **après** que `commandes_essai.md` a validé le pilote (ou avec le faux pilote pour
s'entraîner). Source du comportement : `docs/SPEC_FACTURATION_NORMALISEE_MECEF.md` §1 et §10.

**Rappel : le jeton e-MECeF n'a rien à voir avec cet essai** (il n'existe pas sur le poste).
**Rappel : une facture normalisée par le vrai boîtier est un vrai document fiscal, irréversible
(sa correction est un avoir).**

## A. Préparer

1. *(Au serveur, administrateur)* Paramètres → Identité & Légal → **Facturation normalisée (MECeF)** :
   - **Mode** : « Boîtier CC300 (poste) » ;
   - l'**IFU** de l'entreprise (13 chiffres ; en essai avec le faux pilote : `0000000000000`) ;
   - **Identifiant de l'opérateur** et **Nom de l'opérateur** (≤ 30 caractères) — obligatoires.
   Le mode descend au poste à la prochaine synchronisation.
   *(Sans serveur : régler directement l'étape 2 sur le poste.)*
2. Sur le poste : Paramètres → **Facturation normalisée (MECeF)** → carte « Ce poste certifie par » :
   choisir **Boîtier** (ou « Comme le réglage du serveur » si le serveur est en mode boîtier) →
   **Enregistrer**. Contrôler **Adresse du pilote du boîtier** = `http://localhost:38917`.
3. Lancer le pilote (`commandes_essai.md` §1) **ou** le faux pilote :
   `dart run tool/faux_pilote_boitier.dart --ifu <IFU des Paramètres>`.

## B. Tester la liaison

4. Même carte : **Tester le boîtier**. Message de l'ordre de « Essai en cours : le boîtier met environ
   4 secondes à répondre… », puis « Boîtier prêt — NIM …, IFU …, taux A … B … ». Si l'IFU du boîtier
   diffère de celui de l'entreprise, la phrase « Attention : l'IFU du boîtier (…) n'est pas celui de
   l'entreprise (…) » s'ajoute : **s'arrêter**, corriger.
   Relever NIM, compteurs → `fiche_resultats.md`.

## C. Normaliser une vente

5. Encaisser une petite vente (comptoir) ou clôturer un séjour : à la validation, le lien/la modale
   **« IFU du client »** s'ouvre (facultatif ; 13 chiffres s'il est rempli ; laisser vide = client sans
   IFU). La case **« Normaliser maintenant »** est décochée par défaut.
   - **Variante 1 (bouton)** : ne pas cocher. La facture est émise « En attente de normalisation »
     (ticket et A4 : « Facture en attente de normalisation », aucun QR). Aller dans **Facturation**
     (registre), ligne de la facture → bouton **Normaliser**.
   - **Variante 2** : cocher « Normaliser maintenant ».
6. Attendre jusqu'à 30 s. Attendu : message « Facture normalisée : NIM-TC », le statut passe à
   **Normalisée**. Le ticket et le A4 portent alors : « Facture normalisée MECeF », NIM-TC, code
   MECeF, date, et le **QR**. Relever le NIM-TC (= valeur de `rn` pour un avoir).
7. Imprimer le ticket **sur la thermique** et **scanner le QR** avec un téléphone : noter la plus petite
   taille lisible (inconnue n° 6). Comparer avec `03_ticket_thermique_poste_normalisee.pdf` et
   `04_facture_A4_poste_normalisee.pdf` (échantillons).

## D. Cas d'échec à provoquer (de préférence avec le faux pilote)

| Provocation | Attendu dans l'application |
|---|---|
| Arrêter le pilote, cliquer **Normaliser** | « Le pilote du boîtier ne répond pas à l'adresse … » ; la facture reste **En attente**, rejouable (**Réessayer**) ; l'encaissement n'est jamais bloqué |
| Débrancher le boîtier / `--mode absent` | « Le boîtier de facturation n'est pas branché, ou son pilote ne le voit pas. » ; en attente |
| `--mode vide` ou `erreur` | « Le boîtier a répondu sans code de facture valide : la facture n'est pas normalisée. » ; compteur inchangé → en attente |
| `--mode perdu` | statut **À vérifier** (bouton **Vérifier**) : « ne la rejouez pas » ; **jamais rejouée automatiquement** |
| IFU du boîtier ≠ IFU des Paramètres | « L'IFU du boîtier (…) n'est pas celui de l'entreprise (…) » avant tout envoi |
| Facture non réglée | refus : « La facture n'est pas réglée : enregistrez le règlement avant de la normaliser. » |
| Cliquer **Normaliser** sur une facture déjà normalisée | « Cette facture est déjà normalisée. » ; rien n'est renvoyé |

## E. L'avoir

8. Sur une facture **normalisée**, annuler (ou avoir partiel) : en mode boîtier l'avoir est créé « en
   attente » puis normalisé par le bouton **Normaliser** avec `rt = FA`, `rn = NIM-TC` de la facture
   d'origine. **Hors ligne, l'avoir d'une facture normalisée est refusé** (« Un avoir sur une facture
   normalisée se fait en ligne : reconnectez le poste au serveur ») — c'est voulu (décision du PO).
9. Relever quel compteur avance (`SettlementBillCounter` ?) : inconnue n° 1.

## F. Remettre le poste en ordre après l'essai

Remettre le mode du serveur sur **Désactivé** (ou le réglage du poste sur « Comme le réglage du
serveur ») si l'essai a été fait avec un faux pilote ; les factures « normalisées » par le faux pilote
n'ont **aucune** valeur fiscale (NIM `ECHANTILLON`) et ne doivent pas être remises à un client.
Si l'essai a utilisé le vrai boîtier, conserver la fiche remplie avec les documents.

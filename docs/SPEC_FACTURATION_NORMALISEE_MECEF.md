# Spécification — facturation normalisée du Bénin (MECeF)

Statut : lots 0 à 4 de la session du 07/11/2026 (le lot 4 applique les décisions du PO, §10). Source : décisions du PO, pilote
`eltrade-cc300-driver` (lu), paquet `laraSgmefQR` (lu, jamais copié). **Aucun
essai n'a été fait contre un vrai boîtier ni un vrai compte DGI** : les contrats
ci-dessous sont ceux des documents lus, éprouvés contre de FAUX serveurs.

## 1. Les trois modes

Un seul réglage, `facturation_mode` (paramètre système, groupe `mecef`), trois valeurs :

| Valeur | Libellé | Qui certifie | Réseau |
|---|---|---|---|
| `desactive` (défaut) | Désactivé | PERSONNE : **facturation SIMPLE** (facture ordinaire « Facture », sans numéro MECeF, sans QR, sans AUCUNE mention) | non |
| `emecef` | e-MECeF (en ligne) | le SERVEUR, par l'API de la DGI | oui |
| `boitier` | Boîtier CC300 (poste) | le POSTE de la réception, par le pilote USB local | non (le boîtier transmet lui-même à la DGI) |

L'IFU est UNIQUE : la clé existante `entreprise_ifu` (13 chiffres, validée) sert aux deux voies.

**Où se règle le mode.** Au serveur, par un administrateur (Paramètres → Identité & Légal →
« Facturation normalisée (MECeF) »). Il descend aux postes en lecture seule avec les
autres paramètres. Un poste lit le mode du serveur quand il l'a, sinon garde le dernier
connu (la ligne descendue reste en base). Un réglage LOCAL du poste peut le surcharger :
« Ce poste certifie par : serveur / boîtier / rien » (`poste.json`, clé
`facturation_surcharge`), parce que le boîtier n'existe que sur ce poste. Mode effectif du
poste = surcharge, sinon mode du serveur, sinon `desactive`. Un poste dont le mode
effectif n'est pas « boîtier » n'envoie AUCUNE requête au pilote.

**Facture simple (décision du PO du 07/11/2026, §10).** En mode `desactive` la facture s'émet, s'imprime et
se range comme une facture ordinaire : `statut` `certifiee` (nom hérité : ce mot veut dire « émise et figée »,
la normalisation se lit sur `normalisation_statut`), `numero_mecef` et `qr_code_fiscal` NULL, aucun faux client
(`MecefClientFake` n'est plus appelé nulle part en production), aucune mention de démonstration, aucun bouton.

Le serveur NE certifie PAS en mode `boitier` : la facture créée au web reste « en attente
de normalisation par le poste » ; un poste avec boîtier la reprend à son passage (la
descente la lui apporte). Le serveur n'appelle JAMAIS le boîtier.

## 2. Réglages (clés et règles)

| Clé | Type | Règle | Descend au poste |
|---|---|---|---|
| `facturation_mode` | choix | `desactive`, `emecef`, `boitier` ; administrateur seulement | oui |
| `entreprise_ifu` | texte | 13 chiffres (règle ajoutée) | oui (déjà) |
| `mecef_api_url` | texte | `https://` exigé, défaut `https://developper.impots.bj/sygmef-emcf/api` | oui |
| `mecef_operateur_id` | texte | ≤ 30 car. | oui |
| `mecef_operateur_nom` | texte | ≤ 30 car. (limite du pilote `seller_name`) | oui |
| JETON JWT e-MECeF | SECRET | `secrets_configuration`, clé `mecef_jeton_api`, chiffré par `APP_KEY` | **JAMAIS** |
| `facturation_boitier_adresse` | `poste.json` | `http://localhost:38917` par défaut, modifiable sans recompiler | poste seul |
| `facturation_surcharge` | `poste.json` | `serveur` / `boitier` / `rien` / absent | poste seul |

Mode ≠ `desactive` : refusé à l'enregistrement si l'IFU manque (et, pour `emecef`, si
l'adresse ou le jeton manquent : « refus clair en français »).

## 3. Sécurité du jeton

- Saisie en champ mot de passe ; rangé CHIFFRÉ (`SecretsConfigurationService`, comme le mot de passe SMTP) ;
  affichage : « ••• enregistré le jj/mm/aaaa hh:mm » seulement ; remplacer = nouvelle saisie ;
  vider = effacer, avec confirmation (modale du dépôt).
- Jamais renvoyé au navigateur (ni valeur de champ, ni état Livewire public), jamais au poste
  (la descente lit `parametres_systeme`, qui n'en contient pas ; garde de test qui lit le code
  source de la descente ET une descente réelle), jamais dans le journal d'audit (seule la
  CLÉ est tracée), jamais dans les logs (les messages d'erreur du client sont reconstruits,
  aucun en-tête ni URL signée n'est journalisé).
- Lu uniquement par `MecefClientEmecef` et par « Tester la connexion ».
- Audit : « Réglage de la facturation normalisée modifié » (clés modifiées, jamais le jeton).
- Le poste n'a pas de client e-MECeF : il n'a ni ne saisit le jeton.

## 4. Contrat du pilote CC300 (poste)

`http://localhost:38917` (sans authentification : le client n'appelle QUE l'adresse réglée).
`GET /check` → 200 `{"status":"Ready"}` | 503 `{"status":"DeviceNotConnected"}`.
`GET /info` (≈ 4 s) → NIM, IFU, TIME, COUNTER, SellBillCounter, SettlementBillCounter,
TaxA..D, LastConnectionToServer, DocumentOnDeviceCount, UploadedDocumentCount.
`POST /bill` (JSON `bill.spec.json`) → `{"qr_code":"F;NIM;code;IFU;date"}`.

Pièges du pilote (lus dans le code Go) et réponses du client :

1. Il répond 200 MÊME EN CAS D'ÉCHEC (`qr_code` vide ou erroné, ou contenant « E: »). Le client
   exige un `qr_code` non vide commençant par `F;` à cinq champs, dont le NIM = celui de `/info`.
2. `specific_tax` et `original_price` sont des CHAÎNES dans la structure Go mais des nombres au
   schéma : les envoyer fait échouer le décodage (réponse vide, 200). Le client ne les envoie jamais.
3. Montants en `float32` : le client n'envoie que des entiers FCFA (exacts jusqu'à 2^24) et refuse
   toute facture > 16 777 215 FCFA par ligne ou en total.
4. La requête dure plusieurs secondes : délai 30 s ; jamais deux `POST /bill` en parallèle (verrou
   par poste, en mémoire ET en base : un statut « tentative en cours »).
5. Réponse perdue : un `POST` peut réussir côté boîtier alors que la réponse se perd. Protocole :
   lire `/info` AVANT (compteur N0, enregistré sur la pièce), poster, lire `/info` APRÈS.
   Succès net : `qr_code` valide et compteur = N0 + 1. Échec réseau/délai/réponse illisible :
   relire `/info` ; compteur = N0 → rien n'a été facturé, la pièce reste « en attente » et
   rejouable ; compteur > N0 → « à vérifier », JAMAIS rejouée automatiquement.
6. Compteur : ventes = `SellBillCounter`, avoirs = `SettlementBillCounter` (à confirmer sur appareil, §8).
7. IFU du boîtier (`/info`) ≠ `entreprise_ifu` : refus avant tout `POST`.

Conversion TATACORA → pilote : voir le code (`conversion_boitier.dart`). Vente : `vt = FV`. Avoir : `rt = FA`,
`rn = « NIM-TC »` de la facture d'origine. `seller_id` = `mecef_operateur_id`, `seller_name` = nom
de l'opérateur tronqué à 30. Modes de paiement : espèces `E`, mobile money `M`, carte `C`,
chèque `D`, virement `V`, autre `A` ; crédit jamais accepté (facture non réglée refusée).
Groupes de taxe : TVA active → `B`, sinon `A` ; une ligne « Taxe de séjour » → groupe `F` et
libellé exactement `TAXE DE SEJOUR`. Libellés rendus en ASCII (le protocole série du boîtier n'a pas de
table de caractères documentée : accents transcrits, apostrophes et guillemets redressés) ; `< > & CR LF`,
virgule, point-virgule, `*`, tabulation et caractères de contrôle (séparateurs du protocole, ou remplacés
par le pilote en entités qui rallongent le texte) deviennent des espaces ; coupure à 60/30/24 caractères
sans couper un mot si une espace précède dans les 15 derniers caractères. Prix = prix TTC unitaire,
`items` = quantité entière ; convention de prix HT refusée (le boîtier exige des TTC).
Contrôle AVANT envoi : Σ lignes = total TATACORA = Σ paiements, sinon refus.

## 5. Contrat e-MECeF (serveur)

Base `…/sygmef-emcf/api`, en-tête `Authorization: Bearer <JWT>`. `POST /invoice` (ifu, type
`FV|FA|EV|EA`, client, operator, items, payment, aib, `reference` pour FA/EA) → `uid` + totaux (PAS de
QR). `PUT /invoice/{uid}/confirm` → `codeMECeFDGI`, `qrCode`, `dateTime`, `counters`, `nim` (ou
`errorCode`/`errorDesc`). `PUT /invoice/{uid}/cancel`. `GET /info/status|taxGroups|invoiceTypes|paymentTypes`.
Une facture non confirmée EXPIRE après 2 minutes : créer puis confirmer dans la foulée, dans le même job.
Paiements : `ESPECES, VIREMENT, CARTEBANCAIRE, MOBILEMONEY, CHEQUES, CREDIT, AUTRE`. Avoir : `reference` =
`codeMECeFDGI` de la facture d'origine.
Idempotence : une facture déjà `normalisee` n'est JAMAIS retransmise ; l'`uid` d'une création réussie
dont la confirmation a été REFUSÉE (limite, jeton) est conservé et la confirmation seule est rejouée avant
l'expiration (100 s). Une confirmation SANS réponse exploitable (réseau coupé, 5xx, corps illisible) rend
l'issue incertaine : « à vérifier », jamais retransmise (même règle que le boîtier). PDF A4 du serveur : mentions
et QR DESSINÉ (`bacon/bacon-qr-code`), son contenu restant imprimé en texte en dessous.

## 6. Statuts et colonnes

Statut de normalisation, registre fermé : `normalisee` (« Normalisée »), `en_attente`
(« En attente de normalisation »), `refusee` (« Refusée par la DGI / le boîtier »), `a_verifier`
(« À vérifier »). Absent (NULL) = non concernée (démonstration, mode désactivé, avant la v50).
Colonnes ajoutées par migration additive conditionnelle, poste (v50, `pieces_facturation_local`)
et serveur (`factures`, `avoirs`) : `normalisation_statut`, `normalisation_motif`, `normalisation_mode`
(`boitier`/`emecef`), `normalisation_compteur` (TC), `code_mecef`, `qr_code_fiscal`, `normalisee_le` ;
côté poste en plus `normalisation_compteur_avant` (protocole de la réponse perdue).
Existantes : `numero_mecef` = « NIM-TC » (identité fiscale, valeur de `rn` des avoirs).
Une pièce n'est « réellement normalisée » que si `normalisation_statut = normalisee` ET `numero_mecef`
non DEMO ET QR : QR et mentions fiscales sur le PDF/ticket seulement dans ce cas. Sinon : AUCUNE mention en mode
désactivé ; « Facture en attente de normalisation » en e-MECeF / boîtier (jamais de filigrane, jamais de bandeau DEMO).
Une facture normalisée est FIGÉE : jamais modifiée, jamais écrasée ; sa correction est un AVOIR, qui passe aussi par la même voie.
Cycle serveur : `statut` `en_attente_certification` (instant de la création) → `certifiee` = ÉMISE (figée) à la fin de
l'émission (`EmissionFactureService::figerEmission`, ou par le rejeu pour une facture restée en attente). Un échec
de normalisation ne touche PAS `statut` d'une facture déjà émise : il se range sur `normalisation_statut` / `motif`.
Colonnes ajoutées au lot 4 : `factures.acheteur_ifu`, `factures.acheteur_nom`, `clients.ifu` (serveur) ;
`pieces_facturation_local.acheteur_ifu`, `.acheteur_nom`, `clients_local.ifu` (poste, schéma v51).

## 7. Messages d'erreur (français, jamais un secret)

Appareil absent · « Le boîtier de facturation n'est pas branché, ou son pilote n'est pas démarré. » ;
pilote injoignable · « Le pilote du boîtier ne répond pas à l'adresse … » ; délai · « Le boîtier n'a pas répondu
en 30 secondes. » (+ issue du compteur) ; réponse invalide · « Le boîtier a répondu sans code de facture valide :
la facture n'est pas normalisée. » ; refus · « Le boîtier a refusé la facture : … » ; montants · « Les montants ne
concordent pas (lignes …, paiements …). » ; IFU · « L'IFU du boîtier (…) n'est pas celui de l'entreprise (…). » ;
jeton refusé (401/403) · « La DGI a refusé le jeton e-MECeF : vérifiez-le dans Paramètres. » ; limite (429) ·
« La DGI limite les envois : nouvel essai dans … s. » ; réseau/délai · « La DGI est injoignable : nouvel essai
automatique. » ; configuration · « Facturation e-MECeF incomplète : renseignez l'IFU, l'adresse et le jeton. »

## 8. Questions ouvertes (à valider, non testables sans matériel)

1. `SettlementBillCounter` est-il bien le compteur des avoirs (`FA`) ? Sinon, quel champ de `/info` ?
2. Le « TC » de `rn` est-il le compteur relu APRÈS la vente (hypothèse retenue) ?
3. Format exact de `counters` (e-MECeF) et du TC à imprimer ; QR : `F;NIM;code;IFU;date` pour les deux voies ?
4. Facture à crédit / acompte : la DGI exige-t-elle un mode « crédit » ? Aujourd'hui : refus tant que non réglée.
5. Taxe de séjour : montant TTC dans le groupe F, ou hors TVA avec taxe spécifique ? (le pilote ne sait pas porter `specific_tax`).
6. AIB : non géré (toujours `N/A`).
7. Perte de réponse avec compteur avancé : aucun moyen de retrouver le QR par le pilote — saisie manuelle à prévoir ?
8. ~~Clients assujettis (`buyer_ifu`)~~ : TRANCHÉ le 07/11/2026 (§10, décision 2) : IFU client facultatif saisi à la validation.
9. Quel mode pour un poste sans boîtier quand le serveur est en `boitier` ? Aujourd'hui : « en attente ».
10. ~~`bacon/bacon-qr-code`~~ : TRANCHÉ (installé côté serveur, le PDF A4 dessine le QR ; `composer install` à chaque mise en production).
11. Une confirmation e-MECeF sans réponse peut-elle être rejouée sans risque (la DGI est-elle idempotente sur `confirm`) ?

## 9. Plan

Lot 0 cette spécification · Lot 1 réglage (serveur : registre, secret, section, audit, descente, test de connexion ;
poste : registre miroir, `poste.json`, section, surcharge) · Lot 2 boîtier (migration v50, client Dart, conversion,
service de normalisation, synchronisation vers le serveur, écran, PDF) · Lot 3 `MecefClientEmecef`, choix par mode dans
`MecefServiceProvider`, rejeu, avoirs.

## 10. Décisions du PO du 07/11/2026 (lot 4) — tranchées

1. **Normalisation par BOUTON, jamais automatique à l'émission.** Web : « Normaliser » (e-MECeF seulement) sur la ligne
   de l'écran Facturation, et case « Normaliser maintenant » à la validation du POS hébergement (décochée). Poste :
   « Normaliser » (boîtier, ou serveur si le poste est en ligne) et case « Normaliser maintenant » (décochée). Le rejeu
   de 30 minutes ne reprend QUE ce qu'un bouton a déjà demandé (statut en attente / refusée) ; une facture neuve n'est
   jamais normalisée par lui. Un échec ne bloque JAMAIS la facture ni l'encaissement.
2. **IFU.** L'IFU de l'ENTREPRISE vient de Paramètres (`entreprise_ifu`). L'IFU du CLIENT est demandé à la validation de la
   facturation de chaque flux (clés `facturation.ifu_client.*`, mêmes mots au web et au poste) : facultatif, 13 chiffres
   s'il est rempli (séparateurs de saisie ôtés), vide = client sans IFU. Boîtier : `buyer_ifu` facultatif (clé absente si
   vide), `buyer_name` = nom saisi, sinon nom de la fiche, sinon « Client divers ». e-MECeF : `client.ifu` facultatif,
   `client.name` idem. Prérempli depuis `clients.ifu` ; « Retenir pour ce client » (décochée) le range sur la fiche (jamais
   sur la fiche partagée « Client de passage »). Figé avec la facture (`acheteur_ifu`, `acheteur_nom`).
3. **Comportement par mode** : tableau ci-dessous (mesuré dans le code).
4. **Avoir EN LIGNE.** L'avoir d'une facture NORMALISÉE (annulation ou partiel) se fait en ligne : au poste, appel direct au
   serveur par le jeton d'appairage (`POST /api/v1/sync/factures/{id}/avoir`), interrupteur « Synchronisation activée »
   respecté ; hors ligne, refus « Un avoir sur une facture normalisée se fait en ligne : reconnectez le poste au serveur »
   et RIEN n'est écrit localement. L'avoir naît AU SERVEUR (identifiant serveur) puis descend ; la file du poste refuse
   d'envoyer un tel avoir. Normalisation de l'avoir : e-MECeF = le serveur (type FA, référence = code MECeF de l'origine),
   à sa création ; boîtier = « en attente », le poste avec boîtier le normalise par bouton (rt = FA, rn = NIM-TC). Avoir
   d'une facture simple : avoir simple, annulation toujours possible hors ligne par la file (avoir créé au serveur sous
   son identifiant, le poste le reconnaît par le numéro rendu). La charge d'annulation ne porte plus d'`avoir_id`.
5. **QR** : `bacon/bacon-qr-code` installé, le PDF A4 dessine le QR.
6. **Mode désactivé : AUCUNE mention** (correction du PO, même jour) — ni « DEMO », ni « Document non normalisé », ni bandeau,
   ni cachet réservé, ni filigrane, au web comme au poste. « En attente de normalisation » ne s'affiche que dans les modes
   e-MECeF et boîtier.
7. **IFU client facultatif, 13 chiffres validé s'il est rempli** : confirmé.
8. **e-MECeF depuis le poste.** Le jeton JWT ne descend jamais, le poste n'appelle jamais la DGI : en mode e-MECeF (ou
   surcharge « serveur »), le bouton « Normaliser » du poste, EN LIGNE, demande au serveur
   (`POST /api/v1/sync/factures/{id}/normalisation`, idempotent : jamais de retransmission d'une facture normalisée) ; le
   serveur normalise par `MecefClientEmecef` et le RÉSULTAT revient dans la réponse, écrit sur la facture du poste. Hors
   ligne : « La normalisation e-MECeF se fait en ligne : reconnectez le poste au serveur », rien d'écrit. Avant ce lot, le
   serveur NE normalisait PAS une facture du poste à sa réception : seul le job de rejeu (toutes les 30 min) le faisait,
   automatiquement.

### Comportement mesuré, flux × mode

| Flux | Désactivé (facture simple) | e-MECeF | Boîtier |
|---|---|---|---|
| **POS hébergement, web** (clôture de séjour) | Facture émise « Facture », IFU/nom saisis ; stockée figée sans numéro ni QR ; PDF sans mention | Idem + case « Normaliser maintenant » (non cochée) ; stockée « en attente » puis normalisée par le bouton ; QR et NIM-TC seulement ensuite ; échec = facture émise, motif rangé, rejouable | Facture émise « en attente de normalisation par le poste » ; aucun bouton web ; PDF : « Facture en attente de normalisation » |
| **POS hébergement, poste** (note de chambre) | Même facture, IFU/nom/« Retenir » dans la modale ; part au serveur avec l'acheteur ; ticket et A4 sans mention | Case « Normaliser maintenant » si en ligne ; bouton « Normaliser » = demande au serveur, hors ligne refusé (phrase) | Case et bouton = boîtier CC300 (hors ligne possible) ; « en attente » sinon, rejouable |
| **Réservation d'hôtel** (facture « à la fin ») | Aucune facture émise à la réservation : le web remet un papier « ne vaut pas facture » (mention hors facture), le poste n'a pas de flux ; la facture du séjour naît à la clôture au POS hébergement | idem | idem |
| **POS vente, web** (comptoir) | Ticket 80 mm + « Facture » A4 = ticket de vente, AUCUNE facture enregistrée ; pied « MECeF » supprimé en désactivé | idem (pas de facture enregistrée : rien à normaliser) | idem |
| **POS vente, poste** | Encaissement → facture `pos_comptant` émise d'office, lien « IFU du client » (facultatif) ; sans mention | idem + « Normaliser maintenant » ; sinon bouton Normaliser du registre | idem, par boîtier |
| **Location (contrat)** | Pas de facture (contrat seul), web et poste | idem | idem |
| **Tourisme (circuit)** | Pas de facture, web et poste | idem | idem |

Limites assumées : les flux sans facture enregistrée (réservation, POS vente web, location, tourisme) n'ont pas de champ IFU
tant qu'ils n'émettent pas de facture ; le signaler au PO plutôt que réécrire ces flux.

# Essai du boîtier CC300 — procédure pas à pas (technicien, poste de la réception)

> **ATTENTION — ce n'est PAS un exercice quand le vrai boîtier est branché.** Chaque `POST /bill`
> crée un **vrai document fiscal** dans la mémoire du boîtier, transmis à la DGI, et le compteur
> avance **sans retour possible**. Les montants des trois fichiers sont minuscules (100 à 1 700 FCFA)
> pour cette raison. Ne rejouez jamais deux fois le même fichier « pour voir » : notez chaque
> envoi sur la `fiche_resultats.md`.
>
> Pour s'entraîner sans boîtier : `dart run tool/faux_pilote_boitier.dart` (voir §7).

Fichiers du kit (dossier `presentation/05_essai_boitier/`) :

| Fichier | Contenu |
|---|---|
| `bill_essai_1_simple.json` | vente espèces, 1 ligne taxable B, 100 FCFA |
| `bill_essai_2_multi.json` | 4 lignes (3 en B, 1 « TAXE DE SEJOUR » en F), paiement mixte espèces 1 000 + mobile money 700, `buyer_ifu` fictif |
| `bill_essai_3_avoir.json` | avoir `FA`, `rn` à REMPLACER par le NIM-TC relevé à l'essai 1 |
| `bill.spec.json` | schéma du pilote (copie), pour valider un JSON modifié |

Ouvrez **PowerShell** sur le poste de la réception, dans le dossier du kit :

```powershell
cd C:\chemin\vers\presentation\05_essai_boitier
```

## 1. Installer / lancer le pilote

Le pilote est `eltrade-cc300-driver` (exécutable `eltrade`, service Windows `eltradeCC300Driver`).
Il écoute sur `http://localhost:38917`. Dans une invite **Administrateur** :

```powershell
.\eltrade.exe install     # installe le service ET le démarre
.\eltrade.exe start       # si déjà installé mais arrêté
```

Sans installation (essai ponctuel), lancer `.\eltrade.exe` sans argument le fait tourner dans la
fenêtre ; la fermer l'arrête. Branchez le boîtier en USB **avant** de lancer. Pour désinstaller :
`.\eltrade.exe uninstall`.

## 2. Vérifier le boîtier : `/check` puis `/info`

PowerShell :

```powershell
Invoke-RestMethod http://localhost:38917/check
```

curl.exe (le `.exe` est obligatoire sous PowerShell : `curl` seul est un alias) :

```powershell
curl.exe -i http://localhost:38917/check
```

Attendu : HTTP 200 et `{"status":"Ready"}`. Si **503** `{"status":"DeviceNotConnected"}` : voir §6.

```powershell
Invoke-RestMethod http://localhost:38917/info | ConvertTo-Json
curl.exe -i http://localhost:38917/info
```

`/info` dure environ **4 secondes** : c'est normal. À relever sur la fiche (ligne « avant ») :
`NIM`, `IFU`, `SellBillCounter`, `SettlementBillCounter`, `TaxB`, `LastConnectionToServer`,
`DocumentOnDeviceCount`, `UploadedDocumentCount`. Vérifier que **`IFU` est celui de l'entreprise**
(le poste refuse de normaliser sinon).

## 3. Envoyer une facture : `POST /bill`

Procédure identique pour chaque fichier. **Ordre : 1, puis 2, puis 3** (l'avoir a besoin du NIM-TC
de l'essai 1). Avant chaque envoi : `/info` (compteurs « avant »). Après : `/info` (compteurs « après »).

**PowerShell** (`-InFile` envoie le fichier tel quel ; l'UTF-8 est sans objet, les JSON sont en ASCII) :

```powershell
Invoke-RestMethod -Uri http://localhost:38917/bill -Method Post `
  -ContentType 'application/json' -InFile .\bill_essai_1_simple.json
```

**curl.exe** :

```powershell
curl.exe -i -X POST http://localhost:38917/bill -H "Content-Type: application/json" --data-binary "@bill_essai_1_simple.json"
```

Le `-i` affiche le code HTTP : **le notez**, car le pilote répond 200 même en cas d'échec.

### Que regarder dans la réponse

Réponse normale (HTTP 200, un seul champ) :

```json
{"qr_code":"F;NIM;CODE_MECEF;IFU;AAAAMMJJHHMMSS"}
```

Cinq champs séparés par `;` : `F`, le **NIM** du boîtier, le **code MECeF/DGI**, l'**IFU**, la **date**
(`aaaammjjhhmmss`). C'est exactement ce que le poste exige. Recopier le `qr_code` entier sur la fiche.

Le **TC** (compteur de la facture) n'est PAS dans la réponse : c'est `SellBillCounter` relu **après**
la vente. Le **NIM-TC** de l'essai 1 = `NIM` + `-` + `SellBillCounter` après (ex. `ED04000623-41`).
C'est la valeur à mettre dans `rn` de l'avoir.

Attendu : `SellBillCounter` après = avant + 1 (vente), `SettlementBillCounter` inchangé.

### Essai 3 : l'avoir

1. Ouvrir `bill_essai_3_avoir.json` et remplacer `NIM_A_REMPLACER-TC_A_REMPLACER` par le NIM-TC de
   l'essai 1 (format `NIM-TC`, ex. `ED04000623-41`). Rien d'autre ne change.
2. Envoyer comme ci-dessus, en notant le compteur **des avoirs** (`SettlementBillCounter`) ET celui
   des ventes avant/après : on veut savoir lequel avance (inconnue n° 1 de la spécification).

Pour modifier le fichier en PowerShell :

```powershell
(Get-Content .\bill_essai_3_avoir.json -Raw).Replace('NIM_A_REMPLACER-TC_A_REMPLACER','ED04000623-41') | Set-Content .\bill_essai_3_avoir.json -Encoding ascii
```

## 4. Lire le résultat : tableau de décision

| Constat | Verdict |
|---|---|
| HTTP 200, `qr_code` à 5 champs commençant par `F;`, NIM = celui de `/info`, compteur +1 | **OK** |
| HTTP 200 et `qr_code` vide `""` | **KO** : rien n'est facturé. Relire `/info` : compteur inchangé ? Voir §6 |
| HTTP 200 et `qr_code` contenant `E:` (ex. `E: ...`) | **KO** : le boîtier a refusé. Recopier le texte, voir §6 |
| HTTP 400 `{"errors":"[...]"}` | JSON non conforme au schéma (fichier modifié par erreur). Rien n'est facturé |
| HTTP 503 `DeviceNotConnected` | boîtier absent, voir §6 |
| Corps vide / coupure / plus de 30 s | **issue inconnue** : relire `/info`. Compteur inchangé = rien n'a été facturé ; compteur +1 = la facture existe sans qu'on ait son QR : **ne pas renvoyer**, noter « à vérifier » |

## 5. Test du poste de la réception (avec le boîtier)

Voir `essai_poste_pas_a_pas.md` (dans ce dossier) : l'essai dans l'application, une fois le pilote validé.

## 6. Quand ça ne marche pas

**503 `DeviceNotConnected`** (sur `/check`, `/info` ou `/bill`) : le pilote tourne mais ne voit pas le
boîtier. Vérifier le câble USB et l'alimentation, rebrancher, attendre 10 s, relancer `/check`. Si
persistant : fermer toute autre application qui utilise le boîtier, redémarrer le service
(`.\eltrade.exe uninstall` puis `install`), redémarrer le poste.

**Pas de réponse du tout** (`Impossible de se connecter` / `connection refused`) : le pilote n'est
pas démarré (§1). Contrôler : `Get-Service eltradeCC300Driver` ; et que le port est libre :
`netstat -ano | findstr 38917`.

**Corps vide avec HTTP 200 sur `/bill`** : c'est le piège connu du pilote (il répond 200 même en cas
d'échec). Causes probables : JSON non décodable (champ `specific_tax` ou `original_price` envoyé : ne
pas en ajouter), boîtier occupé, ou facture refusée sans message. **Toujours relire `/info`** :
compteur inchangé → rien n'a été enregistré, on peut recommencer UNE fois ; compteur +1 → NE PAS
renvoyer, noter « à vérifier » sur la fiche.

**`qr_code` contenant `E:`** : le boîtier a rejeté la facture (ex. taux de TVA non configuré, date,
format de `rn` pour un avoir, mode de paiement non accepté, `buyer_ifu` inconnu de la DGI). Recopier
le message **mot pour mot** sur la fiche (colonne remarques) et ne pas insister. Pour l'essai 2, si
le seul doute est `buyer_ifu`, supprimer la ligne `"buyer_ifu": ...` et rejouer UNE fois en le
notant : c'est une information (inconnue n° 8 résolue ou non).

**`/info` très lent ou en erreur 500 (`{error_message: ...}`)** : le pilote écrit un 200 avant de
rencontrer l'erreur ; le corps est alors du texte et non du JSON. Recommencer après 10 s.

Ne jamais : envoyer un JSON avec des montants décimaux, renvoyer un fichier dont l'issue est
inconnue sans avoir relu les compteurs, lancer deux `POST /bill` en parallèle.

## 7. S'entraîner avec le FAUX pilote (sans boîtier)

Depuis `tatacora-flutter/` (Dart/Flutter installé) :

```powershell
dart run tool/faux_pilote_boitier.dart --ifu 0000000000000
```

Il répond comme le vrai sur `http://localhost:38917` (NIM `ECHANTILLON`, compteurs en mémoire, QR
`F;ECHANTILLON;...` manifestement factice). Modes de panne : `--mode absent` (503), `vide`
(`qr_code` vide), `erreur` (`E: ...`), `perdu` (facture enregistrée mais réponse vide). Il ne produit
**aucun** document fiscal. Ctrl+C pour l'arrêter. Toutes les commandes ci-dessus fonctionnent à
l'identique ; seul l'IFU doit être celui des Paramètres du poste pour que l'application l'accepte.

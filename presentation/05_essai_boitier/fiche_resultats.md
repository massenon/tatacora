# Fiche de résultats — essai du boîtier CC300

À remplir **pendant** l'essai (imprimer ou compléter dans un éditeur). Un envoi = une ligne ; ne jamais
renvoyer sans avoir noté les compteurs. Les valeurs fictives du dépôt (NIM `ECHANTILLON`, IFU
`0000000000000`) ne doivent apparaître QUE si l'essai se fait avec le faux pilote.

**Date :** ____ / ____ / ________ **Technicien :** ______________ **Poste :** ______________
**Pilote (version, `Readme` : v0.1.3 ?) :** __________ **Boîtier (modèle, n° de série) :** __________
**Relevé initial `/info` :** NIM ____________ IFU ______________ TaxB ______ Dernière connexion DGI __________

## Journal des envois

SellBillCounter = compteur des ventes ; SettlementBillCounter = compteur des avoirs. « avant » et
« après » sont lus par `/info` juste avant et juste après le `POST`.

| N° | Heure | Fichier utilisé | HTTP | NIM | `qr_code` reçu (recopier en entier) | Vente avant | Vente après | Avoir avant | Avoir après | OK / KO | Remarques (texte exact d'un `E:`, durée, etc.) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | | bill_essai_1_simple.json | | | | | | | | | |
| 2 | | bill_essai_2_multi.json | | | | | | | | | |
| 3 | | bill_essai_3_avoir.json (rn = ______________) | | | | | | | | | |
| 4 | | | | | | | | | | | |
| 5 | | | | | | | | | | | |

**NIM-TC de l'essai 1** (NIM + `-` + compteur des ventes après) : ______________________

## Les inconnues à lever

Cocher et recopier la preuve (ligne du journal, valeur relue).

| N° (spéc. §8) | Question | Réponse constatée | Preuve (ligne du journal) |
|---|---|---|---|
| 1 | `SettlementBillCounter` est-il bien le compteur des avoirs (`FA`) ? | ☐ oui, il avance de +1 et pas SellBillCounter ☐ non, c'est ______ ☐ les deux avancent | |
| 2 | Le TC du `rn` est-il le compteur des ventes relu APRÈS la vente ? L'avoir (essai 3) a-t-il été accepté avec `rn` = NIM + compteur après ? | ☐ accepté ☐ refusé (message : ____________) | |
| 3 | Format du `qr_code` : bien `F;NIM;code;IFU;date` à 5 champs pour une vente ET pour un avoir ? Date `aaaammjjhhmmss` ? | ☐ oui ☐ non : ____________ | |
| 4 | Crédit : le boîtier accepte-t-il une facture non réglée (payments absent / montant inférieur) ? *Essai OPTIONNEL, à ne faire que sur autorisation (crée un document réel).* | ☐ non essayé ☐ accepté ☐ refusé : ____________ | |
| 5 | Taxe de séjour (essai 2, ligne F `TAXE DE SEJOUR`) acceptée ? Que fait le boîtier du taux (0 % ?) | ☐ acceptée ☐ refusée : ____________ | |
| 6 | Rendu du QR sur la thermique : imprimer le ticket de l'essai (ou la planche d'essai QR du poste), scanner avec un téléphone. Plus petite taille lisible (mm) : | ______ mm ; lisible à 80 mm : ☐ oui ☐ non | |
| 7 | `float32` : montants entiers acceptés sans arrondi ? Les montants lus sur le ticket du boîtier = ceux envoyés ? | ☐ identiques ☐ écart : ____________ | |
| 8 | `buyer_ifu` (essai 2) accepté alors que fictif ? | ☐ accepté ☐ refusé (retiré, puis OK ?) ☐ sans effet visible | |
| 9 | Délai de `POST /bill` | ______ secondes | |
| 10 | Le boîtier imprime-t-il lui-même un ticket ? Que porte-t-il (NIM, code, QR, taxe de séjour, libellés tronqués ?) | | |

## Verdict

☐ Pilote et boîtier prêts pour le poste ☐ À corriger : ____________________________________________

Signature technicien : ______________ Date : ____________

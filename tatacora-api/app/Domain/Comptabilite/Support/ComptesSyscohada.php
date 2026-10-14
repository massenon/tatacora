<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Support;

/**
 * Table de correspondance UNIQUE : fonction métier -> compte du plan
 * comptable du Product Owner (`database/data/plan-comptable-syscohada-revise.csv`).
 *
 * Décision du 10/10/2026 (lot 0, D191). Le fichier du PO ne compte aucun compte
 * de plus de quatre chiffres : les anciens numéros à six chiffres sont abandonnés.
 * Le client Flutter desktop réplique CETTE table. Un compte absent du fichier
 * n'est JAMAIS créé ici : le flux concerné se refuse en nommant le compte.
 *
 * ⚠ À VALIDER PAR LE COMPTABLE : correspondance établie par le lead à partir de
 * sources secondaires (plan-comptable-ohada.com, guides OHADA) ; le texte
 * officiel de l'AUDCIF n'a pas été consulté. Le fichier du PO fait foi.
 *
 * | Fonction | Ancien | Compte | Libellé EXACT du fichier | Division parente |
 * |---|---|---|---|---|
 * | Clients | 411000 | 4111 | « Clients » | 411 CLIENTS |
 * | Fournisseurs | 401000 | 4011 | « Fournisseurs » | 401 FOURNISSEURS, DETTES EN COMPTE |
 * | Avances et acomptes clients | 419100 | 4191 | « Clients, avances et acomptes reçus » | 419 CLIENTS CREDITEURS |
 * | TVA facturée, biens / bar | 443100 | 4431 | « T.V.A. facturée sur ventes » | 443 ETAT, T.V.A. FACTUREE |
 * | TVA facturée, prestations / restaurant | 443100 | 4432 | « T.V.A. facturée sur prestations de services » | 443 |
 * | TVA récupérable sur achats | 4452 | 4452 | « T.V.A. récupérable sur achats » | 445 ETAT, T.V.A. RECUPERABLE |
 * | Caisse | 571000-573000 | 5711 | « Caisse en monnaie nationale » | 571 CAISSE SIEGE SOCIAL |
 * | Banque | 521000 | 5211 | « Banque X » | 521 BANQUES LOCALES |
 * | Mobile Money | 522000 | 552 | « MONNAIE ELECTRONIQUE- TELEPHONE PORTABLE » | 55 (feuille à 3 chiffres) |
 * | Produit restaurant (M4), hébergement (M1) | 706200 / 706100 | 7061 | « dans la Région (1) » | 706 SERVICES VENDUS |
 * | Produit bar (M5) | 706300 | 7011 | « dans la Région (1) » | 701 VENTES DE MARCHANDISES |
 * | Achats de marchandises (dépenses) | 601100 | 6011 | « dans la Région » | 601 ACHATS DE MARCHANDISES (1) |
 * | Électricité | 604000 | 6052 | « Fournitures non stockables- Electricité » | 605 AUTRES ACHATS |
 * | Eau | 604000 | 6051 | « Fournitures non stockables-Eau » | 605 AUTRES ACHATS |
 * | Location minibus | 622100 | 6223 | « Locations de matériels et outillages » | 622 LOCATIONS ET CHARGES LOCATIVES |
 * | Internet / GSM | 628100 | 6281 | « Frais de téléphone » | 628 FRAIS DE TELECOMMUNICATIONS |
 * | Résultat net bénéfice | 131000 | 131 | « RESULTAT NET : BENEFICE » | 13 (feuille à 3 chiffres) |
 * | Résultat net perte | 139000 | 139 | « RESULTAT NET : PERTE » | 13 (feuille à 3 chiffres) |
 *
 * Correspondances décidées mais sans appelant dans le serveur aujourd'hui
 * (paie non comptabilisée) : salaires 661000 -> 6611, charges patronales CNSS
 * 645100 -> 6641, CNSS retenue 431000 -> 431, ITS 447000 -> 4472, personnel
 * 421000 -> 422, locations de véhicules -> 7073.
 *
 * Le CENTRE DE COÛT porte la distinction que les anciens numéros portaient
 * (caisse Réception/Restaurant/Bar, produit hébergement/restaurant) : une
 * ligne sur 5711 ou 7061 doit nommer son centre.
 */
final class ComptesSyscohada
{
    public const CLIENTS = '4111';

    public const FOURNISSEURS = '4011';

    public const AVANCES_CLIENTS = '4191';

    public const TVA_FACTUREE_BIENS = '4431';

    public const TVA_FACTUREE_PRESTATIONS = '4432';

    public const TVA_RECUPERABLE_ACHATS = '4452';

    public const CAISSE = '5711';

    public const BANQUE = '5211';

    public const MOBILE_MONEY = '552';

    public const PRODUIT_PRESTATIONS = '7061';

    public const PRODUIT_MARCHANDISES = '7011';

    public const ACHATS_MARCHANDISES = '6011';

    public const ELECTRICITE = '6052';

    public const EAU = '6051';

    public const LOCATION_MATERIEL_TRANSPORT = '6223';

    public const TELEPHONE_INTERNET = '6281';

    public const RESULTAT_BENEFICE = '131';

    public const RESULTAT_PERTE = '139';
}

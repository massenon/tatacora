<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Support;

/**
 * Les rôles comptables que l'administrateur peut rattacher à un autre compte
 * du plan — décision du PO du 26/10/2026 (« on peut impérativement modifier les
 * comptes sur poste et le web »).
 *
 * ## Ce que ce registre est
 *
 * La liste FERMÉE des rôles modifiables, chacun avec ce que l'écran et la
 * validation en disent : son groupe, son libellé, son aide, et les PRÉFIXES de
 * numéro de compte qu'il admet (« classe cohérente avec le rôle » : un produit
 * est de classe 7, la TVA collectée de 443, une trésorerie de classe 5…).
 * Le numéro par défaut d'un rôle est la constante de même nom de
 * {@see ComptesSyscohada} ; le paramètre qui porte la valeur choisie s'appelle
 * `compte_<rôle en minuscules>` ({@see \App\Domain\Comptabilite\Services\CorrespondanceComptesService::cle()}).
 *
 * ## Ce que ce registre n'est PAS : les comptes de CHARGE
 *
 * `ACHATS_MARCHANDISES`, `ELECTRICITE`, `EAU`, `LOCATION_MATERIEL_TRANSPORT` et
 * `TELEPHONE_INTERNET` n'y figurent pas. Le compte d'une charge se choisit
 * LIGNE PAR LIGNE à la saisie d'une dépense (`compte_charge`) : ces constantes
 * ne servent que de valeurs de démonstration au seeder. Les déclarer
 * modifiables serait offrir un réglage que AUCUNE pièce ne lit (PA-59/60/61).
 *
 * ## Le poste réplique ce registre
 *
 * `test/features/comptabilite/correspondance_comptes_contre_serveur_test.dart`
 * EXÉCUTE PHP et exige l'égalité exacte (rôles, groupes, libellés, aides,
 * préfixes).
 */
final class RolesCorrespondance
{
    public const GROUPE_TIERS = 'tiers';

    public const GROUPE_TVA = 'tva';

    public const GROUPE_TRESORERIE = 'tresorerie';

    public const GROUPE_PRODUITS = 'produits';

    public const GROUPE_RESULTAT = 'resultat';

    /**
     * L'ordre des groupes à l'écran.
     *
     * @var list<string>
     */
    public const GROUPES = [
        self::GROUPE_PRODUITS,
        self::GROUPE_TVA,
        self::GROUPE_TRESORERIE,
        self::GROUPE_TIERS,
        self::GROUPE_RESULTAT,
    ];

    /**
     * rôle (nom de la constante de {@see ComptesSyscohada}) => description.
     *
     * @var array<string, array{groupe: string, libelle: string, aide: string, prefixes: list<string>}>
     */
    public const ROLES = [
        'PRODUIT_PRESTATIONS' => [
            'groupe' => self::GROUPE_PRODUITS,
            'libelle' => 'Produits du restaurant',
            'aide' => 'Crédité par une vente du restaurant au comptoir.',
            'prefixes' => ['7'],
        ],
        'PRODUIT_MARCHANDISES' => [
            'groupe' => self::GROUPE_PRODUITS,
            'libelle' => 'Produits du bar',
            'aide' => 'Crédité par une vente de boissons au comptoir.',
            'prefixes' => ['7'],
        ],
        'PRODUIT_LOCATIONS' => [
            'groupe' => self::GROUPE_PRODUITS,
            'libelle' => 'Produits de la location de véhicules',
            'aide' => 'Crédité par une location encaissée au comptoir.',
            'prefixes' => ['7'],
        ],
        'PRODUIT_CIRCUITS' => [
            'groupe' => self::GROUPE_PRODUITS,
            'libelle' => 'Produits du tourisme, circuits',
            'aide' => 'Crédité par un circuit encaissé au comptoir.',
            'prefixes' => ['7'],
        ],
        'TVA_FACTUREE_BIENS' => [
            'groupe' => self::GROUPE_TVA,
            'libelle' => 'TVA facturée sur les ventes de biens (bar)',
            'aide' => 'Crédité par la part de TVA d’une vente de boissons ; lu par la déclaration de TVA.',
            'prefixes' => ['443'],
        ],
        'TVA_FACTUREE_PRESTATIONS' => [
            'groupe' => self::GROUPE_TVA,
            'libelle' => 'TVA facturée sur les prestations (restaurant, location, tourisme)',
            'aide' => 'Crédité par la part de TVA d’une prestation de services ; lu par la déclaration de TVA.',
            'prefixes' => ['443'],
        ],
        'TVA_RECUPERABLE_ACHATS' => [
            'groupe' => self::GROUPE_TVA,
            'libelle' => 'TVA récupérable sur les achats',
            'aide' => 'Lu par la déclaration de TVA, au titre de la TVA déductible.',
            'prefixes' => ['445'],
        ],
        'CAISSE' => [
            'groupe' => self::GROUPE_TRESORERIE,
            'libelle' => 'Caisse',
            'aide' => 'Trésorerie des règlements en espèces.',
            'prefixes' => ['5'],
        ],
        'BANQUE' => [
            'groupe' => self::GROUPE_TRESORERIE,
            'libelle' => 'Banque',
            'aide' => 'Trésorerie des règlements par carte, virement ou chèque.',
            'prefixes' => ['5'],
        ],
        'MOBILE_MONEY' => [
            'groupe' => self::GROUPE_TRESORERIE,
            'libelle' => 'Mobile Money',
            'aide' => 'Trésorerie des règlements par Mobile Money.',
            'prefixes' => ['5'],
        ],
        'CLIENTS' => [
            'groupe' => self::GROUPE_TIERS,
            'libelle' => 'Clients',
            'aide' => 'Débité par une vente portée sur la note de chambre, crédité par l’encaissement d’une facture.',
            'prefixes' => ['411'],
        ],
        'FOURNISSEURS' => [
            'groupe' => self::GROUPE_TIERS,
            'libelle' => 'Fournisseurs',
            'aide' => 'Débité par le règlement d’une commande fournisseur.',
            'prefixes' => ['401'],
        ],
        'AVANCES_CLIENTS' => [
            'groupe' => self::GROUPE_TIERS,
            'libelle' => 'Avances et acomptes clients',
            'aide' => 'Crédité par l’acompte d’une réservation, débité par son remboursement.',
            'prefixes' => ['419'],
        ],
        'RESULTAT_BENEFICE' => [
            'groupe' => self::GROUPE_RESULTAT,
            'libelle' => 'Résultat net : bénéfice',
            'aide' => 'Crédité par la clôture d’un exercice qui dégage un bénéfice.',
            'prefixes' => ['13'],
        ],
        'RESULTAT_PERTE' => [
            'groupe' => self::GROUPE_RESULTAT,
            'libelle' => 'Résultat net : perte',
            'aide' => 'Débité par la clôture d’un exercice qui dégage une perte.',
            'prefixes' => ['13'],
        ],
    ];

    public static function existe(string $role): bool
    {
        return array_key_exists($role, self::ROLES);
    }

    /**
     * Le numéro par défaut d'un rôle : la constante de {@see ComptesSyscohada}.
     */
    public static function defaut(string $role): string
    {
        return (string) constant(ComptesSyscohada::class . '::' . $role);
    }
}

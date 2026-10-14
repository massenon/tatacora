<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Domain\Vehicules\Models\Vehicule;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

/**
 * Parc de véhicules RÉEL du Gîte Chez Noël — auteur unique.
 *
 * ## Ce qui a changé le 03/09/2026 : le catalogue commercial fait foi
 *
 * Ce seeder posait cinq véhicules génériques de `SEEDER_TEST_LARAVEL.md` §6.3,
 * aux tarifs arrondis (65 000, 55 000, 35 000, 10 000, 90 000). Le parc réel
 * est celui du catalogue commercial imprimé, transcrit en
 * `prototype_v2/assets/js/referentiel-tatacora.js` l.186-198 : **huit
 * véhicules**, avec leurs places, leur transmission et leurs tarifs affichés
 * au client. Aucun des cinq tarifs génériques n'était le bon.
 *
 * « Prix des véhicules indiqué avec chauffeur inclus. » (catalogue p. 25)
 *
 * ## Le tarif du Prado est celui du CATALOGUE, pas celui de la spécification
 *
 * `SPEC_ECRAN_M8_VEHICULES.md` §1 affirme une « confirmation croisée positive »
 * à 65 000 F/jour. Le catalogue imprimé affiche **70 000 F**. C'est le
 * catalogue qui est opposable au client : c'est lui qui est retenu, et l'écart
 * est signalé plutôt qu'aplani (le maître le signale déjà, l.171-177).
 *
 * ## Scooter et vélo EXISTENT — ce qui rouvre PA-50
 *
 * `SPEC_ECRAN_M8_VEHICULES.md` §6 supposait que « le parc réel ne comprenait
 * vraisemblablement ni scooter ni vélo ». Le catalogue les tarife tous les
 * deux, et le maître en tire la conséquence : exiger un permis de conduire
 * pour louer un VÉLO à 5 000 F/jour n'a aucun sens.
 *
 * ⚠ `Vehicule::CATEGORIES_SANS_PERMIS` ne contient toujours que `moto` : louer
 * le vélo ou le scooter exigera donc un permis tant que PA-50 n'est pas
 * tranchée. Le parc le rend visible au lieu de l'éviter — c'est le seul
 * endroit à modifier le jour de l'arbitrage, et modifier une constante de
 * domaine n'appartient pas à un seeder.
 *
 * ## Deux lacunes de schéma, NOMMÉES
 *
 * 1. **Aucune colonne ne porte le MODÈLE.** `vehicules` connaît la catégorie,
 *    l'immatriculation, l'année, la transmission, la capacité, le tarif et le
 *    statut — pas la marque ni le modèle. « Toyota Land Cruiser Prado TX » n'a
 *    donc nulle part où s'écrire, et les véhicules ne se distinguent que par
 *    leur immatriculation. Le modèle est conservé en commentaire sur chaque
 *    ligne, pour que le jour où la colonne existera, la donnée n'ait pas à
 *    être relevée une seconde fois.
 * 2. **`annee` est NOT NULL et le catalogue ne la donne pas partout** — le
 *    Coaster et le vélo la portent à `null` au maître. Une année est posée
 *    pour les deux : c'est une valeur de DÉMARRAGE, pas une carte grise, comme
 *    les six autres d'ailleurs, que le catalogue donne mais qu'aucune carte
 *    grise du dossier ne confirme.
 *
 * ## Les immatriculations sont des PLACEHOLDERS, et cela ne se devine pas
 *
 * Le catalogue n'en porte aucune. Elles sont posées pour satisfaire la
 * contrainte d'unicité et pour que les contrats de démonstration aient une
 * clé de sélection stable — jamais parce qu'elles seraient réelles. Un numéro
 * de plaque plausible imprimé sur un contrat remis au client serait un faux
 * document, même famille que l'IFU et le RCCM des états.
 *
 * ⚠ CE SEEDER EST LE SEUL CHEMIN DE CRÉATION D'UN VÉHICULE des seeders : les
 * autres le LISENT par immatriculation (`LocationsTourismeSeeder`).
 *
 * Dév/Recette UNIQUEMENT. Idempotent.
 *
 * @see EF-M8-01 Référentiel du parc de véhicules
 * @see PA-50 RG-09 et les catégories dispensées de permis — question ouverte
 */
class VehiculeSeeder extends Seeder
{
    /**
     * Immatriculations de démonstration — voir l'en-tête : des placeholders,
     * pas des plaques. Nommées pour que les seeders d'exploitation cessent de
     * les recopier en dur.
     */
    public const PRADO = 'AB 1234 RB';

    public const HILUX = 'AB 5678 RB';

    public const HIACE = 'AB 9012 RB';

    public const COASTER = 'AB 3456 RB';

    public const MOTO_KA150 = 'AB 7890 RB';

    public const MOTO_EXPRESS = 'AB 2468 RB';

    public const SCOOTER = 'AB 1357 RB';

    public const VELO = 'AB 0246 RB';

    /**
     * Le parc du catalogue — `referentiel-tatacora.js` l.186-198.
     *
     * Colonnes : immatriculation (placeholder), catégorie (enum du schéma),
     * capacité en places, année, transmission, tarif par jour, modèle réel
     * (sans colonne — voir l'en-tête).
     *
     * @return list<array{string, string, int, int, string|null, string, string}>
     */
    public static function parc(): array
    {
        return [
            [self::PRADO, '4x4', 5, 2010, 'Manuelle', '70000', 'Toyota Land Cruiser Prado TX'],
            [self::HILUX, 'pickup', 2, 2013, 'Manuelle', '60000', 'Toyota Hilux 3.0 L Country'],
            [self::HIACE, 'bus', 14, 2006, 'Manuelle', '80000', 'Mini-bus Toyota Hiace'],
            // Année absente du catalogue : 2006 est une valeur de démarrage.
            [self::COASTER, 'bus', 30, 2006, 'Manuelle', '180000', 'Grand bus Toyota Coaster'],
            [self::MOTO_KA150, 'moto', 2, 2006, '5 vitesses', '10000', 'Moto Haojue KA 150'],
            [self::MOTO_EXPRESS, 'moto', 2, 2006, '5 vitesses', '7000', 'Moto Haojue Express'],
            [self::SCOOTER, 'scooter', 2, 2006, '4 vitesses', '6000', 'Scooter Haojue 110'],
            // Ni année ni transmission au catalogue — un vélo n'en a pas.
            [self::VELO, 'velo', 1, 2006, null, '5000', 'Vélo'],
        ];
    }

    public function run(): void
    {
        if (Vehicule::query()->exists()) {
            return;
        }

        foreach (self::parc() as [$immatriculation, $categorie, $places, $annee, $transmission, $tarif]) {
            Vehicule::create([
                'id' => (string) Str::uuid(),
                'categorie' => $categorie,
                'immatriculation' => $immatriculation,
                'annee' => $annee,
                'transmission' => $transmission,
                'capacite' => $places,
                'tarif_jour' => $tarif,
                // Le statut n'est PAS la disponibilité (même distinction qu'en
                // M1, RG-02) : un véhicule `disponible` peut être loué demain.
                'statut' => 'disponible',
            ]);
        }
    }
}

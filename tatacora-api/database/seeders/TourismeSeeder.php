<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Domain\Tourisme\Models\Circuit;
use App\Domain\Tourisme\Models\Guide;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

/**
 * Circuits, excursions et guides RÉELS — auteur unique.
 *
 * ## Ce qui a changé le 03/09/2026 : le catalogue commercial fait foi
 *
 * Ce seeder posait cinq circuits inventés (« Circuit Parc National de la
 * Pendjari », « Route des Esclaves — Ouidah »…) tirés de
 * `SEEDER_TEST_LARAVEL.md` §6.2. L'offre réelle est celle du catalogue
 * commercial imprimé, transcrit en `prototype_v2/assets/js/referentiel-tatacora.js` :
 * **5 circuits** (l.146-151, catalogue p. 20-21) et **8 excursions**
 * (l.156-165, p. 22-23), soit **13 prestations**, avec leurs durées et leurs
 * prix affichés au client. Aucun des cinq noms précédents n'existe au
 * catalogue, et aucun des cinq prix n'était le bon.
 *
 * ## Circuits et excursions vivent dans la MÊME table, et c'est le schéma
 *
 * `circuits` ne porte aucune colonne de nature : une excursion de deux heures
 * et un séjour de quatorze jours sont deux lignes de la même table, distinguées
 * par leur `duree` (`varchar` libre — un circuit de plusieurs jours ne bloque
 * que son jour de départ, PA-51). Créer une seconde table serait une décision
 * de schéma, pas de seeder. Les excursions sont donc semées comme circuits, et
 * leur durée le dit.
 *
 * ## Trois écarts au catalogue, NOMMÉS
 *
 * 1. **`capacite_max` n'est nulle part au catalogue**, et la colonne est NOT
 *    NULL. Les valeurs ci-dessous sont des valeurs de DÉMARRAGE, déduites du
 *    véhicule qui porte la prestation là où le maître en désigne un
 *    (`seed-locations-tourisme.js`) — le Nord Togo part en Hiace, et le maître
 *    écrit lui-même « il reste 3 places sur 13 » après dix places réservées.
 *    Elles se corrigent à l'écran ; elles ne sont pas relevées.
 * 2. **Les excursions n'ont pas de ZONE au catalogue**, et la colonne est NOT
 *    NULL. Elles partent toutes du gîte, à Natitingou : « Atacora » est une
 *    classification d'amorçage imposée par le schéma, pas une donnée du
 *    catalogue.
 * 3. **Aucune certification de guide n'est semée.** Une certification est un
 *    titre professionnel : en inventer un serait de la même famille qu'un IFU
 *    d'exemple sur une facture. La colonne est nullable, elle reste nulle, et
 *    l'écran M9 est l'endroit où elle se renseignera. `tarif_jour`, lui, est
 *    NOT NULL : 25 000 F est une valeur de démarrage, pas un tarif relevé.
 *
 * ## Les guides sont des EMPLOYÉS du gîte, pas des noms génériques
 *
 * « Guide Touristique Référent » et « Guide Sud Bénin » n'existaient nulle
 * part ailleurs. Le maître fait partir ses circuits avec ADJOVI Paul
 * (Chauffeur-guide, service Tourisme) et GNANSOUNOU Éric — deux membres réels
 * de l'équipe de `seed-personnel.js`, semés par `PersonnelSeeder`.
 *
 * ⚠ `guides` et `employes` sont DEUX tables sans lien au schéma : aucune clé
 * étrangère ne les rapproche, et rien n'empêche les deux listes de diverger.
 * L'écart est signalé, pas comblé — créer la relation est une décision de
 * schéma.
 *
 * Dév/Recette UNIQUEMENT. Idempotent — les circuits se retrouvent par leur
 * NOM, unique dans ce jeu, jamais par un ordre de requête non garanti.
 *
 * @see EF-M9-01 Référentiel des circuits
 * @see PA-51 `reservations_tour.guide_id` est NOT NULL — un départ a UN guide
 */
class TourismeSeeder extends Seeder
{
    /** Le circuit qui porte le départ de démonstration — voir `LocationsTourismeSeeder`. */
    public const CIRCUIT_DEPART_DEMONSTRATION = 'Nord Togo';

    /** Le guide qui le conduit — ADJOVI Paul, Chauffeur-guide au service Tourisme. */
    public const GUIDE_PRINCIPAL = 'ADJOVI Paul';

    public const GUIDE_SECOND = 'GNANSOUNOU Éric';

    /**
     * Les 13 prestations du catalogue.
     *
     * Colonnes : nom, thème (enum du schéma), zone, durée (texte libre du
     * catalogue), prix, capacité maximale (valeur de démarrage), page du
     * catalogue.
     *
     * @return list<array{string, string, string, string, string, int, int}>
     */
    public static function prestations(): array
    {
        return [
            // ============ CIRCUITS — catalogue p. 20-21 (l.146-151)
            ['Tata Otammari', 'culture', 'Atacora', '2 heures', '5000', 12, 20],
            // 13 places : le maître fait partir ce circuit en Hiace et écrit
            // « il reste 3 places sur 13 » après deux réservations de 6 et 4.
            [self::CIRCUIT_DEPART_DEMONSTRATION, 'faune', 'Togo', '2 jours', '77000', 13, 20],
            ['Sud Bénin', 'culture', 'Sud Bénin', '4 ou 7 jours', '352000', 12, 20],
            // « Plusieurs jours » : durée non exploitable, le véhicule n'est
            // bloqué que sur le jour de départ. 30 places — le maître le fait
            // partir en Coaster.
            ['Togo Complet', 'culture', 'Togo', 'Plusieurs jours', '225000', 30, 21],
            ['Bénin Complet', 'culture', 'Bénin', '14 jours', '561000', 12, 21],

            // ========== EXCURSIONS — catalogue p. 22-23 (l.156-165)
            ['Ornithologique', 'nature', 'Atacora', '2 heures', '5000', 12, 22],
            ['Quartier', 'culture', 'Atacora', '2 heures', '5000', 12, 22],
            ['Botanique', 'nature', 'Atacora', '2 heures', '5000', 12, 22],
            ['Équestre', 'aventure', 'Atacora', '2 heures', '15000', 12, 22],
            ['Au cœur des Tata', 'culture', 'Atacora', '3 heures', '35000', 12, 23],
            ['Cascade de Wabou', 'nature', 'Atacora', '1 journée', '35000', 12, 23],
            ['Chutes de Kota', 'nature', 'Atacora', '1 journée', '35000', 12, 23],
            ['Taneka Béri', 'culture', 'Atacora', '1 journée', '35000', 12, 23],
        ];
    }

    public function run(): void
    {
        if (Circuit::query()->exists()) {
            return;
        }

        foreach (self::prestations() as [$nom, $theme, $zone, $duree, $prix, $capacite]) {
            Circuit::create([
                'id' => (string) Str::uuid(),
                'nom' => $nom,
                'theme' => $theme,
                'zone' => $zone,
                'duree' => $duree,
                'prix' => $prix,
                'capacite_max' => $capacite,
            ]);
        }

        // `certification` reste NULLE : un titre professionnel ne s'invente
        // pas. `zone_competence` de même — le dossier n'en porte aucune.
        foreach ([self::GUIDE_PRINCIPAL, self::GUIDE_SECOND] as $nom) {
            Guide::create([
                'id' => (string) Str::uuid(),
                'nom' => $nom,
                'certification' => null,
                'zone_competence' => null,
                // NOT NULL au schéma : valeur de démarrage, pas un tarif relevé.
                'tarif_jour' => '25000',
            ]);
        }
    }
}

<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Domain\Crm\Models\Client;
use App\Domain\Tourisme\Models\Circuit;
use App\Domain\Tourisme\Models\Guide;
use App\Domain\Tourisme\Models\ReservationTour;
use App\Domain\Tourisme\Services\ReservationTourService;
use App\Domain\Vehicules\Models\ContratLocation;
use App\Domain\Vehicules\Models\Vehicule;
use App\Domain\Vehicules\Services\ContratLocationService;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * L'EXPLOITATION de M8 et M9 — contrats de location et départ en circuit —
 * posée SUR le parc de `VehiculeSeeder` et les circuits de `TourismeSeeder`.
 *
 * ## Le défaut corrigé le 31/08/2026 : troisième et quatrième référentiels à deux auteurs
 *
 * Ce seeder semait son propre parc (6 véhicules immatriculés `BJ-…`) et ses
 * propres circuits (4), alors que `VehiculeSeeder` (spécification §6.3, 5
 * véhicules `AB …`) et `TourismeSeeder` (§6.2, 5 circuits, 2 guides)
 * existaient déjà — décrochés de `DatabaseSeeder`, donc jamais exécutés. C'est
 * la même mécanique que le parc d'hébergement : deux jeux qui se distinguent
 * par le LIBELLÉ, chacun se croyant idempotent, aucun ne voyant l'autre. La
 * démonstration montrait **4 circuits pour les 5 de la spécification et 6
 * véhicules pour 5**, et un `db:seed --class=VehiculeSeeder` lancé un jour par
 * quelqu'un aurait produit 11 véhicules pour un parc de 5.
 *
 * ## Second défaut, de même famille que celui de M1 : RG-08, RG-09 et RG-13 étaient contournées
 *
 * Contrats et réservations de circuit étaient insérés en `DB::table()`, donc
 * hors de `ContratLocationService` et de `ReservationTourService`. Trois
 * garanties sautaient d'un coup, sans la moindre erreur visible :
 *
 * - **RG-08** — le verrou pessimiste sur le calendrier du véhicule
 *   (`VerificationChevauchementService`). La démonstration posait deux contrats
 *   sur le MÊME 4x4 ; ils ne se chevauchent pas, mais rien ne le vérifiait ;
 * - **RG-09** — pièce d'identité toujours, permis sauf catégorie dispensée.
 *   Les trois contrats semés n'en portaient aucune ;
 * - **RG-13** — capacité du départ, contrôlée CUMULÉE sur la date, et
 *   exclusivité du guide.
 *
 * Elles passent désormais par les services, connectées à un compte réel pour
 * que `utilisateur_creation_id` porte un auteur (RG-15).
 *
 * ## Ce que les contrats ne portent PAS, et pourquoi
 *
 * `contrats_location` a des colonnes `numero`, `montant`, `acompte`,
 * `reste_a_payer`, `statut` et `client_nom` que `ContratLocation::$fillable`
 * ne déclare pas — le modèle les ignore délibérément (`reste_a_payer` est
 * dérivable, `client_nom` doublerait la clé étrangère, et `statut` est la
 * lacune PA-50 : la table n'a aucun cycle de vie exploitable). Les remplir
 * exigerait un `DB::table()`, c'est-à-dire de rouvrir la porte que ce
 * correctif ferme. Ils restent vides, et l'écran le montre tel quel.
 *
 * Les pièces justificatives sont des mentions de démonstration, pas des
 * numéros : un numéro de CNI plausible sur un contrat imprimable serait une
 * fausse pièce d'identité, même famille que l'IFU de `FournisseurSeeder`.
 *
 * Dév/Recette UNIQUEMENT. Idempotent.
 *
 * @see \Database\Seeders\VehiculeSeeder l'unique auteur du parc de véhicules
 * @see \Database\Seeders\TourismeSeeder l'unique auteur des circuits et des guides
 * @see RG-08 Prévention des doubles locations
 * @see RG-09 Pièces justificatives conditionnelles
 * @see RG-13 Capacité et exclusivité du guide sur un départ
 */
class LocationsTourismeSeeder extends Seeder
{
    /**
     * Mention portée par les deux pièces de RG-09. Ce n'est pas un numéro :
     * un identifiant plausible sur un contrat remis serait une fausse pièce.
     */
    private const PIECE_DEMONSTRATION = 'Piece de demonstration — aucun document reel';

    public function run(): void
    {
        $this->contratsDeLocation();
        $this->departEnCircuit();
    }

    /**
     * Trois contrats sur le parc — deux clos, un en cours. Les deux premiers
     * portent sur le MÊME véhicule, bout à bout : c'est le cas que RG-08
     * accepte (bornes semi-ouvertes) et qu'un chevauchement d'un seul jour
     * ferait refuser.
     */
    private function contratsDeLocation(): void
    {
        if (ContratLocation::query()->exists()) {
            return;
        }

        $responsable = User::query()->where('login', 'garage')->first();

        if ($responsable === null) {
            return;
        }

        // Le scénario est celui du maître (`seed-locations-tourisme.js`
        // l.39-57) : deux locations du Prado bout à bout, puis le Hilux en
        // cours. Les véhicules sont désignés par les constantes de
        // `VehiculeSeeder` — une immatriculation recopiée en dur ici
        // divergerait du parc au premier changement de plaque.
        $contrats = [
            ['vehicule' => VehiculeSeeder::PRADO, 'client' => 'Agence Bénin Tour', 'debut' => 12, 'fin' => 8],
            ['vehicule' => VehiculeSeeder::PRADO, 'client' => 'KORA', 'debut' => 8, 'fin' => 5],
            ['vehicule' => VehiculeSeeder::HILUX, 'client' => 'Groupe scolaire ESCO', 'debut' => 2, 'fin' => -3],
        ];

        Auth::login($responsable);

        try {
            $service = app(ContratLocationService::class);

            foreach ($contrats as $c) {
                $service->creer([
                    'id' => (string) Str::uuid(),
                    'vehicule_id' => $this->vehiculeId($c['vehicule']),
                    'client_id' => $this->clientId($c['client']),
                    'date_debut' => now()->subDays($c['debut'])->toDateString(),
                    'date_fin' => now()->subDays($c['fin'])->toDateString(),
                    'piece_identite' => self::PIECE_DEMONSTRATION,
                    'permis_conduire' => self::PIECE_DEMONSTRATION,
                ]);
            }
        } finally {
            Auth::logout();
        }
    }

    /**
     * Un départ à venir, six participants sur les treize places du circuit :
     * l'écran de capacité a quelque chose à montrer sans être complet.
     *
     * Le circuit est « Nord Togo », celui que le maître fait partir en Hiace
     * (`seed-locations-tourisme.js` l.86-88) — et non plus « Circuit Parc
     * National de la Pendjari », qui n'existe à aucun catalogue. Le guide est
     * ADJOVI Paul, Chauffeur-guide au service Tourisme.
     */
    private function departEnCircuit(): void
    {
        if (ReservationTour::query()->exists()) {
            return;
        }

        $guideUtilisateur = User::query()->where('login', 'guide')->first();

        if ($guideUtilisateur === null) {
            return;
        }

        Auth::login($guideUtilisateur);

        try {
            app(ReservationTourService::class)->reserver([
                'id' => (string) Str::uuid(),
                'circuit_id' => $this->circuitId(TourismeSeeder::CIRCUIT_DEPART_DEMONSTRATION),
                'client_id' => $this->clientId('KORA'),
                'guide_id' => $this->guideId(TourismeSeeder::GUIDE_PRINCIPAL),
                'date_circuit' => now()->addDays(6)->toDateString(),
                'nb_participants' => 6,
            ]);
        } finally {
            Auth::logout();
        }
    }

    private function vehiculeId(string $immatriculation): string
    {
        return $this->obligatoire(
            Vehicule::query()->where('immatriculation', $immatriculation)->value('id'),
            'vehicule',
            $immatriculation,
        );
    }

    private function circuitId(string $nom): string
    {
        return $this->obligatoire(Circuit::query()->where('nom', $nom)->value('id'), 'circuit', $nom);
    }

    private function guideId(string $nom): string
    {
        return $this->obligatoire(Guide::query()->where('nom', $nom)->value('id'), 'guide', $nom);
    }

    private function clientId(string $nom): string
    {
        return $this->obligatoire(Client::query()->where('nom', $nom)->value('id'), 'client', $nom);
    }

    /**
     * Le référentiel est LU, jamais recréé — un second auteur produirait le
     * doublon corrigé le 31/08/2026. Le refus est explicite : un seeder qui
     * « réussit » sans rien semer est la forme PA-59/60/61 du peuplement.
     */
    private function obligatoire(mixed $id, string $quoi, string $cle): string
    {
        if ($id === null) {
            // Message exploitant, jamais affiché a un utilisateur.
            throw new RuntimeException(
                'LocationsTourismeSeeder pose une exploitation sur des referentiels '
                .'existants : '.$quoi.' introuvable ('.$cle.'). Lancer VehiculeSeeder, '
                .'TourismeSeeder et ClientSeeder avant (DatabaseSeeder le fait deja). '
                .'Ce seeder ne cree AUCUN referentiel.',
            );
        }

        return (string) $id;
    }
}

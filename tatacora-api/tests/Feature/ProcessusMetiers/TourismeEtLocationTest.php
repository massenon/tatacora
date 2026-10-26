<?php

declare(strict_types=1);

namespace Tests\Feature\ProcessusMetiers;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Services\EmissionFactureService;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ReservationService;
use App\Domain\Tourisme\Models\Circuit;
use App\Domain\Tourisme\Models\Guide;
use App\Domain\Tourisme\Services\ReservationTourService;
use App\Domain\Vehicules\Models\Vehicule;
use App\Domain\Vehicules\Services\ContratLocationService;
use App\Models\User;
use App\Shared\Integrite\Exceptions\ChevauchementDetecteException;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Processus métier n°4 — Tourisme et location.
 *
 * « Consultation catalogue (M9/M8) → Vérification disponibilité (guide,
 * véhicule) → Réservation avec pièces justificatives → Réalisation →
 * Retour/clôture → Facturation (M2) »
 * (`05_MODULE_SPECIFICATIONS.md` §Processus transverses).
 *
 * ## Pourquoi ce niveau est le seul à voir ce qu'il voit
 *
 * `07_TESTING_QA.md` §8 : « un changement dans M6 peut casser silencieusement
 * le processus Restauration **sans qu'aucun test unitaire du module M6
 * lui-même ne le détecte** ». Le même raisonnement s'applique ici entre M8, M9
 * et M2 : chacun passe ses tests, et pourtant le package véhicule+guide
 * (EF-M8-04 / EF-M9-03) traverse les trois.
 *
 * ## Ce qui n'est PAS exercé, et pourquoi
 *
 * - **Retour de véhicule / état des lieux (EF-M8-06)** : capture photo côté
 *   Flutter, aucun service serveur ne l'implémente.
 * - **Annulation d'une location** : impossible, `contrats_location` n'a pas de
 *   colonne `statut` (PA-50). Le test le constate explicitement plutôt que de
 *   laisser croire que le cas est couvert.
 * - **Comptabilisation (M10)** : aucune génération automatique d'écriture
 *   depuis une facture n'existe.
 */
final class TourismeEtLocationTest extends TestCase
{
    use RefreshDatabase;

    private const DEPART = '2026-09-15';

    private Client $client;

    private Vehicule $prado;

    private Circuit $cascade;

    private Guide $referent;

    private User $operateur;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        // Le Gérant a accès à l'ensemble des modules traversés : le processus
        // est éprouvé de bout en bout, pas coupé par un refus RBAC au milieu.
        $this->operateur = $this->utilisateur('gerant');
        $this->actingAs($this->operateur);

        $this->client = Client::factory()->create(['type_client' => 'particulier']);

        $this->prado = Vehicule::create([
            'categorie' => '4x4', 'immatriculation' => 'AB 1234 RB', 'annee' => 2019,
            'transmission' => 'automatique', 'capacite' => 7,
            'tarif_jour' => '65000.00', 'statut' => 'disponible',
        ]);

        $this->cascade = Circuit::create([
            'nom' => 'Cascades de Tanougou', 'theme' => 'nature', 'zone' => 'Atacora',
            'duree' => 'Journée', 'prix' => '15000.00', 'capacite_max' => 12,
        ]);

        $this->referent = Guide::create([
            'nom' => 'Guide Touristique Référent', 'certification' => 'Guide national',
            'zone_competence' => 'Atacora', 'tarif_jour' => '20000.00',
        ]);
    }

    /**
     * Le package complet : circuit avec guide **et** véhicule, jusqu'à la
     * facture consolidée (EF-M8-04, EF-M9-03, RG-04).
     */
    #[Test]
    public function le_package_vehicule_plus_guide_va_du_catalogue_a_la_facture(): void
    {
        $tours = app(ReservationTourService::class);
        $locations = app(ContratLocationService::class);

        // --- 1. Consultation catalogue : les deux ressources sont libres
        $this->assertSame(12, $tours->placesRestantes($this->cascade, self::DEPART));
        $this->assertTrue($locations->estDisponible($this->prado->id, self::DEPART, '2026-09-16'));
        $this->assertTrue($tours->affectationsDuGuide($this->referent->id, self::DEPART)->isEmpty());

        // --- 2. Réservation du circuit avec affectation de guide (M9)
        $prestation = $tours->reserver([
            'circuit_id' => $this->cascade->id,
            'client_id' => $this->client->id,
            'guide_id' => $this->referent->id,
            'date_circuit' => self::DEPART,
            'nb_participants' => 4,
        ]);

        // --- 3. Location du véhicule qui transporte le groupe (M8), avec les
        // pièces justificatives exigées par RG-09 pour un 4x4.
        $contrat = $locations->creer([
            'vehicule_id' => $this->prado->id,
            'client_id' => $this->client->id,
            // EF-M8-04 : le contrat porte le guide, c'est ce qui en fait un package.
            'guide_id' => $this->referent->id,
            'date_debut' => self::DEPART,
            'date_fin' => '2026-09-16',
            'piece_identite' => 'CNI-2026-0042',
            'permis_conduire' => 'PC-2026-0042',
        ]);

        $this->assertTrue($contrat->estPackageAvecGuide());

        // --- 4. Les deux ressources sont désormais engagées
        $this->assertSame(8, $tours->placesRestantes($this->cascade->fresh(), self::DEPART));
        $this->assertFalse($locations->estDisponible($this->prado->id, self::DEPART, '2026-09-16'));

        // --- 5. Réalisation puis clôture de la prestation (UC-40)
        $this->assertSame('terminee', $tours->cloturer($prestation)->statut);

        // --- 6. Facturation consolidée (M2, RG-04) : les deux lignes portent
        // leur module d'origine, ce qui rend un litige vérifiable.
        $emission = app(EmissionFactureService::class);
        $facture = $emission->emettrePourReservation($this->reservationHebergement(), '25000.00');

        $emission->ajouterLigne($facture, 'M9', $prestation->id, 'Circuit Cascades ×4', '4.00', '15000.00');
        $emission->ajouterLigne($facture, 'M8', $contrat->id, 'Location 4x4 — 1 jour', '1.00', '65000.00');

        $facture->refresh();

        $this->assertEqualsCanonicalizing(
            ['M1', 'M9', 'M8'],
            $facture->lignes()->pluck('source_module')->all(),
        );

        // 25 000 hébergement + 60 000 circuit + 65 000 location.
        $this->assertSame('150000.00', $facture->montant_ttc);

        // Les montants facturés correspondent aux montants calculés par les
        // domaines — c'est le raccord que ce niveau existe pour vérifier.
        $this->assertSame('60000.00', $prestation->fresh()->montant());
        $this->assertSame('65000.00', $contrat->montant());
    }

    /**
     * La rupture de chaîne que ce niveau doit attraper : le guide est la
     * ressource **partagée** entre M8 et M9. Un second circuit le même jour
     * doit être refusé alors même que le véhicule, lui, serait disponible.
     */
    #[Test]
    public function le_guide_partage_entre_les_deux_modules_ne_peut_pas_etre_double_affecte(): void
    {
        $tours = app(ReservationTourService::class);

        $tours->reserver([
            'circuit_id' => $this->cascade->id,
            'client_id' => $this->client->id,
            'guide_id' => $this->referent->id,
            'date_circuit' => self::DEPART,
            'nb_participants' => 4,
        ]);

        $autreCircuit = Circuit::create([
            'nom' => 'Village Taneka', 'theme' => 'culture', 'zone' => 'Atacora',
            'duree' => 'Demi-journée', 'prix' => '9000.00', 'capacite_max' => 10,
        ]);

        // Un second véhicule est libre : ce n'est donc pas lui qui bloque.
        $secondVehicule = Vehicule::create([
            'categorie' => 'pickup', 'immatriculation' => 'CD 5678 RB', 'annee' => 2020,
            'transmission' => 'manuelle', 'capacite' => 5,
            'tarif_jour' => '45000.00', 'statut' => 'disponible',
        ]);
        $this->assertTrue(
            app(ContratLocationService::class)->estDisponible($secondVehicule->id, self::DEPART, '2026-09-16'),
        );

        $this->assertThrows(
            fn () => $tours->reserver([
                'circuit_id' => $autreCircuit->id,
                'client_id' => $this->client->id,
                'guide_id' => $this->referent->id,
                'date_circuit' => self::DEPART,
                'nb_participants' => 3,
            ]),
            RuntimeException::class,
        );
    }

    /**
     * RG-09 traverse le processus : sans permis, la chaîne s'arrête à l'étape
     * « réservation avec pièces justificatives » — et rien n'est écrit, ni
     * côté M8 ni côté M9.
     */
    #[Test]
    public function une_piece_justificative_manquante_arrete_la_chaine_sans_rien_ecrire(): void
    {
        $locations = app(ContratLocationService::class);

        $this->assertThrows(
            fn () => $locations->creer([
                'vehicule_id' => $this->prado->id,
                'client_id' => $this->client->id,
                'date_debut' => self::DEPART,
                'date_fin' => '2026-09-16',
                'piece_identite' => 'CNI-2026-0042',
                // Permis absent sur un 4x4 : RG-09 refuse.
            ]),
            RuntimeException::class,
        );

        $this->assertDatabaseCount('contrats_location', 0);
        // Le véhicule reste disponible : aucun engagement partiel.
        $this->assertTrue($locations->estDisponible($this->prado->id, self::DEPART, '2026-09-16'));
    }

    /**
     * RG-08 de bout en bout : deux groupes ne partagent pas un véhicule, même
     * si chacun a son propre circuit et son propre guide.
     */
    #[Test]
    public function deux_groupes_distincts_ne_peuvent_pas_partager_le_meme_vehicule(): void
    {
        $locations = app(ContratLocationService::class);

        $locations->creer([
            'vehicule_id' => $this->prado->id,
            'client_id' => $this->client->id,
            'date_debut' => self::DEPART,
            'date_fin' => '2026-09-18',
            'piece_identite' => 'CNI-1', 'permis_conduire' => 'PC-1',
        ]);

        $autreClient = Client::factory()->create();

        $this->assertThrows(
            fn () => $locations->creer([
                'vehicule_id' => $this->prado->id,
                'client_id' => $autreClient->id,
                'date_debut' => '2026-09-16',
                'date_fin' => '2026-09-17',
                'piece_identite' => 'CNI-2', 'permis_conduire' => 'PC-2',
            ]),
            ChevauchementDetecteException::class,
        );
    }

    /**
     * Le maillon qui manquait au processus (PA-50) est fermé le 26/10/2026 : une
     * location erronée s'annule comme une prestation touristique, et le
     * véhicule redevient libre sur sa plage (RG-08).
     */
    #[Test]
    public function pa50_l_annulation_est_possible_cote_circuit_et_cote_vehicule(): void
    {
        $tours = app(ReservationTourService::class);
        $locations = app(ContratLocationService::class);

        $prestation = $tours->reserver([
            'circuit_id' => $this->cascade->id,
            'client_id' => $this->client->id,
            'guide_id' => $this->referent->id,
            'date_circuit' => self::DEPART,
            'nb_participants' => 4,
        ]);

        $contrat = $locations->creer([
            'vehicule_id' => $this->prado->id,
            'client_id' => $this->client->id,
            'date_debut' => self::DEPART,
            'date_fin' => '2026-09-16',
            'piece_identite' => 'CNI-1', 'permis_conduire' => 'PC-1',
        ]);

        // Côté M9 : l'annulation libère la place au départ.
        $tours->annuler($prestation);
        $this->assertSame(12, $tours->placesRestantes($this->cascade->fresh(), self::DEPART));

        // Côté M8 : le contrat bloque sa plage tant qu'il n'est pas annulé, puis
        // le véhicule redevient libre.
        $this->assertFalse($locations->estDisponible($this->prado->id, self::DEPART, '2026-09-16'));
        $locations->annuler($contrat);
        $this->assertTrue($locations->estDisponible($this->prado->id, self::DEPART, '2026-09-16'));
    }

    // ------------------------------------------------------------- Helpers

    private function reservationHebergement(): \App\Domain\Hebergement\Models\Reservation
    {
        $categorie = CategorieHebergement::create([
            'libelle' => 'Bungalow', 'capacite_max' => 4, 'tarif_base' => '25000.00',
        ]);
        $unite = UniteHebergement::create([
            'categorie_id' => $categorie->id, 'numero' => 'B-01', 'statut' => 'libre',
        ]);

        return app(ReservationService::class)->creer([
            'client_id' => $this->client->id, 'unite_id' => $unite->id,
            'date_arrivee' => self::DEPART, 'date_depart' => '2026-09-16',
            'statut' => 'confirmee', 'acompte' => '0.00',
        ]);
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.' . Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}

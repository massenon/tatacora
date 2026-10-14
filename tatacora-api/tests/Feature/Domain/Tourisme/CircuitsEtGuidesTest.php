<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Tourisme;

use App\Domain\Crm\Models\Client;
use App\Domain\Tourisme\Models\Circuit;
use App\Domain\Tourisme\Models\Guide;
use App\Domain\Tourisme\Models\ReservationTour;
use App\Domain\Tourisme\Services\ReservationTourService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Circuits, guides et prestations — EF-M9-01 à EF-M9-05.
 *
 * Deux règles y sont éprouvées que rien d'autre ne protège : la capacité
 * **cumulée** d'un départ (EF-M9-04) et l'exclusivité journalière d'un guide.
 */
final class CircuitsEtGuidesTest extends TestCase
{
    use RefreshDatabase;

    private Circuit $cascade;

    private Guide $referent;

    private Client $client;

    private User $guideUtilisateur;

    /** Date de départ fixe : un test de planning calé sur l'horloge est instable. */
    private const DEPART = '2026-09-15';

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->guideUtilisateur = $this->utilisateur('guide');
        $this->actingAs($this->guideUtilisateur);

        $this->client = Client::factory()->create();

        $this->cascade = Circuit::create([
            'nom' => 'Cascades de Tanougou', 'theme' => 'nature', 'zone' => 'Atacora',
            'duree' => 'Journée', 'prix' => '15000.00', 'capacite_max' => 12,
        ]);

        $this->referent = Guide::create([
            'nom' => 'Guide Touristique Référent', 'certification' => 'Guide national',
            'zone_competence' => 'Atacora', 'tarif_jour' => '20000.00',
        ]);
    }

    private function service(): ReservationTourService
    {
        return app(ReservationTourService::class);
    }

    // ----------------------------------------------------------- EF-M9-04

    /**
     * Le point que `SPEC_ECRAN_M9_TOURISME.md` §91 laisse ambigu : lue
     * littéralement (« nombre de participants <= capacité »), la règle
     * n'empêcherait pas trois groupes de 5 sur un circuit à 12 places.
     * EF-M9-04 parlant de « gestion des **groupes** », le contrôle porte sur
     * la somme du départ.
     */
    #[Test]
    public function ef_m9_04_la_capacite_est_cumulee_sur_le_depart_et_non_par_reservation(): void
    {
        // Le MEME guide sur les deux groupes, et ce n'est pas un detail :
        // jusqu'au 31/08/2026 ce cas passait un guide neuf a chaque appel,
        // donc eprouvait un depart a DEUX guides -- une situation qui ne peut
        // pas exister. Le cumul n'avait jamais ete verifie sur un depart reel.
        $guide = $this->nouveauGuide()->id;

        $this->reserver(5, guide: $guide);
        $this->reserver(5, guide: $guide);

        // 10/12 pris : un troisième groupe de 5 ferait 15.
        $this->assertSame(2, $this->service()->placesRestantes($this->cascade->fresh(), self::DEPART));

        $this->assertThrows(fn () => $this->reserver(5, guide: $guide), RuntimeException::class);

        $this->assertSame(2, ReservationTour::count());
    }

    #[Test]
    public function ef_m9_04_un_groupe_qui_remplit_exactement_le_depart_est_accepte(): void
    {
        // Un depart, un guide : les deux groupes montent dans le meme car.
        $guide = $this->nouveauGuide()->id;

        $this->reserver(7, guide: $guide);
        $this->reserver(5, guide: $guide);

        $this->assertSame(0, $this->service()->placesRestantes($this->cascade->fresh(), self::DEPART));
        $this->assertThrows(fn () => $this->reserver(1, guide: $guide), RuntimeException::class);
    }

    /**
     * Une annulation libère aussitôt la place, comme RG-02 le fait en M1 —
     * `reservations_tour` porte bien un `statut`, contrairement à
     * `contrats_location` (PA-50).
     */
    #[Test]
    public function une_annulation_libere_immediatement_la_place_au_depart(): void
    {
        $premiere = $this->reserver(12);

        $this->assertSame(0, $this->service()->placesRestantes($this->cascade->fresh(), self::DEPART));

        $this->service()->annuler($premiere);

        $this->assertSame(12, $this->service()->placesRestantes($this->cascade->fresh(), self::DEPART));
        // Aucun job, aucun cache : un autre groupe réserve immédiatement.
        $this->assertSame(12, $this->reserver(12)->nb_participants);
    }

    /**
     * Deux dates distinctes du même circuit ne partagent pas leur capacité.
     */
    #[Test]
    public function deux_departs_a_des_dates_differentes_ont_des_capacites_independantes(): void
    {
        $this->reserver(12);
        $autre = $this->reserver(12, date: '2026-09-16');

        $this->assertSame('2026-09-16', $autre->date_circuit->toDateString());
        $this->assertSame(2, ReservationTour::count());
    }

    // -------------------------------------------------- Exclusivité guide

    /**
     * Règle dérivée, non adossée à une RG explicite : RG-13 vise les
     * `plannings` d'employés, et un guide peut être prestataire externe. Elle
     * est appliquée parce qu'un guide ne peut physiquement pas conduire deux
     * groupes le même jour (PA-51).
     */
    #[Test]
    public function un_guide_ne_peut_pas_assurer_deux_circuits_le_meme_jour(): void
    {
        $this->reserver(4, guide: $this->referent->id);

        $autreCircuit = Circuit::create([
            'nom' => 'Village Taneka', 'theme' => 'culture', 'zone' => 'Atacora',
            'duree' => 'Demi-journée', 'prix' => '9000.00', 'capacite_max' => 10,
        ]);

        $this->assertThrows(
            fn () => $this->service()->reserver([
                'circuit_id' => $autreCircuit->id,
                'client_id' => $this->client->id,
                'guide_id' => $this->referent->id,
                'date_circuit' => self::DEPART,
                'nb_participants' => 3,
            ]),
            RuntimeException::class,
        );
    }

    #[Test]
    public function le_meme_guide_reste_affectable_un_autre_jour(): void
    {
        $this->reserver(4, guide: $this->referent->id);

        $lendemain = $this->reserver(4, guide: $this->referent->id, date: '2026-09-16');

        $this->assertSame($this->referent->id, $lendemain->guide_id);
    }

    /**
     * Une prestation annulée ne bloque plus son guide.
     */
    #[Test]
    public function un_guide_est_libere_par_l_annulation_de_sa_prestation(): void
    {
        $premiere = $this->reserver(4, guide: $this->referent->id);
        $this->service()->annuler($premiere);

        $seconde = $this->reserver(4, guide: $this->referent->id);

        $this->assertSame($this->referent->id, $seconde->guide_id);
    }

    /**
     * UC-39 — affectation après coup, avec le même contrôle d'exclusivité.
     */
    #[Test]
    public function uc39_la_reaffectation_verifie_aussi_l_exclusivite(): void
    {
        $this->reserver(4, guide: $this->referent->id);

        // ⚠ Un AUTRE depart, donc un autre CIRCUIT. Jusqu'au 31/08/2026 ce
        // cas reservait le meme circuit a la meme date sous le nom
        // `$autreDepart` : ce n'etait pas un second depart, c'etait un second
        // groupe du premier. L'exclusivite qu'il pretendait eprouver ne
        // pouvait donc pas l'etre.
        $autreCircuit = Circuit::create([
            'nom' => 'Chutes de Tanougou', 'theme' => 'nature', 'zone' => 'Atacora',
            'duree' => 'Journee', 'prix' => '11000.00', 'capacite_max' => 8,
        ]);

        $autreDepart = $this->service()->reserver([
            'circuit_id' => $autreCircuit->id,
            'client_id' => $this->client->id,
            'guide_id' => $this->nouveauGuide()->id,
            'date_circuit' => self::DEPART,
            'nb_participants' => 2,
        ]);

        // Le referent assure deja un circuit ce jour-la : le reprendre sur un
        // second depart est refuse.
        $this->assertThrows(
            fn () => $this->service()->affecterGuide($autreDepart, $this->referent->id),
            RuntimeException::class,
        );

        // Un remplacant libre passe sans difficulte — c'est le cas reel :
        // guide malade, un autre reprend le depart.
        $remplacant = Guide::create([
            'nom' => 'Guide Sud Bénin', 'certification' => 'Guide régional',
            'zone_competence' => 'Sud', 'tarif_jour' => '15000.00',
        ]);

        $this->assertSame($remplacant->id, $this->service()->affecterGuide($autreDepart, $remplacant->id)->guide_id);
    }

    /**
     * La compétence de zone est **consultative** : un remplacement en urgence
     * hors zone est un cas d'exploitation normal, le bloquer paralyserait le
     * gîte un jour de maladie.
     */
    #[Test]
    public function la_competence_de_zone_est_indicative_et_ne_bloque_pas(): void
    {
        $horsZone = Guide::create([
            'nom' => 'Guide Sud Bénin', 'certification' => 'Guide régional',
            'zone_competence' => 'Sud', 'tarif_jour' => '15000.00',
        ]);

        $this->assertFalse($horsZone->competentSurZone($this->cascade->zone));
        $this->assertTrue($this->referent->competentSurZone($this->cascade->zone));

        // ...mais l'affectation reste possible.
        $reservation = $this->reserver(3, guide: $horsZone->id);
        $this->assertSame($horsZone->id, $reservation->guide_id);
    }

    // ----------------------------------------------------------- EF-M9-05

    /**
     * `guide_id` est NOT NULL : une prestation sans guide **ne peut pas
     * exister**. Ce que ce test verifie est donc l'inverse de ce qu'on
     * attendrait a la lecture d'UC-39 — la garantie vient du schema, pas d'un
     * controle applicatif (PA-51).
     */
    #[Test]
    public function uc40_une_prestation_porte_toujours_un_guide_et_se_cloture(): void
    {
        $reservation = $this->reserver(3, guide: $this->referent->id);

        $this->assertSame($this->referent->id, $reservation->guide_id);
        $this->assertSame('terminee', $this->service()->cloturer($reservation)->statut);
    }

    /**
     * Le schema refuse lui-meme une prestation sans guide : la regle n'est pas
     * seulement applicative.
     */
    #[Test]
    public function une_reservation_sans_guide_est_refusee_des_la_validation(): void
    {
        Sanctum::actingAs($this->guideUtilisateur);

        $this->postJson('/api/v1/tourisme/reservations', [
            'circuit_id' => $this->cascade->id,
            'client_id' => $this->client->id,
            'date_circuit' => self::DEPART,
            'nb_participants' => 3,
        ])->assertStatus(422)->assertJsonValidationErrors('guide_id');
    }

    #[Test]
    public function une_prestation_cloturee_ne_peut_plus_etre_annulee(): void
    {
        $reservation = $this->reserver(3, guide: $this->referent->id);
        $this->service()->cloturer($reservation);

        $this->assertThrows(
            fn () => $this->service()->annuler($reservation->fresh()),
            RuntimeException::class,
        );
    }

    #[Test]
    public function une_prestation_annulee_ne_peut_plus_changer_de_guide(): void
    {
        $reservation = $this->reserver(3, guide: $this->referent->id);
        $this->service()->annuler($reservation);

        $this->assertThrows(
            fn () => $this->service()->affecterGuide($reservation->fresh(), $this->referent->id),
            RuntimeException::class,
        );
    }

    // ------------------------------------------------------------- Calculs

    #[Test]
    public function le_montant_est_calcule_au_prix_du_circuit_jamais_saisi(): void
    {
        $reservation = $this->reserver(4);

        // 4 × 15 000, en bcmul.
        $this->assertSame('60000.00', $reservation->montant());
    }

    // ---------------------------------------------------------------- API

    #[Test]
    public function l_api_expose_les_places_restantes_seulement_si_une_date_est_donnee(): void
    {
        Sanctum::actingAs($this->guideUtilisateur);
        $this->reserver(5);

        // Sans date, la question n'a pas de sens : null, jamais 0.
        $this->getJson('/api/v1/tourisme/circuits')
            ->assertOk()
            ->assertJsonPath('data.0.places_restantes', null);

        $this->getJson('/api/v1/tourisme/circuits?date=' . self::DEPART)
            ->assertOk()
            ->assertJsonPath('data.0.places_restantes', 7);
    }

    /**
     * EF-M9-02 — le référentiel guides n'avait aucun écran au prototype
     * (`SPEC_ECRAN_M9_TOURISME.md` §6). C'est son premier accès.
     */
    #[Test]
    public function ef_m9_02_le_referentiel_guides_est_consultable(): void
    {
        Sanctum::actingAs($this->guideUtilisateur);

        $this->getJson('/api/v1/tourisme/guides?zone=Atacora&date=' . self::DEPART)
            ->assertOk()
            ->assertJsonPath('data.0.nom', 'Guide Touristique Référent')
            ->assertJsonPath('data.0.competent_sur_zone', true)
            ->assertJsonPath('data.0.disponible', true);
    }

    #[Test]
    public function l_api_refuse_un_depassement_de_capacite_en_422(): void
    {
        Sanctum::actingAs($this->guideUtilisateur);
        $this->reserver(10);

        $this->postJson('/api/v1/tourisme/reservations', [
            'circuit_id' => $this->cascade->id,
            'client_id' => $this->client->id,
            'guide_id' => $this->nouveauGuide()->id,
            'date_circuit' => self::DEPART,
            'nb_participants' => 5,
        ])->assertStatus(422);
    }

    #[Test]
    public function l_api_est_refusee_a_un_role_sans_droit_sur_m9(): void
    {
        $sansAcces = Role::all()->first(fn (Role $role): bool => $role->niveauSurModule('M9') === '-');

        if ($sansAcces === null) {
            $this->markTestSkipped('Tous les rôles ont accès à M9 dans la matrice.');
        }

        Sanctum::actingAs($this->compteAvecRole($sansAcces));

        $this->getJson('/api/v1/tourisme/circuits')->assertForbidden();
    }

    #[Test]
    public function l_api_annule_une_reservation_sans_la_supprimer(): void
    {
        Sanctum::actingAs($this->guideUtilisateur);
        $reservation = $this->reserver(5);

        $this->patchJson("/api/v1/tourisme/reservations/{$reservation->id}/annulation")
            ->assertOk()
            ->assertJsonPath('data.statut', 'annulee');

        // La trace subsiste : aucune suppression physique.
        $this->assertDatabaseHas('reservations_tour', ['id' => $reservation->id, 'statut' => 'annulee']);
    }

    // ------------------------------------------------------------- Helpers

    /**
     * `guide_id` etant NOT NULL au schema, chaque reservation cree son propre
     * guide par defaut : sans cela, deux reservations sur le meme depart
     * buteraient sur l'exclusivite journaliere du guide, et le test de
     * capacite mesurerait la mauvaise regle.
     */
    private function reserver(
        int $participants,
        ?string $guide = null,
        string $date = self::DEPART,
    ): ReservationTour {
        return $this->service()->reserver([
            'circuit_id' => $this->cascade->id,
            'client_id' => $this->client->id,
            'guide_id' => $guide ?? $this->nouveauGuide()->id,
            'date_circuit' => $date,
            'nb_participants' => $participants,
        ]);
    }

    private function nouveauGuide(): Guide
    {
        return Guide::create([
            'nom' => 'Guide ' . Str::random(5),
            'certification' => 'Guide regional',
            'zone_competence' => 'Atacora',
            'tarif_jour' => '15000.00',
        ]);
    }

    private function utilisateur(string $role): User
    {
        return $this->compteAvecRole(Role::where('libelle', $role)->firstOrFail());
    }

    private function compteAvecRole(Role $role): User
    {
        return User::create([
            'login' => $role->libelle . '.' . Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => $role->id,
            'statut' => 'actif',
        ]);
    }
}

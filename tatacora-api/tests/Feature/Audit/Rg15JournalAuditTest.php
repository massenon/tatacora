<?php

declare(strict_types=1);

namespace Tests\Feature\Audit;

use App\Domain\Facturation\Models\Facture;
use App\Domain\Hebergement\Models\Reservation;
use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * RG-15 — Journalisation exhaustive de toute action sensible (qui, quoi, quand).
 *
 * Vérifie le trait Auditable sur les deux modèles auxquels il est appliqué
 * au Sprint 0 : Reservation (M1) et Facture (M2).
 */
final class Rg15JournalAuditTest extends TestCase
{
    use RefreshDatabase;

    private User $utilisateur;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->utilisateur = User::create([
            'login' => 'receptionniste.test',
            'mot_de_passe_hash' => 'mot-de-passe-de-test',
            'role_id' => Role::where('libelle', 'receptionniste')->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    #[Test]
    public function rg15_la_creation_d_une_reservation_alimente_le_journal_audit(): void
    {
        $this->actingAs($this->utilisateur);

        $reservation = $this->creerReservation();

        $entree = JournalAudit::where('entite_id', $reservation->id)->sole();

        $this->assertSame('creation', $entree->action);
        $this->assertSame('reservations', $entree->entite_concernee);
        $this->assertSame($this->utilisateur->id, $entree->utilisateur_id);
        $this->assertNull($entree->valeur_avant);
        $this->assertSame('en_attente', $entree->valeur_apres['statut']);
    }

    #[Test]
    public function rg15_la_modification_journalise_la_valeur_avant_et_apres(): void
    {
        $this->actingAs($this->utilisateur);

        $reservation = $this->creerReservation();
        $reservation->update(['statut' => 'confirmee']);

        $entree = JournalAudit::where('entite_id', $reservation->id)
            ->where('action', 'modification')
            ->sole();

        $this->assertSame('en_attente', $entree->valeur_avant['statut']);
        $this->assertSame('confirmee', $entree->valeur_apres['statut']);
    }

    #[Test]
    public function rg15_les_colonnes_d_audit_de_la_table_sont_renseignees(): void
    {
        $this->actingAs($this->utilisateur);

        $reservation = $this->creerReservation();

        $this->assertSame($this->utilisateur->id, $reservation->utilisateur_creation_id);
        $this->assertNotNull($reservation->date_creation);

        $reservation->update(['statut' => 'confirmee']);

        $this->assertSame($this->utilisateur->id, $reservation->fresh()->utilisateur_modification_id);
        $this->assertNotNull($reservation->fresh()->date_modification);
    }

    #[Test]
    public function rg15_la_facture_est_egalement_auditee(): void
    {
        $this->actingAs($this->utilisateur);

        $facture = Facture::create([
            'numero_mecef' => 'MECeF-TEST-00001',
            'client_id' => $this->creerClient(),
            'date_emission' => '2026-08-15',
            'montant_ht' => '100000.00',
            'montant_tva' => '18000.00',
            'montant_ttc' => '118000.00',
            'statut' => 'brouillon',
        ]);

        $entree = JournalAudit::where('entite_id', $facture->id)->sole();

        $this->assertSame('factures', $entree->entite_concernee);
        $this->assertSame('creation', $entree->action);
    }

    #[Test]
    public function rg15_les_montants_sont_compares_avec_bccomp_jamais_en_flottant(): void
    {
        // Illustre la regle A1_MASTER_PROMPT.md §2.5 sur une valeur reellement
        // relue depuis MySQL : l'egalite flottante directe est le piege a eviter.
        $this->actingAs($this->utilisateur);

        $facture = Facture::create([
            'numero_mecef' => 'MECeF-TEST-00002',
            'client_id' => $this->creerClient(),
            'date_emission' => '2026-08-15',
            'montant_ht' => '2364830.51',
            'montant_tva' => '425669.49',
            'montant_ttc' => '2790500.00',
            'statut' => 'brouillon',
        ]);

        $relue = $facture->fresh();
        $somme = bcadd((string) $relue->montant_ht, (string) $relue->montant_tva, 2);

        $this->assertSame(0, bccomp($somme, (string) $relue->montant_ttc, 2));
    }

    #[Test]
    public function rg15_aucune_entree_n_est_ecrite_sans_passer_par_le_trait(): void
    {
        $this->actingAs($this->utilisateur);
        $this->creerReservation();

        // Une seule entree pour une seule creation : le trait ne doit pas
        // journaliser en double (creating + created par exemple).
        $this->assertSame(1, JournalAudit::count());
    }

    private function creerReservation(): Reservation
    {
        return Reservation::create([
            'client_id' => $this->creerClient(),
            'unite_id' => $this->creerUnite(),
            'date_arrivee' => '2026-09-01',
            'date_depart' => '2026-09-04',
            'statut' => 'en_attente',
            'acompte' => '25000.00',
        ]);
    }

    private function creerClient(): string
    {
        $id = (string) Str::uuid();
        DB::table('clients')->insert([
            'id' => $id,
            'nom' => 'KORA',
            'prenom' => 'Jean',
            'telephone' => '01 97 35 59 74',
            'type_client' => 'particulier',
        ]);

        return $id;
    }

    private function creerUnite(): string
    {
        $categorieId = (string) Str::uuid();
        DB::table('categories_hebergement')->insert([
            'id' => $categorieId,
            'libelle' => 'Bungalow',
            'capacite_max' => 4,
            'tarif_base' => '25000.00',
        ]);

        $uniteId = (string) Str::uuid();
        DB::table('unites_hebergement')->insert([
            'id' => $uniteId,
            'categorie_id' => $categorieId,
            'numero' => 'B-01',
            'statut' => 'libre',
        ]);

        return $uniteId;
    }
}

<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ReservationService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use App\Shared\Sync\Models\DeduplicationSynchronisation;
use App\Shared\Sync\Services\ClassificationConflitService;
use App\Shared\Sync\Services\RegistreSynchronisation;
use App\Shared\Sync\Services\SynchronisationService;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Registre de gestionnaires de synchronisation — lot S1 (décisions PO du
 * 15/10/2026).
 *
 * Fige ce que le refactoring a FERMÉ : plus aucune écriture brute par la
 * synchronisation, le type annoncé confronté à l'état serveur, et la date
 * MÉTIER (jamais celle de réception) sur les pièces produites par le serveur
 * (D246).
 */
final class RegistreGestionnairesSynchronisationTest extends TestCase
{
    use RefreshDatabase;

    private User $utilisateur;

    private UniteHebergement $unite;

    private Client $client;

    protected function setUp(): void
    {
        parent::setUp();
        // Horloge figée : l'exercice semé est celui de l'année courante, et
        // les dates métier testées doivent y tomber quel que soit le jour.
        $this->travelTo('2026-10-15 12:00:00');
        $this->seed(RolePermissionSeeder::class);

        $this->utilisateur = $this->creerUtilisateur('receptionniste');

        $categorie = CategorieHebergement::create([
            'libelle' => 'Bungalow', 'capacite_max' => 4, 'tarif_base' => '25000.00',
        ]);
        $this->unite = UniteHebergement::create([
            'categorie_id' => $categorie->id, 'numero' => 'B-01', 'statut' => 'libre',
        ]);
        $this->client = Client::create([
            'nom' => 'HOUNKPATIN', 'prenom' => 'Afi', 'telephone' => '01 97 00 00 01', 'type_client' => 'particulier',
        ]);
    }

    // ------------------------------------------------------------ Registre

    /**
     * Chaque gestionnaire DÉCLARE ce que le moteur exige : module RBAC, niveau
     * d'écriture, service de domaine réel, table cohérente avec sa clé, et
     * caractère financier lu à la seule source (RG-17).
     */
    #[Test]
    public function chaque_gestionnaire_declare_module_niveau_service_et_classification(): void
    {
        $gestionnaires = app(RegistreSynchronisation::class)->tous();

        $this->assertSame([
            'reservations', 'sejours', 'clients', 'fournisseurs',
            // Catalogue (S2, 15/10/2026) — création seule, fusion sur clé naturelle.
            'points_stockage', 'articles', 'cartes_boisson', 'menus', 'recettes', 'plats',
            'categories_hebergement', 'unites_hebergement',
            // Documents (S3, 15/10/2026) — dans l'ordre de poussée : la
            // commande avant son bon, l'ouverture de caisse avant ses ventes.
            'commandes_achat', 'bons_reception', 'sessions_caisse', 'ventes', 'depenses',
            // Tourisme (F4, 17/10/2026) — les définitions avant la réservation.
            'circuits', 'guides', 'reservations_tour',
        ], array_keys($gestionnaires));

        foreach ($gestionnaires as $table => $gestionnaire) {
            $this->assertSame($table, $gestionnaire->table());
            $this->assertMatchesRegularExpression('/^M\d{1,2}$/', $gestionnaire->module(), $table);
            $this->assertSame('C', $gestionnaire->niveauRequis(), $table);
            $this->assertTrue(class_exists($gestionnaire->serviceDomaine()), "{$table} : service de domaine inexistant.");
            $this->assertSame(
                in_array($table, ClassificationConflitService::TABLES_FINANCIERES, true),
                $gestionnaire->estFinanciere(),
                $table,
            );
        }

        $this->assertSame('M7', $gestionnaires['fournisseurs']->module());
    }

    /**
     * Le chemin `DB::table($table)->insert/update($payload)` n'existe plus dans
     * le moteur : c'était la porte par laquelle la synchronisation écrivait
     * sans les règles de gestion. Garde par lecture du source — un retour du
     * repli brut ferait rougir ce test avant d'atteindre un poste.
     */
    #[Test]
    public function le_moteur_n_ecrit_plus_aucune_table_metier_en_brut(): void
    {
        $source = (string) file_get_contents(app_path('Shared/Sync/Services/SynchronisationService.php'));

        $this->assertDoesNotMatchRegularExpression('/DB::table\(\$table\)[^;]*->(insert|update)\(/s', $source);
        $this->assertStringNotContainsString('->insert([...$payload', $source);
    }

    #[Test]
    public function une_table_hors_registre_reste_refusee(): void
    {
        $this->synchroniser([$this->operation('factures', 'creation', (string) Str::uuid(), ['montant' => '1000'])])
            ->assertOk()
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.table_non_synchronisable', ['table' => 'factures']));
    }

    // -------------------------------------------- Modification : par le gestionnaire ou refusée

    /**
     * `reservations` REFUSE la modification (aucune route d'API ne l'offre) :
     * avant le 15/10/2026, cette opération déplaçait le séjour par un UPDATE
     * brut, sans repasser par RG-01, et pouvait basculer `statut`/`acompte`.
     */
    #[Test]
    public function une_modification_de_reservation_est_refusee_explicitement(): void
    {
        $reservation = app(ReservationService::class)->creer([
            'client_id' => $this->client->id, 'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-11-01', 'date_depart' => '2026-11-03', 'statut' => 'confirmee',
        ]);

        $this->synchroniser([$this->operation('reservations', 'modification', $reservation->id, [
            'date_arrivee' => '2026-12-01', 'date_depart' => '2026-12-05', 'statut' => 'annulee',
        ])])
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.modification_non_synchronisable'));

        $reservation->refresh();
        $this->assertSame('2026-11-01', $reservation->date_arrivee->toDateString());
        $this->assertSame('confirmee', $reservation->statut);
    }

    /**
     * `clients` ACCEPTE la modification, par `EnregistrementClientService` :
     * l'audit RG-15 est tenu, et `actif` — que seul le service d'archivage
     * bascule, sous son verrou d'engagement — n'est plus jamais écrit par ce
     * chemin (l'UPDATE brut l'écrivait).
     */
    #[Test]
    public function une_modification_client_passe_par_le_service_et_n_archive_rien(): void
    {
        $this->synchroniser([$this->operation('clients', 'modification', $this->client->id, [
            'nom' => 'HOUNKPATIN-AGBO', 'actif' => false,
        ])])->assertJsonPath('resultats.0.statut', 'synchronise');

        $fiche = $this->client->fresh();
        $this->assertSame('HOUNKPATIN-AGBO', $fiche->nom);
        $this->assertTrue($fiche->actif, 'Le payload ne doit pas pouvoir archiver une fiche client.');
        $this->assertSame($this->utilisateur->id, $fiche->utilisateur_modification_id);
        $this->assertDatabaseHas('journal_audit', [
            'entite_concernee' => 'clients', 'entite_id' => $this->client->id, 'action' => 'modification',
        ]);
    }

    #[Test]
    public function une_modification_client_invalide_est_rejetee_avec_la_phrase_de_l_api(): void
    {
        $reponse = $this->synchroniser([$this->operation('clients', 'modification', $this->client->id, [
            'type_client' => 'touriste',
        ])]);

        $reponse->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('crm.validation.type_invalide'))
            ->assertJsonPath('resultats.0.erreurs.type_client.0', __('crm.validation.type_invalide'));

        $this->assertSame('particulier', $this->client->fresh()->type_client);
    }

    /**
     * Création par le service : l'UUID du poste est conservé, et RG-18 reste
     * AVERTISSANTE — l'homonyme est créé, l'avertissement accompagne le résultat.
     */
    #[Test]
    public function une_creation_client_passe_par_le_service_avec_l_avertissement_de_doublon(): void
    {
        $id = (string) Str::uuid();

        $reponse = $this->synchroniser([$this->operation('clients', 'creation', $id, [
            'nom' => 'HOUNKPATIN', 'telephone' => '01 97 00 00 01', 'type_client' => 'particulier',
        ])]);

        $reponse->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.entite_id', $id);
        $this->assertNotNull($reponse->json('resultats.0.avertissement_doublon'));
        $this->assertDatabaseHas('clients', ['id' => $id, 'nom' => 'HOUNKPATIN']);
    }

    // ------------------------------------------------- Type annoncé ↔ état serveur

    #[Test]
    public function une_modification_d_un_identifiant_inconnu_est_rejetee(): void
    {
        $id = (string) Str::uuid();

        $this->synchroniser([$this->operation('clients', 'modification', $id, ['nom' => 'FANTOME'])])
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.modification_entite_inconnue'));

        $this->assertDatabaseMissing('clients', ['id' => $id]);
    }

    /**
     * Avant le 15/10/2026, une « création » sur un identifiant existant
     * devenait une mise à jour brute : n'importe quelle fiche se réécrivait en
     * l'annonçant nouvelle.
     */
    #[Test]
    public function une_creation_sur_un_identifiant_existant_est_rejetee_sans_rien_ecrire(): void
    {
        $this->synchroniser([$this->operation('clients', 'creation', $this->client->id, [
            'nom' => 'ECRASE', 'telephone' => '00', 'type_client' => 'particulier',
        ])])
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.creation_entite_existante'));

        $this->assertSame('HOUNKPATIN', $this->client->fresh()->nom);
    }

    // ------------------------------------------------------------ Date métier (D246)

    /**
     * L'acompte d'une réservation saisie hors connexion le 03/10 et
     * synchronisée le 15/10 appartient au tiroir du 03/10 : la pièce produite
     * par le serveur porte la date MÉTIER, pas la date de réception.
     */
    #[Test]
    public function la_date_metier_explicite_date_la_piece_produite_par_le_serveur(): void
    {
        $this->seed(ComptabiliteReferentielSeeder::class);

        $this->synchroniser([$this->operationReservationAvecAcompte([
            'date_metier' => '2026-10-03',
        ], horodatage: '2026-10-04T08:00:00+01:00')])->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame(['2026-10-03'], $this->datesDesPiecesDAcompte());
    }

    /**
     * Sans date explicite, la date de SAISIE du poste — jamais `now()`.
     */
    #[Test]
    public function a_defaut_la_date_de_saisie_du_poste_date_la_piece(): void
    {
        $this->seed(ComptabiliteReferentielSeeder::class);

        $this->synchroniser([$this->operationReservationAvecAcompte([], horodatage: '2026-10-05T09:30:00+01:00')])
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame(['2026-10-05'], $this->datesDesPiecesDAcompte());
    }

    #[Test]
    public function une_date_metier_illisible_rejette_l_operation_sans_rien_ecrire(): void
    {
        $this->synchroniser([$this->operationReservationAvecAcompte(['date_metier' => 'lundi dernier'])])
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.date_metier_invalide'));

        $this->assertSame(0, Reservation::count());
    }

    // ------------------------------------------------------------ Idempotence 30 jours

    /**
     * Un poste resté trois semaines sans serveur rejoue sa file : sous l'ancien
     * TTL (7 jours), la mémoire aurait été purgée et la réservation recréée —
     * ici, rejetée par RG-01 au mieux, dupliquée au pire sur une autre table.
     */
    #[Test]
    public function un_rejeu_apres_trois_semaines_reste_idempotent(): void
    {
        $operation = $this->operation('reservations', 'creation', (string) Str::uuid(), [
            'client_id' => $this->client->id, 'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-11-10', 'date_depart' => '2026-11-12', 'statut' => 'confirmee',
        ]);

        $this->synchroniser([$operation])->assertJsonPath('resultats.0.statut', 'synchronise');

        DeduplicationSynchronisation::query()->update(['date_traitement' => now()->subDays(21)]);
        $this->assertSame(0, app(SynchronisationService::class)->purgerDeduplication());

        $this->synchroniser([$operation])
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.rejeu_idempotent', true);
        $this->assertSame(1, Reservation::count());
    }

    // ------------------------------------------------------------- Helpers

    /**
     * @return list<string>
     */
    private function datesDesPiecesDAcompte(): array
    {
        $compte4191 = CompteComptable::query()->where('numero_compte', '4191')->value('id');

        return EcritureComptable::query()
            ->where('compte_id', $compte4191)
            ->get()
            ->map(static fn (EcritureComptable $e): string => $e->date_ecriture->toDateString())
            ->all();
    }

    /**
     * @param  array<string, mixed>  $complements
     * @return array<string, mixed>
     */
    private function operationReservationAvecAcompte(array $complements, string $horodatage = '2026-10-04T08:00:00+01:00'): array
    {
        return $this->operation('reservations', 'creation', (string) Str::uuid(), [
            'client_id' => $this->client->id, 'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-11-01', 'date_depart' => '2026-11-03', 'statut' => 'confirmee',
            'acompte' => '10000.00', 'mode_paiement' => 'especes',
            ...$complements,
        ], $horodatage);
    }

    /**
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    private function operation(string $table, string $type, string $entiteId, array $payload, ?string $horodatage = null): array
    {
        return [
            'uuid_operation' => (string) Str::uuid(),
            'table' => $table,
            'type' => $type,
            'entite_id' => $entiteId,
            'payload' => $payload,
            'horodatage_client' => $horodatage ?? now()->toIso8601String(),
        ];
    }

    /**
     * @param  list<array<string, mixed>>  $operations
     * @return TestResponse<\Illuminate\Http\JsonResponse>
     */
    private function synchroniser(array $operations, string $poste = 'poste-windows-1'): TestResponse
    {
        Sanctum::actingAs($this->utilisateur);

        return $this->postJson('/api/v1/sync', ['poste_id' => $poste, 'operations' => $operations]);
    }

    private function creerUtilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.' . Str::random(5),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}

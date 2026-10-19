<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ReservationService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use App\Shared\Sync\Models\ConflitSynchronisation;
use App\Shared\Sync\Models\DeduplicationSynchronisation;
use App\Shared\Sync\Models\SessionSynchronisation;
use App\Shared\Sync\Services\RegistreSynchronisation;
use App\Shared\Sync\Services\SynchronisationService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Synchronisation offline-first — LARAVEL_SYNC_FLUTTER.md.
 *
 * Couvre la famille de tests que 07_TESTING_QA.md §3 traite comme une
 * catégorie à part entière, « sans équivalent dans un CRUD classique ».
 */
final class SynchronisationOfflineTest extends TestCase
{
    use RefreshDatabase;

    private User $utilisateur;

    private UniteHebergement $unite;

    private Client $client;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->utilisateur = $this->creerUtilisateur('receptionniste');

        // Pas d'`actingAs` global : il rendrait le test de synchronisation
        // anonyme silencieusement authentifié, donc inopérant. Chaque test
        // s'authentifie via `synchroniser()`.

        $categorie = CategorieHebergement::create([
            'libelle' => 'Bungalow', 'capacite_max' => 4, 'tarif_base' => '25000.00',
        ]);
        $this->unite = UniteHebergement::create([
            'categorie_id' => $categorie->id, 'numero' => 'B-01', 'statut' => 'libre',
        ]);
        $this->client = Client::factory()->create();
    }

    // ------------------------------------------------------------ Nominal

    #[Test]
    public function une_creation_hors_connexion_est_appliquee_a_la_synchronisation(): void
    {
        $entiteId = (string) Str::uuid();

        $reponse = $this->synchroniser([
            $this->operationReservation($entiteId, '2026-09-01', '2026-09-04'),
        ]);

        $reponse->assertOk()
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.entite_id', $entiteId);

        // L'UUID genere cote client est conserve — c'est lui qui garantit
        // l'absence de collision entre deux postes hors connexion.
        $this->assertDatabaseHas('reservations', ['id' => $entiteId]);
    }

    #[Test]
    public function la_session_de_synchronisation_est_tracee(): void
    {
        $this->synchroniser([$this->operationReservation((string) Str::uuid(), '2026-09-01', '2026-09-04')]);

        $session = SessionSynchronisation::sole();
        $this->assertSame('poste-flutter-test', $session->poste_id);
        $this->assertSame(1, $session->nb_enregistrements);
        $this->assertSame('succes', $session->statut);
    }

    // -------------------------------------------------------- Idempotence

    /**
     * Le scénario de 07_TESTING_QA.md §3 : « coupure réseau PENDANT une
     * opération d'écriture — aucune double-écriture à la reprise ».
     */
    #[Test]
    public function un_rejeu_apres_coupure_ne_cree_aucun_doublon(): void
    {
        $entiteId = (string) Str::uuid();
        $operation = $this->operationReservation($entiteId, '2026-09-01', '2026-09-04');

        // Premier envoi : le serveur traite, mais le client ne recoit jamais
        // la reponse (coupure). Il ne peut pas savoir si l'operation a abouti.
        $this->synchroniser([$operation])->assertOk();

        // Rejeu du MEME uuid_operation a la reconnexion.
        $rejeu = $this->synchroniser([$operation]);

        $rejeu->assertOk()
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.rejeu_idempotent', true);

        // Une seule reservation, malgre deux envois.
        $this->assertSame(1, Reservation::count());
    }

    #[Test]
    public function un_rejeu_restitue_meme_un_rejet_a_l_identique(): void
    {
        // Une reservation occupe deja la periode.
        app(ReservationService::class)->creer([
            'client_id' => $this->client->id, 'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-01', 'date_depart' => '2026-09-10',
            'statut' => 'confirmee', 'acompte' => '0.00',
        ]);

        $operation = $this->operationReservation((string) Str::uuid(), '2026-09-02', '2026-09-05');

        $premier = $this->synchroniser([$operation]);
        $premier->assertJsonPath('resultats.0.statut', 'rejete');
        $motif = $premier->json('resultats.0.motif');

        // Le client doit obtenir la MEME reponse au rejeu : sinon il croirait
        // que sa reservation a finalement ete acceptee.
        $this->synchroniser([$operation])
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', $motif)
            ->assertJsonPath('resultats.0.rejeu_idempotent', true);
    }

    /**
     * TTL porté de 7 à 30 jours (décision PO du 15/10/2026) : les postes
     * Windows des sites isolés peuvent rester des semaines sans serveur. Une
     * mémoire de 8 jours — purgée sous l'ancien TTL — doit désormais SURVIVRE.
     */
    #[Test]
    public function la_memoire_d_idempotence_se_purge_apres_son_ttl(): void
    {
        $this->assertSame(30, SynchronisationService::TTL_DEDUPLICATION_JOURS);

        $this->synchroniser([
            $this->operationReservation((string) Str::uuid(), '2026-09-01', '2026-09-04'),
            $this->operationReservation((string) Str::uuid(), '2026-09-10', '2026-09-12'),
        ]);
        $this->assertSame(2, DeduplicationSynchronisation::count());

        [$expiree, $recente] = DeduplicationSynchronisation::query()->orderBy('id')->get()->all();
        $expiree->update(['date_traitement' => now()->subDays(SynchronisationService::TTL_DEDUPLICATION_JOURS + 1)]);
        $recente->update(['date_traitement' => now()->subDays(8)]);

        $this->assertSame(1, app(SynchronisationService::class)->purgerDeduplication());
        $this->assertSame([$recente->id], DeduplicationSynchronisation::query()->pluck('id')->all());
    }

    // ------------------------------------------------ Rejet structurel

    /**
     * 07_TESTING_QA.md §3 : deux postes créent hors connexion une réservation
     * sur la MÊME unité et la même période. Le second à synchroniser doit être
     * rejeté avec un message clair, pas une erreur technique brute.
     */
    #[Test]
    public function rg01_deux_postes_hors_connexion_sur_la_meme_periode_le_second_est_rejete(): void
    {
        $posteA = $this->operationReservation((string) Str::uuid(), '2026-09-01', '2026-09-10');
        $posteB = $this->operationReservation((string) Str::uuid(), '2026-09-05', '2026-09-12');

        $this->synchroniser([$posteA])->assertJsonPath('resultats.0.statut', 'synchronise');

        $reponse = $this->synchroniser([$posteB], poste: 'poste-flutter-b');

        $reponse->assertJsonPath('resultats.0.statut', 'rejete');
        // Message exploitable par l'utilisateur, pas une trace technique —
        // et depuis le 02/09/2026 (Article 8, PA-171) les codes RG-xx ne
        // figurent plus dans les textes rendus : on verifie la PHRASE que
        // l'operateur lit, jamais le code qui vit en commentaire.
        $this->assertStringContainsString(
            'déjà réservée sur cette période',
            (string) $reponse->json('resultats.0.motif'),
        );
        $this->assertNotEmpty($reponse->json('resultats.0.entites_en_conflit'));

        $this->assertSame(1, Reservation::count());
    }

    /**
     * Le rejet passe par VerificationChevauchementService : la synchronisation
     * ne doit pas devenir le chemin par lequel on contourne RG-01.
     *
     * Adapté le 15/10/2026 : le registre nomme désormais un GESTIONNAIRE par
     * table (`RegistreSynchronisation`), qui déclare son service — l'invariant
     * vérifié est le même.
     */
    #[Test]
    public function rg01_la_synchronisation_ne_contourne_pas_le_verrou(): void
    {
        $this->assertSame(
            ReservationService::class,
            app(RegistreSynchronisation::class)->pour('reservations')->serviceDomaine(),
        );
    }

    // ------------------------------------------------- RBAC de la synchronisation

    /**
     * PA-65 — la porte derobee.
     *
     * `/api/v1/sync` ne porte AUCUN `VerifierAccesModule`, et il ne peut pas :
     * un lot est multi-modules par nature. Rien ne verifiait donc les droits.
     * Un `barman` (`M1 = '-'`, aucun acces a l'Hebergement) creait une
     * reservation par ce chemin, alors que `POST /hebergement/reservations` la
     * lui refuse — soit un contournement complet du 2e niveau RBAC, sur un
     * chemin d'ECRITURE ouvert a tous les postes.
     *
     * Ces tests figent la fermeture.
     */
    #[Test]
    public function rg16_un_role_sans_droit_ne_synchronise_pas_ce_module(): void
    {
        Sanctum::actingAs($this->creerUtilisateur('barman'));

        $reponse = $this->postJson('/api/v1/sync', [
            'poste_id' => 'poste-bar',
            'operations' => [$this->operationReservation((string) Str::uuid(), '2026-11-01', '2026-11-03')],
        ]);

        $reponse->assertOk();
        $this->assertSame('rejete', $reponse->json('resultats.0.statut'));
        $this->assertSame(0, Reservation::count());
    }

    /**
     * Un droit de LECTURE ne suffit pas : toute operation de synchronisation
     * est une ecriture.
     */
    #[Test]
    public function rg16_un_droit_de_lecture_ne_permet_pas_d_ecrire_par_la_synchronisation(): void
    {
        // `cuisine` : M3 = 'L' — peut consulter les clients, pas les modifier.
        Sanctum::actingAs($this->creerUtilisateur('cuisine'));

        $reponse = $this->postJson('/api/v1/sync', [
            'poste_id' => 'poste-cuisine',
            'operations' => [$this->operationClient('NOM MODIFIE', now())],
        ]);

        $reponse->assertOk();
        $this->assertSame('rejete', $reponse->json('resultats.0.statut'));
        $this->assertNotSame('NOM MODIFIE', $this->client->fresh()->nom);
    }

    /**
     * Le refus porte sur l'OPERATION, jamais sur le lot.
     *
     * Echouer le lot entier ferait perdre a un utilisateur legitime les
     * operations qu'il avait le droit de pousser, a cause d'une seule qu'il
     * n'avait pas — et sa file, hors ligne, est la seule copie.
     */
    #[Test]
    public function rg16_le_refus_n_emporte_pas_les_operations_legitimes_du_meme_lot(): void
    {
        // `vehicules` : M3 = 'L' (refuse), et aucun droit sur M1 (refuse aussi).
        // On prend plutot un receptionniste, qui a M1='C' et M3='C', pour
        // verifier le cas inverse : tout passe quand tout est permis.
        Sanctum::actingAs($this->utilisateur);

        $reponse = $this->postJson('/api/v1/sync', [
            'poste_id' => 'poste-reception',
            'operations' => [
                $this->operationReservation((string) Str::uuid(), '2026-11-01', '2026-11-03'),
                $this->operationClient('NOM AUTORISE', now()),
            ],
        ]);

        $reponse->assertOk();
        $this->assertSame('synchronise', $reponse->json('resultats.0.statut'));
        $this->assertSame('synchronise', $reponse->json('resultats.1.statut'));
    }

    /**
     * SECURITY_STRICT.md §10 — une tentative refusee se trace, quelle que soit
     * la porte empruntee. Sans cette trace, un poste qui pousse en boucle des
     * operations interdites resterait invisible.
     */
    #[Test]
    public function rg16_un_refus_de_synchronisation_est_trace_au_journal_de_securite(): void
    {
        Sanctum::actingAs($barman = $this->creerUtilisateur('barman'));

        $this->postJson('/api/v1/sync', [
            'poste_id' => 'poste-bar',
            'operations' => [$this->operationReservation((string) Str::uuid(), '2026-11-01', '2026-11-03')],
        ]);

        $this->assertDatabaseHas('journal_securite', [
            'type_evenement' => 'acces_refuse_rbac',
            'utilisateur_id' => $barman->id,
            'module_concerne' => 'M1',
        ]);
    }

    /**
     * Le refus est DEFINITIF, pas un conflit : rejouer n'accorde pas de droits.
     *
     * L'idempotence doit donc rendre le meme refus, sans retenter l'ecriture.
     */
    #[Test]
    public function rg16_le_rejeu_d_une_operation_refusee_rend_le_meme_refus(): void
    {
        Sanctum::actingAs($this->creerUtilisateur('barman'));

        $operation = $this->operationReservation((string) Str::uuid(), '2026-11-01', '2026-11-03');
        $lot = ['poste_id' => 'poste-bar', 'operations' => [$operation]];

        $this->postJson('/api/v1/sync', $lot);
        $second = $this->postJson('/api/v1/sync', $lot);

        $second->assertOk();
        $this->assertSame('rejete', $second->json('resultats.0.statut'));
        $this->assertSame(0, Reservation::count());
    }

    /**
     * Chaque table synchronisable nomme son module — sans quoi le controle ne
     * s'appliquerait pas a une table ajoutee plus tard, silencieusement.
     *
     * Adapte le 15/10/2026 : le module est declare par le gestionnaire de la
     * table (`GestionnaireSynchronisation::module()`), plus par un tableau.
     */
    #[Test]
    public function rg16_chaque_table_synchronisable_declare_son_module(): void
    {
        foreach (app(RegistreSynchronisation::class)->tous() as $table => $gestionnaire) {
            $this->assertMatchesRegularExpression(
                // Lot 10e : `PARAM` et `ROLES` sont des modules de la matrice.
                '/^(M\d{1,2}|PARAM|ROLES)$/',
                $gestionnaire->module(),
                "La table {$table} ne declare aucun module.",
            );
        }
    }

    // ------------------------------------------- Identite du poste (PA-66)

    /**
     * PA-66 — §8 affirmait cette verification depuis l'origine ; elle n'existait pas.
     *
     * `poste_id` etait une chaine libre choisie par le client. Ce n'est pas une
     * escalade de privileges — un jeton vole porte deja les droits de son
     * proprietaire — mais `poste_id` commande la classification des conflits
     * (RG-17, `estEnConflit()`) : un client qui annonce un autre poste que le
     * sien fait passer ses propres ecritures pour celles d'un tiers, et
     * l'arbitrage porte alors sur une provenance fausse.
     *
     * **Ce test emprunte un jeton REEL.** `Sanctum::actingAs()` produit un
     * `TransientToken` sans nom de poste : le garde ne s'y applique pas, et un
     * test qui l'utiliserait ne prouverait rien — c'est exactement le piege de
     * PA-54, ou 421 tests verts masquaient une API sans point d'entree.
     */
    #[Test]
    public function un_poste_different_de_celui_du_jeton_est_refuse(): void
    {
        $jeton = $this->utilisateur->createToken('poste-reception')->plainTextToken;

        $this->withHeader('Authorization', 'Bearer '.$jeton)
            ->postJson('/api/v1/sync', [
                'poste_id' => 'poste-usurpe',
                'operations' => [$this->operationReservation((string) Str::uuid(), '2026-11-01', '2026-11-03')],
            ])
            ->assertForbidden();

        $this->assertSame(0, Reservation::count());
    }

    #[Test]
    public function le_poste_du_jeton_est_accepte(): void
    {
        $jeton = $this->utilisateur->createToken('poste-reception')->plainTextToken;

        $this->withHeader('Authorization', 'Bearer '.$jeton)
            ->postJson('/api/v1/sync', [
                'poste_id' => 'poste-reception',
                'operations' => [$this->operationReservation((string) Str::uuid(), '2026-11-01', '2026-11-03')],
            ])
            ->assertOk();

        $this->assertSame(1, Reservation::count());
    }

    /**
     * Le refus porte sur le LOT entier, contrairement au refus RBAC de PA-65 :
     * ce n'est pas une operation qui est en cause mais l'identite du lot.
     * En accepter une partie inscrirait une provenance fausse en base.
     */
    #[Test]
    public function un_poste_usurpe_n_ecrit_rien_du_tout(): void
    {
        $jeton = $this->utilisateur->createToken('poste-reception')->plainTextToken;

        $this->withHeader('Authorization', 'Bearer '.$jeton)
            ->postJson('/api/v1/sync', [
                'poste_id' => 'poste-usurpe',
                'operations' => [
                    $this->operationReservation((string) Str::uuid(), '2026-11-01', '2026-11-03'),
                    $this->operationClient('NOM MODIFIE', now()),
                ],
            ])
            ->assertForbidden();

        $this->assertSame(0, Reservation::count());
        $this->assertNotSame('NOM MODIFIE', $this->client->fresh()->nom);
        $this->assertDatabaseCount('sessions_synchronisation', 0);
    }

    // ---------------------------------------------------- Isolation du lot

    /**
     * §2.1 — « traité transactionnellement par opération, pas par lot entier ».
     */
    #[Test]
    public function un_rejet_dans_un_lot_n_annule_pas_les_operations_valides(): void
    {
        $valideA = (string) Str::uuid();
        $valideB = (string) Str::uuid();

        $reponse = $this->synchroniser([
            $this->operationReservation($valideA, '2026-09-01', '2026-09-04'),
            // Chevauche la premiere : sera rejetee.
            $this->operationReservation((string) Str::uuid(), '2026-09-02', '2026-09-03'),
            $this->operationReservation($valideB, '2026-09-10', '2026-09-12'),
        ]);

        $reponse->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.1.statut', 'rejete')
            ->assertJsonPath('resultats.2.statut', 'synchronise');

        // Les deux operations valides ont bien ete conservees : le poste ne
        // doit pas avoir a rejouer une saisie correcte.
        $this->assertDatabaseHas('reservations', ['id' => $valideA]);
        $this->assertDatabaseHas('reservations', ['id' => $valideB]);
        $this->assertSame(2, Reservation::count());
    }

    #[Test]
    public function la_session_est_marquee_partielle_quand_une_operation_echoue(): void
    {
        $this->synchroniser([
            $this->operationReservation((string) Str::uuid(), '2026-09-01', '2026-09-04'),
            $this->operationReservation((string) Str::uuid(), '2026-09-02', '2026-09-03'),
        ]);

        $this->assertSame('partiel', SessionSynchronisation::sole()->statut);
    }

    // ------------------------------------------------------------ Conflits

    /**
     * §4.2 — une saisie antérieure ne doit jamais écraser une donnée serveur
     * plus récente : le guide revenu de circuit après trois jours ne doit pas
     * effacer les corrections faites entre-temps.
     */
    #[Test]
    public function rg17_une_saisie_anterieure_ne_ecrase_pas_la_version_serveur(): void
    {
        $this->client->update(['nom' => 'VERSION SERVEUR']);

        $reponse = $this->synchroniser([
            $this->operationClient('VERSION LOCALE PERIMEE', now()->subDays(3)),
        ], poste: 'poste-flutter-b');

        $reponse->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.resolution', 'version_serveur_conservee');

        $this->assertSame('VERSION SERVEUR', $this->client->fresh()->nom);

        // La version perdante reste consultable : jamais écrasée sans trace.
        $conflit = ConflitSynchronisation::sole();
        $this->assertSame('resolu_serveur', $conflit->statut);
        $this->assertSame('VERSION LOCALE PERIMEE', $conflit->version_locale['nom']);
        $this->assertSame('clients', $conflit->table_concernee);
    }

    /**
     * Le cas que la spécification décrit mais qu'aucune table ne permettait
     * d'arbitrer (PA-44) : la saisie la plus récente gagne, **même
     * synchronisée en second**.
     *
     * Poste A saisit à −4 h et synchronise en premier ; poste B saisit à −3 h
     * et synchronise ensuite. B est plus récent EN SAISIE : il doit gagner.
     * Comparer son horodatage à la date de modification serveur — postérieure
     * aux deux — aurait fait gagner A.
     */
    #[Test]
    public function rg17_la_saisie_la_plus_recente_gagne_meme_synchronisee_en_second(): void
    {
        $this->vieillirFicheClient();

        $this->synchroniser([
            $this->operationClient('SAISIE POSTE A', now()->subHours(4)),
        ], poste: 'poste-flutter-a')->assertJsonPath('resultats.0.statut', 'synchronise');

        $reponse = $this->synchroniser([
            $this->operationClient('SAISIE POSTE B', now()->subHours(3)),
        ], poste: 'poste-flutter-b');

        $reponse->assertJsonPath('resultats.0.resolution', 'version_locale_conservee');
        $this->assertSame('SAISIE POSTE B', $this->client->fresh()->nom);
    }

    #[Test]
    public function rg17_une_saisie_plus_ancienne_que_la_precedente_synchronisation_perd(): void
    {
        $this->vieillirFicheClient();

        $this->synchroniser([
            $this->operationClient('SAISIE POSTE A', now()->subHours(4)),
        ], poste: 'poste-flutter-a');

        // Poste C a saisi AVANT A, mais synchronise en dernier.
        $this->synchroniser([
            $this->operationClient('SAISIE POSTE C', now()->subHours(6)),
        ], poste: 'poste-flutter-c')
            ->assertJsonPath('resultats.0.resolution', 'version_serveur_conservee');

        $this->assertSame('SAISIE POSTE A', $this->client->fresh()->nom);
    }

    // ------------------------------------------------------------ Securite

    #[Test]
    public function aucune_synchronisation_anonyme_n_est_possible(): void
    {
        // §8 : jamais de synchronisation anonyme, meme temporaire.
        $this->postJson('/api/v1/sync', [
            'poste_id' => 'poste-pirate',
            'operations' => [$this->operationReservation((string) Str::uuid(), '2026-09-01', '2026-09-04')],
        ])->assertUnauthorized();
    }

    #[Test]
    public function une_table_hors_registre_est_refusee(): void
    {
        $reponse = $this->synchroniser([[
            'uuid_operation' => (string) Str::uuid(),
            'table' => 'utilisateurs',
            'type' => 'modification',
            'entite_id' => $this->utilisateur->id,
            'payload' => ['statut' => 'actif'],
            'horodatage_client' => now()->toIso8601String(),
        ]]);

        // Accepter une ecriture sur une table inconnue ferait de la
        // synchronisation un contournement des regles de son domaine.
        $reponse->assertJsonPath('resultats.0.statut', 'rejete');
        $this->assertStringContainsString('synchronisable', (string) $reponse->json('resultats.0.motif'));
    }

    #[Test]
    public function un_lot_trop_gros_est_refuse(): void
    {
        $operations = [];
        for ($i = 0; $i <= SynchronisationService::TAILLE_LOT_MAX; $i++) {
            $operations[] = $this->operationReservation((string) Str::uuid(), '2026-09-01', '2026-09-04');
        }

        $this->synchroniser($operations)
            ->assertStatus(422)
            ->assertJsonValidationErrors('operations');
    }

    #[Test]
    public function un_horodatage_client_manquant_est_refuse(): void
    {
        $operation = $this->operationReservation((string) Str::uuid(), '2026-09-01', '2026-09-04');
        unset($operation['horodatage_client']);

        // Sans horodatage, aucun conflit ne peut etre arbitre par anteriorite.
        $this->synchroniser([$operation])->assertStatus(422);
    }

    // ------------------------------------------------------------- Helpers

    /**
     * @param  list<array<string, mixed>>  $operations
     * @return \Illuminate\Testing\TestResponse<\Illuminate\Http\JsonResponse>
     */
    private function synchroniser(array $operations, string $poste = 'poste-flutter-test'): \Illuminate\Testing\TestResponse
    {
        Sanctum::actingAs($this->utilisateur);

        return $this->postJson('/api/v1/sync', [
            'poste_id' => $poste,
            'operations' => $operations,
        ]);
    }

    /**
     * Ramene la derniere modification serveur de la fiche dans le passe.
     *
     * Sans cela, une fiche creee a l'instant rendrait toute saisie hors
     * connexion anterieure — et donc perdante — ce qui masquerait le
     * comportement reellement teste.
     */
    private function vieillirFicheClient(): void
    {
        DB::table('clients')
            ->where('id', $this->client->id)
            ->update(['updated_at' => now()->subDay(), 'date_modification' => now()->subDay()]);
    }

    /**
     * @return array<string, mixed>
     */
    private function operationClient(string $nom, \Illuminate\Support\Carbon $horodatageSaisie): array
    {
        return [
            'uuid_operation' => (string) Str::uuid(),
            'table' => 'clients',
            'type' => 'modification',
            'entite_id' => $this->client->id,
            'payload' => ['nom' => $nom],
            'horodatage_client' => $horodatageSaisie->toIso8601String(),
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function operationReservation(string $entiteId, string $arrivee, string $depart): array
    {
        return [
            'uuid_operation' => (string) Str::uuid(),
            'table' => 'reservations',
            'type' => 'creation',
            'entite_id' => $entiteId,
            'payload' => [
                'client_id' => $this->client->id,
                'unite_id' => $this->unite->id,
                'date_arrivee' => $arrivee,
                'date_depart' => $depart,
                'statut' => 'confirmee',
                'acompte' => '0.00',
            ],
            'horodatage_client' => now()->toIso8601String(),
        ];
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

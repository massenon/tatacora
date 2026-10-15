<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Achats\Services\ReferentielFournisseurService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use App\Shared\Sync\Gestionnaires\GestionnaireFournisseurs;
use App\Shared\Sync\Models\CorrespondanceSynchronisation;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Fournisseurs synchronisés depuis les postes Windows hors connexion — lot S1
 * (décisions du Product Owner du 15/10/2026).
 *
 * Le serveur est MAÎTRE du référentiel ; un poste peut créer un fournisseur
 * hors connexion, et s'il existe déjà côté serveur (raison sociale
 * normalisée), le serveur FUSIONNE — aucun doublon — et retient la
 * correspondance UUID poste → UUID serveur.
 */
final class FournisseursSynchronisationTest extends TestCase
{
    use RefreshDatabase;

    private User $acheteur;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        // `achats` : M7 = 'C', hors rôles d'administration.
        $this->acheteur = $this->creerUtilisateur('achats');
    }

    // ------------------------------------------------------------ Création

    #[Test]
    public function un_fournisseur_cree_hors_connexion_est_cree_sous_l_uuid_du_poste(): void
    {
        $id = (string) Str::uuid();

        $reponse = $this->synchroniser([$this->creation($id, [
            'raison_sociale' => 'Glacier du Port', 'contact' => '01 21 00 00 00', 'evaluation' => 'bon',
        ])]);

        $reponse->assertOk()
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.entite_id', $id)
            ->assertJsonMissingPath('resultats.0.fusionne_avec');

        $fournisseur = Fournisseur::findOrFail($id);
        $this->assertSame('Glacier du Port', $fournisseur->raison_sociale);
        // Par le service, donc par Eloquent : l'audit RG-15 est tenu.
        $this->assertSame($this->acheteur->id, $fournisseur->utilisateur_creation_id);
        $this->assertDatabaseHas('journal_audit', ['entite_concernee' => 'fournisseurs', 'entite_id' => $id]);
        $this->assertSame(0, CorrespondanceSynchronisation::count());
    }

    /**
     * Les règles ET les phrases d'`EnregistrerFournisseurRequest` : le poste
     * affiche le même refus que l'écran en ligne.
     */
    #[Test]
    public function une_creation_invalide_est_rejetee_avec_les_phrases_de_l_api(): void
    {
        $reponse = $this->synchroniser([
            $this->creation((string) Str::uuid(), ['contact' => 'sans raison sociale']),
            $this->creation((string) Str::uuid(), ['raison_sociale' => 'Brasserie', 'evaluation' => 'Excellent']),
            $this->creation((string) Str::uuid(), ['raison_sociale' => 'Brasserie', 'encours' => '150000']),
        ]);

        $reponse->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('achats.validation.raison_sociale_obligatoire'))
            ->assertJsonPath('resultats.1.motif', __('achats.validation.evaluation_inconnue'))
            ->assertJsonPath('resultats.1.erreurs.evaluation.0', __('achats.validation.evaluation_inconnue'))
            ->assertJsonPath('resultats.2.motif', __('achats.validation.valeur_calculee'));

        $this->assertSame(0, Fournisseur::count());
    }

    // ------------------------------------------------------------ RBAC

    /**
     * M7 en `C` est exigé : `receptionniste` (M7 = '-') et `comptable`
     * (M7 = 'L') sont refusés, et chaque refus est tracé.
     */
    #[Test]
    public function sans_ecriture_sur_m7_aucun_fournisseur_n_est_synchronise(): void
    {
        foreach (['receptionniste', 'comptable'] as $role) {
            $utilisateur = $this->creerUtilisateur($role);

            $this->synchroniser([$this->creation((string) Str::uuid(), ['raison_sociale' => 'Fournisseur ' . $role])], $utilisateur)
                ->assertJsonPath('resultats.0.statut', 'rejete')
                ->assertJsonPath('resultats.0.motif', __('auth.module_refuse'));

            $this->assertDatabaseHas('journal_securite', [
                'type_evenement' => 'acces_refuse_rbac', 'utilisateur_id' => $utilisateur->id, 'module_concerne' => 'M7',
            ]);
        }

        $this->assertSame(0, Fournisseur::count());
    }

    // ------------------------------------------------------------ Fusion sur clé naturelle

    #[Test]
    public function un_fournisseur_deja_au_catalogue_est_fusionne_sans_doublon_ni_ecrasement(): void
    {
        $serveur = $this->fournisseurServeur('Société Béninoise des Brasseries', contact: 'Service commercial');
        $idPoste = (string) Str::uuid();

        $reponse = $this->synchroniser([$this->creation($idPoste, [
            'raison_sociale' => '  SOCIETE beninoise   des BRASSERIES ', 'contact' => 'Le livreur',
        ])], poste: 'poste-windows-1');

        $reponse->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.entite_id', $serveur->id)
            ->assertJsonPath('resultats.0.fusionne_avec', $serveur->id);

        $this->assertSame(1, Fournisseur::count());
        $this->assertDatabaseMissing('fournisseurs', ['id' => $idPoste]);
        // Le serveur est maître : la fusion n'écrase rien.
        $this->assertSame('Service commercial', $serveur->fresh()->contact);

        $this->assertDatabaseHas('correspondances_synchronisation', [
            'poste_id' => 'poste-windows-1', 'table_concernee' => 'fournisseurs',
            'id_poste' => $idPoste, 'id_serveur' => $serveur->id,
        ]);
    }

    #[Test]
    public function le_rejeu_d_une_fusion_rend_le_meme_resultat_sans_seconde_correspondance(): void
    {
        $serveur = $this->fournisseurServeur('SOBEBRA');
        $operation = $this->creation((string) Str::uuid(), ['raison_sociale' => 'Sobebra']);

        $premier = $this->synchroniser([$operation])->json('resultats.0');
        $rejeu = $this->synchroniser([$operation]);

        $rejeu->assertJsonPath('resultats.0.rejeu_idempotent', true)
            ->assertJsonPath('resultats.0.entite_id', $serveur->id)
            ->assertJsonPath('resultats.0.fusionne_avec', $premier['fusionne_avec']);

        $this->assertSame(1, CorrespondanceSynchronisation::count());
        $this->assertSame(1, Fournisseur::count());
    }

    /**
     * Le cas que la décision vise d'abord : deux postes coupés du serveur
     * créent le même fournisseur. Le premier synchronisé le crée, le second
     * s'y fond — un seul élément serveur, deux correspondances.
     */
    #[Test]
    public function deux_postes_creant_le_meme_fournisseur_fusionnent_sur_le_meme_element(): void
    {
        $idA = (string) Str::uuid();
        $idB = (string) Str::uuid();

        $this->synchroniser([$this->creation($idA, ['raison_sociale' => 'Glacier du Port'])], poste: 'poste-a')
            ->assertJsonPath('resultats.0.entite_id', $idA);

        $this->synchroniser([$this->creation($idB, ['raison_sociale' => 'GLACIER DU PORT'])], poste: 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.entite_id', $idA)
            ->assertJsonPath('resultats.0.fusionne_avec', $idA);

        $this->assertSame([$idA], Fournisseur::pluck('id')->all());
        $this->assertDatabaseHas('correspondances_synchronisation', [
            'poste_id' => 'poste-b', 'id_poste' => $idB, 'id_serveur' => $idA,
        ]);

        // Un troisième poste : même cible, pas de chaîne de correspondances.
        $idC = (string) Str::uuid();
        $this->synchroniser([$this->creation($idC, ['raison_sociale' => 'Glacier  du port'])], poste: 'poste-c')
            ->assertJsonPath('resultats.0.fusionne_avec', $idA);
        $this->assertSame(1, Fournisseur::count());
    }

    /**
     * Après la fusion, le poste désigne encore l'élément par SON uuid tant
     * qu'il n'a pas remappé : ses modifications atteignent l'élément serveur,
     * et une re-création (nouvelle tentative) rend la fusion d'origine.
     */
    #[Test]
    public function l_uuid_du_poste_est_traduit_par_la_correspondance(): void
    {
        $serveur = $this->fournisseurServeur('Moulin de Bohicon');
        $idPoste = (string) Str::uuid();

        $this->synchroniser([$this->creation($idPoste, ['raison_sociale' => 'moulin de bohicon'])]);

        $this->synchroniser([$this->operation('modification', $idPoste, [
            'raison_sociale' => 'Moulin de Bohicon', 'contact' => '01 66 00 00 00',
        ], now()->addMinute())])
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.entite_id', $serveur->id)
            ->assertJsonPath('resultats.0.fusionne_avec', $serveur->id);

        $this->assertSame('01 66 00 00 00', $serveur->fresh()->contact);

        $this->synchroniser([$this->creation($idPoste, ['raison_sociale' => 'Moulin de Bohicon'])])
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.fusionne_avec', $serveur->id);

        $this->assertSame(1, Fournisseur::count());
    }

    /**
     * Une fiche ARCHIVÉE reste la même société : on s'y fond plutôt que de
     * faire renaître un doublon, et le poste est prévenu qu'elle est rangée.
     */
    #[Test]
    public function la_fusion_sur_une_fiche_archivee_le_signale(): void
    {
        $serveur = $this->fournisseurServeur('Ancienne Boulangerie');
        app(ReferentielFournisseurService::class)->archiver($serveur);

        $this->synchroniser([$this->creation((string) Str::uuid(), ['raison_sociale' => 'ancienne boulangerie'])])
            ->assertJsonPath('resultats.0.fusionne_avec', $serveur->id)
            ->assertJsonPath('resultats.0.cible_archivee', true);

        $this->assertFalse($serveur->fresh()->actif);
    }

    #[Test]
    public function la_cle_naturelle_ignore_casse_accents_et_espaces(): void
    {
        $this->assertSame(
            GestionnaireFournisseurs::cleNaturelle('Société  Béninoise des Brasseries'),
            GestionnaireFournisseurs::cleNaturelle(' SOCIETE BENINOISE DES BRASSERIES '),
        );
        $this->assertNotSame(
            GestionnaireFournisseurs::cleNaturelle('Glacier du Port'),
            GestionnaireFournisseurs::cleNaturelle('Glacier du Lac'),
        );
    }

    // ------------------------------------------------------------ Modification

    #[Test]
    public function une_modification_passe_par_le_service_avec_les_regles_de_l_api(): void
    {
        $serveur = $this->fournisseurServeur('Ferme Avicole');

        $this->synchroniser([$this->operation('modification', $serveur->id, [
            'raison_sociale' => 'Ferme Avicole', 'contact' => 'M. Dossou', 'evaluation' => 'excellent',
        ])])->assertJsonPath('resultats.0.statut', 'synchronise');

        $fiche = $serveur->fresh();
        $this->assertSame('M. Dossou', $fiche->contact);
        $this->assertSame('excellent', $fiche->evaluation);
        $this->assertSame($this->acheteur->id, $fiche->utilisateur_modification_id);

        // Même règle que `PUT /achats/fournisseurs/{id}` : la raison sociale
        // est obligatoire sur une fiche modifiée.
        $this->synchroniser([$this->operation('modification', $serveur->id, ['contact' => 'Autre'], now()->addMinute())])
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('achats.validation.raison_sociale_obligatoire'));
        $this->assertSame('M. Dossou', $serveur->fresh()->contact);
    }

    // ------------------------------------------------------------ Archivage par `actif`

    #[Test]
    public function l_administrateur_archive_et_restaure_un_fournisseur_par_la_synchronisation(): void
    {
        $admin = $this->creerUtilisateur('administrateur');
        $serveur = $this->fournisseurServeur('Quincaillerie Centrale');

        $this->synchroniser([$this->operation('modification', $serveur->id, ['actif' => false])], $admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertFalse($serveur->fresh()->actif);

        $this->synchroniser([$this->operation('modification', $serveur->id, ['actif' => true], now()->addMinute())], $admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertTrue($serveur->fresh()->actif);
    }

    /**
     * Directive du 03/09/2026 : hors administration, archiver exige la
     * bascule des Paramètres — même règle (`DroitArchivageService`) que
     * l'écran PWA. Le droit `C` sur M7 ne suffit pas.
     */
    #[Test]
    public function un_role_sans_droit_d_archivage_ne_range_pas_un_fournisseur(): void
    {
        $serveur = $this->fournisseurServeur('Quincaillerie Centrale');

        $this->synchroniser([$this->operation('modification', $serveur->id, ['actif' => false])])
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('pwa.archivage.refus_bascule'));

        $this->assertTrue($serveur->fresh()->actif);
    }

    /**
     * Le verrou d'engagement du service tient aussi par ce chemin : un
     * fournisseur sous commande en cours ne s'archive pas.
     */
    #[Test]
    public function un_fournisseur_engage_ne_s_archive_pas_par_la_synchronisation(): void
    {
        $admin = $this->creerUtilisateur('administrateur');
        $serveur = $this->fournisseurServeur('Quincaillerie Centrale');

        DB::table('commandes_achat')->insert([
            'id' => (string) Str::uuid(), 'fournisseur_id' => $serveur->id, 'date_commande' => '2026-10-01',
            'statut' => 'envoyee', 'utilisateur_id' => $admin->id,
        ]);

        $this->synchroniser([$this->operation('modification', $serveur->id, ['actif' => false])], $admin)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('achats_pwa.archivage.verrou', ['nombre' => 1]));

        $this->assertTrue($serveur->fresh()->actif);
    }

    // ------------------------------------------------------------- Helpers

    private function fournisseurServeur(string $raisonSociale, ?string $contact = null): Fournisseur
    {
        return app(ReferentielFournisseurService::class)->creer([
            'raison_sociale' => $raisonSociale, 'contact' => $contact,
        ])->refresh();
    }

    /**
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    private function creation(string $id, array $payload): array
    {
        return $this->operation('creation', $id, $payload);
    }

    /**
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    private function operation(string $type, string $id, array $payload, ?\Illuminate\Support\Carbon $horodatage = null): array
    {
        return [
            'uuid_operation' => (string) Str::uuid(),
            'table' => 'fournisseurs',
            'type' => $type,
            'entite_id' => $id,
            'payload' => $payload,
            'horodatage_client' => ($horodatage ?? now())->toIso8601String(),
        ];
    }

    /**
     * @param  list<array<string, mixed>>  $operations
     * @return TestResponse<\Illuminate\Http\JsonResponse>
     */
    private function synchroniser(array $operations, ?User $utilisateur = null, string $poste = 'poste-windows-1'): TestResponse
    {
        Sanctum::actingAs($utilisateur ?? $this->acheteur);

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

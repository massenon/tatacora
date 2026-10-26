<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Comptabilite\Services\CorrespondanceComptesService;
use App\Models\User;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Parametres\Services\EnregistrerParametreService;
use App\Shared\Rbac\Models\Role;
use App\Shared\Rbac\Services\RolePermissionService;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Le paramétrage et les rôles en synchronisation — lot 10e (audit de
 * couverture du 18/10/2026). Un enregistrement de l'écran Paramètres est UNE
 * opération (cohérence sur l'état résultant), arbitrée clé par clé ; un rôle
 * fusionne par son libellé et sa matrice passe par `definirNiveau`. Les deux
 * descendent vers tout compte qui synchronise ; aucun compte ne monte.
 */
final class ParametresRolesSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-18 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->admin = $this->creerUtilisateur('administrateur');
    }

    /**
     * @param  array<string, scalar|null>  $valeurs
     * @return array<string, mixed>
     */
    private function enregistrement(array $valeurs, ?string $saisiLe = null): array
    {
        $op = $this->creation('parametres_systeme', $this->uuid(), ['valeurs' => $valeurs]);

        if ($saisiLe !== null) {
            $op['horodatage_client'] = $saisiLe;
        }

        return $op;
    }

    /** @return list<array<string, mixed>> */
    private function flux(User $compte): array
    {
        $this->travel(10)->seconds();
        Sanctum::actingAs($compte);
        $elements = [];
        $curseur = null;

        do {
            $r = $this->getJson('/api/v1/referentiels?' . http_build_query(array_filter(['poste_id' => 'poste-b', 'depuis' => $curseur, 'limite' => 500])))->assertOk();
            $elements = [...$elements, ...$r->json('data.elements')];
            $curseur = $r->json('meta.curseur');
        } while (! $r->json('meta.complet'));

        return $elements;
    }

    #[Test]
    public function un_enregistrement_du_poste_passe_en_lot_et_le_dernier_ecrit_gagne_cle_par_cle(): void
    {
        // TVA activée ET taux saisi dans le même envoi : clé par clé,
        // l'activation arriverait seule et serait refusée (PA-62).
        $this->pousser([$this->enregistrement(['tva_active' => 'true', 'taux_tva' => '18', 'entreprise_ifu' => '0202011344660'])], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('true', ParametreSysteme::where('cle', 'tva_active')->value('valeur'));
        $this->assertSame('18', ParametreSysteme::where('cle', 'taux_tva')->value('valeur'));

        // Une saisie du poste ANTÉRIEURE à la dernière modification du
        // serveur : la valeur du serveur reste, les autres clés passent.
        $this->travel(5)->minutes();
        app(EnregistrerParametreService::class)->enregistrer(['entreprise_ifu' => '1111111111111']);
        $this->pousser([$this->enregistrement(
            ['entreprise_ifu' => '2222222222222', 'tolerance_reception_pct' => '5'],
            now()->subMinutes(2)->toIso8601String(),
        )], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.cles_conservees', ['entreprise_ifu']);
        $this->assertSame('1111111111111', ParametreSysteme::where('cle', 'entreprise_ifu')->value('valeur'));
        $this->assertSame('5', ParametreSysteme::where('cle', 'tolerance_reception_pct')->value('valeur'));

        // Une clé hors registre refuse le lot entier.
        $this->pousser([$this->enregistrement(['cle_inventee' => 'x', 'tolerance_reception_pct' => '7'])], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'rejete');
        $this->assertSame('5', ParametreSysteme::where('cle', 'tolerance_reception_pct')->value('valeur'));
    }

    /**
     * La correspondance des comptes (26/10/2026) : un changement fait SUR UN
     * POSTE monte comme un paramètre, passe par la MÊME validation que l'écran
     * du web (`EnregistrerParametreService`) — format, plan, classe du rôle —,
     * est lu par les pièces du serveur, et DESCEND vers les autres postes.
     */
    #[Test]
    public function la_correspondance_des_comptes_d_un_poste_passe_par_la_validation_de_l_ecran_et_redescend(): void
    {
        $this->seed(ComptabiliteReferentielSeeder::class);
        $comptes = app(CorrespondanceComptesService::class);

        $this->pousser([$this->enregistrement(['compte_produit_locations' => '7078', 'compte_caisse' => '5712'])], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.cles_modifiees', ['compte_produit_locations', 'compte_caisse']);
        $this->assertSame('7078', $comptes->compte('PRODUIT_LOCATIONS'));
        $this->assertSame('5712', $comptes->compte('CAISSE'));

        // Les trois refus du serveur valent pour le poste : le lot ENTIER est
        // rejeté, la clé valide du même lot n'est pas écrite.
        foreach (['7999' => 'compte_absent', '6011' => 'compte_incoherent', '70' => 'division'] as $numero => $motif) {
            $this->pousser([$this->enregistrement(['compte_produit_circuits' => $numero, 'compte_banque' => '5212'])], $this->admin)
                ->assertJsonPath('resultats.0.statut', 'rejete');
            $this->assertSame('7061', $comptes->compte('PRODUIT_CIRCUITS'), $motif);
            $this->assertSame('5211', $comptes->compte('BANQUE'), $motif);
        }

        // Vider revient au défaut.
        $this->pousser([$this->enregistrement(['compte_caisse' => null])], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('5711', $comptes->compte('CAISSE'));

        // La valeur DESCEND : un autre poste la reçoit comme tout paramètre.
        $flux = collect($this->flux($this->creerUtilisateur('gerant')))
            ->where('table', 'parametres_systeme')
            ->mapWithKeys(static fn (array $e): array => [$e['donnees']['cle'] => $e['donnees']['valeur']]);
        $this->assertSame('7078', $flux['compte_produit_locations']);
    }

    #[Test]
    public function seul_un_compte_au_droit_param_enregistre(): void
    {
        $this->pousser([$this->enregistrement(['tolerance_reception_pct' => '9'])], $this->creerUtilisateur('barman'))
            ->assertJsonPath('resultats.0.statut', 'rejete');
        $this->assertNull(ParametreSysteme::where('cle', 'tolerance_reception_pct')->value('valeur'));
    }

    #[Test]
    public function un_role_du_poste_nait_au_serveur_un_role_du_socle_fusionne_par_son_libelle(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->creation('roles', $id, ['libelle' => 'Économe', 'description' => 'Stocks', 'droits' => ['M6' => 'C', 'M7' => 'L']])], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $role = Role::findOrFail($id);
        $this->assertSame(['C', 'L', '-'], [$role->niveauSurModule('M6'), $role->niveauSurModule('M7'), $role->niveauSurModule('M1')]);

        // Le socle du poste porte ses propres UUID : retrouvé par le libellé.
        $local = $this->uuid();
        $barman = Role::where('libelle', 'barman')->firstOrFail();
        $this->pousser([$this->operation('roles', 'modification', $local, ['libelle' => 'barman', 'droits' => ['M6' => 'C']])], $this->admin)
            ->assertJsonPath('resultats.0.fusionne_avec', $barman->id);
        $this->assertSame('C', $barman->refresh()->niveauSurModule('M6'));

        // La suivante désigne le même rôle par l'UUID du poste.
        $this->travel(1)->minutes();
        $this->pousser([$this->operation('roles', 'modification', $local, ['libelle' => 'barman', 'droits' => ['M6' => 'L']])], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('L', $barman->refresh()->niveauSurModule('M6'));

        // Le verrou de l'administrateur tient, un module inconnu est refusé.
        $this->pousser([$this->operation('roles', 'modification', $this->uuid(), ['libelle' => 'administrateur', 'droits' => ['ROLES' => 'L']])], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'rejete');
        $this->pousser([$this->creation('roles', $this->uuid(), ['libelle' => 'Autre', 'droits' => ['M99' => 'C']])], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'rejete');
        $this->assertSame('C', Role::where('libelle', 'administrateur')->firstOrFail()->niveauSurModule('ROLES'));
    }

    #[Test]
    public function parametres_et_roles_descendent_vers_tout_compte_jamais_un_compte(): void
    {
        app(EnregistrerParametreService::class)->enregistrer(['tolerance_reception_pct' => '3']);
        $barman = $this->creerUtilisateur('barman');

        $elements = collect($this->flux($barman))->groupBy('table');

        $this->assertSame('3', $elements['parametres_systeme']->firstWhere('donnees.cle', 'tolerance_reception_pct')['donnees']['valeur']);
        $role = $elements['roles']->firstWhere('donnees.libelle', 'administrateur');
        $this->assertSame('C', $role['donnees']['droits']['ROLES']);
        $this->assertArrayHasKey('ANNULATIONS', $role['donnees']['droits']);
        $this->assertArrayNotHasKey('utilisateurs', $elements->all());

        // Un changement de matrice (pivot) date le rôle : il redescend.
        $this->travel(1)->minutes();
        app(RolePermissionService::class)->definirNiveau(Role::where('libelle', 'barman')->firstOrFail(), 'M9', 'L');
        $this->assertTrue(Role::where('libelle', 'barman')->firstOrFail()->updated_at->greaterThan(now()->subSeconds(5)));
    }
}

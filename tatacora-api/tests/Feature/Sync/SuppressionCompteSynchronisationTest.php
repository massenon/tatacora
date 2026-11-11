<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Models\User;
use App\Pwa\Livewire\Transverse\ComptesUtilisateurs;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Auth\Services\SuppressionCompteService;
use App\Shared\Sync\Services\EpoqueSynchronisation;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * SUPPRIMER UN COMPTE (décision du PO du 03/11/2026) : au web (Livewire) et par la
 * synchronisation (poste -> serveur -> autres postes), SANS jamais un mot de passe.
 *
 * Les tests de MUTATION de la règle d'autorité sont ici : un non super_admin ne
 * supprime pas, un administrateur n'est pas supprimable, on ne se supprime pas
 * soi-même. Chacun a été éprouvé en retirant la garde correspondante.
 */
final class SuppressionCompteSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $superAdmin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-11-03 08:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->superAdmin = $this->creerUtilisateur('super_admin');
    }

    /** @return array<string, mixed> */
    private function suppression(string $login, ?string $par = 'n.nabogou'): array
    {
        return $this->operation('utilisateurs', 'suppression', $this->uuid(), ['login' => $login, 'supprime_par' => $par]);
    }

    // ---------------------------------------------------------------- web

    #[Test]
    public function un_super_admin_supprime_un_compte_non_administrateur_au_web(): void
    {
        $cible = $this->creerUtilisateur('barman');
        $jeton = $cible->createToken('poste-b');

        Livewire::actingAs($this->superAdmin)->test(ComptesUtilisateurs::class)
            ->assertSee(__('pwa.comptes.supprimer'))
            ->call('ouvrirSuppression', $cible->id)
            ->assertSee(__('pwa.comptes.supprimer_titre', ['login' => $cible->login]))
            ->assertSee(__('pwa.comptes.supprimer_texte'))
            ->call('supprimerCompte')
            ->assertDontSee('data-compte="' . $cible->login . '"', false);

        // Suppression LOGIQUE : la ligne reste, l'identifiant n'est pas réutilisable.
        $this->assertNull(User::find($cible->id));
        $this->assertNotNull(DB::table('utilisateurs')->where('id', $cible->id)->value('supprime_le'));
        $this->assertSame(0, DB::table('personal_access_tokens')->where('id', $jeton->accessToken->id)->count());
        $this->assertNotNull(User::withTrashed()->find($cible->id)?->supprime_le);

        $entree = JournalAudit::where('action', 'compte_supprime')->firstOrFail();
        $this->assertSame($this->superAdmin->id, $entree->utilisateur_id);
        $this->assertSame($cible->login, $entree->valeur_apres['login']);
        $this->assertStringNotContainsString('mot_de_passe', json_encode($entree->valeur_apres, JSON_THROW_ON_ERROR));
    }

    #[Test]
    public function seul_un_super_admin_voit_le_bouton_et_peut_supprimer(): void
    {
        $cible = $this->creerUtilisateur('barman');

        foreach (['administrateur', 'gerant'] as $role) {
            $auteur = $this->creerUtilisateur($role);
            Livewire::actingAs($auteur)->test(ComptesUtilisateurs::class)
                ->assertDontSee('ouvrirSuppression', false);
        }

        // MUTATION : un administrateur appelle quand même l'action -> refus lisible.
        $admin = $this->creerUtilisateur('administrateur');
        Livewire::actingAs($admin)->test(ComptesUtilisateurs::class)
            ->call('ouvrirSuppression', $cible->id)
            ->call('supprimerCompte')
            ->assertSet('refus', __('pwa.comptes.refus_suppression_droit'));
        $this->assertNull(User::withTrashed()->find($cible->id)?->supprime_le);
    }

    #[Test]
    public function un_administrateur_ou_un_super_admin_n_est_pas_supprimable(): void
    {
        $admin = $this->creerUtilisateur('administrateur');
        $autreSuper = $this->creerUtilisateur('super_admin');

        $this->assertFalse($admin->estSupprimable());
        $this->assertFalse($autreSuper->estSupprimable());
        $this->assertTrue($this->creerUtilisateur('gerant')->estSupprimable());

        foreach ([$admin, $autreSuper] as $cible) {
            Livewire::actingAs($this->superAdmin)->test(ComptesUtilisateurs::class)
                ->call('ouvrirSuppression', $cible->id)
                ->call('supprimerCompte')
                ->assertSet('refus', __('pwa.comptes.refus_suppression_administrateur'));
            $this->assertNull(User::withTrashed()->find($cible->id)?->supprime_le);
        }
    }

    #[Test]
    public function on_ne_se_supprime_pas_soi_meme(): void
    {
        Livewire::actingAs($this->superAdmin)->test(ComptesUtilisateurs::class)
            ->call('ouvrirSuppression', $this->superAdmin->id)
            ->assertSet('refus', __('pwa.comptes.refus_suppression_soi_meme'))
            ->assertSet('compteASupprimer', null);

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage(__('pwa.comptes.refus_suppression_soi_meme'));
        app(SuppressionCompteService::class)->supprimer($this->superAdmin, $this->superAdmin->id, null);
    }

    #[Test]
    public function un_compte_supprime_ne_se_connecte_plus_et_garde_son_nom_sur_ses_saisies(): void
    {
        $cible = $this->creerUtilisateur('barman');
        $connexion = ['identifiant' => $cible->login, 'mot_de_passe' => 'mot-de-passe-de-test', 'poste' => 'poste-x'];
        // Preuve que la connexion marche AVANT (sinon le refus ci-dessous serait vide).
        $this->postJson('/api/v1/login', $connexion)->assertOk();

        app(SuppressionCompteService::class)->supprimer($this->superAdmin, $cible->id, null);

        $this->postJson('/api/v1/login', $connexion)->assertStatus(401);
        $this->assertSame($cible->login . ' (compte supprimé)', User::withTrashed()->findOrFail($cible->id)->libelleAuteur());

        // Le journal d'audit relit l'auteur supprimé, par son nom.
        JournalAudit::create(['id' => $this->uuid(), 'utilisateur_id' => $cible->id, 'action' => 'creation', 'entite_concernee' => 'clients', 'entite_id' => $this->uuid(), 'valeur_apres' => []]);
        $this->assertSame($cible->id, JournalAudit::with('utilisateur')->where('utilisateur_id', $cible->id)->firstOrFail()->utilisateur?->id);

        // L'identifiant n'est pas réutilisable.
        $this->expectException(\Illuminate\Database\QueryException::class);
        User::create(['login' => $cible->login, 'mot_de_passe_hash' => 'x', 'role_id' => $this->superAdmin->role_id, 'statut' => 'actif']);
    }

    // ---------------------------------------------------- poste -> serveur

    #[Test]
    public function un_poste_dont_le_jeton_est_super_admin_supprime_le_compte_par_son_login(): void
    {
        $cible = $this->creerUtilisateur('gerant');
        $operation = $this->suppression($cible->login);

        $this->pousser([$operation], $this->superAdmin, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertNull(User::find($cible->id));

        $entree = JournalAudit::where('action', 'compte_supprime')->firstOrFail();
        $this->assertSame('poste-a', $entree->valeur_apres['poste']);
        $this->assertSame('n.nabogou', $entree->valeur_apres['par_login_local']);

        // Rejeu : un accusé, rien d'autre. Et une autre tentative sur le compte disparu : no-op.
        $this->pousser([$operation], $this->superAdmin, 'poste-a')->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->pousser([$this->suppression($cible->login)], $this->superAdmin, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.deja_supprime', true);
        $this->assertSame(1, JournalAudit::where('action', 'compte_supprime')->count());
    }

    #[Test]
    public function un_compte_inconnu_du_serveur_est_accepte_sans_erreur_et_journalise(): void
    {
        $this->pousser([$this->suppression('cree-sur-le-poste')], $this->superAdmin, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.deja_supprime', true);

        $this->assertSame(1, JournalAudit::where('action', 'compte_supprime_inconnu')->count());
        $this->assertSame(0, JournalAudit::where('action', 'compte_supprime')->count());
    }

    #[Test]
    public function l_autorite_est_celle_du_jeton_d_appairage_un_non_super_admin_est_refuse(): void
    {
        $cible = $this->creerUtilisateur('gerant');

        // MUTATION de la règle : un administrateur, un gérant, un barman — refus définitif.
        foreach (['administrateur', 'gerant', 'barman'] as $role) {
            $this->pousser([$this->suppression($cible->login)], $this->creerUtilisateur($role), 'poste-a')
                ->assertJsonPath('resultats.0.statut', 'rejete')
                ->assertJsonPath('resultats.0.code_motif', 'droit_manquant')
                ->assertJsonPath('resultats.0.motif', __('sync.comptes.suppression_reservee'));
        }

        $this->assertNotNull(User::find($cible->id));
        $this->assertSame(0, JournalAudit::where('action', 'compte_supprime')->count());
    }

    #[Test]
    public function un_administrateur_ne_se_supprime_pas_par_la_synchronisation_et_le_jeton_ne_se_supprime_pas_lui_meme(): void
    {
        $admin = $this->creerUtilisateur('administrateur');
        $this->pousser([$this->suppression($admin->login)], $this->superAdmin, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('pwa.comptes.refus_suppression_administrateur'));
        $this->assertNotNull(User::find($admin->id));

        $autreSuper = $this->creerUtilisateur('super_admin');
        $this->pousser([$this->suppression($autreSuper->login)], $this->superAdmin, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'rejete');
        $this->assertNotNull(User::find($autreSuper->id));
    }

    #[Test]
    public function une_creation_ou_une_modification_de_compte_ne_passe_jamais(): void
    {
        $creation = $this->operation('utilisateurs', 'creation', $this->uuid(), ['login' => 'x', 'mot_de_passe_hash' => 'y']);
        $modification = $this->operation('utilisateurs', 'modification', $this->uuid(), ['role' => 'super_admin']);

        $this->pousser([$creation, $modification], $this->superAdmin, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.1.statut', 'rejete')
            ->assertJsonPath('resultats.1.code_motif', 'modification_non_synchronisable');
        $this->assertSame(0, User::where('login', 'x')->count());
    }

    // ---------------------------------------------------- serveur -> postes

    #[Test]
    public function la_suppression_descend_vers_les_autres_postes_par_le_login_sans_aucun_secret(): void
    {
        $cible = $this->creerUtilisateur('gerant');
        $vivant = $this->creerUtilisateur('barman');

        $this->pousser([$this->suppression($cible->login)], $this->superAdmin, 'poste-a');
        $this->travel(10)->seconds();

        Sanctum::actingAs($this->creerUtilisateur('receptionniste'));
        $reponse = $this->getJson('/api/v1/referentiels?poste_id=poste-b&limite=500')->assertOk();
        $elements = collect($reponse->json('data.elements'))->where('table', 'utilisateurs')->values();

        $this->assertCount(1, $elements);
        $this->assertSame($cible->id, $elements[0]['id']);
        $this->assertFalse($elements[0]['actif']);
        $this->assertSame($cible->login, $elements[0]['donnees']['login']);
        $this->assertNotNull($elements[0]['donnees']['supprime_le']);
        // Rien d'autre que `login` et `supprime_le` ne descend — jamais un hash ni un rôle.
        $this->assertSame(['login', 'supprime_le'], array_keys($elements[0]['donnees']));
        $this->assertStringNotContainsString($vivant->login, (string) $reponse->getContent());
        $this->assertStringNotContainsString('mot_de_passe', (string) $reponse->getContent());
        $this->assertStringNotContainsString('$2y$', (string) $reponse->getContent());
    }

    // ------------------------------------------------------------ l'époque

    #[Test]
    public function l_epoque_change_quand_une_operation_est_acceptee_et_pas_sur_un_rejeu_ni_un_refus(): void
    {
        $epoque = app(EpoqueSynchronisation::class);
        Sanctum::actingAs($this->superAdmin);
        $avant = $this->getJson('/api/v1/sync/demande?poste_id=poste-windows-1')->assertOk()->json('data.epoque');
        $this->assertSame($avant, $epoque->courante());

        // Un refus ne change rien.
        $this->pousser([$this->suppression('inconnu-du-tout', null)], $this->creerUtilisateur('barman'), 'poste-windows-1');
        $this->assertSame($avant, $epoque->courante());

        $cible = $this->creerUtilisateur('gerant');
        $operation = $this->suppression($cible->login);
        $this->pousser([$operation], $this->superAdmin);
        $apres = $epoque->courante();
        $this->assertNotSame($avant, $apres);

        // Le rejeu idempotent ne la fait pas varier.
        $this->pousser([$operation], $this->superAdmin);
        $this->assertSame($apres, $epoque->courante());

        // La réponse du battement léger la porte.
        Sanctum::actingAs($this->superAdmin);
        $this->getJson('/api/v1/sync/demande?poste_id=poste-windows-1')->assertOk()->assertJsonPath('data.epoque', $apres);
    }
}

<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Models\User;
use App\Pwa\Livewire\Transverse\MonProfil;
use App\Pwa\Livewire\Transverse\RolesPermissions;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Rbac\Models\Permission;
use App\Shared\Rbac\Models\Role;
use App\Shared\Rbac\Services\RolePermissionService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * « Mon profil » : le nom complet, le téléphone et l'intitulé de poste se
 * modifient SOUS DROIT (modules RBAC `PROFIL_*`, décision du PO du 03/11/2026).
 *
 * Ce que ces cas prouvent :
 *  - les valeurs par défaut (nom, téléphone : tous les rôles ; intitulé : les
 *    deux rôles d'administration) et le complément additif qui ne réécrit
 *    JAMAIS un réglage fait à l'écran ;
 *  - le droit est appliqué par le SERVEUR : une action forgée sans le droit est
 *    refusée (403) et n'écrit RIEN ;
 *  - normalisation, bornes, journal d'audit « Profil modifié » (ancien → nouveau).
 */
final class MonProfilDroitsTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    private function compte(string $role): User
    {
        return User::create([
            'login' => $role.'.profil',
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    #[Test]
    public function les_valeurs_par_defaut_suivent_la_decision_du_po(): void
    {
        foreach (Role::query()->pluck('libelle') as $role) {
            $compte = $this->compte($role);

            $this->assertTrue($compte->peutModifierSonProfil('nom_complet'), "$role : nom");
            $this->assertTrue($compte->peutModifierSonProfil('telephone'), "$role : téléphone");
            $this->assertSame(
                in_array($role, User::ROLES_ADMINISTRATION, true),
                $compte->peutModifierSonProfil('intitule_poste'),
                "$role : intitulé de poste",
            );
        }
    }

    #[Test]
    public function le_complement_est_additif_et_ne_reecrit_jamais_un_reglage_d_ecran(): void
    {
        // L'administrateur a retiré le téléphone au barman : le complément n'y touche pas.
        $barman = Role::where('libelle', 'barman')->firstOrFail();
        app(RolePermissionService::class)->definirNiveau($barman, 'PROFIL_TELEPHONE', '-');
        // Un rôle ajouté à l'écran, avant l'apparition des droits de profil.
        $personnalise = Role::create(['libelle' => 'caissier_special']);
        // Base d'avant le lot : les modules de profil sont inconnus de `permissions`.
        $ancien = Permission::query()->whereIn('module', ['PROFIL_NOM', 'PROFIL_INTITULE'])->pluck('id')->all();
        \DB::table('permission_role')->whereIn('permission_id', $ancien)->delete();
        Permission::query()->whereIn('id', $ancien)->delete();

        (new RolePermissionSeeder())->completerModulesNouveaux();
        (new RolePermissionSeeder())->completerModulesNouveaux();

        $this->assertSame('-', $barman->refresh()->niveauSurModule('PROFIL_TELEPHONE'), 'réglage d\'écran conservé');
        $this->assertSame('C', $barman->niveauSurModule('PROFIL_NOM'));
        $this->assertSame('C', $personnalise->refresh()->niveauSurModule('PROFIL_NOM'), 'rôle hors socle : nom pour tous');
        $this->assertSame('-', $personnalise->niveauSurModule('PROFIL_INTITULE'));
        $this->assertSame('C', Role::where('libelle', 'administrateur')->firstOrFail()->niveauSurModule('PROFIL_INTITULE'));
    }

    #[Test]
    public function un_role_cree_a_l_ecran_recoit_nom_et_telephone_mais_pas_l_intitule(): void
    {
        $role = app(RolePermissionService::class)->creerRole('Nouveau rôle de test', null);

        $this->assertSame('C', $role->niveauSurModule('PROFIL_NOM'));
        $this->assertSame('C', $role->niveauSurModule('PROFIL_TELEPHONE'));
        $this->assertSame('-', $role->niveauSurModule('PROFIL_INTITULE'));
        $this->assertSame('-', $role->niveauSurModule('M1'), 'les modules métier restent fermés');
    }

    #[Test]
    public function un_administrateur_renseigne_ses_trois_champs_normalises_et_l_audit_garde_ancien_et_nouveau(): void
    {
        $admin = $this->compte('administrateur');
        $this->actingAs($admin);

        Livewire::test(MonProfil::class)
            ->set('nomSaisi', "  Awa   Kossou \t")
            ->set('telephoneSaisi', ' +229  97 00-11 22 ')
            ->set('intituleSaisi', '  Directrice   des opérations ')
            ->call('enregistrerInformations')
            ->assertHasNoErrors()
            ->assertSee(__('pwa.profil.infos_enregistrees'));

        $admin->refresh();
        $this->assertSame('Awa Kossou', $admin->nom_complet);
        $this->assertSame('+229 97 00-11 22', $admin->telephone);
        $this->assertSame('Directrice des opérations', $admin->intitule_poste);

        $trace = JournalAudit::query()->where('action', 'profil_modifie')->sole();
        $this->assertSame($admin->id, $trace->utilisateur_id);
        $this->assertSame('Awa Kossou', $trace->valeur_apres['nom_complet']);
        $this->assertNull($trace->valeur_avant['telephone']);
        $this->assertStringNotContainsString('mot_de_passe', json_encode($trace->valeur_apres));

        // Vider est permis : la valeur est effacée.
        Livewire::test(MonProfil::class)->set('telephoneSaisi', '   ')->call('enregistrerInformations')->assertHasNoErrors();
        $this->assertNull($admin->refresh()->telephone);
        $efface = JournalAudit::query()->where('action', 'profil_modifie')->get()
            ->first(static fn (JournalAudit $t): bool => array_key_exists('telephone', $t->valeur_apres) && $t->valeur_apres['telephone'] === null);
        $this->assertNotNull($efface);
        $this->assertSame('+229 97 00-11 22', $efface->valeur_avant['telephone']);
    }

    #[Test]
    public function une_action_forgee_sans_le_droit_est_refusee_et_n_ecrit_rien(): void
    {
        $barman = $this->compte('barman');
        $this->actingAs($barman);
        $this->assertFalse($barman->peutModifierSonProfil('intitule_poste'));

        // Le champ est en lecture seule à l'écran ; la requête est forgée.
        Livewire::test(MonProfil::class)
            ->set('nomSaisi', 'Nouveau nom permis')
            ->set('intituleSaisi', 'Directeur général')
            ->call('enregistrerInformations')
            ->assertForbidden();

        $barman->refresh();
        $this->assertNull($barman->intitule_poste);
        $this->assertNull($barman->nom_complet, 'rien n\'est écrit, pas même le champ permis');
        $this->assertSame(0, JournalAudit::query()->where('action', 'profil_modifie')->count());

        // Retirer le droit au nom le refuse aussi : le droit est lu, pas supposé.
        app(RolePermissionService::class)->definirNiveau($barman->role, 'PROFIL_NOM', '-');
        Livewire::test(MonProfil::class)->set('nomSaisi', 'Forgé')->call('enregistrerInformations')->assertForbidden();
        $this->assertNull($barman->refresh()->nom_complet);
    }

    #[Test]
    public function la_vue_rend_un_champ_modifiable_ou_la_phrase_vraie_selon_le_droit(): void
    {
        $this->actingAs($this->compte('barman'))
            ->get('/pwa/mon-profil')
            ->assertOk()
            ->assertSee('wire:model="nomSaisi"', false)
            ->assertSee('wire:model="telephoneSaisi"', false)
            ->assertDontSee('wire:model="intituleSaisi"', false)
            ->assertSee(__('pwa.profil.intitule_poste'))
            ->assertSee(__('pwa.profil.champ_non_modifiable_avant'))
            ->assertDontSee('contournerait la matrice');

        $this->actingAs($this->compte('administrateur'))
            ->get('/pwa/mon-profil')
            ->assertSee('wire:model="intituleSaisi"', false)
            ->assertDontSee(__('pwa.profil.champ_non_modifiable_avant'));
    }

    #[Test]
    #[\PHPUnit\Framework\Attributes\DataProvider('saisiesInvalides')]
    public function les_bornes_et_le_format_sont_refuses(string $propriete, string $valeur): void
    {
        $this->actingAs($this->compte('administrateur'));

        Livewire::test(MonProfil::class)
            ->set($propriete, $valeur)
            ->call('enregistrerInformations')
            ->assertHasErrors([$propriete]);
    }

    /** @return array<string, array{string, string}> */
    public static function saisiesInvalides(): array
    {
        return [
            'nom de 121 caractères' => ['nomSaisi', str_repeat('a', 121)],
            'nom avec caractère de contrôle' => ['nomSaisi', "Awa\x07Kossou"],
            'téléphone avec lettres' => ['telephoneSaisi', '97 00 AB 11'],
            'téléphone de 31 caractères' => ['telephoneSaisi', str_repeat('1', 31)],
            'intitulé de 121 caractères' => ['intituleSaisi', str_repeat('b', 121)],
        ];
    }

    #[Test]
    public function la_matrice_affiche_la_section_profil_et_l_ecran_l_enregistre(): void
    {
        $admin = $this->compte('administrateur');
        $this->actingAs($admin);

        $this->get('/pwa/roles-permissions')
            ->assertOk()
            ->assertSee('id="section-profil-matrice"', false)
            ->assertSee('Modifier son nom complet')
            ->assertSee('Modifier son téléphone')
            ->assertSee('Modifier son intitulé de poste');

        $barman = Role::where('libelle', 'barman')->firstOrFail();

        Livewire::test(RolesPermissions::class)
            ->call('ouvrirFormulaireDroits', $barman->id)
            ->assertSet('niveauxSaisis.PROFIL_INTITULE', '-')
            ->set('niveauxSaisis.PROFIL_INTITULE', 'C')
            ->call('enregistrerDroits')
            ->assertHasNoErrors();

        $this->assertTrue($this->compte('barman')->peutModifierSonProfil('intitule_poste'));

        // `L` n'a pas de sens pour un droit binaire.
        Livewire::test(RolesPermissions::class)
            ->call('ouvrirFormulaireDroits', $barman->id)
            ->set('niveauxSaisis.PROFIL_NOM', 'L')
            ->call('enregistrerDroits')
            ->assertHasErrors(['niveauxSaisis.PROFIL_NOM']);
    }

    #[Test]
    public function la_reponse_de_connexion_porte_les_trois_droits(): void
    {
        $compte = $this->compte('administrateur');
        $compte->forceFill(['mot_de_passe_hash' => Hash::make('Secret-123456')])->save();

        $reponse = $this->postJson('/api/v1/login', [
            'identifiant' => $compte->login,
            'mot_de_passe' => 'Secret-123456',
        ]);

        $reponse->assertOk();
        $droits = $reponse->json('utilisateur.droits');
        $this->assertSame('C', $droits['PROFIL_NOM'] ?? null);
        $this->assertSame('C', $droits['PROFIL_INTITULE'] ?? null);
    }
}

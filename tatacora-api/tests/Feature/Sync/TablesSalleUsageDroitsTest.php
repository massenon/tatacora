<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Ventes\Models\Panier;
use App\Domain\Ventes\Models\TableSalle;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Bogue du PO (09/11/2026) : le barman du poste A prend des tables au point de
 * vente ; trois lignes « Tables de salle — Droit manquant » dans « À traiter ».
 *
 * CAUSE : `TableSalleService`/`GestionnaireTablesSalle` exigeait M5 ET `PARAM`
 * (écriture) pour TOUTE opération sur `tables_salle`. Or le poste enfile une
 * `creation` de la table (`assurerConnueDuServeur`) au premier geste d'USAGE
 * qui la cite (prendre une table au POS) quand il ne l'a pas encore reçue du
 * serveur : le serveur la FUSIONNE avec la sienne (même espace, même numéro),
 * c'est-à-dire n'écrit rien. Un compte jugé sur `PARAM` (barman : `-` ; gérant :
 * `L`) était donc refusé pour un geste qui ne change pas la salle.
 *
 * RÈGLE : l'USAGE (prendre / libérer une table, ou citer une table qui existe
 * déjà) exige M5 en écriture, le droit du point de vente ; la CONFIGURATION
 * (créer une table nouvelle, renuméroter, changer les places, activer /
 * désactiver) exige EN PLUS `PARAM` en écriture.
 *
 * Le droit se juge sur le compte du JETON D'APPAIRAGE (`request()->user()`),
 * seul compte que le serveur connaisse d'un poste : les connexions locales du
 * poste ne sont pas des comptes serveur.
 */
final class TablesSalleUsageDroitsTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private TableSalle $r1;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->r1 = TableSalle::create(['espace' => 'restaurant', 'numero' => 1, 'libelle' => 'R1', 'places' => 4, 'actif' => true]);
    }

    /** @return array<string, array{0: string}> */
    public static function rolesDeVente(): array
    {
        // Les rôles de la matrice qui ÉCRIVENT sur M5 (le POS) : l'usage leur est ouvert.
        return ['barman' => ['barman'], 'gérant' => ['gerant'], 'administrateur' => ['administrateur'], 'super admin' => ['super_admin']];
    }

    /** @return array<string, array{0: string}> */
    public static function rolesSansVente(): array
    {
        // M5 en lecture (`receptionniste`, `magasinier`, `comptable`) ou sans M5 (`cuisine`, `achats`).
        return [
            'réceptionniste (M5 en lecture)' => ['receptionniste'],
            'magasinier (M5 en lecture)' => ['magasinier'],
            'comptable (M5 en lecture)' => ['comptable'],
            'cuisine (sans M5)' => ['cuisine'],
            'achats (sans M5)' => ['achats'],
            'RH (sans M5)' => ['rh'],
        ];
    }

    #[Test]
    #[DataProvider('rolesDeVente')]
    public function le_compte_du_jeton_qui_vend_prend_une_table_que_le_poste_croyait_inconnue(string $role): void
    {
        $compte = $this->creerUtilisateur($role);
        [$tablePoste, $panier] = [$this->uuid(), $this->uuid()];

        // Ce que le poste enfile à la première prise de R1 : la table, puis l'ouverture.
        $this->pousser([
            $this->creation('tables_salle', $tablePoste, ['espace' => 'restaurant', 'numero' => 1, 'places' => 4]),
            $this->creation('paniers', $panier, ['point_vente' => 'Bar', 'table_id' => $tablePoste]),
        ], $compte)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.fusionne_avec', $this->r1->id)
            ->assertJsonPath('resultats.1.statut', 'synchronise');

        $this->assertSame(1, TableSalle::query()->count(), 'la fusion ne crée aucune seconde table');
        $this->assertSame($this->r1->id, Panier::findOrFail($panier)->table_id);

        // Libérer : la fermeture de l'addition.
        $this->pousser([$this->operation('paniers', 'modification', $panier, ['statut' => 'cloture'])], $compte)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('cloture', Panier::findOrFail($panier)->statut);
    }

    #[Test]
    #[DataProvider('rolesDeVente')]
    public function la_configuration_du_plan_reste_reservee_au_droit_de_gestion(string $role): void
    {
        $compte = $this->creerUtilisateur($role);
        $gere = in_array($role, ['administrateur', 'super_admin'], true);
        $attendu = $gere ? 'synchronise' : 'rejete';

        // Une table NOUVELLE (aucune de cet espace et de ce numéro) : c'est de la configuration.
        $nouvelle = $this->uuid();
        $this->pousser([$this->creation('tables_salle', $nouvelle, ['espace' => 'plage', 'numero' => 2, 'places' => 6])], $compte)
            ->assertJsonPath('resultats.0.statut', $attendu)
            ->assertJsonPath('resultats.0.code_motif', $gere ? null : 'droit_manquant');
        $this->assertSame($gere, TableSalle::query()->where('id', $nouvelle)->exists());

        // Renuméroter, changer les places, désactiver : idem.
        foreach ([['numero' => 7], ['places' => 9], ['actif' => false]] as $champs) {
            $this->pousser([$this->operation('tables_salle', 'modification', $this->r1->id, $champs)], $compte)
                ->assertJsonPath('resultats.0.statut', $attendu);
        }

        $r1 = $this->r1->refresh();
        $this->assertSame($gere ? [7, 9, false] : [1, 4, true], [(int) $r1->numero, (int) $r1->places, (bool) $r1->actif]);
    }

    #[Test]
    #[DataProvider('rolesSansVente')]
    public function un_compte_qui_ne_vend_pas_n_obtient_rien_sur_la_salle(string $role): void
    {
        $compte = $this->creerUtilisateur($role);

        $this->pousser([
            $this->creation('tables_salle', $this->uuid(), ['espace' => 'restaurant', 'numero' => 1]),
            $this->creation('tables_salle', $this->uuid(), ['espace' => 'jardin', 'numero' => 1]),
            $this->creation('paniers', $this->uuid(), ['point_vente' => 'Bar', 'table_id' => $this->r1->id]),
        ], $compte)
            ->assertJsonPath('resultats.0.code_motif', 'droit_manquant')
            ->assertJsonPath('resultats.1.code_motif', 'droit_manquant')
            ->assertJsonPath('resultats.2.code_motif', 'droit_manquant');

        $this->assertSame(1, TableSalle::query()->count());
        $this->assertSame(0, Panier::query()->count());
    }

    #[Test]
    public function un_compte_desactive_est_toujours_refuse_meme_pour_l_usage(): void
    {
        $barman = $this->creerUtilisateur('barman');
        $barman->forceFill(['statut' => 'desactive'])->save();

        $this->pousser([$this->creation('tables_salle', $this->uuid(), ['espace' => 'restaurant', 'numero' => 1])], $barman)
            ->assertJsonPath('resultats.0.code_motif', 'compte_inactif');
    }

    #[Test]
    public function la_meme_operation_rejouee_ne_double_rien_et_rend_le_meme_verdict(): void
    {
        $barman = $this->creerUtilisateur('barman');
        $operation = $this->creation('tables_salle', $this->uuid(), ['espace' => 'restaurant', 'numero' => 1]);

        $premier = $this->pousser([$operation], $barman)->json('resultats.0');
        $second = $this->pousser([$operation], $barman)->json('resultats.0');

        $this->assertSame('synchronise', $premier['statut']);
        $this->assertSame($premier['fusionne_avec'], $second['fusionne_avec']);
        $this->assertSame(1, TableSalle::query()->count());
    }

    #[Test]
    public function une_operation_rejetee_pour_droit_manquant_se_relance_sous_un_nouvel_identifiant_et_passe_apres_le_droit(): void
    {
        // Le cas de la capture : le compte du jeton n'avait pas le droit (rôle sans M5),
        // le rejet est DÉFINITIF et mémorisé sous l'ancien identifiant d'opération…
        $compte = $this->creerUtilisateur('receptionniste');
        $table = $this->uuid();
        $ancienne = $this->creation('tables_salle', $table, ['espace' => 'restaurant', 'numero' => 1]);

        $this->pousser([$ancienne], $compte)->assertJsonPath('resultats.0.code_motif', 'droit_manquant');
        // … rejouée à l'identique, elle est rejugée à l'identique (pas de boucle de re-jugement).
        $this->pousser([$ancienne], $compte)->assertJsonPath('resultats.0.statut', 'rejete');

        // Le droit est accordé ; « Renvoyer » (poste) = MÊME élément, MÊME document, NOUVEL uuid d'opération.
        $compte->forceFill(['role_id' => Role::where('libelle', 'barman')->firstOrFail()->id])->save();
        $relance = [...$ancienne, 'uuid_operation' => $this->uuid()];

        // Le contrôleur est mémorisé par la route le temps du test : en production,
        // chaque requête repart d'un service neuf, qui relit le compte.
        foreach (app('router')->getRoutes() as $route) {
            $route->flushController();
        }

        $this->pousser([$relance], $compte->refresh())
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.fusionne_avec', $this->r1->id);
    }
}

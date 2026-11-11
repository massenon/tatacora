<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Ventes\Models\Panier;
use App\Domain\Ventes\Models\TableSalle;
use App\Models\User;
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
 * CAUSE : le serveur jugeait le compte du JETON D'APPAIRAGE (celui qui a appairé le
 * poste), pas l'utilisateur connecté au poste. Un premier correctif (a85db45)
 * distinguait l'USAGE (M5) de la CONFIGURATION (M5 + `PARAM`) ; la DÉCISION DU PO du
 * 09/11/2026 le remplace : « Le jeton du poste porte un seul compte. Tout ce qui sort
 * d'un poste appairé par le barman est jugé sur les droits du barman. NON, ÇA NE DOIT
 * PAS JUGER. » Le serveur ne juge donc plus AUCUN module du compte du jeton pour la
 * salle : prendre / libérer une table, en créer une, la renuméroter, changer ses places
 * ou l'activer sont acceptés pour tout compte ACTIF ; qui peut configurer le plan, c'est
 * le RBAC LOCAL du poste. Le serveur garde la cohérence (clé naturelle, table au panier
 * ouvert, idempotence) et le compte désactivé reste refusé.
 *
 * Ce fichier tient ce que la règle a laissé : la matrice rôle × table n'est plus une
 * présomption (tous les rôles passent), la fusion, l'idempotence, le compte désactivé, et
 * le « Renvoyer » d'un lot déjà rejeté « Droit manquant » dans « À traiter ».
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
    public function la_configuration_du_plan_n_est_pas_jugee_sur_le_compte_d_appairage(string $role): void
    {
        $compte = $this->creerUtilisateur($role);

        // Une table NOUVELLE, renuméroter, changer les places, désactiver : acceptés pour tous.
        $nouvelle = $this->uuid();
        $this->pousser([$this->creation('tables_salle', $nouvelle, ['espace' => 'plage', 'numero' => 2, 'places' => 6])], $compte)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertTrue(TableSalle::query()->where('id', $nouvelle)->exists());

        foreach ([['numero' => 7], ['places' => 9], ['actif' => false]] as $champs) {
            $this->pousser([$this->operation('tables_salle', 'modification', $this->r1->id, $champs)], $compte)
                ->assertJsonPath('resultats.0.statut', 'synchronise');
        }

        $r1 = $this->r1->refresh();
        $this->assertSame([7, 9, false], [(int) $r1->numero, (int) $r1->places, (bool) $r1->actif]);
    }

    #[Test]
    #[DataProvider('rolesSansVente')]
    public function un_compte_qui_ne_vend_pas_est_jugee_au_poste_pas_au_serveur(string $role): void
    {
        $compte = $this->creerUtilisateur($role);

        $this->pousser([
            $this->creation('tables_salle', $this->uuid(), ['espace' => 'jardin', 'numero' => 1]),
            $this->creation('paniers', $this->uuid(), ['point_vente' => 'Bar', 'table_id' => $this->r1->id]),
        ], $compte)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.1.statut', 'synchronise');

        $this->assertSame(2, TableSalle::query()->count());
        $this->assertSame(1, Panier::query()->count());
    }

    #[Test]
    public function une_table_deja_prise_reste_refusee_par_coherence_pas_par_droit(): void
    {
        $barman = $this->creerUtilisateur('barman');

        $this->pousser([$this->creation('paniers', $this->uuid(), ['point_vente' => 'Bar', 'table_id' => $this->r1->id])], $barman)
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        // Une seconde ouverture de la MÊME table : règle de cohérence du service (verrou de plage).
        $this->pousser([$this->creation('paniers', $this->uuid(), ['point_vente' => 'Bar', 'table_id' => $this->r1->id])], $barman)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.code_motif', 'regle_metier');
        $this->assertSame(1, Panier::query()->count());
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
    public function un_lot_deja_rejete_droit_manquant_se_relance_sous_un_nouvel_identifiant_et_passe(): void
    {
        // Le cas de la capture : avant la décision du PO, le serveur avait rejeté DÉFINITIVEMENT
        // (et mémorisé) l'opération sous l'ancien identifiant. On reconstitue ce refus mémorisé,
        // tel qu'il dort dans « À traiter » du poste.
        $compte = $this->creerUtilisateur('receptionniste');
        $table = $this->uuid();
        $ancienne = $this->creation('tables_salle', $table, ['espace' => 'restaurant', 'numero' => 1]);
        \App\Shared\Sync\Models\DeduplicationSynchronisation::create([
            'uuid_operation' => $ancienne['uuid_operation'],
            'utilisateur_id' => $compte->id,
            'poste_id' => 'poste-windows-1',
            'table_concernee' => 'tables_salle',
            'entite_id' => $table,
            'resultat' => [
                'uuid_operation' => $ancienne['uuid_operation'], 'statut' => 'rejete', 'entite_id' => $table,
                'motif' => __('auth.module_refuse'), 'code_motif' => 'droit_manquant',
            ],
            'horodatage_client' => $ancienne['horodatage_client'],
            'date_traitement' => now(),
        ]);

        // Rejouée à l'identique, la mémoire d'idempotence rend le MÊME refus (c'est son rôle) …
        $this->pousser([$ancienne], $compte)->assertJsonPath('resultats.0.code_motif', 'droit_manquant');

        // … « Renvoyer » (poste) = MÊME élément, MÊME document, NOUVEL uuid d'opération : il passe,
        // sans qu'aucun droit n'ait été accordé à quiconque.
        $relance = [...$ancienne, 'uuid_operation' => $this->uuid()];
        $this->pousser([$relance], $compte)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.fusionne_avec', $this->r1->id);
    }
}

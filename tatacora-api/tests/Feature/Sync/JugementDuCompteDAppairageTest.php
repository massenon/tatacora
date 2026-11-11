<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Crm\Models\Client;
use App\Domain\Ventes\Models\Panier;
use App\Domain\Ventes\Models\TableSalle;
use App\Domain\Ventes\Services\TableSalleService;
use App\Models\User;
use App\Shared\Rbac\Models\JournalSecurite;
use App\Shared\Rbac\Models\Role;
use App\Shared\Rbac\Services\RolePermissionService;
use App\Shared\Sync\Gestionnaires\GestionnaireTablesSalle;
use App\Shared\Sync\Models\DeduplicationSynchronisation;
use App\Shared\Sync\Models\JournalReceptionSynchronisation;
use App\Shared\Sync\Models\SessionSynchronisation;
use App\Shared\Sync\Services\RegistreSynchronisation;
use App\Shared\Sync\Support\OperationsSensibles;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Mockery;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * DÉCISION DU PO (09/11/2026) : « Le jeton du poste porte un seul compte. Tout ce qui
 * sort d'un poste appairé par le barman est jugé sur les droits du barman. NON, ÇA NE
 * DOIT PAS JUGER » ; « AUCUNE OPÉRATION NE DOIT BLOQUER LA SYNCHRONISATION ».
 *
 * Le serveur ne juge plus les modules du compte du JETON D'APPAIRAGE pour une opération
 * d'usage ou de saisie courante : le droit se juge AU POSTE, sur l'utilisateur connecté.
 * Il garde le jeton, le poste, le compte ACTIF, l'idempotence, la cohérence métier, le
 * journal — et la liste fermée `OperationsSensibles`, rejetée SEULE.
 *
 * Ce fichier épingle la règle générale (un compte SANS AUCUN droit passe), la liste
 * fermée (relue du code, pas recopiée), et la preuve que rien ne bloque : un refus, une
 * dépendance pas encore reçue ou une erreur imprévue sur UNE opération laissent passer
 * les autres, de la même table comme des tables suivantes du lot. Mutations : voir le
 * journal des lots du 09/11/2026.
 */
final class JugementDuCompteDAppairageTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $sansDroit;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        // Un rôle SANS AUCUN droit : '-' sur tous les modules. Si le serveur jugeait encore
        // le compte du jeton, rien ne passerait.
        $role = app(RolePermissionService::class)->creerRole('sans_aucun_droit', 'Aucun module', null);
        $this->assertSame('-', $role->niveauSurModule('M5'));
        $this->assertSame('-', $role->niveauSurModule('PARAM'));
        $this->sansDroit = User::create([
            'login' => 'jeton.sans.droit',
            'mot_de_passe_hash' => 'x',
            'role_id' => $role->id,
            'statut' => 'actif',
        ]);

        TableSalle::create(['espace' => 'restaurant', 'numero' => 1, 'libelle' => 'R1', 'places' => 4, 'actif' => true]);
    }

    private function client(string $nom): array
    {
        return $this->creation('clients', $this->uuid(), ['nom' => $nom, 'telephone' => '9600' . random_int(1000, 9999), 'type_client' => 'particulier']);
    }

    /* ------------------------------------------------------------------ */
    /* La règle générale                                                    */
    /* ------------------------------------------------------------------ */

    #[Test]
    public function un_compte_sans_aucun_droit_voit_ses_operations_d_usage_acceptees(): void
    {
        [$table, $panier] = [$this->uuid(), $this->uuid()];

        $this->pousser([
            $this->client('Sabi'),
            // Une table NOUVELLE (c'était de la « configuration » exigeant PARAM) puis le panier qui la cite.
            $this->creation('tables_salle', $table, ['espace' => 'restaurant', 'numero' => 3, 'places' => 6]),
            $this->creation('paniers', $panier, ['point_vente' => 'Bar', 'table_id' => $table]),
            $this->operation('tables_salle', 'modification', $table, ['places' => 8, 'numero' => 4]),
        ], $this->sansDroit)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.1.statut', 'synchronise')
            ->assertJsonPath('resultats.2.statut', 'synchronise')
            ->assertJsonPath('resultats.3.statut', 'synchronise');

        $this->assertSame(1, Client::query()->count());
        $this->assertSame(8, (int) TableSalle::findOrFail($table)->places);
        $this->assertSame($table, Panier::findOrFail($panier)->table_id);
        $this->assertSame(0, JournalSecurite::where('type_evenement', 'acces_refuse_rbac')->count(), 'rien n\'est refusé, rien n\'est tracé comme refus');
    }

    #[Test]
    public function un_compte_desactive_reste_refuse_meme_pour_l_usage(): void
    {
        $this->sansDroit->forceFill(['statut' => 'desactive'])->save();

        $this->pousser([$this->client('Sabi'), $this->creation('tables_salle', $this->uuid(), ['espace' => 'restaurant', 'numero' => 3])], $this->sansDroit)
            ->assertJsonPath('resultats.0.code_motif', 'compte_inactif')
            ->assertJsonPath('resultats.1.code_motif', 'compte_inactif');

        $this->assertSame(0, Client::query()->count());
    }

    /* ------------------------------------------------------------------ */
    /* La liste fermée — relue du CODE, jamais recopiée                     */
    /* ------------------------------------------------------------------ */

    /** @return array<string, array{0: string}> */
    public static function tablesDuRegistre(): array
    {
        $tables = [];

        foreach (array_keys(RegistreSynchronisation::TABLES_SYNCHRONISABLES) as $table) {
            $tables[$table] = [$table];
        }

        return $tables;
    }

    /**
     * Les charges qui, hier, faisaient exiger un module de plus (plat, location, tourisme,
     * table nouvelle, article du bar…) : un gestionnaire ne doit en exiger AUCUN.
     *
     * @return list<array<string, mixed>>
     */
    private function chargesPiegees(): array
    {
        return [
            [],
            ['plat_id' => 'p-1'],
            ['espace' => 'plage', 'numero' => 99],
            ['espace' => 'restaurant', 'numero' => 1],
            ['lignes' => [['module_source' => 'M4'], ['module_source' => 'M8'], ['module_source' => 'M9']]],
            ['actif' => false],
            ['valeurs' => ['nom_etablissement' => 'Gîte']],
        ];
    }

    #[Test]
    #[DataProvider('tablesDuRegistre')]
    public function aucune_table_du_registre_n_exige_de_module_hors_la_liste_fermee(string $table): void
    {
        $gestionnaire = app(RegistreSynchronisation::class)->pour($table);
        $exigeParLeModule = [];

        foreach ($this->chargesPiegees() as $charge) {
            if ($gestionnaire->modulesRequis($charge) !== []) {
                $exigeParLeModule[] = $charge;
            }
        }

        if ($table === 'demandes_cloture_exercice') {
            $this->assertSame(['M10'], $gestionnaire->modulesRequis([]), 'la clôture d\'exercice exige l\'écriture sur M10 (liste fermée)');
            $this->assertArrayHasKey($table, OperationsSensibles::PAR_TABLE);

            return;
        }

        if ($table === 'pieces_saisie') {
            $this->assertSame([], $gestionnaire->modulesRequis(['statut' => 'validee']), 'une pièce ordinaire est une saisie courante');
            $this->assertSame(['M10'], $gestionnaire->modulesRequis(['affectation' => ['annee' => 2025]]), 'l\'affectation du résultat est sensible (liste fermée)');
            $this->assertArrayHasKey($table, OperationsSensibles::PAR_TABLE);

            return;
        }

        $this->assertSame([], $exigeParLeModule, "« {$table} » exige un module du compte d'appairage : décision du PO du 09/11/2026, le droit se juge au poste");
    }

    #[Test]
    public function la_liste_fermee_ne_porte_que_les_decisions_explicites_du_po(): void
    {
        $this->assertSame(
            ['demandes_cloture_exercice', 'pieces_saisie', 'parametres_systeme', 'utilisateurs'],
            array_keys(OperationsSensibles::PAR_TABLE),
        );

        // Les deux autres sont jugées par un droit PARTICULIER (`refusDeDroit`), jamais par un module.
        $registre = app(RegistreSynchronisation::class);
        $barman = $this->creerUtilisateur('barman');

        $this->assertNotNull($registre->pour('parametres_systeme')->refusDeDroit(['valeurs' => ['facturation_mode' => 'emecef']], $barman));
        $this->assertNotNull($registre->pour('parametres_systeme')->refusDeDroit(['valeurs' => ['forme_juridique' => 'sarl']], $barman));
        $this->assertNull($registre->pour('parametres_systeme')->refusDeDroit(['valeurs' => ['nom_etablissement' => 'Gîte']], $barman), 'un réglage ordinaire ne se juge pas');

        // Aucun autre gestionnaire ne juge un droit particulier.
        foreach ($registre->tous() as $table => $gestionnaire) {
            if ($table === 'parametres_systeme') {
                continue;
            }

            foreach ($this->chargesPiegees() as $charge) {
                $this->assertNull($gestionnaire->refusDeDroit($charge, $barman), "« {$table} » juge un droit du compte d'appairage");
            }
        }
    }

    #[Test]
    public function le_rbac_du_web_pour_corriger_une_operation_recue_ne_change_pas(): void
    {
        // Le WEB garde le RBAC par module (décision du PO du 09/11/2026) : corriger / relancer une
        // opération reçue exige toujours le module de la donnée, y compris les modules en plus d'un plat.
        $registre = app(RegistreSynchronisation::class);

        $this->assertSame(['M5', 'M4', 'M8', 'M9'], $registre->pour('ventes')->modulesDeLaCorrection(['lignes' => [
            ['module_source' => 'M4'], ['module_source' => 'M8'], ['module_source' => 'M9'],
        ]]));
        $this->assertSame(['M5'], $registre->pour('ventes')->modulesDeLaCorrection(['lignes' => []]));
        $this->assertSame(['M4'], $registre->pour('indisponibilites_carte')->modulesDeLaCorrection(['plat_id' => 'p']));
        $this->assertSame(['M5', 'PARAM'], $registre->pour('tables_salle')->modulesDeLaCorrection(['espace' => 'plage', 'numero' => 99]));
        $this->assertSame(['M5'], $registre->pour('tables_salle')->modulesDeLaCorrection(['espace' => 'restaurant', 'numero' => 1]));

        // Toute table nomme au moins son module pour la correction web.
        foreach ($registre->tous() as $table => $gestionnaire) {
            $this->assertContains($gestionnaire->module(), $gestionnaire->modulesDeLaCorrection([]), "« {$table} »");
        }
    }

    #[Test]
    public function la_clôture_d_exercice_est_refusee_seule_et_les_autres_operations_du_lot_passent(): void
    {
        $this->pousser([
            $this->client('Avant'),
            $this->creation('demandes_cloture_exercice', $this->uuid(), ['annee' => 2026, 'action' => 'demarrer']),
            $this->client('Apres'),
            $this->creation('tables_salle', $this->uuid(), ['espace' => 'restaurant', 'numero' => 3]),
        ], $this->sansDroit)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.1.statut', 'rejete')
            ->assertJsonPath('resultats.1.code_motif', 'droit_manquant')
            ->assertJsonPath('resultats.2.statut', 'synchronise')
            ->assertJsonPath('resultats.3.statut', 'synchronise');

        $this->assertSame(2, Client::query()->count());
        $this->assertSame(1, JournalSecurite::where('type_evenement', 'acces_refuse_rbac')->where('module_concerne', 'M10')->count());
        $this->assertSame('partiel', SessionSynchronisation::query()->latest('date_sync')->value('statut'));
    }

    /* ------------------------------------------------------------------ */
    /* Aucune opération ne bloque la synchronisation                        */
    /* ------------------------------------------------------------------ */

    #[Test]
    public function un_rejet_metier_ne_bloque_ni_les_suivantes_de_la_table_ni_les_tables_suivantes(): void
    {
        // Une table du même espace et du même numéro mais sans espace : refus de donnée (cohérence).
        $this->pousser([
            $this->creation('tables_salle', $this->uuid(), ['numero' => 3]), // espace manquant : rejet de cohérence
            $this->creation('tables_salle', $this->uuid(), ['espace' => 'restaurant', 'numero' => 3]),
            $this->client('Apres'),
        ], $this->sansDroit)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.1.statut', 'synchronise')
            ->assertJsonPath('resultats.2.statut', 'synchronise');
    }

    #[Test]
    public function une_dependance_pas_encore_recue_est_differee_jamais_memorisee_puis_acceptee_dans_l_ordre(): void
    {
        [$table, $panier] = [$this->uuid(), $this->uuid()];
        $ouverture = $this->creation('paniers', $panier, ['point_vente' => 'Bar', 'table_id' => $table]);
        $fermeture = $this->operation('paniers', 'modification', $panier, ['statut' => 'cloture']);

        // 1. La table citée n'est pas encore connue ; l'opération du MÊME panier qui suit
        //    attend derrière (jamais « élément inconnu » définitif) ; le client passe.
        $this->pousser([$ouverture, $fermeture, $this->client('Passe')], $this->sansDroit)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.code_motif', 'dependance_manquante')
            ->assertJsonPath('resultats.1.statut', 'rejete')
            ->assertJsonPath('resultats.1.code_motif', 'dependance_manquante')
            ->assertJsonPath('resultats.2.statut', 'synchronise');

        // Aucun résultat différé n'est MÉMORISÉ : le même identifiant sera rejugé pour de bon.
        $this->assertSame(0, DeduplicationSynchronisation::whereIn('uuid_operation', [$ouverture['uuid_operation'], $fermeture['uuid_operation']])->count());
        $this->assertSame(0, Panier::query()->count());
        $this->assertSame('dependance_manquante', JournalReceptionSynchronisation::where('uuid_operation', $ouverture['uuid_operation'])->value('code_motif'));

        // 2. La table arrive (création de l'élément cité), puis le poste RENVOIE les deux
        //    opérations sous LEUR identifiant : elles passent, dans l'ordre.
        $this->pousser([$this->creation('tables_salle', $table, ['espace' => 'plage', 'numero' => 3, 'places' => 4])], $this->sansDroit)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->pousser([$ouverture, $fermeture], $this->sansDroit)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.1.statut', 'synchronise');

        $this->assertSame('cloture', Panier::findOrFail($panier)->statut);
        $this->assertSame(0, Panier::query()->where('statut', Panier::STATUT_OUVERT)->count());
        // Le journal n'affiche plus « refusé » : la reprise a remplacé la ligne différée.
        $this->assertNotSame('dependance_manquante', JournalReceptionSynchronisation::where('uuid_operation', $ouverture['uuid_operation'])->value('code_motif'));
    }

    #[Test]
    public function une_erreur_imprevue_sur_une_operation_ne_fait_pas_echouer_le_lot(): void
    {
        $this->app->bind(GestionnaireTablesSalle::class, function () {
            $faux = Mockery::mock(GestionnaireTablesSalle::class, [app(TableSalleService::class)])->makePartial();
            $faux->shouldReceive('creer')->andThrow(new \LogicException('bogue de programmation simulé'));

            return $faux;
        });

        $operationEnErreur = $this->creation('tables_salle', $this->uuid(), ['espace' => 'restaurant', 'numero' => 3]);

        // Avant : un 500 sur tout le lot, le même 500 à chaque passage, la file derrière bloquée.
        $this->pousser([$this->client('Avant'), $operationEnErreur, $this->client('Apres')], $this->sansDroit)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.1.statut', 'rejete')
            ->assertJsonPath('resultats.1.code_motif', 'erreur_serveur')
            ->assertJsonPath('resultats.2.statut', 'synchronise');

        $this->assertSame(2, Client::query()->count());
        $this->assertSame(0, DeduplicationSynchronisation::where('uuid_operation', $operationEnErreur['uuid_operation'])->count(), 'jamais mémorisée : rejouée pour de bon');
        $this->assertSame('erreur', JournalReceptionSynchronisation::where('uuid_operation', $operationEnErreur['uuid_operation'])->value('issue'));
    }

    #[Test]
    public function un_role_de_la_matrice_n_est_jamais_juge_sur_ses_modules(): void
    {
        // La matrice du seeder n'est pas une présomption : on balaie TOUS les rôles, y compris
        // ceux qui n'écrivent nulle part (cuisine, achats, RH), sur une saisie de salle.
        foreach (array_keys(RolePermissionSeeder::MATRICE) as $i => $role) {
            $compte = $this->creerUtilisateur($role);

            $resultat = $this->pousser([$this->creation('tables_salle', $this->uuid(), ['espace' => 'restaurant', 'numero' => 20 + $i])], $compte)->json('resultats.0');
            $this->assertSame('synchronise', $resultat['statut'], "rôle {$role} : " . ($resultat['motif'] ?? ''));
        }

        $this->assertSame(0, Role::query()->where('libelle', 'introuvable')->count());
    }
}

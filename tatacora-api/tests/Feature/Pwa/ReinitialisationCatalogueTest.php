<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Models\User;
use App\Shared\Backup\Services\ReinitialisationDonneesTestService;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\DemonstrationSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Symfony\Component\Process\Process;
use Tests\TestCase;

/**
 * Demande du Product Owner (correction) : « Quand je VIDE les seeders ou les
 * données de test, les données des tables PLATS, INGRÉDIENTS, ARTICLES, CARTES
 * BOISSON et leurs AUTRES TABLES LIÉES EN JOINTURE doivent être vidées AUSSI. »
 *
 * Aucune liste de tables n'est recopiée ici : l'arbre du catalogue est
 * ÉNUMÉRÉ sur les clés étrangères réelles (`information_schema`), pour qu'une
 * table jointe ajoutée demain soit exigée vide sans qu'on y pense.
 */
final class ReinitialisationCatalogueTest extends TestCase
{
    use RefreshDatabase;

    /** Les racines nommées par le PO (+ menus et recettes, leurs parents de jointure). */
    private const RACINES = [
        'plats', 'menus', 'recettes', 'ingredients_recette', 'articles', 'cartes_boisson',
    ];

    /**
     * Les jointures SANS clé étrangère : une colonne qui désigne une ligne du
     * catalogue par son identifiant seul (`source_id` polymorphe de
     * l'historique des prix). Détectées par NOM de colonne, sur les tables
     * GARDÉES.
     */
    private const COLONNES_DE_JOINTURE = '/^(article_id|plat_id|boisson_id|recette_id|menu_id|carte_boisson_id|source_id)$/';

    #[Test]
    public function tout_l_arbre_du_catalogue_est_vide_apres_la_reinitialisation(): void
    {
        if (! $this->mysqldumpDisponible()) {
            $this->markTestSkipped('mysqldump introuvable : la sauvegarde préalable ne peut pas être éprouvée ici.');
        }

        $this->seed(DemonstrationSeeder::class);
        $administrateur = $this->administrateur();
        $this->completerLeCatalogue($administrateur);

        $arbre = $this->arbreDuCatalogue();

        // Le catalogue semé est COMPLET : chaque table de l'arbre est peuplée
        // AVANT (sinon le test passerait à vide).
        foreach (['articles', 'mouvements_stock', 'plats', 'recettes', 'ingredients_recette', 'cartes_boisson',
            'indisponibilites_carte', 'menus', 'historique_prix_carte'] as $table) {
            $this->assertGreaterThan(0, DB::table($table)->count(), "`{$table}` n'est pas semée.");
        }

        ParametreSysteme::updateOrCreate(
            ['cle' => ReinitialisationDonneesTestService::CLE_BASCULE],
            ['valeur' => 'true'],
        );

        $resultat = app(ReinitialisationDonneesTestService::class)->executer($administrateur);
        @unlink(storage_path('app/sauvegardes/'.$resultat['sauvegarde']));

        foreach ($arbre as $table) {
            $this->assertSame(0, DB::table($table)->count(), "`{$table}` (catalogue ou jointure) n'a pas été vidée.");
        }

        foreach ($this->tablesGardeesAvecJointureSansCle() as $reference) {
            $this->assertSame(0, DB::table($reference['table'])->count(), "`{$reference['table']}` désigne le catalogue par `{$reference['colonne']}` et survit orpheline.");
        }

        // Les registres de référence restent : comptes, rôles, paramètres,
        // plan comptable, et le LIEU de stockage (un référentiel, pas un article).
        foreach (['utilisateurs', 'roles', 'parametres_systeme', 'plan_comptable', 'points_stockage'] as $table) {
            $this->assertGreaterThan(0, DB::table($table)->count(), "`{$table}` devait être gardée.");
        }
    }

    #[Test]
    public function aucune_table_liee_au_catalogue_n_est_oubliee(): void
    {
        $service = app(ReinitialisationDonneesTestService::class);
        $effacables = $service->tablesEffacables();

        $arbre = $this->arbreDuCatalogue();
        $this->assertContains('mouvements_stock', $arbre, 'La sonde ne voit pas les mouvements : elle est cassée.');
        $this->assertContains('indisponibilites_carte', $arbre);

        foreach ($arbre as $table) {
            $this->assertContains($table, $effacables, "`{$table}` référence le catalogue mais n'est pas vidée.");
            $this->assertNotContains($table, ReinitialisationDonneesTestService::TABLES_PRESERVEES);
        }

        foreach ($this->tablesGardeesAvecJointureSansCle() as $reference) {
            $this->fail("`{$reference['table']}.{$reference['colonne']}` désigne le catalogue sans clé étrangère et la table est GARDÉE.");
        }

        // Aucune table gardée ne référence l'arbre vidé (sauf le rattachement
        // utilisateur -> employé, étranger au catalogue et déjà arbitré).
        foreach ($this->clesEtrangeres() as $cle) {
            if (in_array($cle->cible, $arbre, true) && ! in_array($cle->source, $arbre, true)) {
                $this->fail("`{$cle->source}` (gardée) référence `{$cle->cible}` (vidée).");
            }
        }
    }

    #[Test]
    public function l_ecran_dit_que_le_catalogue_est_vide(): void
    {
        foreach (['seeders_vide_texte', 'seeders_modale_texte_1'] as $cle) {
            $texte = (string) __('pwa.import_export.'.$cle);
            foreach (['plats', 'articles', 'recettes', 'carte des boissons'] as $mot) {
                $this->assertStringContainsString($mot, $texte, "`{$cle}` ne dit pas que « {$mot} » est vidé.");
            }
        }

        $this->assertStringNotContainsString('articles', (string) __('pwa.import_export.seeders_conserve_texte'));
    }

    // ---------------------------------------------------------------- privé

    /**
     * Les racines + toute table qui les référence, transitivement, par clé
     * étrangère réelle.
     *
     * @return list<string>
     */
    private function arbreDuCatalogue(): array
    {
        $cles = $this->clesEtrangeres();
        $arbre = self::RACINES;

        do {
            $avant = count($arbre);
            foreach ($cles as $cle) {
                if (in_array($cle->cible, $arbre, true) && ! in_array($cle->source, $arbre, true)) {
                    $arbre[] = $cle->source;
                }
            }
        } while (count($arbre) > $avant);

        sort($arbre);

        return $arbre;
    }

    /** @return list<object{source: string, cible: string}> */
    private function clesEtrangeres(): array
    {
        return DB::select(
            'SELECT TABLE_NAME AS source, REFERENCED_TABLE_NAME AS cible FROM information_schema.KEY_COLUMN_USAGE'
            .' WHERE TABLE_SCHEMA = DATABASE() AND REFERENCED_TABLE_NAME IS NOT NULL',
        );
    }

    /**
     * Les tables GARDÉES qui portent une colonne de jointure vers le
     * catalogue sans clé étrangère.
     *
     * @return list<array{table: string, colonne: string}>
     */
    private function tablesGardeesAvecJointureSansCle(): array
    {
        $gardees = app(ReinitialisationDonneesTestService::class)->tablesPreservees();
        $trouvees = [];

        $colonnes = DB::select(
            'SELECT TABLE_NAME AS nom, COLUMN_NAME AS colonne FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()',
        );
        foreach ($colonnes as $colonne) {
            if (in_array($colonne->nom, $gardees, true) && preg_match(self::COLONNES_DE_JOINTURE, $colonne->colonne) === 1) {
                $trouvees[] = ['table' => $colonne->nom, 'colonne' => $colonne->colonne];
            }
        }

        return $trouvees;
    }

    /** Ce que la démonstration ne sème pas : indisponibilité, historique des prix. */
    private function completerLeCatalogue(User $auteur): void
    {
        $plat = DB::table('plats')->first();
        $boisson = DB::table('cartes_boisson')->first();

        if (DB::table('indisponibilites_carte')->count() === 0) {
            $colonnes = collect(DB::select('SHOW COLUMNS FROM indisponibilites_carte'))->keyBy('Field');
            $ligne = ['id' => (string) Str::uuid(), 'plat_id' => $plat->id, 'boisson_id' => null];
            foreach ($colonnes as $nom => $colonne) {
                if (array_key_exists($nom, $ligne) || $colonne->Null === 'YES' || $colonne->Default !== null || str_contains((string) $colonne->Extra, 'auto_increment')) {
                    continue;
                }
                $ligne[$nom] = match (true) {
                    $nom === 'utilisateur_id' => $auteur->id,
                    str_starts_with((string) $colonne->Type, 'enum') => $this->premierEnum((string) $colonne->Type),
                    str_contains((string) $colonne->Type, 'timestamp'), str_contains((string) $colonne->Type, 'datetime') => now(),
                    default => 'temoin',
                };
            }
            DB::table('indisponibilites_carte')->insert($ligne);
        }

        if (DB::table('historique_prix_carte')->count() === 0) {
            DB::table('historique_prix_carte')->insert([
                'id' => (string) Str::uuid(), 'source' => 'plat', 'source_id' => $plat->id,
                'champ' => 'prix_vente', 'ancien_prix' => 1000, 'nouveau_prix' => 1200,
            ]);
            DB::table('historique_prix_carte')->insert([
                'id' => (string) Str::uuid(), 'source' => 'carte_boisson', 'source_id' => $boisson->id,
                'champ' => 'prix_vente', 'ancien_prix' => 500, 'nouveau_prix' => 600,
            ]);
        }
    }

    private function premierEnum(string $type): string
    {
        preg_match("/enum\\('([^']+)'/", $type, $m);

        return $m[1] ?? 'temoin';
    }

    private function administrateur(): User
    {
        return User::create([
            'login' => 'administrateur.catalogue-'.Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    private function mysqldumpDisponible(): bool
    {
        $processus = new Process([config('backup.mysqldump', 'mysqldump'), '--version']);
        $processus->setTimeout(15);
        $processus->run();

        return $processus->isSuccessful();
    }
}

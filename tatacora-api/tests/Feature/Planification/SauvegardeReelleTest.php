<?php

declare(strict_types=1);

namespace Tests\Feature\Planification;

use App\Shared\Backup\Jobs\SauvegardeBaseQuotidienneJob;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Symfony\Component\Process\Process;
use Tests\TestCase;

/**
 * La sauvegarde quotidienne, **réellement exécutée**.
 *
 * ## Pourquoi ce test existe
 *
 * `TachesPlanifieesTest` vérifie que le job est *planifié* et que sa commande
 * est bien *construite*. Il n'appelait jamais `handle()` : jusqu'ici, **aucun
 * fichier de sauvegarde n'avait jamais été produit** par le dépôt.
 *
 * C'est le pire endroit où laisser un chemin non éprouvé. Une sauvegarde qui
 * échoue ne dérange personne — on s'en aperçoit le jour où l'on en a besoin,
 * c'est-à-dire le jour où il est trop tard. Et l'échec d'un job planifié sur
 * cPanel est silencieux par nature : il part dans `failed_jobs`, que personne
 * ne consulte tant que tout va bien.
 *
 * ## Ce test dépend de `mysqldump`
 *
 * Il est **ignoré** si le binaire est absent, plutôt qu'échoué : sur une
 * machine sans client MySQL, l'absence n'est pas un défaut du code. Mais il
 * s'exécute partout où il peut, et c'est là tout l'intérêt — l'environnement
 * de développement du projet en dispose (`03_DATABASE_ENGINEERING.md`).
 *
 * @see PA-59 — même famille : un chemin jamais exécuté est un chemin non écrit
 */
final class SauvegardeReelleTest extends TestCase
{
    use RefreshDatabase;

    private string $repertoire;

    protected function setUp(): void
    {
        parent::setUp();

        $this->repertoire = storage_path('app/sauvegardes');

        if (! $this->mysqldumpDisponible()) {
            $this->markTestSkipped(
                'mysqldump introuvable : la sauvegarde ne peut pas etre eprouvee ici.',
            );
        }

        $this->viderRepertoire();
    }

    protected function tearDown(): void
    {
        $this->viderRepertoire();
        parent::tearDown();
    }

    private function mysqldumpDisponible(): bool
    {
        $binaire = config('backup.mysqldump', 'mysqldump');
        $processus = new Process([$binaire, '--version']);
        $processus->setTimeout(15);
        $processus->run();

        return $processus->isSuccessful();
    }

    private function viderRepertoire(): void
    {
        foreach (glob($this->repertoire.'/tatacora-*.sql') ?: [] as $fichier) {
            @unlink($fichier);
        }
    }

    /** @return list<string> */
    private function fichiers(): array
    {
        return glob($this->repertoire.'/tatacora-*.sql') ?: [];
    }

    #[Test]
    public function la_sauvegarde_produit_un_fichier_non_vide(): void
    {
        $bilan = (new SauvegardeBaseQuotidienneJob())->handle();

        $this->assertFileExists($bilan['fichier']);
        // `filesize() === 0` est deja verifie par le job lui-meme ; on
        // controle ici un seuil qui exclut un dump tronque au premier octet.
        $this->assertGreaterThan(1024, $bilan['octets']);
        $this->assertSame(filesize($bilan['fichier']), $bilan['octets']);
    }

    /**
     * Un dump qui ne contient aucune table est un fichier valide et inutile —
     * exactement le genre de sauvegarde qui rassure sans rien protéger.
     */
    #[Test]
    public function le_dump_contient_reellement_le_schema(): void
    {
        $bilan = (new SauvegardeBaseQuotidienneJob())->handle();
        $contenu = (string) file_get_contents($bilan['fichier']);

        $this->assertStringContainsString('CREATE TABLE', $contenu);

        // Trois tables au coeur du metier : si le dump les porte, il porte le
        // schema. Les chercher nommement evite qu'un dump partiel passe.
        foreach (['reservations', 'factures', 'ecritures_comptables'] as $table) {
            $this->assertStringContainsString($table, $contenu, "La table {$table} manque au dump.");
        }
    }

    #[Test]
    public function le_dump_porte_les_donnees_et_pas_seulement_la_structure(): void
    {
        // `mysqldump` sans `--no-data` doit ecrire les INSERT. Un dump de
        // structure seule restaurerait une base vide, ce qui a l'apparence
        // d'une sauvegarde reussie.
        $bilan = (new SauvegardeBaseQuotidienneJob())->handle();
        $contenu = (string) file_get_contents($bilan['fichier']);

        $this->assertStringContainsString('INSERT INTO', $contenu);
    }

    #[Test]
    public function deux_sauvegardes_ne_s_ecrasent_pas(): void
    {
        // Le nom porte l'horodatage a la seconde. Deux executions rapprochees
        // dans la meme seconde produiraient le meme nom et la seconde
        // effacerait la premiere — on verifie que ce n'est pas le cas sur deux
        // executions successives.
        $premier = (new SauvegardeBaseQuotidienneJob())->handle();
        sleep(1);
        $second = (new SauvegardeBaseQuotidienneJob())->handle();

        $this->assertNotSame($premier['fichier'], $second['fichier']);
        $this->assertCount(2, $this->fichiers());
    }

    #[Test]
    public function une_sauvegarde_recente_n_est_pas_purgee(): void
    {
        (new SauvegardeBaseQuotidienneJob())->handle();
        $bilan = (new SauvegardeBaseQuotidienneJob())->handle();

        $this->assertSame(0, $bilan['purgees']);
        $this->assertCount(2, $this->fichiers());
    }

    /**
     * La retention est le seul mecanisme qui empeche le disque de se remplir
     * jusqu'a faire echouer la sauvegarde suivante — celle dont on aurait
     * besoin.
     */
    #[Test]
    public function une_sauvegarde_trop_ancienne_est_purgee(): void
    {
        $ancienne = $this->repertoire.'/tatacora-2020-01-01_000000.sql';
        if (! is_dir($this->repertoire)) {
            mkdir($this->repertoire, 0755, true);
        }
        file_put_contents($ancienne, '-- vieille sauvegarde');
        touch($ancienne, now()->subDays(90)->getTimestamp());

        $bilan = (new SauvegardeBaseQuotidienneJob())->handle();

        $this->assertSame(1, $bilan['purgees']);
        $this->assertFileDoesNotExist($ancienne);
        $this->assertFileExists($bilan['fichier']);
    }

    /**
     * L'echec doit etre BRUYANT : le job part en `failed_jobs`.
     *
     * Un echec avale laisserait croire, chaque nuit, qu'une sauvegarde a eu
     * lieu. C'est le seul comportement qui soit pire que l'absence de
     * sauvegarde, parce qu'il retire la vigilance.
     */
    #[Test]
    public function un_binaire_introuvable_leve_une_exception(): void
    {
        config(['backup.mysqldump' => 'binaire-qui-n-existe-pas']);

        $this->expectException(RuntimeException::class);

        (new SauvegardeBaseQuotidienneJob())->handle();
    }

    #[Test]
    public function un_binaire_introuvable_ne_laisse_aucun_fichier(): void
    {
        config(['backup.mysqldump' => 'binaire-qui-n-existe-pas']);

        try {
            (new SauvegardeBaseQuotidienneJob())->handle();
        } catch (RuntimeException) {
            // attendu
        }

        $this->assertSame([], $this->fichiers());
    }

    /**
     * Le cas qui comptait, et qui laissait un orphelin.
     *
     * `mysqldump` existe mais echoue en cours de route — ici sur une base
     * inexistante. Il a deja ecrit son en-tete : le fichier fait plusieurs
     * centaines d'octets, porte un nom conforme, et la retention le
     * conserverait trente jours. Un exploitant listant le repertoire y verrait
     * une sauvegarde datee de la nuit.
     *
     * C'est le seul etat pire que l'absence de sauvegarde : il retire la
     * vigilance.
     */
    #[Test]
    public function un_dump_interrompu_ne_laisse_pas_de_fichier_trompeur(): void
    {
        config(['database.connections.mysql.database' => 'base_absente_pour_le_test']);

        $leve = false;
        try {
            (new SauvegardeBaseQuotidienneJob())->handle();
        } catch (RuntimeException) {
            $leve = true;
        }

        $this->assertTrue($leve, 'un dump interrompu doit lever.');
        $this->assertSame(
            [],
            $this->fichiers(),
            'un fichier incomplet reste sur le disque et passe pour une sauvegarde.',
        );
    }
}

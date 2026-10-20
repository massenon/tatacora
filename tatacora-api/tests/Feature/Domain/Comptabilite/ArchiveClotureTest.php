<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Comptabilite;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\ClotureExercice;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\ArchiveClotureService;
use App\Domain\Comptabilite\Services\ClotureExerciceService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Models\User;
use App\Pwa\Livewire\Comptabilite\Hub;
use App\Shared\Backup\Services\ReinitialisationDonneesTestService;
use App\Shared\Exploitation\Services\VerificationProductionService;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Symfony\Component\Process\Process;
use Tests\TestCase;

/**
 * L'ARCHIVE LÉGALE de clôture — lot 4 (décision du Product Owner du
 * 20/10/2026 : fichier des écritures et PDF des états de clôture, avec
 * empreinte d'intégrité). Ce qu'elle contient, que son empreinte la
 * protège, qu'elle ne se réécrit jamais, et que l'écran la délivre.
 */
final class ArchiveClotureTest extends TestCase
{
    use RefreshDatabase;

    private User $comptable;

    private ExerciceComptable $n;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake(ArchiveClotureService::DISQUE);
        $this->travelTo('2026-10-20 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->comptable = User::create([
            'login' => 'comptable.'.Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'comptable')->firstOrFail()->id,
            'statut' => 'actif',
        ]);
        $this->actingAs($this->comptable);
        $this->n = ExerciceComptable::query()->where('annee', 2026)->firstOrFail();

        $bar = (string) CentreCout::query()->where('libelle', 'Bar')->value('id');
        app(PasserEcritureService::class)->passerEtValider(['journal' => 'CAI', 'date' => '2026-03-10', 'libelle' => 'Ventes bar', 'lignes' => [
            ['compte' => '5711', 'debit' => '100000.00'],
            ['compte' => '7011', 'credit' => '100000.00', 'centre_id' => $bar],
        ]]);
    }

    private function cloturer(): ClotureExercice
    {
        $service = app(ClotureExerciceService::class);
        $service->demarrer($this->n, $this->comptable);

        return $service->cloturer($this->n->refresh(), $this->comptable);
    }

    #[Test]
    public function l_archive_porte_les_ecritures_la_balance_les_etats_et_leur_empreinte(): void
    {
        $cloture = app(ArchiveClotureService::class)->archiver($this->cloturer(), $this->comptable);
        $disque = Storage::disk(ArchiveClotureService::DISQUE);
        $dossier = 'archives/exercices/2026/'.$cloture->id;

        $this->assertSame($dossier, $cloture->archive_chemin);
        $manifeste = (string) $disque->get($dossier.'/manifeste.json');
        $this->assertSame(hash('sha256', $manifeste), $cloture->archive_empreinte);

        $lu = json_decode($manifeste, true);
        $this->assertSame(2026, $lu['exercice']);
        $this->assertSame('100000.00', $lu['cloture']['resultat']);
        foreach (['ecritures.csv', 'balance.csv', 'etats-cloture.pdf'] as $fichier) {
            $this->assertSame(hash('sha256', (string) $disque->get($dossier.'/'.$fichier)), $lu['fichiers'][$fichier]['sha256'], $fichier);
        }

        // Le fichier des écritures : BOM, en-tête, la vente, et la pièce de
        // clôture (journal CL) qui solde 7011.
        $ecritures = (string) $disque->get($dossier.'/ecritures.csv');
        $this->assertStringStartsWith("\xEF\xBB\xBFJournalCode;JournalLib;EcritureNum;EcritureDate;CompteNum", $ecritures);
        $this->assertStringContainsString(';20260310;7011;', $ecritures);
        $this->assertStringContainsString('0,00;100000,00;validee', $ecritures);
        $this->assertMatchesRegularExpression('/^CL;[^;]*;[^;]*;20261231;7011;.*;100000,00;0,00;validee/m', $ecritures);

        // La balance est celle d'AVANT le solde des comptes de gestion.
        $balance = (string) $disque->get($dossier.'/balance.csv');
        $this->assertStringContainsString('7011;', $balance);
        $this->assertStringNotContainsString("\n131;", $balance);

        $this->assertStringStartsWith('%PDF', (string) $disque->get($dossier.'/etats-cloture.pdf'));
        $this->assertTrue(app(ArchiveClotureService::class)->verifier($cloture));
    }

    #[Test]
    public function une_archive_alteree_est_detectee_et_n_est_plus_delivree(): void
    {
        $archives = app(ArchiveClotureService::class);
        $cloture = $archives->archiver($this->cloturer(), $this->comptable);

        Storage::disk(ArchiveClotureService::DISQUE)
            ->put($cloture->archive_chemin.'/ecritures.csv', 'JournalCode;falsifié');

        $this->assertFalse($archives->verifier($cloture));
        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage(__('comptabilite.archive_alteree'));
        $archives->zip($cloture);
    }

    #[Test]
    public function l_archive_ne_se_reecrit_jamais_et_une_re_cloture_a_la_sienne(): void
    {
        $archives = app(ArchiveClotureService::class);
        $premiere = $archives->archiver($this->cloturer(), $this->comptable);
        $empreinte = $premiere->archive_empreinte;

        $this->travel(5)->minutes();
        $this->assertSame($empreinte, $archives->archiver($premiere->refresh(), $this->comptable)->archive_empreinte);

        // Réouverture puis re-clôture : une NOUVELLE archive ; l'ancienne
        // reste, intacte.
        $service = app(ClotureExerciceService::class);
        $service->rouvrir($this->n->refresh(), $this->comptable, 'Régularisation oubliée en mars');
        $seconde = $archives->archiver($service->cloturer($this->n->refresh(), $this->comptable), $this->comptable);

        $this->assertNotSame($premiere->id, $seconde->id);
        $this->assertNotSame($premiere->archive_chemin, $seconde->archive_chemin);
        $this->assertTrue($archives->verifier($premiere->refresh()));
        $this->assertTrue($archives->verifier($seconde));

        // Une clôture rouverte SANS archive n'en reçoit plus.
        $service->rouvrir($this->n->refresh(), $this->comptable, 'Seconde régularisation de mars');
        $troisieme = $service->cloturer($this->n->refresh(), $this->comptable);
        $service->rouvrir($this->n->refresh(), $this->comptable, 'Troisième régularisation de mars');
        $this->expectException(RuntimeException::class);
        $archives->archiver($troisieme->refresh(), $this->comptable);
    }

    #[Test]
    public function l_ecran_cloture_archive_affiche_l_empreinte_et_telecharge_le_zip(): void
    {
        $hub = fn () => Livewire::withQueryParams(['exercice' => $this->n->id])->test(Hub::class, ['onglet' => 'clotures']);

        $hub()->call('demarrerCloture')->assertHasNoErrors();
        $hub()->call('cloturerExercice')->assertHasNoErrors();

        $cloture = app(ClotureExerciceService::class)->clotureActive($this->n->id);
        $this->assertNotNull($cloture?->archive_empreinte);

        $hub()->assertSee($cloture->archive_empreinte)
            ->call('telechargerArchive')
            ->assertHasNoErrors()
            ->assertFileDownloaded('archive_exercice_2026.zip');

        // Archive absente (génération échouée après la clôture) : l'écran
        // propose de la générer.
        $cloture->forceFill(['archive_chemin' => null, 'archive_empreinte' => null])->save();
        $hub()->assertSee(__('comptabilite_pwa.archive_absente'))
            ->call('genererArchive')->assertHasNoErrors();
        $this->assertNotNull($cloture->refresh()->archive_empreinte);
    }

    #[Test]
    public function la_verification_de_production_rougit_sur_une_archive_absente_ou_alteree(): void
    {
        $controle = fn (): array => collect(app(VerificationProductionService::class)->executer())
            ->firstWhere('controle', 'archives_cloture');

        $this->assertSame('ok', $controle()['issue']);

        $cloture = $this->cloturer();
        $this->assertSame('attention', $controle()['issue']);
        $this->assertStringContainsString('2026', $controle()['detail']);

        $cloture = app(ArchiveClotureService::class)->archiver($cloture, $this->comptable);
        $this->assertSame('ok', $controle()['issue']);

        Storage::disk(ArchiveClotureService::DISQUE)->put($cloture->archive_chemin.'/balance.csv', 'falsifié');
        $this->assertSame('echec', $controle()['issue']);
    }

    #[Test]
    public function la_reinitialisation_d_essais_rouvre_l_exercice_et_efface_ses_archives(): void
    {
        if ((new Process([config('backup.mysqldump', 'mysqldump'), '--version']))->run() !== 0) {
            $this->markTestSkipped('mysqldump introuvable.');
        }
        $deja = glob(storage_path('app/sauvegardes/tatacora-*.sql')) ?: [];
        $this->beforeApplicationDestroyed(static function () use ($deja): void {
            foreach (array_diff(glob(storage_path('app/sauvegardes/tatacora-*.sql')) ?: [], $deja) as $f) {
                @unlink($f);
            }
        });

        $cloture = app(ArchiveClotureService::class)->archiver($this->cloturer(), $this->comptable);
        $disque = Storage::disk(ArchiveClotureService::DISQUE);
        $this->assertTrue($disque->exists($cloture->archive_chemin.'/manifeste.json'));

        ParametreSysteme::updateOrCreate(['cle' => ReinitialisationDonneesTestService::CLE_BASCULE], ['valeur' => 'true']);
        $admin = User::create([
            'login' => 'administrateur.'.Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id,
            'statut' => 'actif',
        ]);
        app(ReinitialisationDonneesTestService::class)->executer($admin);

        $this->assertSame(0, ClotureExercice::count());
        $this->assertSame('ouvert', $this->n->refresh()->statut);
        $this->assertNull($this->n->date_cloture);
        $this->assertSame('ouvert', ExerciceComptable::query()->where('annee', 2027)->value('statut'));
        $this->assertFalse($disque->exists($cloture->archive_chemin.'/manifeste.json'));
    }
}

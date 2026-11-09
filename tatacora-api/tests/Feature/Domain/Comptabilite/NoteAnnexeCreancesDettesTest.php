<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Comptabilite;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\ReadModels\Note;
use App\Domain\Comptabilite\ReadModels\PosteBilan;
use App\Domain\Comptabilite\Services\BilanService;
use App\Domain\Comptabilite\Services\NotesAnnexesService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Domain\Comptabilite\Support\RubriquesSyscohada;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Note annexe 4, « État des créances et dettes » : ses dettes sont celles du
 * BILAN, dividendes à payer (465) compris (10/11/2026).
 *
 * Le « passif circulant » du Bilan est `DETTES_CIRCULANTES` + `DETTES_ASSOCIES`.
 * La note ne lisait que la première : un dividende décidé et non réglé figurait
 * au bilan et manquait à la note, qui restait en deçà du bilan de ce montant.
 *
 * Le balayage s'ancre sur les préfixes que le BILAN déclare pour son passif
 * circulant (pas sur une liste du test, pas sur celle de la note) : une rubrique
 * de dettes ajoutée demain au bilan sans l'être à la note fait rougir ici.
 */
final class NoteAnnexeCreancesDettesTest extends TestCase
{
    use RefreshDatabase;

    private ExerciceComptable $exercice;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-20 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->actingAs(User::create([
            'login' => 'comptable.' . Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'comptable')->firstOrFail()->id,
            'statut' => 'actif',
        ]));
        $this->exercice = ExerciceComptable::query()->where('annee', 2026)->firstOrFail();
    }

    /** Le compte IMPUTABLE le plus court sous un préfixe (le préfixe lui-même s'il est une feuille). */
    private function feuille(string $prefixe): string
    {
        $comptes = CompteComptable::query()
            ->where('numero_compte', 'like', $prefixe . '%')
            ->orderByRaw('LENGTH(numero_compte)')
            ->orderBy('numero_compte')
            ->pluck('numero_compte');

        foreach ($comptes as $numero) {
            $numero = (string) $numero;
            $estDivision = strlen($numero) < 4
                && $comptes->contains(static fn ($autre): bool => $autre !== $numero && str_starts_with((string) $autre, $numero));

            if (! $estDivision) {
                return $numero;
            }
        }

        $this->fail("aucun compte imputable sous le préfixe {$prefixe}");
    }

    private function crediter(string $compte, string $montant): void
    {
        $structure = (string) CentreCout::query()->where('libelle', 'Structure')->value('id');
        app(PasserEcritureService::class)->passerEtValider([
            'journal' => 'OD', 'date' => '2026-05-10', 'libelle' => 'Dette ' . $compte,
            'lignes' => [
                ['compte' => '5711', 'debit' => $montant, 'credit' => '0.00', 'centre_id' => $structure],
                ['compte' => $compte, 'debit' => '0.00', 'credit' => $montant, 'centre_id' => $structure],
            ],
        ]);
    }

    private function note4(): Note
    {
        $notes = app(NotesAnnexesService::class)->genererPourExercice($this->exercice, ['validee'], 'validee');

        foreach ($notes->notes as $note) {
            if ($note->numero === 4) {
                return $note;
            }
        }

        $this->fail('note 4 absente');
    }

    private function passifCirculantDuBilan(): PosteBilan
    {
        $bilan = app(BilanService::class)->genererPourExercice($this->exercice->id, ['validee'], 'validee');

        foreach ($bilan->passif as $poste) {
            if ($poste->code === 'passif_circulant') {
                return $poste;
            }
        }

        $this->fail('« passif circulant » absent du bilan');
    }

    /** @param list<string> $prefixes */
    private function relevant(string $numero, array $prefixes): bool
    {
        return RubriquesSyscohada::releveDe($numero, $prefixes);
    }

    #[Test]
    public function les_dividendes_a_payer_465_figurent_a_la_note_4_avec_le_libelle_du_plan(): void
    {
        $this->crediter('465', '40000.00');

        $postes = array_values(array_filter(
            $this->note4()->postes,
            static fn (array $p): bool => $p['prefixes'] === ['465'],
        ));

        $this->assertCount(1, $postes, 'le 465 doit être une ligne de la note 4');
        $this->assertSame('ASSOCIES(1), DIVIDENDES A PAYER (465)', $postes[0]['libelle']);
        $this->assertSame('40000.00', $postes[0]['montant']);
    }

    #[Test]
    public function toute_rubrique_de_dettes_du_bilan_apparait_dans_la_note_4_et_le_total_des_dettes_egale_celui_du_bilan(): void
    {
        $passif = $this->passifCirculantDuBilan();
        $prefixes = $passif->prefixes;

        // Plancher : le balayage ne doit jamais être vide, et le 465 en fait partie.
        $this->assertGreaterThanOrEqual(9, count($prefixes));
        $this->assertContains('465', $prefixes);

        $attendus = [];
        foreach (array_values($prefixes) as $i => $prefixe) {
            $compte = $this->feuille($prefixe);
            $this->crediter($compte, number_format(1000 * ($i + 1) + 7, 2, '.', ''));
            $attendus[$prefixe] = $compte;
        }

        $dettesDeLaNote = array_values(array_filter(
            $this->note4()->postes,
            fn (array $p): bool => $this->relevant($p['prefixes'][0], $prefixes),
        ));
        $comptesDeLaNote = array_map(static fn (array $p): string => $p['prefixes'][0], $dettesDeLaNote);

        foreach ($attendus as $prefixe => $compte) {
            $this->assertContains($compte, $comptesDeLaNote, "la rubrique de dettes du bilan « {$prefixe} » (compte {$compte}) manque à la note 4");
        }

        $total = '0.00';
        foreach ($dettesDeLaNote as $poste) {
            $total = bcadd($total, $poste['montant'], 2);
        }

        $this->assertSame($this->passifCirculantDuBilan()->net, $total, 'total des dettes de la note 4 ≠ passif circulant du bilan');
        $this->assertNotSame('0.00', $total);
    }

    #[Test]
    public function la_note_4_ne_compte_le_465_qu_une_fois_et_son_total_egale_le_passif_circulant_du_bilan(): void
    {
        // Avis du 10/11/2026 : le 465 est au passif circulant du bilan (« autres
        // dettes », « dont dividendes a payer »). La note le porte une seule fois,
        // sans le doubler par un second balayage (DETTES_CIRCULANTES puis
        // DETTES_ASSOCIES), et le total des dettes de la note est celui du bilan.
        $this->crediter('465', '40000.00');
        $this->crediter('4011', '1000.00');

        $lignes465 = array_values(array_filter(
            $this->note4()->postes,
            static fn (array $p): bool => $p['prefixes'] === ['465'],
        ));
        $this->assertCount(1, $lignes465, 'le 465 ne figure qu\'une fois dans la note 4');

        $total = '0.00';
        foreach ($this->note4()->postes as $poste) {
            if (RubriquesSyscohada::releveDe($poste['prefixes'][0], $this->passifCirculantDuBilan()->prefixes)) {
                $total = bcadd($total, $poste['montant'], 2);
            }
        }

        $this->assertSame('41000.00', $total);
        $this->assertSame('41000.00', $this->passifCirculantDuBilan()->net);

        $bilan = app(BilanService::class)->genererPourExercice($this->exercice->id, ['validee'], 'validee');
        $this->assertSame('40000.00', $bilan->dividendesAPayer);
    }
}

<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Comptabilite;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\BilanService;
use App\Domain\Comptabilite\Services\ClotureExerciceService;
use App\Domain\Comptabilite\Services\CompteResultatService;
use App\Domain\Comptabilite\Services\EtatClotureService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
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
 * Le résultat d'un exercice = produits − charges (classes 6, 7, 8) de CET
 * exercice, jamais les à-nouveaux : le résultat de N-1, déjà reporté en 131/139
 * (journal AN ou à-nouveaux provisoires), reste au bilan comme REPORT mais ne se
 * recompte ni dans le résultat de N ni dans « résultat à reporter » de l'écran
 * Clôtures.
 *
 * Défaut constaté (09/11/2026) : exercice N-1 clôturé (+80 000), N à −190 559 ;
 * l'écran Clôtures affichait −110 559 — `Bilan::resultatExercice` valait
 * « 131/139 des à-nouveaux + résultat net de N », et l'état de clôture le
 * reprenait comme « résultat à reporter ».
 */
final class ResultatExerciceApresClotureTest extends TestCase
{
    use RefreshDatabase;

    private const RESULTAT_N1 = '80000.00';

    private const RESULTAT_N = '-190559.00';

    private User $comptable;

    private ExerciceComptable $n1;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-20 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->comptable = User::create([
            'login' => 'comptable.' . Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'comptable')->firstOrFail()->id,
            'statut' => 'actif',
        ]);
        $this->actingAs($this->comptable);
        $this->n1 = ExerciceComptable::query()->where('annee', 2026)->firstOrFail();
    }

    private function centre(string $libelle): string
    {
        return (string) CentreCout::query()->where('libelle', $libelle)->value('id');
    }

    /** Une vente et une charge, comptées au résultat de l'exercice de la date. */
    private function exploiter(string $annee, string $vente, string $charge): void
    {
        $passer = app(PasserEcritureService::class);
        $passer->passerEtValider(['journal' => 'CAI', 'date' => "{$annee}-03-10", 'libelle' => 'Ventes bar', 'lignes' => [
            ['compte' => '5711', 'debit' => $vente],
            ['compte' => '7011', 'credit' => $vente, 'centre_id' => $this->centre('Bar')],
        ]]);
        $passer->passerEtValider(['journal' => 'CAI', 'date' => "{$annee}-03-11", 'libelle' => 'Achats', 'lignes' => [
            ['compte' => '6011', 'debit' => $charge, 'centre_id' => $this->centre('Restaurant')],
            ['compte' => '5711', 'credit' => $charge],
        ]]);
    }

    private function clotures(): ClotureExerciceService
    {
        return app(ClotureExerciceService::class);
    }

    /** N-1 (2026) clôturé à +80 000, puis N (2027) à −190 559. */
    private function nMoinsUnClotureEtNExploite(): ExerciceComptable
    {
        $this->exploiter('2026', '110000.00', '30000.00');
        $this->clotures()->demarrer($this->n1, $this->comptable);
        $this->clotures()->cloturer($this->n1->refresh(), $this->comptable);
        $this->assertSame(self::RESULTAT_N1, (string) $this->clotures()->clotureActive($this->n1->id)->resultat);

        $this->travelTo('2027-03-20 10:00:00');
        $this->exploiter('2027', '40000.00', '230559.00');

        return ExerciceComptable::query()->where('annee', 2027)->firstOrFail();
    }

    private function resultatNet(ExerciceComptable $exercice): string
    {
        return app(CompteResultatService::class)->genererPourExercice($exercice->id, ['validee'])->resultatNet;
    }

    private function etat(ExerciceComptable $exercice): \App\Domain\Comptabilite\ReadModels\EtatCloture
    {
        return app(EtatClotureService::class)->genererPourExercice($exercice->refresh(), ['validee', 'brouillon']);
    }

    #[Test]
    public function le_resultat_a_reporter_est_le_resultat_net_de_n_avec_n_moins_un_cloture(): void
    {
        $n = $this->nMoinsUnClotureEtNExploite();

        $this->assertSame(self::RESULTAT_N, $this->resultatNet($n));

        $etat = $this->etat($n);
        $this->assertSame(self::RESULTAT_N, $etat->resultatAReporter, 'le résultat de N-1 (131 des à-nouveaux) ne se recompte pas');
        $this->assertSame('139', $etat->compteDeDestination);

        $calcul = collect($etat->etapes)->firstWhere('libelle', 'Calcul du résultat net');
        $this->assertSame(self::RESULTAT_N, $calcul->valeur);
    }

    #[Test]
    public function le_bilan_de_n_reste_equilibre_avec_le_resultat_de_n_moins_un_en_a_nouveaux(): void
    {
        $n = $this->nMoinsUnClotureEtNExploite();

        $bilan = app(BilanService::class)->genererPourExercice($n->id, ['validee']);

        $this->assertTrue($bilan->equilibre, 'écart ' . $bilan->ecart);
        $this->assertSame('0.00', $bilan->ecart);
        $this->assertSame(self::RESULTAT_N, $bilan->resultatExercice, 'le résultat de N seul');

        // Le report reste au passif : capitaux propres = 80 000 (N-1) − 190 559 (N).
        $capitaux = collect($bilan->passif)->firstWhere('code', 'capitaux_propres');
        $this->assertSame('-110559.00', $capitaux->net);
    }

    #[Test]
    public function la_cloture_de_n_puis_les_pieces_cl_et_an_de_n_sont_coherentes(): void
    {
        $n = $this->nMoinsUnClotureEtNExploite();

        $this->clotures()->demarrer($n, $this->comptable);
        $avant = $this->etat($n);
        $this->assertSame(self::RESULTAT_N, $avant->resultatAReporter);

        $cloture = $this->clotures()->cloturer($n->refresh(), $this->comptable);
        $this->assertSame(self::RESULTAT_N, (string) $cloture->resultat);

        // La pièce CL ne solde QUE les classes de gestion de N : 139 débité de 190 559.
        $cl = EcritureComptable::query()->where('numero_piece', $cloture->piece_cloture)->with('compte')->get();
        $cl139 = $cl->filter(fn ($e): bool => $e->compte->numero_compte === '139');
        $this->assertEquals(190559, (float) $cl139->sum('debit'));
        $this->assertCount(0, $cl->filter(fn ($e): bool => $e->compte->numero_compte === '131'), 'aucun 131 dans la pièce CL de N');

        // L'étape 4 de la liste de contrôle : 131/139 = résultat net calculé.
        $etapeControle = collect($this->etat($n)->etapes)->firstWhere('libelle', 'Compte 131/139 = résultat net calculé');
        $this->assertSame('conforme', $etapeControle->etat);

        // La pièce AN de 2028 : 131 = résultat de 2026 (80 000, UNE fois), 139 =
        // résultat de 2027 (190 559, UNE fois) — jamais N + N-1 deux fois.
        $an = EcritureComptable::query()->where('numero_piece', $cloture->piece_a_nouveaux)->with('compte')->get();
        $lignes = fn (string $numero) => $an->filter(fn ($e): bool => $e->compte->numero_compte === $numero);
        $this->assertCount(1, $lignes('131'));
        $this->assertCount(1, $lignes('139'));
        $this->assertEquals(80000, (float) $lignes('131')->first()->credit);
        $this->assertEquals(190559, (float) $lignes('139')->first()->debit);

        // N+1 (2028) : aucun résultat de gestion, donc rien à reporter ; bilan équilibré.
        $n2 = ExerciceComptable::query()->where('annee', 2028)->firstOrFail();
        $this->assertSame('0.00', $this->resultatNet($n2));
        $this->assertSame('0.00', $this->etat($n2)->resultatAReporter);
        $bilan2 = app(BilanService::class)->genererPourExercice($n2->id, ['validee']);
        $this->assertTrue($bilan2->equilibre);
        $this->assertSame('0.00', $bilan2->resultatExercice);
        $this->assertSame('-110559.00', collect($bilan2->passif)->firstWhere('code', 'capitaux_propres')->net);
    }

    #[Test]
    public function sans_exercice_precedent_cloture_le_resultat_a_reporter_est_inchange(): void
    {
        // Aucun exercice précédent : exercice inaugural.
        $this->exploiter('2026', '110000.00', '30000.00');
        $etat = $this->etat($this->n1);
        $this->assertSame('80000.00', $etat->resultatAReporter);
        $this->assertSame('131', $etat->compteDeDestination);
        $this->assertSame('80000.00', $this->resultatNet($this->n1));
        $bilan = app(BilanService::class)->genererPourExercice($this->n1->id, ['validee']);
        $this->assertTrue($bilan->equilibre);
        $this->assertSame('80000.00', $bilan->resultatExercice);
    }

    #[Test]
    public function avec_n_moins_un_non_cloture_les_a_nouveaux_provisoires_ne_se_recomptent_pas_non_plus(): void
    {
        $this->exploiter('2026', '110000.00', '30000.00');
        $this->clotures()->demarrer($this->n1, $this->comptable);
        $n = ExerciceComptable::query()->where('annee', 2027)->firstOrFail();
        $this->travelTo('2027-03-20 10:00:00');
        $this->exploiter('2027', '40000.00', '230559.00');

        $etat = $this->etat($n);
        $this->assertSame(self::RESULTAT_N, $etat->resultatAReporter);
        $this->assertTrue(app(BilanService::class)->genererPourExercice($n->id, ['validee'])->equilibre);
    }
}

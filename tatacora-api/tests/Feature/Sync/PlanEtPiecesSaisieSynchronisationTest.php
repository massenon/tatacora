<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Models\User;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * D246 rouvert (28/10/2026) : un COMPTE créé et une PIÈCE saisie à la main sur un
 * poste sont rejoués par les services du web (`PlanComptableService`,
 * `PasserEcritureService`), aux mêmes règles et aux mêmes phrases.
 */
final class PlanEtPiecesSaisieSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $comptable;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-28 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->comptable = $this->creerUtilisateur('comptable');
    }

    /** @return array<string, mixed> */
    private function compte(string $id, string $numero = '6099', string $libelle = 'Charges diverses', string $nature = 'charge'): array
    {
        return $this->creation('plan_comptable', $id, ['numero_compte' => $numero, 'libelle' => $libelle, 'nature' => $nature]);
    }

    /** @param list<array<string, mixed>> $lignes */
    private function piece(string $id, array $lignes, array $surcharge = []): array
    {
        return $this->creation('pieces_saisie', $id, [...[
            'journal' => 'OD', 'date' => '2026-10-20', 'libelle' => 'Régularisation', 'statut' => 'validee', 'lignes' => $lignes,
        ], ...$surcharge]);
    }

    private function bar(): string
    {
        return (string) CentreCout::query()->where('libelle', 'Bar')->value('id');
    }

    /** @return list<array<string, mixed>> */
    private function equilibre(int $centimes = 150000): array
    {
        return [
            ['compte' => '5711', 'debit' => $centimes, 'credit' => 0],
            ['compte' => '7011', 'debit' => 0, 'credit' => $centimes, 'centre' => 'Bar'],
        ];
    }

    #[Test]
    public function un_compte_cree_sur_le_poste_rejoint_le_plan_sous_son_identifiant_et_se_rejoue_sans_doublon(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->compte($id)], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.numero', '6099');

        $compte = CompteComptable::query()->findOrFail($id);
        $this->assertSame('6', $compte->classe);
        $this->assertSame('Charges diverses', $compte->libelle);

        // Rejeu (nouvelle opération, même document) : rien de plus.
        $this->pousser([$this->compte($id)], $this->comptable)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame(1, CompteComptable::query()->where('numero_compte', '6099')->count());
    }

    #[Test]
    public function un_numero_deja_pris_fusionne_si_c_est_le_meme_compte_et_se_refuse_lisiblement_sinon(): void
    {
        $this->pousser([$this->compte($this->uuid())], $this->comptable);
        $existant = (string) CompteComptable::query()->where('numero_compte', '6099')->value('id');

        $this->pousser([$this->compte($this->uuid(), '6099', '  charges DIVERSES ')], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.fusionne_avec', $existant);

        $this->pousser([$this->compte($this->uuid(), '6099', 'Autre chose')], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('comptabilite.compte_deja_existant', ['numero' => '6099']));
        $this->assertSame(1, CompteComptable::query()->where('numero_compte', '6099')->count());

        // Même libellé, autre nature : ce n'est pas le même compte, il ne se fond pas.
        $this->pousser([$this->compte($this->uuid(), '6099', 'Charges diverses', 'produit')], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete');
    }

    #[Test]
    public function les_refus_d_un_compte_sont_les_phrases_du_service(): void
    {
        $this->pousser([$this->compte($this->uuid(), '60999')], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('comptabilite.compte_numero_invalide', ['numero' => '60999']));
        $this->pousser([$this->compte($this->uuid(), '6098', '   ')], $this->comptable)
            ->assertJsonPath('resultats.0.motif', __('comptabilite.compte_libelle_requis'));
        $this->pousser([$this->compte($this->uuid(), '6097', 'X', 'magie')], $this->comptable)
            ->assertJsonPath('resultats.0.motif', __('comptabilite.compte_nature_invalide', ['nature' => 'magie']));
    }

    #[Test]
    public function une_piece_validee_est_rejouee_le_serveur_passe_la_sienne_avec_l_identifiant_d_origine(): void
    {
        $id = $this->uuid();
        $reponse = $this->pousser([$this->piece($id, $this->equilibre())], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $lignes = EcritureComptable::query()->where('piece_origine_id', $id)->get();
        $this->assertCount(2, $lignes);
        $this->assertSame('validee', $lignes->first()->statut);
        $this->assertSame($lignes->first()->numero_piece, $reponse->json('resultats.0.numero_piece'));
        $this->assertSame('1500.00', $lignes->firstWhere('compte_id', CompteComptable::query()->where('numero_compte', '5711')->value('id'))->debit);

        // Rejeu : même pièce, aucun second numéro.
        $this->pousser([$this->piece($id, $this->equilibre())], $this->comptable)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame(2, EcritureComptable::query()->where('piece_origine_id', $id)->count());
        $this->assertSame(1, DB::table('pieces_saisie')->where('id', $id)->count());
    }

    #[Test]
    public function un_brouillon_reste_brouillon_et_n_a_pas_de_piece_validee(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->piece($id, $this->equilibre(), ['statut' => 'brouillon'])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame(['brouillon'], EcritureComptable::query()->where('piece_origine_id', $id)->pluck('statut')->unique()->all());
    }

    #[Test]
    public function les_controles_de_saisie_sont_ceux_du_web_et_rien_n_est_ecrit_sur_refus(): void
    {
        $cas = [
            'desequilibre' => [$this->piece($this->uuid(), [
                ['compte' => '5711', 'debit' => 150000, 'credit' => 0],
                ['compte' => '7011', 'debit' => 0, 'credit' => 100000, 'centre' => 'Bar'],
            ])],
            'journal reserve' => [$this->piece($this->uuid(), $this->equilibre(), ['journal' => 'CL'])],
            'compte inconnu' => [$this->piece($this->uuid(), [
                ['compte' => '5711', 'debit' => 100, 'credit' => 0],
                ['compte' => '9999', 'debit' => 0, 'credit' => 100],
            ])],
            'debit et credit' => [$this->piece($this->uuid(), [
                ['compte' => '5711', 'debit' => 100, 'credit' => 100],
                ['compte' => '7011', 'debit' => 0, 'credit' => 0, 'centre' => 'Bar'],
            ])],
            'une seule ligne' => [$this->piece($this->uuid(), [['compte' => '5711', 'debit' => 100, 'credit' => 0]])],
            'exercice absent' => [$this->piece($this->uuid(), $this->equilibre(), ['date' => '2020-01-05'])],
            'centre absent' => [$this->piece($this->uuid(), [
                ['compte' => '5711', 'debit' => 100, 'credit' => 0],
                ['compte' => '7011', 'debit' => 0, 'credit' => 100],
            ])],
        ];

        foreach ($cas as $nom => [$operation]) {
            $this->pousser([$operation], $this->comptable)
                ->assertJsonPath('resultats.0.statut', 'rejete');
            $this->assertSame(0, EcritureComptable::query()->count(), $nom);
        }

        $this->pousser([$cas['desequilibre'][0]], $this->comptable)
            ->assertJsonPath('resultats.0.motif', __('comptabilite.piece_desequilibree', ['debit' => '1500.00', 'credit' => '1000.00', 'ecart' => '500.00']));
    }

    #[Test]
    public function un_compte_cree_avant_la_piece_qui_le_cite_est_imputable(): void
    {
        $compte = $this->uuid();
        $piece = $this->uuid();
        $this->pousser([
            $this->compte($compte, '6099'),
            $this->piece($piece, [
                ['compte' => '6099', 'debit' => 5000, 'credit' => 0, 'centre' => 'Bar'],
                ['compte' => '5711', 'debit' => 0, 'credit' => 5000],
            ]),
        ], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.1.statut', 'synchronise');
    }
}

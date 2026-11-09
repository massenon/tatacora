<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Comptabilite\Models\AffectationResultat;
use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\AffectationResultatService;
use App\Domain\Comptabilite\Services\ClotureExerciceService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Domain\Comptabilite\Support\FormeJuridique;
use App\Models\User;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Sync\Services\CatalogueDescendantService;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Les AFFECTATIONS DU RÉSULTAT descendent aux postes (09/11/2026, demande du PO :
 * « une affectation passée au web DOIT apparaître sur le poste »).
 *
 * Seconde moitié de la règle « une table répliquée a deux moitiés : qui l'écrit,
 * qui la descend » (PA-127) : le serveur l'écrit (`AffectationResultatService`),
 * le flux de `GET /api/v1/referentiels` la descend — active ET contre-passée (le
 * poste doit apprendre qu'elle peut être refaite), avec l'ANNÉE de l'exercice, le
 * LOGIN de l'auteur et l'identifiant d'origine de la pièce du poste, sous le droit
 * de lecture de la comptabilité (M10).
 */
final class AffectationsDescendantesTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $comptable;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-26 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
        // Ce fichier éprouve une SOCIÉTÉ (réserve légale, dividendes) ; l'entreprise
        // individuelle, forme par défaut du Gîte, a ses tests dans `AffectationFormeJuridiqueTest`.
        ParametreSysteme::query()->updateOrCreate(['cle' => FormeJuridique::CLE], ['valeur' => 'sarl']);
        $this->comptable = $this->creerUtilisateur('comptable');
        $this->actingAs($this->comptable);

        // Vente 100 000, charge 30 000 : bénéfice 70 000, 2026 clôturé.
        $passer = app(PasserEcritureService::class);
        $bar = (string) CentreCout::query()->where('libelle', 'Bar')->value('id');
        $restaurant = (string) CentreCout::query()->where('libelle', 'Restaurant')->value('id');
        $passer->passerEtValider(['journal' => 'CAI', 'date' => '2026-03-10', 'libelle' => 'Ventes bar', 'lignes' => [
            ['compte' => '5711', 'debit' => '100000.00'],
            ['compte' => '7011', 'credit' => '100000.00', 'centre_id' => $bar],
        ]]);
        $passer->passerEtValider(['journal' => 'CAI', 'date' => '2026-03-11', 'libelle' => 'Marché', 'lignes' => [
            ['compte' => '6011', 'debit' => '30000.00', 'centre_id' => $restaurant],
            ['compte' => '5711', 'credit' => '30000.00'],
        ]]);
        $exercice = $this->exercice();
        $clotures = app(ClotureExerciceService::class);
        $clotures->demarrer($exercice, $this->comptable);
        $clotures->cloturer($exercice->refresh(), $this->comptable);
    }

    private function exercice(): ExerciceComptable
    {
        return ExerciceComptable::query()->where('annee', 2026)->firstOrFail();
    }

    /** Une affectation passée AU WEB : le service, sans pièce de poste. */
    private function affecterAuWeb(): AffectationResultat
    {
        return app(AffectationResultatService::class)->affecter(
            $this->exercice(),
            ['reserve_legale' => '7000.00', 'autres_reserves' => '0', 'dividendes' => '10000.00', 'report_a_nouveau' => '53000.00', 'imputation_report_crediteur' => '0'],
            '2027-04-30',
            $this->comptable,
        );
    }

    /**
     * Le flux complet d'un poste neuf, ou depuis [$curseur] ; rend les éléments de la
     * table et le dernier curseur.
     *
     * @return array{0: list<array<string, mixed>>, 1: string}
     */
    private function flux(User $utilisateur, ?string $curseur = null): array
    {
        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        Sanctum::actingAs($utilisateur);
        $elements = [];

        do {
            $reponse = $this->getJson('/api/v1/referentiels?' . http_build_query(array_filter([
                'poste_id' => 'poste-1', 'depuis' => $curseur, 'limite' => 5,
            ], static fn ($v): bool => $v !== null)))->assertOk();
            $elements = [...$elements, ...$reponse->json('data.elements')];
            $curseur = $reponse->json('meta.curseur');
        } while (! $reponse->json('meta.complet'));

        return [
            array_values(array_filter($elements, static fn (array $e): bool => $e['table'] === 'affectations_resultat')),
            (string) $curseur,
        ];
    }

    #[Test]
    public function une_affectation_passee_au_web_est_dans_le_flux_avec_sa_ventilation_son_auteur_et_l_annee(): void
    {
        $affectation = $this->affecterAuWeb();

        [$elements] = $this->flux($this->comptable);

        $this->assertCount(1, $elements);
        $e = $elements[0];
        $this->assertSame($affectation->id, $e['id']);
        $this->assertTrue($e['actif']);
        $d = $e['donnees'];
        $this->assertSame(2026, $d['annee'], 'l\'exercice est rendu en ANNÉE : le poste a ses propres identifiants');
        $this->assertArrayNotHasKey('exercice_id', $d);
        $this->assertSame('70000.00', $d['resultat']);
        $this->assertSame('2027-04-30', substr((string) $d['date_approbation'], 0, 10));
        $this->assertSame('7000.00', $d['reserve_legale']);
        $this->assertSame('0.00', $d['autres_reserves']);
        $this->assertSame('10000.00', $d['dividendes']);
        $this->assertSame('53000.00', $d['report_a_nouveau_crediteur']);
        $this->assertSame('0.00', $d['report_a_nouveau_debiteur']);
        $this->assertSame($affectation->piece_affectation, $d['piece_affectation']);
        $this->assertNull($d['piece_origine_id'], 'passée au web : aucune pièce de poste');
        $this->assertNotNull($d['affectee_le']);
        $this->assertNull($d['contrepassee_le']);
        $this->assertSame($this->comptable->login, $d['par'], 'l\'auteur descend en LOGIN, jamais en identifiant');
        $this->assertNotContains($this->comptable->id, array_map('strval', $d));
    }

    #[Test]
    public function une_contrepassation_change_le_statut_et_la_ligne_redescend_depuis_le_curseur(): void
    {
        $affectation = $this->affecterAuWeb();
        [, $curseur] = $this->flux($this->comptable);

        // Rien de nouveau : le même curseur ne rend plus rien de cette table.
        [$rien] = $this->flux($this->comptable, $curseur);
        $this->assertSame([], $rien);

        $this->travel(5)->minutes();
        $this->travelTo('2027-05-10 10:00:00');
        app(AffectationResultatService::class)->contrepasser($this->exercice(), $this->comptable, 'Reprise de la ventilation');

        [$apres] = $this->flux($this->comptable, $curseur);
        $this->assertCount(1, $apres);
        $this->assertSame($affectation->id, $apres[0]['id']);
        $this->assertNotNull($apres[0]['donnees']['contrepassee_le'], 'une contre-passée descend, datée : le poste peut refaire');

        // Un poste neuf reçoit la même ligne, contre-passée : l'historique ne s'efface pas.
        [$neuf] = $this->flux($this->comptable);
        $this->assertCount(1, $neuf);
        $this->assertNotNull($neuf[0]['donnees']['contrepassee_le']);

        // Refaite : DEUX lignes, l'ancienne contre-passée et la nouvelle active.
        $this->travel(5)->minutes();
        $nouvelle = $this->affecterAuWeb();
        [$deux] = $this->flux($this->comptable);
        $this->assertCount(2, $deux);
        $parId = collect($deux)->keyBy('id');
        $this->assertNotNull($parId[$affectation->id]['donnees']['contrepassee_le']);
        $this->assertNull($parId[$nouvelle->id]['donnees']['contrepassee_le']);
    }

    #[Test]
    public function une_affectation_du_poste_porte_l_identifiant_de_sa_piece_d_origine(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->creation('pieces_saisie', $id, [
            'journal' => 'OD',
            'date' => '2027-04-30',
            'libelle' => 'Affectation du résultat de l’exercice 2026',
            'statut' => 'validee',
            'lignes' => [
                ['compte' => '131', 'debit' => 7000000, 'credit' => 0, 'centre' => 'Structure'],
                ['compte' => '111', 'debit' => 0, 'credit' => 700000, 'centre' => 'Structure'],
                ['compte' => '121', 'debit' => 0, 'credit' => 6300000, 'centre' => 'Structure'],
            ],
            'affectation' => ['annee' => 2026, 'ventilation' => ['reserve_legale' => 700000, 'report_a_nouveau' => 6300000]],
        ])], $this->comptable)->assertJsonPath('resultats.0.statut', 'synchronise');

        [$elements] = $this->flux($this->comptable);

        $this->assertCount(1, $elements);
        $this->assertSame($id, $elements[0]['donnees']['piece_origine_id'], 'le poste reconnaît SA pièce : jamais deux affichages');
        $this->assertSame('63000.00', $elements[0]['donnees']['report_a_nouveau_crediteur']);
        $this->assertSame('7000.00', $elements[0]['donnees']['reserve_legale']);
    }

    #[Test]
    public function la_lecture_respecte_le_droit_sur_la_comptabilite(): void
    {
        $this->affecterAuWeb();

        // Un compte qui ne lit pas M10 ne reçoit rien, et le service le dit (`non_lisibles`).
        $guide = $this->creerUtilisateur('guide');
        [$rien] = $this->flux($guide);
        $this->assertSame([], $rien);
        $service = app(CatalogueDescendantService::class);
        $this->assertContains('affectations_resultat', $service->page($guide, 'poste-1', null, 500)['non_lisibles']);

        // Le comptable (L ou C sur M10) la reçoit, sans en être listé non lisible.
        [$lu] = $this->flux($this->comptable);
        $this->assertCount(1, $lu);
        $this->assertNotContains('affectations_resultat', $service->page($this->comptable, 'poste-1', null, 500)['non_lisibles']);
    }

    #[Test]
    public function la_table_est_dans_la_liste_blanche_apres_les_ecritures_et_lue_sous_m10(): void
    {
        $tables = array_keys(CatalogueDescendantService::COLONNES);
        $this->assertContains('affectations_resultat', $tables);
        $this->assertGreaterThan(
            array_search('ecritures_comptables', $tables, true),
            array_search('affectations_resultat', $tables, true),
            'après les exercices et les écritures qu\'elle cite',
        );
        $this->assertSame('M10', CatalogueDescendantService::MODULES_HORS_REGISTRE['affectations_resultat']);
        $this->assertSame('affectee_par', CatalogueDescendantService::AUTEURS['affectations_resultat']);
        // Jamais une colonne d'audit ni un identifiant de compte dans les colonnes descendues.
        foreach (['affectee_par', 'contrepassee_par', 'motif', 'motif_contrepassation', 'cloture_id'] as $interdite) {
            $this->assertNotContains($interdite, CatalogueDescendantService::COLONNES['affectations_resultat']);
        }
        $this->assertSame([], array_diff(
            CatalogueDescendantService::COLONNES['affectations_resultat'],
            Schema::getColumnListing('affectations_resultat'),
        ), 'toute colonne descendue existe');
    }
}

<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Comptabilite\Models\AffectationResultat;
use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\DemandeClotureExercice;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\ClotureExerciceService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Domain\Comptabilite\Support\FormeJuridique;
use App\Models\User;
use App\Shared\Parametres\Models\ParametreSysteme;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * L'AFFECTATION DU RÉSULTAT saisie sur un poste (09/11/2026).
 *
 * Le poste l'envoie comme une PIÈCE SAISIE À LA MAIN (journal OD, validée, date
 * dans N) qui porte en plus sa ventilation ; le serveur la passe par
 * `AffectationResultatService` — exercice clôturé, une seule affectation active,
 * somme exacte, comptable seul — avec SES phrases. La contre-passation part
 * comme une demande `annuler_affectation`.
 */
final class AffectationResultatSynchronisationTest extends TestCase
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
    }

    private function cloturer(): void
    {
        $exercice = $this->exercice();
        $service = app(ClotureExerciceService::class);
        $service->demarrer($exercice, $this->comptable);
        $service->cloturer($exercice->refresh(), $this->comptable);
    }

    private function exercice(int $annee = 2026): ExerciceComptable
    {
        return ExerciceComptable::query()->where('annee', $annee)->firstOrFail();
    }

    /**
     * La pièce telle que le poste l'enfile : lignes en centimes, centre par son
     * libellé, ventilation en centimes.
     *
     * @param  array<string, int>  $ventilation
     * @return array<string, mixed>
     */
    private function piece(string $id, array $ventilation = ['reserve_legale' => 700000, 'report_a_nouveau' => 6300000], ?array $lignes = null, string $date = '2027-04-30'): array
    {
        $lignes ??= [
            ['compte' => '131', 'debit' => 7000000, 'credit' => 0, 'centre' => 'Structure'],
            ['compte' => '111', 'debit' => 0, 'credit' => 700000, 'centre' => 'Structure'],
            ['compte' => '121', 'debit' => 0, 'credit' => 6300000, 'centre' => 'Structure'],
        ];

        return $this->creation('pieces_saisie', $id, [
            'journal' => 'OD',
            'date' => $date,
            'libelle' => 'Affectation du résultat de l’exercice 2026',
            'statut' => 'validee',
            'lignes' => $lignes,
            'affectation' => ['annee' => 2026, 'ventilation' => $ventilation],
        ]);
    }

    /** @return array<string, mixed> */
    private function demande(string $action, array $surcharge = []): array
    {
        return $this->creation('demandes_cloture_exercice', $this->uuid(), [...['annee' => 2026, 'action' => $action], ...$surcharge]);
    }

    #[Test]
    public function une_affectation_du_poste_est_passee_par_le_service_et_se_rejoue_sans_doublon(): void
    {
        $this->cloturer();
        $id = $this->uuid();

        $reponse = $this->pousser([$this->piece($id)], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.statut_piece', 'validee');

        $affectation = AffectationResultat::query()->firstOrFail();
        $this->assertSame($id, $affectation->piece_origine_id);
        $this->assertSame($affectation->piece_affectation, $reponse->json('resultats.0.numero_piece'));
        $this->assertSame('70000.00', (string) $affectation->resultat);
        $this->assertSame('7000.00', (string) $affectation->reserve_legale);
        $this->assertSame('63000.00', (string) $affectation->report_a_nouveau_crediteur);
        $this->assertSame(
            ['2027-04-30'],
            EcritureComptable::query()->where('numero_piece', $affectation->piece_affectation)->get()->map(fn ($e) => $e->date_ecriture->toDateString())->unique()->values()->all(),
        );
        // Le serveur a marqué la provenance de chaque ligne (reconnue au miroir du poste).
        $this->assertSame(3, EcritureComptable::query()->where('piece_origine_id', $id)->count());

        // Rejeu : même identifiant, rien de nouveau.
        $this->pousser([$this->piece($id)], $this->comptable)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame(1, AffectationResultat::query()->count());
        $this->assertSame(3, EcritureComptable::query()->where('numero_piece', $affectation->piece_affectation)->count());
    }

    #[Test]
    public function le_serveur_rejoue_ses_phrases_de_refus(): void
    {
        // Avant la clôture : l'exercice n'est pas clôturé.
        $this->pousser([$this->piece($this->uuid())], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('comptabilite.affectation_exige_cloture', ['annee' => '2026']));

        $this->cloturer();

        // Somme différente du résultat.
        $this->pousser([$this->piece($this->uuid(), ['reserve_legale' => 700000, 'report_a_nouveau' => 6200000])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('comptabilite.affectation_somme_differente', ['somme' => '69000.00', 'resultat' => '70000.00', 'ecart' => '1000.00']));

        // Date hors de N.
        $this->pousser([$this->piece($this->uuid(), date: '2026-12-31')], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('comptabilite.affectation_date_hors_exercice', ['date' => '2026-12-31', 'annee' => '2027']));

        // Comptable seul.
        $this->pousser([$this->piece($this->uuid())], $this->creerUtilisateur('administrateur'))
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('comptabilite.affectation_reservee'));

        // La pièce du poste ne correspond pas à celle du serveur.
        $this->pousser([$this->piece($this->uuid(), lignes: [
            ['compte' => '131', 'debit' => 7000000, 'credit' => 0, 'centre' => 'Structure'],
            ['compte' => '118', 'debit' => 0, 'credit' => 7000000, 'centre' => 'Structure'],
        ])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('comptabilite.affectation_piece_divergente'));

        $this->assertSame(0, AffectationResultat::query()->count());

        // Une première passe, puis la seconde est refusée (unicité).
        $this->pousser([$this->piece($this->uuid())], $this->comptable)->assertJsonPath('resultats.0.statut', 'synchronise');
        $piece = AffectationResultat::query()->firstOrFail()->piece_affectation;
        $this->pousser([$this->piece($this->uuid())], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('comptabilite.affectation_deja_passee', ['annee' => '2026', 'piece' => $piece]));
        $this->assertSame(1, AffectationResultat::query()->count());
    }

    #[Test]
    public function la_contrepassation_du_poste_est_une_demande_aux_phrases_du_service(): void
    {
        $this->cloturer();
        $this->pousser([$this->piece($this->uuid())], $this->comptable);
        // La contre-passation se date du jour de la correction, dans N, jamais avant la pièce.
        $this->travelTo('2027-05-10 10:00:00');

        $this->pousser([$this->demande('annuler_affectation', ['motif' => 'court'])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('comptabilite.affectation_motif', ['min' => 10]));
        $this->pousser([$this->demande('annuler_affectation', ['motif' => 'Ventilation à revoir en assemblée'])], $this->creerUtilisateur('administrateur'))
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('comptabilite.affectation_reservee'));
        $this->assertSame(1, AffectationResultat::query()->whereNull('contrepassee_le')->count());

        $this->pousser([$this->demande('annuler_affectation', ['motif' => 'Ventilation à revoir en assemblée'])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.issue', 'executee');
        $this->assertSame(0, AffectationResultat::query()->whereNull('contrepassee_le')->count());

        // Déjà contre-passée : acceptée sans rien réécrire.
        $this->pousser([$this->demande('annuler_affectation', ['motif' => 'Ventilation à revoir en assemblée'])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.issue', DemandeClotureExercice::ISSUE_DEJA_DANS_CET_ETAT);

        // Une affectation contre-passée peut être refaite.
        $this->pousser([$this->piece($this->uuid())], $this->comptable)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame(2, AffectationResultat::query()->count());
    }

    #[Test]
    public function une_piece_de_poste_qui_porte_un_dividende_ou_une_reserve_legale_est_refusee_pour_une_entreprise_individuelle(): void
    {
        ParametreSysteme::query()->where('cle', FormeJuridique::CLE)->update(['valeur' => FormeJuridique::EntrepriseIndividuelle->value]);
        $this->cloturer();

        // La ventilation du poste porte 20 000 de dividendes (compte 465) : refus du serveur, sa phrase.
        $this->pousser([$this->piece($this->uuid(), ['dividendes' => 2000000, 'compte_exploitant' => 5000000], [
            ['compte' => '131', 'debit' => 7000000, 'credit' => 0, 'centre' => 'Structure'],
            ['compte' => '465', 'debit' => 0, 'credit' => 2000000, 'centre' => 'Structure'],
            ['compte' => '1041', 'debit' => 0, 'credit' => 5000000, 'centre' => 'Structure'],
        ])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('comptabilite.affectation_ei_dividende'));

        // La réserve légale du poste (SARL de l'ancienne version) : refusée aussi.
        $this->pousser([$this->piece($this->uuid())], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('comptabilite.affectation_ei_reserve_legale'));

        // Une ligne 465 glissée dans la pièce sans la ventilation : la pièce diverge, refusée.
        $this->pousser([$this->piece($this->uuid(), ['compte_exploitant' => 7000000], [
            ['compte' => '131', 'debit' => 7000000, 'credit' => 0, 'centre' => 'Structure'],
            ['compte' => '465', 'debit' => 0, 'credit' => 7000000, 'centre' => 'Structure'],
        ])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('comptabilite.affectation_piece_divergente'));
        $this->assertSame(0, AffectationResultat::query()->count());

        // La pièce EI correcte (compte de l'exploitant 1041, report à nouveau) passe.
        $this->pousser([$this->piece($this->uuid(), ['compte_exploitant' => 5000000, 'report_a_nouveau' => 2000000], [
            ['compte' => '131', 'debit' => 7000000, 'credit' => 0, 'centre' => 'Structure'],
            ['compte' => '1041', 'debit' => 0, 'credit' => 5000000, 'centre' => 'Structure'],
            ['compte' => '121', 'debit' => 0, 'credit' => 2000000, 'centre' => 'Structure'],
        ])], $this->comptable)->assertJsonPath('resultats.0.statut', 'synchronise');
        $affectation = AffectationResultat::query()->firstOrFail();
        $this->assertSame('50000.00', (string) $affectation->compte_exploitant);
        $this->assertSame('entreprise_individuelle', $affectation->forme_juridique);
    }

    #[Test]
    public function la_demande_de_contrepassation_du_poste_porte_la_reference_et_se_heurte_a_un_dividende_regle(): void
    {
        $this->cloturer();
        $this->pousser([$this->piece($this->uuid(), ['reserve_legale' => 700000, 'dividendes' => 1000000, 'report_a_nouveau' => 5300000], [
            ['compte' => '131', 'debit' => 7000000, 'credit' => 0, 'centre' => 'Structure'],
            ['compte' => '111', 'debit' => 0, 'credit' => 700000, 'centre' => 'Structure'],
            ['compte' => '465', 'debit' => 0, 'credit' => 1000000, 'centre' => 'Structure'],
            ['compte' => '121', 'debit' => 0, 'credit' => 5300000, 'centre' => 'Structure'],
        ])], $this->comptable)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->travelTo('2027-05-10 10:00:00');

        // Un règlement partiel du dividende (D 465 / C banque) : la demande est refusée.
        $reglement = app(PasserEcritureService::class)->passerEtValider(['journal' => 'OD', 'date' => '2027-05-02', 'libelle' => 'Règlement partiel', 'lignes' => [
            ['compte' => '465', 'debit' => '1000.00', 'centre_id' => (string) CentreCout::query()->where('libelle', 'Structure')->value('id')],
            ['compte' => '5211', 'credit' => '1000.00'],
        ]]);
        $this->pousser([$this->demande('annuler_affectation', ['motif' => 'Ventilation à revoir en assemblée'])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('comptabilite.affectation_dividende_regle', ['annee' => '2026', 'regle' => '1000.00', 'dividendes' => '10000.00']));
        $this->assertSame(1, AffectationResultat::query()->whereNull('contrepassee_le')->count());

        // Le règlement annulé, la demande passe, avec la référence de la décision.
        app(PasserEcritureService::class)->contrepasserPiece($reglement, 'Annulation du règlement');
        $this->pousser([$this->demande('annuler_affectation', ['motif' => 'Ventilation à revoir en assemblée', 'reference_decision' => 'PV du 10/05/2027'])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.issue', 'executee');
        $this->assertSame('PV du 10/05/2027', AffectationResultat::query()->firstOrFail()->reference_decision_contrepassation);
    }
}

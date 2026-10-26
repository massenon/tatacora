<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\ClotureExercice;
use App\Domain\Comptabilite\Models\DemandeClotureExercice;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Models\User;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Les DEMANDES de clôture d'un poste (26/10/2026) : le poste envoie un
 * document source (`annee`, `action`, `motif`) et le serveur, seul comptable,
 * rejoue les règles de `ClotureExerciceService` — il ne reçoit aucune pièce.
 */
final class DemandesClotureSynchronisationTest extends TestCase
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
        $this->comptable = $this->creerUtilisateur('comptable');
    }

    /** Vente bar 100 000, charge restaurant 30 000 : bénéfice 70 000. */
    private function exploiter(): void
    {
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

    /** @return array<string, mixed> */
    private function demande(string $action, array $surcharge = []): array
    {
        return $this->creation('demandes_cloture_exercice', $this->uuid(), [...['annee' => 2026, 'action' => $action], ...$surcharge]);
    }

    private function exercice(int $annee = 2026): ExerciceComptable
    {
        return ExerciceComptable::query()->where('annee', $annee)->firstOrFail();
    }

    #[Test]
    public function le_cycle_demarrer_cloturer_rouvrir_se_joue_par_le_serveur_et_ses_pieces_sont_les_siennes(): void
    {
        $this->exploiter();

        $this->pousser([$this->demande('demarrer')], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.issue', 'executee')
            ->assertJsonPath('resultats.0.statut_exercice', 'en_cloture');
        $this->assertSame('en_cloture', $this->exercice()->statut);
        // L'exercice suivant s'ouvre d'office, comme à l'écran.
        $this->assertSame('ouvert', $this->exercice(2027)->statut);

        $reponse = $this->pousser([$this->demande('cloturer')], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.statut_exercice', 'cloture');
        $this->assertSame('cloture', $this->exercice()->statut);

        $cloture = ClotureExercice::query()->where('exercice_id', $this->exercice()->id)->whereNull('rouverte_le')->firstOrFail();
        $this->assertSame('70000.00', (string) $cloture->resultat);
        $this->assertSame($cloture->piece_cloture, $reponse->json('resultats.0.piece_cloture'));
        $this->assertSame($cloture->piece_a_nouveaux, $reponse->json('resultats.0.piece_a_nouveaux'));
        // L'archive légale suit la clôture : son empreinte revient au poste.
        $this->assertNotNull($cloture->archive_empreinte);
        $this->assertSame($cloture->archive_empreinte, $reponse->json('resultats.0.archive_empreinte'));

        $this->pousser([$this->demande('rouvrir', ['motif' => 'Facture fournisseur oubliée'])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.statut_exercice', 'en_cloture');
        $this->assertSame('en_cloture', $this->exercice()->statut);
        $this->assertNotNull($cloture->refresh()->rouverte_le);
        $this->assertSame('Facture fournisseur oubliée', $cloture->motif_reouverture);

        $this->pousser([$this->demande('reprendre_saisie')], $this->comptable)
            ->assertJsonPath('resultats.0.statut_exercice', 'ouvert');

        $this->assertSame(4, DemandeClotureExercice::query()->count());
    }

    #[Test]
    public function les_refus_sont_ceux_du_service_aux_memes_phrases(): void
    {
        $this->exploiter();

        // Clôturer sans « Démarrer » : refus du service.
        $this->pousser([$this->demande('cloturer')], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('comptabilite.cloture_exige_en_cloture', ['annee' => '2026']));

        // Une pièce en brouillon bloque la clôture (liste de contrôle).
        app(PasserEcritureService::class)->passer(['journal' => 'OD', 'date' => '2026-04-01', 'libelle' => 'Brouillon', 'lignes' => [
            ['compte' => '5711', 'debit' => '10.00'],
            ['compte' => '7011', 'credit' => '10.00', 'centre_id' => (string) CentreCout::query()->where('libelle', 'Bar')->value('id')],
        ]]);
        $this->pousser([$this->demande('demarrer')], $this->comptable)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->pousser([$this->demande('cloturer')], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.code_motif', 'regle_metier');
        $this->assertSame('en_cloture', $this->exercice()->statut);
        $this->assertSame(0, ClotureExercice::query()->count());

        // Un exercice inconnu, une action inconnue, une année absurde.
        $this->pousser([$this->demande('demarrer', ['annee' => 2031])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('comptabilite.demande_cloture_exercice_inconnu', ['annee' => '2031']));
        $this->pousser([$this->demande('supprimer')], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('comptabilite.demande_cloture_action_inconnue', [
                'action' => 'supprimer',
                'admises' => 'demarrer, reprendre_saisie, cloturer, rouvrir',
            ]));
        $this->pousser([$this->demande('demarrer', ['annee' => 1850])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete');
        $this->assertSame(1, DemandeClotureExercice::query()->count());
    }

    #[Test]
    public function la_reouverture_reste_au_comptable_et_exige_un_motif_de_dix_caracteres(): void
    {
        $this->exploiter();
        $this->pousser([$this->demande('demarrer'), $this->demande('cloturer')], $this->comptable);
        $this->assertSame('cloture', $this->exercice()->statut);

        $gerant = $this->creerUtilisateur('administrateur');
        $this->pousser([$this->demande('rouvrir', ['motif' => 'Un motif assez long'])], $gerant)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('comptabilite.reouverture_reservee'));

        $this->pousser([$this->demande('rouvrir', ['motif' => 'court'])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('comptabilite.reouverture_motif', ['min' => 10]));

        $this->assertSame('cloture', $this->exercice()->statut);
        $this->assertNull(ClotureExercice::query()->firstOrFail()->rouverte_le);
    }

    #[Test]
    public function une_demande_deja_satisfaite_est_acceptee_sans_rien_reecrire(): void
    {
        $this->exploiter();
        $this->pousser([$this->demande('demarrer')], $this->comptable);
        $pieces = EcritureComptable::query()->count();

        $this->pousser([$this->demande('demarrer')], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.issue', 'deja_dans_cet_etat');
        $this->pousser([$this->demande('rouvrir', ['motif' => 'inutile ici'])], $this->comptable)
            ->assertJsonPath('resultats.0.issue', 'deja_dans_cet_etat');

        $this->assertSame($pieces, EcritureComptable::query()->count());
        $this->assertSame('en_cloture', $this->exercice()->statut);
    }

    #[Test]
    public function le_rejeu_d_une_demande_ne_clot_pas_deux_fois_et_le_droit_est_celui_de_m10(): void
    {
        $this->exploiter();
        $this->pousser([$this->demande('demarrer')], $this->comptable);
        $operation = $this->demande('cloturer');

        $this->pousser([$operation], $this->comptable)->assertJsonPath('resultats.0.statut', 'synchronise');
        // Même document sous un AUTRE identifiant d'opération : reconnu par son UUID.
        $rejeu = [...$operation, 'uuid_operation' => $this->uuid()];
        $this->pousser([$rejeu], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.document_deja_enregistre', true);

        $this->assertSame(1, ClotureExercice::query()->count());
        $this->assertSame(2, DemandeClotureExercice::query()->count());

        $sansDroit = $this->creerUtilisateur('cuisine');
        $this->pousser([$this->demande('rouvrir', ['motif' => 'Un motif assez long'])], $sansDroit)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.code_motif', 'droit_manquant');

        $this->pousser([$this->operation('demandes_cloture_exercice', 'modification', $operation['entite_id'], ['action' => 'rouvrir'])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.code_motif', 'modification_non_synchronisable');
        $this->assertSame('cloture', $this->exercice()->statut);
    }

    #[Test]
    public function le_serveur_ne_recoit_aucune_piece_du_poste_et_passe_les_siennes(): void
    {
        $this->exploiter();
        $avant = EcritureComptable::query()->count();
        $this->pousser([$this->demande('demarrer')], $this->comptable);
        // Aucune pièce n'est passée par une demande de démarrage.
        $this->assertSame($avant, EcritureComptable::query()->count());

        $this->pousser([$this->demande('cloturer')], $this->comptable);
        $journaux = EcritureComptable::query()->join('journaux_comptables as j', 'j.id', '=', 'ecritures_comptables.journal_id')
            ->whereIn('j.code', ['CL', 'AN'])->distinct()->pluck('j.code')->sort()->values()->all();
        $this->assertSame(['AN', 'CL'], $journaux);
    }
}

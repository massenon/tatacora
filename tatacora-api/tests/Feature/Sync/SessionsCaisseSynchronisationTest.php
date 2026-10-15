<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Caisse\Services\SessionCaisseService;
use App\Models\User;
use App\Shared\Sync\Models\AnomalieSynchronisation;
use App\Shared\Sync\Models\ConflitSynchronisation;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PrepareLesDocuments;
use Tests\TestCase;

/**
 * Sessions de caisse ouvertes et clôturées hors connexion — lot S3,
 * décisions du Product Owner du 15/10/2026.
 *
 * Ouverture = création, clôture = modification de la même entité, toutes
 * deux par `SessionCaisseService` (l'auteur que la PWA appelle aussi), aux
 * dates MÉTIER saisies au poste. Le théorique est recalculé par le serveur ;
 * celui du poste, s'il diffère, est SIGNALÉ — jamais écrit à sa place.
 */
final class SessionsCaisseSynchronisationTest extends TestCase
{
    use PrepareLesDocuments;
    use RefreshDatabase;

    private User $barman;

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerLeDecor();

        // `barman` : M5 = 'C' — le droit de `PosComptant::ouvrirCaisse`.
        $this->barman = $this->creerUtilisateur('barman');
    }

    #[Test]
    public function l_ouverture_passe_par_le_service_a_la_date_saisie_au_poste(): void
    {
        $id = $this->uuid();

        $this->pousser([$this->ouverture($id, '2026-10-14 07:00:00', 2500000)], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.entite_id', $id)
            ->assertJsonPath('resultats.0.statut_caisse', 'ouverte');

        $session = SessionCaisse::findOrFail($id);
        $this->assertSame('bar', $session->point_vente);
        $this->assertSame('25000.00', (string) $session->montant_fond);
        // La date MÉTIER, pas celle de réception (15/10 12:00).
        $this->assertSame('2026-10-14 07:00:00', $session->date_ouverture->format('Y-m-d H:i:s'));
        // L'auteur est le titulaire du JETON (RG-15), jamais un champ du payload.
        $this->assertSame($this->barman->id, $session->utilisateur_ouverture_id);
    }

    /**
     * Le piège connu : ouverture et clôture dans le MÊME lot. La clôture est
     * saisie avant que l'ouverture ne soit écrite au serveur ; elle ne doit
     * pas partir en « conflit financier ».
     */
    #[Test]
    public function ouverture_et_cloture_dans_le_meme_lot_ne_sont_pas_un_conflit(): void
    {
        $id = $this->uuid();

        $reponse = $this->pousser([
            $this->ouverture($id, '2026-10-14 07:00:00', 1000000),
            $this->cloture($id, '2026-10-14 22:00:00', 1000000),
        ], $this->barman);

        $reponse->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.1.statut', 'synchronise')
            ->assertJsonPath('resultats.1.statut_caisse', 'cloturee')
            ->assertJsonPath('resultats.1.montant_theorique', '10000.00')
            ->assertJsonPath('resultats.1.ecart', '0.00');

        $this->assertSame(0, ConflitSynchronisation::count());
        $session = SessionCaisse::findOrFail($id);
        $this->assertSame('2026-10-14 22:00:00', $session->date_cloture->format('Y-m-d H:i:s'));
    }

    /**
     * Une écriture d'un TIERS après celle du poste reste un conflit : la
     * reconnaissance du « même poste » ne vaut que s'il est le dernier
     * écrivain.
     */
    #[Test]
    public function une_cloture_venue_d_un_autre_poste_reste_un_conflit_financier(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->ouverture($id, '2026-10-14 07:00:00', 1000000)], $this->barman, 'poste-a');

        $this->pousser([$this->cloture($id, '2026-10-14 22:00:00', 1000000)], $this->barman, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'conflit')
            ->assertJsonPath('resultats.0.type_conflit', 'financier_arbitrage_requis');

        $this->assertNull(SessionCaisse::findOrFail($id)->date_cloture);
    }

    #[Test]
    public function le_theorique_est_recalcule_et_l_ecart_du_poste_signale_sans_etre_ecrit(): void
    {
        $id = $this->uuid();

        $reponse = $this->pousser([
            $this->ouverture($id, '2026-10-14 07:00:00', 1000000),
            // Le poste croit avoir 12 000 F de théorique ; le serveur ne
            // connaît aucune vente de cette session : 10 000 F.
            $this->cloture($id, '2026-10-14 22:00:00', 1150000, theorique: 1200000),
        ], $this->barman);

        $reponse->assertJsonPath('resultats.1.statut', 'synchronise')
            ->assertJsonPath('resultats.1.montant_theorique', '10000.00')
            ->assertJsonPath('resultats.1.montant_theorique_poste', '12000.00')
            ->assertJsonPath('resultats.1.ecart_theorique', '2000.00')
            ->assertJsonPath('resultats.1.ecart', '1500.00');

        $this->assertSame('10000.00', (string) SessionCaisse::findOrFail($id)->montant_theorique);
        $this->assertDatabaseHas('anomalies_synchronisation', [
            'table_concernee' => 'sessions_caisse', 'entite_id' => $id,
            'type' => AnomalieSynchronisation::ECART_THEORIQUE_CAISSE,
            'valeur_poste' => '12000.00', 'valeur_serveur' => '10000.00',
        ]);
    }

    #[Test]
    public function une_cloture_ne_transmet_que_ses_champs(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->ouverture($id, '2026-10-14 07:00:00', 1000000)], $this->barman);

        $this->pousser([$this->operation('sessions_caisse', 'modification', $id, [
            'date_cloture' => '2026-10-14 22:00:00', 'montant_constate_centimes' => 1000000,
            'montant_fond_centimes' => 0,
        ])], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.caisse.champ_non_modifiable', ['champs' => 'montant_fond_centimes']));

        $this->assertNull(SessionCaisse::findOrFail($id)->date_cloture);
    }

    #[Test]
    public function le_rejeu_de_l_ouverture_et_de_la_cloture_ne_double_rien(): void
    {
        $id = $this->uuid();
        $ouverture = $this->ouverture($id, '2026-10-14 07:00:00', 1000000);
        $cloture = $this->cloture($id, '2026-10-14 22:00:00', 1000000);

        $this->pousser([$ouverture, $cloture], $this->barman);

        // Même `uuid_operation` : la mémoire d'idempotence répond.
        $this->pousser([$ouverture, $cloture], $this->barman)
            ->assertJsonPath('resultats.0.rejeu_idempotent', true)
            ->assertJsonPath('resultats.1.rejeu_idempotent', true);

        // Nouvelle tentative APRÈS la purge : le document répond.
        $this->purgerLaMemoireDIdempotence();

        $this->pousser([$this->nouvelleTentative($ouverture), $this->nouvelleTentative($cloture)], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.document_deja_enregistre', true)
            ->assertJsonPath('resultats.1.statut', 'synchronise')
            ->assertJsonPath('resultats.1.statut_caisse', 'cloturee');

        $this->assertSame(1, SessionCaisse::count());

        // Une AUTRE clôture d'une session close est refusée.
        $this->pousser([$this->cloture($id, '2026-10-14 23:00:00', 900000)], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('caisse.deja_cloturee'));
    }

    #[Test]
    public function une_seconde_caisse_ouverte_sur_le_meme_point_est_refusee_avec_la_phrase_de_l_ecran(): void
    {
        app(SessionCaisseService::class)->ouvrir('bar', '5000', $this->barman->id);

        $this->pousser([$this->ouverture($this->uuid(), '2026-10-14 07:00:00', 1000000)], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('pos_pwa.comptant.refus_caisse_deja_ouverte'));

        $this->assertSame(1, SessionCaisse::count());
    }

    #[Test]
    public function sans_ecriture_sur_m5_aucune_session_n_est_synchronisee(): void
    {
        $receptionniste = $this->creerUtilisateur('receptionniste');

        $this->pousser([$this->ouverture($this->uuid(), '2026-10-14 07:00:00', 1000000)], $receptionniste)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('auth.module_refuse'));

        $this->assertDatabaseHas('journal_securite', [
            'utilisateur_id' => $receptionniste->id, 'module_concerne' => 'M5',
        ]);
        $this->assertSame(0, SessionCaisse::count());
    }

    #[Test]
    public function une_ouverture_invalide_est_rejetee_par_champ(): void
    {
        $this->pousser([$this->creation('sessions_caisse', $this->uuid(), [
            'point_vente' => 'piscine', 'date_ouverture' => '2026-10-14 07:00:00', 'montant_fond_centimes' => -5,
        ])], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('caisse.point_inconnu', ['point' => 'piscine']))
            ->assertJsonStructure(['resultats' => [['erreurs' => ['point_vente', 'montant_fond_centimes']]]]);

        $this->assertSame(0, SessionCaisse::count());
    }

    /**
     * @return array<string, mixed>
     */
    private function ouverture(string $id, string $date, int $fondCentimes): array
    {
        return $this->operationDatee('sessions_caisse', 'creation', $id, [
            'point_vente' => 'bar', 'date_ouverture' => $date, 'montant_fond_centimes' => $fondCentimes,
        ], str_replace(' ', 'T', $date) . '+00:00');
    }

    /**
     * @return array<string, mixed>
     */
    private function cloture(string $id, string $date, int $constateCentimes, ?int $theorique = null): array
    {
        return $this->operationDatee('sessions_caisse', 'modification', $id, [
            'date_cloture' => $date,
            'montant_constate_centimes' => $constateCentimes,
            ...($theorique !== null ? ['montant_theorique_centimes' => $theorique] : []),
        ], str_replace(' ', 'T', $date) . '+00:00');
    }
}

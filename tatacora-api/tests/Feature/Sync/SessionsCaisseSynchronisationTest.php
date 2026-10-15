<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Caisse\Services\SessionCaisseService;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Ventes\Models\Vente;
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

    // ------------------------------- Clôture jamais bloquée (PO 15/10/2026)

    /**
     * La clôture d'une session que le serveur ne connaît pas n'est PAS
     * rejetée : statut `cloture_sans_session_serveur`, anomalie avec les
     * chiffres du poste, et rien d'autre d'écrit — ni session, ni pièce.
     * Rejouée (même opération, puis nouvelle tentative après la purge), elle
     * rend le même statut sans second signalement.
     */
    #[Test]
    public function la_cloture_d_une_session_inconnue_est_acceptee_sans_rien_ecrire_et_signalee(): void
    {
        $id = $this->uuid();
        $sessions = SessionCaisse::count();
        $pieces = EcritureComptable::count();
        $cloture = $this->operationDatee('sessions_caisse', 'modification', $id, [
            'date_cloture' => '2026-10-14 22:00:00',
            'montant_constate_centimes' => 1150000,
            'montant_theorique_centimes' => 1200000,
            'montant_fond_centimes' => 1000000,
            'date_ouverture' => '2026-10-14 07:00:00',
            'point_vente' => 'bar',
        ], '2026-10-14T22:00:00+00:00');

        $this->pousser([$cloture], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'cloture_sans_session_serveur')
            ->assertJsonPath('resultats.0.entite_id', $id)
            ->assertJsonPath('resultats.0.anomalies', [AnomalieSynchronisation::CLOTURE_SESSION_INCONNUE])
            ->assertJsonMissingPath('resultats.0.motif');

        $anomalie = AnomalieSynchronisation::query()
            ->where('entite_id', $id)->where('type', AnomalieSynchronisation::CLOTURE_SESSION_INCONNUE)->sole();
        $this->assertSame('11500.00', (string) $anomalie->valeur_poste);
        // `assertEquals` : une colonne JSON ne garde pas l'ordre des clés.
        $this->assertEquals([
            'point_vente' => 'bar',
            'date_ouverture' => '2026-10-14 07:00:00',
            'date_cloture' => '2026-10-14 22:00:00',
            'montant_fond' => '10000.00',
            'montant_theorique_poste' => '12000.00',
            'montant_constate' => '11500.00',
        ], $anomalie->details);

        $this->assertSame($sessions, SessionCaisse::count());
        $this->assertSame($pieces, EcritureComptable::count());
        $this->assertSame(0, ConflitSynchronisation::count());

        // Rejeu de la même opération : la mémoire d'idempotence répond.
        $this->pousser([$cloture], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'cloture_sans_session_serveur')
            ->assertJsonPath('resultats.0.rejeu_idempotent', true);

        // Nouvelle tentative après la purge : même statut, toujours UNE anomalie.
        $this->purgerLaMemoireDIdempotence();
        $this->pousser([$this->nouvelleTentative($cloture)], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'cloture_sans_session_serveur');

        $this->assertSame(1, AnomalieSynchronisation::where('entite_id', $id)->count());
        $this->assertSame($sessions, SessionCaisse::count());
    }

    /**
     * Le scénario complet du Product Owner : une caisse est déjà ouverte sur
     * le bar au serveur → l'ouverture du poste est refusée (phrase de
     * l'écran) → ses ventes sont ENREGISTRÉES et signalées → sa clôture est
     * acceptée en `cloture_sans_session_serveur`. Rien n'est bloqué, et la
     * caisse du serveur n'est pas touchée.
     */
    #[Test]
    public function ouverture_refusee_ventes_enregistrees_cloture_acceptee_rien_n_est_bloque(): void
    {
        $serveur = app(SessionCaisseService::class)->ouvrir('bar', '5000', $this->barman->id);
        $sessionPoste = $this->uuid();
        [$venteA, $venteB] = [$this->uuid(), $this->uuid()];

        $reponse = $this->pousser([
            $this->ouverture($sessionPoste, '2026-10-14 07:00:00', 1000000),
            $this->venteDeLaSession($venteA, $sessionPoste, '2026-10-14 12:00:00', 2),
            $this->venteDeLaSession($venteB, $sessionPoste, '2026-10-14 20:00:00', 1),
            $this->operationDatee('sessions_caisse', 'modification', $sessionPoste, [
                'date_cloture' => '2026-10-14 22:00:00',
                'montant_constate_centimes' => 1300000,
                'montant_theorique_centimes' => 1300000,
                'montant_fond_centimes' => 1000000,
                'date_ouverture' => '2026-10-14 07:00:00',
            ], '2026-10-14T22:00:00+00:00'),
        ], $this->barman);

        $reponse->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('pos_pwa.comptant.refus_caisse_deja_ouverte'))
            ->assertJsonPath('resultats.1.statut', 'synchronise')
            ->assertJsonPath('resultats.1.anomalies', [AnomalieSynchronisation::VENTE_SESSION_INCONNUE])
            ->assertJsonPath('resultats.2.statut', 'synchronise')
            ->assertJsonPath('resultats.2.anomalies', [AnomalieSynchronisation::VENTE_SESSION_INCONNUE])
            ->assertJsonPath('resultats.3.statut', 'cloture_sans_session_serveur');

        // Les ventes existent, sans session (inconnue), avec leurs pièces.
        $this->assertSame([null, null], [Vente::findOrFail($venteA)->session_id, Vente::findOrFail($venteB)->session_id]);
        $this->assertSame('3000.00', bcadd((string) Vente::findOrFail($venteA)->montant_total, (string) Vente::findOrFail($venteB)->montant_total, 2));

        // La caisse du serveur est intacte : toujours ouverte, seule session.
        $this->assertSame(1, SessionCaisse::count());
        $this->assertNull($serveur->fresh()->date_cloture);
        $this->assertNull(SessionCaisse::find($sessionPoste));

        $this->assertDatabaseHas('anomalies_synchronisation', [
            'table_concernee' => 'sessions_caisse', 'entite_id' => $sessionPoste,
            'type' => AnomalieSynchronisation::CLOTURE_SESSION_INCONNUE, 'valeur_poste' => '13000.00',
        ]);
        // Le lot n'est pas un échec : seule l'ouverture est refusée.
        $this->assertDatabaseHas('sessions_synchronisation', ['id' => $reponse->json('session_id'), 'statut' => 'partiel']);
    }

    /**
     * Le poste ne sait pas toujours si le serveur connaît sa session : il
     * peut rappeler l'ouverture dans sa clôture. Session connue, rappel
     * conforme → la clôture passe ; rappel DIFFÉRENT → refusé (voir
     * `une_cloture_ne_transmet_que_ses_champs`).
     */
    #[Test]
    public function une_cloture_qui_rappelle_l_ouverture_conforme_passe(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->ouverture($id, '2026-10-14 07:00:00', 1000000)], $this->barman);

        $this->pousser([$this->operationDatee('sessions_caisse', 'modification', $id, [
            'date_cloture' => '2026-10-14 22:00:00', 'montant_constate_centimes' => 1000000,
            'montant_fond_centimes' => 1000000, 'date_ouverture' => '2026-10-14 07:00:00', 'point_vente' => 'bar',
        ], '2026-10-14T22:00:00+00:00')], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.statut_caisse', 'cloturee');
    }

    /**
     * @return array<string, mixed>
     */
    private function venteDeLaSession(string $id, string $session, string $cloture, int $bieres): array
    {
        return $this->operationDatee('ventes', 'creation', $id, [
            'type_vente' => 'comptant',
            'mode_paiement' => 'especes',
            'session_encaissement_id' => $session,
            'cloture_le' => $cloture,
            'point_vente' => 'Bar',
            'lignes' => [[
                'module_source' => 'M5', 'code_article' => $this->biere->id,
                'prix_unitaire' => 1000, 'quantite' => $bieres,
            ]],
        ], str_replace(' ', 'T', $cloture) . '+00:00');
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

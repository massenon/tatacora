<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Caisse\Services\SessionCaisseService;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use App\Domain\Restaurant\Models\CommandeRestaurant;
use App\Domain\Stocks\Models\MouvementStock;
use App\Domain\Ventes\Models\LigneVente;
use App\Domain\Ventes\Models\Vente;
use App\Models\User;
use App\Shared\Sync\Models\AnomalieSynchronisation;
use App\Shared\Sync\Models\CorrespondanceSynchronisation;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PrepareLesDocuments;
use Tests\TestCase;

/**
 * Ventes au comptant faites hors connexion — lot S3, décisions du Product
 * Owner du 15/10/2026.
 *
 * Le poste pousse le panier CLÔTURÉ (source) ; le serveur produit la pièce
 * VTE et les sorties de stock par `VenteService`, à la date métier. Le prix
 * du POSTE fait foi, l'écart avec le catalogue est signalé ; une rupture de
 * stock ne rejette pas une vente déjà faite ; aucun bon de cuisine n'est
 * émis pour une assiette déjà servie.
 */
final class VentesSynchronisationTest extends TestCase
{
    use PrepareLesDocuments;
    use RefreshDatabase;

    private User $barman;

    private User $gerant;

    private SessionCaisse $session;

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerLeDecor();

        $this->barman = $this->creerUtilisateur('barman');
        $this->gerant = $this->creerUtilisateur('gerant');
        $this->session = app(SessionCaisseService::class)->ouvrir(
            'bar',
            '10000',
            $this->barman->id,
            now()->subDay()->setTime(7, 0),
        );
    }

    #[Test]
    public function la_vente_est_enregistree_par_le_service_avec_sa_piece_a_la_date_metier(): void
    {
        $id = $this->uuid();

        $reponse = $this->pousser([$this->vente($id, [$this->ligneBiere(2)])], $this->barman);

        $reponse->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.entite_id', $id)
            ->assertJsonPath('resultats.0.numero', 'V-2026-00001')
            ->assertJsonPath('resultats.0.montant_total', '2000.00')
            ->assertJsonMissingPath('resultats.0.ecart_prix');

        $vente = Vente::findOrFail($id);
        $this->assertSame($this->session->id, $vente->session_id);
        $this->assertSame($this->barman->id, $vente->utilisateur_id);
        // La date de la VENTE (14/10 21:30), pas celle de réception (15/10).
        $this->assertSame('2026-10-14 21:30:00', $vente->created_at->format('Y-m-d H:i:s'));

        // La pièce : journal VTE, datée du 14/10, débit caisse 5711 = 2 000 F.
        $piece = EcritureComptable::where('libelle', __('ventes.libelle_ecriture', ['numero' => 'V-2026-00001']))->get();
        $this->assertNotEmpty($piece);
        $this->assertSame(['2026-10-14'], $piece->map(fn ($e) => $e->date_ecriture->toDateString())->unique()->values()->all());
        $this->assertSame(JournalComptable::where('code', 'VTE')->value('id'), $piece->first()->journal_id);
        $caisse = CompteComptable::where('numero_compte', '5711')->value('id');
        $this->assertSame('2000.00', (string) $piece->firstWhere('compte_id', $caisse)?->debit);

        // La sortie de stock du bar, à la date métier.
        $sortie = MouvementStock::where('article_id', $this->articleBiere->id)->where('type_mouvement', 'sortie')->sole();
        $this->assertSame('2.00', (string) $sortie->quantite);
        $this->assertSame('2026-10-14 21:30:00', $sortie->date_mouvement->format('Y-m-d H:i:s'));
    }

    /**
     * Le prix du POSTE fait foi ; l'écart avec le catalogue serveur est
     * stocké sur la ligne ET signalé, puis rendu au poste.
     */
    #[Test]
    public function le_prix_du_poste_fait_foi_et_l_ecart_au_catalogue_est_signale(): void
    {
        $id = $this->uuid();

        $reponse = $this->pousser([$this->vente($id, [$this->ligneBiere(2, prix: 900)])], $this->barman);

        $reponse->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.montant_total', '1800.00')
            ->assertJsonPath('resultats.0.ecart_prix.0.code_article', $this->biere->id)
            ->assertJsonPath('resultats.0.ecart_prix.0.prix_poste', '900.00')
            ->assertJsonPath('resultats.0.ecart_prix.0.prix_catalogue', '1000.00')
            ->assertJsonPath('resultats.0.ecart_prix.0.ecart', '-100.00')
            ->assertJsonPath('resultats.0.anomalies', [AnomalieSynchronisation::ECART_PRIX]);

        $ligne = LigneVente::where('vente_id', $id)->sole();
        $this->assertSame('900.00', (string) $ligne->prix_unitaire);
        $this->assertSame('1000.00', (string) $ligne->prix_catalogue);
        // Le catalogue n'est PAS corrigé, la vente n'est pas recalculée.
        $this->assertSame('1000.00', (string) $this->biere->fresh()->prix_vente);
        $this->assertDatabaseHas('anomalies_synchronisation', [
            'table_concernee' => 'ventes', 'entite_id' => $id, 'type' => AnomalieSynchronisation::ECART_PRIX,
            'reference' => $this->biere->id, 'valeur_poste' => '900.00', 'valeur_serveur' => '1000.00',
        ]);
    }

    #[Test]
    public function une_rupture_de_stock_force_la_vente_et_la_signale(): void
    {
        $id = $this->uuid();

        // 50 bières vendues, 48 en stock serveur.
        $this->pousser([$this->vente($id, [$this->ligneBiere(50)])], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.numero', 'V-2026-00001')
            ->assertJsonPath('resultats.0.anomalies', [AnomalieSynchronisation::VENTE_EN_RUPTURE]);

        $this->assertSame(1, Vente::count());
        $this->assertSame(1, $this->nombreDeMouvements($this->articleBiere->id, 'sortie'));
        $this->assertDatabaseHas('anomalies_synchronisation', [
            'entite_id' => $id, 'type' => AnomalieSynchronisation::VENTE_EN_RUPTURE,
        ]);
        // RG-06 : la rupture forcée est imputée à quelqu'un.
        $this->assertDatabaseHas('journal_audit', ['action' => 'rupture_stock_forcee', 'utilisateur_id' => $this->barman->id]);
        // La tentative annulée n'a brûlé aucun numéro, ni laissé de pièce.
        $this->assertSame(1, $this->nombreDePieces(__('ventes.libelle_ecriture', ['numero' => 'V-2026-00001'])));
    }

    /**
     * L'assiette est servie : la synchronisation sort les denrées (RG-05) mais
     * n'émet aucune commande ni aucun bon de cuisine.
     */
    #[Test]
    public function un_plat_sort_ses_denrees_sans_creer_de_commande_de_cuisine(): void
    {
        $this->pousser([$this->vente($this->uuid(), [$this->lignePlat(2)])], $this->gerant)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.montant_total', '5000.00');

        $this->assertSame(0, CommandeRestaurant::count());
        $sortie = MouvementStock::where('article_id', $this->articleRiz->id)->where('type_mouvement', 'sortie')->sole();
        $this->assertSame('0.50', (string) $sortie->quantite);
        $this->assertSame($this->cuisine->id, $sortie->point_id);
    }

    #[Test]
    public function un_ticket_avec_des_plats_exige_aussi_l_ecriture_sur_m4(): void
    {
        // `barman` : M5 = C, M4 = '-'.
        $this->pousser([$this->vente($this->uuid(), [$this->ligneBiere(1), $this->lignePlat(1)])], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('auth.module_refuse'));

        $this->assertDatabaseHas('journal_securite', ['utilisateur_id' => $this->barman->id, 'module_concerne' => 'M4']);
        $this->assertSame(0, Vente::count());

        $receptionniste = $this->creerUtilisateur('receptionniste');
        $this->pousser([$this->vente($this->uuid(), [$this->ligneBiere(1)])], $receptionniste)
            ->assertJsonPath('resultats.0.motif', __('auth.module_refuse'));
        $this->assertSame(0, Vente::count());
    }

    /**
     * Même `uuid_operation` → mémoire d'idempotence ; nouvelle tentative
     * APRÈS la purge → le document répond. Jamais un second numéro, une
     * seconde pièce ni une seconde sortie de stock.
     */
    #[Test]
    public function le_rejeu_ne_produit_ni_second_numero_ni_seconde_piece_ni_second_mouvement(): void
    {
        $operation = $this->vente($this->uuid(), [$this->ligneBiere(3)]);

        $this->pousser([$operation], $this->barman);
        $this->pousser([$operation], $this->barman)->assertJsonPath('resultats.0.rejeu_idempotent', true);

        $this->purgerLaMemoireDIdempotence();

        $this->pousser([$this->nouvelleTentative($operation)], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.document_deja_enregistre', true)
            ->assertJsonPath('resultats.0.numero', 'V-2026-00001');

        $this->assertSame(1, Vente::count());
        $this->assertSame(1, $this->nombreDeMouvements($this->articleBiere->id, 'sortie'));
        $this->assertSame(1, $this->nombreDePieces(__('ventes.libelle_ecriture', ['numero' => 'V-2026-00001'])));
        $this->assertSame(0, Vente::where('numero', 'V-2026-00002')->count());
    }

    /**
     * Une vente du 31/12 synchronisée le 15/10 suivant… dans l'autre sens :
     * une vente du 31/12/2025 reçue en 2026 porte un numéro 2025, une pièce
     * 2025.
     */
    #[Test]
    public function le_numero_est_alloue_dans_l_annee_de_la_vente(): void
    {
        $this->ouvrirExercice(2025);
        $session = app(SessionCaisseService::class)->cloturer($this->session, '10000');
        $this->assertNotNull($session->date_cloture);

        $id = $this->uuid();
        $this->pousser([$this->vente($id, [$this->ligneBiere(1)], cloture: '2025-12-31 23:10:00', session: null)], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.numero', 'V-2025-00001');

        $piece = EcritureComptable::where('libelle', __('ventes.libelle_ecriture', ['numero' => 'V-2025-00001']))->firstOrFail();
        $this->assertSame('2025-12-31', $piece->date_ecriture->toDateString());
    }

    #[Test]
    public function les_identifiants_cites_passent_par_les_correspondances(): void
    {
        $idPosteBiere = $this->uuid();
        $idPosteSession = $this->uuid();
        CorrespondanceSynchronisation::create([
            'poste_id' => 'poste-windows-1', 'table_concernee' => 'cartes_boisson', 'id_poste' => $idPosteBiere, 'id_serveur' => $this->biere->id,
        ]);
        CorrespondanceSynchronisation::create([
            'poste_id' => 'poste-windows-1', 'table_concernee' => 'sessions_caisse', 'id_poste' => $idPosteSession, 'id_serveur' => $this->session->id,
        ]);

        $id = $this->uuid();
        $this->pousser([$this->vente($id, [[...$this->ligneBiere(1), 'code_article' => $idPosteBiere]], session: $idPosteSession)], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame($this->biere->id, LigneVente::where('vente_id', $id)->value('code'));
        $this->assertSame($this->session->id, Vente::findOrFail($id)->session_id);
    }

    #[Test]
    public function une_session_inconnue_ou_close_ne_fait_pas_perdre_la_vente_mais_est_signalee(): void
    {
        $inconnue = $this->uuid();
        $this->pousser([$this->vente($inconnue, [$this->ligneBiere(1)], session: $this->uuid())], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.anomalies', [AnomalieSynchronisation::VENTE_SESSION_INCONNUE]);
        $this->assertNull(Vente::findOrFail($inconnue)->session_id);

        app(SessionCaisseService::class)->cloturer($this->session, '11000');

        $tardive = $this->uuid();
        $this->pousser([$this->vente($tardive, [$this->ligneBiere(1)])], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.anomalies', [AnomalieSynchronisation::VENTE_SESSION_CLOTUREE]);
        $this->assertSame($this->session->id, Vente::findOrFail($tardive)->session_id);
    }

    #[Test]
    public function la_note_de_chambre_est_refusee_avec_son_motif(): void
    {
        $this->pousser([$this->vente($this->uuid(), [$this->ligneBiere(1)], extra: [
            'type_vente' => 'sur_sejour', 'mode_paiement' => 'note_chambre', 'reservation_id' => $this->uuid(),
        ])], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.ventes.note_chambre_hors_perimetre'));

        $this->assertSame(0, Vente::count());
    }

    #[Test]
    public function les_refus_portent_les_phrases_du_service(): void
    {
        $reponse = $this->pousser([
            $this->vente($this->uuid(), []),
            $this->vente($this->uuid(), [[...$this->ligneBiere(1), 'code_article' => $this->uuid()]]),
            $this->vente($this->uuid(), [$this->ligneBiere(1)], extra: ['mode_paiement' => 'cheque']),
            $this->vente($this->uuid(), [$this->ligneBiere(0)]),
            $this->vente($this->uuid(), [$this->ligneBiere(2)], extra: ['montant_cloture' => 5000]),
        ], $this->barman);

        $reponse->assertJsonPath('resultats.0.motif', __('ventes.panier_vide'))
            ->assertJsonPath('resultats.1.statut', 'rejete')
            ->assertJsonPath('resultats.2.motif', __('ventes.mode_paiement_inconnu', ['mode' => 'cheque']))
            ->assertJsonPath('resultats.3.motif', __('ventes.quantite_minimale'))
            ->assertJsonPath('resultats.4.motif', __('sync.ventes.total_incoherent', ['annonce' => '5000', 'lignes' => '2000']));

        $this->assertStringContainsString('introuvable', (string) $reponse->json('resultats.1.motif'));
        $this->assertSame(0, Vente::count());
    }

    #[Test]
    public function une_vente_ne_se_modifie_pas_par_la_synchronisation(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->vente($id, [$this->ligneBiere(1)])], $this->barman);

        $this->pousser([$this->operation('ventes', 'modification', $id, ['mode_paiement' => 'carte'])], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.modification_non_synchronisable'));

        $this->assertSame('especes', Vente::findOrFail($id)->mode_paiement);
    }

    // ------------------------------------------------------------- Helpers

    /**
     * @param  list<array<string, mixed>>  $lignes
     * @param  array<string, mixed>  $extra
     * @return array<string, mixed>
     */
    private function vente(
        string $id,
        array $lignes,
        string $cloture = '2026-10-14 21:30:00',
        ?string $session = 'session',
        array $extra = [],
    ): array {
        return $this->operationDatee('ventes', 'creation', $id, [
            'type_vente' => 'comptant',
            'mode_paiement' => 'especes',
            'session_encaissement_id' => $session === 'session' ? $this->session->id : $session,
            'cloture_le' => $cloture,
            'point_vente' => 'Bar',
            'lignes' => $lignes,
            ...$extra,
        ], str_replace(' ', 'T', $cloture) . '+00:00');
    }

    /**
     * @return array<string, mixed>
     */
    private function ligneBiere(int $quantite, int $prix = 1000): array
    {
        return [
            'module_source' => 'M5', 'code_article' => $this->biere->id, 'libelle' => 'Béninoise 65cl',
            'prix_unitaire' => $prix, 'quantite' => $quantite,
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function lignePlat(int $quantite): array
    {
        return [
            'module_source' => 'M4', 'code_article' => $this->platRiz->id, 'libelle' => 'Riz sauce arachide',
            'prix_unitaire' => 2500, 'quantite' => $quantite,
        ];
    }
}

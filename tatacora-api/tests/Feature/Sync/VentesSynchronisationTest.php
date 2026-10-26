<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Caisse\Services\SessionCaisseService;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use App\Domain\Restaurant\Exceptions\RecetteManquanteException;
use App\Domain\Restaurant\Models\CommandeRestaurant;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Stocks\Models\MouvementStock;
use App\Domain\Ventes\Models\LigneVente;
use App\Domain\Ventes\Models\Vente;
use App\Domain\Ventes\Services\VenteService;
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

    /**
     * Décision du PO du 15/10/2026 : un plat SANS composition (fiche vide,
     * aucun lien direct) ne fait pas rejeter une vente synchronisée. La vente
     * est écrite, ses autres lignes sortent leur stock, la ligne fautive n'en
     * sort aucun et l'anomalie `plat_sans_composition` est enregistrée — une
     * seule fois, même au rejeu. En ligne, la même vente reste refusée.
     */
    #[Test]
    public function un_plat_sans_composition_ne_fait_pas_rejeter_la_vente_mais_est_signale(): void
    {
        $ficheVide = Recette::create(['libelle' => 'Salade du jour', 'cout_matiere_calcule' => '0.00']);
        $salade = Plat::create([
            'menu_id' => $this->platRiz->menu_id, 'recette_id' => $ficheVide->id,
            'libelle' => 'Salade du jour', 'prix_vente' => '1500.00',
        ]);
        $id = $this->uuid();
        $operation = $this->vente($id, [
            $this->lignePlat(2),
            ['module_source' => 'M4', 'code_article' => $salade->id, 'prix_unitaire' => 1500, 'quantite' => 3],
            $this->ligneBiere(1),
        ]);

        $this->pousser([$operation], $this->gerant)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.montant_total', '10500.00')
            ->assertJsonPath('resultats.0.anomalies', [AnomalieSynchronisation::PLAT_SANS_COMPOSITION]);

        $vente = Vente::findOrFail($id);
        $this->assertSame(3, $vente->lignes()->count());
        // `assertEquals` : une colonne JSON ne garde pas l'ordre des clés.
        $this->assertEquals([[
            'ligne' => 'Salade du jour', 'module' => 'M4',
            'motif' => __('ventes.stock_non_sorti_plat_sans_composition', ['plat' => 'Salade du jour']),
            'cause' => 'plat_sans_composition', 'plat_id' => $salade->id, 'quantite' => 3,
        ]], $vente->stock_non_impacte);
        // Les autres lignes ont sorti leur stock.
        $this->assertSame('0.50', (string) MouvementStock::where('article_id', $this->articleRiz->id)->where('type_mouvement', 'sortie')->sole()->quantite);
        $this->assertSame(1, $this->nombreDeMouvements($this->articleBiere->id, 'sortie'));
        $this->assertDatabaseHas('anomalies_synchronisation', [
            'table_concernee' => 'ventes', 'entite_id' => $id,
            'type' => AnomalieSynchronisation::PLAT_SANS_COMPOSITION, 'reference' => $salade->id,
        ]);

        // Rejeu après purge : même document, aucune seconde anomalie.
        $this->purgerLaMemoireDIdempotence();
        $this->pousser([$this->nouvelleTentative($operation)], $this->gerant)
            ->assertJsonPath('resultats.0.document_deja_enregistre', true);
        $this->assertSame(1, AnomalieSynchronisation::where('type', AnomalieSynchronisation::PLAT_SANS_COMPOSITION)->count());

        // En ligne (sans `sansBonDeCuisine`), rien ne change : refusée.
        $this->expectException(RecetteManquanteException::class);
        $this->actingAs($this->gerant);
        app(VenteService::class)->enregistrer([
            'mode_paiement' => 'especes',
            'lignes' => [['module' => 'M4', 'reference_id' => $salade->id, 'quantite' => 1]],
        ]);
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

    /**
     * Lot F5 (décision PO du 17/10/2026) : la note de chambre monte, rattachée
     * à SA réservation — non encaissée, sans session, client et unité de la
     * réservation ; une réservation inconnue, ou un document incohérent
     * (note au comptoir, séjour encaissé), est refusé avec sa phrase.
     */
    #[Test]
    public function la_note_de_chambre_monte_rattachee_a_sa_reservation(): void
    {
        $categorie = \App\Domain\Hebergement\Models\CategorieHebergement::create(['libelle' => 'Bungalow', 'capacite_max' => 2, 'tarif_base' => '25000.00']);
        $unite = \App\Domain\Hebergement\Models\UniteHebergement::create(['categorie_id' => $categorie->id, 'numero' => 'B-07', 'statut' => 'libre']);
        $client = \App\Domain\Crm\Models\Client::create(['nom' => 'Sabi', 'telephone' => '96000003', 'type_client' => 'groupe']);
        $reservation = app(\App\Domain\Hebergement\Services\ReservationService::class)->creer([
            'client_id' => $client->id, 'unite_id' => $unite->id, 'date_arrivee' => '2026-10-14', 'date_depart' => '2026-10-16',
        ]);

        $id = $this->uuid();
        $this->pousser([$this->vente($id, [$this->ligneBiere(2)], extra: [
            'type_vente' => 'sur_sejour', 'mode_paiement' => 'note_chambre', 'reservation_id' => $reservation->id,
            'table' => 'ne compte pas',
        ])], $this->barman)->assertJsonPath('resultats.0.statut', 'synchronise');

        $vente = Vente::findOrFail($id);
        $this->assertSame('note_chambre', $vente->mode_paiement);
        $this->assertFalse((bool) $vente->encaisse);
        $this->assertNull($vente->session_id, 'une note de chambre n\'entre dans aucun tiroir');
        $this->assertSame($reservation->id, $vente->reservation_id);
        $this->assertSame($client->id, $vente->client_id);
        $this->assertSame('B-07', $vente->table);

        $refus = $this->pousser([
            $this->vente($this->uuid(), [$this->ligneBiere(1)], extra: [
                'type_vente' => 'sur_sejour', 'mode_paiement' => 'note_chambre', 'reservation_id' => $this->uuid(),
            ]),
            $this->vente($this->uuid(), [$this->ligneBiere(1)], extra: ['mode_paiement' => 'note_chambre']),
            $this->vente($this->uuid(), [$this->ligneBiere(1)], extra: ['type_vente' => 'sur_sejour', 'reservation_id' => $reservation->id]),
        ], $this->barman);
        $refus->assertJsonPath('resultats.0.motif', __('sync.ventes.reservation_inconnue'))
            ->assertJsonPath('resultats.1.motif', __('sync.ventes.note_chambre_incoherente'))
            ->assertJsonPath('resultats.2.motif', __('sync.ventes.note_chambre_incoherente'));

        $this->assertSame(1, Vente::count());
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

    /**
     * Lot F6 : l'annulation, par `VenteService::annuler` (contre-passation),
     * une fois ; une vente d'un AUTRE poste ne s'annule que par
     * l'administration ou le comptable (Q3).
     */
    #[Test]
    public function l_annulation_passe_par_le_service_et_suit_la_regle_des_autres_postes(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->vente($id, [$this->ligneBiere(2)])], $this->barman, 'poste-a');
        $annulation = fn (): array => $this->operation('ventes', 'modification', $id, ['statut' => 'annulee', 'motif' => 'Erreur de table']);

        $this->pousser([$annulation()], $this->barman, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.annulation_autre_poste'));
        $this->assertFalse(Vente::findOrFail($id)->estAnnulee());

        $this->pousser([$annulation()], $this->barman, 'poste-a')->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertTrue(Vente::findOrFail($id)->estAnnulee());
        $lignes = EcritureComptable::count();

        // Rejeu (autre uuid, plus tard) : rien n'est contre-passé deux fois.
        $this->travel(1)->minutes();
        $this->pousser([$annulation()], $this->barman, 'poste-a')->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame($lignes, EcritureComptable::count());
    }

    #[Test]
    public function l_administration_annule_la_vente_d_un_autre_poste_le_gerant_non(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->vente($id, [$this->ligneBiere(1)])], $this->barman, 'poste-a');

        $this->pousser([$this->operation('ventes', 'modification', $id, ['statut' => 'annulee', 'motif' => 'Doublon'])], $this->gerant, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'rejete');
        $this->pousser([$this->operation('ventes', 'modification', $id, ['statut' => 'annulee', 'motif' => 'Doublon'])], $this->creerUtilisateur('administrateur'), 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertTrue(Vente::findOrFail($id)->estAnnulee());
    }

    // ------------------------------------------------------------- Helpers

    /**
     * La remise du panier (21/10/2026) : le poste pousse le TYPE et la VALEUR
     * saisis, le serveur dérive le montant par `Panier::remiseSur` et encaisse
     * le NET — `montant_total`, pièce `VTE` (débit caisse) et théorique de
     * caisse.
     */
    #[Test]
    public function la_remise_en_pourcentage_est_appliquee_et_la_piece_passe_sur_le_net(): void
    {
        $id = $this->uuid();

        // 3 bières à 1 000 F = 3 000 F, 10 % de remise : 300 F, net 2 700 F.
        $this->pousser([$this->vente($id, [$this->ligneBiere(3)], extra: [
            'remise_type' => 'pourcentage', 'remise_valeur' => 10, 'montant_cloture' => 2700,
        ])], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.montant_total', '2700.00');

        $vente = Vente::findOrFail($id);
        $this->assertSame('2700.00', (string) $vente->montant_total);
        // Les lignes restent au prix brut figé.
        $this->assertSame('3000.00', (string) LigneVente::where('vente_id', $id)->sole()->montant);

        $piece = EcritureComptable::where('libelle', __('ventes.libelle_ecriture', ['numero' => $vente->numero]))->get();
        $caisse = CompteComptable::where('numero_compte', '5711')->value('id');
        $this->assertSame('2700.00', (string) $piece->firstWhere('compte_id', $caisse)?->debit);
    }

    #[Test]
    public function la_remise_en_montant_et_le_total_annonce_se_confrontent_au_net(): void
    {
        $id = $this->uuid();

        $this->pousser([$this->vente($id, [$this->ligneBiere(2)], extra: [
            'remise_type' => 'montant', 'remise_valeur' => 500, 'montant_cloture' => 1500,
        ])], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.montant_total', '1500.00');

        // Le total annonce le BRUT alors qu'une remise existe : incohérent, rejeté.
        $this->pousser([$this->vente($this->uuid(), [$this->ligneBiere(2)], extra: [
            'remise_type' => 'montant', 'remise_valeur' => 500, 'montant_cloture' => 2000,
        ])], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'rejete');
        $this->assertSame(1, Vente::count());
    }

    #[Test]
    public function une_remise_hors_bornes_est_rejetee_avec_la_phrase_du_serveur(): void
    {
        $this->pousser([$this->vente($this->uuid(), [$this->ligneBiere(1)], extra: [
            'remise_type' => 'montant', 'remise_valeur' => 5000,
        ])], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('ventes.remise_superieure_au_total'));

        $this->pousser([$this->vente($this->uuid(), [$this->ligneBiere(1)], extra: [
            'remise_type' => 'pourcentage', 'remise_valeur' => 120,
        ])], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('ventes.remise_pourcentage_hors_bornes'));

        $this->assertSame(0, Vente::count());
    }

    /**
     * Un pourcentage qui donne des centimes (10 % de 1 005 F = 100,50 F) : le
     * poste compte en francs entiers et annonce le net ARRONDI au franc ; le
     * serveur garde les centimes de SA formule.
     */
    #[Test]
    public function un_net_a_centimes_est_annonce_arrondi_au_franc_et_garde_ses_centimes(): void
    {
        $id = $this->uuid();

        $this->pousser([$this->vente($id, [$this->ligneBiere(1, prix: 1005)], extra: [
            'remise_type' => 'pourcentage', 'remise_valeur' => 10, 'montant_cloture' => 905,
        ])], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.montant_total', '904.50');
    }

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

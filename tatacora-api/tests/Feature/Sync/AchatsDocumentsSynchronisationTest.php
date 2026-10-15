<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Achats\Models\BonReception;
use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Stocks\Models\MouvementStock;
use App\Models\User;
use App\Shared\Sync\Models\AnomalieSynchronisation;
use App\Shared\Sync\Models\CorrespondanceSynchronisation;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PrepareLesDocuments;
use Tests\TestCase;

/**
 * Commandes d'achat et bons de réception saisis hors connexion — lot S3,
 * décisions du Product Owner du 15/10/2026 (les commandes d'achat sont dans
 * le périmètre ; les règlements de factures relèvent de la phase 2).
 *
 * Ordre de poussée : référentiels → commande → bon. Quantités du poste en
 * centièmes, prix en centimes ; règles et phrases des routes M7.
 */
final class AchatsDocumentsSynchronisationTest extends TestCase
{
    use PrepareLesDocuments;
    use RefreshDatabase;

    private User $acheteur;

    private Fournisseur $fournisseur;

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerLeDecor();

        // `achats` : M7 = 'C', le droit de `POST /achats/commandes`.
        $this->acheteur = $this->creerUtilisateur('achats');
        $this->fournisseur = Fournisseur::create(['raison_sociale' => 'Société Béninoise des Brasseries']);
    }

    // ------------------------------------------------------------ Commandes

    #[Test]
    public function la_commande_est_creee_par_le_service_sous_l_uuid_du_poste(): void
    {
        $id = $this->uuid();

        $this->pousser([$this->commande($id)], $this->acheteur)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.entite_id', $id)
            ->assertJsonPath('resultats.0.statut_commande', 'envoyee')
            ->assertJsonPath('resultats.0.montant_total', '24000.00');

        $commande = CommandeAchat::with('lignes')->findOrFail($id);
        $this->assertSame('2026-10-10', $commande->date_commande->toDateString());
        // Auteur : le titulaire du jeton (RG-15).
        $this->assertSame($this->acheteur->id, $commande->utilisateur_id);
        $this->assertSame('24.00', (string) $commande->lignes->sole()->quantite_commandee);
        $this->assertSame('1000.00', (string) $commande->lignes->sole()->prix_unitaire);
        // Une commande n'engage ni stock ni écriture : rien d'autre n'est écrit.
        $this->assertSame(1, $this->nombreDeMouvements($this->articleBiere->id, 'entree'), 'seul le stock initial');
    }

    /**
     * Un statut que le poste a DÉRIVÉ de ses propres réceptions n'est pas
     * saisissable au serveur : il monte comme « envoyee », et c'est le bon
     * synchronisé qui le fera avancer.
     */
    #[Test]
    public function un_statut_derive_du_poste_monte_comme_envoyee(): void
    {
        $id = $this->uuid();

        $this->pousser([$this->commande($id, ['statut' => 'receptionnee'])], $this->acheteur)
            ->assertJsonPath('resultats.0.statut_commande', 'envoyee');
    }

    #[Test]
    public function fournisseur_et_articles_cites_passent_par_les_correspondances(): void
    {
        $idPosteFournisseur = $this->uuid();
        $idPosteArticle = $this->uuid();
        CorrespondanceSynchronisation::create([
            'poste_id' => 'poste-windows-1', 'table_concernee' => 'fournisseurs', 'id_poste' => $idPosteFournisseur, 'id_serveur' => $this->fournisseur->id,
        ]);
        CorrespondanceSynchronisation::create([
            'poste_id' => 'poste-windows-1', 'table_concernee' => 'articles', 'id_poste' => $idPosteArticle, 'id_serveur' => $this->articleBiere->id,
        ]);

        $id = $this->uuid();
        $this->pousser([$this->commande($id, [
            'fournisseur_id' => $idPosteFournisseur,
            'lignes' => [['article_id' => $idPosteArticle, 'quantite_centiemes' => 1000, 'prix_unitaire_centimes' => 50000]],
        ])], $this->acheteur)->assertJsonPath('resultats.0.statut', 'synchronise');

        $commande = CommandeAchat::with('lignes')->findOrFail($id);
        $this->assertSame($this->fournisseur->id, $commande->fournisseur_id);
        $this->assertSame($this->articleBiere->id, $commande->lignes->sole()->article_id);
    }

    #[Test]
    public function une_commande_invalide_est_rejetee_avec_les_phrases_de_l_api(): void
    {
        $reponse = $this->pousser([
            $this->commande($this->uuid(), ['fournisseur_id' => $this->uuid()]),
            $this->commande($this->uuid(), ['lignes' => []]),
            $this->commande($this->uuid(), ['lignes' => [
                ['article_id' => $this->articleBiere->id, 'quantite_centiemes' => 0, 'prix_unitaire_centimes' => 100],
            ]]),
            $this->commande($this->uuid(), ['montant_total' => '999']),
        ], $this->acheteur);

        $reponse->assertJsonPath('resultats.0.motif', __('achats.validation.fournisseur_inexistant'))
            ->assertJsonPath('resultats.1.motif', __('achats.validation.lignes_obligatoires'))
            ->assertJsonPath('resultats.2.motif', __('achats.validation.quantite_positive'))
            ->assertJsonPath('resultats.3.motif', __('achats.validation.valeur_calculee'));

        $this->assertSame(0, CommandeAchat::count());
    }

    #[Test]
    public function une_commande_rejouee_n_est_creee_qu_une_fois_et_ne_se_modifie_pas(): void
    {
        $operation = $this->commande($this->uuid());

        $this->pousser([$operation], $this->acheteur);
        $this->purgerLaMemoireDIdempotence();
        $this->pousser([$this->nouvelleTentative($operation)], $this->acheteur)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.document_deja_enregistre', true);

        $this->assertSame(1, CommandeAchat::count());

        // Ni modification ni annulation : le service n'en offre pas.
        $this->pousser([$this->operation('commandes_achat', 'modification', $operation['entite_id'], ['statut' => 'cloturee'])], $this->acheteur)
            ->assertJsonPath('resultats.0.motif', __('sync.modification_non_synchronisable'));
        $this->assertSame('envoyee', CommandeAchat::findOrFail($operation['entite_id'])->statut);
    }

    #[Test]
    public function sans_ecriture_sur_m7_aucun_document_d_achat_n_est_synchronise(): void
    {
        $barman = $this->creerUtilisateur('barman');

        $this->pousser([$this->commande($this->uuid())], $barman)
            ->assertJsonPath('resultats.0.motif', __('auth.module_refuse'));
        $this->pousser([$this->bon($this->uuid(), $this->uuid())], $barman)
            ->assertJsonPath('resultats.0.motif', __('auth.module_refuse'));

        $this->assertDatabaseHas('journal_securite', ['utilisateur_id' => $barman->id, 'module_concerne' => 'M7']);
    }

    // ------------------------------------------------------------ Bons de réception

    #[Test]
    public function le_bon_entre_le_stock_a_la_date_de_reception_et_recalcule_la_conformite(): void
    {
        $this->toleranceDeReception('2');
        $commande = $this->uuid();
        $bon = $this->uuid();

        $reponse = $this->pousser([
            $this->commande($commande),
            // Le poste a jugé « totale » une livraison de 20 sur 24 : le
            // serveur, sur SA tolérance (2 %), dit « partielle ».
            $this->bon($bon, $commande, quantiteCentiemes: 2000, conformite: 'totale'),
        ], $this->acheteur);

        $reponse->assertJsonPath('resultats.1.statut', 'synchronise')
            ->assertJsonPath('resultats.1.conformite', 'partielle')
            ->assertJsonPath('resultats.1.conformite_poste', 'totale')
            ->assertJsonPath('resultats.1.statut_commande', 'receptionnee_partiellement');

        $this->assertSame('2026-10-13', BonReception::findOrFail($bon)->date_reception->toDateString());
        $entree = MouvementStock::where('article_id', $this->articleBiere->id)->where('type_mouvement', 'entree')
            ->where('motif', 'like', '%' . $bon . '%')->sole();
        $this->assertSame('20.00', (string) $entree->quantite);
        $this->assertSame('2026-10-13', $entree->date_mouvement->toDateString());
        $this->assertDatabaseHas('anomalies_synchronisation', [
            'table_concernee' => 'bons_reception', 'entite_id' => $bon, 'type' => AnomalieSynchronisation::ECART_CONFORMITE_RECEPTION,
        ]);
    }

    #[Test]
    public function sans_tolerance_parametree_le_bon_est_refuse_avec_son_motif(): void
    {
        $commande = $this->uuid();

        $this->pousser([$this->commande($commande), $this->bon($this->uuid(), $commande)], $this->acheteur)
            ->assertJsonPath('resultats.1.statut', 'rejete')
            ->assertJsonPath('resultats.1.motif', __('achats.tolerance_absente', ['cle' => 'tolerance_reception_pct']));

        $this->assertSame(0, BonReception::count());
    }

    #[Test]
    public function un_bon_sur_une_commande_inconnue_est_refuse(): void
    {
        $this->toleranceDeReception('2');

        $this->pousser([$this->bon($this->uuid(), $this->uuid())], $this->acheteur)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.receptions.commande_inconnue'));
    }

    #[Test]
    public function le_rejeu_d_un_bon_n_entre_jamais_deux_fois_le_stock(): void
    {
        $this->toleranceDeReception('2');
        $commande = $this->commande($this->uuid());
        $bon = $this->bon($this->uuid(), $commande['entite_id']);

        $this->pousser([$commande, $bon], $this->acheteur)->assertJsonPath('resultats.1.conformite', 'totale');
        $this->pousser([$bon], $this->acheteur)->assertJsonPath('resultats.0.rejeu_idempotent', true);

        $this->purgerLaMemoireDIdempotence();

        // La commande est désormais « receptionnee » : sans l'idempotence du
        // service AVANT ses contrôles, le rejeu serait refusé comme un bon neuf.
        $this->pousser([$this->nouvelleTentative($bon)], $this->acheteur)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.document_deja_enregistre', true);

        $this->assertSame(1, BonReception::count());
        $this->assertSame(2, $this->nombreDeMouvements($this->articleBiere->id, 'entree'), 'stock initial + UNE réception');
    }

    /**
     * @param  array<string, mixed>  $surcharges
     * @return array<string, mixed>
     */
    private function commande(string $id, array $surcharges = []): array
    {
        return $this->operationDatee('commandes_achat', 'creation', $id, [
            'fournisseur_id' => $this->fournisseur->id,
            'date_commande' => '2026-10-10',
            'statut' => 'envoyee',
            'lignes' => [[
                'article_id' => $this->articleBiere->id, 'article_libelle' => 'Bière 65cl', 'unite_mesure' => 'bouteille',
                'quantite_centiemes' => 2400, 'prix_unitaire_centimes' => 100000, 'rang' => 1,
            ]],
            ...$surcharges,
        ], '2026-10-10T08:00:00+00:00');
    }

    /**
     * @return array<string, mixed>
     */
    private function bon(string $id, string $commandeId, int $quantiteCentiemes = 2400, ?string $conformite = null): array
    {
        return $this->operationDatee('bons_reception', 'creation', $id, [
            'commande_id' => $commandeId,
            'date_reception' => '2026-10-13',
            'point_stockage_id' => $this->bar->id,
            ...($conformite !== null ? ['conformite' => $conformite] : []),
            'lignes' => [['article_id' => $this->articleBiere->id, 'quantite_centiemes' => $quantiteCentiemes]],
        ], '2026-10-13T10:00:00+00:00');
    }
}

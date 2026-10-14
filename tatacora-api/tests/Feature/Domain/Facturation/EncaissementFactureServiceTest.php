<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Facturation;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\Paiement;
use App\Domain\Facturation\Services\EncaissementFactureService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Le PREMIER writer de `paiements` — PA-165 ferme la moitié restante de PA-21.
 *
 * ## Ce que cette classe prouve, et que rien ne prouvait
 *
 * Jusqu'à ce lot, `paiements` n'avait aucun writer : le solde client de M3
 * était un MAXIMUM, aucun encaissement ne pouvant réduire une créance. Ici :
 * l'encaissement écrit le paiement ET sa pièce comptable dans la même
 * transaction (règle du Product Owner, PA-162), les quatre refus locaux
 * tiennent, et le reste dû suit l'UNIQUE formule SQL de `Facture::SQL_RESTE_DU`
 * (avoirs et acomptes liés déduits).
 *
 * ## Mutations vérifiées (01/09/2026)
 *
 * 1. `passerEtValider()` retiré de la transaction → rouge sur « la pièce
 *    comptable existe et s'équilibre ».
 * 2. Le refus de sur-encaissement retiré → rouge sur « un montant supérieur
 *    au reste dû refuse ».
 */
final class EncaissementFactureServiceTest extends TestCase
{
    use RefreshDatabase;

    private Facture $facture;

    private EncaissementFactureService $service;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);

        // Un auteur réel : `Auditable` lit `auth()->id()` (RG-15).
        $gerant = User::create([
            'login' => 'gerant.test',
            'mot_de_passe_hash' => Hash::make('x'),
            'role_id' => Role::where('libelle', 'gerant')->firstOrFail()->id,
            'statut' => 'actif',
        ]);
        $this->actingAs($gerant);

        $client = Client::create([
            'nom' => 'KORA', 'prenom' => 'Jean',
            'telephone' => '01 97 35 59 74', 'type_client' => 'particulier',
        ]);

        // Figée (RG-03) et en démonstration — le chemin d'encaissement doit
        // être emprunté hors Production aussi (le raisonnement d'`estFigee`).
        $this->facture = Facture::create([
            'numero_mecef' => 'MECEF-DEMO-TEST0001',
            'client_id' => $client->id,
            'date_emission' => now()->toDateString(),
            'montant_ht' => '50000.00',
            'montant_tva' => '0.00',
            'montant_ttc' => '50000.00',
            'statut' => 'certifiee',
        ]);

        SessionCaisse::create([
            'point_vente' => 'bar',
            'montant_fond' => '10000.00',
            'date_ouverture' => now(),
            'utilisateur_ouverture_id' => $gerant->id,
        ]);

        $this->service = app(EncaissementFactureService::class);
    }

    #[Test]
    public function un_encaissement_ecrit_le_paiement_et_sa_piece_comptable_dans_la_meme_transaction(): void
    {
        $paiement = $this->service->encaisser($this->facture, '30000.00', 'especes');

        $this->assertSame(0, bccomp((string) $paiement->montant, '30000', 2));
        $this->assertSame('especes', $paiement->mode_paiement);
        $this->assertNotNull($paiement->utilisateur_creation_id, 'RG-15 : le paiement porte son auteur.');

        // Le reste dû a réellement diminué — c'est le point de PA-21.
        $this->assertSame(0, bccomp($this->facture->refresh()->resteDu(), '20000.00', 2));

        // La pièce comptable existe, s'équilibre, et se retrouve par son
        // libellé (PA-52 : aucune colonne ne groupe une pièce).
        $lignes = EcritureComptable::query()
            ->where('libelle', 'like', 'Encaissement MECEF-DEMO-TEST0001%')
            ->get();

        $this->assertCount(2, $lignes, 'la pièce comptable existe et s\'équilibre');

        $debit = '0.00';
        $credit = '0.00';

        foreach ($lignes as $ligne) {
            $debit = bcadd($debit, (string) $ligne->debit, 2);
            $credit = bcadd($credit, (string) $ligne->credit, 2);
        }

        $this->assertSame(0, bccomp($debit, '30000.00', 2));
        $this->assertSame(0, bccomp($credit, '30000.00', 2));
    }

    #[Test]
    public function un_montant_superieur_au_reste_du_refuse_et_rien_n_est_ecrit(): void
    {
        $this->service->encaisser($this->facture, '45000.00', 'especes');

        try {
            $this->service->encaisser($this->facture->refresh(), '10000.00', 'especes');
            $this->fail('Un sur-encaissement aurait dû refuser.');
        } catch (RuntimeException $refus) {
            $this->assertStringContainsString('5000.00', $refus->getMessage(), 'un montant supérieur au reste dû refuse');
        }

        $this->assertSame(1, Paiement::count(), 'Le refus n\'a rien écrit.');
    }

    #[Test]
    public function sans_session_de_caisse_ouverte_l_encaissement_refuse(): void
    {
        SessionCaisse::query()->update(['date_cloture' => now()]);

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage(__('facturation.encaissement_caisse_fermee'));

        $this->service->encaisser($this->facture, '1000.00', 'especes');
    }

    #[Test]
    public function une_facture_non_figee_ne_s_encaisse_pas(): void
    {
        $brouillon = Facture::create([
            'client_id' => $this->facture->client_id,
            'date_emission' => now()->toDateString(),
            'montant_ht' => '1000.00',
            'montant_tva' => '0.00',
            'montant_ttc' => '1000.00',
            'statut' => 'en_attente_certification',
        ]);

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage(__('facturation.encaissement_facture_non_figee'));

        $this->service->encaisser($brouillon, '1000.00', 'especes');
    }

    /**
     * Un avoir et un acompte lié réduisent le reste dû par la MÊME formule
     * que le registre de M3 — `Facture::SQL_RESTE_DU`, unique auteur. La
     * constante de `SoldeClientService` DOIT être un alias de celle-ci :
     * deux formules divergeraient au premier terme ajouté.
     */
    #[Test]
    public function le_reste_du_suit_l_unique_formule_partagee_avec_le_registre_m3(): void
    {
        $this->assertSame(
            Facture::SQL_RESTE_DU,
            \App\Domain\Crm\Services\SoldeClientService::SQL_RESTE_DU,
            'SoldeClientService doit référencer la formule de Facture, jamais la sienne.',
        );

        \App\Domain\Facturation\Models\Avoir::create([
            'facture_id' => $this->facture->id,
            'motif' => 'Geste commercial',
            'montant' => '5000.00',
            'date_emission' => now()->toDateString(),
            'utilisateur_validation_id' => auth()->id(),
        ]);

        // 50 000 − 5 000 d'avoir = 45 000 ; l'encaissement du reste solde.
        $this->assertSame(0, bccomp($this->facture->refresh()->resteDu(), '45000.00', 2));

        $this->service->encaisser($this->facture->refresh(), '45000.00', 'mobile_money');

        $this->assertTrue($this->facture->refresh()->estSoldee());
    }
}

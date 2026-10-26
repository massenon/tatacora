<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Ventes;

use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Tourisme\Models\Circuit;
use App\Domain\Vehicules\Models\Vehicule;
use App\Domain\Ventes\Models\LigneVente;
use App\Domain\Ventes\Models\Vente;
use App\Domain\Ventes\Services\PanierService;
use App\Domain\Ventes\Services\VenteService;
use App\Models\User;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Tourisme (M9) et location de véhicules (M8) sont ENCAISSABLES au comptoir
 * (directive du PO du 22/10/2026) : le prix et le libellé sont figés depuis
 * `circuits.prix` et `vehicules.tarif_jour`, jamais saisis ; la pièce `VTE`
 * crédite le bon compte de produits ; aucune sortie de stock.
 *
 * Comptes : M9 sur 7061 « services vendus » (le plan du PO n'a pas de compte
 * dédié aux circuits), M8 sur 7073 « Locations » ; TVA des deux sur 4432
 * (prestations de services) ; centres « Tourisme » et « Véhicules ».
 */
final class VenteTourismeLocationTest extends TestCase
{
    use RefreshDatabase;

    private VenteService $ventes;

    private Circuit $circuit;

    private Vehicule $vehicule;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);

        $this->ventes = app(VenteService::class);

        $this->actingAs(User::create([
            'login' => 'gerant.'.Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'gerant')->firstOrFail()->id,
            'statut' => 'actif',
        ]));

        $this->circuit = Circuit::create([
            'nom' => 'Cascades de Kota',
            'theme' => 'nature',
            'zone' => 'Atacora',
            'duree' => '1 jour',
            'prix' => '15000.00',
            'capacite_max' => 12,
        ]);

        $this->vehicule = Vehicule::create([
            'categorie' => '4x4',
            'immatriculation' => 'AB-123-CD',
            'annee' => 2022,
            'transmission' => 'automatique',
            'capacite' => 5,
            'tarif_jour' => '65000.00',
            'statut' => 'disponible',
        ]);
    }

    #[Test]
    public function un_circuit_et_un_vehicule_s_encaissent_aux_prix_du_catalogue(): void
    {
        $vente = $this->ventes->enregistrer([
            'point_vente' => 'Bar',
            'mode_paiement' => 'especes',
            'lignes' => [
                ['module' => 'M9', 'reference_id' => $this->circuit->id, 'quantite' => 4],
                ['module' => 'M8', 'reference_id' => $this->vehicule->id, 'quantite' => 2],
            ],
        ]);

        // 4 x 15 000 + 2 x 65 000.
        $this->assertSame('190000.00', (string) $vente->montant_total);

        $lignes = LigneVente::where('vente_id', $vente->id)->get()->keyBy('module');
        $this->assertSame('15000.00', (string) $lignes['M9']->prix_unitaire);
        $this->assertSame('Cascades de Kota', $lignes['M9']->nom);
        $this->assertSame('65000.00', (string) $lignes['M8']->prix_unitaire);
        $this->assertStringContainsString('AB-123-CD', $lignes['M8']->nom);
    }

    #[Test]
    public function la_piece_credite_7061_pour_le_tourisme_et_7073_pour_la_location_avec_leur_centre(): void
    {
        $vente = $this->ventes->enregistrer([
            'mode_paiement' => 'especes',
            'lignes' => [
                ['module' => 'M9', 'reference_id' => $this->circuit->id, 'quantite' => 1],
                ['module' => 'M8', 'reference_id' => $this->vehicule->id, 'quantite' => 1],
            ],
        ]);

        $piece = $this->piece($vente);

        $this->assertSame('15000.00', $this->credit($piece, '7061'));
        $this->assertSame('65000.00', $this->credit($piece, '7073'));
        $this->assertSame('80000.00', $this->debit($piece, '5711'));

        $centres = $piece->mapWithKeys(fn (EcritureComptable $e): array => [
            CompteComptable::findOrFail($e->compte_id)->numero_compte => optional($e->centre)->libelle,
        ]);
        $this->assertSame('Tourisme', $centres['7061']);
        $this->assertSame('Véhicules', $centres['7073']);
    }

    #[Test]
    public function la_tva_des_prestations_se_credite_sur_4432_et_la_piece_s_equilibre(): void
    {
        foreach ([
            CalculTvaService::CLE_PARAMETRE_TAUX => '18.00',
            CalculTvaService::CLE_PARAMETRE_ACTIVE => 'true',
            CalculTvaService::CLE_PARAMETRE_CONVENTION => 'ttc',
        ] as $cle => $valeur) {
            ParametreSysteme::updateOrCreate(['cle' => $cle], ['valeur' => $valeur]);
        }

        $vente = $this->ventes->enregistrer([
            'mode_paiement' => 'mobile_money',
            'lignes' => [
                ['module' => 'M9', 'reference_id' => $this->circuit->id, 'quantite' => 1],
                ['module' => 'M8', 'reference_id' => $this->vehicule->id, 'quantite' => 1],
            ],
        ]);

        $piece = $this->piece($vente);

        // 15 000 TTC : HT 12 711,86 + TVA 2 288,14 ; 65 000 TTC : HT 55 084,75 + TVA 9 915,25.
        $this->assertSame('12711.86', $this->credit($piece, '7061'));
        $this->assertSame('55084.75', $this->credit($piece, '7073'));
        $this->assertSame('12203.39', $this->credit($piece, '4432'));

        $debit = '0.00';
        $credit = '0.00';
        foreach ($piece as $ecriture) {
            $debit = bcadd($debit, (string) $ecriture->debit, 2);
            $credit = bcadd($credit, (string) $ecriture->credit, 2);
        }
        $this->assertSame('80000.00', $debit);
        $this->assertSame($debit, $credit);
    }

    #[Test]
    public function une_reference_inconnue_de_location_ou_de_tourisme_est_refusee(): void
    {
        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessageMatches('/introuvable/');

        $this->ventes->enregistrer([
            'lignes' => [['module' => 'M9', 'reference_id' => (string) Str::uuid(), 'quantite' => 1]],
        ]);
    }

    #[Test]
    public function l_hebergement_reste_non_encaissable_au_comptoir(): void
    {
        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessageMatches('/Hébergement/');

        $this->ventes->enregistrer([
            'lignes' => [['module' => 'M1', 'reference_id' => (string) Str::uuid(), 'quantite' => 1]],
        ]);
    }

    #[Test]
    public function aucune_sortie_de_stock_n_est_produite_et_l_annulation_contrepasse_la_piece(): void
    {
        $vente = $this->ventes->enregistrer([
            'mode_paiement' => 'especes',
            'lignes' => [['module' => 'M8', 'reference_id' => $this->vehicule->id, 'quantite' => 1]],
        ]);

        $this->assertSame([], $vente->stock_non_impacte ?? []);
        $this->assertSame(0, \App\Domain\Stocks\Models\MouvementStock::count());

        $this->ventes->annuler($vente, 'Erreur de saisie');

        $this->assertSame('annulee', $vente->fresh()->statut);
        $this->assertSame(0, \App\Domain\Stocks\Models\MouvementStock::count());
    }

    #[Test]
    public function le_panier_porte_un_circuit_et_un_vehicule_aux_prix_figes(): void
    {
        $paniers = app(PanierService::class);
        $panier = $paniers->ouvrirPourPoste('Bar', null);

        $paniers->ajouterLigne($panier, 'M9', $this->circuit->id, 3);
        $paniers->ajouterLigne($panier, 'M8', $this->vehicule->id);

        $panier = $panier->fresh('lignes');
        $this->assertSame('110000.00', $panier->total());

        $lignes = $paniers->lignesPourVente($panier);
        $this->assertCount(2, $lignes);
        $this->assertEqualsCanonicalizing(['M8', 'M9'], array_column($lignes, 'module'));
    }

    /**
     * @return \Illuminate\Database\Eloquent\Collection<int, EcritureComptable>
     */
    private function piece(Vente $vente): \Illuminate\Database\Eloquent\Collection
    {
        return EcritureComptable::where('libelle', 'Vente '.$vente->numero)
            ->whereNull('ecriture_contrepassee_id')
            ->get();
    }

    private function credit(\Illuminate\Database\Eloquent\Collection $piece, string $numero): string
    {
        return $this->ligne($piece, $numero)->credit;
    }

    private function debit(\Illuminate\Database\Eloquent\Collection $piece, string $numero): string
    {
        return $this->ligne($piece, $numero)->debit;
    }

    private function ligne(\Illuminate\Database\Eloquent\Collection $piece, string $numero): EcritureComptable
    {
        foreach ($piece as $ecriture) {
            if (CompteComptable::findOrFail($ecriture->compte_id)->numero_compte === $numero) {
                return $ecriture;
            }
        }

        $this->fail("La pièce ne porte aucune ligne sur le compte {$numero}.");
    }
}

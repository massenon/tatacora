<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Crm;

use App\Domain\Crm\Models\Client;
use App\Domain\Crm\Services\SoldeClientService;
use App\Domain\TableauxDeBord\Data\Periode;
use App\Domain\TableauxDeBord\Services\TableauDeBordService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Solde client calcule — EF-M3-04, PA-126.
 *
 * Le predicat « facture impayee » est LA source unique (PA-121) : ces cas
 * verifient qu'il rend le meme perimetre pour le solde par client (M3) et
 * pour le compteur du tableau de bord (M11), et que la colonne morte
 * `clients.solde` n'influence JAMAIS le resultat.
 */
final class SoldeClientServiceTest extends TestCase
{
    use RefreshDatabase;

    private SoldeClientService $service;

    private ?string $sessionCaisseId = null;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->actingAs(User::create([
            'login' => 'compte.gerant',
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'gerant')->firstOrFail()->id,
            'statut' => 'actif',
        ]));

        $this->service = app(SoldeClientService::class);
    }

    #[Test]
    public function le_solde_d_un_client_est_la_somme_des_restes_dus_de_ses_factures_certifiees(): void
    {
        $client = $this->client('KORA', 'Jean');

        // 10 000 dont 4 000 payes -> reste 6 000 ; 2 000 sans paiement.
        $facture = $this->facture($client, '10000.00');
        $this->paiement($facture, '4000.00');
        $this->facture($client, '2000.00');

        $ligne = collect($this->service->registre())->firstWhere('id', $client->id);

        $this->assertNotNull($ligne);
        $this->assertSame('8000.00', $ligne->solde);
        $this->assertSame(2, $ligne->pieces);
    }

    #[Test]
    public function une_facture_soldee_ou_non_certifiee_n_entre_pas_dans_le_solde(): void
    {
        $client = $this->client('NABOGOU', 'Awa');

        // Entierement payee : plus une creance.
        $payee = $this->facture($client, '5000.00');
        $this->paiement($payee, '5000.00');

        // Brouillon et en attente : pas encore opposables — le predicat du
        // tableau de bord, conserve tel quel (PA-49).
        $this->facture($client, '7000.00', 'brouillon');
        $this->facture($client, '9000.00', 'en_attente_certification');

        $ligne = collect($this->service->registre())->firstWhere('id', $client->id);

        $this->assertNotNull($ligne);
        $this->assertSame('0.00', $ligne->solde);
        $this->assertSame(0, $ligne->pieces);
    }

    /**
     * PA-126 — la colonne `clients.solde` que RIEN n'ecrit ne doit JAMAIS
     * etre lue. On la falsifie deliberement : si le service la lisait, ce cas
     * rougirait avec « 999999.99 » a la place du calcul.
     */
    #[Test]
    public function la_colonne_morte_clients_solde_n_influence_jamais_le_resultat(): void
    {
        $client = $this->client('SANNI', 'Rachidatou');
        $this->facture($client, '3000.00');

        DB::table('clients')->where('id', $client->id)->update(['solde' => '999999.99']);

        $ligne = collect($this->service->registre())->firstWhere('id', $client->id);

        $this->assertNotNull($ligne);
        $this->assertSame('3000.00', $ligne->solde);
        $this->assertSame('3000.00', $this->service->totaux()['total_du']);
    }

    /**
     * PA-121 — UNE formule pour la meme grandeur. Le compteur M11 et le
     * registre M3 doivent designer exactement les memes pieces : une facture
     * qui sort de l'un doit sortir de l'autre.
     */
    #[Test]
    public function le_tableau_de_bord_et_le_solde_client_partagent_le_meme_predicat(): void
    {
        $client = $this->client('BONI', 'Charlemagne');

        $impayee = $this->facture($client, '12000.00');
        $payee = $this->facture($client, '4000.00');
        $this->paiement($payee, '4000.00');
        $this->facture($client, '1000.00', 'brouillon');

        $tableauDeBord = app(TableauDeBordService::class);
        $periode = Periode::depuisCode(Periode::TRENTE_JOURS);

        $this->assertSame(1, $tableauDeBord->facturesImpayees($periode));

        $ligne = collect($this->service->registre())->firstWhere('id', $client->id);
        $this->assertNotNull($ligne);
        $this->assertSame(1, $ligne->pieces);
        $this->assertSame('12000.00', $ligne->solde);

        // Solder la piece fait tomber LES DEUX compteurs — c'est le sens de
        // la source unique : ils ne peuvent pas diverger.
        $this->paiement($impayee, '12000.00');

        $this->assertSame(0, $tableauDeBord->facturesImpayees($periode));
        $this->assertSame(0, collect($this->service->registre())->firstWhere('id', $client->id)?->pieces);
    }

    #[Test]
    public function le_registre_trie_par_solde_decroissant_et_filtre_par_etat(): void
    {
        $petit = $this->client('AJAVON', 'Berthe');
        $gros = $this->client('ZINSOU', 'Cosme');
        $sansDette = $this->client('DOSSOU', 'Marius');

        $this->facture($petit, '2000.00');
        $this->facture($gros, '50000.00');

        $tous = collect($this->service->registre());

        // Tri du maitre : solde decroissant, puis nom — le sans-dette ferme
        // la marche, present au registre (la liste montre TOUT le
        // referentiel).
        $this->assertSame(
            [$gros->id, $petit->id, $sansDette->id],
            $tous->pluck('id')->all(),
        );

        $this->assertSame(
            [$gros->id, $petit->id],
            collect($this->service->registre(null, 'debiteur'))->pluck('id')->all(),
        );
        $this->assertSame(
            [$sansDette->id],
            collect($this->service->registre(null, 'solde'))->pluck('id')->all(),
        );

        // Le filtre de recherche porte sur nom, prenom et telephone.
        $this->assertSame(
            [$gros->id],
            collect($this->service->registre('ZINSOU'))->pluck('id')->all(),
        );
    }

    #[Test]
    public function les_totaux_portent_sur_le_registre_entier(): void
    {
        $a = $this->client('GNANSOUNOU', 'Felicien');
        $b = $this->client('HOUNGBEDJI', 'Perpetue');

        $this->facture($a, '10000.00');
        $partielle = $this->facture($b, '8000.00');
        $this->paiement($partielle, '3000.00');

        $totaux = $this->service->totaux();

        $this->assertSame('15000.00', $totaux['total_du']);
        $this->assertSame(2, $totaux['nb_pieces']);
        $this->assertSame(2, $totaux['nb_clients']);
    }

    /* ----------------------------------------------------- auxiliaires */

    private function client(string $nom, string $prenom): Client
    {
        return Client::create([
            'nom' => $nom,
            'prenom' => $prenom,
            'telephone' => '01 90 ' . str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT),
            'type_client' => 'particulier',
        ]);
    }

    private function facture(Client $client, string $montant, string $statut = 'certifiee'): string
    {
        $id = (string) Str::uuid();

        DB::table('factures')->insert([
            'id' => $id,
            'client_id' => $client->id,
            'date_emission' => now()->subDays(3)->toDateString(),
            'montant_ht' => $montant, 'montant_tva' => '0.00', 'montant_ttc' => $montant,
            'statut' => $statut,
            'numero_mecef' => $statut === 'certifiee' ? 'MECEF-TEST-' . Str::random(6) : null,
            'utilisateur_creation_id' => auth()->id(),
            'date_creation' => now(), 'created_at' => now(), 'updated_at' => now(),
        ]);

        return $id;
    }

    /**
     * `paiements.session_id` est NOT NULL au schema : un encaissement
     * appartient toujours a une session de caisse — respecte tel quel, jamais
     * contourne pour arranger un test.
     */
    private function sessionCaisse(): string
    {
        if ($this->sessionCaisseId === null) {
            $this->sessionCaisseId = (string) Str::uuid();

            DB::table('sessions_caisse')->insert([
                'id' => $this->sessionCaisseId,
                'point_vente' => 'reception',
                'utilisateur_ouverture_id' => auth()->id(),
                'date_ouverture' => now()->subDays(10),
                'montant_fond' => '10000.00',
            ]);
        }

        return $this->sessionCaisseId;
    }

    private function paiement(string $factureId, string $montant): void
    {
        DB::table('paiements')->insert([
            'id' => (string) Str::uuid(),
            'facture_id' => $factureId,
            'session_id' => $this->sessionCaisse(),
            'mode_paiement' => 'especes',
            'montant' => $montant,
            'date_paiement' => now()->subDays(2),
            'utilisateur_creation_id' => auth()->id(),
            'date_creation' => now(), 'created_at' => now(), 'updated_at' => now(),
        ]);
    }
}

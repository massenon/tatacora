<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Models\Avoir;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Services\MecefClientInterface;
use App\Models\User;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PrepareLesDocuments;
use Tests\TestCase;

/**
 * La NORMALISATION faite par le boîtier d'un poste, rangée par le serveur
 * (07/11/2026, lot 2) : le serveur RANGE le résultat — numéro fiscal, QR, statut,
 * voie, compteur — sans re-certifier et sans JAMAIS appeler le boîtier ni la DGI ;
 * une pièce normalisée n'est jamais écrasée ; l'avoir a sa propre identité.
 */
final class NormalisationFactureSynchronisationTest extends TestCase
{
    use PrepareLesDocuments;
    use RefreshDatabase;

    private const QR = 'F;ED04000623;NW34NID6ZHANFNMZ2IU7LL3H;3201910768821;20261107100000';

    private User $receptionniste;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-11-07 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->receptionniste = $this->creerUtilisateur('receptionniste');
        Client::create(['nom' => 'Sabi', 'telephone' => '96000003', 'type_client' => 'groupe']);
        // Le serveur n'appelle JAMAIS le réseau pour ranger une normalisation.
        Http::preventStrayRequests();
    }

    private function factureDe10000(): string
    {
        $id = $this->uuid();
        $this->pousser([$this->operationDatee('factures', 'creation', $id, [
            'origine' => 'facture_directe', 'date_emission' => '2026-11-07',
            'lignes' => [['module' => 'M5', 'libelle' => 'Bière', 'prix_unitaire' => 5000, 'quantite' => 2]],
        ], '2026-11-07T09:00:00+00:00')], $this->receptionniste, 'poste-a')->assertJsonPath('resultats.0.statut', 'synchronise');

        return $id;
    }

    /** @return array<string, mixed> */
    private function normalisee(string $numero = 'ED04000623-41'): array
    {
        return [
            'statut' => 'normalisee', 'mode' => 'boitier', 'numero_mecef' => $numero, 'qr_code' => self::QR,
            'code_mecef' => 'NW34NID6ZHANFNMZ2IU7LL3H', 'compteur' => '41', 'date' => '2026-11-07T10:00:00+01:00',
        ];
    }

    #[Test]
    public function une_normalisation_du_poste_est_rangee_sans_certifier_et_fige_la_facture(): void
    {
        $facture = $this->factureDe10000();
        // Le client certifiant n'est PAS appelé : on le remplace par un piège.
        $this->app->bind(MecefClientInterface::class, fn () => throw new \LogicException('Le serveur ne certifie pas une normalisation du poste.'));

        $this->pousser([$this->operation('factures', 'modification', $facture, ['normalisation' => $this->normalisee()])], $this->receptionniste, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.normalisation_statut', 'normalisee');

        $f = Facture::findOrFail($facture);
        $this->assertSame('ED04000623-41', $f->numero_mecef);
        $this->assertSame(self::QR, $f->qr_code_fiscal);
        $this->assertSame('boitier', $f->normalisation_mode);
        $this->assertSame('41', $f->normalisation_compteur);
        $this->assertSame('NW34NID6ZHANFNMZ2IU7LL3H', $f->code_mecef);
        $this->assertSame('certifiee', $f->statut, 'la facture est figée');
        $this->assertTrue($f->estNormalisee());
        $this->assertFalse($f->estCertificationDemonstration());
        Http::assertNothingSent();
    }

    #[Test]
    public function le_rejeu_est_un_no_op_et_un_autre_resultat_n_ecrase_jamais_une_normalisation(): void
    {
        $facture = $this->factureDe10000();
        $op = fn (array $n) => $this->operation('factures', 'modification', $facture, ['normalisation' => $n]);

        $this->pousser([$op($this->normalisee())], $this->receptionniste, 'poste-a');
        $this->pousser([$op($this->normalisee())], $this->receptionniste, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->pousser([$op($this->normalisee('ED04000623-99'))], $this->receptionniste, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('facturation.normalisation_deja_faite'));
        $this->pousser([$op(['statut' => 'en_attente', 'mode' => 'boitier', 'motif' => 'Boîtier absent'])], $this->receptionniste, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'rejete');

        $this->assertSame('ED04000623-41', Facture::findOrFail($facture)->numero_mecef);
    }

    #[Test]
    public function un_echec_du_poste_se_range_avec_son_motif_et_la_facture_reste_modifiable_par_le_rejeu(): void
    {
        $facture = $this->factureDe10000();

        foreach (['en_attente' => 'Le boîtier n’est pas branché.', 'refusee' => 'Refusée.', 'a_verifier' => 'Compteur 40 → 41.'] as $statut => $motif) {
            $this->pousser([$this->operation('factures', 'modification', $facture, ['normalisation' => [
                'statut' => $statut, 'mode' => 'boitier', 'motif' => $motif,
            ]])], $this->receptionniste, 'poste-a')->assertJsonPath('resultats.0.statut', 'synchronise');

            $f = Facture::findOrFail($facture);
            $this->assertSame($statut, $f->normalisation_statut);
            $this->assertSame($motif, $f->normalisation_motif);
            $this->assertNull($f->numero_mecef);
            $this->assertSame('certifiee', $f->statut, 'la facture est ÉMISE (figée, simple) : la normalisation ne vient que par le bouton');
            $this->assertFalse($f->estNormalisee());
        }

        // Puis le succès : le même chemin range la normalisation.
        $this->pousser([$this->operation('factures', 'modification', $facture, ['normalisation' => $this->normalisee()])], $this->receptionniste, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertTrue(Facture::findOrFail($facture)->estNormalisee());
    }

    #[Test]
    public function le_resultat_recu_est_valide_sans_rien_inventer(): void
    {
        $facture = $this->factureDe10000();
        $mauvais = [
            'identité mal formée' => [...$this->normalisee(), 'numero_mecef' => 'pas une identité'],
            'QR vide' => [...$this->normalisee(), 'qr_code' => ''],
            'QR sans F;' => [...$this->normalisee(), 'qr_code' => 'X;ED;ABC;3201910768821;20261107100000'],
            'QR à quatre champs' => [...$this->normalisee(), 'qr_code' => 'F;ED04000623;ABC;3201910768821'],
            'statut inconnu' => ['statut' => 'quasi', 'mode' => 'boitier'],
            'voie inconnue' => [...$this->normalisee(), 'mode' => 'pigeon'],
            'sans statut' => ['mode' => 'boitier'],
        ];

        foreach ($mauvais as $cas => $normalisation) {
            $this->pousser([$this->operation('factures', 'modification', $facture, ['normalisation' => $normalisation])], $this->receptionniste, 'poste-a')
                ->assertJsonPath('resultats.0.statut', 'rejete', $cas);
        }

        $f = Facture::findOrFail($facture);
        $this->assertNull($f->numero_mecef);
        $this->assertNull($f->normalisation_statut);
    }

    #[Test]
    public function l_annulation_d_une_facture_normalisee_ne_passe_jamais_par_la_file_du_poste(): void
    {
        $facture = $this->factureDe10000();
        $this->pousser([$this->operation('factures', 'modification', $facture, ['normalisation' => $this->normalisee()])], $this->receptionniste, 'poste-a');

        // Avoir d'annulation ET avoir partiel : refusés, rien n'est écrit au serveur.
        $this->pousser([$this->operation('factures', 'modification', $facture, [
            'statut' => 'annulee', 'motif' => 'Erreur de saisie', 'avoir_id' => $this->uuid(),
        ])], $this->receptionniste, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('facturation.avoir_en_ligne_refuse_file'));

        $this->pousser([$this->operation('factures', 'modification', $facture, [
            'montant' => 2000, 'motif' => 'Geste commercial', 'avoir_id' => $this->uuid(),
        ])], $this->receptionniste, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('facturation.avoir_en_ligne_refuse_file'));

        $this->assertSame(0, Avoir::query()->where('facture_id', $facture)->count());
        $this->assertSame('ED04000623-41', Facture::findOrFail($facture)->numero_mecef, 'la facture normalisée reste figée');
    }

    #[Test]
    public function l_annulation_d_une_facture_simple_reste_possible_et_l_avoir_naît_sous_l_identifiant_du_serveur(): void
    {
        $facture = $this->factureDe10000();
        $local = $this->uuid();

        $this->pousser([$this->operation('factures', 'modification', $facture, [
            'statut' => 'annulee', 'motif' => 'Erreur de saisie', 'avoir_id' => $local,
        ])], $this->receptionniste, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $avoir = Avoir::query()->where('facture_id', $facture)->firstOrFail();
        $this->assertNotSame($local, (string) $avoir->id, 'l\'identifiant du poste est ignoré : l\'avoir naît au serveur');
        $this->assertNull($avoir->normalisation_statut, 'avoir d\'une facture simple = avoir simple');
    }

    #[Test]
    public function la_normalisation_d_un_avoir_cree_au_serveur_le_retrouve_par_son_identifiant_serveur(): void
    {
        $facture = $this->factureDe10000();
        $this->pousser([$this->operation('factures', 'modification', $facture, ['normalisation' => $this->normalisee()])], $this->receptionniste, 'poste-a');

        // L'avoir est créé AU SERVEUR (porte en ligne, identifiant serveur), puis normalisé par le poste.
        $avoir = app(\App\Domain\Facturation\Services\EmissionFactureService::class)
            ->emettreAvoir(Facture::findOrFail($facture), '10000.00', 'Erreur de saisie');

        $this->pousser([$this->operation('factures', 'modification', $facture, [
            'avoir_id' => (string) $avoir->id,
            'normalisation' => [
                'statut' => 'normalisee', 'mode' => 'boitier', 'numero_mecef' => 'ED04000623-3', 'qr_code' => self::QR,
                'code_mecef' => 'ZZZZ', 'compteur' => '3',
            ],
        ])], $this->receptionniste, 'poste-a')->assertJsonPath('resultats.0.statut', 'synchronise');

        $a = Avoir::findOrFail($avoir->id);
        $this->assertSame('ED04000623-3', $a->numero_mecef);
        $this->assertSame('normalisee', $a->normalisation_statut);
        $this->assertSame('ED04000623-41', Facture::findOrFail($facture)->numero_mecef);

        // Un avoir inconnu est refusé, jamais deviné.
        $this->pousser([$this->operation('factures', 'modification', $facture, [
            'avoir_id' => $this->uuid(), 'normalisation' => $this->normalisee('ED04000623-4'),
        ])], $this->receptionniste, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.factures.avoir_inconnu'));
    }

    #[Test]
    public function une_demonstration_peut_etre_remplacee_par_une_vraie_normalisation_jamais_l_inverse(): void
    {
        $facture = $this->factureDe10000();
        // Une ligne HÉRITÉE d'avant le 07/11/2026 (le faux client écrivait un numéro DEMO) : posée en SQL.
        \Illuminate\Support\Facades\DB::table('factures')->where('id', $facture)->update(['numero_mecef' => 'MECEF-DEMO-ABCD1234', 'qr_code_fiscal' => 'DONNEES-NON-CERTIFIEES-DEMO', 'statut' => 'certifiee']);

        $this->pousser([$this->operation('factures', 'modification', $facture, ['normalisation' => $this->normalisee()])], $this->receptionniste, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $f = Facture::findOrFail($facture);
        $this->assertSame('ED04000623-41', $f->numero_mecef);
        $this->assertTrue($f->estNormalisee());

        // L'inverse : un numéro réel ne redevient jamais une démonstration.
        $this->expectException(\App\Domain\Facturation\Exceptions\FactureImmuableException::class);
        $f->update(['numero_mecef' => 'MECEF-DEMO-ZZZZ9999']);
    }

    #[Test]
    public function la_facture_normalisee_descend_avec_son_resultat_et_sans_aucun_secret(): void
    {
        $facture = $this->factureDe10000();
        $this->pousser([$this->operation('factures', 'modification', $facture, ['normalisation' => $this->normalisee()])], $this->receptionniste, 'poste-a');

        $this->travel(10)->seconds();
        \Laravel\Sanctum\Sanctum::actingAs($this->receptionniste);
        $elements = [];
        $curseur = null;

        do {
            $r = $this->getJson('/api/v1/referentiels?' . http_build_query(array_filter(['poste_id' => 'poste-b', 'depuis' => $curseur, 'limite' => 500])))->assertOk();
            $elements = [...$elements, ...$r->json('data.elements')];
            $curseur = $r->json('meta.curseur');
        } while (! $r->json('meta.complet'));

        $recue = collect($elements)->where('table', 'factures')->firstWhere('id', $facture);
        $this->assertNotNull($recue, 'la facture descend');
        $this->assertSame('ED04000623-41', $recue['donnees']['numero_mecef']);
        $this->assertSame(self::QR, $recue['donnees']['qr_code_fiscal']);
        $this->assertSame('normalisee', $recue['donnees']['normalisation_statut']);
        $this->assertSame('boitier', $recue['donnees']['normalisation_mode']);
        $this->assertSame('41', $recue['donnees']['normalisation_compteur']);
    }
}

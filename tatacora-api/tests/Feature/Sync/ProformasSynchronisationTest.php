<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\Proforma;
use App\Domain\Facturation\Services\ReglagesDocuments;
use App\Models\User;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Sync\Services\CatalogueDescendantService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PrepareLesDocuments;
use Tests\TestCase;

/**
 * Facture proforma (PO, 07/11/2026) : le poste crée hors ligne, le serveur attribue le numéro continu,
 * la synchronisation est idempotente, la conversion faite au poste se LIE sans créer de seconde facture.
 */
final class ProformasSynchronisationTest extends TestCase
{
    use PrepareLesDocuments;
    use RefreshDatabase;

    private User $receptionniste;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-11-08 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->receptionniste = $this->creerUtilisateur('receptionniste');
    }

    /** @param array<string, mixed> $surcharges @return array<string, mixed> */
    private function proforma(string $id, array $surcharges = []): array
    {
        return $this->operationDatee('proformas', 'creation', $id, [
            'client_nom' => 'SARL KORA', 'client_telephone' => '0190123456', 'objet' => 'Atelier',
            'date_emission' => '2026-11-07', 'emettre' => true,
            'numero_provisoire' => 'PROV-FP-2026-00001',
            'lignes' => [['designation' => 'Salle', 'quantite' => 2, 'prix_unitaire' => 50000]],
            ...$surcharges,
        ], '2026-11-07T09:00:00+00:00');
    }

    #[Test]
    public function le_serveur_attribue_le_numero_continu_et_le_rend_au_poste(): void
    {
        [$a, $b] = [$this->uuid(), $this->uuid()];

        $this->pousser([$this->proforma($a), $this->proforma($b)], $this->receptionniste, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.numero', 'N°0001 FP-GCN/2026')
            ->assertJsonPath('resultats.1.numero', 'N°0002 FP-GCN/2026');

        $p = Proforma::with('lignes')->findOrFail($a);
        $this->assertSame(100000, $p->total);
        $this->assertSame('emise', $p->statut);
        $this->assertSame('2026-11-07', $p->date_emission->toDateString());
    }

    #[Test]
    public function un_rejeu_rend_le_meme_numero_sans_en_bruler_un(): void
    {
        $op = $this->proforma($this->uuid());
        $this->pousser([$op], $this->receptionniste);
        $this->pousser([[...$op, 'uuid_operation' => $this->uuid()]], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.numero', 'N°0001 FP-GCN/2026');

        $this->assertSame(1, Proforma::count());
        $this->pousser([$this->proforma($this->uuid())], $this->receptionniste)->assertJsonPath('resultats.0.numero', 'N°0002 FP-GCN/2026');
    }

    #[Test]
    public function la_validite_decidee_au_poste_est_rangee_telle_quelle(): void
    {
        // Le serveur a la validité sur Oui / 90 jours, le poste avait Non à l'émission : le serveur ne recalcule pas.
        ParametreSysteme::create(['cle' => ReglagesDocuments::CLE_VALIDITE_AFFICHEE, 'valeur' => 'true']);
        ParametreSysteme::create(['cle' => ReglagesDocuments::CLE_VALIDITE_JOURS, 'valeur' => '90']);
        [$sans, $avec] = [$this->uuid(), $this->uuid()];

        $this->pousser([
            $this->proforma($sans, ['valide_jusqu_au' => null]),
            $this->proforma($avec, ['valide_jusqu_au' => '2026-12-07']),
        ], $this->receptionniste);

        $this->assertNull(Proforma::findOrFail($sans)->valide_jusqu_au);
        $this->assertSame('2026-12-07', Proforma::findOrFail($avec)->valide_jusqu_au->toDateString());
    }

    #[Test]
    public function un_brouillon_puis_son_emission_son_annulation_se_rejouent(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->proforma($id, ['emettre' => false])], $this->receptionniste);
        $this->assertNull(Proforma::findOrFail($id)->numero);

        $this->pousser([$this->operationDatee('proformas', 'modification', $id, ['statut' => 'emise', 'date_emission' => '2026-11-07', 'valide_jusqu_au' => null], '2026-11-07T10:00:00+00:00')], $this->receptionniste)
            ->assertJsonPath('resultats.0.numero', 'N°0001 FP-GCN/2026');

        $this->pousser([$this->operationDatee('proformas', 'modification', $id, ['statut' => 'annulee', 'motif' => 'Client désisté'], '2026-11-07T11:00:00+00:00')], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame('annulee', Proforma::findOrFail($id)->statut);
        $this->assertSame('N°0001 FP-GCN/2026', Proforma::findOrFail($id)->numero);
    }

    #[Test]
    public function une_modification_de_lignes_met_a_jour_le_total(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->proforma($id)], $this->receptionniste);

        $this->pousser([$this->operationDatee('proformas', 'modification', $id, [
            'objet' => 'Atelier révisé', 'lignes' => [['designation' => 'Forfait', 'quantite' => 1, 'prix_unitaire' => 400000]],
        ], '2026-11-07T10:30:00+00:00')], $this->receptionniste)->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame(400000, Proforma::findOrFail($id)->total);
    }

    #[Test]
    public function la_conversion_faite_au_poste_lie_la_facture_sans_en_creer_une_seconde(): void
    {
        $idProforma = $this->uuid();
        $idFacture = $this->uuid();
        Client::create(['nom' => 'Client de passage', 'telephone' => '-', 'type_client' => 'particulier']);

        $this->pousser([
            $this->proforma($idProforma),
            $this->operationDatee('factures', 'creation', $idFacture, [
                'origine' => 'facture_directe', 'date_emission' => '2026-11-07', 'acheteur_nom' => 'SARL KORA',
                'lignes' => [['module' => 'M9', 'libelle' => 'Salle', 'prix_unitaire' => 50000, 'quantite' => 2]],
            ], '2026-11-07T09:30:00+00:00'),
            $this->operationDatee('proformas', 'modification', $idProforma, ['statut' => 'convertie', 'facture_id' => $idFacture], '2026-11-07T09:40:00+00:00'),
        ], $this->receptionniste)->assertJsonPath('resultats.1.statut', 'synchronise')
            ->assertJsonPath('resultats.2.statut', 'synchronise');

        $p = Proforma::findOrFail($idProforma);
        $this->assertSame('convertie', $p->statut);
        $this->assertSame($idFacture, $p->facture_id);
        $this->assertSame($idProforma, Facture::findOrFail($idFacture)->proforma_id);
        $this->assertSame(1, Facture::count());

        // Rejeu de la même liaison : idempotent.
        $this->pousser([$this->operationDatee('proformas', 'modification', $idProforma, ['statut' => 'convertie', 'facture_id' => $idFacture], '2026-11-07T09:50:00+00:00')], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
    }

    #[Test]
    public function une_conversion_vers_une_facture_inconnue_est_refusee(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->proforma($id)], $this->receptionniste);

        $this->pousser([$this->operationDatee('proformas', 'modification', $id, ['statut' => 'convertie', 'facture_id' => $this->uuid()], '2026-11-07T09:50:00+00:00')], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'rejete');
        $this->assertSame('emise', Proforma::findOrFail($id)->statut);
    }

    #[Test]
    public function un_poste_ecrit_les_reglages_des_documents_dernier_ecrit_gagnant(): void
    {
        $admin = $this->creerUtilisateur('administrateur');
        ParametreSysteme::create(['cle' => ReglagesDocuments::CLE_REFERENCE_FACTURE, 'valeur' => 'GCN']);

        $this->pousser([$this->operationDatee('parametres_systeme', 'creation', $this->uuid(), [
            'valeurs' => [ReglagesDocuments::CLE_REFERENCE_FACTURE => 'ZZZ', ReglagesDocuments::CLE_SIGNATURE_AFFICHEE => 'true'],
        ], '2026-11-07T09:00:00+00:00')], $admin);

        // Décision du PO du 09/11/2026 : les réglages des documents se modifient AU POSTE
        // (droit Paramètres) et se synchronisent. Dernier écrit gagnant, clé par clé : la
        // référence déjà posée plus récemment au serveur n'est pas écrasée par une
        // opération plus ancienne ; la signature, absente, est écrite.
        $this->assertSame('GCN', ParametreSysteme::query()->where('cle', ReglagesDocuments::CLE_REFERENCE_FACTURE)->value('valeur'));
        $this->assertSame('true', ParametreSysteme::query()->where('cle', ReglagesDocuments::CLE_SIGNATURE_AFFICHEE)->value('valeur'));
    }

    #[Test]
    public function un_compte_sans_ecriture_sur_m2_est_refuse(): void
    {
        $sans = $this->creerUtilisateur('comptable'); // M2 = L : lecture seule

        $this->pousser([$this->proforma($this->uuid())], $sans)->assertJsonPath('resultats.0.statut', 'rejete');
        $this->assertSame(0, Proforma::count());
    }

    #[Test]
    public function la_proforma_et_ses_lignes_descendent_aux_autres_postes(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->proforma($id)], $this->receptionniste, 'poste-a');
        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();

        Sanctum::actingAs($this->creerUtilisateur('administrateur'));
        $elements = collect($this->getJson('/api/v1/referentiels?'.http_build_query(['poste_id' => 'poste-b', 'limite' => 500]))->assertOk()->json('data.elements'))
            ->where('table', 'proformas');

        $this->assertCount(1, $elements);
        $element = $elements->first();
        $this->assertSame($id, $element['id']);
        $this->assertSame('N°0001 FP-GCN/2026', $element['donnees']['numero']);
        $this->assertSame(100000, $element['donnees']['total']);
        $this->assertSame('Salle', $element['donnees']['lignes'][0]['designation']);
    }
}

<?php

declare(strict_types=1);

namespace Tests\Feature\Facturation;

use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\Proforma;
use App\Domain\Facturation\Services\ModeFacturation;
use App\Domain\Facturation\Services\ProformaService;
use App\Domain\Facturation\Services\ReglagesDocuments;
use App\Shared\Parametres\Models\ParametreSysteme;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/** Facture proforma (PO, 07/11/2026) : numérotation, cycle de vie, validité, conversion. */
final class ProformaServiceTest extends TestCase
{
    use RefreshDatabase;

    private function regler(string $cle, string $valeur): void
    {
        ParametreSysteme::updateOrCreate(['cle' => $cle], ['valeur' => $valeur]);
    }

    private function service(): ProformaService
    {
        return app(ProformaService::class);
    }

    /** @param list<array{designation: string, quantite: int, prix_unitaire: int}>|null $lignes */
    private function brouillon(?array $lignes = null, array $extra = []): Proforma
    {
        return $this->service()->creer([
            'client_nom' => 'SOCIÉTÉ KORA', 'client_telephone' => '0190123456', 'client_ifu' => '0202011344660',
            'objet' => 'Séjour de groupe',
            'lignes' => $lignes ?? [
                ['designation' => 'Chambre double', 'quantite' => 4, 'prix_unitaire' => 25000],
                ['designation' => 'Petit déjeuner', 'quantite' => 8, 'prix_unitaire' => 2500],
            ],
            ...$extra,
        ]);
    }

    #[Test]
    public function le_numero_suit_le_format_du_po_et_la_sequence_est_continue(): void
    {
        $a = $this->service()->emettre($this->brouillon(), '2026-11-02');
        $b = $this->service()->emettre($this->brouillon(), '2026-11-03');

        $this->assertSame('N°0001 FP-GCN/2026', $a->numero);
        $this->assertSame('N°0002 FP-GCN/2026', $b->numero);
        $this->assertSame('N°0045 FP-GCN/2026', ProformaService::formaterNumero(45, 'GCN', 2026));
        $this->assertSame(Proforma::EMISE, $a->statut);
    }

    #[Test]
    public function la_sequence_repart_a_un_chaque_annee(): void
    {
        $this->service()->emettre($this->brouillon(), '2026-12-31');
        $this->service()->emettre($this->brouillon(), '2026-12-31');
        $premiere2027 = $this->service()->emettre($this->brouillon(), '2027-01-01');

        $this->assertSame('N°0001 FP-GCN/2027', $premiere2027->numero);
    }

    #[Test]
    public function un_brouillon_n_a_pas_de_numero_et_n_ouvre_aucun_trou(): void
    {
        $abandonne = $this->brouillon();
        $this->assertNull($abandonne->numero);
        $this->assertSame(Proforma::BROUILLON, $abandonne->statut);

        $premiere = $this->service()->emettre($this->brouillon(), '2026-11-02');
        $this->assertSame(1, $premiere->rang);
    }

    #[Test]
    public function la_reference_est_copiee_a_l_emission_et_ne_renumerote_rien(): void
    {
        $avant = $this->service()->emettre($this->brouillon(), '2026-11-02');
        $this->regler(ReglagesDocuments::CLE_REFERENCE_FACTURE, 'abc');
        $apres = $this->service()->emettre($this->brouillon(), '2026-11-02');

        $this->assertSame('N°0001 FP-GCN/2026', $avant->refresh()->numero);
        $this->assertSame('N°0002 FP-ABC/2026', $apres->numero);
    }

    #[Test]
    public function emettre_deux_fois_rend_le_meme_numero(): void
    {
        $p = $this->brouillon();
        $premier = $this->service()->emettre($p, '2026-11-02')->numero;
        $second = $this->service()->emettre($p, '2026-11-09')->numero;

        $this->assertSame($premier, $second);
        $this->assertSame(1, Proforma::query()->whereNotNull('numero')->count());
    }

    #[Test]
    public function la_base_refuse_deux_numeros_definitifs_identiques(): void
    {
        $a = $this->service()->emettre($this->brouillon(), '2026-11-02');
        $b = $this->brouillon();

        $this->expectException(QueryException::class);
        // Même (annee, rang) : le dernier rempart de la séquence.
        DB::table('proformas')->where('id', $b->id)->update(['annee' => $a->annee, 'rang' => $a->rang]);
    }

    #[Test]
    public function la_validite_est_calculee_a_l_emission_et_enregistree(): void
    {
        $sans = $this->service()->emettre($this->brouillon(), '2026-11-02');
        $this->assertNull($sans->valide_jusqu_au);

        $this->regler(ReglagesDocuments::CLE_VALIDITE_AFFICHEE, 'true');
        $this->regler(ReglagesDocuments::CLE_VALIDITE_JOURS, '15');
        $avec = $this->service()->emettre($this->brouillon(), '2026-11-02');
        $this->assertSame('2026-11-17', $avec->valide_jusqu_au->toDateString());

        // Un changement ultérieur du réglage ne touche pas la proforma déjà émise.
        $this->regler(ReglagesDocuments::CLE_VALIDITE_JOURS, '90');
        $this->regler(ReglagesDocuments::CLE_VALIDITE_AFFICHEE, 'false');
        $this->assertSame('2026-11-17', $avec->refresh()->valide_jusqu_au->toDateString());
        $this->assertNull($sans->refresh()->valide_jusqu_au);
    }

    #[Test]
    public function passee_la_date_la_proforma_est_expiree_sans_changer_son_statut_stocke(): void
    {
        $this->regler(ReglagesDocuments::CLE_VALIDITE_AFFICHEE, 'true');
        $p = $this->service()->emettre($this->brouillon(), '2026-11-02'); // valable jusqu'au 02/12/2026

        $this->assertSame('emise', $p->statutAffiche(Carbon::parse('2026-12-02')));
        $this->assertSame('expiree', $p->statutAffiche(Carbon::parse('2026-12-03')));
        $this->assertSame('emise', $p->refresh()->statut);

        // Expirée : la conversion reste possible.
        $this->assertNotNull($this->service()->convertir($p));
    }

    #[Test]
    public function une_emise_se_modifie_avec_audit_une_convertie_non(): void
    {
        $p = $this->service()->emettre($this->brouillon(), '2026-11-02');
        $this->service()->modifier($p, ['objet' => 'Nouvel objet', 'lignes' => [['designation' => 'Forfait', 'quantite' => 1, 'prix_unitaire' => 400000]]]);

        $p->refresh();
        $this->assertSame(400000, $p->total);
        $this->assertSame('Nouvel objet', $p->objet);
        $this->assertGreaterThanOrEqual(1, DB::table('journal_audit')->where('entite_id', $p->id)->where('action', 'modification_proforma')->count());

        $this->service()->convertir($p);
        $this->expectException(RuntimeException::class);
        $this->service()->modifier($p, ['objet' => 'Trop tard']);
    }

    #[Test]
    public function l_annulation_exige_un_motif_garde_le_numero_et_interdit_la_conversion(): void
    {
        $p = $this->service()->emettre($this->brouillon(), '2026-11-02');

        try {
            $this->service()->annuler($p, '   ');
            $this->fail('Le motif est obligatoire.');
        } catch (RuntimeException) {
        }

        $annulee = $this->service()->annuler($p, 'Client désisté');
        $this->assertSame(Proforma::ANNULEE, $annulee->statut);
        $this->assertSame('N°0001 FP-GCN/2026', $annulee->numero);
        // Rejeu : même état, sans erreur.
        $this->assertSame(Proforma::ANNULEE, $this->service()->annuler($p, 'autre motif')->statut);

        $this->expectException(RuntimeException::class);
        $this->service()->convertir($p);
    }

    #[Test]
    public function un_brouillon_ne_se_convertit_pas(): void
    {
        $this->expectException(RuntimeException::class);
        $this->service()->convertir($this->brouillon());
    }

    #[Test]
    public function la_conversion_cree_une_vraie_facture_aux_memes_montants_une_seule_fois(): void
    {
        $p = $this->service()->emettre($this->brouillon(), '2026-11-02');
        $this->assertSame(120000, $p->total);

        $facture = $this->service()->convertir($p);
        $p->refresh();

        $this->assertSame(Proforma::CONVERTIE, $p->statut);
        $this->assertSame($facture->id, $p->facture_id);
        $this->assertSame($p->id, $facture->proforma_id);
        $this->assertSame('120000.00', (string) $facture->montant_ttc);
        $this->assertSame('0202011344660', $facture->acheteur_ifu);
        $this->assertSame('SOCIÉTÉ KORA', $facture->acheteur_nom);
        $this->assertSame(2, $facture->lignes()->count());
        $this->assertStringStartsWith('F-', (string) $facture->numero);
        $this->assertSame('certifiee', $facture->statut); // émise (simple) : aucune normalisation automatique
        $this->assertNull($facture->numero_mecef);
        $this->assertNull($facture->qr_code_fiscal);

        // Idempotent : le rejeu rend la MÊME facture, sans doublon.
        $this->assertSame($facture->id, $this->service()->convertir($p)->id);
        $this->assertSame(1, Facture::query()->where('proforma_id', $p->id)->count());
        $this->assertSame(1, Facture::query()->count());
    }

    #[Test]
    public function la_conversion_ne_normalise_jamais_toute_seule_meme_en_mode_emecef(): void
    {
        Http::fake();
        $this->regler(ModeFacturation::CLE, ModeFacturation::Emecef->value);

        $facture = $this->service()->convertir($this->service()->emettre($this->brouillon(), '2026-11-02'));

        Http::assertNothingSent();
        $this->assertNull($facture->numero_mecef);
        $this->assertNull($facture->qr_code_fiscal);
        $this->assertNull($facture->normalisation_statut);
    }

    #[Test]
    public function une_proforma_n_ecrit_ni_piece_comptable_ni_mouvement_de_stock(): void
    {
        $avant = [DB::table('ecritures_comptables')->count(), DB::table('mouvements_stock')->count()];

        $p = $this->service()->emettre($this->brouillon(), '2026-11-02');
        $this->service()->modifier($p, ['objet' => 'x']);
        $this->service()->annuler($p, 'test');

        $this->assertSame($avant, [DB::table('ecritures_comptables')->count(), DB::table('mouvements_stock')->count()]);
    }

    #[Test]
    public function les_lignes_invalides_sont_refusees(): void
    {
        foreach ([
            [['designation' => '', 'quantite' => 1, 'prix_unitaire' => 100]],
            [['designation' => 'X', 'quantite' => 0, 'prix_unitaire' => 100]],
            [['designation' => 'X', 'quantite' => 1, 'prix_unitaire' => '12.5']],
            [],
        ] as $lignes) {
            try {
                $this->brouillon($lignes);
                $this->fail('Ligne invalide acceptée.');
            } catch (RuntimeException) {
                $this->addToAssertionCount(1);
            }
        }
    }
}

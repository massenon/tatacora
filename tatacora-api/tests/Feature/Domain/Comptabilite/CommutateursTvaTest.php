<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Comptabilite;

use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Services\EmissionFactureService;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ReservationService;
use App\Shared\Parametres\Models\ParametreSysteme;
use Database\Seeders\TvaReferentielSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Commutateurs de TVA — assujettissement (`tva_active`) et convention de prix
 * (`convention_prix`), tous deux paramétrables sans déploiement.
 *
 * Résout PA-37 par configuration : les deux conventions restent implémentées,
 * le paramètre dit laquelle s'applique.
 */
final class CommutateursTvaTest extends TestCase
{
    use RefreshDatabase;

    private Reservation $reservation;

    protected function setUp(): void
    {
        parent::setUp();
        // Comptes de TVA du fichier du PO (plus semés par TvaReferentielSeeder).
        foreach ([['4431', 'T.V.A. facturée sur ventes'], ['4432', 'T.V.A. facturée sur prestations de services'], ['4452', 'T.V.A. récupérable sur achats']] as [$n, $l]) {
            \App\Domain\Comptabilite\Models\CompteComptable::firstOrCreate(['numero_compte' => $n], ['libelle' => $l, 'classe' => '4', 'nature' => 'passif']);
        }
        $this->seed(TvaReferentielSeeder::class);

        $categorie = CategorieHebergement::create([
            'libelle' => 'Bungalow', 'capacite_max' => 4, 'tarif_base' => '25000.00',
        ]);
        $unite = UniteHebergement::create([
            'categorie_id' => $categorie->id, 'numero' => 'B-01', 'statut' => 'libre',
        ]);

        $this->reservation = app(ReservationService::class)->creer([
            'client_id' => Client::factory()->create()->id,
            'unite_id' => $unite->id,
            'date_arrivee' => '2026-09-01',
            'date_depart' => '2026-09-02',   // 1 nuitée, pour des chiffres lisibles
            'statut' => 'confirmee',
            'acompte' => '0.00',
        ]);
    }

    // --------------------------------------------------- Assujettissement

    /**
     * ⚠ PRÉMISSE RENVERSÉE le 01/09/2026 : ce cas s'appelait « la TVA est
     * inactive par défaut ». Le Product Owner a rendu l'acte d'administration
     * que la version inactive attendait — « les prix du catalogue sont TTC,
     * la TVA est 18 % » — et le référentiel seed désormais cet état. Le
     * contrat mesuré devient : ACTIVE, convention TTC, ventilation exacte
     * (25 000 TTC → 21 186,44 HT + 3 813,56 de TVA, ht + tva = ttc au
     * centime).
     */
    #[Test]
    public function la_tva_est_active_en_convention_ttc_par_decision_du_product_owner(): void
    {
        $calcul = app(CalculTvaService::class);

        $this->assertTrue($calcul->estActive());
        $this->assertSame('active', $calcul->etatTva());

        $ventilation = $calcul->ventiler('25000.00');
        $this->assertSame('21186.44', $ventilation['ht']);
        $this->assertSame('3813.56', $ventilation['tva']);
        $this->assertSame('25000.00', $ventilation['ttc']);
        $this->assertTrue($ventilation['tva_active']);
    }

    #[Test]
    public function une_facture_emise_ventile_le_tarif_ttc_du_catalogue(): void
    {
        // Le tarif du catalogue est TTC (décision PO du 01/09/2026) :
        // l'émission extrait la taxe, elle ne l'ajoute pas — et le TTC du
        // document reste EXACTEMENT le prix affiché au client.
        $facture = app(EmissionFactureService::class)
            ->emettrePourReservation($this->reservation, '25000.00');

        $this->assertSame('21186.44', $facture->montant_ht);
        $this->assertSame('3813.56', $facture->montant_tva);
        $this->assertSame('25000.00', $facture->montant_ttc);
    }

    // ------------------------------ Incoherence entre les deux commutateurs

    /**
     * PA-62 — l'etat que personne n'avait eprouve.
     *
     * `tva_active` et `taux_tva` sont deux parametres INDEPENDANTS : rien
     * n'empeche d'activer la TVA sans renseigner son taux. Aucun test ne
     * couvrait cette combinaison, et `estConfigure()` — le seul controle qui la
     * nomme — n'avait aucun appelant dans `app/`.
     */
    #[Test]
    public function la_tva_peut_etre_activee_sans_taux_et_l_etat_le_dit(): void
    {
        $this->activerSansTaux();
        $calcul = app(CalculTvaService::class);

        // L'intention est bien « active »...
        $this->assertTrue($calcul->estActive());
        // ...mais la capacite ne suit pas.
        $this->assertFalse($calcul->estConfigure());

        // Et c'est l'etat derive qui le dit, pas le commutateur.
        $this->assertSame('activee_sans_taux', $calcul->etatTva());
    }

    /**
     * La consequence, reproduite : le refus tombe **au comptoir**.
     *
     * C'est la bonne decision — emettre a 0 % pendant qu'un Administrateur
     * croit la TVA active serait une sous-taxation silencieuse sur un document
     * immuable, que seul un avoir pourrait corriger. Ce test fige le refus pour
     * que personne ne le remplace un jour par un repli a zero.
     */
    #[Test]
    public function une_tva_activee_sans_taux_refuse_d_emettre_plutot_que_de_taxer_a_zero(): void
    {
        $this->activerSansTaux();

        $this->expectException(RuntimeException::class);

        app(EmissionFactureService::class)
            ->emettrePourReservation($this->reservation, '25000.00');
    }

    #[Test]
    public function le_refus_nomme_le_parametre_et_l_action_attendue(): void
    {
        $this->activerSansTaux();

        try {
            app(EmissionFactureService::class)
                ->emettrePourReservation($this->reservation, '25000.00');
            $this->fail('Une emission aurait du etre refusee.');
        } catch (RuntimeException $e) {
            // Un receptionniste doit pouvoir transmettre le message tel quel.
            $this->assertStringContainsString(CalculTvaService::CLE_PARAMETRE_TAUX, $e->getMessage());
            $this->assertStringContainsString('Administrateur', $e->getMessage());
        }
    }

    #[Test]
    public function une_convention_illisible_donne_un_etat_nomme_sans_faire_tomber_l_ecran(): void
    {
        ParametreSysteme::where('cle', CalculTvaService::CLE_PARAMETRE_ACTIVE)
            ->update(['valeur' => 'true']);
        ParametreSysteme::where('cle', CalculTvaService::CLE_PARAMETRE_CONVENTION)
            ->update(['valeur' => 'hors-taxe-peut-etre']);

        // `convention()` leve, c'est voulu. Mais un badge d'etat ne doit pas
        // faire tomber l'ecran qui l'affiche : `etatTva()` nomme le probleme.
        $this->assertSame('activee_convention_invalide', app(CalculTvaService::class)->etatTva());
    }

    #[Test]
    public function les_quatre_etats_sont_atteignables(): void
    {
        $calcul = app(CalculTvaService::class);

        // 1. Active et complete : l'etat par defaut du referentiel depuis la
        //    decision du PO (01/09/2026).
        $this->assertSame('active', $calcul->etatTva());

        // 2. Inactive : atteignable par l'acte inverse.
        ParametreSysteme::where('cle', CalculTvaService::CLE_PARAMETRE_ACTIVE)
            ->update(['valeur' => 'false']);
        $this->assertSame('inactive', $calcul->etatTva());

        // 3. et 4. sont couverts par les deux tests precedents.
    }

    private function activerSansTaux(): void
    {
        ParametreSysteme::where('cle', CalculTvaService::CLE_PARAMETRE_ACTIVE)
            ->update(['valeur' => 'true']);
        ParametreSysteme::where('cle', CalculTvaService::CLE_PARAMETRE_TAUX)->delete();
    }

    // ------------------------------------------------------ Convention HT

    #[Test]
    public function en_convention_ht_la_tva_s_ajoute_au_tarif(): void
    {
        $this->configurer(active: true, convention: CalculTvaService::CONVENTION_HT);

        $facture = app(EmissionFactureService::class)
            ->emettrePourReservation($this->reservation, '25000.00');

        // Le tarif s'entend hors taxe : le client paie 29 500.
        $this->assertSame('25000.00', $facture->montant_ht);
        $this->assertSame('4500.00', $facture->montant_tva);
        $this->assertSame('29500.00', $facture->montant_ttc);
    }

    // ----------------------------------------------------- Convention TTC

    #[Test]
    public function en_convention_ttc_la_tva_est_extraite_du_tarif(): void
    {
        $this->configurer(active: true, convention: CalculTvaService::CONVENTION_TTC);

        $facture = app(EmissionFactureService::class)
            ->emettrePourReservation($this->reservation, '25000.00');

        // Le tarif inclut déjà la taxe : le client paie 25 000, dont 3 813,56.
        $this->assertSame('21186.44', $facture->montant_ht);
        $this->assertSame('3813.56', $facture->montant_tva);
        $this->assertSame('25000.00', $facture->montant_ttc);
    }

    /**
     * L'écart entre les deux conventions sur un même tarif — la raison pour
     * laquelle ce paramètre ne pouvait pas être deviné (PA-37).
     */
    #[Test]
    public function les_deux_conventions_donnent_des_totaux_differents_sur_le_meme_tarif(): void
    {
        $this->configurer(active: true, convention: CalculTvaService::CONVENTION_HT);
        $enHt = app(CalculTvaService::class)->ventiler('25000.00');

        $this->configurer(active: true, convention: CalculTvaService::CONVENTION_TTC);
        $enTtc = app(CalculTvaService::class)->ventiler('25000.00');

        $this->assertSame('29500.00', $enHt['ttc']);
        $this->assertSame('25000.00', $enTtc['ttc']);
        $this->assertSame('4500.00', bcsub($enHt['ttc'], $enTtc['ttc'], 2));
    }

    // ---------------------------------------------------------- Robustesse

    #[Test]
    public function une_convention_inconnue_fait_echouer_le_calcul(): void
    {
        $this->configurer(active: true, convention: 'net_de_taxe');

        // Un repli silencieux sur « ht » ferait facturer 18 % de trop sur des
        // tarifs qui les incluaient peut-être déjà.
        $this->expectException(RuntimeException::class);
        app(CalculTvaService::class)->ventiler('25000.00');
    }

    #[Test]
    public function la_convention_est_insensible_a_la_casse_et_aux_espaces(): void
    {
        $this->configurer(active: true, convention: '  TTC ');

        $this->assertSame(
            CalculTvaService::CONVENTION_TTC,
            app(CalculTvaService::class)->convention(),
        );
    }

    /**
     * Le point le plus important de la configurabilité : changer le paramètre
     * ne doit JAMAIS modifier une facture déjà émise.
     */
    #[Test]
    public function changer_les_parametres_ne_modifie_aucune_facture_deja_emise(): void
    {
        $this->configurer(active: true, convention: CalculTvaService::CONVENTION_HT);

        $facture = app(EmissionFactureService::class)
            ->emettrePourReservation($this->reservation, '25000.00');
        $totauxEmis = $facture->only(['montant_ht', 'montant_tva', 'montant_ttc']);

        // L'entreprise change de convention, puis suspend son assujettissement.
        $this->configurer(active: true, convention: CalculTvaService::CONVENTION_TTC);
        $this->assertSame($totauxEmis, $facture->fresh()->only(['montant_ht', 'montant_tva', 'montant_ttc']));

        $this->configurer(active: false, convention: CalculTvaService::CONVENTION_HT);
        $this->assertSame($totauxEmis, $facture->fresh()->only(['montant_ht', 'montant_tva', 'montant_ttc']));
    }

    #[Test]
    public function une_ligne_ajoutee_est_stockee_hors_taxe_et_le_total_reste_coherent(): void
    {
        $this->configurer(active: true, convention: CalculTvaService::CONVENTION_TTC);
        $emission = app(EmissionFactureService::class);

        $facture = $emission->emettrePourReservation($this->reservation, '25000.00');
        $emission->ajouterLigne($facture, 'M5', (string) Str::uuid(), 'Boissons', '2.00', '1180.00');

        $facture->refresh();

        // Ligne bar : 2 × 1 180 TTC = 2 360 TTC → 2 000 HT.
        $ligneBar = $facture->lignes()->where('source_module', 'M5')->sole();
        $this->assertSame('2000.00', $ligneBar->montant);

        // Total HT = 21 186,44 + 2 000, TVA recalculée dans le sens HT → TVA.
        $this->assertSame('23186.44', $facture->montant_ht);
        $this->assertSame(
            0,
            bccomp(
                bcadd($facture->montant_ht, $facture->montant_tva, 2),
                $facture->montant_ttc,
                2,
            ),
        );
    }

    private function configurer(bool $active, string $convention): void
    {
        ParametreSysteme::where('cle', CalculTvaService::CLE_PARAMETRE_ACTIVE)
            ->update(['valeur' => $active ? 'true' : 'false']);
        ParametreSysteme::where('cle', CalculTvaService::CLE_PARAMETRE_CONVENTION)
            ->update(['valeur' => $convention]);
    }
}

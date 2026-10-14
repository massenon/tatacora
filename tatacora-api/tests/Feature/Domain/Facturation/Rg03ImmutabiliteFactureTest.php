<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Facturation;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Exceptions\FactureImmuableException;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Providers\MecefServiceProvider;
use App\Domain\Facturation\Services\CertificationMecefResultat;
use App\Domain\Facturation\Services\EmissionFactureService;
use App\Domain\Facturation\Services\MecefClientInterface;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ReservationService;
use App\Models\User;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use DateTimeImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * RG-03 — Immutabilité de la facture MECeF, et bascule Fake/Réel.
 *
 * Cas obligatoires de 07_TESTING_QA.md §2 : tentative d'UPDATE/DELETE sur
 * facture certifiée → exception ; création d'avoir → facture d'origine
 * inchangée.
 */
final class Rg03ImmutabiliteFactureTest extends TestCase
{
    use RefreshDatabase;

    private EmissionFactureService $emission;

    private Reservation $reservation;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->emission = app(EmissionFactureService::class);
        $this->actingAs($this->utilisateur('receptionniste'));

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
            'date_depart' => '2026-09-04',
            'statut' => 'confirmee',
            'acompte' => '0.00',
        ]);
    }

    #[Test]
    public function une_facture_est_emise_avant_certification(): void
    {
        $facture = $this->emission->emettrePourReservation($this->reservation, '25000.00');

        // La facture existe immédiatement : la DGI peut être indisponible, le
        // client ne doit pas attendre (MECEF_INTEGRATION_SPEC.md §2).
        $this->assertSame('en_attente_certification', $facture->statut);
        $this->assertNull($facture->numero_mecef);
        // 3 nuitées × 25 000 — total calculé, jamais saisi.
        $this->assertSame('75000.00', $facture->montant_ttc);
        $this->assertCount(1, $facture->lignes()->get());
    }

    #[Test]
    public function rg04_la_ligne_porte_son_module_d_origine(): void
    {
        $facture = $this->emission->emettrePourReservation($this->reservation, '25000.00');
        $ligne = $facture->lignes()->sole();

        $this->assertSame('M1', $ligne->source_module);
        $this->assertSame($this->reservation->id, $ligne->source_id);
    }

    #[Test]
    public function rg04_une_facture_consolide_des_lignes_de_plusieurs_modules(): void
    {
        $facture = $this->emission->emettrePourReservation($this->reservation, '25000.00');

        // Consommation au bar rattachée au même document.
        $this->emission->ajouterLigne($facture, 'M5', (string) Str::uuid(), 'Boissons — bar', '4.00', '1500.00');

        $facture->refresh();
        $this->assertCount(2, $facture->lignes()->get());
        $this->assertSame('81000.00', $facture->montant_ttc);
        $this->assertEqualsCanonicalizing(
            ['M1', 'M5'],
            $facture->lignes()->pluck('source_module')->all(),
        );
    }

    #[Test]
    public function rg03_une_facture_certifiee_ne_peut_plus_etre_modifiee(): void
    {
        $facture = $this->emission->certifier(
            $this->emission->emettrePourReservation($this->reservation, '25000.00'),
        );

        $this->assertSame('certifiee', $facture->statut);
        $this->assertNotNull($facture->numero_mecef);

        $this->expectException(FactureImmuableException::class);
        $facture->update(['montant_ttc' => '1.00']);
    }

    #[Test]
    public function rg03_une_facture_certifiee_ne_peut_pas_etre_supprimee(): void
    {
        $facture = $this->emission->certifier(
            $this->emission->emettrePourReservation($this->reservation, '25000.00'),
        );

        // assertThrows plutôt qu'expectException : on veut aussi vérifier
        // APRÈS coup que la ligne est toujours là, ce qu'un expectException
        // rendrait inatteignable.
        $this->assertThrows(
            fn () => $facture->delete(),
            FactureImmuableException::class,
        );

        $this->assertDatabaseHas('factures', ['id' => $facture->id]);
    }

    /**
     * Même une facture en brouillon ne se supprime pas : un trou dans la
     * numérotation se lit comme une facture dissimulée.
     */
    #[Test]
    public function rg03_meme_une_facture_non_certifiee_ne_se_supprime_pas(): void
    {
        $facture = $this->emission->emettrePourReservation($this->reservation, '25000.00');

        $this->expectException(FactureImmuableException::class);
        $facture->delete();
    }

    #[Test]
    public function rg03_une_facture_certifiee_ne_peut_pas_etre_recertifiee(): void
    {
        $facture = $this->emission->certifier(
            $this->emission->emettrePourReservation($this->reservation, '25000.00'),
        );
        $nimOrigine = $facture->numero_mecef;

        // Un second passage écraserait un NIM réel par un NIM de démonstration.
        $this->expectException(FactureImmuableException::class);
        $facture->update(['numero_mecef' => 'MECEF-AUTRE-0001']);

        $this->assertSame($nimOrigine, $facture->fresh()->numero_mecef);
    }

    #[Test]
    public function rg03_aucune_ligne_ne_peut_etre_ajoutee_apres_certification(): void
    {
        $facture = $this->emission->certifier(
            $this->emission->emettrePourReservation($this->reservation, '25000.00'),
        );

        $this->expectException(FactureImmuableException::class);
        $this->emission->ajouterLigne($facture, 'M5', (string) Str::uuid(), 'Boissons', '1.00', '1500.00');
    }

    /**
     * Le cas central de RG-03 : l'avoir corrige SANS toucher à l'original.
     */
    #[Test]
    public function rg03_un_avoir_neutralise_la_facture_sans_la_modifier(): void
    {
        $facture = $this->emission->certifier(
            $this->emission->emettrePourReservation($this->reservation, '25000.00'),
        );

        $avant = $facture->only(['montant_ht', 'montant_ttc', 'statut', 'numero_mecef']);

        $avoir = $this->emission->emettreAvoir($facture, '75000.00', 'Séjour écourté');

        $this->assertSame('75000.00', $avoir->montant);
        $this->assertSame($facture->id, $avoir->facture_id);
        $this->assertNotNull($avoir->utilisateur_validation_id);

        // La facture d'origine est rigoureusement inchangée — c'est le point.
        $this->assertSame($avant, $facture->fresh()->only(['montant_ht', 'montant_ttc', 'statut', 'numero_mecef']));
        $this->assertCount(1, $facture->avoirs()->get());
    }

    #[Test]
    public function un_avoir_ne_peut_pas_depasser_le_montant_de_la_facture(): void
    {
        $facture = $this->emission->emettrePourReservation($this->reservation, '25000.00');

        $this->expectException(\InvalidArgumentException::class);
        $this->emission->emettreAvoir($facture, '100000.00', 'Montant aberrant');
    }

    /**
     * PA-17 non résolue : la certification doit être explicitement factice.
     */
    #[Test]
    public function la_certification_de_demonstration_est_impossible_a_confondre_avec_une_vraie(): void
    {
        $facture = $this->emission->certifier(
            $this->emission->emettrePourReservation($this->reservation, '25000.00'),
        );

        $this->assertStringStartsWith('MECEF-DEMO-', (string) $facture->numero_mecef);
        $this->assertSame('DONNEES-NON-CERTIFIEES-DEMO', $facture->qr_code_fiscal);
        $this->assertTrue($facture->estCertificationDemonstration());
        $this->assertTrue($this->emission->modeDemonstration());
    }

    /**
     * Les deux prédicats disent deux choses différentes, et c'est le point.
     *
     * `estCertifiee()` rendait `true` en démonstration jusqu'au 20/08/2026 : il
     * ne lisait que `statut`, que la certification factice met à `certifiee`.
     * Rien ne se voyait, ses deux seuls appelants s'en servant pour figer la
     * facture — mais le premier badge ou en-tête de PDF qui l'aurait consulté
     * pour dire « certifiée » aurait annoncé un fait fiscal qui n'a pas eu lieu.
     * C'est PA-61 déplacé du badge Paramètres vers le document lui-même.
     */
    #[Test]
    public function une_facture_de_demonstration_est_figee_mais_PAS_certifiee(): void
    {
        $facture = $this->emission->certifier(
            $this->emission->emettrePourReservation($this->reservation, '25000.00'),
        );

        $this->assertSame('certifiee', $facture->statut);

        // Figée : le chemin d'immuabilité doit être emprunté hors Production,
        // sans quoi personne ne saurait s'il fonctionne (famille PA-59).
        $this->assertTrue(
            $facture->estFigee(),
            'une facture de demonstration se fige comme une vraie',
        );

        // Certifiée : non. Aucune valeur fiscale — le numéro le dit, et c'est
        // le numéro qui fait foi, jamais le statut.
        $this->assertFalse(
            $facture->estCertifiee(),
            'une facture MECEF-DEMO- ne porte AUCUNE certification fiscale',
        );
    }

    /**
     * Le corollaire : figée veut bien dire immuable, y compris en démonstration.
     *
     * **Ce cas épingle la PROPRIÉTÉ, pas la ligne de garde du service** — et la
     * nuance a été établie par mutation, pas supposée. Remettre `estCertifiee()`
     * dans `EmissionFactureService::ajouterLigne()` laisse ce test VERT : c'est
     * `FactureObserver::updating()` qui refuse en réalité, la ligne ajoutée
     * entraînant un recalcul des montants sur une facture certifiée, et la
     * transaction est annulée.
     *
     * La garde du service est donc **redondante avec l'Observer**. Ce n'est pas
     * un défaut : sur une table financière, la défense en profondeur est la
     * règle du dépôt, et le service refuse plus tôt avec un message plus clair.
     * Mais il faut le savoir — croire que cette garde est la seule conduirait à
     * la déplacer un jour en pensant déplacer la protection.
     *
     * C'est la même architecture que RG-11 en comptabilité, où l'immuabilité vit
     * dans un `Observer` et jamais dans un service : l'Observer couvre aussi la
     * synchronisation différée et les jobs, qu'un contrôle de service manquerait.
     */
    #[Test]
    public function la_garde_d_immuabilite_tient_sur_une_facture_de_demonstration(): void
    {
        $facture = $this->emission->certifier(
            $this->emission->emettrePourReservation($this->reservation, '25000.00'),
        );

        $this->expectException(FactureImmuableException::class);

        $this->emission->ajouterLigne(
            $facture,
            'M1',
            (string) Str::uuid(),
            'Nuitée supplémentaire',
            '1',
            '25000.00',
        );
    }

    #[Test]
    public function la_bascule_reste_en_mode_demonstration_sans_cle_api(): void
    {
        $this->assertFalse(app(MecefClientInterface::class)->estModeReel());
        $this->assertSame('non_configuree', MecefServiceProvider::etatConfiguration());
    }

    /**
     * Le badge de l'écran Paramètres doit distinguer trois états, pas deux :
     * « numéro renseigné mais clé absente » est une situation réelle qu'un
     * administrateur doit pouvoir diagnostiquer (MECEF_INTEGRATION_SPEC.md §7.4).
     */
    #[Test]
    public function un_numero_contribuable_sans_cle_api_donne_un_etat_partiel(): void
    {
        ParametreSysteme::create([
            'cle' => 'entreprise_numero_mecef',
            'valeur' => '1234567890123',
            'description' => 'N° Contribuable MECeF',
        ]);

        $this->assertSame('configuration_partielle', MecefServiceProvider::etatConfiguration());
        // Et surtout : toujours pas de bascule en mode réel.
        $this->assertFalse(app(MecefClientInterface::class)->estModeReel());
    }

    /**
     * Le cas qui manquait, et qui mentait (PA-61).
     *
     * Configuration COMPLETE : numero renseigne et cle API reelle. La version
     * precedente renvoyait `active` — alors que `register()` liait le faux
     * client dans les DEUX branches de son ternaire. Le badge de l'ecran
     * Parametres aurait annonce « active » pendant que chaque facture partait
     * avec `DONNEES-NON-CERTIFIEES-DEMO` en cachet fiscal.
     *
     * Meme famille que le fichier de sauvegarde de 802 octets (PA-60) : un
     * indicateur qui dit « tout va bien » pendant que rien n'a lieu. Mais ici
     * sur une matiere fiscale, et sur un document remis au client.
     */
    #[Test]
    public function une_configuration_complete_ne_suffit_pas_a_dire_active(): void
    {
        ParametreSysteme::create([
            'cle' => 'entreprise_numero_mecef',
            'valeur' => '1234567890123',
            'description' => 'N° Contribuable MECeF',
        ]);
        config(['services.mecef.api_key' => 'cle-dgi-parfaitement-reelle']);

        // La configuration, elle, est bien en etat.
        $this->assertTrue(MecefServiceProvider::estModeReelDisponible());

        // Mais rien n'est certifie pour autant : PA-17 n'est pas resolue,
        // `MecefClient` n'existe pas, le faux client reste le seul liable.
        $this->assertFalse(app(MecefClientInterface::class)->estModeReel());
        $this->assertSame('en_attente_implementation', MecefServiceProvider::etatConfiguration());
    }

    /**
     * Le garde-fou de la resolution de PA-17.
     *
     * `active` ne doit devenir atteignable que le jour ou un client dont
     * `estModeReel()` est vrai est reellement lie. Ce test lie un tel client a
     * la main : c'est la seule maniere d'eprouver aujourd'hui la branche que
     * l'implementation reelle empruntera demain.
     */
    #[Test]
    public function actif_exige_un_client_reellement_en_mode_reel(): void
    {
        ParametreSysteme::create([
            'cle' => 'entreprise_numero_mecef',
            'valeur' => '1234567890123',
            'description' => 'N° Contribuable MECeF',
        ]);
        config(['services.mecef.api_key' => 'cle-dgi-parfaitement-reelle']);

        $this->app->bind(MecefClientInterface::class, fn () => new class () implements MecefClientInterface {
            public function certifier(Facture $facture): CertificationMecefResultat
            {
                return new CertificationMecefResultat(
                    nim: 'MECEF-REEL-0000',
                    cachetFiscal: 'CACHET-REEL',
                    dateCertification: new DateTimeImmutable(),
                );
            }

            public function estModeReel(): bool
            {
                return true;
            }
        });

        $this->assertSame('active', MecefServiceProvider::etatConfiguration());
    }

    /**
     * Et l'inverse : une cle absente ne peut jamais donner `active`, meme si
     * un client en mode reel etait lie par erreur.
     */
    #[Test]
    public function un_client_reel_sans_configuration_ne_donne_pas_active(): void
    {
        $this->app->bind(MecefClientInterface::class, fn () => new class () implements MecefClientInterface {
            public function certifier(Facture $facture): CertificationMecefResultat
            {
                return new CertificationMecefResultat(
                    nim: 'MECEF-REEL-0000',
                    cachetFiscal: 'CACHET-REEL',
                    dateCertification: new DateTimeImmutable(),
                );
            }

            public function estModeReel(): bool
            {
                return true;
            }
        });

        $this->assertSame('non_configuree', MecefServiceProvider::etatConfiguration());
    }

    #[Test]
    public function la_cle_api_n_est_jamais_stockee_en_base(): void
    {
        // Vérification structurelle : aucun paramètre en base ne doit porter
        // une clé API (MECEF_INTEGRATION_SPEC.md §7.1).
        ParametreSysteme::create([
            'cle' => 'entreprise_numero_mecef', 'valeur' => '1234567890123', 'description' => 'N° MECeF',
        ]);

        $cles = ParametreSysteme::pluck('cle')->all();

        foreach ($cles as $cle) {
            $this->assertStringNotContainsStringIgnoringCase('api_key', $cle);
            $this->assertStringNotContainsStringIgnoringCase('token', $cle);
            $this->assertStringNotContainsStringIgnoringCase('secret', $cle);
        }
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.' . Str::random(5),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}

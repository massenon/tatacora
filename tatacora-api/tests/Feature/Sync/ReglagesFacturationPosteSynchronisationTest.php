<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Comptabilite\Models\AffectationResultat;
use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\AffectationResultatService;
use App\Domain\Comptabilite\Services\ClotureExerciceService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Domain\Comptabilite\Support\FormeJuridique;
use App\Domain\Facturation\Services\ModeFacturation;
use App\Domain\Facturation\Services\ReglagesDocuments;
use App\Domain\Facturation\Services\ReglagesMecef;
use App\Models\User;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Parametres\Services\EnregistrerParametreService;
use App\Shared\Rbac\Models\JournalSecurite;
use App\Shared\Rbac\Models\Role;
use App\Shared\Rbac\Services\RolePermissionService;
use App\Shared\Secrets\Services\SecretsConfigurationService;
use App\Shared\Sync\Gestionnaires\GestionnaireParametres;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Les réglages MECeF et la forme juridique ÉCRITS DEPUIS UN POSTE (09/11/2026, décision
 * du PO : « le poste fait ce que le web fait »). Avant : le serveur les écartait de tout
 * envoi de poste, qui les recevait en lecture seule. Maintenant : un poste les écrit si
 * le compte de son JETON D'APPAIRAGE est administrateur (la règle de l'écran web), sinon
 * rejet `droit_manquant` lisible ; mêmes validations que l'écran ; le JETON e-MECeF,
 * lui, n'est jamais un paramètre — il ne monte pas, il ne descend pas.
 */
final class ReglagesFacturationPosteSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private const IFU = '0202011344660';

    private const JETON = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0LW5vbi1yZWVsIn0.c2lnbmF0dXJlLW5vbi1yZWVsbGU';

    private User $admin;

    /** Un compte qui écrit PARAM (donc « Modifier » partout au web, hors réglages réservés) sans être administrateur. */
    private User $comptable;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-11-09 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->admin = $this->creerUtilisateur('administrateur');

        $role = app(RolePermissionService::class)->creerRole('comptable_essai', null);
        app(RolePermissionService::class)->definirNiveau($role, 'PARAM', 'C');
        $this->comptable = User::create([
            'login' => 'comptable.' . uniqid(),
            'mot_de_passe_hash' => bcrypt('mot-de-passe-de-test'),
            'role_id' => $role->id,
            'statut' => 'actif',
        ]);
    }

    /**
     * @param  array<string, scalar|null>  $valeurs
     * @return array<string, mixed>
     */
    private function enregistrement(array $valeurs, ?string $saisiLe = null): array
    {
        $op = $this->creation('parametres_systeme', $this->uuid(), ['valeurs' => $valeurs]);

        if ($saisiLe !== null) {
            $op['horodatage_client'] = $saisiLe;
        }

        return $op;
    }

    private function valeur(string $cle): ?string
    {
        return ParametreSysteme::where('cle', $cle)->value('valeur');
    }

    /** @return array<string, mixed> */
    private function reglagesComplets(string $mode = 'boitier'): array
    {
        return [
            'entreprise_ifu' => self::IFU,
            ReglagesMecef::CLE_OPERATEUR_ID => 'RECEPTION01',
            ReglagesMecef::CLE_OPERATEUR_NOM => 'Réception',
            ReglagesMecef::CLE_API_URL => 'https://sygmef.exemple.bj/api',
            ModeFacturation::CLE => $mode,
        ];
    }

    #[Test]
    public function un_administrateur_regle_le_mode_l_api_et_l_operateur_depuis_un_poste(): void
    {
        $this->pousser([$this->enregistrement($this->reglagesComplets())], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.cles_conservees', []);

        $this->assertSame('boitier', $this->valeur(ModeFacturation::CLE));
        $this->assertSame('https://sygmef.exemple.bj/api', $this->valeur(ReglagesMecef::CLE_API_URL));
        $this->assertSame('RECEPTION01', $this->valeur(ReglagesMecef::CLE_OPERATEUR_ID));
        $this->assertSame('Réception', $this->valeur(ReglagesMecef::CLE_OPERATEUR_NOM));
        $this->assertSame(ModeFacturation::Boitier, ModeFacturation::courant());
    }

    #[Test]
    public function un_administrateur_regle_la_forme_juridique_depuis_un_poste(): void
    {
        $this->pousser([$this->enregistrement([FormeJuridique::CLE => 'sarl'])], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame(FormeJuridique::Sarl, FormeJuridique::courante());
    }

    #[Test]
    public function un_compte_non_administrateur_est_rejete_droit_manquant_avec_la_phrase_de_l_ecran(): void
    {
        $this->assertTrue($this->comptable->niveauSurModule('PARAM') === 'C' && ! $this->comptable->estAdministrateur());

        foreach ([
            ModeFacturation::CLE => 'boitier',
            ReglagesMecef::CLE_API_URL => 'https://sygmef.exemple.bj/api',
            ReglagesMecef::CLE_OPERATEUR_ID => 'R1',
            ReglagesMecef::CLE_OPERATEUR_NOM => 'Réception',
        ] as $cle => $valeur) {
            $this->pousser([$this->enregistrement([$cle => $valeur, 'tolerance_reception_pct' => '6'])], $this->comptable)
                ->assertJsonPath('resultats.0.statut', 'rejete')
                ->assertJsonPath('resultats.0.code_motif', 'droit_manquant')
                ->assertJsonPath('resultats.0.motif', __('parametres.mecef_reserve_administrateur'));
            $this->assertNull($this->valeur($cle), $cle);
        }

        $this->pousser([$this->enregistrement([FormeJuridique::CLE => 'sarl'])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.code_motif', 'droit_manquant')
            ->assertJsonPath('resultats.0.motif', __('parametres.forme_juridique_reservee_administrateur'));
        $this->assertSame(FormeJuridique::EntrepriseIndividuelle, FormeJuridique::courante());

        // L'opération entière est rejetée : la clé ordinaire du même lot n'est pas écrite non plus.
        $this->assertNull($this->valeur('tolerance_reception_pct'));
        // Et le refus est TRACÉ comme tout accès refusé.
        $this->assertSame(5, JournalSecurite::where('type_evenement', 'acces_refuse_rbac')->where('utilisateur_id', $this->comptable->id)->count());
    }

    #[Test]
    public function les_reglages_des_documents_s_ecrivent_avec_le_seul_droit_param_comme_au_web(): void
    {
        $this->pousser([$this->enregistrement([
            ReglagesDocuments::CLE_ACTIVITES => 'Tourisme, Hébergement',
            ReglagesDocuments::CLE_REFERENCE_FACTURE => 'GCN',
            ReglagesDocuments::CLE_VALIDITE_JOURS => '45',
            ReglagesDocuments::CLE_SIGNATURE_AFFICHEE => 'true',
        ])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame('Tourisme, Hébergement', $this->valeur(ReglagesDocuments::CLE_ACTIVITES));
        $this->assertSame('45', $this->valeur(ReglagesDocuments::CLE_VALIDITE_JOURS));
        $this->assertSame('true', $this->valeur(ReglagesDocuments::CLE_SIGNATURE_AFFICHEE));
    }

    #[Test]
    public function un_barman_sans_param_est_refuse_comme_pour_toute_cle(): void
    {
        $this->pousser([$this->enregistrement([ReglagesDocuments::CLE_ACTIVITES => 'X'])], $this->creerUtilisateur('barman'))
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.code_motif', 'droit_manquant');
        $this->assertNull($this->valeur(ReglagesDocuments::CLE_ACTIVITES));
    }

    /**
     * Les validations de l'écran, REJOUÉES : une valeur refusée rejette l'opération entière et
     * n'écrit rien. Chaque cas porte la phrase du refus.
     */
    #[Test]
    public function les_validations_de_l_ecran_sont_rejouees(): void
    {
        $cas = [
            'mode inconnu' => [[ModeFacturation::CLE => 'quantique'], __('parametres.valeur_choix_inconnu', ['libelle' => 'Mode', 'valeur' => 'quantique'])],
            'adresse sans https' => [[ReglagesMecef::CLE_API_URL => 'http://sygmef.exemple.bj'], __('parametres.valeur_https', ['libelle' => 'Adresse de l’API de la DGI'])],
            'adresse avec espace' => [[ReglagesMecef::CLE_API_URL => 'https://a b.bj'], __('parametres.valeur_https', ['libelle' => 'Adresse de l’API de la DGI'])],
            'nom de 31 caractères' => [[ReglagesMecef::CLE_OPERATEUR_NOM => str_repeat('n', 31)], __('parametres.valeur_trop_longue', ['libelle' => 'Nom de l’opérateur', 'max' => 30])],
            'identifiant de 31 caractères' => [[ReglagesMecef::CLE_OPERATEUR_ID => str_repeat('i', 31)], __('parametres.valeur_trop_longue', ['libelle' => 'Identifiant de l’opérateur', 'max' => 30])],
            'forme inconnue' => [[FormeJuridique::CLE => 'gie'], __('parametres.valeur_choix_inconnu', ['libelle' => 'Forme juridique', 'valeur' => 'gie'])],
            'référence non alphanumérique' => [[ReglagesDocuments::CLE_REFERENCE_FACTURE => 'G-N'], __('parametres.valeur_alphanumerique', ['libelle' => 'Référence facture'])],
            'validité hors bornes' => [[ReglagesDocuments::CLE_VALIDITE_JOURS => '400'], __('parametres.valeur_entre', ['libelle' => 'Durée de validité d’une proforma (jours)', 'min' => 1, 'max' => 365])],
            'interrupteur vide' => [[ReglagesDocuments::CLE_SIGNATURE_AFFICHEE => ''], __('parametres.valeur_booleen', ['libelle' => 'Afficher la signature et le cachet sur les factures'])],
            'mode sans opérateur ni IFU' => [[ModeFacturation::CLE => 'boitier'], __('parametres.mecef_mode_refuse', [
                'mode' => ModeFacturation::Boitier->libelle(),
                'manques' => __('parametres.mecef_manque_ifu') . ' ' . __('parametres.mecef_manque_operateur'),
            ])],
            'e-MECeF sans jeton' => [[...$this->reglagesComplets('emecef')], __('parametres.mecef_mode_refuse', [
                'mode' => ModeFacturation::Emecef->libelle(),
                'manques' => __('parametres.mecef_manque_jeton'),
            ])],
        ];

        foreach ($cas as $nom => [$valeurs, $phrase]) {
            $this->pousser([$this->enregistrement($valeurs)], $this->admin)
                ->assertJsonPath('resultats.0.statut', 'rejete', $nom)
                ->assertJsonPath('resultats.0.motif', $phrase, $nom);
            foreach (array_keys($valeurs) as $cle) {
                $this->assertNull($this->valeur($cle), $nom . ' : ' . $cle);
            }
        }
    }

    #[Test]
    public function la_forme_juridique_est_refusee_tant_qu_une_affectation_est_active(): void
    {
        $this->poserUneAffectationActive();

        $this->pousser([$this->enregistrement([FormeJuridique::CLE => 'sarl'])], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('parametres.forme_juridique_affectation_active'));
        $this->assertSame(FormeJuridique::EntrepriseIndividuelle, FormeJuridique::courante());

        // La même valeur que l'actuelle n'est pas un changement : acceptée.
        $this->pousser([$this->enregistrement([FormeJuridique::CLE => 'entreprise_individuelle'])], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
    }

    #[Test]
    public function le_jeton_e_mecef_n_est_pas_un_parametre_il_ne_monte_ni_ne_descend(): void
    {
        $this->pousser([$this->enregistrement(['mecef_jeton_api' => self::JETON])], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'rejete');
        $this->assertNull($this->valeur('mecef_jeton_api'));
        $this->assertSame(0, DB::table('secrets_configuration')->count());

        // Avec un jeton réellement enregistré au serveur, la descente d'un autre poste ne le porte pas.
        app(SecretsConfigurationService::class)->enregistrer(SecretsConfigurationService::MECEF_JETON, self::JETON, $this->admin);
        $this->pousser([$this->enregistrement($this->reglagesComplets('emecef'))], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->travel(10)->seconds();
        Sanctum::actingAs($this->creerUtilisateur('gerant'));
        $corps = '';
        $elements = [];
        $curseur = null;
        do {
            $r = $this->getJson('/api/v1/referentiels?' . http_build_query(array_filter(['poste_id' => 'poste-b', 'depuis' => $curseur, 'limite' => 500])))->assertOk();
            $corps .= $r->getContent();
            $elements = [...$elements, ...$r->json('data.elements')];
            $curseur = $r->json('meta.curseur');
        } while (! $r->json('meta.complet'));

        $this->assertStringNotContainsString(self::JETON, $corps);
        $this->assertStringNotContainsString(SecretsConfigurationService::MECEF_JETON, $corps);
        $descendus = collect($elements)->where('table', 'parametres_systeme')
            ->mapWithKeys(static fn (array $e): array => [$e['donnees']['cle'] => $e['donnees']['valeur']]);
        // …mais le mode, lui, redescend aux autres postes.
        $this->assertSame('emecef', $descendus[ModeFacturation::CLE]);
        $this->assertSame('RECEPTION01', $descendus[ReglagesMecef::CLE_OPERATEUR_ID]);
    }

    #[Test]
    public function le_rejeu_est_idempotent_et_le_dernier_ecrit_gagne_cle_par_cle(): void
    {
        $operation = $this->enregistrement($this->reglagesComplets());
        $this->pousser([$operation], $this->admin)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->pousser([$operation], $this->admin)->assertJsonPath('resultats.0.rejeu_idempotent', true);
        $this->assertSame(1, ParametreSysteme::where('cle', ModeFacturation::CLE)->count());

        // Modifié au serveur APRÈS la saisie du poste : la valeur du serveur reste, rapportée au poste.
        $this->travel(5)->minutes();
        $this->actingAs($this->admin);
        app(EnregistrerParametreService::class)->enregistrer([ReglagesMecef::CLE_OPERATEUR_NOM => 'Direction']);
        $this->pousser([$this->enregistrement(
            [ReglagesMecef::CLE_OPERATEUR_NOM => 'Caisse', ReglagesMecef::CLE_OPERATEUR_ID => 'CAISSE02'],
            now()->subMinutes(2)->toIso8601String(),
        )], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.cles_conservees', [ReglagesMecef::CLE_OPERATEUR_NOM]);
        $this->assertSame('Direction', $this->valeur(ReglagesMecef::CLE_OPERATEUR_NOM));
        $this->assertSame('CAISSE02', $this->valeur(ReglagesMecef::CLE_OPERATEUR_ID));
    }

    #[Test]
    public function la_liste_des_cles_reservees_est_celle_des_cinq_reglages(): void
    {
        $this->assertEqualsCanonicalizing(
            ['facturation_mode', 'mecef_api_url', 'mecef_operateur_id', 'mecef_operateur_nom', 'forme_juridique'],
            GestionnaireParametres::CLES_ADMINISTRATEUR,
        );
        $this->assertSame(
            [],
            array_values(array_filter(GestionnaireParametres::CLES_CONTROLEES, static fn (string $c): bool => str_contains($c, 'jeton'))),
        );
    }

    /** Une affectation du résultat ACTIVE : un bénéfice de 70 000 en 2026, exercice clôturé, tout au compte de l'exploitant. */
    private function poserUneAffectationActive(): void
    {
        $this->seed(ComptabiliteReferentielSeeder::class);
        $comptable = User::create([
            'login' => 'comptable.aff.' . uniqid(),
            'mot_de_passe_hash' => bcrypt('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'comptable')->firstOrFail()->id,
            'statut' => 'actif',
        ]);
        $this->actingAs($comptable);
        $centre = static fn (string $l): string => (string) CentreCout::query()->where('libelle', $l)->value('id');
        $passer = app(PasserEcritureService::class);
        $passer->passerEtValider(['journal' => 'CAI', 'date' => '2026-03-10', 'libelle' => 'Ventes bar', 'lignes' => [
            ['compte' => '5711', 'debit' => '100000.00'],
            ['compte' => '7011', 'credit' => '100000.00', 'centre_id' => $centre('Bar')],
        ]]);
        $passer->passerEtValider(['journal' => 'CAI', 'date' => '2026-03-11', 'libelle' => 'Achats', 'lignes' => [
            ['compte' => '6011', 'debit' => '30000.00', 'centre_id' => $centre('Restaurant')],
            ['compte' => '5711', 'credit' => '30000.00'],
        ]]);
        $exercice = ExerciceComptable::query()->where('annee', 2026)->firstOrFail();
        $cloture = app(ClotureExerciceService::class);
        $cloture->demarrer($exercice, $comptable);
        $cloture->cloturer($exercice->refresh(), $comptable);
        app(AffectationResultatService::class)->affecter($exercice->refresh(), [
            'reserve_legale' => '0', 'autres_reserves' => '0', 'dividendes' => '0',
            'report_a_nouveau' => '0', 'imputation_report_crediteur' => '0', 'compte_exploitant' => '70000',
        ], '2027-04-30', $comptable);
        $this->assertTrue(AffectationResultat::query()->whereNull('contrepassee_le')->exists());
    }
}

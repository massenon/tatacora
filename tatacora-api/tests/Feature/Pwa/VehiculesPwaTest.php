<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Crm\Models\Client;
use App\Domain\Vehicules\Models\ContratLocation;
use App\Domain\Vehicules\Models\EntretienVehicule;
use App\Domain\Vehicules\Models\Vehicule;
use App\Models\User;
use App\Pwa\Livewire\Vehicules\Locations;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Pwa\Concerns\OuvreLaSaisie;
use Tests\TestCase;

/**
 * M8 en ÉCRITURE — `m8-locations.html`, vague CRUD du 31/08/2026.
 *
 * Ce fichier remplace la suite de la vague « lecture seule » : la PWA écrit
 * depuis le 28/08/2026 (PA-159), et une garde qui vérifiait l'absence
 * d'écriture serait désormais fausse — c'est exactement le motif périmé de
 * PA-144.
 *
 * Ce qu'il tient, et qui n'est vérifié nulle part ailleurs :
 *
 *  1. **Le RBAC d'écriture.** Un `receptionniste` (M8 = `L`) LIT l'écran et se
 *     voit refuser chaque geste — c'est le défaut V1, « zéro contrôle RBAC
 *     d'écriture », qui donnait par le navigateur ce que l'API refuse en 403.
 *  2. **Aucune suppression.** Archiver un véhicule le passe `hors_service`,
 *     annuler un contrat le passe `annule` : les DEUX lignes existent encore
 *     après le geste. Le lot précédent appelait `$vehicule->delete()`.
 *  3. **Le verrou d'archivage** est lu EN BASE et bloque réellement.
 *  4. **RG-09** est appliquée depuis `Vehicule::exigePermis()`, et RG-08 par
 *     le service sous verrou.
 *  5. **Les colonnes financières sont réellement écrites** — elles ne figurent
 *     pas au `$fillable` du modèle de domaine, et une affectation de masse les
 *     jetterait en silence.
 *
 * ## Mutations RÉELLEMENT EXÉCUTÉES le 31/08/2026 — les quatre ont mordu
 *
 * Chacune a été appliquée au composant, la cible relancée, puis le fichier
 * remis en l'état. Un test qui ne peut pas échouer ne compte pas.
 *
 * | Mutation                                                     | Cible rougie |
 * |--------------------------------------------------------------|--------------|
 * | retirer les trois clés de montant du `forceFill()`            | `le_contrat_porte_ses_montants_et_un_numero_alloue` |
 * | archiver en `disponible` au lieu de `hors_service`            | `archiver_un_vehicule_ne_le_supprime_jamais` |
 * | faire rendre `[]` à `verrousDuVehicule()`                     | `un_vehicule_engage_ne_s_archive_pas` |
 * | neutraliser le contrôle `exigePermis()`                       | `rg09_le_permis_est_exige_hors_categorie_dispensee` |
 *
 * @see EF-M8-01, EF-M8-03, EF-M8-05
 * @see RG-08 Prévention des doubles locations
 * @see RG-09 Pièces justificatives conditionnelles
 * @see RG-18 Fiche client unique
 */
final class VehiculesPwaTest extends TestCase
{
    use OuvreLaSaisie;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    // ------------------------------------------------------------- fixtures

    private function compte(string $role): User
    {
        return User::create([
            'login' => $role.'.m8.'.bin2hex(random_bytes(3)),
            'mot_de_passe_hash' => Hash::make('MotDePasseTresLong!2026'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    private function vehicule(string $categorie = '4x4', string $statut = 'disponible'): Vehicule
    {
        return Vehicule::create([
            'immatriculation' => 'AB '.random_int(1000, 9999).' RB',
            'categorie' => $categorie,
            'annee' => 2022,
            'transmission' => 'Manuelle',
            'capacite' => 5,
            'tarif_jour' => '70000.00',
            'statut' => $statut,
        ]);
    }

    private function client(): Client
    {
        return Client::create([
            'nom' => 'Agence Bénin Tour',
            'telephone' => '+229 01 97 00 00',
            'type_client' => 'structure',
        ]);
    }

    // =====================================================================
    // 1. L'écran est servi, et son RBAC de lecture tient
    // =====================================================================

    #[Test]
    public function les_quatre_onglets_du_maitre_sont_servis(): void
    {
        $this->vehicule();

        foreach (Locations::ONGLETS as $onglet) {
            $this->actingAs($this->compte('vehicules'))
                ->get('/pwa/vehicules?onglet='.$onglet)
                ->assertOk()
                ->assertSee('Véhicules &amp; Locations', false);
        }
    }

    /**
     * L'ONGLET IMMOBILISATIONS VIDE PORTE QUAND MÊME SES SEPT EN-TÊTES —
     * défaut relevé par l'audit navigateur du Product Owner (01/09/2026) :
     * l'état vide remplaçait le tableau ENTIER par une phrase centrée, si
     * bien qu'un onglet sans aucune immobilisation n'affichait aucun
     * en-tête de colonne. Le maître (`m8-locations.js` l.414) montre
     * toujours les sept colonnes, même sans ligne.
     *
     * Éprouvé par mutation le 02/09/2026 : remettre le `@if`/`@else` qui
     * substituait le tableau entier par la phrase vide fait rougir ce cas
     * sur « Motif » absent — restauré ensuite.
     */
    #[Test]
    public function l_onglet_immobilisations_vide_rend_ses_sept_en_tetes(): void
    {
        // Aucun véhicule immobilisé n'existe : le tableau est VIDE.
        $this->vehicule();

        $html = (string) $this->actingAs($this->compte('vehicules'))
            ->get('/pwa/vehicules?onglet=immo')
            ->assertOk()
            ->getContent();

        foreach (['col_vehicule', 'col_motif', 'col_du', 'col_au', 'col_jours', 'col_commentaire', 'col_enregistre_par'] as $colonne) {
            $this->assertStringContainsString(
                e((string) __('vehicules.pwa.'.$colonne)),
                $html,
                "L'en-tête « {$colonne} » n'est pas rendu quand l'onglet est vide.",
            );
        }

        $this->assertStringContainsString(__('vehicules.pwa.immo_vide'), $html);
    }

    #[Test]
    public function un_role_sans_acces_au_module_ne_voit_pas_l_ecran(): void
    {
        // `barman` porte M8 = '-' : le middleware `module:M8,L` refuse.
        $this->actingAs($this->compte('barman'))
            ->get('/pwa/vehicules')
            ->assertForbidden();
    }

    // =====================================================================
    // 2. V1 — le RBAC d'ÉCRITURE, absent du lot précédent
    // =====================================================================

    /**
     * Le défaut mesuré le 31/08/2026 : un rôle en lecture seule établissait un
     * contrat depuis son navigateur, quand l'API le lui refuse en 403.
     */
    #[Test]
    public function le_role_lecture_seule_se_voit_refuser_chaque_geste_d_ecriture(): void
    {
        $vehicule = $this->vehicule();
        $client = $this->client();
        $lecteur = $this->compte('receptionniste');   // M8 = 'L'

        $gestes = [
            ['ouvrirFormulaireVehicule', []],
            ['enregistrerVehicule', []],
            ['ouvrirFormulaireContrat', []],
            ['enregistrerContrat', []],
            ['ouvrirFormulaireImmobilisation', []],
            ['enregistrerImmobilisation', []],
            ['confirmerArchivage', ['vehicule', $vehicule->id]],
            ['executerSuppression', []],
            ['remettreEnService', [$vehicule->id]],
        ];

        foreach ($gestes as [$methode, $arguments]) {
            $this->actingAs($lecteur);

            Livewire::test(Locations::class)
                ->call($methode, ...$arguments)
                ->assertForbidden();
        }

        // Et rien n'a été écrit : le refus précède la validation comme dans
        // l'API — un rôle sans droit n'apprend rien de ses données.
        $this->assertSame(0, ContratLocation::count());
        $this->assertSame('disponible', $vehicule->fresh()->statut);
        $this->assertNotNull($client->fresh());
    }

    // =====================================================================
    // 3. Le contrat — RG-08, RG-09, et les montants réellement persistés
    // =====================================================================

    #[Test]
    public function la_modale_de_contrat_rend_exactement_les_champs_du_maitre(): void
    {
        $this->vehicule();
        $this->client();

        $this->assertLaModaleSOuvreEtRendExactementSesChamps(
            $this->compte('vehicules'),
            Locations::class,
            'ouvrirFormulaireContrat',
            [
                'vehiculeIdContrat', 'dateDebutContrat', 'dateFinContrat',
                'clientIdContrat', 'pieceIdentiteSaisie', 'numeroPermisSaisi',
                'remiseSaisie', 'acompteSaisi',
            ],
        );
    }

    /**
     * Les six colonnes de `2026_08_28_200000_add_missing_pwa_columns.php` ne
     * sont PAS au `$fillable` de `ContratLocation`. Une affectation de masse
     * les jetterait sans un mot : le montant resterait à zéro sur l'écran
     * même où l'on réclame le solde.
     */
    #[Test]
    public function le_contrat_porte_ses_montants_et_un_numero_alloue(): void
    {
        $vehicule = $this->vehicule('bus');   // exige un permis
        $client = $this->client();

        $this->actingAs($this->compte('vehicules'));

        Livewire::test(Locations::class)
            ->call('ouvrirFormulaireContrat', $vehicule->id)
            ->set('clientIdContrat', $client->id)
            ->set('pieceIdentiteSaisie', 'CNI-2026-114')
            ->set('numeroPermisSaisi', 'PC-778')
            ->set('dateDebutContrat', '2026-09-01')
            ->set('dateFinContrat', '2026-09-04')
            ->set('remiseSaisie', '10000')
            ->set('acompteSaisi', '50000')
            ->call('enregistrerContrat')
            ->assertHasNoErrors();

        $contrat = ContratLocation::firstOrFail();

        // 3 jours x 70 000 = 210 000, moins 10 000 de remise = 200 000.
        $this->assertSame(0, bccomp((string) $contrat->montant, '200000', 2));
        $this->assertSame(0, bccomp((string) $contrat->acompte, '50000', 2));
        $this->assertSame(0, bccomp((string) $contrat->reste_a_payer, '150000', 2));

        // Le numéro est ALLOUÉ, jamais six caractères d'un UUID.
        $this->assertSame('LOC-'.date('Y').'-00001', $contrat->numero);
        $this->assertSame('actif', $contrat->statut);

        // RG-18 : le client est une clé étrangère, et `client_nom` reste vide.
        $this->assertSame($client->id, $contrat->client_id);
        $this->assertNull($contrat->client_nom);
    }

    /**
     * RG-09 — la question est posée à `Vehicule::exigePermis()`, seul endroit
     * qui connaisse `CATEGORIES_SANS_PERMIS` (PA-50).
     */
    #[Test]
    public function rg09_le_permis_est_exige_hors_categorie_dispensee(): void
    {
        $client = $this->client();
        $quatreQuatre = $this->vehicule('4x4');
        $moto = $this->vehicule('moto');

        $sansPermis = static fn (Vehicule $v) => Livewire::test(Locations::class)
            ->call('ouvrirFormulaireContrat', $v->id)
            ->set('clientIdContrat', null)
            ->set('pieceIdentiteSaisie', 'CNI-2026-115')
            ->set('numeroPermisSaisi', '')
            ->set('dateDebutContrat', '2026-10-01')
            ->set('dateFinContrat', '2026-10-03');

        Livewire::actingAs($this->compte('vehicules'));

        $sansPermis($quatreQuatre)
            ->set('clientIdContrat', $client->id)
            ->call('enregistrerContrat')
            ->assertHasErrors('numeroPermisSaisi');

        $this->assertSame(0, ContratLocation::count(), 'RG-09 : aucun contrat ne doit naître sans permis.');

        $sansPermis($moto)
            ->set('clientIdContrat', $client->id)
            ->call('enregistrerContrat')
            ->assertHasNoErrors();

        $this->assertSame(1, ContratLocation::count());
    }

    /**
     * RG-08 — le refus vient du SERVICE, sous verrou pessimiste, et son
     * message est AFFICHÉ. Le lot précédent l'avalait dans un `catch` qui
     * annonçait « Contrat de location créé ».
     */
    #[Test]
    public function rg08_un_second_contrat_chevauchant_est_refuse_et_le_dit(): void
    {
        $vehicule = $this->vehicule('moto');
        $client = $this->client();

        $poser = fn (string $debut, string $fin) => Livewire::test(Locations::class)
            ->call('ouvrirFormulaireContrat', $vehicule->id)
            ->set('clientIdContrat', $client->id)
            ->set('pieceIdentiteSaisie', 'CNI-2026-116')
            ->set('dateDebutContrat', $debut)
            ->set('dateFinContrat', $fin)
            ->call('enregistrerContrat');

        Livewire::actingAs($this->compte('vehicules'));

        $poser('2026-11-02', '2026-11-06')->assertHasNoErrors();
        $poser('2026-11-04', '2026-11-08')->assertHasErrors('vehiculeIdContrat');

        $this->assertSame(1, ContratLocation::count(), 'RG-08 : le second contrat ne doit pas exister.');
    }

    // =====================================================================
    // 4. V2 — archiver, jamais supprimer
    // =====================================================================

    #[Test]
    public function archiver_un_vehicule_ne_le_supprime_jamais(): void
    {
        $vehicule = $this->vehicule();

        $this->actingAs($this->compte('vehicules'));

        Livewire::test(Locations::class)
            ->call('confirmerArchivage', 'vehicule', $vehicule->id)
            ->assertSet('archivageBloque', false)
            ->call('executerSuppression');

        $apres = Vehicule::find($vehicule->id);

        $this->assertNotNull($apres, 'Le maître ARCHIVE : la ligne doit exister encore.');
        $this->assertSame('hors_service', $apres->statut);
    }

    #[Test]
    public function un_vehicule_engage_ne_s_archive_pas(): void
    {
        $vehicule = $this->vehicule('moto');
        $client = $this->client();

        Livewire::actingAs($this->compte('vehicules'));

        Livewire::test(Locations::class)
            ->call('ouvrirFormulaireContrat', $vehicule->id)
            ->set('clientIdContrat', $client->id)
            ->set('pieceIdentiteSaisie', 'CNI-2026-117')
            ->set('dateDebutContrat', now()->format('Y-m-d'))
            ->set('dateFinContrat', now()->addDays(4)->format('Y-m-d'))
            ->call('enregistrerContrat')
            ->assertHasNoErrors();

        $composant = Livewire::test(Locations::class)
            ->call('confirmerArchivage', 'vehicule', $vehicule->id)
            ->assertSet('archivageBloque', true);

        // Le maître MASQUE le bouton de confirmation dans cet état
        // (`crud-engine.js` l.535) : le laisser visible et inerte laisserait
        // croire à une panne.
        $composant->assertDontSee('wire:click="executerSuppression"', false);

        // Et le forcer depuis le navigateur ne passe pas non plus.
        $composant->call('executerSuppression')->assertForbidden();

        $this->assertSame('disponible', $vehicule->fresh()->statut);
    }

    #[Test]
    public function annuler_un_contrat_le_conserve_et_libere_le_vehicule(): void
    {
        $vehicule = $this->vehicule('moto');
        $client = $this->client();

        Livewire::actingAs($this->compte('vehicules'));

        Livewire::test(Locations::class)
            ->call('ouvrirFormulaireContrat', $vehicule->id)
            ->set('clientIdContrat', $client->id)
            ->set('pieceIdentiteSaisie', 'CNI-2026-118')
            ->set('dateDebutContrat', now()->format('Y-m-d'))
            ->set('dateFinContrat', now()->addDays(3)->format('Y-m-d'))
            ->call('enregistrerContrat');

        $contrat = ContratLocation::firstOrFail();

        Livewire::test(Locations::class)
            ->call('confirmerArchivage', 'contrat', $contrat->id)
            ->assertSet('archivageBloque', false)
            ->call('executerSuppression');

        $apres = ContratLocation::find($contrat->id);

        $this->assertNotNull($apres, 'Un contrat annulé reste une pièce lisible.');
        $this->assertSame('annule', $apres->statut);
        $this->assertSame(1, ContratLocation::count());
    }

    // =====================================================================
    // 5. L'immobilisation passe par le service, et ne pose aucun drapeau
    // =====================================================================

    #[Test]
    public function l_immobilisation_ecrit_un_entretien_sans_toucher_au_statut(): void
    {
        $vehicule = $this->vehicule();

        $this->actingAs($this->compte('vehicules'));

        Livewire::test(Locations::class)
            ->call('ouvrirFormulaireImmobilisation', $vehicule->id)
            ->set('motifImmo', EntretienVehicule::TYPE_ENTRETIEN)
            ->set('dateImmo', '2026-09-12')
            ->set('coutImmo', '35000')
            ->call('enregistrerImmobilisation')
            ->assertHasNoErrors();

        $entretien = EntretienVehicule::firstOrFail();

        $this->assertSame($vehicule->id, $entretien->vehicule_id);
        $this->assertSame(0, bccomp((string) $entretien->cout, '35000', 2));

        // `statut` n'est PAS la disponibilité (même distinction qu'en M1,
        // RG-02) : une immobilisation datée ne pose pas de drapeau permanent
        // que rien ne lèverait. Le lot précédent écrivait 'entretien' ici.
        $this->assertSame('disponible', $vehicule->fresh()->statut);
    }

    // =====================================================================
    // 6. Gardes de source — ce qui ne doit JAMAIS revenir
    // =====================================================================

    /**
     * Aucun `->delete()` dans le code ni la vue de M8.
     *
     * `BasePolicy::delete()` rend `false` pour les 20 policies, mais Livewire
     * n'invoque aucune Policy : le `delete()` du lot précédent s'exécutait.
     */
    #[Test]
    public function aucune_suppression_physique_ne_subsiste_dans_le_code_m8(): void
    {
        $fichiers = [
            app_path('Pwa/Livewire/Vehicules/Locations.php'),
            resource_path('views/pwa/vehicules/locations.blade.php'),
        ];

        foreach ($fichiers as $fichier) {
            $source = (string) file_get_contents($fichier);

            // Plancher : un fichier vide rendrait ce contrôle vert à vide.
            $this->assertGreaterThan(2000, strlen($source), "{$fichier} est trop court pour être le fichier attendu.");

            $this->assertDoesNotMatchRegularExpression(
                '/->\s*(?:force)?[dD]elete\s*\(/',
                $source,
                basename($fichier).' appelle une suppression physique. Le maître ARCHIVE '
                .'(crud-engine.js l.523-551) et les clés étrangères portent `restrictOnDelete()`.',
            );
        }
    }

    /**
     * Aucun montant, taux ou téléphone écrit en dur dans le composant.
     *
     * Précédents réels du dépôt : un tarif de repli `20000`, un compte `'601'`,
     * un téléphone `'0100000000'` — ce dernier était dans le lot précédent de
     * cet écran.
     */
    #[Test]
    public function aucune_valeur_en_dur_ne_subsiste_dans_le_composant_m8(): void
    {
        $source = (string) file_get_contents(app_path('Pwa/Livewire/Vehicules/Locations.php'));

        $this->assertGreaterThan(2000, strlen($source));

        // Un littéral numérique de 4 chiffres ou plus est soit un montant,
        // soit un numéro de téléphone : ni l'un ni l'autre n'a sa place ici.
        // Les années des règles de validation (`min:1950`) sont écrites en
        // chaîne et ne mordent pas sur ce motif.
        $this->assertDoesNotMatchRegularExpression(
            '/=>\s*\d{4,}|=\s*\d{4,}\s*;/',
            $source,
            'Un littéral numérique long subsiste : montant, taux ou téléphone en dur.',
        );

        $this->assertStringNotContainsString(
            'class_exists(',
            $source,
            'Un `class_exists()` gardant un appel de service est le motif exact qui a fait '
            .'qu aucune dépense n a jamais produit d écriture comptable, silencieusement.',
        );
    }

    /**
     * Chaque `wire:click="methode(...)"` RENDU correspond à une méthode
     * publique déclarée.
     *
     * C'est le défaut qui a mis `/pwa/stocks` en 500 : un bouton qui appelle
     * une méthode disparue ne se voit qu'au clic, donc en production.
     */
    #[Test]
    public function chaque_action_rendue_existe_sur_le_composant_m8(): void
    {
        $this->vehicule();
        $this->client();

        $publiques = array_map(
            static fn (\ReflectionMethod $m): string => $m->getName(),
            (new \ReflectionClass(Locations::class))->getMethods(\ReflectionMethod::IS_PUBLIC),
        );

        // Les composants IMBRIQUES de la coquille (cloche de notifications,
        // recherche globale — audit PO du 01/09/2026) rendent leurs propres
        // actions sur CHAQUE page : elles se resolvent sur eux, jamais sur le
        // composant de page.
        foreach ([
            \App\Pwa\Livewire\Transverse\ClocheNotifications::class,
            \App\Pwa\Livewire\Transverse\RechercheGlobale::class,
        ] as $imbrique) {
            foreach ((new \ReflectionClass($imbrique))->getMethods(\ReflectionMethod::IS_PUBLIC) as $m) {
                $publiques[] = $m->getName();
            }
        }

        $actionsVues = 0;

        foreach (Locations::ONGLETS as $onglet) {
            $html = (string) $this->actingAs($this->compte('vehicules'))
                ->get('/pwa/vehicules?onglet='.$onglet)
                ->getContent();

            // Les DEUX formes du depot : `methode(...)` et `methode` sans
            // argument. Ne lire que la premiere laissait dix boutons hors du
            // balayage — dont ceux de la barre d'actions.
            preg_match_all('/wire:click="([a-zA-Z_][a-zA-Z0-9_]*)\s*[("]/', $html, $trouves);

            foreach (array_unique($trouves[1]) as $action) {
                $actionsVues++;
                $this->assertContains(
                    $action,
                    $publiques,
                    "wire:click=\"{$action}(...)\" de l onglet {$onglet} n a aucune methode publique.",
                );
            }
        }

        // Plancher : sans lui, une vue qui ne rendrait plus aucun bouton
        // passerait ce controle a vide.
        $this->assertGreaterThanOrEqual(14, $actionsVues, 'Le balayage des actions est devenu creux.');
    }


    /**
     * L'export est REELLEMENT execute — PDF et tableur.
     *
     * Un gabarit qui reference une variable absente ne se voit qu'au
     * telechargement : le lot precedent passait `$vehicules`, `$contrats` et
     * `$entretiens` au document, et lisait `$c->client_nom` — une colonne que
     * RG-18 interdit d'ecrire.
     */
    #[Test]
    public function les_deux_formats_d_export_sont_reellement_produits(): void
    {
        $this->vehicule();

        foreach (['pdf', 'excel'] as $format) {
            $this->actingAs($this->compte('vehicules'));

            Livewire::test(Locations::class)
                ->set('onglet', 'parc')
                ->set('formatExport', $format)
                ->call('genererExport')
                ->assertHasNoErrors()
                ->assertFileDownloaded();
        }
    }

    /**
     * PA-119 — une liste vide se REFUSE : un document vierge se lirait comme
     * un registre verifie.
     */
    #[Test]
    public function un_export_sans_ligne_est_refuse(): void
    {
        $this->actingAs($this->compte('vehicules'));

        Livewire::test(Locations::class)
            ->set('onglet', 'contrats')
            ->call('genererExport')
            ->assertHasErrors('formatExport');
    }


    /**
     * Un rôle en LECTURE SEULE sur le module obtient bien son export.
     *
     * Exporter ne produit rien de neuf : c'est le rendu sur un autre papier de
     * données déjà à l'écran, et le droit de les lire est porté par le
     * middleware `module:M8,L` de la route. Ce cas est la contrepartie
     * de `le_role_lecture_seule_se_voit_refuser_chaque_geste_d_ecriture` : le
     * même compte qui se voit refuser toute écriture doit pouvoir exporter,
     * sans quoi le comptable perdrait un document qu'il a le droit de lire.
     */
    #[Test]
    public function un_role_en_lecture_seule_obtient_son_export(): void
    {
        $this->vehicule();

        foreach (['comptable', 'receptionniste'] as $role) {
            $this->actingAs($this->compte($role));     // M8 = 'L'

            Livewire::test(Locations::class)
                ->set('onglet', 'parc')
                ->set('formatExport', 'pdf')
                ->call('genererExport')
                ->assertHasNoErrors()
                ->assertFileDownloaded();
        }
    }

}

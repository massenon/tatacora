<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Crm\Models\Client;
use App\Domain\Tourisme\Models\Circuit;
use App\Domain\Tourisme\Models\Guide;
use App\Domain\Tourisme\Models\ReservationTour;
use App\Models\User;
use App\Pwa\Livewire\Tourisme\Departs;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Pwa\Concerns\OuvreLaSaisie;
use Tests\TestCase;

/**
 * M9 en ÉCRITURE — `m9-tourisme-departs.html`, vague CRUD du 31/08/2026.
 *
 * Ce fichier remplace la suite de la vague « lecture seule », devenue fausse
 * depuis PA-159.
 *
 * Ce qu'il tient, et qui n'est vérifié nulle part ailleurs :
 *
 *  1. **V3 — la réaffectation du guide est PERSISTÉE.** Le lot précédent la
 *     rangeait dans `Session::put('tourisme_departs_assignments', …)` : la
 *     table relisait la session et affichait le nouveau guide pendant que la
 *     base gardait l'ancien. L'écran disait Paul, le départ partait avec Jean,
 *     et la décision disparaissait à la déconnexion. Ce cas relit la BASE.
 *  2. **Aucune session** ne subsiste dans le composant — garde de source, sans
 *     quoi le défaut peut revenir dans une méthode que personne ne rejoue.
 *  3. **La capacité vient du SERVICE**, cumulée sur le départ (EF-M9-04,
 *     PA-51). `capaciteRestanteResa = 99` du lot précédent était une
 *     sur-réservation en puissance.
 *  4. **Le RBAC d'écriture** (défaut V1).
 *  5. **Aucune suppression** : annuler passe le statut, la ligne demeure.
 *
 * ## Mutations RÉELLEMENT EXÉCUTÉES le 31/08/2026 — les deux ont mordu
 *
 * Chacune a été appliquée au composant, la cible relancée, puis le fichier
 * remis en l'état.
 *
 * | Mutation                                                        | Cible rougie |
 * |------------------------------------------------------------------|--------------|
 * | remplacer `affecterGuide()` par une écriture en session           | `la_reaffectation_du_guide_est_ecrite_en_base` |
 * | remplacer `placesRestantes()` par la constante 99 du lot précédent | `les_places_restantes_viennent_du_service` |
 * | neutraliser `alignerGuideSurLeDepart()`                           | `le_guide_du_depart_est_impose_des_le_choix_de_la_date` |
 * | rendre `guideImpose` toujours `null` à la vue                     | `deux_groupes_partagent_un_meme_depart_et_leurs_places_se_cumulent` |
 * | avaler la `RuntimeException` du service au lieu de l'afficher      | `le_troisieme_groupe_est_refuse_par_la_capacite_cumulee` |
 *
 * ⚠ La quatrième n'a PAS mordu au premier essai : le guide par défaut de la
 * modale est le premier par nom, et « ADJOVI Paul » l'était déjà. Le cas
 * passait sans que l'alignement ait rien fait. Un second guide triant avant
 * lui a été ajouté, et sa raison est écrite au-dessus de lui — le renommer
 * rendrait le cas vert à vide.
 *
 * Les deux gardes de SOURCE (`aucune_decision_metier_ne_transite_par_la_session`,
 * `aucune_valeur_en_dur_…`) portent leur propre preuve : la seconde vérifie que
 * son motif mord sur `$capaciteRestanteResa = 99;`, sans quoi elle pourrait
 * cesser de reconnaître quoi que ce soit et passer à vide.
 *
 * @see EF-M9-01, EF-M9-03, EF-M9-04
 * @see UC-39 Réaffecter un guide (PA-51 : `guide_id` est NOT NULL)
 */
final class TourismePwaTest extends TestCase
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
            'login' => $role.'.m9.'.bin2hex(random_bytes(3)),
            'mot_de_passe_hash' => Hash::make('MotDePasseTresLong!2026'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    private function circuit(int $capacite = 12): Circuit
    {
        return Circuit::create([
            'nom' => 'Tata Otammari',
            'theme' => 'culture',
            'zone' => 'Atacora',
            'duree' => '2 jours / 1 nuit',
            'prix' => '35000.00',
            'capacite_max' => $capacite,
        ]);
    }

    private function guide(string $nom): Guide
    {
        return Guide::create([
            'nom' => $nom,
            'certification' => 'Guide national',
            'zone_competence' => 'Atacora',
            'tarif_jour' => '15000.00',
        ]);
    }

    private function client(string $nom = 'Groupe Franco-Béninois'): Client
    {
        return Client::create([
            'nom' => $nom,
            'telephone' => '+229 01 97 88 99',
            'type_client' => 'particulier',
        ]);
    }

    // =====================================================================
    // 1. L'écran est servi, et son RBAC de lecture tient
    // =====================================================================

    #[Test]
    public function les_trois_onglets_du_maitre_sont_servis(): void
    {
        $this->circuit();

        foreach (Departs::ONGLETS as $onglet) {
            $this->actingAs($this->compte('guide'))
                ->get('/pwa/tourisme?onglet='.$onglet)
                ->assertOk()
                ->assertSee('Tourisme');
        }
    }

    #[Test]
    public function un_role_sans_acces_au_module_ne_voit_pas_l_ecran(): void
    {
        // `barman` porte M9 = '-'.
        $this->actingAs($this->compte('barman'))
            ->get('/pwa/tourisme')
            ->assertForbidden();
    }

    // =====================================================================
    // 2. V1 — le RBAC d'ÉCRITURE
    // =====================================================================

    #[Test]
    public function le_role_lecture_seule_se_voit_refuser_chaque_geste_d_ecriture(): void
    {
        $circuit = $this->circuit();
        $guide = $this->guide('ADJOVI Paul');
        $client = $this->client();
        $lecteur = $this->compte('receptionniste');   // M9 = 'L'

        $reservation = ReservationTour::create([
            'circuit_id' => $circuit->id,
            'client_id' => $client->id,
            'guide_id' => $guide->id,
            'date_circuit' => '2026-12-05',
            'nb_participants' => 4,
            'statut' => 'reservee',
        ]);

        $gestes = [
            ['ouvrirFormulaireReservation', []],
            ['enregistrerReservation', []],
            ['ouvrirFormulaireGuide', [$circuit->id, '2026-12-05']],
            ['enregistrerReaffectationGuide', []],
            ['ouvrirFormulairePrestation', []],
            ['enregistrerPrestation', []],
            ['confirmerArchivage', ['reservation', $reservation->id]],
            ['executerSuppression', []],
        ];

        foreach ($gestes as [$methode, $arguments]) {
            $this->actingAs($lecteur);

            Livewire::test(Departs::class)
                ->call($methode, ...$arguments)
                ->assertForbidden();
        }

        $this->assertSame(1, ReservationTour::count());
        $this->assertSame($guide->id, $reservation->fresh()->guide_id);
        $this->assertSame('reservee', $reservation->fresh()->statut);
    }

    // =====================================================================
    // 3. V3 — la réaffectation du guide, écrite EN BASE
    // =====================================================================

    /**
     * Le défaut du lot précédent en une phrase : l'écran affichait Paul et le
     * départ partait avec Jean. Ce cas relit `reservations_tour.guide_id`.
     */
    #[Test]
    public function la_reaffectation_du_guide_est_ecrite_en_base(): void
    {
        $circuit = $this->circuit();
        $paul = $this->guide('ADJOVI Paul');
        $jean = $this->guide('KOTO Jean');
        $client = $this->client();

        $reservation = ReservationTour::create([
            'circuit_id' => $circuit->id,
            'client_id' => $client->id,
            'guide_id' => $paul->id,
            'date_circuit' => '2026-12-10',
            'nb_participants' => 3,
            'statut' => 'reservee',
        ]);

        $this->actingAs($this->compte('guide'));

        Livewire::test(Departs::class)
            ->call('ouvrirFormulaireGuide', $circuit->id, '2026-12-10')
            ->assertSet('guideIdResa', null)
            ->set('nouveauGuideId', $jean->id)
            ->call('enregistrerReaffectationGuide')
            ->assertHasNoErrors();

        $this->assertSame(
            $jean->id,
            $reservation->fresh()->guide_id,
            'UC-39 : la décision doit vivre en base, pas dans la session HTTP.',
        );
    }

    /**
     * `guide_id` est NOT NULL (PA-51) : l'écran ne doit jamais laisser croire
     * qu'on peut vider l'affectation.
     */
    #[Test]
    public function la_reaffectation_exige_un_guide(): void
    {
        $circuit = $this->circuit();
        $paul = $this->guide('ADJOVI Paul');
        $client = $this->client();

        ReservationTour::create([
            'circuit_id' => $circuit->id,
            'client_id' => $client->id,
            'guide_id' => $paul->id,
            'date_circuit' => '2026-12-11',
            'nb_participants' => 2,
            'statut' => 'reservee',
        ]);

        $this->actingAs($this->compte('guide'));

        Livewire::test(Departs::class)
            ->call('ouvrirFormulaireGuide', $circuit->id, '2026-12-11')
            ->set('nouveauGuideId', null)
            ->call('enregistrerReaffectationGuide')
            ->assertHasErrors('nouveauGuideId');
    }

    /**
     * Garde de SOURCE : la session ne doit jamais redevenir un support de
     * décision métier. Un test de comportement ne verrait pas une seconde
     * méthode qui la réintroduirait.
     */
    #[Test]
    public function aucune_decision_metier_ne_transite_par_la_session(): void
    {
        $source = (string) file_get_contents(app_path('Pwa/Livewire/Tourisme/Departs.php'));

        // Plancher : un fichier vide rendrait ce contrôle vert à vide.
        $this->assertGreaterThan(2000, strlen($source));

        $this->assertDoesNotMatchRegularExpression(
            '/Session::\s*(?:put|get)\s*\(/',
            $source,
            'Une décision rangée en session disparaît à la déconnexion et '
            .'n a jamais existé pour les autres postes.',
        );
    }

    // =====================================================================
    // 4. La capacité vient du service, cumulée sur le départ
    // =====================================================================

    #[Test]
    public function les_places_restantes_viennent_du_service(): void
    {
        $circuit = $this->circuit(12);
        $paul = $this->guide('ADJOVI Paul');
        $client = $this->client();

        ReservationTour::create([
            'circuit_id' => $circuit->id,
            'client_id' => $client->id,
            'guide_id' => $paul->id,
            'date_circuit' => '2026-12-20',
            'nb_participants' => 5,
            'statut' => 'reservee',
        ]);

        $this->actingAs($this->compte('guide'));

        Livewire::test(Departs::class)
            ->call('ouvrirFormulaireReservation', $circuit->id, '2026-12-20', $paul->id)
            ->assertViewHas('placesRestantesResa', 7)
            ->assertViewHas('capaciteResa', 12);
    }

    /**
     * EF-M9-04 — le contrôle porte sur le CUMUL. La lecture littérale de la
     * spécification laisserait passer trois groupes de 5 sur 12 places
     * (PA-51). Le refus du service est AFFICHÉ, jamais avalé.
     */
    #[Test]
    public function la_capacite_cumulee_du_depart_est_refusee_au_depassement(): void
    {
        $circuit = $this->circuit(6);
        $paul = $this->guide('ADJOVI Paul');
        $client = $this->client();

        ReservationTour::create([
            'circuit_id' => $circuit->id,
            'client_id' => $client->id,
            'guide_id' => $paul->id,
            'date_circuit' => '2026-12-21',
            'nb_participants' => 5,
            'statut' => 'reservee',
        ]);

        // LE MEME guide : un départ a un guide, et les groupes suivants le
        // reprennent. Ce cas porte sur la CAPACITÉ cumulée, pas sur le guide —
        // le construire avec un second guide éprouverait un départ à deux
        // guides, situation qui ne peut pas exister au Gîte.
        $autreClient = $this->client('Mission PAEB');

        $this->actingAs($this->compte('guide'));

        Livewire::test(Departs::class)
            ->call('ouvrirFormulaireReservation', $circuit->id, '2026-12-21', $paul->id)
            ->set('clientIdResa', $autreClient->id)
            ->set('nbPersonnesSaisi', 3)
            ->call('enregistrerReservation')
            ->assertHasErrors('nbPersonnesSaisi');

        $this->assertSame(1, ReservationTour::count(), 'EF-M9-04 : la 2e réservation dépasse la capacité.');
    }

    #[Test]
    public function une_reservation_valide_est_ecrite_par_le_service(): void
    {
        $circuit = $this->circuit();
        $paul = $this->guide('ADJOVI Paul');
        $client = $this->client();

        $this->actingAs($this->compte('guide'));

        Livewire::test(Departs::class)
            ->call('ouvrirFormulaireReservation', $circuit->id, '2026-12-22', $paul->id)
            ->set('clientIdResa', $client->id)
            ->set('nbPersonnesSaisi', 4)
            ->call('enregistrerReservation')
            ->assertHasNoErrors();

        $reservation = ReservationTour::firstOrFail();

        $this->assertSame($circuit->id, $reservation->circuit_id);
        $this->assertSame($client->id, $reservation->client_id);
        $this->assertSame($paul->id, $reservation->guide_id);
        $this->assertSame(4, $reservation->nb_participants);
        $this->assertSame('reservee', $reservation->statut);
    }

    #[Test]
    public function la_modale_de_reservation_rend_exactement_ses_champs(): void
    {
        $this->circuit();
        $this->guide('ADJOVI Paul');
        $this->client();

        $this->assertLaModaleSOuvreEtRendExactementSesChamps(
            $this->compte('guide'),
            Departs::class,
            'ouvrirFormulaireReservation',
            [
                'circuitIdResa', 'dateDepartResa', 'guideIdResa',
                'clientIdResa', 'nbPersonnesSaisi',
            ],
        );
    }

    // =====================================================================
    // 5. Archiver, jamais supprimer
    // =====================================================================

    #[Test]
    public function annuler_une_reservation_ne_la_supprime_jamais(): void
    {
        $circuit = $this->circuit();
        $paul = $this->guide('ADJOVI Paul');
        $client = $this->client();

        $reservation = ReservationTour::create([
            'circuit_id' => $circuit->id,
            'client_id' => $client->id,
            'guide_id' => $paul->id,
            'date_circuit' => '2026-12-23',
            'nb_participants' => 2,
            'statut' => 'reservee',
        ]);

        $this->actingAs($this->compte('guide'));

        Livewire::test(Departs::class)
            ->call('confirmerArchivage', 'reservation', $reservation->id)
            ->assertSet('archivageBloque', false)
            ->call('executerSuppression');

        $apres = ReservationTour::find($reservation->id);

        $this->assertNotNull($apres, 'Le maître ARCHIVE : la ligne reste lisible.');
        $this->assertSame('annulee', $apres->statut);
    }

    #[Test]
    public function annuler_un_depart_annule_toutes_ses_reservations(): void
    {
        $circuit = $this->circuit();
        $paul = $this->guide('ADJOVI Paul');
        $client = $this->client();

        $reservation = ReservationTour::create([
            'circuit_id' => $circuit->id,
            'client_id' => $client->id,
            'guide_id' => $paul->id,
            'date_circuit' => '2026-12-24',
            'nb_participants' => 6,
            'statut' => 'reservee',
        ]);

        $this->actingAs($this->compte('guide'));

        Livewire::test(Departs::class)
            ->call('confirmerArchivage', 'depart', $circuit->id, '2026-12-24')
            ->assertSet('archivageBloque', false)
            ->assertSet('placesConcernees', 6)
            ->call('executerSuppression');

        $this->assertSame('annulee', $reservation->fresh()->statut);
        $this->assertSame(1, ReservationTour::count());
    }

    /**
     * Un départ sans réservation active n'existe pas : le bouton de
     * confirmation doit être masqué, comme le maître le fait quand un verrou
     * s'applique (`crud-engine.js` l.535).
     */
    #[Test]
    public function un_depart_sans_reservation_bloque_l_archivage(): void
    {
        $circuit = $this->circuit();

        $this->actingAs($this->compte('guide'));

        Livewire::test(Departs::class)
            ->call('confirmerArchivage', 'depart', $circuit->id, '2026-12-25')
            ->assertSet('archivageBloque', true)
            ->assertDontSee('wire:click="executerSuppression"', false)
            ->call('executerSuppression')
            ->assertForbidden();
    }

    // =====================================================================
    // 6. Le catalogue — thème pris à l'énumération, aucune suppression
    // =====================================================================

    #[Test]
    public function une_prestation_est_enregistree_avec_un_theme_de_l_enumeration(): void
    {
        $this->actingAs($this->compte('guide'));

        Livewire::test(Departs::class)
            ->call('ouvrirFormulairePrestation')
            ->set('circuitNomSaisi', 'Chutes de Tanougou')
            ->set('circuitThemeSaisi', 'nature')
            ->set('circuitZoneSaisie', 'Atacora')
            ->set('circuitDureeSaisie', 'Journée')
            ->set('circuitPrixSaisi', '25000')
            ->set('circuitCapaciteSaisie', 10)
            ->call('enregistrerPrestation')
            ->assertHasNoErrors();

        $circuit = Circuit::firstOrFail();

        $this->assertSame('Chutes de Tanougou', $circuit->nom);
        $this->assertSame('nature', $circuit->theme);
    }

    #[Test]
    public function un_theme_hors_enumeration_est_refuse_avant_l_ecriture(): void
    {
        $this->actingAs($this->compte('guide'));

        Livewire::test(Departs::class)
            ->call('ouvrirFormulairePrestation')
            ->set('circuitNomSaisi', 'Circuit gastronomique')
            ->set('circuitThemeSaisi', 'gastronomie')   // hors énumération
            ->set('circuitZoneSaisie', 'Atacora')
            ->set('circuitDureeSaisie', 'Journée')
            ->set('circuitPrixSaisi', '25000')
            ->set('circuitCapaciteSaisie', 10)
            ->call('enregistrerPrestation')
            ->assertHasErrors('circuitThemeSaisi');

        $this->assertSame(0, Circuit::count());
    }

    // =====================================================================
    // 7. Gardes de source
    // =====================================================================

    #[Test]
    public function aucune_suppression_physique_ne_subsiste_dans_le_code_m9(): void
    {
        $fichiers = [
            app_path('Pwa/Livewire/Tourisme/Departs.php'),
            resource_path('views/pwa/tourisme/departs.blade.php'),
        ];

        foreach ($fichiers as $fichier) {
            $source = (string) file_get_contents($fichier);

            $this->assertGreaterThan(2000, strlen($source), "{$fichier} est trop court.");

            $this->assertDoesNotMatchRegularExpression(
                '/->\s*(?:force)?[dD]elete\s*\(/',
                $source,
                basename($fichier).' appelle une suppression physique. `circuits` est '
                .'référencée par `reservations_tour` en `restrictOnDelete()`.',
            );
        }
    }

    #[Test]
    public function aucune_valeur_en_dur_ne_subsiste_dans_le_composant_m9(): void
    {
        $source = (string) file_get_contents(app_path('Pwa/Livewire/Tourisme/Departs.php'));

        $this->assertGreaterThan(2000, strlen($source));

        // `capaciteRestanteResa = 99` du lot précédent : une capacité posée en
        // dur est une sur-réservation en puissance. Le motif vise les seules
        // proprietes de capacite, place et remplissage — un plafond de
        // validation (`max:999`) ou une fenêtre de jours n en est pas une.
        $this->assertDoesNotMatchRegularExpression(
            '/\$[a-zA-Z]*(?:apacite|laces|estante)[a-zA-Z]*\s*=\s*\d{2,}/',
            $source,
            'Une capacité ou un nombre de places est écrit en dur : la valeur doit '
            .'venir de `ReservationTourService::placesRestantes()`.',
        );

        // Et le motif MORD : sans ce contrôle, il pourrait ne plus rien
        // reconnaître et passer à vide.
        $this->assertMatchesRegularExpression(
            '/\$[a-zA-Z]*(?:apacite|laces|estante)[a-zA-Z]*\s*=\s*\d{2,}/',
            '$capaciteRestanteResa = 99;',
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
    public function chaque_action_rendue_existe_sur_le_composant_m9(): void
    {
        $this->circuit();
        $this->guide('ADJOVI Paul');
        $this->client();

        $publiques = array_map(
            static fn (\ReflectionMethod $m): string => $m->getName(),
            (new \ReflectionClass(Departs::class))->getMethods(\ReflectionMethod::IS_PUBLIC),
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

        foreach (Departs::ONGLETS as $onglet) {
            $html = (string) $this->actingAs($this->compte('guide'))
                ->get('/pwa/tourisme?onglet='.$onglet)
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
        $this->assertGreaterThanOrEqual(6, $actionsVues, 'Le balayage des actions est devenu creux.');
    }


    /**
     * L'export est REELLEMENT execute — PDF et tableur.
     *
     * Le lot precedent lisait `$item->acompte` sur `reservations_tour`, une
     * colonne qui n'existe pas : toutes les lignes sortaient a zero.
     */
    #[Test]
    public function les_deux_formats_d_export_sont_reellement_produits(): void
    {
        $this->circuit();

        foreach (['pdf', 'excel'] as $format) {
            $this->actingAs($this->compte('guide'));

            Livewire::test(Departs::class)
                ->set('onglet', 'catalogue')
                ->set('formatExport', $format)
                ->call('genererExport')
                ->assertHasNoErrors()
                ->assertFileDownloaded();
        }
    }

    /**
     * PA-119 — une liste vide se REFUSE.
     */
    #[Test]
    public function un_export_sans_ligne_est_refuse(): void
    {
        $this->actingAs($this->compte('guide'));

        Livewire::test(Departs::class)
            ->set('onglet', 'departs')
            ->call('genererExport')
            ->assertHasErrors('formatExport');
    }


    /**
     * Un rôle en LECTURE SEULE sur le module obtient bien son export.
     *
     * Exporter ne produit rien de neuf : c'est le rendu sur un autre papier de
     * données déjà à l'écran, et le droit de les lire est porté par le
     * middleware `module:M9,L` de la route. Ce cas est la contrepartie
     * de `le_role_lecture_seule_se_voit_refuser_chaque_geste_d_ecriture` : le
     * même compte qui se voit refuser toute écriture doit pouvoir exporter,
     * sans quoi le comptable perdrait un document qu'il a le droit de lire.
     */
    #[Test]
    public function un_role_en_lecture_seule_obtient_son_export(): void
    {
        $this->circuit();

        foreach (['comptable', 'receptionniste'] as $role) {
            $this->actingAs($this->compte($role));     // M9 = 'L'

            Livewire::test(Departs::class)
                ->set('onglet', 'catalogue')
                ->set('formatExport', 'pdf')
                ->call('genererExport')
                ->assertHasNoErrors()
                ->assertFileDownloaded();
        }
    }


    /**
     * DEUX GROUPES SUR LE MÊME DÉPART — le geste réel du comptoir, qu'aucun
     * test PWA ne couvrait.
     *
     * Il était impossible jusqu'au 31/08/2026 : `verifierGuideLibre()`
     * refusait tout guide ayant déjà une réservation ce jour-là sans regarder
     * le circuit, donc la deuxième réservation d'un départ tombait toujours.
     * Le contrôle de capacité cumulée de PA-51 était par conséquent
     * inatteignable — il n'y avait jamais qu'une ligne à cumuler.
     *
     * Ce cas vérifie les deux moitiés : la seconde réservation PASSE, et les
     * places s'AJOUTENT sur le même départ.
     */
    #[Test]
    public function deux_groupes_partagent_un_meme_depart_et_leurs_places_se_cumulent(): void
    {
        $circuit = $this->circuit(12);
        $paul = $this->guide('ADJOVI Paul');
        $premier = $this->client('Groupe Franco-Béninois');
        $second = $this->client('Mission PAEB');

        Livewire::actingAs($this->compte('guide'));

        Livewire::test(Departs::class)
            ->call('ouvrirFormulaireReservation', $circuit->id, '2027-01-15', $paul->id)
            ->set('clientIdResa', $premier->id)
            ->set('nbPersonnesSaisi', 5)
            ->call('enregistrerReservation')
            ->assertHasNoErrors();

        // Le second groupe est ouvert depuis la LIGNE du départ : le guide en
        // place lui est imposé, et l'écran le montre au lieu d'une liste
        // libre que le service refuserait.
        // `assertViewHas()` rend le `TestResponse` sous-jacent : la fiche
        // est gardee en variable pour reprendre la chaine Livewire apres les
        // verifications de vue (analyse statique, 02/09/2026).
        $fiche = Livewire::test(Departs::class)
            ->call('ouvrirFormulaireReservation', $circuit->id, '2027-01-15', $paul->id)
            ->assertSet('guideIdResa', $paul->id);

        $fiche->assertViewHas('guideImpose', static fn ($guide): bool => $guide !== null && $guide->id === $paul->id)
            ->assertViewHas('placesRestantesResa', 7);

        $fiche->set('clientIdResa', $second->id)
            ->set('nbPersonnesSaisi', 4)
            ->call('enregistrerReservation')
            ->assertHasNoErrors();

        $this->assertSame(2, ReservationTour::count(), 'Un départ porte plusieurs groupes.');
        $this->assertSame(9, (int) ReservationTour::sum('nb_participants'));

        // Le départ reste UN départ, conduit par UN guide.
        $this->assertSame([$paul->id], ReservationTour::pluck('guide_id')->unique()->values()->all());

        // Et l'écran le rend comme une seule ligne, au remplissage cumulé.
        // La fenêtre est posée explicitement : la fenêtre par défaut part
        // d'aujourd'hui, et un départ hors fenêtre ne serait pas dérivé —
        // le cas passerait alors pour de mauvaises raisons.
        Livewire::test(Departs::class)
            ->set('debut', '2027-01-01')
            ->set('fin', '2027-01-31')
            ->set('onglet', 'departs')
            ->assertViewHas('departs', static function (array $departs): bool {
                return count($departs) === 1
                    && $departs[0]['places_vendues'] === 9
                    && $departs[0]['places_restantes'] === 3;
            });
    }

    /**
     * Le troisième groupe déborde la capacité : le refus vient du service, et
     * il est AFFICHÉ.
     */
    #[Test]
    public function le_troisieme_groupe_est_refuse_par_la_capacite_cumulee(): void
    {
        $circuit = $this->circuit(12);
        $paul = $this->guide('ADJOVI Paul');

        Livewire::actingAs($this->compte('guide'));

        foreach ([['Groupe A', 5], ['Groupe B', 5]] as [$nom, $personnes]) {
            Livewire::test(Departs::class)
                ->call('ouvrirFormulaireReservation', $circuit->id, '2027-02-01', $paul->id)
                ->set('clientIdResa', $this->client($nom)->id)
                ->set('nbPersonnesSaisi', $personnes)
                ->call('enregistrerReservation')
                ->assertHasNoErrors();
        }

        // 5 + 5 = 10 sur 12 : un groupe de 5 ne passe plus.
        Livewire::test(Departs::class)
            ->call('ouvrirFormulaireReservation', $circuit->id, '2027-02-01', $paul->id)
            ->set('clientIdResa', $this->client('Groupe C')->id)
            ->set('nbPersonnesSaisi', 5)
            ->call('enregistrerReservation')
            ->assertHasErrors('nbPersonnesSaisi');

        $this->assertSame(2, ReservationTour::count());
        $this->assertSame(10, (int) ReservationTour::sum('nb_participants'));
    }

    /**
     * Le guide d'un départ existant est IMPOSÉ même quand la modale est
     * ouverte sans lui — depuis « + Réservation » ou « Planifier » au
     * catalogue, où seul le circuit est connu.
     *
     * Sans cet alignement, l'écran offrirait une liste libre et le service
     * refuserait à l'enregistrement (`tourisme.guide_du_depart_impose`), sur
     * un formulaire déjà rempli.
     */
    #[Test]
    public function le_guide_du_depart_est_impose_des_le_choix_de_la_date(): void
    {
        $circuit = $this->circuit();
        $paul = $this->guide('ADJOVI Paul');

        // ⚠ Ce guide-ci trie AVANT Paul : sans lui, le defaut de la modale
        // (le premier guide par nom) serait deja Paul, et le cas passerait
        // sans que l'alignement ait rien fait. Mutation du 31/08/2026 :
        // neutraliser `alignerGuideSurLeDepart()` laissait le cas VERT avec
        // « KOTO Jean ». Ne pas renommer ce guide.
        $this->guide('ABLO Jean');

        ReservationTour::create([
            'circuit_id' => $circuit->id,
            'client_id' => $this->client()->id,
            'guide_id' => $paul->id,
            'date_circuit' => '2027-03-08',
            'nb_participants' => 2,
            'statut' => 'reservee',
        ]);

        $this->actingAs($this->compte('guide'));

        Livewire::test(Departs::class)
            // Ouverture SANS guide : c'est le chemin du catalogue.
            ->call('ouvrirFormulaireReservation', $circuit->id)
            ->set('dateDepartResa', '2027-03-08')
            ->assertSet('guideIdResa', $paul->id)
            ->assertViewHas('guideImpose', static fn ($guide): bool => $guide !== null && $guide->id === $paul->id);
    }

}

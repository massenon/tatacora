<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CanalReservation;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\Sejour;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\TableauxDeBord\Data\Periode;
use App\Domain\TableauxDeBord\Services\TableauDeBordService;
use App\Models\User;
use App\Pwa\Livewire\Accueil;
use App\Shared\Rbac\Models\Permission;
use App\Shared\Rbac\Models\Role;
use Carbon\CarbonImmutable;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Le tableau de bord M11 de la PWA — vue maîtresse (PA-183) :
 * `resources/views/pwa/livewire/accueil.blade.php`.
 *
 * Ce qui est vérifié ici, et qui ne l'est nulle part ailleurs :
 *
 *  1. **AUCUN CHIFFRE INVENTÉ.** Le fichier ne porte ni `200000`, ni `165000`,
 *     ni aucun des huit replis que la version précédente affichait comme des
 *     faits. Un échec de lecture rend « Non consulté », JAMAIS un zéro ni un
 *     montant plausible.
 *  2. Une période inconnue ne produit ni 500 ni repli silencieux (A3).
 *  3. Une action rapide exige le droit du module qu'elle ÉCRIT (M1, M3), pas
 *     celui de l'écran seul.
 *  4. Les gestes passent par les Services de domaine : RG-01 refuse le
 *     chevauchement depuis CET écran comme depuis l'écran M1.
 *  5. `ecransVisibles()` filtre par droit réel — la constante
 *     `ECRANS_AUTORISES` a un lecteur applicatif, elle n'est pas du code mort.
 *
 * ## PREUVES PAR MUTATION (31/08/2026)
 *
 * Chaque cas ci-dessous a été cassé, vu rouge, puis remis :
 *
 * | Mutation | Cas devenu rouge |
 * |---|---|
 * | `codePeriodeValide()` rend `$this->filtrePeriode` sans filtrer | `une_periode_inconnue_ne_produit_ni_500_ni_repli_muet` (500) |
 * | `periodeRefusee()` rend toujours `null` | idem (bandeau absent) |
 * | le `catch` de `render()` pose `$indicateurs = []` | `un_echec_de_lecture_affiche_non_consulte_et_jamais_zero` |
 * | `exigerEcriture(self::MODULE_HEBERGEMENT)` retiré d'`ouvrirReservationRapide` | `une_action_rapide_exige_le_droit_du_module_ecrit_et_pas_celui_de_l_ecran` |
 * | `ReservationService::creer()` remplacé par `Reservation::create()` | `rg01_le_chevauchement_est_refuse_depuis_le_tableau_de_bord` |
 * | `SejourService::checkin()` remplacé par une écriture directe | `le_check_in_passe_par_le_service_et_ecrit_le_cycle_de_l_unite` |
 *
 * ⚠ LA MUTATION RBAC (quatrième ligne) N'A PAS MORDU au premier jet, et
 * la raison vaut d'être retenue : le rôle éprouvé (`rh`) n'a que `M11 = 'L'`,
 * si bien que le droit de l'ÉCRAN refusait déjà — la garde du module ÉCRIT
 * n'était jamais atteinte. Le cas a été dédoublé, et le second fabrique un
 * rôle `M11 = 'C'` et rien d'autre. Un test vert qui n'éprouve pas ce qu'il
 * annonce est précisément le défaut que ce dépôt poursuit.
 *
 * @see EF-M11-01 Tableau de bord global
 * @see RG-01 Prévention des doubles réservations
 * @see RG-02 Disponibilité toujours calculée
 */
final class AccueilM11Test extends TestCase
{
    use RefreshDatabase;

    private CategorieHebergement $categorie;

    private UniteHebergement $unite;

    private Client $client;

    private CanalReservation $canal;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->categorie = CategorieHebergement::create([
            'libelle' => 'Bungalow',
            'capacite_max' => 2,
            'tarif_base' => '28000.00',
        ]);

        $this->unite = UniteHebergement::create([
            'categorie_id' => $this->categorie->id,
            'numero' => 'BNG-01',
            'statut' => 'libre',
        ]);

        $this->client = Client::create([
            'nom' => 'KPETONI',
            'prenom' => 'Julien',
            'telephone' => '01 90 00 00 02',
            'type_client' => 'particulier',
        ]);

        // Le canal est OBLIGATOIRE sur la réservation rapide depuis PA-163,
        // comme au maître : la fiche de test en a besoin.
        $this->canal = CanalReservation::create(['nom' => 'Physique', 'actif' => true]);
    }

    /* ================================================================
       1 — AUCUN CHIFFRE INVENTÉ
       ================================================================ */

    /**
     * Le défaut nommé A2 : `$caPaye = 200000` dans un `catch`.
     *
     * Le contrôle porte sur le SOURCE et pas sur le rendu : un montant de repli
     * ne s'affiche que sur le chemin d'échec, et un test de rendu heureux ne le
     * verrait jamais — c'est exactement pourquoi il a survécu.
     */
    #[Test]
    public function aucun_montant_ni_compteur_n_est_ecrit_en_dur_dans_le_composant(): void
    {
        $source = (string) file_get_contents(app_path('Pwa/Livewire/Accueil.php'));

        // Les commentaires NOMMENT les valeurs retirées : les relire ferait
        // rougir ce cas à tort, et un cas qui crie à tort finit désactivé.
        $code = (string) preg_replace('#/\*.*?\*/#s', '', $source);
        $code = (string) preg_replace('#//[^\n]*#', '', $code);

        foreach (['200000', '165000', '82500', '40000', '25000'] as $montant) {
            $this->assertStringNotContainsString(
                $montant,
                $code,
                "Un montant en dur (« {$montant} ») a été réintroduit dans le tableau de bord. "
                .'On décide sur ces nombres.',
            );
        }

        // UN SEUL `catch (\Throwable)`, et c'est celui de la bande
        // d'indicateurs. Les autres `catch` du fichier nomment une exception
        // MÉTIER précise (`ChevauchementDetecteException`, `RuntimeException`)
        // et remontent son message à l'écran : ils ne remplacent rien, ils
        // refusent. Un second `catch (\Throwable)` serait, lui, le retour du
        // défaut — c'est cette forme-là qu'on compte.
        $this->assertSame(
            1,
            substr_count($code, 'catch (\Throwable'),
            'Un second `catch (\Throwable)` est apparu : le seul autorisé '
            .'entoure la bande d indicateurs et ne remplace aucun chiffre.',
        );

        // Et aucun `catch` du fichier n'avale : chaque bloc fait quelque chose
        // de son exception — `report()`, ou une erreur remontée à l'écran.
        preg_match_all('#catch \([^)]*\)\s*\{(.*?)\n        \}#s', $code, $blocs);

        foreach ($blocs[1] as $index => $corps) {
            $this->assertNotSame(
                '',
                trim($corps),
                "Le catch n° {$index} est vide : il avale son exception.",
            );
        }
    }

    /**
     * Les huit indicateurs affichés sont ceux du Service, pas un recalcul.
     */
    #[Test]
    public function les_huit_indicateurs_viennent_du_service_et_sont_tous_rendus(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $attendus = app(TableauDeBordService::class)->indicateurs(Periode::mois());

        $this->assertCount(8, $attendus);

        $rendu = Livewire::test(Accueil::class);

        foreach (array_keys($attendus) as $cle) {
            $rendu->assertSee((string) __('accueil_pwa.kpi.'.$cle.'.libelle'));
        }
    }

    /**
     * Le chemin d'échec est RÉELLEMENT exécuté — une branche de secours jamais
     * empruntée est exactement PA-59/60/61.
     */
    #[Test]
    public function un_echec_de_lecture_affiche_non_consulte_et_jamais_zero(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $this->app->bind(TableauDeBordService::class, static fn (): TableauDeBordService => new class () extends TableauDeBordService {
            public function indicateurs(Periode $periode): array
            {
                throw new RuntimeException('source indisponible');
            }
        });

        Livewire::test(Accueil::class)
            ->assertSee((string) __('accueil_pwa.non_consulte'))
            ->assertSee((string) __('accueil_pwa.lecture_impossible'))
            // ⚠ LE POINT DU CAS : rien ne se substitue au chiffre absent.
            //
            // L'assertion portait sur le LIBELLÉ de l'indicateur, et elle a
            // cessé d'être juste le 02/09/2026 : les trois panneaux sont
            // désormais montés en même temps (bascule locale), et la carte
            // « Chiffre d'affaires encaissé » du pilotage consolidé nomme cet
            // indicateur — en affichant « Non consulté » à la place du montant,
            // ce qui est exactement le comportement voulu. Le cas n'est pas
            // affaibli : il porte sur ce qu'il visait réellement, la CARTE de
            // la bande d'indicateurs. `carte-kpi` est l'anatomie du maître
            // (`tableau-de-bord.html` l.15) ; zéro carte rendue = zéro chiffre
            // substitué. En marche nominale elles sont SEIZE — huit par
            // conteneur, l'accordéon et la grille —, et le cas voisin
            // `les_huit_indicateurs_viennent_du_service_et_sont_tous_rendus`
            // tient ce chiffre. Sans lui, `assertDontSee` passerait aussi sur
            // une vue qui aurait cessé de rendre la bande.
            //
            // ⚠ LE LIBELLÉ CHOISI EST CELUI QUI N'APPARAÎT QUE LÀ. Cinq des
            // huit indicateurs sont repris par les cartes du pilotage
            // consolidé (CA encaissé, trésorerie, valeur du stock) ou par ses
            // libellés propres ; « Taux d'occupation hôtel » n'existe QUE dans
            // la bande. Prendre le premier venu ferait un cas qui ne peut plus
            // être vert, ou pire, un cas vert pour la mauvaise raison.
            ->assertDontSee((string) __('accueil_pwa.kpi.taux_occupation.libelle'));
    }

    /* ================================================================
       2 — LA PÉRIODE (A3)
       ================================================================ */

    #[Test]
    public function une_periode_inconnue_ne_produit_ni_500_ni_repli_muet(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        // La route, telle qu'un utilisateur la compose.
        $this->get('/pwa/?periode=ce_siecle')
            ->assertOk()
            ->assertSee('ce_siecle', false);

        Livewire::test(Accueil::class, ['periode' => 'ce_siecle'])
            ->set('filtrePeriode', 'ce_siecle')
            ->assertOk()
            // Le repli est DIT : les chiffres sont ceux du mois, et l'écran
            // prévient qu'ils ne répondent pas à la demande.
            ->assertSee(mb_substr((string) __('accueil_pwa.periode_inconnue', [
                'code' => 'ce_siecle',
                'defaut' => __('accueil_pwa.periodes.mois'),
            ]), 0, 40));
    }

    #[Test]
    public function une_periode_connue_ne_declenche_aucun_bandeau(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(Accueil::class)
            ->set('filtrePeriode', 'trimestre')
            ->assertOk()
            ->assertDontSee(mb_substr((string) __('accueil_pwa.periode_inconnue', [
                'code' => 'x',
                'defaut' => 'y',
            ]), 0, 30));
    }

    /* ================================================================
       3 — LE DROIT EXIGÉ EST CELUI DU MODULE ÉCRIT
       ================================================================ */

    /**
     * `rh` a `M11 = 'L'`, `M1 = '-'` et `M3 = '-'` : aucune action rapide.
     * `comptable` a `M11 = 'L'` : il lit l'écran, il n'y écrit pas.
     */
    #[Test]
    public function une_action_rapide_est_refusee_a_un_role_sans_le_droit(): void
    {
        $this->actingAs($this->utilisateur('rh'));

        Livewire::test(Accueil::class)
            ->call('ouvrirReservationRapide')
            ->assertForbidden();

        Livewire::test(Accueil::class)
            ->call('ouvrirClientRapide')
            ->assertForbidden();

        Livewire::test(Accueil::class)
            ->call('ouvrirCheckinRapide', 'peu-importe')
            ->assertForbidden();
    }

    /**
     * ⚠ LE CAS QUI SÉPARE LE MODULE DE L'ÉCRAN DU MODULE ÉCRIT.
     *
     * Le cas précédent ne le prouve PAS, et c'est mesuré : retirer
     * `exigerEcriture(self::MODULE_HEBERGEMENT)` d'`ouvrirReservationRapide` ne
     * l'a pas fait rougir. `rh` a `M11 = 'L'`, donc le droit de l'ÉCRAN suffit
     * déjà à refuser — la garde du module écrit n'était jamais atteinte.
     *
     * Aucun rôle de la matrice ne porte `M11 = 'C'` sans porter aussi M1 et M3 :
     * la distinction est indémontrable avec les onze rôles du CdCF. Le rôle
     * ci-dessous est donc FABRIQUÉ pour ce cas, avec le droit d'écriture sur
     * M11 et sur rien d'autre. Sans lui, la ligne `exigerEcriture(
     * self::MODULE_HEBERGEMENT)` pourrait disparaître sans qu'aucune assertion
     * bouge — c'est le genre de garde « déclarée, jamais éprouvée » que ce
     * dépôt poursuit.
     */
    #[Test]
    public function une_action_rapide_exige_le_droit_du_module_ecrit_et_pas_celui_de_l_ecran(): void
    {
        $this->actingAs($this->utilisateurAvecM11Seul());

        // M11 = C : le droit de l'écran est acquis. M1 et M3 sont à '-'.
        Livewire::test(Accueil::class)
            ->call('ouvrirReservationRapide')
            ->assertForbidden();

        Livewire::test(Accueil::class)
            ->call('ouvrirClientRapide')
            ->assertForbidden();

        Livewire::test(Accueil::class)
            ->call('ouvrirCheckoutRapide', 'peu-importe')
            ->assertForbidden();

        // Et la LECTURE, elle, reste ouverte : le refus porte sur l'écriture,
        // pas sur la page.
        Livewire::test(Accueil::class)->assertOk();
    }

    /**
     * Le premier niveau du RBAC : le bouton n'est pas rendu inerte, il est
     * ABSENT. Un bouton qui refuse toujours n'apprend rien.
     *
     * ⚠ L'assertion porte sur le GESTE (`wire:click="ouvrirReservationRapide"`),
     * pas sur le LIBELLÉ : depuis le panneau « Accès rapides » (Alt+A,
     * `AccesRapide::ACTIONS_PAR_PAGE`), qui vit sur CHAQUE page et navigue
     * plutôt qu'il n'écrit, porte le même libellé « Nouvelle réservation »
     * en lien `<a href>` vers `pwa.reservations` — un rôle en lecture peut
     * légitimement s'Y rendre, il y trouvera un écran qui refuse l'écriture
     * lui-même. Chercher le seul libellé ferait ce test échouer sur une
     * coïncidence de texte entre deux fonctionnalités distinctes.
     */
    #[Test]
    public function les_raccourcis_d_ecriture_sont_masques_pour_un_role_en_lecture(): void
    {
        $this->actingAs($this->utilisateur('comptable'));

        $htmlLecture = (string) Livewire::test(Accueil::class)->html();
        $this->assertStringNotContainsString('wire:click="ouvrirReservationRapide"', $htmlLecture);
        $this->assertStringNotContainsString('wire:click="ouvrirClientRapide"', $htmlLecture);
        // La consultation, elle, reste ouverte : lire les stocks critiques
        // n'écrit rien.
        $this->assertStringContainsString(e((string) __('accueil_pwa.acces_rapide.stocks')), $htmlLecture);

        $this->actingAs($this->utilisateur('administrateur'));

        $htmlEcriture = (string) Livewire::test(Accueil::class)->html();
        $this->assertStringContainsString('wire:click="ouvrirReservationRapide"', $htmlEcriture);
        $this->assertStringContainsString('wire:click="ouvrirClientRapide"', $htmlEcriture);
    }

    /* ================================================================
       4 — LES GESTES PASSENT PAR LES SERVICES
       ================================================================ */

    #[Test]
    public function la_reservation_rapide_ecrit_par_le_service_de_domaine(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $arrivee = CarbonImmutable::today();

        Livewire::test(Accueil::class)
            ->call('ouvrirReservationRapide')
            ->set('resaClientId', $this->client->id)
            ->set('resaUniteId', $this->unite->id)
            ->set('resaCanalId', $this->canal->id)
            ->set('resaDateArrivee', $arrivee->toDateString())
            ->set('resaNuits', 3)
            ->call('enregistrerReservationRapide')
            ->assertHasNoErrors();

        $reservation = Reservation::firstOrFail();

        $this->assertSame($this->unite->id, $reservation->unite_id);
        $this->assertSame($this->client->id, $reservation->client_id);
        // Trois nuits : la date de départ est DÉRIVÉE, jamais saisie.
        $this->assertSame(
            $arrivee->addDays(3)->toDateString(),
            $reservation->date_depart->toDateString(),
        );
    }

    /**
     * RG-01 depuis le tableau de bord — le défaut que la version précédente
     * rouvrait par une autre porte, sur les mêmes tables.
     */
    #[Test]
    public function rg01_le_chevauchement_est_refuse_depuis_le_tableau_de_bord(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $arrivee = CarbonImmutable::today();

        Reservation::create([
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => $arrivee->toDateString(),
            'date_depart' => $arrivee->addDays(4)->toDateString(),
            'statut' => 'confirmee',
        ]);

        Livewire::test(Accueil::class)
            ->call('ouvrirReservationRapide')
            ->set('resaClientId', $this->client->id)
            ->set('resaUniteId', $this->unite->id)
            ->set('resaCanalId', $this->canal->id)
            ->set('resaDateArrivee', $arrivee->addDay()->toDateString())
            ->set('resaNuits', 2)
            ->call('enregistrerReservationRapide')
            ->assertHasErrors('resaUniteId');

        $this->assertSame(1, Reservation::count());
    }

    #[Test]
    public function le_check_in_passe_par_le_service_et_ecrit_le_cycle_de_l_unite(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $reservation = Reservation::create([
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => CarbonImmutable::today()->toDateString(),
            'date_depart' => CarbonImmutable::today()->addDays(2)->toDateString(),
            'statut' => 'confirmee',
        ]);

        Livewire::test(Accueil::class)
            ->call('ouvrirCheckinRapide', $reservation->id)
            ->call('confirmerCheckin')
            ->assertHasNoErrors();

        $sejour = Sejour::where('reservation_id', $reservation->id)->firstOrFail();

        $this->assertNotNull($sejour->date_checkin_reel);
        $this->assertNull($sejour->date_checkout_reel);
        // ⚠ La valeur EXACTE de l'`enum` — `occupee`, pas « Occupée ». La
        // version précédente écrivait la seconde, qui ne « marchait » que par
        // la collation insensible à la casse de MySQL.
        $this->assertSame('occupee', $this->unite->refresh()->statut);
        $this->assertSame('en_cours', $reservation->refresh()->statut);
    }

    #[Test]
    public function le_check_out_laisse_l_unite_en_nettoyage_jamais_libre(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $reservation = Reservation::create([
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => CarbonImmutable::today()->toDateString(),
            'date_depart' => CarbonImmutable::today()->addDays(2)->toDateString(),
            'statut' => 'confirmee',
        ]);

        Livewire::test(Accueil::class)
            ->call('ouvrirCheckinRapide', $reservation->id)
            ->call('confirmerCheckin')
            ->call('ouvrirCheckoutRapide', $reservation->id)
            ->call('confirmerCheckout')
            ->assertHasNoErrors();

        $this->assertNotNull(
            Sejour::where('reservation_id', $reservation->id)->firstOrFail()->date_checkout_reel,
        );
        $this->assertSame('nettoyage', $this->unite->refresh()->statut);
        $this->assertSame('terminee', $reservation->refresh()->statut);
    }

    /**
     * Un second check-in sur la même réservation est REFUSÉ et le dit — il ne
     * crée pas un second séjour en silence.
     */
    #[Test]
    public function un_second_check_in_est_refuse_et_nomme(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $reservation = Reservation::create([
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => CarbonImmutable::today()->toDateString(),
            'date_depart' => CarbonImmutable::today()->addDays(2)->toDateString(),
            'statut' => 'confirmee',
        ]);

        Livewire::test(Accueil::class)
            ->call('ouvrirCheckinRapide', $reservation->id)
            ->call('confirmerCheckin')
            ->call('ouvrirCheckinRapide', $reservation->id)
            ->call('confirmerCheckin')
            ->assertHasErrors('sejourReservationId');

        $this->assertSame(1, Sejour::where('reservation_id', $reservation->id)->count());
    }

    #[Test]
    public function le_client_rapide_est_une_vraie_fiche_sans_telephone_fabrique(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(Accueil::class)
            ->call('ouvrirClientRapide')
            ->set('clientNom', 'AGOSSOU')
            ->set('clientTelephone', '01 96 55 44 33')
            ->set('clientType', 'agence')
            ->call('enregistrerClientRapide')
            ->assertHasNoErrors();

        $cree = Client::where('nom', 'AGOSSOU')->firstOrFail();

        $this->assertSame('01 96 55 44 33', $cree->telephone);
        // La valeur du SCHÉMA, jamais le libellé du maître : `clients.type_client`
        // est un `enum` et n'accepte pas « Agence partenaire ».
        $this->assertSame('agence', $cree->type_client);

        // Le motif retiré de M1 ne doit pas survivre ici. Les commentaires le
        // NOMMENT pour qu'on sache pourquoi il est proscrit : c'est le code
        // qu'on relit, pas la note qui l'explique.
        $code = (string) preg_replace(
            '#//[^\n]*#',
            '',
            (string) preg_replace(
                '#/\*.*?\*/#s',
                '',
                (string) file_get_contents(app_path('Pwa/Livewire/Accueil.php')),
            ),
        );

        $this->assertStringNotContainsString(
            '0100000000',
            $code,
            'Un numéro de téléphone fabriqué a été réintroduit.',
        );
    }

    /* ================================================================
       5 — LES ÉCRANS DE CONSULTATION (A6)
       ================================================================ */

    #[Test]
    public function ecrans_visibles_filtre_par_droit_reel_et_a_un_lecteur(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $composant = new Accueil();
        $tous = $composant->ecransVisibles();

        $this->assertCount(count(Accueil::ECRANS_AUTORISES), $tous);

        // `guide` : `M11 = '-'`, `M3 = 'L'` — un seul des sept écrans reste.
        $this->actingAs($this->utilisateur('guide'));

        $duGuide = (new Accueil())->ecransVisibles();
        $modules = array_column($duGuide, 'module');

        $this->assertContains('M3', $modules);
        $this->assertNotContains('M11', $modules);
        $this->assertNotContains('M10', $modules);
    }

    /* ================================================================
       6 — L'EXPORT
       ================================================================ */

    /**
     * PA-119 — une liste vide se REFUSE, elle ne produit pas une page blanche.
     */
    #[Test]
    public function un_export_sans_ligne_est_refuse_et_ne_telecharge_rien(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        // « stocks » ne porte que les articles SOUS LE SEUIL
        // (`articlesCritiques()`) : sans aucun article au référentiel de ce
        // test, la liste est vide par construction — PA-119.
        Livewire::test(Accueil::class)
            ->set('etatFormulaire', 'rapport')
            ->set('typeRapport', 'stocks')
            ->set('formatExport', 'pdf')
            ->call('genererExport')
            ->assertHasErrors('typeRapport');
    }

    /**
     * Et un rôle en LECTURE exporte : le droit de lire est porté par la route,
     * l'export n'ajoute aucun accès (décision du 31/08/2026).
     */
    #[Test]
    public function un_role_en_lecture_peut_exporter_la_synthese(): void
    {
        $this->actingAs($this->utilisateur('comptable'));

        $reponse = Livewire::test(Accueil::class)
            ->set('etatFormulaire', 'rapport')
            ->set('typeRapport', 'synthese')
            ->set('formatExport', 'pdf')
            ->call('genererExport');

        $reponse->assertHasNoErrors();
        $this->assertNotNull($reponse->effects['download'] ?? null);
    }

    /* ================================================================
       7 — LES ALERTES DE STOCK
       ================================================================ */

    /**
     * Le stock est CALCULÉ : `articles.quantite_stock` n'existe pas, et la
     * version précédente affichait « 2 articles critiques » écrit en dur.
     */
    #[Test]
    public function la_liste_des_articles_critiques_est_calculee_et_jamais_un_compteur_fixe(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $this->assertFalse(
            \Illuminate\Support\Facades\Schema::hasColumn('articles', 'quantite_stock'),
            'La colonne `quantite_stock` est apparue : ce test et le composant '
            .'reposent sur son absence, relire avant de corriger.',
        );

        Livewire::test(Accueil::class)
            ->set('etatFormulaire', 'stocks-critiques')
            ->assertOk()
            // Aucun article au référentiel : la modale le DIT.
            ->assertSee((string) __('accueil_pwa.modale_stocks.vide'));
    }

    // =====================================================================
    // PILOTAGE CONSOLIDÉ — le portage de `m11-pilotage.html` (31/08/2026)
    // =====================================================================

    /**
     * LE GRAPHIQUE DU MAÎTRE EST POSÉ, ET SA SÉRIE SUIT LA PÉRIODE.
     *
     * Deux moitiés, et la seconde est celle qu'on oublie : un graphique posé au
     * premier rendu et jamais remis à jour affiche les chiffres de la fenêtre
     * initiale sous les boutons « 3 mois / 6 mois / 1 an ». Le bloc de données
     * est donc vérifié APRÈS un changement de fenêtre, pas seulement au GET.
     *
     * ⚠ MUTATION ÉPROUVÉE : retirer `wire:ignore` du conteneur laisse ce cas
     * VERT — c'est une limite assumée, un test HTTP ne voit pas Livewire
     * détruire un canevas au morphing. Ce qui mord ici : supprimer le
     * `<script type="application/json">`, ou remonter la balise `@assets` de
     * Chart.js. Les deux ont été cassées et vues rouges.
     */
    #[Test]
    public function le_graphique_du_maitre_est_pose_avec_une_ressource_locale(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        // ⚠ LE GRAPHIQUE A CHANGÉ D'ONGLET LE 31/08/2026, ET C'EST LE MAÎTRE
        // QUI LE DIT. `tableau-de-bord.html` l.104-116 pose « Chiffre
        // d'affaires vs Dépenses » dans la VUE D'EXPLOITATION — l'onglet par
        // défaut —, pas dans « Pilotage consolidé », dont les deux graphiques
        // sont la marge par activité et les créances par ancienneté. Ce cas
        // interrogeait `?panel=pilotage` ; il interroge désormais l'écran tel
        // qu'il s'ouvre, ce qui est aussi ce que le Product Owner regarde.
        $html = (string) $this->get('/pwa/')->assertOk()->getContent();

        $this->assertStringContainsString('assets/js/vendor/chart.umd.min.js', $html);
        $this->assertStringContainsString('id="graphique-ca"', $html);
        $this->assertStringContainsString('id="donnees-graphique-ca"', $html);

        // CONTRASTE — le graphique est dans l'onglet EXPLOITATION, et les deux
        // graphiques du consolidé sont dans le sien.
        //
        // ⚠ CE CONTRASTE A CHANGÉ DE NATURE LE 02/09/2026, ET IL N'EST PAS
        // AFFAIBLI. Il interrogeait `?panel=pilotage` et vérifiait l'ABSENCE
        // de `graphique-ca` ; les trois panneaux sont désormais montés
        // ensemble — Chart.js a besoin d'un canvas attaché pour mesurer, et un
        // graphe construit sous `display:none` sort à zéro pixel (le maître le
        // dit lui-même, `tableau-de-bord.html` l.464-468). L'absence n'est donc
        // plus une question. La question qui reste est la BONNE : dans quel
        // panneau chaque canevas se trouve-t-il ? Elle se mesure par position,
        // et elle mord sur exactement les mêmes fautes — un graphique rendu
        // dans le mauvais onglet, ou dans les deux.
        $ouverturePilotage = strpos($html, 'data-panneau-tb="pilotage"');
        $this->assertNotFalse($ouverturePilotage, 'Le panneau « Pilotage consolidé » n est pas monté.');

        $this->assertLessThan(
            $ouverturePilotage,
            strpos($html, 'id="graphique-ca"'),
            'Le graphique « Chiffre d affaires vs Depenses » doit vivre dans la vue d exploitation, comme au maitre.',
        );

        // Et le contraire pour les deux blocs du consolidé : les rendre dans
        // l'exploitation serait la même faute, dans l'autre sens.
        //
        // ⚠ ON MESURE LE TITRE, PAS LE CANEVAS, ET C'EST DÉLIBÉRÉ. Les deux
        // graphiques du pilotage ne posent leur `<canvas>` que si la donnée a
        // été LUE : sans exercice comptable ouvert, « Marge sur coûts directs »
        // rend « Non consulté » et aucun canevas — un canevas vide se lirait
        // comme une marge nulle. Ancrer ce cas sur le canevas le rendrait
        // dépendant du jeu de données, donc vert ou rouge pour une raison qui
        // n'est pas la sienne. Le TITRE, lui, est toujours rendu : c'est le
        // bloc dont on veut connaître l'onglet.
        foreach (['accueil_pwa.marge.titre', 'accueil_pwa.creances.titre'] as $cle) {
            $this->assertGreaterThan(
                $ouverturePilotage,
                strpos($html, e((string) __($cle))),
                $cle.' doit vivre dans le panneau « Pilotage consolide ».',
            );
        }

        // Un seul canevas par graphique : deux `id` identiques dans un même
        // document, et le navigateur n'en dessine qu'un — celui qu'on ne
        // regarde pas.
        $this->assertSame(1, substr_count($html, 'id="graphique-ca"'));

        // La PWA doit rester servable sans Internet : la copie est locale, et
        // une balise CDN réintroduite ici fonctionnerait parfaitement au bureau
        // du développeur sans que personne ne le voie.
        $this->assertStringNotContainsString('cdn.jsdelivr', $html);
        $this->assertStringNotContainsString('cdnjs.cloudflare', $html);

        // Le fichier est SERVI, pas seulement référencé : un `asset()` vers un
        // chemin absent rend un 404 muet dans la console du navigateur.
        $this->assertFileExists(public_path('assets/js/vendor/chart.umd.min.js'));

        Livewire::test(Accueil::class)
            ->set('onglet', 'exploitation')
            ->set('moisSerie', 12)
            ->assertOk()
            ->assertSee('donnees-graphique-ca', false);
    }

    /**
     * UNE SÉRIE NON LUE NE DESSINE RIEN — Article 7 et PA-59/60/61.
     *
     * Un graphique plat se lit comme une activité nulle, jamais comme une
     * absence de mesure. Le canevas doit donc DISPARAÎTRE, et la phrase
     * « rien n'a été mesuré » prendre sa place.
     */
    #[Test]
    public function une_serie_illisible_retire_le_graphique_au_lieu_de_le_vider(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $this->app->bind(TableauDeBordService::class, fn (): TableauDeBordService => new class () extends TableauDeBordService {
            public function indicateurs(Periode $periode): array
            {
                throw new RuntimeException('lecture impossible');
            }
        });

        // L'onglet d'EXPLOITATION, celui qui porte désormais le graphique.
        $html = (string) $this->get('/pwa/')->assertOk()->getContent();

        $this->assertStringNotContainsString('id="graphique-ca"', $html);
        $this->assertStringContainsString(e(__('accueil_pwa.lecture_impossible')), $html);
    }

    /**
     * « À TRAITER » LIT PLUSIEURS SOURCES, ET DIT COMBIEN IL EN A LUES.
     *
     * Le panneau n'en portait qu'une — le stock — ce qui affichait « aucune
     * alerte » sur un exercice comptable déséquilibré. Ce qui compte ici n'est
     * pas le nombre d'alertes (il dépend des données) mais le fait que le
     * décompte des SOURCES soit rendu : sans lui, un rôle sans droit M10 lit
     * « rien à traiter » sur une comptabilité en défaut.
     *
     * ⚠ MUTATION ÉPROUVÉE : faire compter `$possibles` sans jamais incrémenter
     * `$sources` fait apparaître « 0 source(s) consultée(s) sur 4 », et
     * l'assertion de contraste ci-dessous devient rouge.
     */
    #[Test]
    public function le_panneau_a_traiter_dit_combien_de_sources_il_a_lues(): void
    {
        $administrateur = $this->utilisateur('administrateur');
        $this->actingAs($administrateur);

        $html = (string) $this->get('/pwa/?panel=pilotage')->assertOk()->getContent();

        $this->assertStringContainsString(e(__('accueil_pwa.alertes.titre')), $html);

        // Un administrateur a les quatre modules : trois sources répondent
        // toujours (M3, M11, M6) ; la quatrième (M10) n'existe que s'il y a un
        // exercice OUVERT — et son absence est justement ce que le décompte
        // doit dire, plutôt que de l'affirmer « sans alerte ».
        $this->assertStringContainsString(
            e(__('accueil_pwa.alertes.sources', ['lues' => 3, 'total' => 4])),
            $html,
            'Sans exercice ouvert, la source M10 n\'a rien dit : le decompte doit le montrer.',
        );

        // ⚠ CONTRASTE — sans lui, un composant qui n'incrémenterait JAMAIS
        // `$sources` passerait ce cas. Un rôle privé de M3, M6 et M10 doit voir
        // le décompte TOMBER.
        $this->actingAs($this->utilisateurAvecM11Seul());

        $htmlRestreint = (string) $this->get('/pwa/?panel=pilotage')->assertOk()->getContent();

        $this->assertStringContainsString(
            e(__('accueil_pwa.alertes.sources', ['lues' => 1, 'total' => 4])),
            $htmlRestreint,
            'Un role sans M3, M6 ni M10 ne doit pas se voir annoncer quatre sources lues.',
        );
    }

    /**
     * LES SIX KPI CONSOLIDÉS DU MAÎTRE SONT TOUS RENDUS (REFUS LEVÉ 02/09/2026).
     *
     * L'ancien motif — « Masse salariale n'existe nulle part côté serveur » —
     * confondait la masse salariale (somme des bruts, un fait) et le coût
     * employeur total que `CalculPaieService` refuse à raison (PA-53).
     * `LivreDePaieService::totaux()` porte les deux séparément ; la carte
     * n'affiche jamais le second.
     */
    #[Test]
    public function le_pilotage_rend_les_six_kpi_du_maitre(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/?panel=pilotage')->assertOk()->getContent();

        foreach ([
            __('accueil_pwa.kpi.chiffre_affaires_encaisse.libelle'),
            __('accueil_pwa.pilotage.resultat_net'),
            __('accueil_pwa.kpi.tresorerie_caisse.libelle'),
            __('accueil_pwa.pilotage.creances_clients'),
            __('accueil_pwa.kpi.valeur_stock.libelle'),
            __('accueil_pwa.pilotage.masse_salariale'),
        ] as $libelle) {
            $this->assertStringContainsString(e((string) $libelle), $html, "Le KPI « {$libelle} » n'est pas rendu.");
        }

        // Sans exercice comptable ouvert, le résultat net n'a PAS été lu : la
        // carte dit « Non consulté », jamais « 0 F ».
        $this->assertStringContainsString(e(__('accueil_pwa.non_consulte')), $html);

        // Aucun bulletin n'a été établi dans ce test : la carte « Masse
        // salariale » dit une ABSENCE RÉELLE, jamais « 0 F » — distincte de
        // « Non consulté » (Article 7).
        $this->assertStringContainsString(e(__('accueil_pwa.pilotage.masse_salariale_absente')), $html);
    }

    /**
     * PLUS AUCUNE SECTION DE REFUS N'EST RENDUE — directive du 31/08/2026.
     */
    #[Test]
    public function le_tableau_de_bord_ne_rend_plus_aucune_section_de_refus(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        foreach (['exploitation', 'pilotage', 'croise'] as $panneau) {
            $html = (string) $this->get('/pwa/?panel='.$panneau)->assertOk()->getContent();

            $this->assertStringNotContainsString(
                'Ce que cet écran ne fait pas',
                $html,
                "Le panneau « {$panneau} » rend encore une section de refus.",
            );
        }
    }

    /**
     * L'alerte de stock critique navigue vers l'écran des stocks — et la
     * branche est réellement EXÉCUTÉE, pas seulement possible.
     *
     * ## Le 500 que ce cas épingle (31/08/2026)
     *
     * `alertesPilotage()` appelait `route('pwa.stocks')` — la route s'appelle
     * `pwa.stocks.liste`, et `route()` lève sur un nom inconnu. Le défaut a
     * atteint le navigateur du Product Owner sur `/pwa`, alors que TOUTES les
     * gardes étaient vertes : l'alerte ne se rend que s'il existe un article
     * sous son seuil, et aucune base de test n'en avait. La branche n'était
     * jamais exécutée — un contrôle par rendu ne voit que ce que ses données
     * déclenchent.
     *
     * Ce cas SÈME donc l'article critique avant de charger la page : c'est la
     * moitié dynamique du correctif, `RoutesNommeesExistentTest` étant la
     * moitié statique (tout nom de route littéral, toutes branches).
     */
    #[Test]
    public function l_alerte_de_stock_critique_navigue_vers_l_ecran_des_stocks(): void
    {
        \App\Domain\Stocks\Models\Article::create([
            'libelle' => 'Casier test critique',
            'categorie' => 'boisson',
            'unite_mesure' => 'casier',
            'seuil_alerte' => '5.00',
            'cout_moyen_pondere' => '0.00',
        ]);
        // Aucun mouvement : stock à 0, sous le seuil de 5 — l'alerte se rend.

        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/?panel=pilotage')->assertOk()->getContent();

        $this->assertStringContainsString(
            route('pwa.stocks.liste'),
            $html,
            "L'alerte de stock critique ne navigue pas vers l'écran des stocks.",
        );
    }

    /* ================================================================
       7 — « PAR MODULE » : LE RBAC PAR CARTE
       (les valeurs réelles des neuf cartes sont éprouvées contre le jeu
        de démonstration dans `AccueilParModuleTest` — `DatabaseSeeder`
        refuse une base déjà peuplée, or le `setUp()` de ce fichier sème
        ses propres fixtures)
       ================================================================ */

    /**
     * Chaque carte est gardée par le droit de SON module — la règle du menu
     * (`MenuLateral`), pas celle de l'écran M11 : un compte qui n'a QUE M11
     * voit l'onglet Pilotage, mais aucune carte, et l'état vide du maître le
     * dit — jamais une grille silencieusement absente.
     */
    #[Test]
    public function une_carte_par_module_exige_le_droit_de_son_module_et_pas_seulement_m11(): void
    {
        $this->actingAs($this->utilisateurAvecM11Seul());

        $html = (string) $this->get('/pwa/?panel=pilotage')->assertOk()->getContent();

        $this->assertStringContainsString(
            e((string) __('accueil_pwa.pilotage.modules.vide')),
            $html,
            "Sans aucun droit de module, l'état vide du maître doit être rendu.",
        );

        foreach ([
            __('accueil_pwa.pilotage.modules.vehicules.titre'),
            __('accueil_pwa.pilotage.modules.depenses.titre'),
            __('accueil_pwa.pilotage.modules.tourisme.titre'),
        ] as $titre) {
            $this->assertStringNotContainsString(
                e((string) $titre),
                $html,
                "La carte « {$titre} » est rendue à un compte qui n'a pas le droit de son module.",
            );
        }
    }

    /* ----------------------------------------------------- auxiliaires */

    /**
     * Un compte avec `M11 = 'C'` et RIEN d'autre — fabriqué pour ce fichier.
     *
     * Les droits sont posés module par module, jamais par un `attach()` en
     * masse : un module ajouté à la matrice demain ne doit pas obtenir un droit
     * d'écriture par effet de bord (même règle que le compte administrateur du
     * premier démarrage côté Flutter).
     */
    private function utilisateurAvecM11Seul(): User
    {
        $role = Role::create(['libelle' => 'essai.m11.seul']);

        $role->permissions()->attach(
            Permission::where('module', 'M11')->pluck('id')->all(),
        );

        return User::create([
            'login' => 'm11.seul',
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => $role->id,
            'statut' => 'actif',
        ]);
    }

    private function utilisateur(string $role): User
    {
        $existant = User::where('login', 'm11.'.$role)->first();

        if ($existant instanceof User) {
            return $existant;
        }

        return User::create([
            'login' => 'm11.'.$role,
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}

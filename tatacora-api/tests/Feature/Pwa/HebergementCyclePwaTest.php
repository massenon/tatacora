<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\Sejour;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ReservationService;
use App\Models\User;
use App\Pwa\Livewire\Hebergement\Hebergement;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Pwa\Concerns\OuvreLaSaisie;
use Tests\TestCase;

/**
 * Le CYCLE OPERATIONNEL de l unite, l ARCHIVAGE du parc, et la RESERVATION
 * RAPIDE du comptoir (M1) — les quatre gestes d ecriture du Plan
 * d Hebergement.
 *
 * ## Ce que ces cas ferment
 *
 * Trois defauts reproduits le 31/08/2026 sur cet ecran :
 *
 * 1. `enregistrerReservationRapide` refaisait RG-01 a la main, hors
 *    transaction et sans `lockForUpdate()`, avec un `whereBetween` — donc un
 *    intervalle FERME. Deux consequences : deux receptionnistes passaient tous
 *    deux le test, et une arrivee le jour meme du depart precedent etait
 *    refusee, ce qui bloquait une nuit A CHAQUE ROTATION, toute l annee. Le
 *    cas `une_arrivee_le_jour_du_depart_precedent_est_acceptee` est la garde
 *    permanente contre le second.
 * 2. Le client du comptoir etait cree avec un telephone FABRIQUE
 *    (`'0100000000'`) et rapproche sur le seul nom : deux homonymes
 *    fusionnaient en une fiche et un solde. Le champ est desormais une vraie
 *    cle etrangere vers le referentiel.
 * 3. `executerSuppressionHebergement` faisait `$u->delete()` sur une unite.
 *
 * ## MUTATIONS REELLEMENT EXECUTEES LE 31/08/2026 — toutes annulees ensuite
 *
 * Chacune a ete appliquee au code, la suite relancee, le rouge constate, puis
 * le fichier restaure et le vert reverifie. Un test qui ne peut pas echouer ne
 * compte pas.
 *
 * | # | Mutation appliquee | Cas devenu ROUGE |
 * |---|---|---|
 * | A | `enregistrerReservationRapide` : l appel a `ReservationService::creer()` remplace par le defaut d origine — `whereBetween` (intervalle FERME) + `Reservation::create()` en direct | `une_arrivee_le_jour_du_depart_precedent_est_acceptee` (« Failed asserting that false is true ») |
 * | A2 | le meme, garde de chevauchement entierement retiree — l etat exact que produit une course entre deux receptionnistes | `rg01_une_seconde_reservation_sur_la_meme_periode_est_refusee` |
 * | B | `'telephone' => '0100000000'` et la creation de fiche au comptoir reintroduites | `la_reservation_rapide_cree_par_le_service_et_sans_client_invente` |
 * | C | `archiverUnite` : `->update(['statut' => 'hors_service'])` remis en `->delete()` | `aucune_suppression_physique_ni_boite_native_dans_le_code_m1` (dans `HebergementPwaTest`) |
 * | D | `archiverUnite` : le recontrole du verrou d engagement retire | `une_unite_engagee_ne_s_archive_pas` |
 * | E | `etatsDuJour` : la branche `$sejour !== null => 'occupee'` neutralisee | `le_cycle_complet_avance_et_chaque_etape_s_affiche` (bouton « Effectuer Check-Out » absent) |
 *
 * ⚠ Ce que A2 dit et que A ne dit pas : un `exists()` reecrit ATTRAPE un
 * chevauchement franc dans un test mono-processus. La mutation A l a montre —
 * `rg01_...` est reste VERT sous elle. Ce qu aucun test PHPUnit ne peut
 * reproduire, c est la course elle-meme : deux transactions concurrentes qui
 * ne trouvent aucune ligne et inserent toutes les deux. A2 la simule en
 * retirant la garde, et c est le mieux que ce niveau de test puisse faire. La
 * garantie reelle reste le verrou pessimiste de
 * `VerificationChevauchementService`, et la seule facon de la conserver est de
 * ne jamais reecrire le controle ici.
 */
final class HebergementCyclePwaTest extends TestCase
{
    use OuvreLaSaisie;
    use RefreshDatabase;

    private CategorieHebergement $categorie;

    private UniteHebergement $unite;

    private Client $client;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->categorie = CategorieHebergement::create([
            'libelle' => 'Bungalow', 'capacite_max' => 2, 'tarif_base' => '28000.00',
        ]);
        $this->unite = UniteHebergement::create([
            'categorie_id' => $this->categorie->id, 'numero' => 'BNG-01', 'statut' => 'libre',
        ]);
        $this->client = Client::create([
            'nom' => 'KPETONI', 'prenom' => 'Julien',
            'telephone' => '01 90 00 00 02', 'type_client' => 'particulier',
        ]);
    }

    // =====================================================================
    // RG-01 — le Service, jamais une reecriture
    // =====================================================================

    /**
     * ⚠ `OuvreLaSaisie` n est PAS utilisable ici, et il vaut mieux l ecrire
     * que de contourner en rendant le parametre optionnel :
     * `assertLaModaleSOuvreEtRendExactementSesChamps` appelle l action SANS
     * argument, alors qu une reservation rapide part TOUJOURS d une unite —
     * c est le sens du geste, le receptionniste a la chambre sous les yeux.
     * Le contrat du trait est donc rejoue a la main, a l identique : la modale
     * ne rend que les champs declares, ni plus (une propriete non relue
     * deviendrait saisissable) ni moins (le formulaire serait ampute).
     */
    #[Test]
    public function la_modale_de_reservation_rapide_rend_exactement_ses_champs(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));

        $composant = Livewire::test(Hebergement::class);
        $avant = $this->liaisons($composant->html());

        $composant->call('ouvrirReservationRapide', $this->unite->id)
            ->assertSet('etatFormulaire', 'reservation-rapide');

        $apres = $this->liaisons($composant->html());

        $nouvelles = [];
        foreach ($apres as $propriete => $occurrences) {
            if ($occurrences > ($avant[$propriete] ?? 0)) {
                $nouvelles[] = $propriete;
            }
        }
        sort($nouvelles);

        $this->assertSame(
            ['rrClientId', 'rrDateArrivee', 'rrDateDepart'],
            $nouvelles,
            'La modale de reservation rapide ne rend pas exactement ses champs declares.',
        );
    }

    #[Test]
    public function la_reservation_rapide_est_refusee_et_tracee_pour_un_role_en_lecture(): void
    {
        $comptable = $this->utilisateur('comptable');
        $this->assertSame('L', $comptable->niveauSurModule('M1'));
        $this->actingAs($comptable);

        Livewire::test(Hebergement::class)
            ->call('ouvrirReservationRapide', $this->unite->id)
            ->assertSet('etatFormulaire', null)
            ->assertForbidden();

        $this->assertDatabaseHas('journal_securite', [
            'type_evenement' => 'acces_refuse_rbac',
            'utilisateur_id' => $comptable->id,
            'module_concerne' => 'M1',
        ]);
    }

    /**
     * Les liaisons `wire:model` d un rendu, quel que soit le modificateur.
     *
     * @return array<string, int>
     */
    private function liaisons(string $html): array
    {
        preg_match_all('/wire:model(?:\.[a-z0-9.]+)?="([A-Za-z0-9_.]+)"/', $html, $captures);

        return array_count_values($captures[1]);
    }

    #[Test]
    public function la_reservation_rapide_cree_par_le_service_et_sans_client_invente(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));

        Livewire::test(Hebergement::class)
            ->call('ouvrirReservationRapide', $this->unite->id)
            ->set('rrClientId', $this->client->id)
            ->set('rrDateArrivee', '2026-09-10')
            ->set('rrDateDepart', '2026-09-12')
            ->call('enregistrerReservationRapide')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $reservation = Reservation::query()->firstOrFail();
        $this->assertSame($this->client->id, $reservation->client_id);
        $this->assertSame($this->unite->id, $reservation->unite_id);

        // H2 — le defaut reproduit : aucune fiche client n a ete fabriquee, et
        // AUCUN telephone n a ete invente. Un seul client existe, celui du
        // referentiel, avec le numero qu on appellera reellement.
        $this->assertSame(1, Client::count(), 'Une fiche client a ete creee par le comptoir.');
        $this->assertSame('01 90 00 00 02', Client::query()->firstOrFail()->telephone);
        $this->assertDatabaseMissing('clients', ['telephone' => '0100000000']);
    }

    /**
     * RG-01 — DEUX RESERVATIONS CONCURRENTES SUR LA MEME UNITE ET LA MEME
     * PERIODE : la seconde est refusee, et rien n est ecrit.
     *
     * Le refus vient du Service sous verrou, et il arrive au champ `rrUniteId`
     * comme une erreur de validation lisible — la modale reste ouverte, la
     * saisie intacte.
     */
    #[Test]
    public function rg01_une_seconde_reservation_sur_la_meme_periode_est_refusee(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));

        app(ReservationService::class)->creer([
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-10',
            'date_depart' => '2026-09-14',
        ]);

        Livewire::test(Hebergement::class)
            ->call('ouvrirReservationRapide', $this->unite->id)
            ->set('rrClientId', $this->client->id)
            ->set('rrDateArrivee', '2026-09-12')
            ->set('rrDateDepart', '2026-09-16')
            ->call('enregistrerReservationRapide')
            ->assertHasErrors('rrUniteId')
            ->assertSet('etatFormulaire', 'reservation-rapide');

        $this->assertSame(1, Reservation::count(), 'RG-01 est contourne : une seconde ligne a ete ecrite.');
    }

    /**
     * ⚠ LA NUIT PERDUE A CHAQUE ROTATION — le defaut permanent de la version
     * precedente, et celui que personne ne signale comme un bug.
     *
     * `whereBetween` produit un intervalle FERME : une arrivee le jour meme du
     * depart precedent y etait vue comme un chevauchement. La chambre restait
     * donc bloquee une nuit entre deux clients, toute l annee, sans qu aucun
     * message ne l explique. Les bornes du Service sont SEMI-OUVERTES
     * (`debut < fin` et `fin > debut`) : le 14 se reloue le 14.
     */
    #[Test]
    public function une_arrivee_le_jour_du_depart_precedent_est_acceptee(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));

        app(ReservationService::class)->creer([
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-10',
            'date_depart' => '2026-09-14',
        ]);

        Livewire::test(Hebergement::class)
            ->call('ouvrirReservationRapide', $this->unite->id)
            ->set('rrClientId', $this->client->id)
            // Arrivee LE JOUR MEME du depart precedent.
            ->set('rrDateArrivee', '2026-09-14')
            ->set('rrDateDepart', '2026-09-16')
            ->call('enregistrerReservationRapide')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $this->assertSame(
            2,
            Reservation::count(),
            'Une arrivee le jour du depart precedent a ete refusee : la chambre '
            .'est bloquee une nuit a chaque rotation.',
        );
    }

    /**
     * L EXPORT EST UNE LECTURE — la contrepartie explicite du cas de refus
     * ci-dessus, et les deux se lisent ensemble.
     *
     * `la_reservation_rapide_est_refusee_et_tracee_pour_un_role_en_lecture`
     * dit ce qu un role `L` ne peut PAS faire ; ce cas-ci dit ce qu il doit
     * pouvoir faire. La frontiere est le point qui compte : un ecran qu on a
     * le droit de consulter, on a le droit de l emporter. `genererExport` ne
     * persiste rien — ni `etats_generes`, ni aucune table : il met en page les
     * lignes deja affichees.
     *
     * ⚠ Le controle du droit sur cette action ne vient PAS du middleware
     * `module:M1,L` : les middlewares gardent les routes `/pwa`, donc le GET
     * initial, tandis qu une action Livewire transite par la route dediee du
     * paquet, hors du groupe (PA-67). Ce qui tient, c est qu appeler l action
     * exige un instantane de composant valide — obtenu en servant la page,
     * qui, elle, est gardee. Le cas
     * `un_profil_sans_droit_sur_m1_est_refuse_sur_les_deux_pages`
     * (`HebergementPwaTest`) tient cette moitie-la.
     *
     * Mutation F, executee le 31/08/2026 :
     * `$this->exigerEcriture(self::MODULE);` remis en tete de
     * `genererExport()` — ce cas a rougi (HTTP 403 au lieu du telechargement).
     * Annulee, vert reverifie.
     */
    #[Test]
    public function un_role_en_lecture_seule_exporte_reellement_un_fichier(): void
    {
        $comptable = $this->utilisateur('comptable');
        $this->assertSame('L', $comptable->niveauSurModule('M1'), 'La matrice a change : ce cas ne verifie plus rien.');
        $this->actingAs($comptable);

        // Le parc n est pas vide : un export vide se refuse (PA-119), et ce
        // refus-la masquerait celui que ce cas cherche a exclure.
        $this->assertSame(1, UniteHebergement::count());

        Livewire::test(Hebergement::class)
            ->call('genererExport')
            ->assertHasNoErrors()
            ->assertFileDownloaded();

        // Et la branche tableur, qui passe par un autre chemin de reponse.
        Livewire::test(Hebergement::class)
            ->set('formatExport', 'excel')
            ->call('genererExport')
            ->assertHasNoErrors()
            ->assertFileDownloaded();

        // Refermer la modale d export n exige rien non plus : enfermer un role
        // en lecture dans un panneau qu il vient d ouvrir serait absurde.
        Livewire::test(Hebergement::class)
            ->set('etatFormulaire', 'export')
            ->call('fermerModales')
            ->assertSet('etatFormulaire', null);

        // ⚠ Le geste d ECRITURE, lui, reste ferme : sans ce contre-controle,
        // ce cas prouverait seulement que la garde a saute partout.
        Livewire::test(Hebergement::class)
            ->call('ouvrirFormulaireUnite')
            ->assertForbidden();
    }

    // =====================================================================
    // Le cycle operationnel — check-in, check-out, menage
    // =====================================================================

    /**
     * Le cycle complet, du comptoir a la chambre prete, en passant par les
     * ETATS DERIVES que l ecran affiche.
     *
     * Chaque etape verifie l etat AFFICHE, pas seulement la colonne : c est
     * l ecran qui doit rester vrai, et la pastille se derive des reservations
     * et du sejour, jamais de `statut` lu seul (RG-02).
     */
    #[Test]
    public function le_cycle_complet_avance_et_chaque_etape_s_affiche(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));

        app(ReservationService::class)->creer([
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => now()->subDay()->toDateString(),
            'date_depart' => now()->addDays(2)->toDateString(),
            'statut' => 'confirmee',
        ]);

        // 1. La reservation couvre aujourd hui : « Réservée », check-in offert.
        //    ⚠ `unites_hebergement.statut` vaut TOUJOURS `libre` en base a
        //    cette etape — l ecran ne le lit pas pour repondre a cette
        //    question.
        $this->assertSame('libre', $this->unite->refresh()->statut);
        $composant = Livewire::test(Hebergement::class);
        $composant->assertSee('Effectuer Check-In Client');

        // 2. Check-in : le sejour existe, l unite passe a `occupee`.
        $composant->call('effectuerCheckIn', $this->unite->id)->assertHasNoErrors();

        $this->assertSame('occupee', $this->unite->refresh()->statut);
        $this->assertSame(1, Sejour::count());
        $this->assertTrue(Sejour::query()->firstOrFail()->estEnCours());
        $this->assertSame('en_cours', Reservation::query()->firstOrFail()->statut);
        Livewire::test(Hebergement::class)->assertSee('Effectuer Check-Out');

        // 3. Check-out : l unite passe en NETTOYAGE, jamais directement en
        //    libre — accueillir un client dans une chambre non faite.
        Livewire::test(Hebergement::class)
            ->call('effectuerCheckOut', $this->unite->id)
            ->assertHasNoErrors();

        $this->assertSame('nettoyage', $this->unite->refresh()->statut);
        $this->assertNotNull(Sejour::query()->firstOrFail()->date_checkout_reel);
        $this->assertSame('terminee', Reservation::query()->firstOrFail()->statut);
        Livewire::test(Hebergement::class)->assertSee('Marquer Nettoyé & Prêt');

        // 4. Menage : le cycle boucle. Sans ce geste, toute unite liberee
        //    resterait en nettoyage indefiniment.
        Livewire::test(Hebergement::class)
            ->call('marquerNettoye', $this->unite->id)
            ->assertHasNoErrors();

        $this->assertSame('libre', $this->unite->refresh()->statut);
    }

    /**
     * Le check-in n est pas une etiquette : il exige une reservation dont le
     * sejour a COMMENCE. Faire entrer un client trois jours avant son arrivee
     * marquerait occupee une chambre encore vendable.
     */
    #[Test]
    public function un_check_in_sans_arrivee_du_jour_est_refuse_et_rien_ne_change(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));

        app(ReservationService::class)->creer([
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => now()->addDays(3)->toDateString(),
            'date_depart' => now()->addDays(5)->toDateString(),
            'statut' => 'confirmee',
        ]);

        Livewire::test(Hebergement::class)
            ->call('effectuerCheckIn', $this->unite->id)
            ->assertHasErrors('cycle');

        $this->assertSame(0, Sejour::count());
        $this->assertSame('libre', $this->unite->refresh()->statut);
    }

    #[Test]
    public function le_cycle_est_refuse_a_un_role_en_lecture_et_le_refus_est_trace(): void
    {
        $comptable = $this->utilisateur('comptable');
        $this->actingAs($comptable);

        Livewire::test(Hebergement::class)
            ->call('effectuerCheckIn', $this->unite->id)
            ->assertForbidden();

        $this->assertSame(0, Sejour::count());
        $this->assertDatabaseHas('journal_securite', [
            'type_evenement' => 'acces_refuse_rbac',
            'utilisateur_id' => $comptable->id,
            'module_concerne' => 'M1',
        ]);
    }

    // =====================================================================
    // Archivage du parc — ARCHIVER, jamais SUPPRIMER
    // =====================================================================

    /**
     * Ouvre la bascule « Suppression d'un enregistrement » (écran Paramètres,
     * 02/09/2026) — FERMÉE par défaut comme au maître (`options-systeme.js`) :
     * depuis cette date, l'archivage du parc est son consommateur et exige
     * qu'un Administrateur l'ait ouverte. Les cas d'archivage ci-dessous la
     * posent explicitement ; le cas qui vérifie la fermeture ne la pose pas.
     */
    private function ouvrirLaSuppression(): void
    {
        \App\Shared\Parametres\Models\ParametreSysteme::create([
            'cle' => \App\Shared\Parametres\Services\OptionsSystemeService::CLE_SUPPRESSION,
            'valeur' => 'true',
        ]);
    }

    /**
     * LA BASCULE FERMÉE (l'état par défaut) : le bouton d'archivage n'est pas
     * rendu — retiré, pas grisé (Article 3.3) — et l'action forgée est
     * refusée en 403, restaurer restant possible (une unité archivée ne doit
     * jamais être ENFERMÉE aux archives par la fermeture de la bascule).
     *
     * Éprouvé par mutation le 02/09/2026 : forcer `exigerSuppressionOuverte()`
     * à ne rien faire fait rougir ce cas (l'action passe en 200 et l'unité
     * part en `hors_service`) — restauré ensuite.
     */
    #[Test]
    public function l_archivage_est_retire_tant_que_la_bascule_suppression_est_fermee(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));

        // Le bouton n'est pas rendu…
        $html = (string) $this->get('/pwa/hebergement')->assertOk()->getContent();
        $this->assertStringNotContainsString('confirmerArchivageUnite', $html);

        // …et l'action forgée est refusée AVANT toute écriture.
        Livewire::test(Hebergement::class)
            ->call('confirmerArchivageUnite', $this->unite->id)
            ->assertForbidden();

        $this->assertSame('libre', $this->unite->refresh()->statut);

        // Restaurer n'est PAS derrière la bascule : une unité archivée avant
        // la fermeture doit pouvoir en sortir.
        $this->unite->update(['statut' => 'hors_service']);
        Livewire::test(Hebergement::class)
            ->call('restaurerUnite', $this->unite->id)
            ->assertHasNoErrors();
        $this->assertSame('libre', $this->unite->refresh()->statut);
    }

    #[Test]
    public function archiver_une_unite_la_retire_du_parc_sans_rien_effacer(): void
    {
        $this->ouvrirLaSuppression();
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));

        Livewire::test(Hebergement::class)
            ->call('confirmerArchivageUnite', $this->unite->id)
            ->assertSet('etatFormulaire', 'archivage')
            ->call('archiverUnite')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $this->unite->refresh();
        $this->assertSame('hors_service', $this->unite->statut);
        // Rien n est efface : la ligne est toujours la, et le parc la compte.
        $this->assertSame(1, UniteHebergement::count());
        $this->assertFalse($this->unite->estCommercialisable());

        // « reste restaurable » n est pas une promesse en l air.
        Livewire::test(Hebergement::class)
            ->call('restaurerUnite', $this->unite->id)
            ->assertHasNoErrors();

        $this->assertSame('libre', $this->unite->refresh()->statut);
    }

    /**
     * LE VERROU DU MAITRE : un element engage ailleurs ne s archive pas — la
     * ligne correspondante deviendrait illisible.
     */
    #[Test]
    public function une_unite_engagee_ne_s_archive_pas(): void
    {
        $this->ouvrirLaSuppression();
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));

        app(ReservationService::class)->creer([
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => now()->addDays(3)->toDateString(),
            'date_depart' => now()->addDays(5)->toDateString(),
        ]);

        Livewire::test(Hebergement::class)
            ->call('confirmerArchivageUnite', $this->unite->id)
            // La modale s ouvre BLOQUEE : le maitre y masque le bouton de
            // confirmation, et l ecran dit pourquoi.
            ->assertSee('Archivage impossible')
            ->call('archiverUnite')
            ->assertHasErrors('archivage');

        $this->assertSame('libre', $this->unite->refresh()->statut);
    }

    /**
     * RG-02 — une reservation ANNULEE ne retient plus rien : l unite
     * redevient archivable, sans qu aucun traitement n ait a propager quoi que
     * ce soit.
     */
    #[Test]
    public function une_reservation_annulee_ne_verrouille_plus_l_unite(): void
    {
        $this->ouvrirLaSuppression();
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));

        $service = app(ReservationService::class);
        $reservation = $service->creer([
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => now()->addDays(3)->toDateString(),
            'date_depart' => now()->addDays(5)->toDateString(),
        ]);
        $service->annuler($reservation);

        Livewire::test(Hebergement::class)
            ->call('confirmerArchivageUnite', $this->unite->id)
            ->call('archiverUnite')
            ->assertHasNoErrors();

        $this->assertSame('hors_service', $this->unite->refresh()->statut);
    }

    // =====================================================================
    // Le parc — ajout et modification
    // =====================================================================

    #[Test]
    public function le_formulaire_d_unite_ne_rend_que_les_colonnes_du_schema(): void
    {
        $this->assertLaModaleSOuvreEtRendExactementSesChamps(
            $this->utilisateur($this->roleQuiEcritSurM1()),
            Hebergement::class,
            'ouvrirFormulaireUnite',
            // + `uniteNouvelleCategorie` depuis le 01/09/2026 (modèle du
            // PO : la modale sait CRÉER la catégorie) — les trois champs de
            // la catégorie (libellé/tarif/capacité) n'apparaissent qu'une
            // fois la case cochée, donc hors du premier rendu mesuré ici.
            ['uniteNumero', 'uniteCategorieId', 'uniteNouvelleCategorie'],
        );
    }

    /**
     * ⚠ `statut` N EST PAS SAISI, et c est le point de ce cas : le cycle
     * operationnel appartient a `SejourService`. Une unite creee entre au parc
     * `libre`, jamais dans un etat choisi a la main qui ferait dire a l ecran
     * qu une chambre est occupee sans que personne y dorme.
     */
    #[Test]
    public function une_unite_creee_entre_au_parc_libre_et_le_statut_n_est_pas_saisissable(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));

        Livewire::test(Hebergement::class)
            ->call('ouvrirFormulaireUnite')
            ->set('uniteNumero', 'BNG-09')
            ->set('uniteCategorieId', $this->categorie->id)
            ->call('enregistrerUnite')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $creee = UniteHebergement::where('numero', 'BNG-09')->firstOrFail();
        $this->assertSame('libre', $creee->statut);

        // Aucune propriete du composant ne porte le statut : le champ du
        // maitre est refuse, pas seulement masque.
        $this->assertFalse(
            property_exists(Hebergement::class, 'uniteStatut'),
            'Le statut est redevenu saisissable : `unites_hebergement.statut` aurait deux ecrivains.',
        );
    }

    #[Test]
    public function modifier_une_unite_ne_cree_pas_de_seconde_ligne(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));

        Livewire::test(Hebergement::class)
            ->call('ouvrirFormulaireUnite', $this->unite->id)
            ->assertSet('uniteNumero', 'BNG-01')
            ->set('uniteNumero', 'BNG-01-BIS')
            ->call('enregistrerUnite')
            ->assertHasNoErrors();

        $this->assertSame(1, UniteHebergement::count());
        $this->assertSame('BNG-01-BIS', $this->unite->refresh()->numero);
    }

    // =====================================================================

    private function utilisateur(string $role): User
    {
        $existant = User::where('login', 'compte.'.$role)->first();

        if ($existant instanceof User) {
            return $existant;
        }

        return User::create([
            'login' => 'compte.'.$role,
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    /** Le role qui porte `M1 = C`, lu du referentiel plutot que suppose. */
    private function roleQuiEcritSurM1(): string
    {
        foreach (['receptionniste', 'gerant', 'administrateur'] as $role) {
            $candidat = Role::where('libelle', $role)->first();

            if ($candidat !== null && $candidat->niveauSurModule('M1') === 'C') {
                return $role;
            }
        }

        $this->fail('Aucun role du referentiel ne porte M1 = C.');
    }
}

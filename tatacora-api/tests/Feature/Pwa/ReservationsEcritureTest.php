<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ReservationService;
use App\Models\User;
use App\Pwa\Livewire\Hebergement\Reservations;
use App\Shared\Rbac\Models\JournalSecurite;
use App\Shared\Rbac\Models\Role;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Pwa\Concerns\OuvreLaSaisie;
use Tests\TestCase;

/**
 * Vague 2 — l'écran Réservations ÉCRIT : créer, modifier, annuler (EF-M1-02).
 *
 * Chaque cas emprunte réellement le chemin : le Service sous verrou (RG-01),
 * l'auto-exclusion en modification (PA-115), l'annulation qui libère l'unité
 * (RG-02), et le RBAC du canal web — le même refus que l'API, tracé.
 */
final class ReservationsEcritureTest extends TestCase
{
    use OuvreLaSaisie;
    use RefreshDatabase;

    private Client $client;

    private UniteHebergement $unite;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        // Depuis PA-168, un acompte avec mode de paiement produit sa pièce
        // comptable dans la MÊME transaction : la fiche complète a besoin du
        // plan, des journaux et d'un exercice ouvert.
        $this->seed(\Database\Seeders\ComptabiliteReferentielSeeder::class);

        $categorie = CategorieHebergement::create([
            'id' => (string) Str::uuid(), 'libelle' => 'Chambre', 'capacite_max' => 2, 'tarif_base' => 18000,
        ]);
        $this->unite = UniteHebergement::create([
            'id' => (string) Str::uuid(), 'categorie_id' => $categorie->id, 'numero' => 'CH-101', 'statut' => 'libre',
        ]);
        $this->client = Client::create([
            'id' => (string) Str::uuid(), 'nom' => 'KORA', 'prenom' => 'Jean',
            'telephone' => '01 97 35 59 74', 'type_client' => 'particulier',
        ]);
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => 'compte.'.$role,
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    /** Le rôle qui porte `M1 = C`, lu du référentiel plutôt que supposé. */
    private function roleQuiEcritSurM1(): string
    {
        foreach (['receptionniste', 'gerant', 'administrateur'] as $role) {
            $r = Role::where('libelle', $role)->first();
            if ($r !== null && $r->niveauSurModule('M1') === 'C') {
                return $role;
            }
        }

        $this->fail('Aucun rôle du référentiel ne porte M1 = C.');
    }

    // =====================================================================

    /**
     * La fiche COMPLÈTE du maître depuis PA-163 (01/09/2026) : aux cinq
     * champs d'origine s'ajoutent canal, remise (type + valeur) et mode de
     * paiement. Les lignes de services ne figurent pas ici : leurs liaisons
     * (`rLignes.N.…`) n'apparaissent qu'une fois un service coché — une
     * modale fraîche n'en rend aucune — et les cases de la grille passent
     * par `wire:click`, invisible à ce contrôle (limite écrite dans son
     * en-tête).
     */
    #[Test]
    public function la_modale_rend_exactement_les_champs_de_la_fiche_du_maitre(): void
    {
        $this->assertLaModaleSOuvreEtRendExactementSesChamps(
            $this->utilisateur($this->roleQuiEcritSurM1()),
            Reservations::class,
            'ouvrirCreationReservation',
            [
                'rClientId', 'rUniteId', 'rDateArrivee', 'rDateDepart', 'rAcompte',
                'rCanalId', 'rRemiseType', 'rRemiseValeur', 'rModePaiement',
            ],
        );
    }

    /**
     * La fiche complète (PA-163) : canal, ligne de service, remise et mode
     * de paiement atteignent la base — et la ligne FIGE prix et libellé.
     *
     * ## Mutation vérifiée (01/09/2026)
     *
     * `remplacerLignes()` privé de son `bcmul` (montant posé à `0`) rend ce
     * cas rouge sur le montant de la ligne ; relire le prix du catalogue à
     * l'affichage plutôt que la colonne figée le rend rouge sur l'assertion
     * post-changement de prix.
     */
    #[Test]
    public function la_fiche_complete_enregistre_canal_ligne_remise_et_fige_les_prix(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));

        $canal = \App\Domain\Hebergement\Models\CanalReservation::create(['nom' => 'Booking.com', 'actif' => true]);
        $circuit = \App\Domain\Tourisme\Models\Circuit::create([
            'nom' => 'Chutes de Kota', 'theme' => 'Nature', 'zone' => 'Atacora',
            'duree' => '1 jour', 'prix' => '15000.00', 'capacite_max' => 12,
        ]);

        Livewire::test(Reservations::class)
            ->call('ouvrirCreationReservation')
            ->set('rClientId', $this->client->id)
            ->set('rUniteId', $this->unite->id)
            ->set('rDateArrivee', '2026-09-10')
            ->set('rDateDepart', '2026-09-12')
            ->set('rAcompte', '10000')
            ->set('rCanalId', $canal->id)
            ->call('basculerServiceFiche', 'tourisme')
            ->set('rLignes.0.source_id', $circuit->id)
            ->set('rLignes.0.quantite', '2')
            ->set('rRemiseType', 'pourcentage')
            ->set('rRemiseValeur', '10')
            ->set('rModePaiement', 'mobile_money')
            ->call('enregistrerReservation')
            ->assertHasNoErrors();

        $reservation = Reservation::query()->with('lignes')->firstOrFail();

        $this->assertSame($canal->id, $reservation->canal_id);
        $this->assertSame('mobile_money', $reservation->mode_paiement);
        $this->assertSame('pourcentage', $reservation->remise_type);
        // Le tarif est FIGÉ depuis le parc, jamais laissé nul.
        $this->assertSame(0, bccomp((string) $reservation->tarif_nuit, '18000', 2));

        $ligne = $reservation->lignes->sole();
        $this->assertSame('tourisme', $ligne->service);
        $this->assertSame($circuit->id, $ligne->source_id);
        $this->assertSame('Chutes de Kota', $ligne->libelle);
        $this->assertSame(0, bccomp((string) $ligne->montant, '30000', 2)); // 2 × 15 000

        // Récapitulatif : (2 × 18 000 + 30 000) − 10 % = 59 400 ; − 10 000
        // d'acompte = 49 400. La MÊME formule que le client Flutter (PA-111).
        $this->assertSame(0, bccomp((string) $reservation->resteAPayer(), '49400.00', 2));

        // PRIX FIGÉ : un changement de catalogue ne réécrit pas la fiche.
        $circuit->update(['prix' => '99000.00']);
        $this->assertSame(0, bccomp((string) $ligne->fresh()->prix_unitaire, '15000', 2));
    }

    #[Test]
    public function la_modale_ne_s_ouvre_pas_pour_un_role_en_lecture_et_le_refus_est_trace(): void
    {
        // `comptable` porte `M1 = 'L'` : la lecture d'un module ne donne
        // aucun droit d'y écrire.
        $comptable = $this->utilisateur('comptable');
        $this->assertSame('L', $comptable->niveauSurModule('M1'));

        $this->assertLOuvertureEstRefuseeEtTracee(
            $comptable,
            Reservations::class,
            'ouvrirCreationReservation',
            'M1',
        );
    }

    #[Test]
    public function une_reservation_est_reellement_creee_par_le_service(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));

        Livewire::test(Reservations::class)
            ->call('ouvrirCreationReservation')
            ->set('rClientId', $this->client->id)
            ->set('rUniteId', $this->unite->id)
            ->set('rDateArrivee', '2026-09-10')
            ->set('rDateDepart', '2026-09-12')
            ->set('rAcompte', '10000')
            ->call('enregistrerReservation')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $reservation = Reservation::query()->firstOrFail();
        $this->assertSame($this->client->id, $reservation->client_id);
        $this->assertSame($this->unite->id, $reservation->unite_id);
        $this->assertSame('2026-09-10', $reservation->date_arrivee->toDateString());
        $this->assertSame('2026-09-12', $reservation->date_depart->toDateString());
        $this->assertSame(0, bccomp((string) $reservation->acompte, '10000', 2));
        // Le statut vient du DÉFAUT du schéma — l'écran n'en décide pas.
        $this->assertSame('en_attente', $reservation->statut);
        // UUID applicatif, convention du projet.
        $this->assertMatchesRegularExpression('/^[0-9a-f-]{36}$/', $reservation->id);
    }

    #[Test]
    public function un_acompte_laisse_vide_vaut_zero_et_non_une_chaine_vide(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));

        Livewire::test(Reservations::class)
            ->call('ouvrirCreationReservation')
            ->set('rClientId', $this->client->id)
            ->set('rUniteId', $this->unite->id)
            ->set('rDateArrivee', '2026-09-10')
            ->set('rDateDepart', '2026-09-12')
            ->call('enregistrerReservation')
            ->assertHasNoErrors();

        $this->assertSame(0, bccomp((string) Reservation::query()->firstOrFail()->acompte, '0', 2));
    }

    #[Test]
    public function rg01_un_chevauchement_est_refuse_et_rendu_au_champ_unite(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));

        app(ReservationService::class)->creer([
            'id' => (string) Str::uuid(),
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-10',
            'date_depart' => '2026-09-14',
        ]);

        // Chevauchement franc sur la même unité : refusé par le Service SOUS
        // VERROU, et le refus arrive comme une erreur de validation lisible —
        // le même message de langue que l'API — pas comme une exception nue.
        Livewire::test(Reservations::class)
            ->call('ouvrirCreationReservation')
            ->set('rClientId', $this->client->id)
            ->set('rUniteId', $this->unite->id)
            ->set('rDateArrivee', '2026-09-12')
            ->set('rDateDepart', '2026-09-16')
            ->call('enregistrerReservation')
            ->assertHasErrors('rUniteId')
            // La modale RESTE ouverte, la saisie intacte : fermer sur un refus
            // ferait perdre la fiche et retaper les dates.
            ->assertSet('etatFormulaire', 'reservation');

        $this->assertSame(1, Reservation::count(), 'Le chevauchement a tout de même écrit une ligne : RG-01 est contourné.');
    }

    #[Test]
    public function la_modification_s_exclut_elle_meme_du_controle_de_chevauchement(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));

        $reservation = app(ReservationService::class)->creer([
            'id' => (string) Str::uuid(),
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-10',
            'date_depart' => '2026-09-14',
        ]);

        // PA-115 : corriger l'acompte sans bouger les dates. Sans
        // l'auto-exclusion, la réservation serait refusée PAR ELLE-MÊME et
        // l'édition ne pourrait jamais rien enregistrer.
        Livewire::test(Reservations::class)
            ->call('ouvrirModificationReservation', $reservation->id)
            ->assertSet('rClientId', $this->client->id)
            ->assertSet('rDateArrivee', '2026-09-10')
            ->set('rAcompte', '5000')
            ->call('enregistrerReservation')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $reservation->refresh();
        $this->assertSame(0, bccomp((string) $reservation->acompte, '5000', 2));
        $this->assertSame('2026-09-10', $reservation->date_arrivee->toDateString());
        $this->assertSame(1, Reservation::count(), 'La modification a créé une seconde ligne au lieu de modifier.');
    }

    #[Test]
    public function une_reservation_annulee_ne_se_modifie_pas(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));

        $reservation = app(ReservationService::class)->creer([
            'id' => (string) Str::uuid(),
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-10',
            'date_depart' => '2026-09-14',
        ]);
        app(ReservationService::class)->annuler($reservation);

        // PA-115 côté serveur : la rouvrir la ferait revivre sans que son
        // statut change.
        Livewire::test(Reservations::class)
            ->call('ouvrirModificationReservation', $reservation->id)
            ->assertStatus(422);
    }

    #[Test]
    public function rg02_l_annulation_libere_l_unite_dans_le_calendrier(): void
    {
        // `administrateur` porte M1 = C ET ANNULATIONS = C (EF-M1-06) —
        // `roleQuiEcritSurM1()` ne garantit que le premier.
        $this->actingAs($this->utilisateur('administrateur'));

        $reservation = app(ReservationService::class)->creer([
            'id' => (string) Str::uuid(),
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-10',
            'date_depart' => '2026-09-14',
            // Nécessaire depuis EF-M1-06 : `montantTotal()` refuse le calcul
            // de commission sans tarif figé — sans lui l'annulation serait
            // rejetée, pas seulement dépouillée de ses conditions.
            'tarif_nuit' => '18000',
        ]);

        Livewire::test(Reservations::class)
            ->call('confirmerAnnulation', $reservation->id)
            ->set('aTaux', '50')
            ->call('annulerReservation', $reservation->id)
            ->assertHasNoErrors();

        $this->assertSame('annulee', $reservation->refresh()->statut);
        $this->assertSame(1, Reservation::count(), 'L annulation a supprimé la ligne : RG-02 interdit tout effacement.');

        // La preuve que l'unité est LIBÉRÉE : les mêmes dates redeviennent
        // réservables — c'est le calendrier réel qui le dit, pas le statut.
        Livewire::test(Reservations::class)
            ->call('ouvrirCreationReservation')
            ->set('rClientId', $this->client->id)
            ->set('rUniteId', $this->unite->id)
            ->set('rDateArrivee', '2026-09-10')
            ->set('rDateDepart', '2026-09-14')
            ->call('enregistrerReservation')
            ->assertHasNoErrors();

        $this->assertSame(2, Reservation::count());
    }

    /**
     * PA-113 — LE PAPIER REMIS N EST PAS UNE FACTURE, ET LE PDF LUI-MEME DOIT
     * LE DIRE.
     *
     * Le maitre titre son document « Facture ». Il n a pourtant ni numero, ni
     * IFU, ni cachet. Au Benin une facture est normalisee MECeF : imprimer
     * « FACTURE » sur ce papier et le remettre a un client, ce serait produire
     * un FAUX DOCUMENT FISCAL — la version papier de PA-61.
     *
     * ⚠ CE CAS PORTE SUR LE DOCUMENT, PAS SUR L ECRAN QUI L APPELLE. Verifier
     * la modale ne prouve rien : c est le papier qui sort de l imprimante et
     * qui passe la main au client. Le rendu de la vue est donc relu
     * directement, ET le flux reellement produit est mesure — un PDF vide ou
     * tronque satisferait n importe quelle assertion de texte.
     *
     * La modale, elle, GARDE les mots du maitre (« Réservation enregistrée »,
     * « Imprimer la facture ») : c est le texte que le client a valide des
     * yeux, et il ne quitte pas l ecran.
     *
     * ⚠ `resources/views/pdf/facture.blade.php` n est PAS le document de cet
     * ecran, et ne l est plus depuis le 31/08/2026 : plus aucun
     * `Pdf::loadView('pdf.facture'` n existe dans le depot. Le vrai document
     * fiscal est `pdf/facture-mecef.blade.php` (M2), avec son filigrane de
     * demonstration derive du NUMERO. Ce sont deux pieces differentes, et il
     * ne faut pas les faire converger.
     *
     * Mutations executees le 31/08/2026, annulees ensuite :
     *  - le titre du document remis en « FACTURE » : ce cas a rougi sur les
     *    deux assertions de titre a la fois ;
     *  - la mention « ne vaut pas facture » deplacee du corps vers le pied de
     *    page : rouge sur la position, pas sur la presence — c est le point,
     *    une mention qu on lit apres avoir signe ne protege personne.
     */
    #[Test]
    public function le_papier_remis_a_la_prise_de_reservation_n_est_pas_une_facture(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));

        $reservation = app(ReservationService::class)->creer([
            'id' => (string) Str::uuid(),
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-10',
            'date_depart' => '2026-09-12',
        ]);

        // 1. LE CONTENU du document, lu dans le rendu de la vue elle-meme.
        // L'en-tête est celui que l'écran passe : RG-19, par le SEUL
        // `ReportHeaderService` (PA-192, 11/09/2026).
        $html = view('pdf.hebergement', [
            'document' => 'confirmation',
            'reservation' => $reservation->load(['client', 'unite.categorie']),
            'etat' => ['cle' => 'a_venir', 'libelle' => 'À venir', 'classe' => ''],
            'entete' => app(ReportHeaderService::class)->genererEnTete(
                __('hebergement_pwa.reservations.confirmation_titre'),
                'Du 10/09/2026 au 12/09/2026',
                null,
            ),
        ])->render();

        $this->assertStringContainsString('CONFIRMATION DE RÉSERVATION', $html);

        // Aucune occurrence de « FACTURE » comme titre : le mot n apparait que
        // dans la mention qui dit precisement que ce papier n en est pas une.
        $this->assertStringNotContainsString('>FACTURE<', $html);
        $this->assertSame(
            0,
            substr_count($html, 'FACTURE</'),
            'Le document porte « FACTURE » comme titre : ce serait un faux document fiscal (PA-113).',
        );

        // 2. LA MENTION EST AU CORPS, pas en pied de page ou personne ne la
        //    lit. Mesure : elle apparait APRES le bloc titre de l en-tete, et
        //    le document n a AUCUN pied — depuis le 11/09/2026 (PA-192), le
        //    pied de rapport (mention de cabinet, pagination) est reserve aux
        //    exports, et n a rien a faire sur un papier remis a un client.
        $mention = strpos($html, 'ne vaut pas facture');
        $blocTitre = strpos($html, 'class="er-bloc-titre"');
        $this->assertNotFalse($mention, 'La mention « ne vaut pas facture » est absente du document.');
        $this->assertNotFalse($blocTitre, 'Le document a perdu son en-tete RG-19 : la mesure de position ne veut plus rien dire.');
        $this->assertGreaterThan(
            $blocTitre,
            $mention,
            'La mention precede l en-tete : elle doit etre au CORPS, la ou on la lit avant de remettre le papier.',
        );
        // Le BALISAGE, pas la classe : les styles partages la citent en tete.
        $this->assertStringNotContainsString('class="er-pied"', $html, 'Un papier client ne porte pas le pied de rapport.');

        // 2 bis. AUCUN VISA : « Visa Ordonnateur » sur un papier remis au
        //    client ferait croire a une piece d ordonnancement interne. La
        //    zone de signatures de la Directive §6 est reservee aux exports.
        $this->assertStringNotContainsString('class="er-signatures"', $html);
        $this->assertStringNotContainsString(__('rapports.signatures.visa_ordonnateur'), $html);

        // 3. Aucun identifiant fiscal invente : IFU et RCCM sont conditionnels
        //    et vides sur ce serveur — en imprimer un exemple serait un faux.
        $this->assertStringNotContainsString('IFU', $html);
        $this->assertStringNotContainsString('RCCM', $html);

        // 4. LE FLUX REEL : un PDF vide ou tronque satisferait tout ce qui
        //    precede. Le document est donc reellement produit et mesure.
        $telechargement = Livewire::test(Reservations::class)
            ->call('imprimerConfirmation', $reservation->id)
            ->assertFileDownloaded()
            ->effects['download'];

        $octets = (string) base64_decode((string) $telechargement['content'], true);

        $this->assertStringStartsWith('%PDF-', $octets, 'Le telechargement n est pas un PDF.');
        $this->assertGreaterThan(3000, strlen($octets), 'Le PDF produit est trop court pour porter le document.');
        $this->assertStringContainsString(
            'confirmation_reservation_',
            (string) $telechargement['name'],
            'Le fichier remis s appelle « facture » : le nom du fichier est lu, lui aussi.',
        );

        // 5. AUCUN NUMERO N EST ALLOUE. Cote serveur, l equivalent de
        //    `numeroSuivant()` — qui alloue ET persiste, ce n est jamais une
        //    lecture (PA-101) — serait une ligne dans `factures`. Il n y en a
        //    aucune : imprimer ce papier ne consomme rien.
        $this->assertSame(0, DB::table('factures')->count(), 'Imprimer la confirmation a cree une facture.');
    }

    #[Test]
    public function un_role_sans_droit_n_ecrit_rien_et_le_refus_est_trace(): void
    {
        $comptable = $this->utilisateur('comptable');
        $this->actingAs($comptable);

        Livewire::test(Reservations::class)
            ->call('enregistrerReservation')
            ->assertForbidden();

        $this->assertSame(0, Reservation::count());
        $this->assertDatabaseHas('journal_securite', [
            'type_evenement' => 'acces_refuse_rbac',
            'utilisateur_id' => $comptable->id,
            'module_concerne' => 'M1',
        ]);

        // Et l'annulation aussi : lecture n'est pas écriture.
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));
        $reservation = app(ReservationService::class)->creer([
            'id' => (string) Str::uuid(),
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-10',
            'date_depart' => '2026-09-12',
        ]);
        $this->actingAs($comptable);

        Livewire::test(Reservations::class)
            ->call('annulerReservation', $reservation->id)
            ->assertForbidden();

        $this->assertSame('en_attente', $reservation->refresh()->statut);
    }

    /**
     * ⚠ L'assertion porte sur le GESTE (`wire:click="ouvrirCreationReservation"`),
     * pas sur le LIBELLÉ : le panneau global « Accès rapides » (Alt+A,
     * `AccesRapide::RACCOURCIS_UNIVERSELS`), qui vit sur CHAQUE page et
     * navigue plutôt qu'il n'écrit, porte le même libellé « Nouvelle
     * réservation » en lien `<a href>` vers cette page — un rôle en lecture
     * peut légitimement s'y rendre, il y trouvera un écran qui refuse
     * l'écriture lui-même. Chercher le seul libellé ferait échouer ce test
     * sur une coïncidence de texte entre deux fonctionnalités distinctes.
     */
    #[Test]
    public function les_boutons_d_ecriture_sont_masques_pour_un_role_en_lecture(): void
    {
        // 1er niveau du RBAC — il ne protège rien (les cas ci-dessus le
        // prouvent côté serveur), mais un bouton offert puis refusé ferait
        // perdre la saisie.
        $this->actingAs($this->utilisateur('comptable'));
        $htmlLecture = (string) Livewire::test(Reservations::class)->html();
        $this->assertStringNotContainsString('wire:click="ouvrirCreationReservation"', $htmlLecture);

        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM1()));
        $htmlEcriture = (string) Livewire::test(Reservations::class)->html();
        $this->assertStringContainsString('wire:click="ouvrirCreationReservation"', $htmlEcriture);

        $this->assertSame(0, JournalSecurite::count(), 'Le simple rendu de la page a tracé un refus.');
    }

    // =========================================================================
    // EF-M1-06 — LE trou RBAC révélé par l'audit préalable de cette tâche :
    // avant `ANNULATIONS`, n'importe quel rôle avec M1 = C pouvait annuler ET
    // décider seul d'un remboursement en numéraire sorti de caisse.
    // =========================================================================

    /**
     * `receptionniste` porte M1 = C (créer/modifier une réservation) mais
     * ANNULATIONS = L (`RolePermissionSeeder::MATRICE`) : il ne peut PAS
     * exécuter une annulation avec remboursement, geste qui engage la caisse
     * et reste un arbitrage de direction. Refuser sur `assertHasNoErrors()`
     * seul ne verrait rien — `assertForbidden()` (403 réel) est la seule
     * preuve, comme le rappelle la note d'`AchatsCyclePwaTest` sur ce piège.
     */
    #[Test]
    public function un_role_avec_m1_c_mais_sans_le_droit_annulations_ne_peut_pas_annuler(): void
    {
        $receptionniste = $this->utilisateur('receptionniste');
        $role = Role::where('libelle', 'receptionniste')->firstOrFail();
        $this->assertSame('C', $role->niveauSurModule('M1'), 'Précondition du test : receptionniste doit écrire sur M1.');
        $this->assertSame('L', $role->niveauSurModule('ANNULATIONS'), 'Précondition du test : receptionniste ne doit PAS pouvoir annuler.');

        $this->actingAs($this->utilisateur('administrateur'));
        $reservation = app(ReservationService::class)->creer([
            'id' => (string) Str::uuid(),
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-10',
            'date_depart' => '2026-09-12',
            'tarif_nuit' => '18000',
        ]);

        $this->actingAs($receptionniste);

        // L'OUVERTURE de la modale est déjà refusée — présenter un
        // formulaire à quelqu'un qui ne pourra pas le soumettre lui ferait
        // perdre sa saisie sans rien lui apprendre.
        Livewire::test(Reservations::class)
            ->call('confirmerAnnulation', $reservation->id)
            ->assertForbidden();

        $this->assertDatabaseHas('journal_securite', [
            'type_evenement' => 'acces_refuse_rbac',
            'utilisateur_id' => $receptionniste->id,
            'module_concerne' => 'ANNULATIONS',
        ]);

        // Et l'ACTION elle-même, si elle était invoquée directement (état de
        // modale falsifié depuis le navigateur — voir la note de
        // `FormulaireModal` : l'ouverture ne protège rien).
        Livewire::test(Reservations::class)
            ->set('reservationAAnnuler', $reservation->id)
            ->set('aTaux', '50')
            ->set('aModeRemboursement', 'montant')
            ->set('aRembourseValeur', '0')
            ->call('annulerReservation', $reservation->id)
            ->assertForbidden();

        $this->assertSame(
            'en_attente',
            $reservation->refresh()->statut,
            'La réservation ne doit pas avoir été annulée par un rôle sans le droit ANNULATIONS.',
        );

        // Le bouton « Annuler » de la grille est MASQUÉ pour ce rôle — 1er
        // niveau du RBAC, qui ne protège rien mais évite d'offrir un bouton
        // qui refusera toujours (Article 6).
        $html = (string) Livewire::test(Reservations::class)->html();
        $this->assertStringNotContainsString('wire:click="confirmerAnnulation(', $html);
    }

    /**
     * `administrateur` et `gerant` portent `ANNULATIONS = C` : le geste
     * complet — ouverture, saisie, exécution — fonctionne réellement de bout
     * en bout, taux et remboursement compris.
     */
    #[Test]
    public function un_role_avec_le_droit_annulations_peut_annuler_avec_remboursement(): void
    {
        // Le remboursement numéraire pose une VRAIE écriture comptable
        // (règle des sept) : le référentiel (journaux, comptes, exercice)
        // doit exister, comme dans les tests dédiés à la comptabilisation.
        $this->seed(\Database\Seeders\ComptabiliteReferentielSeeder::class);

        $this->actingAs($this->utilisateur('administrateur'));

        $reservation = app(ReservationService::class)->creer([
            'id' => (string) Str::uuid(),
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-10',
            'date_depart' => '2026-09-12',
            'tarif_nuit' => '18000',
            'acompte' => '10000',
        ]);

        Livewire::test(Reservations::class)
            ->call('confirmerAnnulation', $reservation->id)
            ->assertSet('reservationAAnnuler', $reservation->id)
            // Pré-rempli à 50 % (référence client, §4.4/§6.3) tant que
            // l'Administrateur n'a rien configuré au registre des paramètres.
            ->assertSet('aTaux', '50.00')
            ->set('aModeRemboursement', 'montant')
            ->set('aRembourseValeur', '5000')
            ->call('annulerReservation', $reservation->id)
            ->assertHasNoErrors()
            ->assertOk();

        $reservation->refresh();
        $this->assertSame('annulee', $reservation->statut);
        $this->assertSame(0, bccomp((string) $reservation->montant_rembourse_annulation, '5000.00', 2));
        $this->assertNotNull($reservation->ecriture_remboursement_id);
    }
}

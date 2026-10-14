<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Crm\Models\Client;
use App\Domain\Crm\Models\RelanceClient;
use App\Domain\Hebergement\Models\Sejour;
use App\Models\User;
use App\Pwa\Livewire\Transverse\AlertesOuvertureModales;
use App\Pwa\Support\AlertesOuverture;
use App\Shared\Parametres\Services\EnregistrerParametreService;
use App\Shared\Parametres\Services\OptionsSystemeService;
use Database\Seeders\DemonstrationSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Les DEUX modales d'ouverture de session (maitre : alertes-ouverture.js,
 * verifiees manquantes par le PO le 02/09/2026).
 *
 * Ce que ce fichier prouve, cas par cas :
 *  - le drapeau est pose PAR LA CONNEXION et consomme par la modale — une
 *    fois par connexion, jamais par page ;
 *  - le check-out inline passe par le MEME service que l'ecran Hebergement
 *    (unite en nettoyage, jamais libre) ;
 *  - la relance est TRACEE (RelanceClient reel, montant = reste du, jamais
 *    une saisie), et REFUSEE quand la derniere relance a moins de 14 jours ;
 *  - la bascule du maitre ferme tout.
 *
 * Le jeu de demonstration (`DemonstrationSeeder`) fournit un stock sous seuil et
 * une creance reelle — les memes donnees que les gardes de conformite.
 */
final class AlertesOuvertureModalesTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(DemonstrationSeeder::class);
    }

    private function admin(): User
    {
        return User::query()->where('login', 'admin')->firstOrFail();
    }

    /**
     * `Connexion` ecrit la cle en LITTERAL (exige par
     * `SessionSansDonneeMetierTest`) ; ce cas garantit que la constante du
     * composant et ce litteral ne divergeront jamais en silence.
     */
    #[Test]
    public function la_constante_du_drapeau_vaut_le_litteral_ecrit_par_la_connexion(): void
    {
        $this->assertSame('alertes_ouverture_en_attente', AlertesOuvertureModales::CLE_SESSION);

        $sourceConnexion = (string) file_get_contents(app_path('Pwa/Livewire/Connexion.php'));
        $this->assertStringContainsString(
            "session()->put('alertes_ouverture_en_attente', true)",
            $sourceConnexion,
            'La connexion doit poser le drapeau, en litteral.',
        );
    }

    #[Test]
    public function le_drapeau_est_pose_a_la_connexion_et_consomme_une_fois(): void
    {
        $this->actingAs($this->admin());
        session()->put(AlertesOuvertureModales::CLE_SESSION, true);

        // Le jeu de demonstration porte des articles sous seuil : la
        // premiere etape (stock) se rend.
        Livewire::test(AlertesOuvertureModales::class)
            ->assertSee(__('pwa.alertes_ouverture.titre_stock'));

        // « J'ai pris connaissance » sur la DERNIERE etape consomme le
        // drapeau : la page suivante ne montre plus rien.
        $composant = Livewire::test(AlertesOuvertureModales::class);
        $etapes = 0;
        while (session()->has(AlertesOuvertureModales::CLE_SESSION) && $etapes < 5) {
            $composant->call('avancer');
            $etapes++;
        }

        $this->assertFalse(session()->has(AlertesOuvertureModales::CLE_SESSION));

        Livewire::test(AlertesOuvertureModales::class)
            ->assertDontSee(__('pwa.alertes_ouverture.titre_stock'));
    }

    #[Test]
    public function le_checkout_inline_passe_l_unite_en_nettoyage(): void
    {
        $this->actingAs($this->admin());
        session()->put(AlertesOuvertureModales::CLE_SESSION, true);

        // Un sejour en cours dont le depart est DEPASSE. L'amorcage ne
        // laisse pas forcement un sejour ouvert : on fait le check-in par le
        // MEME service que l'ecran (jamais un insert direct), puis on
        // vieillit le depart.
        $sejour = Sejour::query()->whereNull('date_checkout_reel')->whereNotNull('date_checkin_reel')->first();

        if ($sejour === null) {
            // `Reservation` ne declare pas de relation vers `sejours` : on
            // exclut par sous-requete, jamais par une relation inventee.
            $reservation = \App\Domain\Hebergement\Models\Reservation::query()
                ->whereNot('statut', 'annulee')
                ->whereNotIn('id', Sejour::query()->select('reservation_id'))
                ->firstOrFail();
            $sejour = app(\App\Domain\Hebergement\Services\SejourService::class)->checkin($reservation);
        }

        // Vieillir le SEJOUR ENTIER : la contrainte CHECK exige
        // date_depart > date_arrivee, on recule donc les deux bornes.
        $sejour->reservation->forceFill([
            'date_arrivee' => now()->subDays(3)->toDateString(),
            'date_depart' => now()->subDay()->toDateString(),
        ])->save();

        $departs = AlertesOuverture::departsAEcheance();
        $this->assertNotEmpty($departs, 'Le collecteur doit voir le depart depasse.');
        $this->assertTrue($departs[0]['critique'], 'Un depart depasse est critique (rouge).');

        Livewire::test(AlertesOuvertureModales::class)
            ->call('effectuerCheckOutOuverture', $sejour->id)
            ->assertHasNoErrors();

        $this->assertNotNull($sejour->fresh()->date_checkout_reel);
        $this->assertSame(
            'nettoyage',
            (string) $sejour->reservation->fresh()->unite->fresh()->statut,
            'Le check-out passe l unite en NETTOYAGE, jamais directement libre (EF-M1-04).',
        );
    }

    #[Test]
    public function la_relance_est_tracee_avec_le_reste_du_reel_puis_refusee_sous_quatorze_jours(): void
    {
        $this->actingAs($this->admin());
        session()->put(AlertesOuvertureModales::CLE_SESSION, true);

        // Vieillir la facture impayee de l'amorcage au-dela de 30 jours.
        \Illuminate\Support\Facades\DB::table('factures')
            ->update(['date_emission' => now()->subDays(45)->toDateString()]);

        $creances = AlertesOuverture::creancesModale();
        $this->assertNotEmpty($creances, 'Le collecteur doit voir la creance de 45 jours.');
        $cible = $creances[0];
        $this->assertTrue($cible['relance_requise'], 'Jamais relancee : elle est relancable.');

        Livewire::test(AlertesOuvertureModales::class)
            ->set('canalRelance', 'whatsapp')
            ->call('tracerRelanceOuverture', $cible['client_id'])
            ->assertHasNoErrors();

        $relance = RelanceClient::query()->where('client_id', $cible['client_id'])->firstOrFail();
        $this->assertSame('whatsapp', $relance->canal);
        $this->assertSame(
            0,
            bccomp((string) $relance->montant_reclame, $cible['reste'], 2),
            'Le montant reclame est le reste du REEL, jamais une saisie.',
        );

        // Relancee a l'instant : la regle des 14 jours la retire des
        // relancables — le geste est refuse, la ligne reste listee.
        $apres = collect(AlertesOuverture::creancesModale())->firstWhere('client_id', $cible['client_id']);
        $this->assertNotNull($apres, 'La creance reste LISTEE apres relance.');
        $this->assertFalse($apres['relance_requise'], 'Relance de moins de 14 jours : plus relancable.');

        Livewire::test(AlertesOuvertureModales::class)
            ->call('tracerRelanceOuverture', $cible['client_id'])
            ->assertHasErrors('alerte_ouverture');
    }

    #[Test]
    public function la_bascule_fermee_ne_rend_rien_du_tout(): void
    {
        $admin = $this->admin();
        $this->actingAs($admin);
        session()->put(AlertesOuvertureModales::CLE_SESSION, true);

        app(EnregistrerParametreService::class)->enregistrer(
            [OptionsSystemeService::CLE_ALERTES_OUVERTURE => 'false'],
        );

        Livewire::test(AlertesOuvertureModales::class)
            ->assertDontSee(__('pwa.alertes_ouverture.titre_stock'))
            ->assertDontSee(__('pwa.alertes_ouverture.titre_operations'));
    }

    #[Test]
    public function un_role_sans_module_ne_voit_pas_le_bloc_et_n_ecrit_pas(): void
    {
        // La cuisine : M6 = 'C' (elle VOIT le stock), M1 = '-' et M3 = 'L'
        // — elle ne voit ni les departs ni ne peut relancer.
        $cuisine = User::query()->where('login', 'cuisine')->firstOrFail();
        $this->actingAs($cuisine);
        session()->put(AlertesOuvertureModales::CLE_SESSION, true);

        $client = Client::query()->firstOrFail();

        Livewire::test(AlertesOuvertureModales::class)
            ->call('tracerRelanceOuverture', $client->id)
            ->assertStatus(403);
    }
}

<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\ExerciceComptableService;
use App\Domain\Comptabilite\Services\PlanComptableService;
use App\Domain\Depenses\Models\Depense;
use App\Models\User;
use App\Pwa\Livewire\Achats\Achats;
use App\Pwa\Livewire\Comptabilite\Hub;
use App\Pwa\Livewire\Depenses\Depenses;
use App\Pwa\Livewire\Facturation\Facturation;
use App\Pwa\Livewire\Rh\Paie;
use App\Pwa\Livewire\Transverse\SelecteurExercice;
use App\Pwa\Support\ExerciceConsulte;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Le SÉLECTEUR D'EXERCICE global (`docs/SPEC_SELECTEUR_EXERCICE.md`,
 * décisions du PO du 20/10/2026) : un choix, en session, suivi par la
 * comptabilité, le tableau de bord, les états, les dépenses, les factures,
 * les achats et la paie — affiché pour tout rôle qui ouvre ces écrans — et
 * qui ne déplace JAMAIS une écriture (R4).
 */
final class SelecteurExerciceTest extends TestCase
{
    use RefreshDatabase;

    private ExerciceComptable $n;

    private ExerciceComptable $n1;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2027-02-10 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->n1 = ExerciceComptable::query()->where('annee', 2027)->firstOrFail();
        $this->n = app(ExerciceComptableService::class)->ouvrir(2026);
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role.'.'.Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    private function facture(string $date, string $ttc): void
    {
        $client = DB::table('clients')->value('id') ?? (string) Str::uuid();
        if (! DB::table('clients')->where('id', $client)->exists()) {
            DB::table('clients')->insert([
                'id' => $client, 'nom' => 'Client', 'telephone' => '+229 01 00 00 00 01',
                'type_client' => 'particulier', 'created_at' => now(), 'updated_at' => now(),
            ]);
        }
        DB::table('factures')->insert([
            'id' => (string) Str::uuid(), 'client_id' => $client, 'numero_mecef' => 'F-'.$date,
            'date_emission' => $date, 'montant_ht' => $ttc, 'montant_tva' => '0', 'montant_ttc' => $ttc,
            'statut' => 'certifiee', 'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    #[Test]
    public function par_defaut_l_exercice_ouvert_le_plus_recent_puis_le_choix_et_le_retour(): void
    {
        $this->actingAs($this->utilisateur('comptable'));
        $this->assertSame($this->n1->id, ExerciceConsulte::exercice()?->id);
        $this->assertFalse(ExerciceConsulte::estAutreQueDefaut());

        Livewire::test(SelecteurExercice::class)
            ->set('exerciceId', $this->n->id)
            ->assertRedirect();
        $this->assertSame($this->n->id, ExerciceConsulte::exercice()?->id);
        $this->assertTrue(ExerciceConsulte::estAutreQueDefaut());
        // Consulter 2026 en 2027 : la référence est le dernier jour de 2026.
        $this->assertSame('2026-12-31', ExerciceConsulte::reference()->toDateString());

        // Sur un écran qui le suit, la pastille et « Revenir à 2027 ».
        $this->get(route('pwa.facturation'))->assertOk()
            ->assertSee(__('pwa.coquille.exercice_pastille', ['annee' => 2026, 'statut' => 'ouvert']))
            ->assertSee(__('pwa.coquille.exercice_revenir', ['annee' => 2027]));

        Livewire::test(SelecteurExercice::class)->call('revenir');
        $this->assertSame($this->n1->id, ExerciceConsulte::exercice()?->id);

        // Un identifiant inconnu ne change rien.
        ExerciceConsulte::choisir('inconnu');
        $this->assertSame($this->n1->id, ExerciceConsulte::exercice()?->id);
    }

    #[Test]
    public function il_s_affiche_sur_les_ecrans_qui_le_suivent_pour_tout_role_qui_les_ouvre(): void
    {
        // Le réceptionniste n'a pas M10 : il voit le sélecteur sur les factures.
        $this->actingAs($this->utilisateur('receptionniste'));
        $this->get(route('pwa.facturation'))->assertOk()->assertSee('id="choix-exercice"', false);
        // … mais pas sur un écran du jour.
        $this->get(route('pwa.hebergement'))->assertOk()->assertDontSee('id="choix-exercice"', false);

        $this->actingAs($this->utilisateur('comptable'));
        foreach (['pwa.comptabilite.hub', 'pwa.depenses', 'pwa.paie', 'pwa.achats.liste', 'pwa.accueil', 'pwa.etats.studio'] as $route) {
            $this->get(route($route))->assertOk()->assertSee('id="choix-exercice"', false);
        }
    }

    #[Test]
    public function la_comptabilite_les_factures_et_les_depenses_suivent_l_exercice_choisi(): void
    {
        $this->actingAs($this->utilisateur('comptable'));
        $this->facture('2026-06-01', '11000.00');
        $this->facture('2027-01-20', '22000.00');

        $this->assertSame(1, Livewire::test(Facturation::class)->viewData('factures')->total());
        Livewire::test(Facturation::class)->assertSee('F-2027-01-20')->assertDontSee('F-2026-06-01');

        ExerciceConsulte::choisir($this->n->id);
        Livewire::test(Facturation::class)->assertSee('F-2026-06-01')->assertDontSee('F-2027-01-20');

        // Le hub, sans `?exercice=`, consulte 2026 ; son sélecteur le montre.
        Livewire::test(Hub::class, ['onglet' => 'journal'])->assertSet('exerciceId', $this->n->id);

        // Un `?exercice=` explicite (lien N+1 du hub) devient le choix global.
        Livewire::withQueryParams(['exercice' => $this->n1->id])->test(Hub::class, ['onglet' => 'journal']);
        $this->assertSame($this->n1->id, ExerciceConsulte::exercice()?->id);

        // Les dépenses : le filtre dit l'exercice, et « du » hors exercice y revient.
        ExerciceConsulte::choisir($this->n->id);
        $this->assertSame(['2026-01-01', '2026-12-31'], ExerciceConsulte::datesDansLExercice('', ''));
        $this->assertSame(['2026-01-01', '2026-03-31'], ExerciceConsulte::datesDansLExercice('2025-05-01', '2026-03-31'));
        Livewire::test(Depenses::class)->assertOk();
        Livewire::test(Achats::class)->assertOk();
    }

    #[Test]
    public function la_paie_propose_le_dernier_mois_de_l_exercice_passe(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        Livewire::test(Paie::class)->assertSet('periode', '2027-02');

        ExerciceConsulte::choisir($this->n->id);
        Livewire::test(Paie::class)->assertSet('periode', '2026-12')
            ->assertSeeHtml('min="2026-01"')->assertSeeHtml('max="2026-12"');
    }

    /** R4 : choisir 2026 ne déplace pas une dépense du jour (2027). */
    #[Test]
    public function aucune_ecriture_n_est_deplacee_par_le_selecteur(): void
    {
        $this->actingAs($this->utilisateur('comptable'));
        ExerciceConsulte::choisir($this->n->id);

        $compte = (string) app(PlanComptableService::class)->comptesDeCharge()
            ->first(static fn ($c): bool => strlen((string) $c->numero_compte) === 4)->numero_compte;
        CompteComptable::query()->where('numero_compte', $compte)
            ->update(['centre_cout_defaut_id' => CentreCout::query()->where('libelle', 'Restaurant')->value('id')]);

        Livewire::test(Depenses::class)
            ->call('ouvrirFormulaireDepense')
            ->assertSet('dateTransaction', '2027-02-10')
            ->set('libelle', 'Marché du matin')
            ->set('tresorerieCode', 'caisse')
            ->set('lignes.0.libelle', 'Oignons')
            ->set('lignes.0.nature', 'Oignon')
            ->set('lignes.0.compte_charge', $compte)
            ->set('lignes.0.montant', '12000')
            ->call('enregistrerDepense')
            ->assertHasNoErrors();

        $this->assertSame(1, Depense::query()->count());
        $this->assertTrue(EcritureComptable::query()->where('exercice_id', $this->n1->id)->exists());
        $this->assertFalse(EcritureComptable::query()->where('exercice_id', $this->n->id)->exists());
    }

    #[Test]
    public function le_rechargement_ne_quitte_jamais_le_site(): void
    {
        $this->actingAs($this->utilisateur('comptable'));

        Livewire::test(SelecteurExercice::class)
            ->set('retour', 'https://exemple.invalid/pwa/facturation?exercice=x&q=abc')
            ->set('exerciceId', $this->n->id)
            ->assertRedirect(url('/pwa/facturation').'?q=abc');
    }
}

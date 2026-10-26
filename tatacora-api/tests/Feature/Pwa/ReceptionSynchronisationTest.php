<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Caisse\Services\SessionCaisseService;
use App\Domain\Ventes\Models\Vente;
use App\Models\User;
use App\Pwa\Livewire\Transverse\EnvoiSynchronisation;
use App\Pwa\Livewire\Transverse\ReceptionSynchronisation;
use App\Pwa\Livewire\Transverse\SynchronisationPostes;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Sync\Models\EtatPosteSynchronisation;
use App\Shared\Sync\Models\JournalReceptionSynchronisation as Journal;
use App\Shared\Sync\Services\CorrectionReceptionService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PrepareLesDocuments;
use Tests\TestCase;

/**
 * Les onglets « Réception » et « Envoi » de « Postes & Appairage »
 * (26/10/2026) : lire la cause d'un échec, corriger, relancer, marquer comme
 * traité — sous le droit du module de la donnée, avec l'auteur tracé.
 */
final class ReceptionSynchronisationTest extends TestCase
{
    use PrepareLesDocuments;
    use RefreshDatabase;

    private User $admin;

    private User $barman;

    private SessionCaisse $session;

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerLeDecor();
        $this->admin = $this->creerUtilisateur('administrateur');
        $this->barman = $this->creerUtilisateur('barman');
        $this->session = app(SessionCaisseService::class)->ouvrir('bar', '10000', $this->barman->id, now()->subDay()->setTime(7, 0));
    }

    /**
     * LE scénario : le poste pousse une vente dont la remise dépasse le total
     * → rejet consigné avec sa cause → correction depuis le web (vérifiée par
     * les règles de la vente) → relance → acceptée, une seule vente.
     */
    #[Test]
    public function une_vente_rejetee_se_corrige_puis_se_relance_depuis_le_web(): void
    {
        $id = $this->uuid();
        $operation = $this->vente($id, remise: 5000);
        $this->pousser([$operation], $this->barman, 'poste-bar')->assertJsonPath('resultats.0.statut', 'rejete');
        $ligne = Journal::where('uuid_operation', $operation['uuid_operation'])->sole();
        $this->assertSame(Journal::REJETEE, $ligne->issue);
        $this->assertSame(0, Vente::count());

        $this->app['auth']->forgetGuards();
        $this->actingAs($this->admin);
        $indice = $this->indiceDuChamp($ligne, 'remise_valeur');

        $composant = Livewire::test(ReceptionSynchronisation::class)
            ->assertSee('Vente')
            ->assertSee('poste-bar')
            ->assertSee('Rejetée')
            ->assertSee(__('ventes.remise_superieure_au_total'))
            ->call('ouvrirOperation', $ligne->id)
            ->assertSee('Cause')
            ->assertSee('Corrigez la charge reçue')
            ->call('ouvrirCorrection', $ligne->id)
            ->assertSet('correctionId', $ligne->id)
            ->assertSet("saisie.{$indice}", '5000');

        // Une correction qui viole encore la règle est refusée, avec la cause.
        $composant->set("saisie.{$indice}", '4000')
            ->call('enregistrerCorrection')
            ->assertSet('correctionId', $ligne->id)
            ->assertSee('Correction refusée');
        $this->assertNull($ligne->fresh()->payload_corrige);

        // Une correction valide est enregistrée, mais PAS appliquée.
        $composant->set("saisie.{$indice}", '500')
            ->call('enregistrerCorrection')
            ->assertSet('correctionId', null)
            ->assertSee('Correction enregistrée');
        $ligne->refresh();
        $this->assertSame(500, $ligne->payload_corrige['remise_valeur']);
        $this->assertSame(5000, $ligne->payload['remise_valeur'], 'La charge reçue n\'est jamais réécrite.');
        $this->assertSame(Journal::CORRIGE, $ligne->traitement);
        $this->assertSame($this->admin->id, $ligne->traite_par);
        $this->assertSame(0, Vente::count(), 'La vérification n\'écrit rien.');
        $this->assertSame(0, \App\Domain\Stocks\Models\MouvementStock::where('type_mouvement', 'sortie')->count());

        // Relancer : rejeu par le chemin de la synchronisation.
        $composant->call('relancer', $ligne->id)->assertSee('Opération rejouée avec succès');
        $ligne->refresh();
        $this->assertSame(Journal::ACCEPTEE, $ligne->issue);
        $this->assertSame(Journal::RELANCE, $ligne->traitement);
        $this->assertSame(2, $ligne->tentatives);
        $this->assertNotNull($ligne->operation_relance_id);
        $this->assertSame(1, Vente::count());
        $vente = Vente::findOrFail($id);
        $this->assertSame($this->barman->id, $vente->utilisateur_id, 'Le document garde son auteur : le caissier du poste.');
        $this->assertSame('2026-10-14 21:30:00', $vente->created_at->format('Y-m-d H:i:s'), 'La date métier reste celle de la saisie.');

        // Idempotent : un second « Relancer » ne refait rien.
        $composant->call('relancer', $ligne->id)->assertSee('déjà abouti');
        $this->assertSame(1, Vente::count());

        // L'auteur est tracé au journal d'audit.
        foreach (['synchronisation_corrigee', 'synchronisation_relancee'] as $action) {
            $this->assertDatabaseHas('journal_audit', ['action' => $action, 'utilisateur_id' => $this->admin->id, 'entite_id' => $ligne->id]);
        }
        $this->assertSame(500, JournalAudit::where('action', 'synchronisation_corrigee')->sole()->valeur_apres['corrections']['remise_valeur']);
    }

    #[Test]
    public function une_relance_qui_echoue_garde_la_nouvelle_cause_et_reste_a_traiter(): void
    {
        $operation = $this->vente($this->uuid(), remise: 5000);
        $this->pousser([$operation], $this->barman);
        $ligne = Journal::where('uuid_operation', $operation['uuid_operation'])->sole();
        $this->actingAs($this->admin);

        Livewire::test(ReceptionSynchronisation::class)
            ->call('relancer', $ligne->id)
            ->assertSee('reste en échec')
            ->assertSee(__('ventes.remise_superieure_au_total'));

        $ligne->refresh();
        $this->assertSame(Journal::REJETEE, $ligne->issue);
        $this->assertSame(Journal::A_TRAITER, $ligne->traitement);
        $this->assertSame(2, $ligne->tentatives);
        $this->assertSame(0, Vente::count());
    }

    #[Test]
    public function un_droit_manquant_se_regle_puis_se_relance_sans_toucher_a_la_charge(): void
    {
        $operation = $this->vente($this->uuid(), plat: true);
        $this->pousser([$operation], $this->barman)->assertJsonPath('resultats.0.code_motif', 'droit_manquant');
        $ligne = Journal::where('uuid_operation', $operation['uuid_operation'])->sole();

        // Le barman n'écrit pas sur le restaurant : la cause le dit. On
        // l'accorde à son rôle, puis on relance.
        $this->actingAs($this->admin);
        Livewire::test(ReceptionSynchronisation::class)->call('ouvrirOperation', $ligne->id)->assertSee('Restaurant');
        $role = $this->barman->role;
        $role->permissions()->attach(\App\Shared\Rbac\Models\Permission::where('module', 'M4')->pluck('id')->all());
        $this->barman->unsetRelation('role');
        app()->forgetInstance(\App\Shared\Sync\Services\SynchronisationService::class);

        Livewire::test(ReceptionSynchronisation::class)->call('relancer', $ligne->id)->assertSee('Opération rejouée avec succès');
        $this->assertSame(1, Vente::count());
    }

    #[Test]
    public function marquer_comme_traite_exige_un_motif_trace_et_ne_rejoue_rien(): void
    {
        $operation = $this->vente($this->uuid(), remise: 5000);
        $this->pousser([$operation], $this->barman);
        $ligne = Journal::where('uuid_operation', $operation['uuid_operation'])->sole();
        $this->actingAs($this->admin);

        Livewire::test(ReceptionSynchronisation::class)
            ->call('ouvrirIgnorer', $ligne->id)
            ->assertSet('ignorerId', $ligne->id)
            ->call('ignorer')
            ->assertSee('Indiquez le motif')
            ->set('motifIgnorer', 'Vente ressaisie sur le serveur')
            ->call('ignorer')
            ->assertSet('ignorerId', null)
            ->assertSee('Opération marquée comme traitée');

        $ligne->refresh();
        $this->assertSame(Journal::IGNORE, $ligne->traitement);
        $this->assertSame('Vente ressaisie sur le serveur', $ligne->motif_traitement);
        $this->assertSame($this->admin->id, $ligne->traite_par);
        $this->assertSame(0, Vente::count());
        $this->assertDatabaseHas('journal_audit', ['action' => 'synchronisation_ignoree', 'utilisateur_id' => $this->admin->id]);

        // Une opération prise en charge ne se relance plus.
        Livewire::test(ReceptionSynchronisation::class)->call('relancer', $ligne->id)->assertSee('déjà été prise en charge');
    }

    #[Test]
    public function les_filtres_restreignent_la_liste_et_les_compteurs(): void
    {
        $this->pousser([$this->vente($this->uuid(), remise: 5000)], $this->barman, 'poste-bar');
        $this->pousser([$this->vente($this->uuid())], $this->barman, 'poste-comptoir');
        $this->actingAs($this->admin);

        $test = Livewire::test(ReceptionSynchronisation::class)
            ->assertSee('poste-bar')->assertSee('poste-comptoir');
        $this->assertSame(2, $test->viewData('compteurs')['total']);

        $test->set('filtrePoste', 'poste-bar')->assertSee('Rejetée');
        $this->assertSame(['poste-bar'], $test->viewData('lignes')->pluck('poste_id')->unique()->values()->all());
        $this->assertSame(1, $test->viewData('compteurs')['total']);
        $this->assertSame(1, $test->viewData('compteurs')['a_traiter']);

        $test->set('filtrePoste', '')->set('filtreIssue', 'acceptee');
        $this->assertCount(1, $test->viewData('lignes'));
        $test->set('filtreIssue', '')->set('filtreATraiter', true);
        $this->assertCount(1, $test->viewData('lignes'));
        $test->set('filtreATraiter', false)->set('filtreTable', 'clients');
        $this->assertCount(0, $test->viewData('lignes'));
    }

    #[Test]
    public function seuls_les_administrateurs_et_le_comptable_lisent_et_chaque_geste_exige_son_module(): void
    {
        $operation = $this->vente($this->uuid(), remise: 5000);
        $this->pousser([$operation], $this->barman);
        $ligne = Journal::where('uuid_operation', $operation['uuid_operation'])->sole();

        // Rôle non autorisé : rien n'est lisible, chaque geste est un 403.
        foreach (['gerant', 'receptionniste', 'barman'] as $role) {
            $this->app['auth']->forgetGuards();
            $this->actingAs($this->creerUtilisateur($role));
            Livewire::test(ReceptionSynchronisation::class)
                ->assertSee('réservés aux Administrateurs et au Comptable')
                ->assertDontSee('poste-windows-1')
                ->call('relancer', $ligne->id)->assertForbidden();
            Livewire::test(ReceptionSynchronisation::class)->call('ouvrirOperation', $ligne->id)->assertForbidden();
            Livewire::test(ReceptionSynchronisation::class)->set('motifIgnorer', 'x')->call('ignorer')->assertForbidden();
            Livewire::test(EnvoiSynchronisation::class)->call('voirPoste', 'poste-windows-1')->assertForbidden();
        }
        $this->assertSame(Journal::A_TRAITER, $ligne->fresh()->traitement);

        // Le comptable lit (M5 en lecture) mais n'écrit pas sur M5 : 403 + trace.
        $this->app['auth']->forgetGuards();
        $comptable = $this->creerUtilisateur('comptable');
        $this->actingAs($comptable);
        Livewire::test(ReceptionSynchronisation::class)
            ->assertSee('Rejetée')
            ->call('ouvrirOperation', $ligne->id)->assertSee('Cause')
            ->call('relancer', $ligne->id)->assertForbidden();
        $this->assertDatabaseHas('journal_securite', ['utilisateur_id' => $comptable->id, 'module_concerne' => 'M5']);
        $this->assertSame(0, Vente::count());
        $this->assertNull(app(CorrectionReceptionService::class)->moduleRefuse($ligne, $this->admin));
        $this->assertSame('M5', app(CorrectionReceptionService::class)->moduleRefuse($ligne, $comptable));
    }

    #[Test]
    public function l_onglet_se_choisit_dans_la_page_et_retombe_sur_postes_sans_le_droit(): void
    {
        $this->actingAs($this->admin);
        Livewire::test(SynchronisationPostes::class)
            ->assertSee('Réception')->assertSee('Envoi')
            ->assertSet('onglet', 'postes')
            ->call('changerOnglet', 'reception')
            ->assertSet('onglet', 'reception')
            ->assertSeeLivewire(ReceptionSynchronisation::class)
            ->call('changerOnglet', 'envoi')
            ->assertSeeLivewire(EnvoiSynchronisation::class)
            ->call('changerOnglet', 'nimportequoi')
            ->assertSet('onglet', 'postes');

        $this->app['auth']->forgetGuards();
        $this->actingAs($this->creerUtilisateur('gerant'));
        Livewire::test(SynchronisationPostes::class)
            ->assertDontSee('onglets-synchronisation', false)
            ->call('changerOnglet', 'reception')
            ->assertSet('onglet', 'postes')
            ->assertDontSeeLivewire(ReceptionSynchronisation::class);
    }

    #[Test]
    public function l_onglet_envoi_montre_les_postes_et_la_redescente_est_reservee_aux_administrateurs(): void
    {
        EtatPosteSynchronisation::create([
            'poste_id' => 'poste-bar', 'utilisateur_id' => $this->barman->id, 'derniere_descente_le' => now(),
            'descente_complete' => true, 'generation_perimee_nb' => 2, 'generation_perimee_le' => now(),
        ]);

        $this->actingAs($this->admin);
        Livewire::test(EnvoiSynchronisation::class)
            ->assertSee('poste-bar')->assertSee('À jour')
            ->call('voirPoste', 'poste-bar')->assertSee('Poste « poste-bar »')->assertSee('2 au total')
            ->call('fermerPoste')
            ->call('demanderRedescente', 'poste-bar')
            ->assertSee('Redescendre depuis le début le poste « poste-bar » ?')
            ->call('redescendre')
            ->assertSee('Redescente demandée')
            ->assertSee('Redescente demandée le');
        $this->assertNotNull(EtatPosteSynchronisation::where('poste_id', 'poste-bar')->value('redescente_demandee_le'));
        // La demande de synchronisation existante invite les postes à passer.
        $this->assertDatabaseCount('demandes_synchronisation', 1);

        $this->app['auth']->forgetGuards();
        $this->actingAs($this->creerUtilisateur('comptable'));
        Livewire::test(EnvoiSynchronisation::class)
            ->assertSee('poste-bar')
            ->assertDontSee('Redescendre depuis le début</button>', false)
            ->call('demanderRedescente', 'poste-bar')->assertForbidden();
        Livewire::test(EnvoiSynchronisation::class)->call('redescendre')->assertForbidden();
    }

    /** L'index du champ dans le formulaire (même ordre que `champs()`). */
    private function indiceDuChamp(Journal $ligne, string $chemin): int
    {
        foreach (app(CorrectionReceptionService::class)->champs($ligne->payload) as $indice => $champ) {
            if ($champ['chemin'] === $chemin) {
                return $indice;
            }
        }

        $this->fail("Champ {$chemin} introuvable.");
    }

    /** @return array<string, mixed> */
    private function vente(string $id, ?int $remise = null, bool $plat = false): array
    {
        $lignes = [[
            'module_source' => 'M5', 'code_article' => $this->biere->id, 'libelle' => 'Béninoise 65cl',
            'prix_unitaire' => 1000, 'quantite' => 2,
        ]];

        if ($plat) {
            $lignes[] = ['module_source' => 'M4', 'code_article' => $this->platRiz->id, 'libelle' => 'Riz sauce arachide', 'prix_unitaire' => 2500, 'quantite' => 1];
        }

        return $this->operationDatee('ventes', 'creation', $id, [
            'type_vente' => 'comptant',
            'mode_paiement' => 'especes',
            'session_encaissement_id' => $this->session->id,
            'cloture_le' => '2026-10-14 21:30:00',
            'point_vente' => 'Bar',
            'lignes' => $lignes,
            ...($remise !== null ? ['remise_type' => 'montant', 'remise_valeur' => $remise] : []),
        ], '2026-10-14T21:30:00+00:00');
    }
}

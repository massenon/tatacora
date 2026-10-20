<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Comptabilite;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\ClotureExercice;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use App\Domain\Comptabilite\Services\BalanceGeneraleService;
use App\Domain\Comptabilite\Services\ClotureExerciceService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Models\User;
use App\Pwa\Livewire\Comptabilite\Hub;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * La clôture SYSCOHADA ANNUELLE — lot 2 (décisions du Product Owner du
 * 20/10/2026 : annuelle, réouverture par LE COMPTABLE). Le cycle complet,
 * chiffres à l'appui : à-nouveaux provisoires calculés en N+1, clôture qui
 * solde les comptes de gestion en 131/139 centre par centre et reporte les
 * comptes de bilan au journal AN, verrou, réouverture contre-passée,
 * re-clôture.
 */
final class ClotureSyscohadaTest extends TestCase
{
    use RefreshDatabase;

    private User $comptable;

    private ExerciceComptable $n;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-20 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->comptable = $this->utilisateur('comptable');
        $this->actingAs($this->comptable);
        $this->n = ExerciceComptable::query()->where('annee', 2026)->firstOrFail();
    }

    private function centre(string $libelle): string
    {
        return (string) CentreCout::query()->where('libelle', $libelle)->value('id');
    }

    /** Vente bar 100 000, charge restaurant 30 000 : bénéfice 70 000. */
    private function exploiter(string $vente = '100000.00', string $charge = '30000.00'): void
    {
        $passer = app(PasserEcritureService::class);
        $passer->passerEtValider(['journal' => 'CAI', 'date' => '2026-03-10', 'libelle' => 'Ventes bar', 'lignes' => [
            ['compte' => '5711', 'debit' => $vente],
            ['compte' => '7011', 'credit' => $vente, 'centre_id' => $this->centre('Bar')],
        ]]);
        $passer->passerEtValider(['journal' => 'CAI', 'date' => '2026-03-11', 'libelle' => 'Marché', 'lignes' => [
            ['compte' => '6011', 'debit' => $charge, 'centre_id' => $this->centre('Restaurant')],
            ['compte' => '5711', 'credit' => $charge],
        ]]);
    }

    /** @return array<string, array{d: string, c: string}> */
    private function balance(string $exerciceId, bool $apresCloture = false): array
    {
        $b = app(BalanceGeneraleService::class)->genererPourExercice($exerciceId, ['validee'], apresCloture: $apresCloture);
        $this->assertTrue($b->equilibree, 'balance équilibrée');

        return collect($b->lignes)->mapWithKeys(fn ($l): array => [$l->numeroCompte => ['d' => $l->totalDebit, 'c' => $l->totalCredit]])->all();
    }

    /**
     * Les SOLDES nets (débit − crédit), comptes non soldés seulement : une
     * contre-passation laisse les totaux grossir, jamais les soldes changer.
     *
     * @return array<string, string>
     */
    private function soldes(string $exerciceId): array
    {
        return collect($this->balance($exerciceId))
            ->map(fn (array $m): string => bcsub($m['d'], $m['c'], 2))
            ->reject(fn (string $s): bool => bccomp($s, '0', 2) === 0)
            ->all();
    }

    private function service(): ClotureExerciceService
    {
        return app(ClotureExerciceService::class);
    }

    #[Test]
    public function le_cycle_complet_a_nouveaux_provisoires_cloture_verrou(): void
    {
        $this->exploiter();

        // Démarrer : N+1 ouvert d'office, les modules ne passent plus dans N.
        $this->service()->demarrer($this->n, $this->comptable);
        $this->assertSame('en_cloture', $this->n->refresh()->statut);
        $n1 = ExerciceComptable::query()->where('annee', 2027)->firstOrFail();
        $this->assertSame('ouvert', $n1->statut);

        try {
            app(PasserEcritureService::class)->passerEtValider(['journal' => 'CAI', 'date' => '2026-12-30', 'libelle' => 'Vente tardive', 'lignes' => [
                ['compte' => '5711', 'debit' => '1000.00'],
                ['compte' => '7011', 'credit' => '1000.00', 'centre_id' => $this->centre('Bar')],
            ]]);
            $this->fail('Une pièce de module dans un exercice en clôture aurait dû être refusée.');
        } catch (RuntimeException $e) {
            $this->assertStringContainsString('en_cloture', $e->getMessage());
        }

        // À-nouveaux PROVISOIRES calculés en 2027 : caisse 70 000, bénéfice en 131.
        $provisoire = app(BalanceGeneraleService::class)->genererPourExercice($n1->id, ['validee']);
        $this->assertSame(2026, $provisoire->aNouveauxProvisoiresDe);
        $b = $this->balance($n1->id);
        $this->assertSame(['d' => '70000.00', 'c' => '0.00'], $b['5711']);
        $this->assertSame(['d' => '0.00', 'c' => '70000.00'], $b['131']);
        $this->assertSame(0, EcritureComptable::query()->where('exercice_id', $n1->id)->count(), 'rien n’est écrit');

        // Clôturer.
        $cloture = $this->service()->cloturer($this->n->refresh(), $this->comptable);
        $this->assertSame('cloture', $this->n->refresh()->statut);
        $this->assertSame('70000.00', (string) $cloture->resultat);

        // Les états de 2026 restent ceux d'AVANT la clôture (journal CL exclu).
        $avant = $this->balance($this->n->id);
        $this->assertSame(['d' => '0.00', 'c' => '100000.00'], $avant['7011']);
        $this->assertArrayNotHasKey('131', $avant);
        $this->assertSame('70000.00', app(\App\Domain\Comptabilite\Services\CompteResultatService::class)->genererPourExercice($this->n->id, ['validee'])->resultatNet);

        // Après clôture : les comptes de gestion soldés, CENTRE PAR CENTRE ;
        // 131 = résultat.
        $b2026 = $this->balance($this->n->id, apresCloture: true);
        $this->assertSame(['d' => '100000.00', 'c' => '100000.00'], $b2026['7011']);
        $this->assertSame(['d' => '30000.00', 'c' => '30000.00'], $b2026['6011']);
        $this->assertSame(['d' => '0.00', 'c' => '70000.00'], $b2026['131']);
        $structure = $this->centre('Structure');
        $pieceCloture = EcritureComptable::query()->where('numero_piece', $cloture->piece_cloture)->get();
        $this->assertSame(['2026-12-31'], $pieceCloture->map(fn ($e) => $e->date_ecriture->toDateString())->unique()->values()->all());
        $this->assertSame($this->centre('Bar'), (string) $pieceCloture->firstWhere('debit', '100000.00')->centre_id);
        $this->assertSame($structure, (string) $pieceCloture->firstWhere('credit', '70000.00')->centre_id);

        // Les à-nouveaux ÉCRITS au journal AN du 01/01/2027, plus aucun provisoire.
        $an = EcritureComptable::query()->where('numero_piece', $cloture->piece_a_nouveaux)->get();
        $this->assertSame(JournalComptable::query()->where('code', 'AN')->value('id'), (string) $an->first()->journal_id);
        $this->assertSame($n1->id, (string) $an->first()->exercice_id);
        $this->assertSame('2027-01-01', $an->first()->date_ecriture->toDateString());
        $this->assertTrue($an->every(fn ($e) => $e->statut === 'validee'));
        $apres = app(BalanceGeneraleService::class)->genererPourExercice($n1->id, ['validee']);
        $this->assertNull($apres->aNouveauxProvisoiresDe);
        $this->assertSame($b, $this->balance($n1->id), 'mêmes soldes, désormais écrits');

        // Verrou : plus rien n'entre dans 2026, même une écriture d'inventaire.
        $this->expectException(RuntimeException::class);
        try {
            app(PasserEcritureService::class)->passerEtValider(['journal' => 'OD', 'date' => '2026-12-31', 'libelle' => 'Inventaire', 'lignes' => [
                ['compte' => '6011', 'debit' => '10.00', 'centre_id' => $structure],
                ['compte' => '5711', 'credit' => '10.00'],
            ], 'statuts_exercice_admis' => ['en_cloture']]);
        } finally {
            $this->assertTrue(JournalAudit::query()->where('action', 'exercice_cloture')->exists());
            $this->assertTrue(JournalAudit::query()->where('action', 'cloture_demarree')->exists());
        }
    }

    #[Test]
    public function une_perte_va_en_139_et_l_inventaire_du_comptable_entre_en_cloture(): void
    {
        $this->exploiter(vente: '10000.00', charge: '25000.00');
        $this->service()->demarrer($this->n, $this->comptable);

        // L'écriture d'inventaire du comptable entre dans l'exercice en clôture.
        app(PasserEcritureService::class)->passerEtValider(['journal' => 'OD', 'date' => '2026-12-31', 'libelle' => 'Provision', 'lignes' => [
            ['compte' => '6011', 'debit' => '5000.00', 'centre_id' => $this->centre('Structure')],
            ['compte' => '5711', 'credit' => '5000.00'],
        ], 'statuts_exercice_admis' => ['ouvert', 'en_cloture']]);

        $cloture = $this->service()->cloturer($this->n->refresh(), $this->comptable);
        $this->assertSame('-20000.00', (string) $cloture->resultat);
        $b = $this->balance($this->n->id, apresCloture: true);
        $this->assertSame(['d' => '20000.00', 'c' => '0.00'], $b['139']);
        $n1 = ExerciceComptable::query()->where('annee', 2027)->firstOrFail();
        $this->assertSame(['d' => '20000.00', 'c' => '0.00'], $this->balance($n1->id)['139']);
    }

    #[Test]
    public function les_refus_statut_ordre_brouillon(): void
    {
        $this->exploiter();

        try {
            $this->service()->cloturer($this->n, $this->comptable);
            $this->fail('Clôturer un exercice ouvert aurait dû être refusé.');
        } catch (RuntimeException $e) {
            $this->assertSame(__('comptabilite.cloture_exige_en_cloture', ['annee' => '2026']), $e->getMessage());
        }

        // Un brouillon bloque la clôture définitive.
        app(PasserEcritureService::class)->passer(['journal' => 'OD', 'date' => '2026-05-05', 'libelle' => 'À relire', 'lignes' => [
            ['compte' => '6011', 'debit' => '10.00', 'centre_id' => $this->centre('Structure')],
            ['compte' => '5711', 'credit' => '10.00'],
        ]]);
        $this->service()->demarrer($this->n, $this->comptable);

        try {
            $this->service()->cloturer($this->n->refresh(), $this->comptable);
            $this->fail('Un brouillon aurait dû bloquer la clôture.');
        } catch (RuntimeException $e) {
            $this->assertStringContainsString(__('pwa.comptabilite.motifs.ecritures_en_brouillon'), $e->getMessage());
        }
        $this->assertSame('en_cloture', $this->n->refresh()->statut);
        $this->assertSame(0, ClotureExercice::query()->count());

        // L'ordre : 2027 ne se clôture pas avant 2026.
        $n1 = ExerciceComptable::query()->where('annee', 2027)->firstOrFail();
        $this->service()->demarrer($n1, $this->comptable);

        try {
            $this->service()->cloturer($n1->refresh(), $this->comptable);
            $this->fail('2027 ne devait pas se clôturer avant 2026.');
        } catch (RuntimeException $e) {
            $this->assertSame(__('comptabilite.cloture_ordre', ['annee' => '2027', 'precedent' => '2026']), $e->getMessage());
        }

        // Reprendre la saisie : en_cloture → ouvert.
        $this->service()->reprendreSaisie($this->n->refresh(), $this->comptable);
        $this->assertSame('ouvert', $this->n->refresh()->statut);
    }

    #[Test]
    public function la_reouverture_est_au_comptable_seul_contre_passe_et_permet_une_re_cloture(): void
    {
        $this->exploiter();
        $this->service()->demarrer($this->n, $this->comptable);
        $premiere = $this->service()->cloturer($this->n->refresh(), $this->comptable);
        $n1 = ExerciceComptable::query()->where('annee', 2027)->firstOrFail();
        $soldes2027 = $this->soldes($n1->id);
        $this->assertSame(['131' => '-70000.00', '5711' => '70000.00'], $soldes2027);

        // Un administrateur ne rouvre pas (décision du PO : le comptable).
        try {
            $this->service()->rouvrir($this->n->refresh(), $this->utilisateur('administrateur'), 'Correction d’une facture oubliée');
            $this->fail('Un administrateur ne doit pas rouvrir.');
        } catch (RuntimeException $e) {
            $this->assertSame(__('comptabilite.reouverture_reservee'), $e->getMessage());
        }

        try {
            $this->service()->rouvrir($this->n->refresh(), $this->comptable, 'court');
            $this->fail('Un motif trop court doit être refusé.');
        } catch (RuntimeException $e) {
            $this->assertSame(__('comptabilite.reouverture_motif', ['min' => 10]), $e->getMessage());
        }

        $this->service()->rouvrir($this->n->refresh(), $this->comptable, 'Correction d’une facture oubliée');
        $this->assertSame('en_cloture', $this->n->refresh()->statut);
        $this->assertNotNull($premiere->refresh()->rouverte_le);
        $this->assertSame('Correction d’une facture oubliée', $premiere->motif_reouverture);

        // Rien ne s'efface : les deux pièces sont contre-passées à leur date.
        $contre = EcritureComptable::query()->whereNotNull('ecriture_contrepassee_id')->get();
        $this->assertSame(
            EcritureComptable::query()->whereIn('numero_piece', [$premiere->piece_cloture, $premiere->piece_a_nouveaux])->count(),
            $contre->count(),
        );
        $this->assertContains('2027-01-01', $contre->map(fn ($e) => $e->date_ecriture->toDateString())->all());
        $this->assertContains('2026-12-31', $contre->map(fn ($e) => $e->date_ecriture->toDateString())->all());

        // 2027 retrouve ses à-nouveaux PROVISOIRES, mêmes soldes.
        $this->assertSame(2026, app(BalanceGeneraleService::class)->genererPourExercice($n1->id, ['validee'])->aNouveauxProvisoiresDe);
        $this->assertSame($soldes2027, $this->soldes($n1->id));

        // Re-clôture : de nouvelles pièces, l'historique garde les deux.
        $seconde = $this->service()->cloturer($this->n->refresh(), $this->comptable);
        $this->assertNotSame($premiere->piece_cloture, $seconde->piece_cloture);
        $this->assertSame(2, ClotureExercice::query()->count());
        $this->assertSame($soldes2027, $this->soldes($n1->id));
        $this->assertTrue(JournalAudit::query()->where('action', 'exercice_rouvert')->exists());

        // N+1 clôturé : N ne se rouvre plus.
        $this->service()->demarrer($n1->refresh(), $this->comptable);
        $this->service()->cloturer($n1->refresh(), $this->comptable);
        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage((string) __('comptabilite.reouverture_suivant_clos', ['annee' => '2026', 'suivant' => '2027']));
        $this->service()->rouvrir($this->n->refresh(), $this->comptable, 'Une seconde correction tardive');
    }

    #[Test]
    public function l_ecran_cloture_mene_le_cycle_et_reserve_la_reouverture_au_comptable(): void
    {
        $this->exploiter();
        $hub = fn () => Livewire::withQueryParams(['exercice' => $this->n->id])->test(Hub::class, ['onglet' => 'clotures']);

        $hub()->assertSee(__('comptabilite_pwa.cloture_demarrer', ['annee' => 2026]))
            ->call('demarrerCloture')->assertHasNoErrors();
        $this->assertSame('en_cloture', $this->n->refresh()->statut);

        $hub()->assertSee(__('comptabilite_pwa.cloture_definitive', ['annee' => 2026]))
            ->call('cloturerExercice')->assertHasNoErrors();
        $this->assertSame('cloture', $this->n->refresh()->statut);

        $this->actingAs($this->utilisateur('administrateur'));
        $hub()->assertSee(__('comptabilite_pwa.reouvrir_reserve'))->assertDontSeeHtml('wire:click="rouvrirExercice"');

        $this->actingAs($this->comptable);
        $hub()->set('motifReouverture', 'Écriture de régularisation oubliée')
            ->call('rouvrirExercice')->assertHasNoErrors();
        $this->assertSame('en_cloture', $this->n->refresh()->statut);

        $hub()->set('motifReouverture', 'x')->call('cloturerExercice')->assertHasNoErrors();
        $this->assertSame('cloture', $this->n->refresh()->statut);
    }

    #[Test]
    public function la_liste_de_controle_suit_la_cloture_reelle(): void
    {
        $this->exploiter();
        $etat = fn () => collect(app(\App\Domain\Comptabilite\Services\EtatClotureService::class)
            ->genererPourExercice($this->n->refresh(), ['validee'])->etapes)
            // Les étapes du geste de clôture (2 à 5), hors le calcul du
            // résultat (toujours fait) et les dotations (hors M10).
            ->filter(fn ($e): bool => $e->groupe >= 2 && $e->groupe <= 5
                && ! in_array($e->libelle, ['Calcul du résultat net', "Dotations aux amortissements de l'exercice"], true))
            ->mapWithKeys(fn ($e): array => [$e->libelle => $e->etat])->all();

        $this->assertSame(['non_atteint'], array_values(array_unique($etat())));

        $this->service()->demarrer($this->n, $this->comptable);
        $this->assertSame('conforme', $etat()["Bloque toute nouvelle saisie sur l'exercice"]);
        $this->assertSame('non_atteint', $etat()['Verrou définitif RG-11bis']);

        $this->service()->cloturer($this->n->refresh(), $this->comptable);
        $this->assertSame(['conforme'], array_values(array_unique($etat())), json_encode($etat(), JSON_UNESCAPED_UNICODE));

        $this->service()->rouvrir($this->n->refresh(), $this->comptable, 'Régularisation oubliée en mars');
        $this->assertSame('non_atteint', $etat()['Solde des comptes de gestion (classes 6/7 → 131/139)']);
    }

    #[Test]
    public function le_grand_livre_et_les_notes_lisent_le_report_a_nouveau(): void
    {
        $this->exploiter(); // 5711 : +70 000 net en 2026 (100 000 - 30 000)
        $n1 = app(\App\Domain\Comptabilite\Services\ExerciceComptableService::class)->assurer(2027, 'test');
        $banque = \App\Domain\Comptabilite\Models\CompteComptable::query()->where('numero_compte', '5711')->firstOrFail();
        $grandLivre = fn () => app(\App\Domain\Comptabilite\Services\GrandLivreService::class)
            ->genererPourCompte($n1->id, $banque, ['validee']);

        // 2026 non clôturé : ouverture PROVISOIRE de 2027 = 70 000 D.
        $provisoire = $grandLivre();
        $this->assertSame('70000.00', $provisoire->soldeOuverture);
        $this->assertSame('70000.00', $provisoire->soldeCloture);
        $this->assertTrue($provisoire->ouvertureProvisoire);
        $this->assertNull($provisoire->motifSoldesIndisponibles);

        // Un compte de gestion repart de zéro.
        $vente = \App\Domain\Comptabilite\Models\CompteComptable::query()->where('numero_compte', '7011')->firstOrFail();
        $this->assertSame('0.00', app(\App\Domain\Comptabilite\Services\GrandLivreService::class)
            ->genererPourCompte($n1->id, $vente, ['validee'])->soldeOuverture);

        // Clôture de 2026 : le report est ÉCRIT (journal AN), même montant,
        // et il fait partie des lignes du grand livre — plus provisoire.
        $this->service()->demarrer($this->n, $this->comptable);
        $this->service()->cloturer($this->n->refresh(), $this->comptable);
        $definitif = $grandLivre();
        $this->assertSame('70000.00', $definitif->soldeOuverture);
        $this->assertSame('70000.00', $definitif->soldeCloture);
        $this->assertFalse($definitif->ouvertureProvisoire);
        $this->assertCount(1, $definitif->lignes);

        // Les notes 2 et 3 portent ouverture et variation, sans motif.
        $notes = app(\App\Domain\Comptabilite\Services\NotesAnnexesService::class)->genererPourExercice($n1, ['validee']);
        $this->assertNull($notes->notes[1]->motif);
    }

    #[Test]
    public function l_alerte_liste_les_postes_qui_n_ont_peut_etre_pas_tout_envoye(): void
    {
        foreach (['poste-a', 'poste-b', 'poste-c', 'poste-d'] as $poste) {
            $this->comptable->createToken($poste);
        }
        $etat = fn (string $poste, ?int $attente, $quand) => \App\Shared\Sync\Models\EtatPosteSynchronisation::query()->create([
            'poste_id' => $poste, 'en_attente' => $attente, 'derniere_descente_le' => $quand,
        ]);
        $etat('poste-a', 3, now()->subMinutes(5));   // 3 opérations à envoyer
        $etat('poste-b', 0, now()->subMinutes(5));   // à jour
        $etat('poste-c', 0, now()->subHours(30));    // silencieux depuis 30 h
        // poste-d : appairé, jamais rien reçu

        $alertes = collect(app(\App\Shared\Sync\Services\SuiviPostesService::class)->postesNonAJour())->keyBy('poste_id');

        $this->assertSame(['poste-a', 'poste-c', 'poste-d'], $alertes->keys()->sort()->values()->all());
        $this->assertSame(3, $alertes['poste-a']['en_attente']);
        $this->assertFalse($alertes['poste-a']['inconnu']);
        $this->assertTrue($alertes['poste-c']['inconnu']);
        $this->assertTrue($alertes['poste-d']['inconnu']);

        // L'onglet Clôtures la montre AVANT de démarrer, et plus ensuite.
        $hub = fn () => Livewire::withQueryParams(['exercice' => $this->n->id])->test(Hub::class, ['onglet' => 'clotures']);
        $hub()->assertSeeHtml('id="alerte-postes"')->assertSee('poste-a')->assertDontSee('poste-b');
        $this->service()->demarrer($this->n, $this->comptable);
        $hub()->assertDontSeeHtml('id="alerte-postes"');
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.' . Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}

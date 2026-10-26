<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Caisse\Services\SessionCaisseService;
use App\Models\User;
use App\Shared\Sync\Models\JournalReceptionSynchronisation as Journal;
use App\Shared\Sync\Services\JournalReceptionService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\Feature\Sync\Concerns\PrepareLesDocuments;
use Tests\TestCase;

/**
 * Le journal de RÉCEPTION (26/10/2026) : chaque opération de `POST /sync`
 * laisse une ligne avec son issue, son motif structuré et sa cause — sans
 * jamais changer ce que le poste reçoit (le contrat reste rétro-compatible :
 * `code_motif` est un ajout).
 */
final class JournalReceptionSynchronisationTest extends TestCase
{
    use PrepareLesDocuments;
    use RefreshDatabase;

    private User $barman;

    private User $gerant;

    private SessionCaisse $session;

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerLeDecor();
        $this->barman = $this->creerUtilisateur('barman');
        $this->gerant = $this->creerUtilisateur('gerant');
        $this->session = app(SessionCaisseService::class)->ouvrir('bar', '10000', $this->barman->id, now()->subDay()->setTime(7, 0));
    }

    #[Test]
    public function une_operation_acceptee_est_consignee_avec_sa_charge_et_son_auteur(): void
    {
        $id = $this->uuid();
        $operation = $this->vente($id, 2);

        $this->pousser([$operation], $this->barman, 'poste-bar')->assertJsonPath('resultats.0.statut', 'synchronise');

        $ligne = Journal::where('uuid_operation', $operation['uuid_operation'])->sole();
        $this->assertSame(Journal::ACCEPTEE, $ligne->issue);
        $this->assertSame('poste-bar', $ligne->poste_id);
        $this->assertSame($this->barman->id, $ligne->utilisateur_id);
        $this->assertSame('ventes', $ligne->table_concernee);
        $this->assertSame($id, $ligne->entite_id);
        $this->assertSame('creation', $ligne->type_operation);
        $this->assertSame(1, $ligne->tentatives);
        $this->assertNull($ligne->traitement);
        $this->assertSame('2026-10-14 21:30:00', $ligne->horodatage_poste->utc()->format('Y-m-d H:i:s'));
        $this->assertSame(2, $ligne->payload['lignes'][0]['quantite']);
        $this->assertNotNull($ligne->recu_le);
    }

    #[Test]
    public function un_renvoi_de_la_meme_operation_compte_une_tentative_de_plus(): void
    {
        $operation = $this->vente($this->uuid(), 1);

        $this->pousser([$operation], $this->barman);
        $reponse = $this->pousser([$operation], $this->barman);

        $reponse->assertJsonPath('resultats.0.rejeu_idempotent', true);
        $ligne = Journal::where('uuid_operation', $operation['uuid_operation'])->sole();
        $this->assertSame(2, $ligne->tentatives);
        $this->assertSame(Journal::ACCEPTEE, $ligne->issue, 'L\'issue d\'origine est conservée.');
        $this->assertSame(1, Journal::count());
    }

    #[Test]
    public function le_meme_document_sous_un_autre_uuid_d_operation_est_une_issue_dupliquee(): void
    {
        $operation = $this->vente($this->uuid(), 1);
        $this->pousser([$operation], $this->barman);
        $seconde = $this->nouvelleTentative($operation);

        $this->pousser([$seconde], $this->barman)->assertJsonPath('resultats.0.document_deja_enregistre', true);

        $ligne = Journal::where('uuid_operation', $seconde['uuid_operation'])->sole();
        $this->assertSame(Journal::DUPLIQUEE, $ligne->issue);
        $this->assertSame('document_deja_enregistre', $ligne->code_motif);
        $this->assertNotEmpty($ligne->cause);
    }

    #[Test]
    public function un_ecart_signale_est_une_issue_signalee_a_traiter(): void
    {
        $operation = $this->vente($this->uuid(), 2, prix: 900);
        $this->pousser([$operation], $this->barman);

        $ligne = Journal::where('uuid_operation', $operation['uuid_operation'])->sole();
        $this->assertSame(Journal::SIGNALEE, $ligne->issue);
        $this->assertSame('ecart_prix', $ligne->code_motif);
        $this->assertSame(['ecart_prix'], $ligne->details['anomalies']);
        $this->assertStringContainsString('Écart de prix', (string) $ligne->motif);
        $this->assertSame(Journal::A_TRAITER, $ligne->traitement);
    }

    #[Test]
    public function un_droit_manquant_est_un_rejet_dont_la_cause_nomme_le_module(): void
    {
        $operation = $this->vente($this->uuid(), 1, plat: true);

        $this->pousser([$operation], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('auth.module_refuse'))
            ->assertJsonPath('resultats.0.code_motif', 'droit_manquant');

        $ligne = Journal::where('uuid_operation', $operation['uuid_operation'])->sole();
        $this->assertSame(Journal::REJETEE, $ligne->issue);
        $this->assertSame('droit_manquant', $ligne->code_motif);
        $this->assertSame('M4', $ligne->details['module']);
        $this->assertStringContainsString('Restaurant', (string) $ligne->cause);
        $this->assertSame(Journal::A_TRAITER, $ligne->traitement);
    }

    #[Test]
    public function un_compte_inactif_n_est_pas_confondu_avec_un_droit_manquant(): void
    {
        $this->barman->update(['statut' => 'desactive']);
        $operation = $this->vente($this->uuid(), 1);

        $this->pousser([$operation], $this->barman)->assertJsonPath('resultats.0.code_motif', 'compte_inactif');
        $this->assertSame('compte_inactif', Journal::where('uuid_operation', $operation['uuid_operation'])->value('code_motif'));
    }

    #[Test]
    public function une_regle_de_gestion_donne_son_code_sa_phrase_et_sa_cause(): void
    {
        $operation = $this->vente($this->uuid(), 1, extra: ['remise_type' => 'montant', 'remise_valeur' => 5000]);

        $this->pousser([$operation], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.code_motif', 'regle_metier');

        $ligne = Journal::where('uuid_operation', $operation['uuid_operation'])->sole();
        $this->assertSame(__('ventes.remise_superieure_au_total'), $ligne->motif);
        $this->assertStringContainsString(__('ventes.remise_superieure_au_total'), (string) $ligne->cause);
        $this->assertSame(5000, $ligne->payload['remise_valeur']);
    }

    #[Test]
    public function des_donnees_invalides_listent_les_valeurs_refusees_en_francais(): void
    {
        $operation = $this->vente($this->uuid(), 1, extra: ['lignes' => []]);

        $this->pousser([$operation], $this->barman)->assertJsonPath('resultats.0.code_motif', 'donnees_invalides');

        $ligne = Journal::where('uuid_operation', $operation['uuid_operation'])->sole();
        $this->assertSame('donnees_invalides', $ligne->code_motif);
        $this->assertNotEmpty($ligne->details['erreurs']);
        $this->assertStringContainsString('Lignes', (string) $ligne->cause);
    }

    #[Test]
    public function une_table_inconnue_et_une_modification_d_inconnu_ont_leur_code(): void
    {
        $inconnue = $this->operation('table_fantome', 'creation', $this->uuid(), ['a' => 1]);
        $modification = $this->operation('ventes', 'modification', $this->uuid(), ['statut' => 'annulee', 'motif' => 'x']);

        $this->pousser([$inconnue, $modification], $this->barman);

        $this->assertSame('table_non_synchronisable', Journal::where('uuid_operation', $inconnue['uuid_operation'])->value('code_motif'));
        $this->assertSame('entite_inconnue', Journal::where('uuid_operation', $modification['uuid_operation'])->value('code_motif'));
        $cause = (string) Journal::where('uuid_operation', $inconnue['uuid_operation'])->value('cause');
        $this->assertStringContainsString('Table fantome', $cause);
    }

    #[Test]
    public function une_fusion_est_une_issue_fusionnee(): void
    {
        $acheteur = $this->creerUtilisateur('achats');
        $this->pousser([$this->operation('fournisseurs', 'creation', $this->uuid(), ['raison_sociale' => 'Glacier du Port'])], $acheteur, 'poste-a');
        $fusion = $this->operation('fournisseurs', 'creation', $this->uuid(), ['raison_sociale' => ' GLACIER du port ']);

        $this->pousser([$fusion], $acheteur, 'poste-b')->assertJsonStructure(['resultats' => [['fusionne_avec']]]);

        $ligne = Journal::where('uuid_operation', $fusion['uuid_operation'])->sole();
        $this->assertSame(Journal::FUSIONNEE, $ligne->issue);
        $this->assertSame('poste-b', $ligne->poste_id);
        $this->assertNotNull($ligne->details['fusionne_avec']);
    }

    #[Test]
    public function une_saisie_plus_ancienne_que_celle_du_serveur_est_une_version_conservee(): void
    {
        $acheteur = $this->creerUtilisateur('achats');
        $id = $this->uuid();
        $this->pousser([$this->operationDatee('fournisseurs', 'creation', $id, ['raison_sociale' => 'Brasserie'], now()->subHour()->toIso8601String())], $acheteur, 'poste-a');
        $this->pousser([$this->operationDatee('fournisseurs', 'modification', $id, ['contact' => 'Récent'], now()->subMinutes(10)->toIso8601String())], $acheteur, 'poste-a');
        $ancienne = $this->operationDatee('fournisseurs', 'modification', $id, ['contact' => 'Ancien'], now()->subMinutes(30)->toIso8601String());

        $this->pousser([$ancienne], $acheteur, 'poste-b')->assertJsonPath('resultats.0.resolution', 'version_serveur_conservee');

        $this->assertSame(Journal::CONSERVEE, Journal::where('uuid_operation', $ancienne['uuid_operation'])->value('issue'));
    }

    #[Test]
    public function un_conflit_et_une_erreur_du_serveur_sont_des_issues_a_traiter(): void
    {
        $journal = app(JournalReceptionService::class);
        $operation = $this->operation('ventes', 'modification', $this->uuid(), ['statut' => 'annulee']);

        $conflit = $journal->analyser($operation, ['statut' => 'conflit', 'conflit_id' => 'c-1']);
        $this->assertSame([Journal::CONFLIT, 'conflit_financier'], [$conflit['issue'], $conflit['code_motif']]);
        $this->assertStringContainsString('trancher', (string) $conflit['cause']);

        $journal->enregistrer($operation, 'poste-bar', $this->barman->id, null, [], [], new RuntimeException('SQLSTATE[HY000]: panne'));
        $ligne = Journal::where('uuid_operation', $operation['uuid_operation'])->sole();
        $this->assertSame([Journal::ERREUR, 'erreur_serveur', Journal::A_TRAITER], [$ligne->issue, $ligne->code_motif, $ligne->traitement]);
        $this->assertSame('RuntimeException', $ligne->details['exception']);

        // Le poste réessaie : l'issue réelle remplace l'erreur, tentative de plus.
        $journal->enregistrer($operation, 'poste-bar', $this->barman->id, null, ['statut' => 'synchronise', 'entite_id' => $operation['entite_id']]);
        $ligne->refresh();
        $this->assertSame([Journal::ACCEPTEE, 2, null], [$ligne->issue, $ligne->tentatives, $ligne->traitement]);
    }

    #[Test]
    public function une_panne_du_journal_ne_fait_jamais_echouer_la_synchronisation(): void
    {
        // Une opération sans table : l'écriture du journal échoue, l'erreur
        // est signalée, rien ne remonte à l'appelant.
        $operation = $this->vente($this->uuid(), 1);
        unset($operation['table']);

        app(JournalReceptionService::class)->enregistrer($operation, 'poste-bar', $this->barman->id, null, ['statut' => 'synchronise']);

        $this->assertSame(0, Journal::count());
    }

    #[Test]
    public function la_retention_est_bornee_et_garde_ce_qui_attend_un_humain(): void
    {
        $journal = app(JournalReceptionService::class);
        $faire = function (string $issue, ?string $traitement, int $joursPasses) {
            return Journal::create([
                'uuid_operation' => $this->uuid(), 'poste_id' => 'p', 'table_concernee' => 'ventes', 'entite_id' => $this->uuid(),
                'type_operation' => 'creation', 'recu_le' => now()->subDays($joursPasses), 'issue' => $issue,
                'tentatives' => 1, 'derniere_tentative_le' => now()->subDays($joursPasses), 'traitement' => $traitement,
            ]);
        };
        $ancienneAcceptee = $faire(Journal::ACCEPTEE, null, JournalReceptionService::RETENTION_JOURS + 1);
        $recenteAcceptee = $faire(Journal::ACCEPTEE, null, 5);
        $ancienneAttente = $faire(Journal::REJETEE, Journal::A_TRAITER, JournalReceptionService::RETENTION_JOURS + 1);
        $ancienneIgnoree = $faire(Journal::REJETEE, Journal::IGNORE, JournalReceptionService::RETENTION_JOURS + 1);
        $tresAncienne = $faire(Journal::REJETEE, Journal::A_TRAITER, JournalReceptionService::RETENTION_A_TRAITER_JOURS + 1);

        $this->assertSame(3, $journal->purger());

        $this->assertNull(Journal::find($ancienneAcceptee->id));
        $this->assertNull(Journal::find($ancienneIgnoree->id));
        $this->assertNull(Journal::find($tresAncienne->id));
        $this->assertNotNull(Journal::find($recenteAcceptee->id));
        $this->assertNotNull(Journal::find($ancienneAttente->id), 'Un rejet qui attend encore une correction n\'est pas purgé à 90 jours.');
    }

    #[Test]
    public function le_job_de_purge_de_la_synchronisation_purge_aussi_le_journal(): void
    {
        Journal::create([
            'uuid_operation' => $this->uuid(), 'poste_id' => 'p', 'table_concernee' => 'ventes', 'entite_id' => $this->uuid(),
            'type_operation' => 'creation', 'recu_le' => now()->subDays(120), 'issue' => Journal::ACCEPTEE,
            'tentatives' => 1, 'derniere_tentative_le' => now()->subDays(120),
        ]);

        (new \App\Shared\Sync\Jobs\NettoyerDeduplicationSyncJob())->handle(app(\App\Shared\Sync\Services\SynchronisationService::class));

        $this->assertSame(0, Journal::count());
    }

    /**
     * @param  array<string, mixed>  $extra
     * @return array<string, mixed>
     */
    private function vente(string $id, int $quantite, int $prix = 1000, bool $plat = false, array $extra = []): array
    {
        $lignes = [[
            'module_source' => 'M5', 'code_article' => $this->biere->id, 'libelle' => 'Béninoise 65cl',
            'prix_unitaire' => $prix, 'quantite' => $quantite,
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
            ...$extra,
        ], '2026-10-14T21:30:00+00:00');
    }
}

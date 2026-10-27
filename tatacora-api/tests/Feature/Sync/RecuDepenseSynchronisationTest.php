<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Depenses\Models\Depense;
use App\Domain\Depenses\Services\RecuDepenseService;
use App\Models\User;
use App\Shared\Sync\Models\JournalReceptionSynchronisation as Journal;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PrepareLesDocuments;
use Tests\TestCase;

/**
 * Le REÇU en image d'une dépense, déposé par un poste (lot L4, décision du PO
 * du 27/10/2026 : un transport de fichier dans la synchronisation).
 *
 * `PUT /api/v1/sync/depenses/{depense}/recu` : le corps est le fichier brut,
 * rattaché à l'UUID de la dépense que le poste a poussée par `/sync`. Les
 * bornes sont celles de l'écran web (règles `image` et `max:400`, mêmes
 * phrases) ; le dépôt est idempotent par empreinte SHA-256 ; il exige les
 * droits de la dépense ET son poste d'origine ; il est consigné au journal de
 * réception avec sa cause. Les jetons sont RÉELS (`createToken`) : un
 * `Sanctum::actingAs` court-circuiterait le contrôle du poste (PA-54).
 */
final class RecuDepenseSynchronisationTest extends TestCase
{
    use PrepareLesDocuments;
    use RefreshDatabase;

    private const POSTE = 'poste-windows-1';

    private User $comptable;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
        $this->preparerLeDecor();
        $this->comptable = $this->creerUtilisateur('comptable');
    }

    #[Test]
    public function le_recu_est_depose_range_et_accuse_avec_son_empreinte(): void
    {
        $id = $this->depenseDuPoste();
        $png = $this->png();

        $this->deposer($id, $png)
            ->assertOk()
            ->assertJsonPath('data.depense_id', $id)
            ->assertJsonPath('data.sha256', hash('sha256', $png))
            ->assertJsonPath('data.taille', strlen($png))
            ->assertJsonPath('data.type', 'image/png')
            ->assertJsonPath('data.rejeu', false);

        $depense = Depense::findOrFail($id);
        $this->assertStringStartsWith('recus_depenses/', (string) $depense->recu_path);
        $this->assertStringEndsWith('.png', (string) $depense->recu_path);
        Storage::disk('public')->assertExists((string) $depense->recu_path);
        $this->assertSame($png, Storage::disk('public')->get((string) $depense->recu_path));
        $this->assertSame(hash('sha256', $png), $depense->recu_sha256);
        $this->assertSame(strlen($png), $depense->recu_taille);
        $this->assertSame('image/png', $depense->recu_type);
    }

    #[Test]
    public function le_meme_fichier_redepose_apres_une_coupure_n_ecrit_rien_de_plus(): void
    {
        $id = $this->depenseDuPoste();
        $png = $this->png();

        $this->deposer($id, $png)->assertOk()->assertJsonPath('data.rejeu', false);
        $chemin = (string) Depense::findOrFail($id)->recu_path;

        $this->deposer($id, $png)->assertOk()->assertJsonPath('data.rejeu', true);

        $this->assertSame($chemin, (string) Depense::findOrFail($id)->recu_path);
        $this->assertCount(1, Storage::disk('public')->files('recus_depenses'));

        // Le journal garde UNE ligne et compte DEUX tentatives ; l'issue reste
        // celle du premier traitement (règle commune du journal de réception).
        $ligne = Journal::query()->where('table_concernee', 'recus_depenses')->sole();
        $this->assertSame(2, $ligne->tentatives);
        $this->assertSame(Journal::ACCEPTEE, $ligne->issue);
        $this->assertSame($id, $ligne->entite_id);
        $this->assertSame(self::POSTE, $ligne->poste_id);
    }

    #[Test]
    public function un_autre_fichier_ne_remplace_pas_le_recu_deja_rattache(): void
    {
        $id = $this->depenseDuPoste();
        $this->deposer($id, $this->png())->assertOk();
        $avant = Depense::findOrFail($id)->recu_sha256;

        $this->deposer($id, $this->jpeg())
            ->assertStatus(409)
            ->assertJsonPath('code', 'recu_deja_rattache')
            ->assertJsonPath('message', __('depenses.recu_deja_rattache'));

        $this->assertSame($avant, Depense::findOrFail($id)->recu_sha256);
        $ligne = Journal::query()->where('code_motif', 'recu_deja_rattache')->sole();
        $this->assertSame(Journal::REJETEE, $ligne->issue);
        $this->assertNull($ligne->traitement, 'rien à corriger côté serveur : le poste renvoie un fichier valable');
        $this->assertStringContainsString('déjà un reçu', (string) $ligne->cause);
    }

    #[Test]
    public function un_fichier_qui_n_est_pas_une_image_est_refuse_avec_la_phrase_du_web(): void
    {
        $id = $this->depenseDuPoste();

        $this->deposer($id, "Ceci est un texte, pas une image.\n", 'image/png')
            ->assertStatus(422)
            ->assertJsonPath('code', 'recu_invalide')
            ->assertJsonPath('message', 'Le champ photo recu doit être une image.');

        $this->assertNull(Depense::findOrFail($id)->recu_path);
        $this->assertSame([], Storage::disk('public')->files('recus_depenses'));
        $this->assertSame(Journal::REJETEE, Journal::query()->where('table_concernee', 'recus_depenses')->sole()->issue);
    }

    #[Test]
    public function les_types_du_web_passent_et_le_svg_est_refuse(): void
    {
        $svg = '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"><script>alert(1)</script></svg>';

        $this->deposer($this->depenseDuPoste(), $svg, 'image/svg+xml')->assertStatus(422);

        foreach (['png' => $this->png(), 'jpeg' => $this->jpeg(), 'gif' => $this->gif()] as $extension => $octets) {
            $id = $this->depenseDuPoste();
            $this->deposer($id, $octets)->assertOk();
            $this->assertStringEndsWith($extension === 'jpeg' ? '.jpg' : '.'.$extension, (string) Depense::findOrFail($id)->recu_path);
        }
    }

    #[Test]
    public function un_fichier_plus_lourd_que_le_maximum_de_l_ecran_est_refuse(): void
    {
        $id = $this->depenseDuPoste();
        $lourd = $this->png().str_repeat("\0", RecuDepenseService::TAILLE_MAX_KO * 1024);

        $this->deposer($id, $lourd)
            ->assertStatus(413)
            ->assertJsonPath('code', 'recu_trop_lourd')
            ->assertJsonPath('message', 'Le fichier photo recu ne peut pas peser plus de 400 kilo-octets.');

        $this->assertNull(Depense::findOrFail($id)->recu_path);

        // Pile à la borne : accepté (comme `max:400` du web).
        $borne = $this->png();
        $borne .= str_repeat("\0", RecuDepenseService::TAILLE_MAX_KO * 1024 - strlen($borne));
        $this->assertSame(RecuDepenseService::TAILLE_MAX_KO * 1024, strlen($borne));
        $this->deposer($this->depenseDuPoste(), $borne)->assertOk();
    }

    #[Test]
    public function une_empreinte_annoncee_differente_refuse_le_fichier_altere(): void
    {
        $id = $this->depenseDuPoste();

        $this->deposer($id, $this->png(), 'image/png', hash('sha256', 'autre chose'))
            ->assertStatus(422)
            ->assertJsonPath('code', 'recu_empreinte');

        $this->assertNull(Depense::findOrFail($id)->recu_path);
    }

    #[Test]
    public function un_fichier_vide_est_refuse(): void
    {
        $this->deposer($this->depenseDuPoste(), '')->assertStatus(422)->assertJsonPath('code', 'recu_invalide');
    }

    #[Test]
    public function une_depense_pas_encore_arrivee_rend_404_sans_rien_consigner(): void
    {
        $this->deposer($this->uuid(), $this->png())
            ->assertNotFound()
            ->assertJsonPath('code', 'depense_inconnue');

        $this->assertSame(0, Journal::query()->where('table_concernee', 'recus_depenses')->count());
    }

    #[Test]
    public function sans_ecriture_sur_m10_le_depot_est_refuse_et_trace(): void
    {
        $id = $this->depenseDuPoste();
        $lecteur = $this->creerUtilisateur('rh');          // M10 = 'L'
        $sansDroit = $this->creerUtilisateur('barman');     // M10 = '-'

        foreach ([$lecteur, $sansDroit] as $utilisateur) {
            $this->deposer($id, $this->png(), 'image/png', null, $utilisateur)
                ->assertForbidden()
                ->assertJsonPath('code', 'droit_manquant');
        }

        $this->assertNull(Depense::findOrFail($id)->recu_path);
        $this->assertGreaterThanOrEqual(2, \App\Shared\Rbac\Models\JournalSecurite::query()->where('type_evenement', 'acces_refuse_rbac')->count());
    }

    #[Test]
    public function le_poste_declare_doit_etre_celui_du_jeton(): void
    {
        $id = $this->depenseDuPoste();
        $this->app['auth']->forgetGuards();
        $jeton = $this->comptable->createToken(self::POSTE)->plainTextToken;

        $this->call('PUT', '/api/v1/sync/depenses/'.$id.'/recu?poste_id=un-autre-poste', [], [], [], $this->entetes($jeton), $this->png())
            ->assertForbidden();

        $this->assertNull(Depense::findOrFail($id)->recu_path);
    }

    #[Test]
    public function la_depense_d_un_autre_poste_ne_recoit_pas_de_recu_d_ici(): void
    {
        $id = $this->depenseDuPoste('poste-autre');

        $this->deposer($id, $this->png())
            ->assertForbidden()
            ->assertJsonPath('code', 'recu_autre_poste');

        $this->assertNull(Depense::findOrFail($id)->recu_path);
    }

    #[Test]
    public function l_interrupteur_du_serveur_reinitialise_refuse_une_generation_perimee(): void
    {
        $id = $this->depenseDuPoste();
        $this->app['auth']->forgetGuards();
        $jeton = $this->comptable->createToken(self::POSTE)->plainTextToken;

        $this->call('PUT', '/api/v1/sync/depenses/'.$id.'/recu?poste_id='.self::POSTE.'&generation=00000000-0000-0000-0000-000000000000', [], [], [], $this->entetes($jeton), $this->png())
            ->assertStatus(409)
            ->assertJsonPath('code', 'generation_perimee');

        $this->assertNull(Depense::findOrFail($id)->recu_path);
    }

    #[Test]
    public function le_telechargement_rend_le_fichier_et_son_empreinte_a_la_demande(): void
    {
        $id = $this->depenseDuPoste();
        $png = $this->png();
        $this->deposer($id, $png)->assertOk();

        $reponse = $this->telecharger($id);
        $reponse->assertOk()
            ->assertHeader('X-Recu-Sha256', hash('sha256', $png))
            ->assertHeader('Content-Type', 'image/png');
        $this->assertSame($png, $reponse->getContent());
        $this->assertSame('nosniff', $reponse->headers->get('X-Content-Type-Options'));

        // Lecture seule sur M10 suffit ; aucun droit sur M10 : refusé.
        $this->telecharger($id, $this->creerUtilisateur('rh'))->assertOk();
        $this->telecharger($id, $this->creerUtilisateur('barman'))->assertForbidden();
    }

    #[Test]
    public function une_depense_sans_recu_ou_inconnue_rend_404_au_telechargement(): void
    {
        $this->telecharger($this->depenseDuPoste())->assertNotFound()->assertJsonPath('code', 'recu_introuvable');
        $this->telecharger($this->uuid())->assertNotFound();
    }

    #[Test]
    public function un_recu_joint_par_l_ecran_web_avant_l_empreinte_se_telecharge_avec_son_empreinte_calculee(): void
    {
        $id = $this->depenseDuPoste();
        $png = $this->png();
        Storage::disk('public')->put('recus_depenses/ancien.png', $png);
        Depense::query()->whereKey($id)->update(['recu_path' => 'recus_depenses/ancien.png']);

        $this->telecharger($id)->assertOk()->assertHeader('X-Recu-Sha256', hash('sha256', $png));

        // Et le même fichier redéposé n'est PAS accepté comme « le même » : le
        // serveur ne connaît pas son empreinte, un reçu ne se remplace pas.
        $this->deposer($id, $png)->assertStatus(409);
    }

    #[Test]
    public function la_descente_donne_la_reference_du_recu_jamais_le_chemin_ni_le_fichier(): void
    {
        $id = $this->depenseDuPoste();
        $png = $this->png();
        $this->deposer($id, $png)->assertOk();
        $sansRecu = $this->depenseDuPoste();
        $this->travel(\App\Shared\Sync\Services\CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();

        $elements = $this->descente();
        $avec = collect($elements)->firstWhere('id', $id);
        $sans = collect($elements)->firstWhere('id', $sansRecu);

        $this->assertSame(['sha256' => hash('sha256', $png), 'taille' => strlen($png), 'type' => 'image/png'], $avec['donnees']['recu']);
        $this->assertNull($sans['donnees']['recu']);
        $this->assertArrayNotHasKey('recu_path', $avec['donnees']);
        $this->assertStringNotContainsString('recus_depenses', json_encode($avec, JSON_THROW_ON_ERROR));
    }

    #[Test]
    public function la_comptable_voit_le_depot_au_journal_de_reception_avec_sa_cause(): void
    {
        $id = $this->depenseDuPoste();
        $this->deposer($id, "pas une image\n")->assertStatus(422);

        $ligne = Journal::query()->where('table_concernee', 'recus_depenses')->sole();
        $this->assertSame('recu_invalide', $ligne->code_motif);
        $this->assertStringContainsString('Le champ photo recu doit être une image.', (string) $ligne->cause);

        $service = app(\App\Shared\Sync\Services\CorrectionReceptionService::class);
        $this->assertContains('recus_depenses', $service->tablesVisibles($this->comptable) ?? ['recus_depenses']);
        $this->assertFalse($service->peutCorriger($ligne));
        $this->assertSame('Reçu de dépense', app(\App\Shared\Sync\Services\JournalReceptionService::class)->libelleTable('recus_depenses'));
    }

    #[Test]
    public function la_saisie_web_pose_aussi_l_empreinte_du_recu(): void
    {
        $this->actingAs($this->comptable);
        $png = $this->png();
        Storage::disk('public')->put('recus_depenses/web.png', $png);

        $depense = app(\App\Domain\Depenses\Services\DepenseService::class)->enregistrer([
            'date_transaction' => '2026-10-12',
            'tresorerie' => 'caisse',
            'libelle' => 'Marché web',
            'centre_id' => \App\Domain\Comptabilite\Models\CentreCout::where('libelle', 'Structure')->value('id'),
            'recu_path' => 'recus_depenses/web.png',
            'recu_sha256' => hash('sha256', $png),
            'recu_taille' => strlen($png),
            'recu_type' => 'image/png',
            'lignes' => [['compte_charge' => '6011', 'montant' => '5000', 'libelle' => 'Tomates']],
        ], $this->comptable);

        $this->assertSame(hash('sha256', $png), $depense->fresh()->recu_sha256);
    }

    // ------------------------------------------------------------------

    /** Une dépense poussée par `/sync` depuis [poste] : la dépense existe, avec son origine. */
    private function depenseDuPoste(string $poste = self::POSTE): string
    {
        $id = $this->uuid();
        $this->pousser([$this->operationDatee('depenses', 'creation', $id, [
            'date_transaction' => '2026-10-12',
            'tresorerie' => 'caisse',
            'libelle' => 'Marché du matin',
            'centre_libelle' => 'Structure',
            'lignes' => [['libelle' => 'Tomates', 'compte_charge' => '6011', 'nature' => 'Tomate', 'famille' => 'Marché', 'montant' => 12500]],
        ], '2026-10-12T09:00:00+00:00')], $this->comptable, $poste)
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        return $id;
    }

    /** @return TestResponse<\Illuminate\Http\Response> */
    private function deposer(string $depense, string $octets, string $type = 'image/png', ?string $empreinte = null, ?User $utilisateur = null, string $poste = self::POSTE): TestResponse
    {
        $this->app['auth']->forgetGuards();
        $jeton = ($utilisateur ?? $this->comptable)->createToken($poste)->plainTextToken;
        $serveur = [
            'CONTENT_TYPE' => $type,
            'HTTP_X_RECU_SHA256' => $empreinte ?? hash('sha256', $octets),
            'HTTP_AUTHORIZATION' => 'Bearer '.$jeton,
            'HTTP_ACCEPT' => 'application/json',
        ];

        return $this->call('PUT', '/api/v1/sync/depenses/'.$depense.'/recu?poste_id='.$poste, [], [], [], $serveur, $octets);
    }

    /** @return TestResponse<\Illuminate\Http\Response> */
    private function telecharger(string $depense, ?User $utilisateur = null): TestResponse
    {
        $this->app['auth']->forgetGuards();
        $jeton = ($utilisateur ?? $this->comptable)->createToken(self::POSTE)->plainTextToken;

        return $this->withToken($jeton)->get('/api/v1/sync/depenses/'.$depense.'/recu?poste_id='.self::POSTE);
    }

    /** @return array<string, string> */
    private function entetes(string $jeton): array
    {
        return ['CONTENT_TYPE' => 'image/png', 'HTTP_AUTHORIZATION' => 'Bearer '.$jeton, 'HTTP_ACCEPT' => 'application/json'];
    }

    /** @return list<array<string, mixed>> */
    private function descente(): array
    {
        $this->app['auth']->forgetGuards();
        $jeton = $this->creerUtilisateur('administrateur')->createToken('poste-windows-2')->plainTextToken;
        $elements = [];
        $curseur = null;

        do {
            $reponse = $this->withToken($jeton)
                ->getJson('/api/v1/referentiels?'.http_build_query(array_filter(['poste_id' => 'poste-windows-2', 'depuis' => $curseur, 'limite' => 500])))
                ->assertOk();
            $elements = [...$elements, ...$reponse->json('data.elements')];
            $curseur = $reponse->json('meta.curseur');
        } while (! $reponse->json('meta.complet'));

        return array_values(array_filter($elements, static fn (array $e): bool => $e['table'] === 'depenses'));
    }

    private function png(): string
    {
        $image = imagecreatetruecolor(8, 8);
        ob_start();
        imagepng($image);
        $octets = (string) ob_get_clean();

        return $octets;
    }

    private function jpeg(): string
    {
        $image = imagecreatetruecolor(8, 8);
        ob_start();
        imagejpeg($image);

        return (string) ob_get_clean();
    }

    private function gif(): string
    {
        $image = imagecreatetruecolor(8, 8);
        ob_start();
        imagegif($image);

        return (string) ob_get_clean();
    }
}

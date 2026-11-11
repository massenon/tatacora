<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Models\User;
use App\Shared\Parametres\Models\DepotImageDocument;
use App\Shared\Parametres\Services\ApparenceEtablissementService;
use App\Shared\Sync\Gestionnaires\GestionnaireImagesDocument;
use App\Shared\Sync\Support\OperationsSensibles;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Le DÉPÔT et le RETRAIT de la signature et du cachet depuis un poste (11/11/2026, décision du PO) :
 * même service que l'écran web, mêmes validations, idempotence sur l'identifiant du geste, aucun
 * droit du compte d'appairage jugé (liste `OperationsSensibles` inchangée).
 */
final class ImagesDocumentSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $barman;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake(ApparenceEtablissementService::DISQUE);
        $this->seed(RolePermissionSeeder::class);
        // Le compte du jeton est un BARMAN : aucun module PARAM, et pourtant accepté.
        $this->barman = $this->creerUtilisateur('barman');
    }

    private function png(int $cote = 8): string
    {
        $toile = imagecreatetruecolor($cote, $cote);
        imagefill($toile, 0, 0, (int) imagecolorallocate($toile, 10, 80, 160));
        ob_start();
        imagepng($toile);

        return (string) ob_get_clean();
    }

    /** @return array<string, mixed> */
    private function depot(string $nature, string $octets, string $mime = 'image/png'): array
    {
        return $this->creation('depots_images_document', $this->uuid(), [
            'nature' => $nature,
            'action' => 'deposer',
            'type_mime' => $mime,
            'octets_base64' => base64_encode($octets),
        ]);
    }

    private function service(): ApparenceEtablissementService
    {
        return app(ApparenceEtablissementService::class);
    }

    #[Test]
    public function un_depot_range_l_image_comme_le_web_et_ne_juge_pas_le_module_du_compte(): void
    {
        $octets = $this->png();

        $this->pousser([$this->depot('signature', $octets)], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.action', 'deposer')
            ->assertJsonPath('resultats.0.empreinte', substr(hash('sha256', $octets), 0, 16));

        // Le fichier est celui que le web range (même service), octets d'origine gardés.
        $this->assertSame($octets, $this->service()->octetsImageDocument('signature'));
        $this->assertNull($this->service()->octetsImageDocument('cachet'));
        $this->assertSame(1, DepotImageDocument::query()->where('nature', 'signature')->count());
    }

    #[Test]
    public function le_remplacement_ne_garde_qu_un_fichier_et_le_retrait_l_efface(): void
    {
        $this->pousser([$this->depot('cachet', $this->png(8))], $this->barman);
        $second = $this->png(16);
        $this->pousser([$this->depot('cachet', $second)], $this->barman);

        $this->assertSame($second, $this->service()->octetsImageDocument('cachet'));
        $this->assertCount(1, Storage::disk('public')->files('apparence'));

        $this->pousser([$this->creation('depots_images_document', $this->uuid(), ['nature' => 'cachet', 'action' => 'retirer'])], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertNull($this->service()->octetsImageDocument('cachet'));
        $this->assertSame([], Storage::disk('public')->files('apparence'));
    }

    #[Test]
    public function un_geste_rejoue_est_accepte_sans_rien_reecrire(): void
    {
        $premier = $this->depot('signature', $this->png(8));
        $this->pousser([$premier], $this->barman);

        // Un autre dépôt passe entre-temps (web ou autre poste)…
        $autre = $this->png(24);
        $this->service()->enregistrerImageDocument('signature', $autre);

        // …puis le premier geste est rejoué sous un NOUVEL uuid_operation (mémoire d'idempotence purgée).
        $rejeu = [...$premier, 'uuid_operation' => $this->uuid()];
        $this->pousser([$rejeu], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.document_deja_enregistre', true);

        $this->assertSame($autre, $this->service()->octetsImageDocument('signature'), 'le rejeu n\'a rien réécrit');
        $this->assertSame(1, DepotImageDocument::query()->count());
    }

    #[Test]
    public function un_fichier_qui_n_est_pas_une_image_est_refuse_meme_annonce_png(): void
    {
        $faux = '%PDF-1.4 ceci n\'est pas une image';

        $this->pousser([$this->depot('signature', $faux)], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.images_document.type_non_admis'));

        $this->assertNull($this->service()->octetsImageDocument('signature'));
        $this->assertSame(0, DepotImageDocument::query()->count());
    }

    #[Test]
    public function le_type_est_lu_des_octets_pas_de_l_annonce_et_gif_n_est_pas_admis(): void
    {
        // PNG réel annoncé « jpeg » : refusé.
        $this->pousser([$this->depot('signature', $this->png(), 'image/jpeg')], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'rejete');

        // GIF réel (une image pour le web, mais hors des trois types de la porte) : refusé.
        $gif = base64_decode('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7', true);
        $this->pousser([$this->depot('signature', (string) $gif, 'image/gif')], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.images_document.type_non_admis'));

        $this->assertNull($this->service()->octetsImageDocument('signature'));
    }

    #[Test]
    public function une_image_de_plus_de_400_ko_est_refusee_a_la_porte(): void
    {
        $gros = $this->png() . str_repeat("\0", GestionnaireImagesDocument::TAILLE_MAX_OCTETS);

        $this->pousser([$this->depot('cachet', $gros)], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.images_document.trop_lourde'));
    }

    #[Test]
    public function nature_geste_et_contenu_illisibles_sont_refuses(): void
    {
        $this->pousser([$this->creation('depots_images_document', $this->uuid(), ['nature' => 'logo', 'action' => 'retirer'])], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.images_document.nature_inconnue'));

        $this->pousser([$this->creation('depots_images_document', $this->uuid(), ['nature' => 'cachet', 'action' => 'effacer'])], $this->barman)
            ->assertJsonPath('resultats.0.motif', __('sync.images_document.action_inconnue'));

        $this->pousser([$this->creation('depots_images_document', $this->uuid(), ['nature' => 'cachet', 'action' => 'deposer', 'octets_base64' => '***pas du base64***'])], $this->barman)
            ->assertJsonPath('resultats.0.motif', __('sync.images_document.contenu_illisible'));
    }

    #[Test]
    public function la_modification_est_refusee_et_la_liste_des_operations_sensibles_n_est_pas_etendue(): void
    {
        $this->assertFalse(array_key_exists('depots_images_document', OperationsSensibles::PAR_TABLE));
        $gestionnaire = app(GestionnaireImagesDocument::class);
        $this->assertSame([], $gestionnaire->modulesRequis([]));
        $this->assertFalse($gestionnaire->accepteModification());
        $this->assertFalse($gestionnaire->accepteSuppression());
    }

    #[Test]
    public function une_image_deposee_depuis_un_poste_descend_vers_un_autre_et_pas_vers_celui_qui_la_connait(): void
    {
        $octets = $this->png(12);
        $this->pousser([$this->depot('signature', $octets)], $this->barman, 'poste-A');
        $empreinte = substr(hash('sha256', $octets), 0, 16);

        // Un AUTRE poste (jeton réel) reçoit les octets…
        $jeton = $this->barman->createToken('poste-B')->plainTextToken;
        $this->withToken($jeton)->getJson('/api/v1/sync/apparence-documents?poste_id=poste-B')
            ->assertOk()
            ->assertJsonPath('data.signature.empreinte', $empreinte)
            ->assertJsonPath('data.signature.octets_base64', base64_encode($octets))
            ->assertJsonPath('data.cachet', null);

        // …et celui qui l'a déposée, forte de son empreinte, n'en reçoit pas les octets : pas de boucle.
        $this->app['auth']->forgetGuards();
        $this->withToken($this->barman->createToken('poste-A')->plainTextToken)
            ->getJson('/api/v1/sync/apparence-documents?poste_id=poste-A&signature='.$empreinte)
            ->assertOk()
            ->assertJsonPath('data.signature.empreinte', $empreinte)
            ->assertJsonPath('data.signature.octets_base64', null);
    }
}

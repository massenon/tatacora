<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Hebergement\Models\CanalReservation;
use App\Domain\Restaurant\Models\Recette;
use App\Models\User;
use App\Shared\Sync\Services\CatalogueDescendantService;
use App\Shared\Sync\Services\RegistreSynchronisation;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Les canaux de réservation en synchronisation (21/10/2026, « tout au
 * complet ») : ajout, renommage, désactivation poussés par un poste, par
 * `CanalReservationService` ; le nom est la clé naturelle ; la descente les
 * sert AVANT les réservations qui les citent, désactivés compris.
 */
final class CanauxReservationSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-21 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->admin = $this->creerUtilisateur('administrateur');
    }

    #[Test]
    public function le_canal_du_poste_nait_sous_son_uuid_se_renomme_et_se_desactive(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->creation('canaux_reservation', $id, ['nom' => 'Agence Sahel', 'actif' => true])], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('Agence Sahel', CanalReservation::findOrFail($id)->nom);
        $this->assertTrue(CanalReservation::findOrFail($id)->actif);

        $this->travel(1)->minutes();
        $this->pousser([$this->operation('canaux_reservation', 'modification', $id, [
            'nom' => 'Agence du Sahel', 'ancien_nom' => 'Agence Sahel', 'actif' => true,
        ])], $this->admin)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('Agence du Sahel', CanalReservation::findOrFail($id)->nom);

        $this->travel(1)->minutes();
        $this->pousser([$this->operation('canaux_reservation', 'modification', $id, [
            'nom' => 'Agence du Sahel', 'actif' => false,
        ])], $this->admin)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertFalse(CanalReservation::findOrFail($id)->actif);

        // La réactivation est le même geste, dans l'autre sens.
        $this->travel(1)->minutes();
        $this->pousser([$this->operation('canaux_reservation', 'modification', $id, [
            'nom' => 'Agence du Sahel', 'actif' => true,
        ])], $this->admin)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertTrue(CanalReservation::findOrFail($id)->actif);
        $this->assertSame(1, CanalReservation::count());
    }

    #[Test]
    public function le_meme_nom_saisi_sur_deux_postes_fusionne_sans_casse(): void
    {
        $premier = $this->uuid();
        $this->pousser([$this->creation('canaux_reservation', $premier, ['nom' => 'Booking.com'])], $this->admin);

        $this->pousser([$this->creation('canaux_reservation', $this->uuid(), ['nom' => 'booking.COM'])], $this->admin, 'poste-b')
            ->assertJsonPath('resultats.0.fusionne_avec', $premier);

        $this->assertSame(1, CanalReservation::count());
    }

    /**
     * Un canal du jeu initial, connu du poste sous SON identifiant (aligné par
     * le nom à la descente) : le renommer ne crée pas un second canal.
     */
    #[Test]
    public function renommer_un_canal_aligne_par_le_nom_renomme_celui_du_serveur(): void
    {
        $serveur = CanalReservation::create(['nom' => 'Physique', 'actif' => true]);
        $local = $this->uuid();

        $this->pousser([$this->operation('canaux_reservation', 'modification', $local, [
            'nom' => 'Comptoir', 'ancien_nom' => 'Physique', 'actif' => true,
        ])], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.fusionne_avec', $serveur->id);

        $this->assertSame(1, CanalReservation::count());
        $this->assertSame('Comptoir', $serveur->fresh()->nom);
    }

    #[Test]
    public function les_refus_du_service_et_du_droit_sont_rendus(): void
    {
        $this->pousser([$this->creation('canaux_reservation', $this->uuid(), ['nom' => '   '])], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'rejete');

        // Sans droit d'écriture sur Paramètres : refusé (le module PARAM).
        $receptionniste = $this->creerUtilisateur('receptionniste');
        $this->pousser([$this->creation('canaux_reservation', $this->uuid(), ['nom' => 'Salon'])], $receptionniste)
            ->assertJsonPath('resultats.0.statut', 'rejete');

        $this->assertSame(0, CanalReservation::count());
    }

    #[Test]
    public function le_registre_connait_les_canaux_en_modification_acceptee(): void
    {
        $gestionnaire = app(RegistreSynchronisation::class)->pour('canaux_reservation');

        $this->assertTrue($gestionnaire->accepteModification());
        $this->assertSame('PARAM', $gestionnaire->module());
        $this->assertSame('C', $gestionnaire->niveauRequis());
    }

    /**
     * La descente : les canaux AVANT les réservations, désactivés compris
     * (marqués `actif: false`, jamais retirés), et pour TOUT compte qui
     * synchronise — le droit de lire Paramètres n'est pas exigé.
     */
    #[Test]
    public function la_descente_sert_les_canaux_avant_les_reservations_desactives_compris(): void
    {
        $ordre = array_keys(CatalogueDescendantService::COLONNES);
        $this->assertLessThan(array_search('reservations', $ordre, true), array_search('canaux_reservation', $ordre, true));

        CanalReservation::create(['nom' => 'Direct', 'actif' => true]);
        CanalReservation::create(['nom' => 'Ancien canal', 'actif' => false]);

        $caissier = $this->creerUtilisateur('barman');
        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        Sanctum::actingAs($caissier);
        $reponse = $this->getJson('/api/v1/referentiels?poste_id=poste-1&limite=500')->assertOk();

        $canaux = collect($reponse->json('data.elements'))
            ->where('table', 'canaux_reservation')
            ->keyBy(fn (array $e): string => $e['donnees']['nom']);

        $this->assertSame(['Ancien canal', 'Direct'], $canaux->keys()->sort()->values()->all());
        $this->assertTrue($canaux['Direct']['actif']);
        $this->assertFalse($canaux['Ancien canal']['actif']);
        $this->assertSame(['nom'], array_keys($canaux['Direct']['donnees']));
    }

    /**
     * La marque « composition provisoire » descend avec la fiche (booléen), et
     * elle TOMBE quand la composition est réenregistrée — par le seul auteur,
     * `CompositionRecetteService`, y compris quand le geste vient d'un poste.
     */
    #[Test]
    public function la_marque_provisoire_de_la_fiche_descend_et_tombe_avec_la_composition_poussee(): void
    {
        $recette = Recette::create(['libelle' => 'Riz sauce', 'cout_matiere_calcule' => '0.00']);
        $recette->forceFill([Recette::PROVISOIRE => true])->save();

        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        Sanctum::actingAs($this->admin);
        $element = collect($this->getJson('/api/v1/referentiels?poste_id=poste-1&limite=500')->assertOk()->json('data.elements'))
            ->firstWhere('id', $recette->id);
        $this->assertTrue($element['donnees']['composition_provisoire']);

        // Le poste enregistre la composition relevée : la marque tombe.
        $article = \App\Domain\Stocks\Models\Article::create([
            'libelle' => 'Riz', 'categorie' => 'Épicerie', 'unite_mesure' => 'kg',
            'seuil_alerte' => '1.00', 'seuil_reappro' => '0.00', 'suivi' => true,
        ]);
        $this->travel(1)->minutes();
        $this->pousser([$this->operation('recettes', 'modification', $recette->id, [
            'lignes' => [['article_id' => $article->id, 'quantite_unitaire' => '0.150']],
        ])], $this->admin)->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertFalse((bool) $recette->fresh()->composition_provisoire);

        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        $element = collect($this->getJson('/api/v1/referentiels?poste_id=poste-1&limite=500')->assertOk()->json('data.elements'))
            ->firstWhere('id', $recette->id);
        $this->assertFalse($element['donnees']['composition_provisoire']);
    }
}

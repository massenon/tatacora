<?php

declare(strict_types=1);

namespace Tests\Feature\Sync\Concerns;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\MouvementStock;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Sync\Models\DeduplicationSynchronisation;
use App\Shared\Sync\Services\SynchronisationService;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;

/**
 * Le décor MINIMAL d'un document synchronisé (lot S3, 15/10/2026) : la
 * matrice des rôles, le référentiel comptable (sans lui, aucune pièce — donc
 * aucune vente ni dépense), un bar et une cuisine, une bière et un plat au
 * catalogue serveur, du stock.
 *
 * L'horloge est figée au 15/10/2026 : l'exercice semé est celui de l'année
 * courante, et les dates métier testées doivent y tomber quel que soit le
 * jour où la suite tourne.
 *
 * @mixin \Tests\TestCase
 */
trait PrepareLesDocuments
{
    use PousseDesOperations;

    protected PointStockage $bar;

    protected PointStockage $cuisine;

    protected Article $articleBiere;

    protected Article $articleRiz;

    protected CarteBoisson $biere;

    protected Plat $platRiz;

    protected function preparerLeDecor(): void
    {
        $this->travelTo('2026-10-15 12:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);

        $this->bar = PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);
        $this->cuisine = PointStockage::create(['libelle' => 'Cuisine', 'type' => 'cuisine']);

        $this->articleBiere = $this->articleDeTest('Bière 65cl', 'bouteille');
        $this->articleRiz = $this->articleDeTest('Riz', 'kg');

        $this->biere = CarteBoisson::create([
            'article_id' => $this->articleBiere->id,
            'libelle' => 'Béninoise 65cl',
            'categorie' => 'locale',
            'prix_vente' => '1000.00',
            'unites_vendables_par_unite_stock' => '1.0000',
        ]);

        $recette = Recette::create(['libelle' => 'Riz sauce', 'cout_matiere_calcule' => '0.00']);
        $recette->ingredients()->attach([$this->articleRiz->id => ['quantite_unitaire' => '0.250']]);

        $menu = Menu::create(['libelle' => 'Carte principale', 'type' => 'local']);
        $this->platRiz = Plat::create([
            'menu_id' => $menu->id,
            'recette_id' => $recette->id,
            'libelle' => 'Riz sauce arachide',
            'prix_vente' => '2500.00',
        ]);

        // Le stock initial a un auteur (RG-15) : le gérant du site.
        $this->actingAs($this->creerUtilisateur('gerant'));
        app(MouvementStockService::class)->entree($this->articleBiere->id, $this->bar->id, '48.00', 'Stock initial');
        app(MouvementStockService::class)->entree($this->articleRiz->id, $this->cuisine->id, '20.00', 'Stock initial');
    }

    protected function articleDeTest(string $libelle, string $unite): Article
    {
        return Article::create([
            'libelle' => $libelle,
            'categorie' => 'test',
            'unite_mesure' => $unite,
            'seuil_alerte' => '0.00',
            'seuil_reappro' => '10.00',
            'cout_moyen_pondere' => '500.0000',
        ]);
    }

    /** Un exercice de plus, ouvert — pour une pièce datée d'une autre année. */
    protected function ouvrirExercice(int $annee): void
    {
        ExerciceComptable::firstOrCreate(
            ['annee' => $annee],
            ['date_debut' => $annee . '-01-01', 'date_fin' => $annee . '-12-31', 'statut' => 'ouvert'],
        );
    }

    protected function toleranceDeReception(string $pourcentage): void
    {
        ParametreSysteme::create([
            'cle' => 'tolerance_reception_pct',
            'valeur' => $pourcentage,
            'description' => 'Tolérance de réception (RG-10) — posée par le test.',
        ]);
    }

    /**
     * La mémoire d'idempotence est VIDÉE comme la purge des 30 jours le
     * ferait : un rejeu ultérieur ne peut plus s'appuyer sur elle, seul le
     * service (UUID du document) protège encore du doublon.
     */
    protected function purgerLaMemoireDIdempotence(): void
    {
        DeduplicationSynchronisation::query()->update(['date_traitement' => now()->subDays(31)]);
        app(SynchronisationService::class)->purgerDeduplication();
        $this->assertSame(0, DeduplicationSynchronisation::count());
    }

    /**
     * Une opération rejouée sous un NOUVEL `uuid_operation`, même entité.
     *
     * @param  array<string, mixed>  $operation
     * @return array<string, mixed>
     */
    protected function nouvelleTentative(array $operation): array
    {
        return [...$operation, 'uuid_operation' => $this->uuid()];
    }

    /**
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    protected function operationDatee(string $table, string $type, string $id, array $payload, string $horodatage): array
    {
        return [...$this->operation($table, $type, $id, $payload), 'horodatage_client' => $horodatage];
    }

    protected function nombreDePieces(string $libelle): int
    {
        return EcritureComptable::query()->where('libelle', $libelle)->distinct()->count('numero_piece');
    }

    protected function nombreDeMouvements(string $articleId, string $type): int
    {
        return MouvementStock::query()->where('article_id', $articleId)->where('type_mouvement', $type)->count();
    }
}

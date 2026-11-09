<?php

declare(strict_types=1);

namespace App\Shared\ImportExport\Services;

use App\Domain\Achats\Services\ReferentielFournisseurService;
use App\Domain\Bar\Services\CarteBoissonService;
use App\Domain\Crm\Services\EnregistrementClientService;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\SejourService;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Restaurant\Services\CartePlatMenuService;
use App\Domain\Restaurant\Services\RapprochementPlatsStockService;
use App\Domain\Restaurant\Services\ReferentielRecetteService;
use App\Domain\Restaurant\Support\DescriptionPlat;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\ReferentielArticleService;
use App\Domain\Tourisme\Models\Circuit;
use App\Domain\Vehicules\Models\Vehicule;
use App\Shared\ImportExport\Data\ModuleImport;
use App\Shared\ImportExport\Models\JournalImport;
use Illuminate\Support\Facades\DB;
use RuntimeException;
use Throwable;

/**
 * Application d'un import CONTRÔLÉ — la moitié « appliquer » du maître
 * (`import-export-engine.js` §2, `appliquer`), 02/09/2026.
 *
 * ## AUCUN IMPORT PARTIEL — une transaction unique
 *
 * Règle du maître (`import-export.html` l.135-139) : « Tant qu'une erreur
 * subsiste, rien n'entre en base. Importer "ce qui passe" laisserait un jeu
 * incomplet dont personne ne saurait dire ce qui manque. » Tout le lot passe
 * dans UNE transaction ; le refus d'un service de domaine sur une seule ligne
 * — même après un contrôle vert, la base a pu bouger entre-temps — annule
 * TOUT, historique compris, et nomme la ligne fautive.
 *
 * ⚠ L'écran M6 Stocks importe autrement (ligne fautive NOMMÉE, lot conservé,
 * `m6-stocks.html` l.487-490) : ce sont les règles de DEUX écrans distincts
 * du maître, pas une divergence à réconcilier.
 *
 * ## Chaque écriture passe par le chemin du domaine
 *
 * Les modules qui ont un `Service` de création l'appellent (M3, M5, M4, M6,
 * M7) ; M1, M8 et M9 écrivent les MÊMES attributs que leur écran PWA
 * (`Hebergement::enregistrerUnite()`, `Locations::enregistrerVehicule()`,
 * `Departs::enregistrerPrestation()`) — référentiels sans verrou RG, comme
 * ces écrans. Jamais un `DB::table()` sur une table gardée par une RG.
 */
class ImportReferentielsService
{
    /**
     * La phrase du rapprochement plats ↔ stock du DERNIER import m4 (« 81 plats
     * rapprochés du stock… »), `null` pour tout autre module. Lue par l'écran
     * pour compléter son message de bilan.
     */
    public ?string $bilanRapprochement = null;

    /** @var list<Plat> les plats créés par le lot m4 en cours */
    private array $platsCrees = [];

    /** @var array<string, array{point_id: string|null, seuil: string|null, valeur: string|null}> */
    private array $parametresPlats = [];

    /**
     * @param  list<array<string, mixed>>  $lignes  lignes CONVERTIES par le contrôle
     * @return int nombre de lignes importées
     *
     * @throws RuntimeException lot refusé — rien n'a été écrit
     */
    public function appliquer(ModuleImport $module, array $lignes): int
    {
        if ($lignes === []) {
            throw new RuntimeException(__('imports.controle.aucune_ligne'));
        }

        $this->bilanRapprochement = null;
        $this->platsCrees = [];
        $this->parametresPlats = [];

        return DB::transaction(function () use ($module, $lignes): int {
            foreach ($lignes as $ligne) {
                try {
                    $this->importerLigne($module, $ligne);
                } catch (Throwable $refus) {
                    // Le rollback de la transaction efface TOUT le lot : la
                    // ligne fautive est nommée avec le mot du domaine, jamais
                    // reformulé.
                    throw new RuntimeException(__('imports.controle.refus_service', [
                        'ligne' => (string) ($ligne['_ligne'] ?? '?'),
                        'element' => (string) ($ligne[$module->identifiant] ?? '?'),
                        'raison' => $refus->getMessage(),
                    ]), 0, $refus);
                }
            }

            // Comme au bar, chaque plat se relie à l'article de stock de même nom
            // (point de la colonne, Cuisine par défaut) ; l'article est CRÉÉ s'il
            // manque (09/11/2026, PO : « rendre le plat vendable du stock »), sans
            // jamais écraser un point, une valeur d'achat ou un seuil déjà posés.
            if ($module->cle === 'm4-restaurant') {
                $this->bilanRapprochement = RapprochementPlatsStockService::phrase(
                    app(RapprochementPlatsStockService::class)->rapprocher($this->platsCrees, true, $this->parametresPlats),
                );
            }

            // L'historique s'écrit DANS la transaction : hors d'elle, un
            // rollback laisserait une entrée annonçant un import effacé.
            JournalImport::create([
                'module_cle' => $module->cle,
                'nombre_lignes' => count($lignes),
                'utilisateur_id' => auth()->id(),
                'date_heure' => now(),
            ]);

            return count($lignes);
        });
    }

    /**
     * @param  array<string, mixed>  $ligne
     */
    private function importerLigne(ModuleImport $module, array $ligne): void
    {
        match ($module->cle) {
            'm3-clients' => app(EnregistrementClientService::class)->creer([
                'nom' => (string) $ligne['nom'],
                'prenom' => $ligne['prenom'] ?? null,
                'type_client' => (string) $ligne['type_client'],
                'telephone' => (string) $ligne['telephone'],
                'email' => $ligne['email'] ?? null,
            ]),
            // Mêmes attributs que `Hebergement::enregistrerUnite()` : l'unité
            // entre au parc LIBRE, le statut n'est jamais importé.
            'm1-hebergement' => UniteHebergement::create([
                'numero' => (string) $ligne['numero'],
                'categorie_id' => (string) $ligne['categorie'],
                'statut' => SejourService::STATUT_LIBRE,
            ]),
            'm5-bar' => app(CarteBoissonService::class)->creer([
                'libelle' => (string) $ligne['libelle'],
                'categorie' => (string) $ligne['categorie'],
                'prix_vente' => (string) $ligne['prix_vente'],
                'article_id' => $this->articleDeLaBoisson($ligne),
            ]),
            'm4-restaurant' => $this->importerPlat($ligne),
            'm6-stocks' => $this->importerArticle($ligne),
            'm7-achats' => app(ReferentielFournisseurService::class)->creer([
                'raison_sociale' => (string) $ligne['raison_sociale'],
                'contact' => $ligne['contact'] ?? null,
                'categorie' => $ligne['categorie'] ?? null,
                'conditions_paiement' => $ligne['conditions_paiement'] ?? null,
                'evaluation' => $ligne['evaluation'] ?? null,
            ]),
            // Mêmes attributs que `Locations::enregistrerVehicule()` : un
            // véhicule importé entre au parc DISPONIBLE.
            'm8-vehicules' => Vehicule::create([
                'immatriculation' => (string) $ligne['immatriculation'],
                'categorie' => (string) $ligne['categorie'],
                'annee' => (int) $ligne['annee'],
                'capacite' => $ligne['capacite'] === null ? null : (int) $ligne['capacite'],
                'transmission' => $ligne['transmission'] ?? null,
                'tarif_jour' => (string) $ligne['tarif_jour'],
                'statut' => 'disponible',
            ]),
            // Mêmes attributs que `Departs::enregistrerPrestation()`.
            'm9-tourisme' => Circuit::create([
                'nom' => (string) $ligne['nom'],
                'theme' => (string) $ligne['theme'],
                'zone' => (string) $ligne['zone'],
                'duree' => (string) $ligne['duree'],
                'prix' => (string) $ligne['prix'],
                'capacite_max' => (int) $ligne['capacite_max'],
            ]),
            default => throw new RuntimeException(__('imports.controle.module_inconnu')),
        };
    }

    /**
     * Un article de stock (m6). Seuil facultatif (vide = 0), valeur d'achat
     * FACULTATIVE : posée comme valeur de référence, jamais une quantité ni un
     * mouvement ; vide, l'article n'a PAS de valeur d'achat (« — »).
     *
     * @param  array<string, mixed>  $ligne
     */
    private function importerArticle(array $ligne): void
    {
        $service = app(ReferentielArticleService::class);

        $article = $service->creer([
            'libelle' => (string) $ligne['libelle'],
            'categorie' => (string) $ligne['categorie'],
            'unite_mesure' => (string) $ligne['unite_mesure'],
            'seuil_alerte' => (string) ($ligne['seuil_alerte'] ?? '0'),
            // Le mode de suivi n'est pas une colonne d'import ici (il
            // l'est sur l'écran M6, qui a son propre modèle) : le défaut
            // du schéma, `permanent`, décrit le comportement habituel.
            'suivi' => 'permanent',
            'point_stockage_id' => $this->pointDeLArticle($ligne['point_stockage'] ?? null),
        ]);

        $service->completer($article, null, isset($ligne['valeur_achat']) ? (string) $ligne['valeur_achat'] : null);
    }

    /**
     * L'article de stock d'une boisson (m5). Renseigné : celui de la colonne.
     * Vide : l'article de MÊME NOM (sans casse ni accents), créé s'il manque —
     * au point de la colonne, sinon au Bar quand il existe. Un article repris
     * n'est que COMPLÉTÉ (point vide, valeur d'achat vide), jamais écrasé.
     *
     * @param  array<string, mixed>  $ligne
     */
    private function articleDeLaBoisson(array $ligne): string
    {
        $service = app(ReferentielArticleService::class);
        $point = $this->pointDeLArticle($ligne['point_stockage'] ?? null);
        $valeur = isset($ligne['valeur_achat']) ? (string) $ligne['valeur_achat'] : null;

        if (($ligne['article'] ?? null) !== null) {
            $article = Article::findOrFail((string) $ligne['article']);
            $service->completer($article, $point, $valeur);

            return (string) $article->id;
        }

        $libelle = (string) $ligne['libelle'];
        $cle = RapprochementPlatsStockService::cle($libelle);
        $article = Article::query()->where('actif', true)->where('suivi', 'permanent')->orderBy('libelle')->get()
            ->first(static fn (Article $a): bool => RapprochementPlatsStockService::cle((string) $a->libelle) === $cle);

        if ($article === null) {
            $article = $service->creer([
                'libelle' => $libelle,
                'categorie' => 'Boissons',
                'unite_mesure' => 'unité',
                'seuil_alerte' => (string) ($ligne['seuil_alerte'] ?? '0'),
                'suivi' => 'permanent',
                'point_stockage_id' => $point ?? PointStockage::query()->where('type', 'bar')->orderBy('libelle')->value('id'),
            ]);
        }

        $service->completer($article, $point, $valeur);

        return (string) $article->id;
    }

    /**
     * Le point d'un article importé : « Cuisine » encore absent est créé ici,
     * par le chemin du domaine (voir `ControleImportService`).
     */
    private function pointDeLArticle(mixed $point): ?string
    {
        if ($point === ControleImportService::POINT_CUISINE_A_CREER) {
            return (string) app(RapprochementPlatsStockService::class)->assurerLePointCuisine()->id;
        }

        return $point === null ? null : (string) $point;
    }

    /** Le menu qui reçoit les plats importés sans menu — celui que crée `RestaurantSeeder`. */
    public const MENU_DEFAUT = 'Carte du restaurant';

    /**
     * Un plat de la carte. Menu, fiche et prix sont FACULTATIFS à l'import :
     *
     *  - menu vide → le menu `MENU_DEFAUT`, créé s'il n'existe pas ;
     *  - fiche vide → une fiche du NOM du plat, sans ingrédient et marquée
     *    « composition provisoire » : la composition (donc le stock consommé)
     *    s'ajoute après, depuis « Fiches techniques ». Tant qu'elle est vide,
     *    le plat SE VEND, sans aucun mouvement de stock (décision du PO du
     *    30/10/2026 : « le stock s'ajoute après ») — l'ancien refus au comptoir
     *    (`RecetteManquanteException`) est levé ;
     *  - description vide → aucune (colonne facultative, 500 caractères) ;
     *  - prix vide → 0 avec la marque PROVISOIRE (plat « sur commande »).
     *
     * @param  array<string, mixed>  $ligne
     */
    private function importerPlat(array $ligne): void
    {
        $libelle = (string) $ligne['libelle'];
        $prix = $ligne['prix_vente'] ?? null;

        $menuId = $ligne['menu'] ?? null;

        if ($menuId === null) {
            $menu = Menu::query()->where('libelle', self::MENU_DEFAUT)->first()
                ?? app(CartePlatMenuService::class)->creerMenu(['libelle' => self::MENU_DEFAUT, 'type' => 'local']);
            $menuId = $menu->id;
        }

        $recetteId = $ligne['recette'] ?? null;

        if ($recetteId === null) {
            $recetteId = app(ReferentielRecetteService::class)->creer([
                'libelle' => $libelle,
                Recette::PROVISOIRE => true,
            ])->id;
        }

        $plat = app(CartePlatMenuService::class)->creerPlat([
            'libelle' => $libelle,
            'categorie' => (string) $ligne['categorie'],
            'description' => DescriptionPlat::normaliser($ligne['description'] ?? null),
            'prix_vente' => $prix === null ? '0' : (string) $prix,
            'prix_provisoire' => $prix === null,
            'menu_id' => (string) $menuId,
            'recette_id' => (string) $recetteId,
        ]);

        $this->platsCrees[] = $plat;
        $this->parametresPlats[(string) $plat->id] = [
            'point_id' => $this->pointDeLArticle($ligne['point_stockage'] ?? null),
            'seuil' => isset($ligne['seuil_alerte']) ? (string) $ligne['seuil_alerte'] : null,
            'valeur' => isset($ligne['valeur_achat']) ? (string) $ligne['valeur_achat'] : null,
        ];
    }
}

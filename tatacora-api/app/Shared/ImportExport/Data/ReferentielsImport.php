<?php

declare(strict_types=1);

namespace App\Shared\ImportExport\Data;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Stocks\Models\Article;
use Illuminate\Support\Facades\DB;

/**
 * Le registre FERMÉ des modules importables par CSV — écran Import & Export.
 *
 * Maître : `import-export-engine.js` §1 (`REFERENTIELS`). Le maître déclare
 * huit modules ; les huit sont portés, mais **les colonnes suivent le SCHÉMA
 * RÉEL et les services de domaine qui écrivent**, jamais la liste du
 * prototype quand elle invente des champs sans colonne (02/09/2026) :
 *
 *  - M3 : `clients` n'a ni `ville` ni `pays` — retirées ; `type_client` est
 *    l'énumération de la base (`structure`, pas « Société » — le piège des
 *    deux registres de types de client est documenté au CLAUDE.md).
 *  - M1 : pas de `nom`, `tarif_base` ni `equipements` par unité (le tarif vit
 *    sur la catégorie) ; `statut` N'EST PAS importable — l'unité entre
 *    `libre`, le cycle appartient à `SejourService` et à l'archivage, un
 *    statut importé serait un second écrivain du cycle.
 *  - M5 : `article` (lien de stock) est ajouté — `cartes_boisson.article_id`
 *    est NOT NULL (RG-05), le maître l'omettait.
 *  - M4 : `menu` et `recette` sont ajoutés (colonnes NOT NULL) ;
 *    « Disponible » retiré — la disponibilité vit dans
 *    `indisponibilites_carte`, jamais en colonne de la carte.
 *  - M7 : `fournisseurs` n'a ni téléphone, ni email, ni IFU en colonnes —
 *    les champs réels (`contact`, `conditions_paiement`, `evaluation`) font foi.
 *  - M8 : pas de colonne « Désignation » ; les catégories sont l'énumération
 *    de la base (`voiture`…), pas la liste du prototype (« Berline »…).
 *
 * Les listes fermées ne sont JAMAIS recopiées ici : elles sont lues du
 * registre qui fait déjà foi ailleurs — l'énumération de la colonne pour les
 * `enum` (même dérivation que `Departs::themesDuCatalogue()` et
 * `Locations::categoriesDuParc()`), les constantes de l'écran M6 pour les
 * catégories et unités d'articles (`Stocks::CATEGORIES`/`UNITES`, maître
 * `m6-stocks.html` l.117-119). Un référentiel a UN SEUL AUTEUR (PA-160/161).
 */
final class ReferentielsImport
{
    /** @var array<string, list<string>> cache de lecture des énumérations */
    private static array $enums = [];

    /**
     * @return list<ModuleImport>
     */
    public static function definitions(): array
    {
        return [
            self::clients(),
            self::unitesHebergement(),
            self::carteBar(),
            self::carteRestaurant(),
            self::articlesStock(),
            self::fournisseurs(),
            self::vehicules(),
            self::circuits(),
        ];
    }

    public static function parCle(string $cle): ?ModuleImport
    {
        foreach (self::definitions() as $module) {
            if ($module->cle === $cle) {
                return $module;
            }
        }

        return null;
    }

    // ------------------------------------------------------------- modules

    private static function clients(): ModuleImport
    {
        $t = self::textes('m3_clients');

        return new ModuleImport(
            cle: 'm3-clients',
            module: 'M3',
            nom: $t['nom'],
            description: $t['description'],
            identifiant: 'nom',
            colonnes: [
                new ColonneImport('nom', $t['colonnes']['nom']['libelle'], true, 'texte', exemple: $t['colonnes']['nom']['exemple']),
                new ColonneImport('prenom', $t['colonnes']['prenom']['libelle'], false, 'texte', exemple: $t['colonnes']['prenom']['exemple']),
                new ColonneImport('type_client', $t['colonnes']['type_client']['libelle'], true, 'liste', valeurs: self::enumDe('clients', 'type_client'), exemple: $t['colonnes']['type_client']['exemple']),
                new ColonneImport('telephone', $t['colonnes']['telephone']['libelle'], true, 'texte', exemple: $t['colonnes']['telephone']['exemple']),
                new ColonneImport('email', $t['colonnes']['email']['libelle'], false, 'texte', exemple: $t['colonnes']['email']['exemple']),
            ],
        );
    }

    private static function unitesHebergement(): ModuleImport
    {
        $t = self::textes('m1_hebergement');

        return new ModuleImport(
            cle: 'm1-hebergement',
            module: 'M1',
            nom: $t['nom'],
            description: $t['description'],
            identifiant: 'numero',
            colonnes: [
                new ColonneImport('numero', $t['colonnes']['numero']['libelle'], true, 'texte', exemple: $t['colonnes']['numero']['exemple']),
                new ColonneImport('categorie', $t['colonnes']['categorie']['libelle'], true, 'reference', reference: 'categories_hebergement.libelle', exemple: $t['colonnes']['categorie']['exemple']),
            ],
        );
    }

    private static function carteBar(): ModuleImport
    {
        $t = self::textes('m5_bar');

        return new ModuleImport(
            cle: 'm5-bar',
            module: 'M5',
            nom: $t['nom'],
            description: $t['description'],
            identifiant: 'libelle',
            colonnes: [
                new ColonneImport('libelle', $t['colonnes']['libelle']['libelle'], true, 'texte', exemple: $t['colonnes']['libelle']['exemple']),
                // L'énumération de `CarteBoisson::CATEGORIES` (clés) — le même
                // registre que le POS et l'écran Carte du bar.
                new ColonneImport('categorie', $t['colonnes']['categorie']['libelle'], true, 'liste', valeurs: array_keys(CarteBoisson::CATEGORIES), exemple: $t['colonnes']['categorie']['exemple']),
                new ColonneImport('prix_vente', $t['colonnes']['prix_vente']['libelle'], true, 'montant', exemple: $t['colonnes']['prix_vente']['exemple']),
                new ColonneImport('article', $t['colonnes']['article']['libelle'], true, 'reference', reference: 'articles.libelle', exemple: $t['colonnes']['article']['exemple']),
            ],
        );
    }

    private static function carteRestaurant(): ModuleImport
    {
        $t = self::textes('m4_restaurant');

        return new ModuleImport(
            cle: 'm4-restaurant',
            module: 'M4',
            nom: $t['nom'],
            description: $t['description'],
            identifiant: 'libelle',
            colonnes: [
                new ColonneImport('libelle', $t['colonnes']['libelle']['libelle'], true, 'texte', exemple: $t['colonnes']['libelle']['exemple']),
                new ColonneImport('categorie', $t['colonnes']['categorie']['libelle'], true, 'liste', valeurs: array_keys(\App\Pwa\Livewire\Restaurant\CarteRestaurant::CATEGORIES), exemple: $t['colonnes']['categorie']['exemple']),
                // 30/10/2026 — trois colonnes FACULTATIVES, pour « enregistrer
                // simplement, puis compléter après » (le PO) : prix vide =
                // plat « sur commande », entré à 0 avec la marque prix
                // PROVISOIRE ; menu vide = le menu `ImportReferentielsService::MENU_DEFAUT` ;
                // fiche vide = une fiche du nom du plat, SANS ingrédient et
                // marquée « composition provisoire » (le stock s'y ajoute après).
                new ColonneImport('prix_vente', $t['colonnes']['prix_vente']['libelle'], false, 'montant', exemple: $t['colonnes']['prix_vente']['exemple']),
                new ColonneImport('menu', $t['colonnes']['menu']['libelle'], false, 'reference', reference: 'menus.libelle', exemple: $t['colonnes']['menu']['exemple']),
                new ColonneImport('recette', $t['colonnes']['recette']['libelle'], false, 'reference', reference: 'recettes.libelle', exemple: $t['colonnes']['recette']['exemple']),
            ],
        );
    }

    private static function articlesStock(): ModuleImport
    {
        $t = self::textes('m6_stocks');

        return new ModuleImport(
            cle: 'm6-stocks',
            module: 'M6',
            nom: $t['nom'],
            description: $t['description'],
            identifiant: 'libelle',
            colonnes: [
                new ColonneImport('libelle', $t['colonnes']['libelle']['libelle'], true, 'texte', exemple: $t['colonnes']['libelle']['exemple']),
                new ColonneImport('categorie', $t['colonnes']['categorie']['libelle'], true, 'liste', valeurs: \App\Pwa\Livewire\Stocks\Stocks::CATEGORIES, exemple: $t['colonnes']['categorie']['exemple']),
                new ColonneImport('unite_mesure', $t['colonnes']['unite_mesure']['libelle'], true, 'liste', valeurs: \App\Pwa\Livewire\Stocks\Stocks::UNITES, exemple: $t['colonnes']['unite_mesure']['exemple']),
                new ColonneImport('seuil_alerte', $t['colonnes']['seuil_alerte']['libelle'], true, 'nombre', exemple: $t['colonnes']['seuil_alerte']['exemple']),
                new ColonneImport('point_stockage', $t['colonnes']['point_stockage']['libelle'], false, 'reference', reference: 'points_stockage.libelle', exemple: $t['colonnes']['point_stockage']['exemple']),
            ],
        );
    }

    private static function fournisseurs(): ModuleImport
    {
        $t = self::textes('m7_achats');

        return new ModuleImport(
            cle: 'm7-achats',
            module: 'M7',
            nom: $t['nom'],
            description: $t['description'],
            identifiant: 'raison_sociale',
            colonnes: [
                new ColonneImport('raison_sociale', $t['colonnes']['raison_sociale']['libelle'], true, 'texte', exemple: $t['colonnes']['raison_sociale']['exemple']),
                new ColonneImport('contact', $t['colonnes']['contact']['libelle'], false, 'texte', exemple: $t['colonnes']['contact']['exemple']),
                new ColonneImport('categorie', $t['colonnes']['categorie']['libelle'], false, 'texte', exemple: $t['colonnes']['categorie']['exemple']),
                new ColonneImport('conditions_paiement', $t['colonnes']['conditions_paiement']['libelle'], false, 'texte', exemple: $t['colonnes']['conditions_paiement']['exemple']),
                new ColonneImport('evaluation', $t['colonnes']['evaluation']['libelle'], false, 'liste', valeurs: self::enumDe('fournisseurs', 'evaluation'), exemple: $t['colonnes']['evaluation']['exemple']),
            ],
        );
    }

    private static function vehicules(): ModuleImport
    {
        $t = self::textes('m8_vehicules');

        return new ModuleImport(
            cle: 'm8-vehicules',
            module: 'M8',
            nom: $t['nom'],
            description: $t['description'],
            identifiant: 'immatriculation',
            // `vehicules.immatriculation` porte une contrainte UNIQUE : un
            // doublon avec l'existant est une ERREUR bloquante, jamais un
            // simple avertissement — la ligne exploserait à l'import.
            doublonExistantBloquant: true,
            colonnes: [
                new ColonneImport('immatriculation', $t['colonnes']['immatriculation']['libelle'], true, 'texte', exemple: $t['colonnes']['immatriculation']['exemple']),
                new ColonneImport('categorie', $t['colonnes']['categorie']['libelle'], true, 'liste', valeurs: self::enumDe('vehicules', 'categorie'), exemple: $t['colonnes']['categorie']['exemple']),
                new ColonneImport('annee', $t['colonnes']['annee']['libelle'], true, 'nombre', exemple: $t['colonnes']['annee']['exemple']),
                new ColonneImport('capacite', $t['colonnes']['capacite']['libelle'], false, 'nombre', exemple: $t['colonnes']['capacite']['exemple']),
                new ColonneImport('transmission', $t['colonnes']['transmission']['libelle'], false, 'texte', exemple: $t['colonnes']['transmission']['exemple']),
                new ColonneImport('tarif_jour', $t['colonnes']['tarif_jour']['libelle'], true, 'montant', exemple: $t['colonnes']['tarif_jour']['exemple']),
            ],
        );
    }

    private static function circuits(): ModuleImport
    {
        $t = self::textes('m9_tourisme');

        return new ModuleImport(
            cle: 'm9-tourisme',
            module: 'M9',
            nom: $t['nom'],
            description: $t['description'],
            identifiant: 'nom',
            colonnes: [
                new ColonneImport('nom', $t['colonnes']['nom']['libelle'], true, 'texte', exemple: $t['colonnes']['nom']['exemple']),
                new ColonneImport('theme', $t['colonnes']['theme']['libelle'], true, 'liste', valeurs: self::enumDe('circuits', 'theme'), exemple: $t['colonnes']['theme']['exemple']),
                new ColonneImport('zone', $t['colonnes']['zone']['libelle'], true, 'texte', exemple: $t['colonnes']['zone']['exemple']),
                new ColonneImport('duree', $t['colonnes']['duree']['libelle'], true, 'texte', exemple: $t['colonnes']['duree']['exemple']),
                new ColonneImport('prix', $t['colonnes']['prix']['libelle'], true, 'montant', exemple: $t['colonnes']['prix']['exemple']),
                new ColonneImport('capacite_max', $t['colonnes']['capacite_max']['libelle'], true, 'nombre', exemple: $t['colonnes']['capacite_max']['exemple']),
            ],
        );
    }

    /**
     * Les colonnes du modèle d'import de l'écran Stocks (M6) — huit colonnes,
     * stock d'ouverture compris, DISTINCTES des cinq de l'écran Import &
     * Export. Déclaration UNIQUE dont découlent le classeur `.xlsx` modèle et
     * la lecture de `Stocks::lancerImport` (par NOM d'en-tête). Même ordre
     * que `Stocks::COLONNES_IMPORT`.
     *
     * @return list<ColonneImport>
     */
    public static function colonnesArticlesEcranStocks(): array
    {
        return [
            new ColonneImport('nom', 'nom', true, 'texte', exemple: 'Riz local (sac 50 kg)'),
            new ColonneImport('categorie', 'categorie', false, 'liste', valeurs: \App\Pwa\Livewire\Stocks\Stocks::CATEGORIES, exemple: 'Denrées'),
            new ColonneImport('unite_mesure', 'unite_mesure', true, 'liste', valeurs: \App\Pwa\Livewire\Stocks\Stocks::UNITES, exemple: 'sac'),
            new ColonneImport('prix_achat', 'prix_achat', false, 'nombre', exemple: '32000'),
            new ColonneImport('seuil_alerte', 'seuil_alerte', false, 'nombre', exemple: '4'),
            new ColonneImport('point_stockage', 'point_stockage', false, 'reference', reference: 'points_stockage.libelle', exemple: 'Magasin général'),
            new ColonneImport('suivi', 'suivi', false, 'liste', valeurs: Article::SUIVIS, exemple: 'permanent'),
            new ColonneImport('stock_initial', 'stock_initial', false, 'nombre', exemple: '10'),
        ];
    }

    // ------------------------------------------------------------- support

    /**
     * Les textes d'un module — clé LITTÉRALE par module, jamais concaténée.
     *
     * @return array{nom: string, description: string, colonnes: array<string, array{libelle: string, exemple: string}>}
     */
    private static function textes(string $cle): array
    {
        /** @var array{nom: string, description: string, colonnes: array<string, array{libelle: string, exemple: string}>} $textes */
        $textes = match ($cle) {
            'm3_clients' => trans('imports.m3_clients'),
            'm1_hebergement' => trans('imports.m1_hebergement'),
            'm5_bar' => trans('imports.m5_bar'),
            'm4_restaurant' => trans('imports.m4_restaurant'),
            'm6_stocks' => trans('imports.m6_stocks'),
            'm7_achats' => trans('imports.m7_achats'),
            'm8_vehicules' => trans('imports.m8_vehicules'),
            'm9_tourisme' => trans('imports.m9_tourisme'),
            default => throw new \LogicException(__('imports.controle.module_inconnu')),
        };

        return $textes;
    }

    /**
     * L'énumération d'une colonne `enum`, lue de la BASE — même dérivation
     * que `Departs::themesDuCatalogue()` : la base est l'unique auteur, une
     * liste recopiée ici aurait divergé à la première migration.
     *
     * @return list<string>
     */
    private static function enumDe(string $table, string $colonne): array
    {
        $cache = $table.'.'.$colonne;

        if (isset(self::$enums[$cache])) {
            return self::$enums[$cache];
        }

        $definition = DB::selectOne(
            'SELECT COLUMN_TYPE AS type FROM information_schema.COLUMNS'
            .' WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
            [$table, $colonne],
        );

        preg_match_all("/'((?:[^'\\\\]|\\\\.)*)'/", (string) ($definition->type ?? ''), $valeurs);

        return self::$enums[$cache] = array_map(
            static fn (string $v): string => str_replace(["\\'", '\\\\'], ["'", '\\'], $v),
            $valeurs[1],
        );
    }
}

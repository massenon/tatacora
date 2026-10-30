<?php

declare(strict_types=1);

namespace App\Shared\ImportExport\Services;

use App\Shared\ImportExport\Data\ReferentielsImport;
use RuntimeException;

/**
 * La carte du Gîte Chez Noël (affiches du 30/10/2026) mise aux colonnes des
 * modèles d'import — « on enregistre de manière simple et on ajoute le stock
 * après » (le PO).
 *
 * La transcription fait foi dans `docs/data/carte_gite_chez_noel_2026.json` ;
 * sa copie `database/data/…` voyage avec l'application (le dossier `docs/`
 * n'est pas déployé). Un test les garde identiques.
 *
 * ## Ce que chaque fichier crée — et dans quel ordre l'importer
 *
 *  1. **m6-stocks** — les articles de stock des BOISSONS : catégorie
 *     « Boissons », unité « unité », seuil 0, AUCUN mouvement : le stock
 *     s'ajoute après, par une entrée. Raison d'être : `cartes_boisson.article_id`
 *     est NOT NULL (RG-05) — une boisson du bar ne peut pas exister sans
 *     fiche d'article.
 *  2. **m5-bar** — les boissons de la carte du bar, liées par leur nom à
 *     l'article du même nom (importer m6 d'abord, sinon « référence inconnue »).
 *  3. **m4-restaurant** — les plats, desserts, petits déjeuners… de la carte du
 *     restaurant. C'est CE module qui alimente la carte du restaurant : m6
 *     crée des articles de stock, pas des plats.
 *
 * ## Décisions de transcription
 *
 *  - Deux prix « a/b » : DEUX lignes — « Jus d'ananas (moyen) » 1500 et
 *    « Jus d'ananas (grand) » 2000 ; « Café simple » 500 et « Café double » 1000.
 *  - « Sur commande » : prix VIDE (m4 l'admet : plat entré à 0, prix provisoire).
 *  - Les descriptions (pizzas, chawarma, petits déjeuners) ne sont PAS importées :
 *    ni `plats` ni `cartes_boisson` n'ont de colonne « description ».
 *  - Doublon exact (Piron, affiches 4 et 6) : une seule ligne, listé par
 *    `doublonsEcartes()`. « Panini » et « Panini jambon » : DEUX lignes (PO).
 *    « Panini » et « Igname pilé » de « Sur commande » : suffixés « (sur commande) ».
 */
class CarteGiteChezNoelService
{
    /** Les trois modules alimentés par la carte, dans l'ordre d'import. */
    public const MODULES = ['m6-stocks', 'm5-bar', 'm4-restaurant'];

    /** Rubrique de l'affiche → clé de `CarteRestaurant::CATEGORIES`. */
    private const CATEGORIES_RESTAURANT = [
        'Nos Desserts' => 'desserts',
        'Entrées' => 'entrees',
        'Plats complets' => 'plats',
        'Nos sauces' => 'sauces',
        'Garnitures' => 'garnitures',
        'Garniture (portions et omelettes)' => 'garnitures',
        'Accompagnements' => 'accompagnements',
        'Accompagnement (affiche 6)' => 'accompagnements',
        'Sandwicherie' => 'sandwicherie',
        'Sandwicherie (affiche 6)' => 'sandwicherie',
        'Pizzas' => 'pizzas',
        'Hamburger frites' => 'sandwicherie',
        'Petits déjeuners' => 'formules',
        'Sur commande' => 'plats',
    ];

    /** Un article « sur commande » qui n'est pas un plat. */
    private const CATEGORIE_ARTICLE = ['hamburger' => 'sandwicherie'];

    /** Rubrique dont les noms déjà pris ailleurs reçoivent ce suffixe (le contrôle refuse deux fois le même nom). */
    private const SUFFIXE_SUR_COMMANDE = ' (sur commande)';

    /** @var list<array{nom: string, rubrique: string, retenu: string, groupe: string}> */
    private array $doublons = [];

    /**
     * Le classeur `.xlsx` PRÉREMPLI d'un module de la carte.
     */
    public function classeur(string $cleModule): string
    {
        $module = ReferentielsImport::parCle($cleModule);

        if ($module === null || ! in_array($cleModule, self::MODULES, true)) {
            throw new RuntimeException(__('imports.controle.module_inconnu'));
        }

        return app(TableurService::class)->ecrireClasseur($module->nom, $module->description, $module->colonnes, $this->lignes($cleModule));
    }

    /**
     * @return list<array<string, string|int|null>>
     */
    public function lignes(string $cleModule): array
    {
        return match ($cleModule) {
            'm4-restaurant' => $this->lignesRestaurant(),
            'm5-bar' => array_map(static fn (array $b): array => [
                'libelle' => $b['libelle'],
                'categorie' => 'maison',
                'prix_vente' => $b['prix'],
                'article' => $b['libelle'],
            ], $this->boissons()),
            'm6-stocks' => array_map(static fn (array $b): array => [
                'libelle' => $b['libelle'],
                'categorie' => 'Boissons',
                'unite_mesure' => 'unité',
                'seuil_alerte' => 0,
                'point_stockage' => null,
            ], $this->boissons()),
            default => throw new RuntimeException(__('imports.controle.module_inconnu')),
        };
    }

    /**
     * Les lignes de la carte écartées comme doublons — à confirmer par le PO.
     *
     * @return list<array{nom: string, rubrique: string, retenu: string, groupe: string}>
     */
    public function doublonsEcartes(): array
    {
        $this->boissons();
        $this->lignesRestaurant();

        return $this->doublons;
    }

    /**
     * @return list<array<string, string|int|null>>
     */
    private function lignesRestaurant(): array
    {
        $this->doublons = array_values(array_filter($this->doublons, static fn (array $d): bool => $d['groupe'] !== 'restaurant'));
        $lignes = [];
        $vus = [];

        foreach ($this->rubriques() as $rubrique) {
            if (($rubrique['type'] ?? '') !== 'restaurant') {
                continue;
            }

            foreach ($rubrique['articles'] as $article) {
                $nom = (string) $article['nom'];

                // « Sur commande » : un nom déjà pris ailleurs (Panini, Igname pilé)
                // est un autre article — suffixé plutôt qu'écarté (PO, 30/10/2026).
                if ($rubrique['rubrique'] === 'Sur commande' && isset($vus[$this->cle($nom)])) {
                    $nom .= self::SUFFIXE_SUR_COMMANDE;
                }

                $cle = $this->cle($nom);

                if (isset($vus[$cle])) {
                    $this->doublons[] = ['nom' => $nom, 'rubrique' => (string) $rubrique['rubrique'], 'retenu' => $vus[$cle], 'groupe' => 'restaurant'];

                    continue;
                }

                $vus[$cle] = $nom;
                $categorie = self::CATEGORIE_ARTICLE[$this->cle((string) $article['nom'])]
                    ?? self::CATEGORIES_RESTAURANT[(string) $rubrique['rubrique']]
                    ?? throw new RuntimeException('Rubrique sans catégorie : '.$rubrique['rubrique']);

                $lignes[] = [
                    'libelle' => $nom,
                    'categorie' => $categorie,
                    'prix_vente' => isset($article['prix']) ? (int) $article['prix'] : null,
                    'menu' => null,
                    'recette' => null,
                    // 30/10/2026 : la composition annoncée sur l'affiche (JSON
                    // `description`), colonne facultative du modèle.
                    'description' => isset($article['description']) ? (string) $article['description'] : null,
                ];
            }
        }

        return $lignes;
    }

    /**
     * Les boissons de la carte du bar, une ligne par taille.
     *
     * @return list<array{libelle: string, prix: int}>
     */
    private function boissons(): array
    {
        $this->doublons = array_values(array_filter($this->doublons, static fn (array $d): bool => $d['groupe'] !== 'boisson'));
        $boissons = [];
        $vus = [];

        foreach ($this->rubriques() as $rubrique) {
            if (($rubrique['type'] ?? '') !== 'boisson') {
                continue;
            }

            foreach ($rubrique['articles'] as $article) {
                $nom = (string) $article['nom'];

                if (isset($vus[$this->cle($nom)])) {
                    $this->doublons[] = ['nom' => $nom, 'rubrique' => (string) $rubrique['rubrique'], 'retenu' => $vus[$this->cle($nom)], 'groupe' => 'boisson'];

                    continue;
                }

                $vus[$this->cle($nom)] = $nom;
                $boissons[] = [
                    'libelle' => isset($article['prix_grand']) && ($rubrique['variantes'] ?? '') === 'moyen/grand' ? $nom.' (moyen)' : $nom,
                    'prix' => (int) $article['prix'],
                ];

                if (isset($article['prix_grand'])) {
                    $boissons[] = [
                        'libelle' => ($rubrique['variantes'] ?? '') === 'simple/double' ? str_ireplace('simple', 'double', $nom) : $nom.' (grand)',
                        'prix' => (int) $article['prix_grand'],
                    ];
                }
            }
        }

        return $boissons;
    }

    /**
     * @return list<array<string, mixed>>
     */
    private function rubriques(): array
    {
        $chemin = database_path('data/carte_gite_chez_noel_2026.json');
        $json = is_file($chemin) ? file_get_contents($chemin) : false;
        $carte = $json === false ? null : json_decode($json, true);

        if (! is_array($carte) || ! isset($carte['rubriques'])) {
            throw new RuntimeException('La carte du Gîte Chez Noël est introuvable ou illisible.');
        }

        return $carte['rubriques'];
    }

    private function cle(string $nom): string
    {
        $translit = transliterator_transliterate('NFD; [:Nonspacing Mark:] Remove; NFC; Lower()', trim($nom));

        return is_string($translit) ? $translit : mb_strtolower(trim($nom));
    }
}

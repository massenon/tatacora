<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Bar\Services\CarteBoissonService;
use App\Domain\Carte\MarquesDePrix;
use App\Domain\Stocks\Models\Article;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * Carte du bar de démonstration — les 33 références de M5, transcrites de
 * `prototype_v2/assets/js/referentiel-carte.js`.
 *
 * ## 33 et non 24 depuis le 03/09/2026, et le compte a une raison
 *
 * Le maître répartit M5 en DEUX rayons : `bar` (l.238-268, l'ardoise
 * manuscrite, **24 références**) et `boissons_maison` (l.213-223, « Jus maison
 * & cafés », **9 références**). `seed-restauration.js` l.15 parle des « 33
 * références du bar » : c'est la somme des deux, et c'est la seule lecture qui
 * rende 33. Seul le premier rayon était semé ; les jus maison et les cafés
 * n'existaient nulle part, si bien que le point de vente ne pouvait pas
 * encaisser un café.
 *
 * ⚠ Le maître compte « bières, sucreries, eaux, vins » dans ces 33 — mais son
 * ardoise ne porte AUCUNE eau. « Eau minérale 1,5 L (pack 6) » figure dans son
 * stock (`seed-donnees.js` l.81) et dans aucune ligne de carte. L'écart est du
 * maître ; il est signalé, pas comblé : inventer un prix de vente pour l'eau
 * serait inventer une ligne de carte.
 *
 * ## Ce seeder ne crée AUCUN article — c'est ce qui a changé
 *
 * Il en créait 24, ce qui en faisait le second auteur de `articles` à côté de
 * `StocksSeeder` (PA-160/PA-161, même défaut que le parc d'hébergement). Le
 * stock du maître descend « AU LITRAGE PRÈS » et porte ses propres casiers :
 * les deux jeux se recouvraient. Les articles sont désormais TOUS créés par
 * `StocksSeeder`, et retrouvés ici par leur libellé EXACT — l'absence est un
 * refus explicite, jamais un `LIKE` suivi d'un repli.
 *
 * ## Le taux de conversion est la donnée qui manquait le plus
 *
 * `cartes_boisson.unites_vendables_par_unite_stock` portait 1 pour toutes les
 * lignes : une Béninoise vendue sortait UN CASIER du stock. Il porte désormais
 * le conditionnement réel — 12 pour un casier de 12, 24 pour un casier de 24,
 * 1 pour ce qui se stocke à la bouteille. La migration `2026_09_01_110000`
 * avertit elle-même que « se tromper de sens vide le stock 24 fois trop vite,
 * ou 24 fois trop lentement », et que l'écart n'apparaît qu'à l'inventaire,
 * imputé à une perte physique.
 *
 * ## L'ardoise ENTIÈRE, marques comprises
 *
 * Six lignes de l'ardoise étaient sans prix (colonne effacée ou jamais
 * renseignée) ; le maître leur a posé un tarif `PROVISOIRE(...)` sur décision
 * du Product Owner du 17/08/2026 (« mets des prix, on le modifiera après »),
 * avec le raisonnement qui a produit chaque montant. Elles sont semées **avec
 * `prix_provisoire = true`**, ce qui les rend reconnaissables partout — filtre
 * de la carte, indicateur, fiche des prix.
 *
 * Les montants sont ceux du maître, au franc près, et ne sont pas recalculés
 * ici : `referentiel-carte.js` l.238-268 porte le raisonnement de chacun, et en
 * produire un second ici créerait deux vérités pour un même prix de vente.
 *
 * ## Deux questions du maître restent OUVERTES, et ce seeder ne les tranche pas
 *
 * 1. « VODY / LOCO » figure sur UNE ligne d'ardoise : un produit ou deux ?
 *    Le maître ne le scinde pas, ce seeder non plus — créer deux articles
 *    poserait une référence qui n'existe peut-être pas.
 * 2. Les vins sont-ils vendus au VERRE ou à la BOUTEILLE ? Le prix retenu est
 *    un prix au verre ; s'il s'agissait de la bouteille, il est très largement
 *    sous-évalué. `prix_provisoire` est exactement le drapeau qui garde la
 *    question visible jusqu'à l'arbitrage.
 *
 * ## `categorie` est une classification d'amorçage, pas une donnée du maître
 *
 * L'`enum` du schéma vaut `locale | maison | importee` — l'ORIGINE. Le maître,
 * lui, classe par famille (`biere`, `sucrerie`, `vin`, `spiritueux`,
 * `energisant`, `sans_alcool`). Les deux registres ne se recouvrent pas : la
 * répartition ci-dessous est une classification de départ, corrigeable par
 * l'écran CRUD, et non un relevé.
 *
 * Dév/Recette UNIQUEMENT. Idempotent. Dépend de `StocksSeeder`.
 *
 * @see EF-M5-02 Carte des boissons
 * @see RG-05 Sortie de stock automatique
 */
class BarSeeder extends Seeder
{
    /**
     * Les 33 références de M5.
     *
     * Colonnes : libellé de carte, prix ardoise, origine (enum du schéma),
     * article de stock (libellé EXACT chez `StocksSeeder`), unités vendables
     * par unité de stock, prix provisoire ?
     *
     * @return list<array{string, string, string, string, string, bool}>
     */
    public static function carte(): array
    {
        return [
            // ============================================================
            // RAYON « bar » — l'ardoise manuscrite, 24 références (l.238-268)
            // ============================================================
            ['Béninoise 66 cl', '800', 'locale', 'Béninoise 66 cl (casier 12)', '12', false],
            ['Béninoise 33 cl', '500', 'locale', 'Béninoise 33 cl (casier 24)', '24', false],
            ['Beaufort 50 cl', '800', 'locale', 'Beaufort 50 cl (casier 12)', '12', false],
            ['Beaufort 33 cl', '500', 'locale', 'Beaufort 33 cl (casier 24)', '24', false],
            ['Doppel 66 cl', '800', 'locale', 'Doppel 66 cl (casier 12)', '12', false],
            ['Doppel 33 cl', '500', 'locale', 'Doppel 33 cl (casier 24)', '24', false],
            ['EKU 33 cl', '700', 'locale', 'EKU 33 cl (casier 24)', '24', false],
            ['Pils 66 cl', '1000', 'locale', 'Pils 66 cl (casier 12)', '12', false],
            ['Pils 33 cl', '500', 'locale', 'Pils 33 cl (casier 24)', '24', false],
            ['Guinness 33 cl', '900', 'importee', 'Guinness 33 cl (casier 24)', '24', false],
            ['Flag', '800', 'locale', 'Flag (casier 24)', '24', false],
            ['Castel', '800', 'locale', 'Castel (casier 24)', '24', false],
            ['Awoyo', '1000', 'locale', 'Awoyo (casier 24)', '24', false],
            ['Racine', '800', 'locale', 'Racine (casier 24)', '24', false],
            ['XXL', '700', 'importee', 'XXL (carton 24)', '24', false],
            ['Sucrerie 66 cl', '700', 'locale', 'Sucrerie 66 cl (casier 12)', '12', false],
            ['Sucrerie 33 cl', '500', 'locale', 'Sucrerie 33 cl (casier 24)', '24', false],
            ['Jus naturel', '700', 'maison', 'Jus naturel (L)', '1', false],

            // Les six lignes SANS PRIX de l'ardoise, avec le tarif posé par le
            // Product Owner le 17/08/2026 et la marque qui dit qu'il reste à
            // confronter à l'ardoise. Les montants sont ceux du maître
            // (`referentiel-carte.js` l.246-267), jamais recalculés ici.
            ['EKU 66 cl', '1200', 'locale', 'EKU 66 cl (bouteille)', '1', true],
            ['Guinness 66 cl', '1500', 'importee', 'Guinness 66 cl (bouteille)', '1', true],
            // SCINDÉS et RETARIFÉS le 01/09/2026 — décision du Product
            // Owner : « Vody et Loco » sont DEUX produits distincts à
            // 1 000 F chacun (le maître les fusionnait à 500 F), et les deux
            // vins passent de 1 000 F à 10 000 F LA BOUTEILLE. Deux
            // références = deux articles (la règle que le maître nomme
            // lui-même pour les contenances).
            ['Vody', '1000', 'locale', 'Vody (bouteille)', '1', true],
            ['Loco', '1000', 'locale', 'Loco (bouteille)', '1', true],
            ['Vin blanc', '10000', 'importee', 'Vin blanc (bouteille)', '1', true],
            ['Vin rouge', '10000', 'importee', 'Vin rouge (bouteille)', '1', true],
            ['Rhum', '1000', 'importee', 'Rhum (bouteille)', '1', true],

            // ============================================================
            // RAYON « boissons_maison » — Jus maison & cafés, 9 références
            // (l.213-223).
            //
            // « 1500/2000 signifie moyen/grand : ce sont DEUX articles
            // vendables, pas une fourchette. Les traiter comme un prix unique
            // rendrait le POS incapable d'encaisser un grand format. »
            // ============================================================
            ["Jus d'ananas (moyen)", '1500', 'maison', "Jus d'ananas moyen (préparation du jour)", '1', false],
            ["Jus d'ananas (grand)", '2000', 'maison', "Jus d'ananas grand (préparation du jour)", '1', false],
            ['Jus de pastèque (moyen)', '1500', 'maison', 'Jus de pastèque moyen (préparation du jour)', '1', false],
            ['Jus de pastèque (grand)', '2000', 'maison', 'Jus de pastèque grand (préparation du jour)', '1', false],
            ['Jus de banane (moyen)', '1500', 'maison', 'Jus de banane moyen (préparation du jour)', '1', false],
            ['Jus de banane (grand)', '2000', 'maison', 'Jus de banane grand (préparation du jour)', '1', false],
            ['Café simple (petit)', '500', 'maison', 'Café simple petit (préparation du jour)', '1', false],
            ['Café simple (grand)', '1000', 'maison', 'Café simple grand (préparation du jour)', '1', false],
            ['Café expresso', '1000', 'maison', 'Café expresso (préparation du jour)', '1', false],
        ];
    }

    public function run(): void
    {
        if (CarteBoisson::query()->exists()) {
            return;
        }

        $cartes = app(CarteBoissonService::class);

        foreach (self::carte() as [$libelle, $prix, $origine, $article, $conversion, $provisoire]) {
            $cartes->creer([
                'id' => (string) Str::uuid(),
                'article_id' => $this->articleId($article),
                // Le conditionnement réel, jamais le 1 par défaut du schéma.
                'unites_vendables_par_unite_stock' => $conversion,
                'libelle' => $libelle,
                'categorie' => $origine,
                'prix_vente' => $prix,
                // La marque, jamais déduite d'un prix nul : `prix_vente` est
                // NOT NULL, et la déduire d'un montant produirait le compteur
                // « aucun prix provisoire » que PA-161 (b) a corrigé.
                MarquesDePrix::PROVISOIRE => $provisoire,
            ]);
        }
    }

    /**
     * L'article est LU dans le référentiel de `StocksSeeder`, par son libellé
     * EXACT. Un `LIKE` rattacherait la ligne de carte au premier article dont
     * le nom contient le motif — « %Béninoise% » a déjà remonté la 33 cl là où
     * la vente portait sur la 66 —, et une création de repli poserait un second
     * article que personne n'approvisionne.
     */
    private function articleId(string $libelle): string
    {
        $id = Article::query()->where('libelle', $libelle)->value('id');

        if ($id === null) {
            // Message exploitant, jamais affiché a un utilisateur.
            throw new RuntimeException(
                'BarSeeder lit les articles de StocksSeeder : article introuvable ('
                .$libelle.'). Lancer StocksSeeder avant (DatabaseSeeder le fait '
                .'deja). Ce seeder ne cree AUCUN article — un article cree ici '
                .'serait un second auteur du referentiel, et la vente '
                .'decrementerait un casier que personne ne remplit.',
            );
        }

        return (string) $id;
    }
}

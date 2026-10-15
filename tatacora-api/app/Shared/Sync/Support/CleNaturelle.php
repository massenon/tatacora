<?php

declare(strict_types=1);

namespace App\Shared\Sync\Support;

use Illuminate\Support\Str;

/**
 * La normalisation des clés naturelles du référentiel — décision du Product
 * Owner du 15/10/2026 (le serveur FUSIONNE un élément créé hors connexion sur
 * l'élément équivalent qu'il porte déjà).
 *
 * ## Une seule normalisation pour toutes les tables
 *
 * Écrite d'abord pour les fournisseurs (S1), elle sert depuis S2 aux points de
 * stockage, articles, boissons, menus, fiches, plats, catégories et unités.
 * Deux normalisations finiraient par diverger : « Béninoise 33cl » fusionnerait
 * au bar et ferait doublon au restaurant.
 *
 * Sans casse, sans accents, espaces de bord retirés et espaces internes
 * resserrés : deux postes ne s'accordent jamais sur la casse ni sur les
 * accents, et ne pas confondre « Sobébra » et « SOBEBRA  » ferait précisément
 * le doublon que la fusion existe pour éviter. La ponctuation, elle, est
 * GARDÉE : « Riz 25kg » et « Riz 2.5kg » ne sont pas le même article.
 */
final class CleNaturelle
{
    /**
     * La clé d'un élément, composée de ses parties normalisées — une partie
     * vide reste une partie (« Riz | » ≠ « Riz | kg »).
     */
    public static function de(?string ...$parties): string
    {
        return implode('|', array_map(self::normaliser(...), $parties));
    }

    public static function normaliser(?string $valeur): string
    {
        $ascii = Str::ascii(trim((string) $valeur));

        return (string) preg_replace('/\s+/', ' ', mb_strtolower($ascii));
    }
}

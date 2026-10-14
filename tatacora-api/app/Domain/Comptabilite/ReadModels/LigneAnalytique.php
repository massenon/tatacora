<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

/**
 * Un centre d'analyse et sa marge sur couts directs — colonnes du maitre
 * (`m10-analytique.html` l.38-48) : « Centre de cout », « Produits »,
 * « Charges », « Marge », « Taux de marge ».
 *
 * `tauxMarge` est un POURCENTAGE a une decimale, rendu en chaine (« 42.7 »),
 * ou `null` quand le centre n'a aucun produit — un centre support n'a pas un
 * taux de zero, il n'en a pas (Article 7).
 *
 * `nombreLignes` est la colonne « Lignes » de l'onglet du hub
 * (`m10-syscohada-etats.js` l.196). Il dit sur combien d'ecritures repose la
 * marge : une marge calculee sur trois lignes ne se lit pas comme une marge
 * calculee sur trois cents.
 */
final readonly class LigneAnalytique
{
    public function __construct(
        public string $centreId,
        public string $libelle,
        public ?string $type,
        public string $produits,
        public string $charges,
        public string $resultat,
        public ?string $tauxMarge,
        public int $nombreLignes,
    ) {
    }
}

<?php

declare(strict_types=1);

namespace App\Shared\ReportEngine\Data;

use InvalidArgumentException;

/**
 * Structure générique d'un état — `{ kpis, entetes, lignes }`.
 *
 * `09_CLAUDE_CODE_SKILLS_LIBRARY.md` §2.4 impose cette forme unique, consommée
 * **à la fois** par l'affichage écran et par les exports PDF et Excel/CSV.
 *
 * La raison est nommée en toutes lettres dans `RESPECT_TABLEAU_RAPPORT.md` §4 :
 * « Export PDF et Excel avec des totaux légèrement différents — deux calculs
 * séparés au lieu d'une structure de données unique réutilisée ». Un état qui
 * calcule deux fois finit par calculer différemment, et l'écart n'apparaît que
 * lorsqu'un comptable compare les deux fichiers.
 *
 * @see EF-M14-03 Génération à la demande avec filtres dynamiques
 * @see EF-M14-04 Export multi-format
 */
final readonly class EtatResultat
{
    /**
     * @param  array<string, string>  $kpis  libellé => valeur déjà formatée
     * @param  list<string>  $entetes  intitulés de colonnes
     * @param  list<list<string>>  $lignes  cellules, dans l'ordre des entêtes
     * @param  array<string, string>  $filtresAppliques  filtres réellement utilisés (EF-M14-06)
     */
    public function __construct(
        public array $kpis,
        public array $entetes,
        public array $lignes,
        public array $filtresAppliques = [],
    ) {
        foreach ($lignes as $index => $ligne) {
            if (count($ligne) !== count($entetes)) {
                // Détecté à la construction plutôt qu'au rendu : un décalage
                // de colonnes produit un PDF plausible mais faux, où chaque
                // valeur est lue sous le mauvais intitulé.
                throw new InvalidArgumentException(sprintf(
                    'Ligne %d : %d cellules pour %d colonnes.',
                    $index,
                    count($ligne),
                    count($entetes),
                ));
            }
        }
    }

    public function estVide(): bool
    {
        return $this->lignes === [];
    }

    public function nombreLignes(): int
    {
        return count($this->lignes);
    }
}

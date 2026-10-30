<?php

declare(strict_types=1);

namespace App\Shared\ImportExport\Data;

/**
 * Une colonne attendue d'un import CSV — la déclaration UNIQUE dont découlent
 * la fiche « Colonnes attendues », le fichier modèle ET le contrôle.
 *
 * C'est la règle du maître (`import-export.html` l.77-81) : « Le modèle porte
 * les colonnes exactes […] Il est généré depuis la même déclaration que le
 * contrôle : il ne peut pas s'en écarter. » Deux déclarations écrites à deux
 * endroits auraient fini par diverger — l'utilisateur aurait rempli un modèle
 * que l'import refuse.
 */
final class ColonneImport
{
    /**
     * @param  string  $champ  clé interne (colonne du schéma ou clé du service)
     * @param  string  $libelle  entête lisible, celle du fichier modèle
     * @param  string  $type  `texte` | `nombre` | `montant` | `liste` | `reference`
     * @param  list<string>|null  $valeurs  liste fermée (type `liste`) — jamais
     *                                      recopiée à la main quand un registre serveur existe
     * @param  string|null  $reference  type `reference` : `table.colonne` du
     *                                  référentiel visé — vraie clé étrangère résolue par libellé
     *                                  EXACT, jamais du texte libre conservé tel quel
     * @param  int|null  $longueurMax  type `texte` : nombre de caractères au plus (30/10/2026,
     *                                 la description d'un plat : 500) ; `null` = pas de borne propre
     */
    public function __construct(
        public readonly string $champ,
        public readonly string $libelle,
        public readonly bool $requis,
        public readonly string $type,
        public readonly ?array $valeurs = null,
        public readonly ?string $reference = null,
        public readonly string $exemple = '',
        public readonly ?int $longueurMax = null,
    ) {
    }
}

<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

/**
 * Une etape de la procedure de cloture — `m10-cloture.html` l.73-123.
 *
 * `groupe` reprend les six blocs du maitre (« 1. Verification pre-cloture »,
 * « 2. Passage en statut 'en_cloture' »…), `libelle` le controle lui-meme.
 *
 * `motif` est un CODE FERME, jamais une phrase — la traduction appartient au
 * client, comme partout ailleurs dans ce domaine.
 *
 * `valeur` porte le chiffre quand l'etape en produit un (le total de la balance,
 * le resultat a reporter). Elle est `null` quand l'etape n'en produit pas : un
 * « 0 F » sur une etape non atteinte se lirait comme un controle passe a vide.
 */
final readonly class EtapeCloture
{
    public function __construct(
        public int $groupe,
        public string $groupeLibelle,
        public string $libelle,
        public string $etat,
        public ?string $motif = null,
        public ?string $valeur = null,
    ) {
    }
}

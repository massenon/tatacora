<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

/**
 * Ce qu'un etat de M10 a retenu, et ce qu'il a LAISSE DE COTE.
 *
 * ## Pourquoi un total ne suffit pas
 *
 * Un etat filtre sur `validee` et un etat filtre sur `toutes` rendent deux
 * chiffres differents sous le meme titre. Sans repartition, le lecteur ne peut
 * pas savoir lequel il regarde — et une Balance amputee de ses brouillons a
 * exactement l'air d'une Balance complete.
 *
 * `INSTRUCTIONS_AGENTS_PORTAGE.md` §5 : « Ce qui **ne peut pas s'ecrire** est
 * **compte et affiche**, jamais avale. » La meme discipline vaut pour ce qui
 * n'est pas lu : on compte ce qu'on ecarte.
 *
 * Les deux compteurs portent sur la portee de l'etat (exercice, et journal s'il
 * est filtre) **sans** le filtre de statut — c'est tout l'interet : ils disent
 * ce qui existe, pas ce qui a ete retenu.
 */
final readonly class RepartitionStatuts
{
    /**
     * @param  list<string>  $statutsRetenus  Les statuts reellement inclus dans l'etat.
     */
    public function __construct(
        public array $statutsRetenus,
        public int $brouillon,
        public int $validee,
    ) {
    }

    /**
     * Des ecritures existent-elles dans la portee sans avoir ete retenues ?
     *
     * Le client s'en sert pour dire « 12 brouillons ne sont pas comptes ici »
     * au lieu de laisser croire que l'etat couvre tout.
     */
    public function comporteDesExclusions(): bool
    {
        foreach (['brouillon', 'validee'] as $statut) {
            if (! in_array($statut, $this->statutsRetenus, true) && $this->compte($statut) > 0) {
                return true;
            }
        }

        return false;
    }

    private function compte(string $statut): int
    {
        return $statut === 'brouillon' ? $this->brouillon : $this->validee;
    }
}

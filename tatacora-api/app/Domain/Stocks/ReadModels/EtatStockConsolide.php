<?php

declare(strict_types=1);

namespace App\Domain\Stocks\ReadModels;

/**
 * État des stocks consolidé — projection de lecture destinée à l'API.
 *
 * ## Les compteurs ne mesurent PAS tous la même population, et c'est voulu
 *
 * - `references` compte les lignes **affichées** (donc après filtre) ;
 * - `sousSeuil` compte les articles critiques sur **tout** le référentiel de
 *   la portée, filtre d'affichage compris ou non.
 *
 * Cette dissymétrie est reprise telle quelle de `EtatStocks` (le même état,
 * rendu en PDF/CSV par le moteur RG-19) : `sousSeuil` est une **alarme**, pas
 * un décompte de page. Filtrer l'écran sur « tous les articles » ne doit pas
 * faire disparaître le nombre d'articles à réapprovisionner.
 *
 * Les faire diverger produirait deux vérités sur le même chiffre selon qu'on
 * le lit à l'écran ou sur le papier — le défaut nommé en PA-121. Un test
 * compare les deux à chaque exécution.
 *
 * `permanents` et `journaliers` suivent la même convention que les alarmes :
 * ils comptent TOUT le référentiel de la portée, pas la page. Le maître les
 * affiche en détail de « Références » et en carte « Gros / petit stock »
 * (`m6-stocks.html` l.170 et l.174), deux indicateurs de référentiel.
 *
 * @see EF-M14-02 État des stocks
 * @see RG-07 Seuil d'alerte
 * @see PA-161 (a) Le mode de suivi
 */
final readonly class EtatStockConsolide
{
    /**
     * @param  list<LigneStockArticle>  $lignes
     * @param  string  $valeurTotale  somme des valorisations AFFICHÉES, `numeric-string`
     * @param  array<string, string>  $filtresAppliques  les filtres RÉELLEMENT retenus
     */
    public function __construct(
        public array $lignes,
        public int $references,
        public int $sousSeuil,
        public int $rupture,
        public string $valeurTotale,
        public int $mouvements30Jours,
        public int $permanents,
        public int $journaliers,
        public array $filtresAppliques,
        public string $arreteAu,
    ) {
    }
}

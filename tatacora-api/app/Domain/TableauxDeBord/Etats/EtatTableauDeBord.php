<?php

declare(strict_types=1);

namespace App\Domain\TableauxDeBord\Etats;

use App\Domain\TableauxDeBord\Data\Periode;
use App\Domain\TableauxDeBord\Services\TableauDeBordService;
use App\Shared\ReportEngine\Contracts\EtatInterface;
use App\Shared\ReportEngine\Data\EtatResultat;

/**
 * Export du tableau de bord — EF-M11-05.
 *
 * `05_MODULE_SPECIFICATIONS.md` §M11 : « utilise le moteur d'export partagé
 * (RG-19) — **aucune génération PDF ad hoc** propre au tableau de bord ».
 *
 * `SPEC_ECRAN_M11_TABLEAU_DE_BORD.md` §7 relève que l'export du prototype
 * (jsPDF) se limitait à un titre et une date, sans l'en-tête obligatoire. En
 * implémentant `EtatInterface`, cet écart devient impossible à reproduire :
 * l'en-tête n'est pas de son ressort, elle lui est imposée.
 *
 * @see EF-M11-05
 * @see RG-19
 */
class EtatTableauDeBord implements EtatInterface
{
    public function __construct(
        private readonly TableauDeBordService $indicateurs,
    ) {
    }

    public function module(): string
    {
        return 'M11';
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function libelle(array $filtres): string
    {
        return __('tableaux_de_bord.etat.libelle');
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function periode(array $filtres): string
    {
        return $this->resoudrePeriode($filtres)->libelle();
    }

    /**
     * @param  array<string, string>  $filtres  `periode` parmi Periode::CODES
     */
    public function calculer(array $filtres): EtatResultat
    {
        $periode = $this->resoudrePeriode($filtres);
        $indicateurs = $this->indicateurs->indicateurs($periode);

        $lignes = [];

        foreach ($indicateurs as $cle => $donnees) {
            $lignes[] = [
                __("tableaux_de_bord.kpi.{$cle}"),
                $donnees['valeur'],
                $donnees['precedent'],
                // `null` volontairement rendu par un tiret : une base
                // précédente nulle ne produit pas « +100 % » (voir
                // TableauDeBordService::variation()).
                $donnees['variation_pct'] === null
                    ? __('tableaux_de_bord.non_comparable')
                    : $donnees['variation_pct'] . ' %',
            ];
        }

        $effectif = $this->indicateurs->effectif();

        return new EtatResultat(
            // Les 4 chiffres que le Gérant lit en premier, repris en tête de
            // document — les mêmes que les cartes de l'écran.
            kpis: [
                __('tableaux_de_bord.kpi.chiffre_affaires_encaisse') => $indicateurs['chiffre_affaires_encaisse']['valeur'],
                __('tableaux_de_bord.kpi.taux_occupation') => $indicateurs['taux_occupation']['valeur'] . ' %',
                __('tableaux_de_bord.kpi.depenses_cumulees') => $indicateurs['depenses_cumulees']['valeur'],
                __('tableaux_de_bord.kpi.employes_actifs') => $effectif['actifs'] . ' / ' . $effectif['total'],
            ],
            entetes: [
                __('tableaux_de_bord.col_indicateur'),
                __('tableaux_de_bord.col_periode'),
                __('tableaux_de_bord.col_precedent'),
                __('tableaux_de_bord.col_variation'),
            ],
            lignes: $lignes,
            filtresAppliques: ['periode' => $periode->code],
        );
    }

    /**
     * @param  array<string, string>  $filtres
     */
    private function resoudrePeriode(array $filtres): Periode
    {
        return Periode::depuisCode($filtres['periode'] ?? Periode::DEFAUT);
    }
}

<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Shared\Parametres\Models\ParametreSysteme;
use Illuminate\Database\Seeder;

/**
 * Référentiel minimal nécessaire à la déclaration de TVA :
 * les deux comptes SYSCOHADA et le taux applicable.
 *
 * **Le taux est une donnée réglementaire.** Il est ici renseigné à 18 %
 * **sur instruction explicite du Consultant Technique (15/08/2026)**, et non
 * déduit ou supposé par l'équipe de développement. Cette provenance est
 * inscrite dans la description du paramètre pour qu'elle reste lisible en
 * base : dans six mois, personne ne se souviendra d'où vient ce chiffre.
 *
 * **Reste à faire** — rattacher la référence officielle (Code Général des
 * Impôts du Bénin, article applicable) à ce paramètre. Tant que la source
 * documentaire n'est pas jointe, le taux est utilisable en développement et en
 * recette mais doit être confirmé avant toute émission de facture réelle.
 */
class TvaReferentielSeeder extends Seeder
{
    public function run(): void
    {
        $this->comptes();
        $this->taux();
    }

    /**
     * Les comptes de TVA (4431, 4432, 4452) viennent du fichier du plan
     * comptable du PO, importé par `ComptabiliteReferentielSeeder` : un seul
     * auteur. Ce seeder ne sème plus que le taux.
     */
    private function comptes(): void
    {
    }

    private function taux(): void
    {
        $parametres = [
            [
                'cle' => CalculTvaService::CLE_PARAMETRE_TAUX,
                'valeur' => '18.00',
                'description' => 'Taux de TVA en % — fourni par le Consultant Technique le 15/08/2026. '
                    . 'Référence au Code Général des Impôts à joindre (voir PA-36).',
            ],
            [
                'cle' => CalculTvaService::CLE_PARAMETRE_ACTIVE,
                // ACTIVE depuis le 01/09/2026 — DÉCISION EXPLICITE du Product
                // Owner (« le montant de base des produits est déjà TTC, donc
                // la TVA est 18 % »), qui est l'acte d'administration que la
                // version inactive attendait. Ce n'est plus un défaut posé
                // sans décision : la décision est datée et attribuée.
                'valeur' => 'true',
                'description' => 'Assujettissement à la TVA (true/false). Activée le 01/09/2026 sur '
                    . 'décision du Product Owner — les prix du catalogue sont TTC, la TVA en est extraite.',
            ],
            [
                'cle' => CalculTvaService::CLE_PARAMETRE_CONVENTION,
                // TTC — même décision du 01/09/2026 : « il revient de déduire
                // le montant HT du montant de base déjà fourni, qui est TTC,
                // pour tout (tourisme, hébergement, boisson, restaurant…) ».
                // PA-37 est RÉSOLUE par cette décision.
                'valeur' => CalculTvaService::CONVENTION_TTC,
                'description' => 'Convention des prix du catalogue : `ht` (les tarifs s\'entendent hors taxe, '
                    . 'la TVA s\'ajoute) ou `ttc` (les tarifs incluent déjà la TVA, elle en est extraite). '
                    . 'TTC depuis le 01/09/2026 — décision du Product Owner (PA-37 résolue).',
            ],
        ];

        foreach ($parametres as $parametre) {
            ParametreSysteme::firstOrCreate(['cle' => $parametre['cle']], $parametre);
        }
    }
}

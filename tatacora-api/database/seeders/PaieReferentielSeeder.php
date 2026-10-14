<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Domain\Rh\Services\CalculPaieService;
use App\Domain\Rh\Services\CongeService;
use App\Shared\Parametres\Models\ParametreSysteme;
use Illuminate\Database\Seeder;

/**
 * Paramètres de paie et de congés — EF-M13-04, EF-M13-07.
 *
 * ## Ce seeder ne pose QUE les taux réellement sourcés
 *
 * `ATELIER_PLAN_COMPTABLE.md` §5.1 confirme sur cnss.bj (source officielle)
 * les cotisations pension et prestations familiales. Le taux de **risques
 * professionnels** y est donné comme « 1 % à 4 %, variable selon l'activité »,
 * avec la mention explicite qu'une valeur de 2 % serait « une hypothèse
 * raisonnable en attendant confirmation ».
 *
 * **Cette hypothèse n'est pas posée ici.** Le paramètre reste absent, et
 * `CalculPaieService::chargesPatronales()` refuse donc de calculer. Sur une
 * masse salariale annuelle, l'écart entre 1 % et 4 % est un redressement —
 * c'est exactement le type de valeur que la première règle du projet interdit
 * de deviner.
 *
 * Les seuils de RG-14 (préavis, couverture) sont laissés absents pour la même
 * raison : ce sont des **décisions de gestion**, pas des constantes techniques.
 * Un délai deviné ferait refuser des congés sur un critère que personne n'a
 * arrêté.
 *
 * ## Il était ORPHELIN, et son premier branchement l'a fait échouer (02/09/2026)
 *
 * Ce seeder n'a jamais figuré dans `DatabaseSeeder` : `grep` à zéro hors
 * autoload. Sur toute base semée, `parametres_systeme` ne portait donc **aucun
 * taux de paie**, et `CalculPaieService` levait à chaque calcul — l'auteur du
 * référentiel était écrit, documenté, et jamais exécuté. C'est la sixième
 * occurrence de ce défaut après les cinq de PA-160/PA-161, et la seule où le
 * code lui-même était cassé : la description du VPS faisait 346 caractères
 * pour une colonne `varchar(255)`, et le branchement a rendu
 * `SQLSTATE[22001] Data too long`. **Un seeder décroché n'est pas du code
 * dormant : c'est du code non compilé.**
 *
 * ## Le détail du VPS, sorti de la colonne
 *
 * Le taux est de **4 % pour les entreprises ordinaires** et de 2 % pour les
 * structures d'enseignement privé : le Gîte relève du taux ordinaire. C'est
 * cette phrase qui débordait la colonne ; elle se lit ici, où la largeur
 * n'est pas contrainte.
 */
class PaieReferentielSeeder extends Seeder
{
    public function run(): void
    {
        $confirmes = [
            [
                'cle' => CalculPaieService::CLE_CNSS_SALARIE,
                'valeur' => '3.6',
                'description' => 'Cotisation CNSS part salariale, en % du brut, sans plafond. '
                    . 'Source : cnss.bj (branche pension, 10 % dont 3,6 % salarié).',
            ],
            [
                'cle' => CalculPaieService::CLE_CNSS_PENSION_EMPLOYEUR,
                'valeur' => '6.4',
                'description' => 'Cotisation CNSS pension part employeur, en % du brut. Source : cnss.bj.',
            ],
            [
                'cle' => CalculPaieService::CLE_CNSS_PRESTATIONS_FAMILIALES,
                'valeur' => '9',
                'description' => 'Cotisation CNSS prestations familiales, employeur uniquement, '
                    . 'en % du brut. Source : cnss.bj.',
            ],
            [
                'cle' => CalculPaieService::CLE_VPS,
                'valeur' => '4',
                // 346 caracteres pour une colonne `varchar(255)` : ce seeder
                // n'avait JAMAIS ete execute, et le jour ou on l'a branche il
                // a leve `SQLSTATE[22001] Data too long`. Le detail vit
                // desormais dans le docbloc de classe, ou il se lit sans
                // contrainte de largeur ; la colonne garde ce qui doit rester
                // sous les yeux d'un Administrateur a l'ecran Parametres.
                'description' => 'VPS (Versement Patronal sur Salaires), en % du total des salaires '
                    . 'bruts, SANS plafond. Taxe a la charge de l\'employeur, jamais retenue sur le '
                    . 'salaire. Declaration et paiement au plus tard le 10 du mois suivant. '
                    . 'Source : ATELIER_PLAN_COMPTABLE.md.',
            ],
        ];

        foreach ($confirmes as $parametre) {
            ParametreSysteme::firstOrCreate(['cle' => $parametre['cle']], $parametre);
        }

        // Volontairement NON créés — leur absence fait échouer le calcul, ce
        // qui est le comportement voulu tant que la décision n'est pas prise :
        //
        //   CalculPaieService::CLE_CNSS_RISQUES_PROFESSIONNELS (PA-53, CNSS)
        //   CongeService::CLE_PREAVIS                          (décision RH)
        //   CongeService::CLE_COUVERTURE                       (décision RH)
        //
        // Ne pas « compléter » ce seeder sans la décision correspondante : la
        // valeur par défaut deviendrait la règle appliquée en production.
    }

    /**
     * Paramètres délibérément absents, exposés pour que l'omission soit
     * lisible depuis le code plutôt que déduite d'un commentaire.
     *
     * @return list<string>
     */
    public static function parametresEnAttenteDeDecision(): array
    {
        return [
            CalculPaieService::CLE_CNSS_RISQUES_PROFESSIONNELS,
            CongeService::CLE_PREAVIS,
            CongeService::CLE_COUVERTURE,
        ];
    }
}

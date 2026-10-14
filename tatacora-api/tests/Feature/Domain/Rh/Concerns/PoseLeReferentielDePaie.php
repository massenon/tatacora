<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Rh\Concerns;

use App\Domain\Rh\Services\CalculPaieService;
use App\Shared\Parametres\Models\ParametreSysteme;

/**
 * Pose les quatre taux CONFIRMÉS dont la paie a besoin — pour les tests.
 *
 * ## Pourquoi ce trait existe au lieu d'appeler `PaieReferentielSeeder`
 *
 * DEUX défauts mesurés le 31/08/2026, et le second n'a été trouvé qu'en
 * essayant réellement de lancer le seeder :
 *
 * 1. **Il n'est appelé par personne.** `PaieReferentielSeeder` ne figure pas
 *    dans `DatabaseSeeder`, et `grep` rend zéro appelant dans tout le dépôt
 *    hors autoload Composer. Sur une base semée par `php artisan db:seed`,
 *    `parametres_systeme` ne porte AUCUN taux de paie. C'est exactement la
 *    forme de PA-161 : un seeder écrit, documenté, décroché, jamais exécuté.
 * 2. **Il échouerait s'il était appelé.** Sa description du VPS fait plus de
 *    400 caractères ; `parametres_systeme.description` est un `varchar(255)`.
 *    MySQL rend « Data too long for column 'description' ». Le seeder est donc
 *    non seulement inerte, il est cassé — et personne ne pouvait le savoir,
 *    puisque rien ne le lançait. C'est la question « quel chemin n'a jamais
 *    été exécuté ? » qui l'a trouvé.
 *
 * ⚠ Ce trait N'EST PAS un correctif : `database/seeders/` est hors du couloir
 * de ce lot, et le défaut est remonté tel quel. Il pose ce dont les tests ont
 * besoin, rien de plus.
 *
 * ## Ce qu'il ne pose PAS, et jamais
 *
 * `taux_cnss_risques_professionnels`. Il est « 1 % à 4 % selon l'activité » et
 * n'est pas confirmé pour l'hôtellerie-restauration (PA-53). Le poser ici,
 * même « juste pour un test », donnerait à la suite une couleur verte sur un
 * chemin que la production n'empruntera jamais — et le refus, qui EST le
 * livrable, ne serait plus jamais éprouvé.
 *
 * Sources des quatre taux : cnss.bj, reprises telles quelles de
 * `PaieReferentielSeeder` (`ATELIER_PLAN_COMPTABLE.md` §5.1).
 */
trait PoseLeReferentielDePaie
{
    protected function poserLeReferentielDePaie(): void
    {
        $taux = [
            CalculPaieService::CLE_CNSS_SALARIE => '3.6',
            CalculPaieService::CLE_CNSS_PENSION_EMPLOYEUR => '6.4',
            CalculPaieService::CLE_CNSS_PRESTATIONS_FAMILIALES => '9',
            CalculPaieService::CLE_VPS => '4',
        ];

        foreach ($taux as $cle => $valeur) {
            ParametreSysteme::firstOrCreate(
                ['cle' => $cle],
                ['valeur' => $valeur, 'description' => 'Taux confirmé (cnss.bj) — fixture de test.'],
            );
        }
    }
}

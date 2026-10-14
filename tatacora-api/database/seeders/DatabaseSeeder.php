<?php

declare(strict_types=1);

namespace Database\Seeders;

use Illuminate\Database\Seeder;

/**
 * BASE VIERGE — les seuls référentiels sans lesquels l'application ne peut pas
 * recevoir de données réelles (directive du Product Owner du 14/10/2026).
 *
 * « L'application doit démarrer avec une base vierge pour saisir ses propres
 * données réelles » : `php artisan migrate:fresh --seed` ne pose plus AUCUN
 * article, carte de boissons, plat, menu, recette, client, fournisseur,
 * parc, véhicule, circuit, vente ni dépense. Le jeu de démonstration vit dans
 * {@see DemonstrationSeeder}, lancé seulement par son nom :
 *
 *     php artisan db:seed --class=DemonstrationSeeder
 *
 * ## AUCUN compte n'est créé ici
 *
 * Un mot de passe posé par un seeder serait connu de quiconque lit le code.
 * Le premier compte se crée par {@see ComptesReelsSeeder}, dont les mots de
 * passe viennent du `.env` du poste (`COMPTE_*_MOT_DE_PASSE`) :
 *
 *     php artisan db:seed --class=ComptesReelsSeeder
 *
 * ## Ce qui est semé, et pourquoi c'est indispensable
 *
 * - matrice RBAC (rôles × modules) — sans elle aucun compte n'a de droit ;
 * - canaux de réservation — `reservations.canal_id` est une clé étrangère ;
 * - plan comptable SYSCOHADA du PO, journaux, centres de coût, exercice
 *   courant — `PasserEcritureService` refuse tout mouvement d'argent sans eux ;
 * - les 20 paramètres système fournis par le PO (script SQL du 14/10/2026 :
 *   identité légale, taux sourcés de paie et de TVA, SMTP sans mot de passe,
 *   bascules) — aucun taux deviné, PA-53 ;
 * - modèles de notification (registre fermé du M12, aucune donnée métier).
 *
 * Tous sont idempotents : relancer `db:seed` ne double rien.
 *
 * @see tests/Feature/Seeders/BaseViergeTest.php qui l'exécute réellement
 */
class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $this->call([
            RolePermissionSeeder::class,
            CanauxReservationSeeder::class,
            ComptabiliteReferentielSeeder::class,
            // AVANT Paie/Tva : les 20 paramètres du PO (script SQL du
            // 14/10/2026) font foi, descriptions comprises ; les deux
            // seeders suivants deviennent sans effet (`firstOrCreate`).
            ParametresEtablissementSeeder::class,
            PaieReferentielSeeder::class,
            TvaReferentielSeeder::class,
            NotificationsModelesSeeder::class,
        ]);
    }
}

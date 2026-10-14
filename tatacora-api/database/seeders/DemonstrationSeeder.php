<?php

declare(strict_types=1);

namespace Database\Seeders;

use Illuminate\Database\Seeder;

/**
 * Jeu de démonstration du Gîte Chez Noël — les 14 modules, un seul auteur par
 * référentiel. Lancé EXPLICITEMENT, jamais par défaut :
 *
 *     php artisan db:seed --class=DemonstrationSeeder
 *
 * ## Pourquoi il a quitté `DatabaseSeeder` (directive PO du 14/10/2026)
 *
 * « L'application doit démarrer avec une base vierge pour saisir ses propres
 * données réelles. » `php artisan migrate:fresh --seed` ne sème plus que les
 * référentiels indispensables ({@see DatabaseSeeder}). Les fichiers de
 * démonstration sont CONSERVÉS — `AmorcageDemonstrationTest` et les tests PWA
 * qui exigent une base peuplée les exécutent réellement — mais regroupés ici,
 * derrière une classe qu'on doit nommer pour la lancer.
 *
 * ## L'arbitrage (i)(j)(k) du 31/08/2026 : la démonstration COMPLÈTE fait foi
 *
 * Le Product Owner a tranché que le jeu de démonstration montre les quatorze
 * modules. Les six cas rouges d'`AmorcageDemonstrationTest` tombaient donc par
 * les DONNÉES, jamais en abaissant une attente.
 *
 * ## La règle qui structure cet ordre : UN SEUL AUTEUR PAR RÉFÉRENTIEL
 *
 * Elle vient d'un défaut réel, corrigé le 31/08/2026 sur le parc
 * ({@see \Database\Seeders\HebergementExploitationSeeder}) : deux seeders
 * semaient chacun un parc, avec des LIBELLÉS différents, si bien que chacun se
 * croyait idempotent et qu'aucun ne voyait l'autre. Un parc dédoublé fait
 * apparaître LIBRE une unité déjà prise — RG-01 contournée par la porte de
 * derrière.
 *
 * Le même défaut existait sur quatre autres référentiels, et il est corrigé ici :
 *
 * | Référentiel        | Auteur unique retenu | Second auteur, et ce qu'il produisait  |
 * |--------------------|----------------------|----------------------------------------|
 * | Parc d'hébergement | `HebergementSeeder`  | `HebergementExploitationSeeder` (6 catégories pour 3) |
 * | Points & articles  | `StocksSeeder`       | `ArticlesStockSeeder` (56 articles, dont 18 doublons du bar) |
 * | Fournisseurs       | `FournisseurSeeder`  | `FournisseursCommandesSeeder` (4 fournisseurs pour 6) |
 * | Parc de véhicules  | `VehiculeSeeder`     | `LocationsTourismeSeeder` (6 véhicules pour 5) |
 * | Circuits & guides  | `TourismeSeeder`     | `LocationsTourismeSeeder` (4 circuits pour 5) |
 *
 * `ArticlesStockSeeder` et `FournisseursCommandesSeeder` sont SUPPRIMÉS, pas
 * seulement décrochés de cette liste : un second auteur laissé en place dans
 * le répertoire est un `db:seed --class=` de distance du défaut qu'on vient de
 * corriger. `HebergementExploitationSeeder` et `LocationsTourismeSeeder`, eux,
 * sont CONSERVÉS et réduits à ce qu'ils sont : de l'exploitation posée sur des
 * référentiels qu'ils LISENT.
 *
 * ## Deuxième règle, de la même vague : les données soumises à une RG passent par le service
 *
 * Cinq blocs écrivaient en `DB::table()` sur des tables gardées par un verrou
 * pessimiste ou par une règle de gestion — réservations (RG-01), contrats de
 * location (RG-08/RG-09), départs en circuit (RG-13), commandes d'achat. Une
 * insertion directe contourne la garantie **sans la moindre erreur visible**.
 * Tous passent désormais par leur `Service`, connectés à un compte réel pour
 * que l'auteur existe (RG-15).
 *
 * ## L'ordre est conservé tel quel, référentiels compris
 *
 * Les référentiels de `DatabaseSeeder` sont rappelés ici À LEUR PLACE
 * d'origine, pas en tête : la TVA est activée APRÈS l'exploitation de
 * démonstration, et la déplacer changerait ce que les ventes de démonstration
 * comptabilisent. Tous sont idempotents (second `db:seed` éprouvé par
 * `AmorcageDemonstrationTest`), donc relancer la démonstration sur une base
 * déjà amorcée par `migrate:fresh --seed` ne double rien.
 *
 * Dév/Recette UNIQUEMENT — jamais en pipeline Production
 * (`SEEDER_TEST_LARAVEL.md`). `UtilisateurSeeder` pose des mots de passe de
 * démonstration et refuse de tourner hors local/development/testing.
 *
 * @see tests/Feature/Seeders/AmorcageDemonstrationTest.php qui EXÉCUTE réellement cet enchaînement
 */
class DemonstrationSeeder extends Seeder
{
    /**
     * Exécute les seeders dans l'ordre chronologique de dépendance.
     */
    public function run(): void
    {
        $this->call([
            // 1. SOCLE SÉCURITÉ & SESSIONS (Matrice RBAC + Comptes de démonstration)
            RolePermissionSeeder::class,
            UtilisateurSeeder::class,

            // 2. RÉFÉRENTIELS DE BASE (Clients, Personnel, Fournisseurs)
            //
            // Les canaux AVANT l'exploitation : `HebergementExploitationSeeder`
            // pose des séjours qui les référencent (PA-163).
            CanauxReservationSeeder::class,
            ClientSeeder::class,
            PersonnelSeeder::class,
            FournisseurSeeder::class,

            // 3. PARCS, STOCKS & CARTES — `StocksSeeder` ouvre les quatre
            // points de stockage : `BarSeeder` et `RestaurantSeeder` les LISENT.
            HebergementSeeder::class,
            StocksSeeder::class,
            BarSeeder::class,
            RestaurantSeeder::class,
            TablesSalleSeeder::class,

            // 4. MOBILITÉ & TOURISME (deux référentiels, puis l'exploitation qui les LIT)
            VehiculeSeeder::class,
            TourismeSeeder::class,
            LocationsTourismeSeeder::class,

            // 5. CAISSES & EXPLOITATION DYNAMIQUE
            HebergementExploitationSeeder::class,
            SessionCaisseSeeder::class,
            AchatsDemonstrationSeeder::class,
            ExploitationDemonstrationSeeder::class,

            // 6. RÉFÉRENTIEL COMPTABLE, puis les écritures qui en dépendent :
            // `DepensesSeeder` passe par `DepenseService`, qui exige un plan
            // comptable, des journaux et un exercice ouvert.
            ComptabiliteReferentielSeeder::class,

            // 7. RÉFÉRENTIELS DE PARAMÈTRES — aucun taux n'y est « complété »
            // (PA-53) ; `AmorcageDemonstrationTest` le vérifie clé par clé.
            PaieReferentielSeeder::class,
            TvaReferentielSeeder::class,
            // `ParametresEtablissementSeeder` (paramètres réels du PO) n'est
            // PAS rappelé ici : hôte SMTP et bascules changeraient le
            // comportement des tests qui exécutent la démonstration.

            // 8. RÉFÉRENTIEL DE NOTIFICATIONS (M12)
            NotificationsModelesSeeder::class,

            DepensesSeeder::class,
            VentesSeeder::class,
        ]);
    }
}

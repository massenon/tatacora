<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;

/**
 * MySQL/MariaDB, révisé 15/08/2026 (remplace la version PostgreSQL de cette
 * migration — décision d'architecture : environnement de développement local
 * = Laragon, résout PA-02/PA-03, 03_DATABASE_ENGINEERING.md v1.8).
 *
 * MySQL n'a pas de système d'extensions comme PostgreSQL — cette migration
 * n'a donc plus de contenu utile et est conservée UNIQUEMENT pour ne pas
 * décaler la numérotation des migrations suivantes (Laravel exécute les
 * migrations dans l'ordre de leur timestamp de nom de fichier).
 *
 * Ce que chaque extension PostgreSQL couvrait, et son remplacement MySQL :
 * - uuid-ossp (génération d'UUID côté serveur) : inutile — Laravel génère
 *   les UUID en PHP (Str::uuid()) dans les seeders/factories, jamais côté SQL.
 * - btree_gist (contraintes EXCLUDE USING gist, RG-01/RG-08/RG-13) : remplacée
 *   par VerificationChevauchementService, verrou pessimiste applicatif
 *   (03_DATABASE_ENGINEERING.md §3).
 * - pg_trgm (recherche floue par similarité trigram) : PAS ENCORE RÉSOLUE —
 *   MOTEUR_DE_RECHERCHE_GLOBALE_TOPBAR.md dépend directement de cette
 *   extension (opérateur %, fonction similarity()) et doit être revu séparément
 *   avant l'implémentation de la recherche globale (nouveau point d'action).
 */
return new class () extends Migration {
    public function up(): void
    {
        // Intentionnellement vide sur MySQL — voir le commentaire ci-dessus.
    }

    public function down(): void
    {
        // Intentionnellement vide sur MySQL.
    }
};

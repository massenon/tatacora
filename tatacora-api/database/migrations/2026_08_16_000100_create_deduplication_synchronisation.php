<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Table technique de deduplication des operations de synchronisation.
 *
 * Exigee par LARAVEL_SYNC_FLUTTER.md §5 (idempotence, TTL 7 jours) et par
 * LISTE_DES_CRON_JOBS_CPANEL.md (`NettoyerDeduplicationSyncJob`), mais
 * ABSENTE de FULL_MIGRATIONS_DATABASE.md — ecart signale en PA-43.
 *
 * ## Pourquoi elle est indispensable
 *
 * Si le reseau coupe APRES que le serveur a traite une operation mais AVANT
 * que le client ne recoive la reponse, le client ne peut pas savoir si elle a
 * abouti : il la renverra. Sans deduplication, une reservation creee hors
 * connexion serait creee deux fois — et sur `mouvements_stock`, une sortie
 * serait comptee deux fois, faussant le stock sans qu'aucune erreur ne
 * l'indique.
 *
 * Le resultat complet est memorise, pas seulement le fait d'avoir traite :
 * le client doit recevoir la MEME reponse au rejeu, y compris un rejet
 * RG-01 ou un identifiant de conflit.
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::create('deduplication_synchronisation', function (Blueprint $table) {
            $table->uuid('id')->primary();

            // UUID de la TENTATIVE de synchronisation, distinct de l'entite
            // metier (LARAVEL_SYNC_FLUTTER.md §2.1). Unique : c'est lui qui
            // porte toute la garantie d'idempotence.
            $table->uuid('uuid_operation')->unique();

            $table->foreignUuid('utilisateur_id')->constrained('utilisateurs')->restrictOnDelete();
            $table->string('poste_id');
            $table->string('table_concernee');
            $table->uuid('entite_id');

            // Reponse renvoyee au client lors du premier traitement, restituee
            // telle quelle en cas de rejeu.
            $table->json('resultat');

            // Horodatage de SAISIE du poste ayant ecrit cette entite.
            //
            // LARAVEL_SYNC_FLUTTER.md §4.2 resout les conflits non-financiers
            // par « horodatage_client le plus recent » — ce qui suppose de
            // connaitre celui de l'ECRIVAIN PRECEDENT. Or §4.1 ne fait
            // persister que la date de modification serveur, et aucune table de
            // la collection ne conserve l'horodatage de saisie. Sans cette
            // colonne, la regle est inapplicable : voir PA-44.
            //
            // Cas concret que cela corrige : le poste A saisit a 10h et
            // synchronise a 14h ; le poste B saisit a 11h et synchronise a
            // 14h05. B est plus recent EN SAISIE, mais comparer son horodatage
            // a la date de modification serveur (14h) ferait gagner A.
            $table->timestamp('horodatage_client')->nullable()->index();

            $table->timestamp('date_traitement')->useCurrent();

            // Recherche du dernier ecrivain d'une entite donnee.
            $table->index(['entite_id', 'horodatage_client']);

            // Purge par anciennete (TTL 7 jours) — NettoyerDeduplicationSyncJob.
            $table->index('date_traitement');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('deduplication_synchronisation');
    }
};

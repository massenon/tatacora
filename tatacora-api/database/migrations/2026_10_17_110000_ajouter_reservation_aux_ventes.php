<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * La RÉSERVATION d'une vente sur note de chambre — lot F5, décision du
 * Product Owner du 17/10/2026 (« POS hébergés … des autres postes, et en
 * synchronisation »).
 *
 * Une vente en note de chambre est une créance d'UN séjour. Jusqu'ici elle
 * ne le disait que par le client et le numéro d'unité (`table`) : un poste
 * qui la reçoit ne saurait pas à quelle réservation la rattacher sans le
 * DEVINER (même client, même chambre, à la bonne date). La colonne le dit.
 * Nullable : une vente au comptoir n'en a pas, et les ventes en note
 * antérieures ne sont pas reconstituées (aucune donnée déduite).
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::table('ventes', function (Blueprint $table) {
            $table->foreignUuid('reservation_id')
                ->nullable()
                ->after('client_id')
                ->constrained('reservations')
                ->restrictOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('ventes', function (Blueprint $table) {
            $table->dropConstrainedForeignId('reservation_id');
        });
    }
};

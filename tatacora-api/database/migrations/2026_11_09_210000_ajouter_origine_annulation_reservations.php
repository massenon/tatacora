<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\Schema;

/**
 * Qui a annulé une réservation DEPUIS UN POSTE, et depuis lequel (09/11/2026,
 * constats du PO : « B reçoit seulement l'information annulée sans l'auteur »).
 *
 * `utilisateur_annulation_id` désigne un compte du SERVEUR : pour une annulation
 * envoyée par un poste, c'est le compte du jeton d'appairage, jamais la personne qui
 * a cliqué. Le LOGIN LOCAL de l'auteur et l'identifiant du poste sont donc posés ici,
 * par `GestionnaireReservations`, pour que l'onglet « Annulations » affiche la même
 * personne au web et sur tous les postes, et que le journal d'audit (`Auditable`)
 * garde l'auteur local, le poste et la date.
 *
 * Deux colonnes NULLABLES, aucune valeur déduite : une annulation faite au web, ou
 * d'avant cette migration, les laisse vides.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('reservations', function ($table): void {
            if (! Schema::hasColumn('reservations', 'annulee_par_login')) {
                $table->string('annulee_par_login', 150)->nullable()->after('utilisateur_annulation_id');
            }

            if (! Schema::hasColumn('reservations', 'annulee_depuis_poste')) {
                $table->string('annulee_depuis_poste', 100)->nullable()->after('annulee_par_login');
            }
        });
    }

    public function down(): void
    {
        Schema::table('reservations', function ($table): void {
            foreach (['annulee_depuis_poste', 'annulee_par_login'] as $colonne) {
                if (Schema::hasColumn('reservations', $colonne)) {
                    $table->dropColumn($colonne);
                }
            }
        });
    }
};

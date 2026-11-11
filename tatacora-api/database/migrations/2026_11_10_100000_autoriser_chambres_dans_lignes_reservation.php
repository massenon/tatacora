<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * RÉSERVATION MULTI-CHAMBRES (décision du PO du 10/11/2026 : « pour UNE SEULE réservation un
 * client peut réserver UNE ou PLUSIEURS chambres »).
 *
 * `reservations.unite_id` reste la PREMIÈRE chambre (compatibilité : RG-01, le plan, les postes
 * anciens). Les chambres SUIVANTES sont des lignes `lignes_reservation` de service
 * `hebergement` : `source_id` = l'unité, `quantite` = les nuitées, `prix_unitaire` = le tarif de
 * nuit FIGÉ, `libelle` figé — elles voyagent avec la fiche (descente, envoi) sans table de plus.
 * La migration ouvre seulement le CHECK du service ; rien n'est réécrit, aucune ligne existante
 * n'est touchée.
 */
return new class () extends Migration {
    public function up(): void
    {
        DB::statement('ALTER TABLE lignes_reservation DROP CHECK chk_lignes_resa_service');
        DB::statement(
            "ALTER TABLE lignes_reservation ADD CONSTRAINT chk_lignes_resa_service CHECK (service IN ('hebergement', 'restauration', 'bar', 'tourisme', 'vehicule'))",
        );
    }

    public function down(): void
    {
        DB::table('lignes_reservation')->where('service', 'hebergement')->delete();
        DB::statement('ALTER TABLE lignes_reservation DROP CHECK chk_lignes_resa_service');
        DB::statement(
            "ALTER TABLE lignes_reservation ADD CONSTRAINT chk_lignes_resa_service CHECK (service IN ('restauration', 'bar', 'tourisme', 'vehicule'))",
        );
    }
};

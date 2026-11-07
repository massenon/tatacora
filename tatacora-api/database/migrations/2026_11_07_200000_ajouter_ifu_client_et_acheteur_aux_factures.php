<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * FACTURATION NORMALISÉE (décision du PO du 07/11/2026, point 2) : l'IFU du CLIENT
 * est demandé à la validation de la facturation, dans chaque flux. Facultatif :
 * vide, c'est un client sans IFU (le boîtier comme e-MECeF l'acceptent).
 *
 *  - `factures.acheteur_ifu` / `factures.acheteur_nom` : ce qui a été SAISI pour CETTE
 *    facture (13 chiffres ou NULL ; le nom tel qu'il part à la normalisation). Figés
 *    avec la facture : l'IFU d'un client peut changer, la facture ne bouge pas.
 *  - `clients.ifu` : « Retenir pour ce client » (case décochée par défaut) range la
 *    saisie sur la fiche pour préremplir la facture suivante.
 *
 * Additive et CONDITIONNELLE, colonnes NULLABLES : rien n'est déduit ni rejoué.
 */
return new class () extends Migration {
    public function up(): void
    {
        if (! Schema::hasColumn('clients', 'ifu')) {
            Schema::table('clients', function (Blueprint $t): void {
                $t->string('ifu', 13)->nullable();
            });
        }

        Schema::table('factures', function (Blueprint $t): void {
            if (! Schema::hasColumn('factures', 'acheteur_ifu')) {
                $t->string('acheteur_ifu', 13)->nullable();
            }
            if (! Schema::hasColumn('factures', 'acheteur_nom')) {
                $t->string('acheteur_nom', 100)->nullable();
            }
        });
    }

    public function down(): void
    {
        Schema::table('factures', function (Blueprint $t): void {
            foreach (['acheteur_ifu', 'acheteur_nom'] as $colonne) {
                if (Schema::hasColumn('factures', $colonne)) {
                    $t->dropColumn($colonne);
                }
            }
        });

        if (Schema::hasColumn('clients', 'ifu')) {
            Schema::table('clients', function (Blueprint $t): void {
                $t->dropColumn('ifu');
            });
        }
    }
};

<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Le NUMÉRO CONTINU des factures et des avoirs — lot F5c, décision du
 * Product Owner du 17/10/2026 (Q2 : « le serveur attribue le numéro, la
 * synchronisation régularise, les postes s'actualisent du numéro que le
 * serveur a attribué » ; puis « F-AAAA-NNNNN au serveur »).
 *
 * Jusqu'ici une facture du serveur n'avait que son numéro MECeF, vide tant
 * que la certification réelle n'est pas lancée (PA-17) : aucun numéro
 * continu. Désormais `F-AAAA-NNNNN` pour une facture, `AV-AAAA-NNNNN` pour un
 * avoir, alloués sous verrou par `SequenceDocumentService` à la création —
 * pour TOUTES les factures (celles des postes à leur arrivée, celles de la
 * PWA). Les pièces déjà émises restent SANS numéro (décision du PO : rien
 * n'est reconstitué) — d'où la colonne nullable.
 *
 * `lignes_facture.prix_catalogue` : le prix auquel la ligne a été VENDUE
 * (celui du catalogue ou du poste), avant la ventilation hors taxe. Sans lui,
 * un poste qui reçoit la facture ne lirait qu'un hors-taxe à centimes, qu'il
 * ne sait pas tenir en francs entiers ; et la facture ne dirait plus le prix
 * remis au client. Nullable : les lignes d'avant n'en ont pas.
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::table('factures', function (Blueprint $table) {
            $table->string('numero')->nullable()->unique()->after('id');
            // L'origine de la facture, comme au poste : `pos_comptant`,
            // `pos_sejour`, `facture_directe`. Nullable : les factures
            // d'avant ne la disent pas, et elle ne se devine pas.
            $table->string('origine', 30)->nullable()->after('numero');
        });
        Schema::table('avoirs', function (Blueprint $table) {
            $table->string('numero')->nullable()->unique()->after('id');
        });
        Schema::table('lignes_facture', function (Blueprint $table) {
            $table->decimal('prix_catalogue', 15, 2)->nullable()->after('prix_unitaire');
        });
    }

    public function down(): void
    {
        Schema::table('lignes_facture', function (Blueprint $table) {
            $table->dropColumn('prix_catalogue');
        });
        Schema::table('avoirs', function (Blueprint $table) {
            $table->dropUnique(['numero']);
            $table->dropColumn('numero');
        });
        Schema::table('factures', function (Blueprint $table) {
            $table->dropUnique(['numero']);
            $table->dropColumn(['numero', 'origine']);
        });
    }
};

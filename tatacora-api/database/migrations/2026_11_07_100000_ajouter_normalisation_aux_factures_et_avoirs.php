<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * FACTURATION NORMALISÉE (07/11/2026, décision du PO) : le résultat de la
 * normalisation d'une facture ou d'un avoir — par le boîtier CC300 d'un poste
 * (rangé par la synchronisation, sans que le serveur re-certifie) ou par
 * e-MECeF (certifié par le serveur). Toutes les colonnes sont NULLABLES et
 * l'ajout est CONDITIONNEL : une pièce d'avant n'est ni « normalisée » ni « en
 * attente » (NULL), rien n'est déduit ni rejoué.
 *
 * `factures.numero_mecef` et `qr_code_fiscal` existent déjà ; les avoirs
 * reçoivent les deux aussi (un avoir normalisé a sa propre identité fiscale).
 */
return new class () extends Migration {
    /** @var list<string> */
    private const COLONNES = [
        'normalisation_statut', 'normalisation_motif', 'normalisation_mode',
        'normalisation_compteur', 'code_mecef', 'normalisee_le',
        // e-MECeF (lot 3) : la facture créée à la DGI et non confirmée (`uid`, valable
        // 2 minutes) et le prochain essai (limite de débit, réseau).
        'emecef_uid', 'emecef_uid_le', 'emecef_prochain_essai_le',
    ];

    public function up(): void
    {
        foreach (['factures', 'avoirs'] as $table) {
            Schema::table($table, function (Blueprint $t) use ($table): void {
                if (! Schema::hasColumn($table, 'normalisation_statut')) {
                    $t->string('normalisation_statut', 20)->nullable();
                }
                if (! Schema::hasColumn($table, 'normalisation_motif')) {
                    $t->string('normalisation_motif', 500)->nullable();
                }
                if (! Schema::hasColumn($table, 'normalisation_mode')) {
                    $t->string('normalisation_mode', 10)->nullable();
                }
                if (! Schema::hasColumn($table, 'normalisation_compteur')) {
                    $t->string('normalisation_compteur', 30)->nullable();
                }
                if (! Schema::hasColumn($table, 'code_mecef')) {
                    $t->string('code_mecef', 64)->nullable();
                }
                if (! Schema::hasColumn($table, 'normalisee_le')) {
                    $t->timestamp('normalisee_le')->nullable();
                }
                if (! Schema::hasColumn($table, 'emecef_uid')) {
                    $t->string('emecef_uid', 64)->nullable();
                }
                if (! Schema::hasColumn($table, 'emecef_uid_le')) {
                    $t->timestamp('emecef_uid_le')->nullable();
                }
                if (! Schema::hasColumn($table, 'emecef_prochain_essai_le')) {
                    $t->timestamp('emecef_prochain_essai_le')->nullable();
                }
            });
        }

        Schema::table('avoirs', function (Blueprint $t): void {
            if (! Schema::hasColumn('avoirs', 'numero_mecef')) {
                $t->string('numero_mecef', 60)->nullable();
            }
            if (! Schema::hasColumn('avoirs', 'qr_code_fiscal')) {
                $t->string('qr_code_fiscal', 255)->nullable();
            }
        });
    }

    public function down(): void
    {
        Schema::table('avoirs', function (Blueprint $t): void {
            $t->dropColumn(['numero_mecef', 'qr_code_fiscal']);
        });

        foreach (['avoirs', 'factures'] as $table) {
            Schema::table($table, function (Blueprint $t): void {
                $t->dropColumn(self::COLONNES);
            });
        }
    }
};

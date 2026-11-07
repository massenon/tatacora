<?php

declare(strict_types=1);

use Database\Migrations\Concerns\HasAuditColumns;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * FACTURE PROFORMA (PO, 07/11/2026) — document NON FISCAL : aucune colonne MECeF, QR ou normalisation,
 * aucune écriture comptable, aucun mouvement de stock (docs/SPEC_FACTURE_PROFORMA.md).
 *
 *  - `proformas.numero` / `annee` / `rang` : le numéro `N°0045 FP-GCN/2026`, alloué par le SERVEUR à
 *    l'ÉMISSION (un brouillon n'en a pas). L'unicité `(annee, rang)` est le dernier rempart de la séquence.
 *  - `proformas.reference` : la RÉFÉRENCE FACTURE du réglage, COPIÉE à l'émission (changer le réglage
 *    ne renumérote rien) ; `valide_jusqu_au` : calculée à l'émission, ENREGISTRÉE.
 *  - `proformas.facture_id` (unique) et `factures.proforma_id` : les deux se répondent ; la conversion est unique.
 *  - `lignes_proforma` : désignation libre, quantité entière, prix unitaire TTC en FCFA entiers.
 *
 * Additive et conditionnelle (Schema::hasTable / hasColumn).
 */
return new class () extends Migration {
    use HasAuditColumns;

    public function up(): void
    {
        if (! Schema::hasTable('proformas')) {
            Schema::create('proformas', function (Blueprint $table): void {
                $table->uuid('id')->primary();
                $table->string('numero', 40)->nullable()->unique();
                $table->unsignedSmallInteger('annee')->nullable();
                $table->unsignedInteger('rang')->nullable();
                $table->unique(['annee', 'rang']);
                $table->string('reference', 10)->nullable();
                $table->string('statut', 12)->default('brouillon');
                $table->foreignUuid('client_id')->nullable()->constrained('clients')->nullOnDelete();
                $table->string('client_nom', 150);
                $table->string('client_telephone', 40)->nullable();
                $table->string('client_ifu', 13)->nullable();
                $table->string('objet', 255)->nullable();
                $table->date('date_emission')->nullable();
                $table->string('ville', 80)->nullable();
                $table->date('valide_jusqu_au')->nullable();
                $table->unsignedBigInteger('total')->default(0);
                $table->uuid('facture_id')->nullable()->unique();
                $table->text('motif_annulation')->nullable();
                // Flux d'origine : `libre`, `location`, `tourisme`, `hebergement`, `evenement`.
                $table->string('source_module', 20)->default('libre');
                $table->uuid('source_id')->nullable();
                // Poste d'origine (synchronisation) ; null : créée sur le web.
                $table->string('origine', 30)->nullable();
                $this->auditColumns($table);
                $table->timestamps();
            });
        }

        if (! Schema::hasTable('lignes_proforma')) {
            Schema::create('lignes_proforma', function (Blueprint $table): void {
                $table->uuid('id')->primary();
                $table->foreignUuid('proforma_id')->constrained('proformas')->cascadeOnDelete();
                $table->unsignedSmallInteger('position')->default(0);
                $table->string('designation', 255);
                $table->unsignedInteger('quantite');
                $table->unsignedBigInteger('prix_unitaire');
                $table->unsignedBigInteger('montant');
                $table->timestamps();
            });
        }

        if (! Schema::hasColumn('factures', 'proforma_id')) {
            Schema::table('factures', function (Blueprint $table): void {
                $table->uuid('proforma_id')->nullable()->unique();
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('factures', 'proforma_id')) {
            Schema::table('factures', function (Blueprint $table): void {
                $table->dropColumn('proforma_id');
            });
        }
        Schema::dropIfExists('lignes_proforma');
        Schema::dropIfExists('proformas');
    }
};

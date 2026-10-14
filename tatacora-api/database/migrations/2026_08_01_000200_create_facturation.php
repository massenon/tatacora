<?php

declare(strict_types=1);

use Database\Migrations\Concerns\HasAuditColumns;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class () extends Migration {
    use HasAuditColumns;

    public function up(): void
    {
        Schema::create('factures', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('numero_mecef')->unique()->nullable(); // null tant que non certifiée
            $table->foreignUuid('client_id')->constrained('clients')->restrictOnDelete();
            $table->date('date_emission');
            $table->decimal('montant_ht', 15, 2);
            $table->decimal('montant_tva', 15, 2);
            $table->decimal('montant_ttc', 15, 2);
            $table->enum('statut', ['brouillon', 'en_attente_certification', 'certifiee', 'echec_certification'])
                ->default('brouillon');
            $table->string('qr_code_fiscal')->nullable();
            $this->auditColumns($table);
            $table->timestamps();
            // AUCUNE colonne "deleted_at" — RG-03, pas de suppression logique même,
            // seul l'avoir corrige les effets d'une facture certifiée.
        });

        Schema::create('lignes_facture', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('facture_id')->constrained('factures')->restrictOnDelete();
            // ⚠ Registre REEL : les CODES de module 'M1'|'M4'|'M5'|'M8'|'M9'
            // (RG-04) — corrige le 02/09/2026. Le commentaire d'origine
            // annoncait les noms de domaine ('hebergement'…) qu'AUCUN
            // ecrivain n'a jamais poses ; il avait fait deriver l'ecran M2
            // (filtre d'activite qui ne correspondait jamais).
            $table->string('source_module');
            $table->uuid('source_id'); // FK polymorphe vers la ligne d'origine du module
            $table->string('libelle');
            $table->decimal('quantite', 10, 2);
            $table->decimal('prix_unitaire', 15, 2);
            $table->decimal('montant', 15, 2);
            $table->timestamps();
        });

        Schema::create('avoirs', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('facture_id')->constrained('factures')->restrictOnDelete();
            $table->text('motif');
            $table->decimal('montant', 15, 2);
            $table->date('date_emission');
            $table->foreignUuid('utilisateur_validation_id')->constrained('utilisateurs')->restrictOnDelete();
            $table->timestamps();
        });

        Schema::create('sessions_caisse', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->enum('point_vente', ['reception', 'restaurant', 'bar']);
            $table->foreignUuid('utilisateur_ouverture_id')->constrained('utilisateurs')->restrictOnDelete();
            $table->timestamp('date_ouverture');
            $table->decimal('montant_fond', 15, 2);
            $table->timestamp('date_cloture')->nullable();
            $table->decimal('montant_theorique', 15, 2)->nullable();
            $table->decimal('montant_constate', 15, 2)->nullable();
            $table->timestamps();
        });

        Schema::create('paiements', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('facture_id')->constrained('factures')->restrictOnDelete();
            $table->foreignUuid('session_id')->constrained('sessions_caisse')->restrictOnDelete();
            $table->enum('mode_paiement', ['especes', 'mobile_money', 'carte', 'virement']);
            $table->decimal('montant', 15, 2);
            $table->timestamp('date_paiement');
            $this->auditColumns($table);
            $table->timestamps();
        });

        // Devis — modèle DISTINCT de facture (05_MODULE_SPECIFICATIONS.md §M2),
        // jamais de numéro MECeF, jamais soumis au pipeline d'immutabilité.
        Schema::create('devis', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('client_id')->constrained('clients')->restrictOnDelete();
            $table->date('date_emission');
            $table->decimal('montant_ttc', 15, 2);
            $table->enum('statut', ['propose', 'accepte', 'refuse', 'expire'])->default('propose');
            $table->foreignUuid('facture_id')->nullable()->constrained('factures')->nullOnDelete(); // si converti
            $this->auditColumns($table);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('devis');
        Schema::dropIfExists('paiements');
        Schema::dropIfExists('sessions_caisse');
        Schema::dropIfExists('avoirs');
        Schema::dropIfExists('lignes_facture');
        Schema::dropIfExists('factures');
    }
};

<?php

declare(strict_types=1);

use Database\Migrations\Concerns\HasAuditColumns;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Relances clients — l'onglet « Relances clients » du maître (PA-165).
 *
 * `m3-clients-creances.html` porte un historique des relances (Date, Client,
 * Canal, Montant réclamé, Promesse, Par) qu'aucune table ne pouvait recevoir.
 * Une relance n'est PAS un mouvement d'argent — c'est un fait de gestion
 * (« on a réclamé tant, le client a promis pour telle date ») : aucune
 * écriture comptable n'en découle, et c'est voulu. L'argent, lui, arrive par
 * `paiements` (`EncaissementFactureService`).
 *
 * `montant_reclame` est une PHOTOGRAPHIE du solde réclamé ce jour-là, figée :
 * le solde vivant se recalcule (PA-126), mais la relance doit garder ce qui a
 * été dit au client au moment de l'appel.
 *
 * @see docs/PLAN_ACTION_SEQUENCE_POST_AUDIT.md PA-165
 */
return new class () extends Migration {
    use HasAuditColumns;

    private const CONTRAINTES = [
        'chk_relances_canal' => "canal IN ('telephone', 'whatsapp', 'email', 'courrier', 'visite')",
        'chk_relances_montant' => 'montant_reclame >= 0',
    ];

    public function up(): void
    {
        Schema::create('relances_clients', function (Blueprint $table): void {
            $table->uuid('id')->primary();

            $table->foreignUuid('client_id')->constrained('clients')->restrictOnDelete();

            $table->date('date_relance');
            $table->string('canal', 20);
            $table->decimal('montant_reclame', 15, 2);

            // La promesse est un engagement du client, pas une certitude :
            // nullable — « il rappellera » n'a pas de date.
            $table->date('promesse')->nullable();

            $table->string('commentaire', 500)->nullable();

            $this->auditColumns($table);
            $table->timestamps();

            $table->index(['client_id', 'date_relance']);
        });

        foreach (self::CONTRAINTES as $nom => $expression) {
            DB::statement("ALTER TABLE relances_clients ADD CONSTRAINT {$nom} CHECK ({$expression})");
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('relances_clients');
    }
};

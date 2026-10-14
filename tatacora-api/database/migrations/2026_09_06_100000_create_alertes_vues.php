<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Alertes d'ouverture — l'état « vu » par utilisateur (audit du 01/09/2026).
 *
 * ## Ce que cette table N'EST PAS
 *
 * Elle ne stocke AUCUNE alerte. Les alertes de la cloche sont DÉRIVÉES à la
 * lecture des tables opérationnelles (stock sous seuil, caisse non clôturée,
 * arrivées du jour, créances anciennes) — stocker l'alerte elle-même la
 * ferait vieillir pendant que la condition disparaît, l'indicateur qui
 * affirme un état qu'il n'a plus vérifié (PA-59/60/61). Une alerte disparaît
 * d'elle-même quand sa condition cesse.
 *
 * Ce qui se stocke est le seul fait qui n'est dérivable de rien : « CET
 * utilisateur a vu CETTE alerte ». La clé (`cle_alerte`) est stable par
 * élément (`stock-seuil:<article>:<point>`, `caisse:<session>`…) pour que le
 * geste survive aux rechargements.
 *
 * @see App\Pwa\Support\AlertesOuverture
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::create('alertes_vues', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->uuid('utilisateur_id');
            $table->string('cle_alerte', 160);
            $table->timestamp('date_vue');

            $table->foreign('utilisateur_id')->references('id')->on('utilisateurs')->restrictOnDelete();
            $table->unique(['utilisateur_id', 'cle_alerte']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('alertes_vues');
    }
};

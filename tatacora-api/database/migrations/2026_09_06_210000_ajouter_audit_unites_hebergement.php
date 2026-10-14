<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class () extends Migration {
    /**
     * Colonnes d'audit sur `unites_hebergement` — préalable à l'onglet
     * « Restaurer » d'Import & Export (02/09/2026).
     *
     * Le tableau des archives du maître (`import-export.html` l.244-248) porte
     * « ARCHIVÉ LE » et « PAR ». Pour les véhicules, `Auditable` renseigne déjà
     * ces deux colonnes (migration 2026_08_28_000001) ; les unités
     * d'hébergement en étaient restées dépourvues — la seule des deux familles
     * archivables (statut `hors_service`) dont personne ne pouvait dire QUI
     * l'avait retirée du parc.
     *
     * Même gabarit que `ajouter_audit_referentiels` — les quatre colonnes de
     * `HasAuditColumns`, nullables : les lignes existantes n'ont pas d'auteur
     * connu, et « — » à l'écran est la seule réponse honnête pour elles.
     */
    public function up(): void
    {
        Schema::table('unites_hebergement', function (Blueprint $table) {
            $table->foreignUuid('utilisateur_creation_id')->nullable()
                ->constrained('utilisateurs')->nullOnDelete();
            $table->timestamp('date_creation')->nullable();
            $table->foreignUuid('utilisateur_modification_id')->nullable()
                ->constrained('utilisateurs')->nullOnDelete();
            $table->timestamp('date_modification')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('unites_hebergement', function (Blueprint $table) {
            $table->dropConstrainedForeignId('utilisateur_creation_id');
            $table->dropConstrainedForeignId('utilisateur_modification_id');
            $table->dropColumn(['date_creation', 'date_modification']);
        });
    }
};

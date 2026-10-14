<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class () extends Migration {
    /**
     * « Historique des imports » — `import-export.html`, colonne latérale de
     * l'onglet 1 (l.143-148) et `import-export-engine.js` §3 (02/09/2026).
     *
     * Le maître journalise chaque import confirmé — module, nombre de lignes,
     * date/heure, auteur — et le rend dans la colonne latérale. `journal_audit`
     * ne peut pas porter cette liste : il est « alimenté exclusivement par le
     * Trait Auditable » (2026_08_01_001200) et trace chaque LIGNE créée, pas le
     * LOT ; reconstituer « 14 lignes importées » depuis 14 entrées d'audit
     * serait une agrégation fragile sur un journal fait pour autre chose.
     *
     * Table de TRACE, jamais purgée par la réinitialisation des données de
     * test (le maître préserve `tatacora_historique_imports`, engine l.520).
     */
    public function up(): void
    {
        Schema::create('journal_imports', function (Blueprint $table) {
            $table->uuid('id')->primary();
            // La clé du référentiel importé (`m6-stocks`…) — registre fermé
            // `ReferentielsImport`, jamais un libellé recomposé à l'affichage.
            $table->string('module_cle', 40);
            $table->unsignedInteger('nombre_lignes');
            $table->foreignUuid('utilisateur_id')->nullable()->constrained('utilisateurs')->nullOnDelete();
            $table->timestamp('date_heure')->useCurrent();

            $table->index('date_heure');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('journal_imports');
    }
};

<?php

// database/migrations/Concerns/HasAuditColumns.php

declare(strict_types=1);

namespace Database\Migrations\Concerns;

use Illuminate\Database\Schema\Blueprint;

trait HasAuditColumns
{
    /**
     * Colonnes d'audit systématiques (03_DATABASE_ENGINEERING.md §15) :
     * auteur et horodatage de création/modification, sur toute table transactionnelle.
     */
    protected function auditColumns(Blueprint $table): void
    {
        $table->foreignUuid('utilisateur_creation_id')->nullable()
            ->constrained('utilisateurs')->nullOnDelete();
        $table->timestamp('date_creation')->useCurrent();
        $table->foreignUuid('utilisateur_modification_id')->nullable()
            ->constrained('utilisateurs')->nullOnDelete();
        $table->timestamp('date_modification')->nullable();
    }
}

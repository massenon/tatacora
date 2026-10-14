<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Colonnes d'audit manquantes sur `parametres_systeme`.
 *
 * La table portait `utilisateur_modification_id` seul — assez pour dire QUI a
 * touché la ligne, pas assez pour le trait `Auditable`, qui renseigne aussi
 * `date_creation`/`date_modification` et refuserait de démarrer sur une table
 * incomplète (« Unknown column »).
 *
 * Le trait est ce qui donne le **avant/après** dans `journal_audit` : changer
 * un taux de TVA ou de CNSS est exactement l'action que RG-15 existe pour
 * tracer, et la question posée après coup n'est jamais « qui ? » mais « à
 * partir de quelle valeur ? ». Sans l'ancienne valeur, une erreur de saisie
 * n'est pas corrigeable — personne ne sait vers quoi revenir.
 *
 * Migration **additive** : aucune colonne existante n'est touchée, et les
 * lignes déjà posées par les seeders gardent leur valeur.
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::table('parametres_systeme', function (Blueprint $table) {
            $table->foreignUuid('utilisateur_creation_id')->nullable()->after('description')
                ->constrained('utilisateurs')->nullOnDelete();
            $table->timestamp('date_creation')->nullable()->after('utilisateur_creation_id');
            $table->timestamp('date_modification')->nullable()->after('utilisateur_modification_id');
        });
    }

    public function down(): void
    {
        Schema::table('parametres_systeme', function (Blueprint $table) {
            $table->dropConstrainedForeignId('utilisateur_creation_id');
            $table->dropColumn(['date_creation', 'date_modification']);
        });
    }
};

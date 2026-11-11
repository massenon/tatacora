<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * L'AFFECTATION DU RÉSULTAT selon la FORME JURIDIQUE (09/11/2026, décision du
 * PO : « le Gîte est une entreprise individuelle »).
 *
 *  - `compte_exploitant` : la part du résultat portée au compte de l'exploitant
 *    (104x) d'une entreprise individuelle — crédit pour un bénéfice, débit pour
 *    une perte ; zéro dans une société ;
 *  - `forme_juridique` : la forme sous laquelle l'affectation a été passée
 *    (`entreprise_individuelle`, `sarl`, `sa`) — la forme ne se change pas tant
 *    qu'une affectation est active, mais l'historique la garde ;
 *  - `reference_decision_contrepassation` : la référence FACULTATIVE de la décision
 *    (PV d'assemblée / décision de l'exploitant) qui motive la contre-passation.
 *
 * Colonnes additives : une affectation passée avant ce lot garde zéro et
 * `null`, jamais une valeur devinée.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('affectations_resultat', function (Blueprint $table) {
            $table->decimal('compte_exploitant', 15, 2)->default(0)->after('report_a_nouveau_debiteur');
            $table->string('forme_juridique', 30)->nullable()->after('compte_exploitant');
            $table->string('reference_decision_contrepassation', 255)->nullable()->after('motif_contrepassation');
        });
    }

    public function down(): void
    {
        Schema::table('affectations_resultat', function (Blueprint $table) {
            $table->dropColumn(['compte_exploitant', 'forme_juridique', 'reference_decision_contrepassation']);
        });
    }
};

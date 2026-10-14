<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * M13 — ce qui manquait au dossier employe et au bulletin pour porter le maitre.
 *
 * Maitre : `prototype_v2/pages/m13-paie.html` et `m13-paie.js`.
 *
 * ## Dossier employe — quatre colonnes, chacune portee par un ecran du maitre
 *
 * - `matricule` : premiere colonne du tableau « Effectif », et l'identifiant
 *   que le bulletin de paie imprime. Il etait absent du schema, et l'ecran
 *   aurait du le fabriquer a l'affichage — un identifiant recalcule a chaque
 *   rendu change quand la liste change, ce qui est pire que pas d'identifiant.
 *   `nullable` : les dix employes semes avant cette migration n'en ont pas,
 *   et leur en inventer un retroactivement serait poser une donnee que
 *   personne n'a decidee. L'unicite est posee malgre le `nullable` — MySQL
 *   autorise plusieurs NULL sous un index unique.
 *
 * - `numero_cnss` : le maitre en fait un signal metier a part entiere (filtre
 *   « Sans n° CNSS », badge « absent », alerte « ne peuvent pas figurer a la
 *   declaration »). Le rendre depuis rien aurait affiche « absent » pour tout
 *   le monde sans qu'aucun chemin permette de le renseigner.
 *
 * - `type_contrat` : filtre du maitre (CDI, CDD, Stage, Journalier).
 *   `nullable`, meme raison que le matricule.
 *
 * - `date_fin_contrat` : le maitre l'affiche sous le contrat (« jusqu'au … »).
 *   Elle n'a de sens que pour un CDD ou un stage, d'ou le `nullable`.
 *
 * ## Bulletin de paie — le detail du calcul est STOCKE, pas recalcule
 *
 * `bulletins_paie` portait le net et un total de retenues, sans leur
 * decomposition. Recalculer la CNSS et l'ITS a l'affichage les reprendrait
 * aux taux D'AUJOURD'HUI : un bulletin de mars relu en decembre changerait de
 * montant si un taux avait bouge entre-temps, sur un document remis au
 * salarie et conserve sans limitation de duree. Les deux retenues sont donc
 * figees a l'etablissement, exactement comme `tarif_nuit` l'est a la
 * reservation (PA-55).
 *
 * `charges_patronales_confirmees` porte la part CERTAINE (CNSS pension 6,4 %,
 * prestations familiales 9 %, VPS 4 %). Le TOTAL de charge patronale n'a
 * volontairement AUCUNE colonne : le taux de risques professionnels est
 * « 1 % a 4 % selon l'activite » et n'est pas confirme pour
 * l'hotellerie-restauration (PA-53). Une colonne `charges_patronales_total`
 * appellerait un jour un chiffre, et ce chiffre serait suppose.
 *
 * `numero` : le maitre imprime un numero sur le bulletin. Il est alloue a
 * l'etablissement et persiste, jamais derive de la position dans une liste.
 *
 * `statut` gagne `annulee`, et `motif_annulation` avec lui : le maitre annule
 * un bulletin avec un motif obligatoire, et le conserve. Aucune suppression —
 * un bulletin annule reste tracable (RG-15).
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::table('employes', function (Blueprint $table): void {
            $table->string('matricule')->nullable()->unique()->after('id');
            $table->string('numero_cnss')->nullable()->after('date_embauche');
            $table->enum('type_contrat', ['CDI', 'CDD', 'Stage', 'Journalier'])
                ->nullable()->after('numero_cnss');
            $table->date('date_fin_contrat')->nullable()->after('type_contrat');
        });

        Schema::table('bulletins_paie', function (Blueprint $table): void {
            $table->string('numero')->nullable()->unique()->after('id');

            // Figees a l'etablissement — voir l'entete.
            $table->decimal('cnss_salarie', 15, 2)->default(0)->after('total_retenues');
            $table->decimal('its', 15, 2)->default(0)->after('cnss_salarie');

            // La part CERTAINE de la charge patronale. Aucun total : PA-53.
            $table->decimal('charges_patronales_confirmees', 15, 2)
                ->default(0)->after('charges_sociales');

            $table->text('motif_annulation')->nullable()->after('statut');
        });

        DB::statement(
            "ALTER TABLE bulletins_paie MODIFY statut ENUM('brouillon','validee','annulee') NOT NULL DEFAULT 'brouillon'",
        );
    }

    public function down(): void
    {
        // Comme pour l'enum des canaux M12 : les lignes que le schema d'arrivee
        // ne sait pas representer partent AVANT le retrecissement. Un bulletin
        // annule n'a pas d'equivalent dans l'ancien schema — le passer en
        // `brouillon` le ferait reapparaitre au livre de paie comme s'il etait
        // encore du, ce qui serait un faux montant a payer.
        DB::table('bulletins_paie')->where('statut', 'annulee')->delete();

        DB::statement(
            "ALTER TABLE bulletins_paie MODIFY statut ENUM('brouillon','validee') NOT NULL DEFAULT 'brouillon'",
        );

        Schema::table('bulletins_paie', function (Blueprint $table): void {
            $table->dropUnique(['numero']);
            $table->dropColumn([
                'numero', 'cnss_salarie', 'its',
                'charges_patronales_confirmees', 'motif_annulation',
            ]);
        });

        Schema::table('employes', function (Blueprint $table): void {
            $table->dropUnique(['matricule']);
            $table->dropColumn(['matricule', 'numero_cnss', 'type_contrat', 'date_fin_contrat']);
        });
    }
};

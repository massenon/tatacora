<?php

declare(strict_types=1);

use Database\Migrations\Concerns\HasAuditColumns;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Immobilisations (M10) — onglet « Immobilisations » du hub SYSCOHADA,
 * maître `prototype_v2/pages/m10-syscohada-etats.js` `vueImmobilisations()`.
 *
 * ## Ce que cette table NE fait PAS — nommé ici, pas découvert au premier bug
 *
 * Aucune écriture comptable de dotation n'est jamais passée à partir de cette
 * table dans ce lot. Le plan d'amortissement (`ImmobilisationService`) est
 * CALCULÉ à la demande, jamais stocké : c'est une lecture, au même titre que
 * `EtatClotureService`. Comptabiliser une dotation (débit 681, crédit 28x)
 * suppose des comptes vérifiés au plan comptable, ce que ce lot ne fait pas —
 * le geste attend l'arbitrage du Comptable, et son absence est nommée dans
 * `ImmobilisationService`, pas comblée par un compte deviné.
 *
 * ## `compte_immobilisation` est un VARCHAR, pas une clé étrangère
 *
 * Écart délibéré à la règle générale du dépôt (« tout champ relationnel est
 * une vraie clé étrangère ») : cette colonne ne sert AUCUNE jointure
 * aujourd'hui, faute d'écriture de dotation qui la consommerait. Elle est
 * néanmoins validée à la saisie contre `plan_comptable.numero_compte`
 * (`ImmobilisationService::creer()`), ce qui lui donne l'intégrité d'une
 * relation sans en payer le schéma tant qu'aucune jointure n'existe.
 *
 * ## Aucune colonne de centre analytique — le maître en porte une, pas ici
 *
 * `m10-syscohada-etats.js` l.361 pose un sélecteur de centre d'affectation.
 * Cette migration n'en porte pas : c'est le périmètre exact commandé par le
 * Product Owner pour ce lot, et l'ajouter aurait exigé une colonne NOT NULL
 * (RG-12, sur toute écriture) sur une table qui n'écrit encore rien au grand
 * livre. Écart nommé, non masqué.
 */
return new class () extends Migration {
    use HasAuditColumns;

    public function up(): void
    {
        Schema::create('immobilisations', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->string('code')->unique();
            $table->string('libelle');
            $table->decimal('valeur_origine', 15, 2);
            $table->unsignedSmallInteger('duree_annees');
            $table->date('date_mise_service');
            // Voir le docblock de classe : ni FK, ni NOT NULL.
            $table->string('compte_immobilisation', 20)->nullable();
            $this->auditColumns($table);
            $table->timestamps();
        });

        \Illuminate\Support\Facades\DB::statement(
            'ALTER TABLE immobilisations ADD CONSTRAINT chk_immobilisations_valeur_positive CHECK (valeur_origine > 0)',
        );
        \Illuminate\Support\Facades\DB::statement(
            'ALTER TABLE immobilisations ADD CONSTRAINT chk_immobilisations_duree_positive CHECK (duree_annees > 0)',
        );
    }

    public function down(): void
    {
        Schema::dropIfExists('immobilisations');
    }
};

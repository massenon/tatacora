<?php

declare(strict_types=1);

use Database\Migrations\Concerns\HasAuditColumns;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * Reprise du schema de `depenses` / `lignes_depense` — PA-159 lot 0b, T4.
 *
 * Trois defauts mesures contre `tatacora_dev` le 31/08/2026 :
 *
 *  1. `depenses.id` et `lignes_depense.id` sont auto-incrementes, contre la
 *     convention de cle du depot (`$table->uuid('id')`, fournie par le client).
 *  2. `depenses.utilisateur_id` est un `varchar(100)` — il CONTIENT deja des
 *     UUID d'utilisateurs valides, sans qu'aucune contrainte ne le garantisse.
 *     C'est exactement « du texte libre la ou une cle etrangere est requise ».
 *  3. `lignes_depense.depense_id` etait en `cascadeOnDelete()`, interdit sur
 *     une table transactionnelle.
 *
 * S'y ajoute `depenses.ecriture_id`, jusqu'ici un `varchar` que rien n'ecrivait
 * (`PasserEcritureService` n'existait pas — voir le service du meme nom, livre
 * avec cette migration). Il devient une vraie cle etrangere vers
 * `ecritures_comptables`.
 *
 * ## Ce que `ecriture_id` designe exactement
 *
 * La LIGNE DE TRESORERIE de la piece — l'unique credit qui porte le montant
 * total sorti de la caisse ou de la banque. Ce n'est pas « la piece » : PA-52
 * constate que `ecritures_comptables` n'a aucune colonne groupant les lignes
 * d'une meme piece, et rien ici ne repare cela. Reconstituer la piece complete
 * depuis cette colonne est donc impossible, et c'est ecrit plutot que suppose.
 * La ligne de tresorerie est retenue parce qu'elle est la seule dont il existe
 * exactement une par depense, quel que soit le nombre de comptes de charge
 * ventiles.
 */
return new class () extends Migration {
    use HasAuditColumns;

    private const DEPENSES_REPRISE = 'depenses_reprise_uuid';

    private const LIGNES_REPRISE = 'lignes_depense_reprise_uuid';

    public function up(): void
    {
        if (! Schema::hasTable('depenses') || ! Schema::hasTable('lignes_depense')) {
            return;
        }

        if (Schema::getColumnType('depenses', 'id') === 'char') {
            return;
        }

        Schema::rename('depenses', self::DEPENSES_REPRISE);
        Schema::rename('lignes_depense', self::LIGNES_REPRISE);

        // Nom de cle etrangere unique a l'echelle du schema en MySQL — voir la
        // note de `2026_09_01_100000_reprendre_ventes_en_uuid.php`.
        Schema::table(self::LIGNES_REPRISE, function (Blueprint $table): void {
            $table->dropForeign('lignes_depense_depense_id_foreign');
        });

        $this->creerDepenses();
        $this->creerLignesDepense();
        $this->recopierVersUuid();

        Schema::drop(self::LIGNES_REPRISE);
        Schema::drop(self::DEPENSES_REPRISE);
    }

    public function down(): void
    {
        if (! Schema::hasTable('depenses') || ! Schema::hasTable('lignes_depense')) {
            return;
        }

        if (Schema::getColumnType('depenses', 'id') !== 'char') {
            return;
        }

        Schema::rename('depenses', self::DEPENSES_REPRISE);
        Schema::rename('lignes_depense', self::LIGNES_REPRISE);

        Schema::table(self::LIGNES_REPRISE, function (Blueprint $table): void {
            $table->dropForeign('lignes_depense_depense_id_foreign');
        });

        $this->creerDepensesEntier();
        $this->creerLignesDepenseEntier();
        $this->recopierVersEntier();

        Schema::drop(self::LIGNES_REPRISE);
        Schema::drop(self::DEPENSES_REPRISE);
    }

    private function creerDepenses(): void
    {
        Schema::create('depenses', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->string('numero')->unique();
            $table->date('date_transaction');
            $table->string('tresorerie', 50)->default('caisse');
            $table->string('compte_tresorerie', 20)->default('5711');
            $table->decimal('montant_total', 15, 2)->default(0);
            $table->string('libelle');
            $table->string('recu_path')->nullable();
            $table->foreignUuid('ecriture_id')->nullable()
                ->constrained('ecritures_comptables')->restrictOnDelete();
            $table->text('ecriture_refus')->nullable();
            $table->foreignUuid('utilisateur_id')->nullable()
                ->constrained('utilisateurs')->restrictOnDelete();
            $table->json('lignes_json')->nullable();
            $this->auditColumns($table);
            $table->timestamps();

            $table->index('date_transaction');
            $table->index('tresorerie');
        });
    }

    private function creerLignesDepense(): void
    {
        Schema::create('lignes_depense', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->foreignUuid('depense_id')->constrained('depenses')->restrictOnDelete();
            $table->string('libelle')->nullable();
            $table->string('compte_charge', 20);
            $table->string('nature', 100);
            $table->string('famille', 50);
            $table->decimal('montant', 15, 2);
            $this->auditColumns($table);
            $table->timestamps();

            $table->index('compte_charge');
            $table->index('famille');
        });
    }

    private function recopierVersUuid(): void
    {
        // Les utilisateurs deja references le sont par un UUID reel : la
        // contrainte va desormais l'imposer. Un identifiant qui ne correspond
        // a aucun compte est RETIRE plutot que de faire echouer la reprise —
        // mais il est nomme, pas efface en silence.
        $utilisateursConnus = DB::table('utilisateurs')->pluck('id')->all();
        $utilisateursConnus = array_flip(array_map('strval', $utilisateursConnus));

        // Même contrôle sur `ecriture_id`, et pour une raison qui a failli
        // manquer : au moment d'écrire cette reprise, AUCUNE dépense n'avait
        // jamais produit d'écriture, et il était tentant de forcer la colonne
        // à NULL. Ce motif cesse d'être vrai dès la première dépense
        // comptabilisée — un retour arrière suivi d'une nouvelle migration
        // aurait alors effacé des liens valides, en silence. Un motif de
        // simplification qui a cessé d'être vrai est un oubli (PA-144).
        $ecrituresConnues = Schema::hasTable('ecritures_comptables')
            ? array_flip(array_map('strval', DB::table('ecritures_comptables')->pluck('id')->all()))
            : [];

        $correspondance = [];

        foreach (DB::table(self::DEPENSES_REPRISE)->orderBy('id')->get() as $ancienne) {
            $uuid = (string) Str::uuid();
            $correspondance[(int) $ancienne->id] = $uuid;

            $utilisateurId = $ancienne->utilisateur_id !== null
                ? (string) $ancienne->utilisateur_id
                : null;

            if ($utilisateurId !== null && ! isset($utilisateursConnus[$utilisateurId])) {
                echo '  depenses : utilisateur_id "'.$utilisateurId.'" inconnu sur la depense '
                    .$ancienne->numero.' — mis a NULL par la reprise.'.PHP_EOL;
                $utilisateurId = null;
            }

            $ecritureId = $ancienne->ecriture_id !== null ? (string) $ancienne->ecriture_id : null;

            if ($ecritureId !== null && ! isset($ecrituresConnues[$ecritureId])) {
                // La colonne etait un `varchar` libre : elle a pu contenir
                // n'importe quoi. Ce qui ne designe aucune ecriture reelle est
                // retire, et NOMME — le taire rendrait `estComptabilisee()`
                // vrai sur une depense que le grand livre ignore.
                echo '  depenses : ecriture_id "'.$ecritureId.'" inconnue sur la depense '
                    .$ancienne->numero.' — mise a NULL par la reprise.'.PHP_EOL;
                $ecritureId = null;
            }

            $ligne = (array) $ancienne;
            $ligne['id'] = $uuid;
            $ligne['utilisateur_id'] = $utilisateurId;
            $ligne['ecriture_id'] = $ecritureId;
            $ligne['date_creation'] = $ancienne->created_at ?? now();

            DB::table('depenses')->insert($ligne);
        }

        foreach (DB::table(self::LIGNES_REPRISE)->orderBy('id')->get() as $ancienneLigne) {
            $depenseUuid = $correspondance[(int) $ancienneLigne->depense_id] ?? null;

            if ($depenseUuid === null) {
                throw new RuntimeException(
                    'Ligne de depense '.$ancienneLigne->id.' rattachee a une depense absente ('
                    .$ancienneLigne->depense_id.') : reprise interrompue.',
                );
            }

            $ligne = (array) $ancienneLigne;
            $ligne['id'] = (string) Str::uuid();
            $ligne['depense_id'] = $depenseUuid;
            $ligne['date_creation'] = $ancienneLigne->created_at ?? now();

            DB::table('lignes_depense')->insert($ligne);
        }
    }

    private function creerDepensesEntier(): void
    {
        Schema::create('depenses', function (Blueprint $table): void {
            $table->id();
            $table->string('numero')->unique();
            $table->date('date_transaction');
            $table->string('tresorerie', 50)->default('caisse');
            $table->string('compte_tresorerie', 20)->default('5711');
            $table->decimal('montant_total', 15, 2)->default(0);
            $table->string('libelle');
            $table->string('recu_path')->nullable();
            $table->string('ecriture_id')->nullable();
            $table->text('ecriture_refus')->nullable();
            $table->string('utilisateur_id', 100)->nullable();
            $table->json('lignes_json')->nullable();
            $table->timestamps();

            $table->index('date_transaction');
            $table->index('tresorerie');
            $table->index('utilisateur_id');
        });
    }

    private function creerLignesDepenseEntier(): void
    {
        Schema::create('lignes_depense', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('depense_id')->constrained('depenses')->cascadeOnDelete();
            $table->string('libelle')->nullable();
            $table->string('compte_charge', 20);
            $table->string('nature', 100);
            $table->string('famille', 50);
            $table->decimal('montant', 15, 2);
            $table->timestamps();

            $table->index('compte_charge');
            $table->index('famille');
        });
    }

    private function recopierVersEntier(): void
    {
        $correspondance = [];

        foreach (DB::table(self::DEPENSES_REPRISE)->orderBy('created_at')->get() as $depense) {
            $ligne = (array) $depense;
            unset($ligne['id'], $ligne['utilisateur_creation_id'], $ligne['date_creation']);
            unset($ligne['utilisateur_modification_id'], $ligne['date_modification']);

            $correspondance[(string) $depense->id] = (int) DB::table('depenses')->insertGetId($ligne);
        }

        foreach (DB::table(self::LIGNES_REPRISE)->orderBy('created_at')->get() as $ligneDepense) {
            $depenseId = $correspondance[(string) $ligneDepense->depense_id] ?? null;

            if ($depenseId === null) {
                throw new RuntimeException(
                    'Ligne de depense '.$ligneDepense->id.' orpheline au retour arriere : interrompu.',
                );
            }

            $ligne = (array) $ligneDepense;
            unset($ligne['id'], $ligne['utilisateur_creation_id'], $ligne['date_creation']);
            unset($ligne['utilisateur_modification_id'], $ligne['date_modification']);
            $ligne['depense_id'] = $depenseId;

            DB::table('lignes_depense')->insert($ligne);
        }
    }
};

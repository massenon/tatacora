<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * `numero_piece` sur `ecritures_comptables` — commande du Product Owner
 * (Vague E, 01/09/2026), qui referme partiellement PA-52.
 *
 * ## Ce que PA-52 constatait, et ce que cette colonne change
 *
 * `EcritureComptableService` documentait qu'aucune colonne ne groupe les
 * lignes d'une même pièce : l'équilibre débit/crédit n'était garanti qu'À
 * L'ÉCRITURE (une transaction, plusieurs lignes), jamais vérifiable a
 * posteriori, faute d'identifiant reliant les lignes entre elles. Le Journal
 * et le Grand livre de la PWA affichaient donc une ligne par écriture, sans
 * numéro de pièce ni regroupement — deux écarts déclarés et datés dans
 * `onglets/journal.blade.php` et `onglets/grandlivre.blade.php`.
 *
 * Cette colonne EST l'identifiant qui manquait. Elle est écrite par
 * `PasserEcritureService::passer()` (seul point d'entrée modifié — voir son
 * docblock) sur TOUTES les lignes d'une même pièce, via
 * `SequenceDocumentService` : `<code_journal>-<année>-<n>`, par exemple
 * `OD-2026-00007`.
 *
 * ## Nullable, et c'est délibéré — jamais un numéro inventé pour le passé
 *
 * Les écritures passées avant ce lot n'ont et n'auront JAMAIS de
 * `numero_piece` : leur reconstituer un numéro après coup produirait une
 * numérotation qui ne reflète l'ordre d'aucune allocation réelle — exactement
 * le défaut que `SequenceDocumentService` existe pour éviter. Elles
 * s'affichent avec un tiret (`MontantFcfa::TIRET`), jamais un numéro
 * plausible (Article 7 : « — » quand la donnée n'existe pas).
 *
 * ## Index simple, jamais unique
 *
 * Une pièce de N lignes porte N FOIS le même `numero_piece` — c'est la
 * définition même du regroupement recherché. Un index UNIQUE rejetterait la
 * deuxième ligne de toute pièce à plus d'une ligne.
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::table('ecritures_comptables', function (Blueprint $table): void {
            $table->string('numero_piece', 20)->nullable()->after('journal_id');
            $table->index('numero_piece');
        });
    }

    public function down(): void
    {
        Schema::table('ecritures_comptables', function (Blueprint $table): void {
            $table->dropIndex(['numero_piece']);
            $table->dropColumn('numero_piece');
        });
    }
};

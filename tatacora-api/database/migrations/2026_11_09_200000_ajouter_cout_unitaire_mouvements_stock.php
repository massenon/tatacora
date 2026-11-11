<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * `mouvements_stock.cout_unitaire` — le COÛT d'achat de l'entrée valorisée
 * (bug du PO du 09/11/2026 : un second poste voyait « — » en Valeur d'achat,
 * CMP et Valeur stock).
 *
 * Jusqu'ici le coût n'existait qu'en deux endroits dérivés — `articles.prix_achat`
 * (le dernier) et `articles.cout_moyen_pondere` (le courant) — jamais sur le
 * mouvement qui l'a produit. Or un poste ne reçoit AUCUNE valeur calculée : il
 * RECALCULE le CMP en rejouant les mouvements, et sans le coût de chaque entrée il
 * n'avait rien à rejouer. Le coût est donc écrit sur le mouvement, par
 * `MouvementStockService::entree` (point d'écriture unique), et descend avec lui.
 *
 * `DECIMAL(15,4)` : la précision du CMP. `NULL` = entrée non valorisée (transfert,
 * retour), sortie, perte, inventaire.
 *
 * ## Rattrapage de l'existant — seulement ce qui se PROUVE
 *
 * Une entrée valorisée saisie sur un POSTE a son coût dans le journal de réception
 * (`journal_reception_synchronisation.payload`, en dix-millièmes de franc) : il est
 * recopié sur le mouvement de même identifiant. Une entrée saisie au web ou par
 * l'API avant cette migration n'a conservé son coût nulle part : elle reste `NULL`,
 * aucune valeur n'est déduite du CMP.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('mouvements_stock', 'cout_unitaire')) {
            Schema::table('mouvements_stock', function ($table): void {
                $table->decimal('cout_unitaire', 15, 4)->nullable()->after('quantite');
            });
        }

        if (! Schema::hasTable('journal_reception_synchronisation')) {
            return;
        }

        DB::table('journal_reception_synchronisation')
            ->where('table_concernee', 'mouvements_stock')
            ->where('type_operation', 'creation')
            ->where('issue', 'acceptee')
            ->orderBy('id')
            ->chunk(200, function ($lignes): void {
                foreach ($lignes as $ligne) {
                    $json = $ligne->payload_corrige ?? $ligne->payload;
                    $charge = is_string($json) ? json_decode($json, true) : null;
                    $cout = is_array($charge) ? ($charge['cout_unitaire'] ?? null) : null;

                    if (! is_int($cout) && ! (is_string($cout) && ctype_digit($cout))) {
                        continue;
                    }

                    DB::table('mouvements_stock')
                        ->where('id', $ligne->entite_id)
                        ->where('type_mouvement', 'entree')
                        ->whereNull('cout_unitaire')
                        ->update(['cout_unitaire' => bcdiv((string) $cout, '10000', 4)]);
                }
            });
    }

    public function down(): void
    {
        if (Schema::hasColumn('mouvements_stock', 'cout_unitaire')) {
            Schema::table('mouvements_stock', function ($table): void {
                $table->dropColumn('cout_unitaire');
            });
        }
    }
};

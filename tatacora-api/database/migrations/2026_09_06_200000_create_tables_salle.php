<?php

declare(strict_types=1);

use Database\Migrations\Concerns\HasAuditColumns;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Le référentiel des TABLES DE SALLE — `tables-engine.js` du maître, porté au
 * schéma le 02/09/2026 (directive Product Owner, onglet « Espaces & tables »
 * de l'écran Paramètres).
 *
 * ## Ce que cette table remplace
 *
 * `PosComptant::PLAN_DE_SALLE` était un REGISTRE D'ÉCRAN : six tables codées
 * en dur, alors que le maître écrit « Les numéros ne sont PAS codés en dur —
 * demande explicite de l'atelier ». Sa propre documentation annonçait sa
 * disparition « le jour où une table `tables_service` existera (§4.3 de la
 * proposition) » : ce jour est arrivé, la constante est retirée et le POS lit
 * ce référentiel ({@see \App\Domain\Ventes\Services\TableSalleService}).
 *
 * ## Les ESPACES restent un registre fermé, PAS une table
 *
 * Restaurant, Jardin, Plage (avec tables) et Comptoir (sans table,
 * structurellement) — même raisonnement que `RegistreCanaux` : un espace
 * change la convention de nommage et l'organisation du service, ce n'est pas
 * une donnée d'écran. Le CHECK ci-dessous les ferme au niveau du moteur.
 *
 * ## `paniers.table_id` et `ventes.table_id` restent des CHAÎNES — motif daté
 *
 * Leurs migrations promettaient « cette colonne devient une vraie clé
 * étrangère » le jour venu. Elle ne l'est PAS encore, et la raison est
 * concrète : les bases déjà semées portent des paniers et des ventes dont le
 * `table_id` vient de l'ancien registre d'écran (`tab-r1`…) — poser la FK
 * ferait échouer la migration sur toute base d'exploitation existante, ou
 * forcerait une réécriture de lignes de VENTE (interdite, RG-03/RG-11 par
 * analogie). La conversion est un arbitrage à part entière (quoi faire des
 * identifiants historiques), ouvert à l'Architecte — pas un oubli.
 *
 * ## Jamais de suppression
 *
 * Une table se désactive (`actif`), elle ne disparaît pas : la supprimer
 * laisserait les ventes passées pointer un identifiant inexistant, et
 * l'analyse par table perdrait son historique — le maître l'écrit en toutes
 * lettres (`tables-engine.js`, `basculer()`).
 *
 * @see RG-02 aucune suppression — désactiver, jamais effacer
 * @see docs/PROPOSITION_MODELE_PANIER_POS.md §4.3
 */
return new class () extends Migration {
    use HasAuditColumns;

    private const CONTRAINTES = [
        'chk_tables_salle_espace' => "espace IN ('restaurant', 'jardin', 'plage')",
        'chk_tables_salle_numero' => 'numero >= 1',
        'chk_tables_salle_places' => 'places >= 1',
    ];

    public function up(): void
    {
        Schema::create('tables_salle', function (Blueprint $table): void {
            $table->uuid('id')->primary();

            $table->string('espace', 20);
            $table->unsignedSmallInteger('numero');
            // Le libellé SUIT le numéro (préfixe d'espace + numéro : R3, J1) —
            // il est réécrit par le service à chaque renumérotation, jamais
            // saisi : un libellé figé sur un numéro changé rendrait la salle
            // illisible (tables-engine.js, `modifier()`).
            $table->string('libelle', 10);
            $table->unsignedSmallInteger('places')->default(4);
            $table->boolean('actif')->default(true);

            $this->auditColumns($table);
            $table->timestamps();

            // La règle du maître : « La table R3 existe déjà. » Deux tables du
            // même numéro dans un espace — active ou non — sont refusées, et
            // l'unicité en base tient ce que le service vérifie.
            $table->unique(['espace', 'numero']);
        });

        foreach (self::CONTRAINTES as $nom => $condition) {
            DB::statement("ALTER TABLE tables_salle ADD CONSTRAINT {$nom} CHECK ({$condition})");
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('tables_salle');
    }
};
